#!/bin/bash

# --- KONFIGURASI ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WIFI_CONFIG="$SCRIPT_DIR/wifi_config.json"
LOG_FILE="/var/log/linux-hotspot-manager.log"

# Fungsi Logging dengan Timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [BACKEND] $1" >> "$LOG_FILE"
}

# Cek dependencies
if ! command -v jq &> /dev/null; then 
    log "Error: 'jq' missing."
    echo "Error: 'jq' missing."
    exit 1
fi

# Load Config
MAIN_IF=$(jq -r '.main_interface' "$WIFI_CONFIG")
VIRT_IF=$(jq -r '.virt_interface' "$WIFI_CONFIG")
SSID_NAME=$(jq -r '.ssid' "$WIFI_CONFIG")
WIFI_PASSWORD=$(jq -r '.password' "$WIFI_CONFIG")
NM_PROFILE_NAME=$(jq -r '.profile_name' "$WIFI_CONFIG")

function start_hotspot() {
    log "--- Memulai Hotspot ---"
    echo "Starting..."
    
    # Cek Interface Utama
    FREQ_INFO=$(iw dev $MAIN_IF info 2>&1)
    if [ $? -ne 0 ]; then
        log "Error: Gagal membaca info dari $MAIN_IF. Detail: $FREQ_INFO"
        echo "Error: Interface $MAIN_IF bermasalah."
        exit 1
    fi

    CURRENT_CHANNEL=$(echo "$FREQ_INFO" | grep channel | awk '{print $2}')
    CURRENT_FREQ=$(echo "$FREQ_INFO" | grep -oP '(?<=center1: ).*?(?= MHz)' | head -1)
    
    if [ -z "$CURRENT_CHANNEL" ]; then 
        log "Error: $MAIN_IF tidak terhubung ke jaringan Wi-Fi apapun."
        echo "Error: $MAIN_IF tidak terhubung."
        exit 1
    fi

    if [ "$CURRENT_FREQ" -gt 5000 ]; then 
        HW_MODE="a"
        log "Mode: 5GHz (Channel $CURRENT_CHANNEL)"
    else 
        HW_MODE="bg"
        log "Mode: 2.4GHz (Channel $CURRENT_CHANNEL)"
    fi

    # Bersihkan Interface Lama
    if ip link show $VIRT_IF > /dev/null 2>&1; then
        log "Membersihkan interface lama $VIRT_IF..."
        nmcli device disconnect $VIRT_IF > /dev/null 2>&1
        ip link set $VIRT_IF down
        iw dev $VIRT_IF del
        sleep 1
    fi
    
    # Buat Interface Baru
    log "Membuat virtual interface $VIRT_IF..."
    ADD_OUT=$(iw dev $MAIN_IF interface add $VIRT_IF type __ap 2>&1)
    if [ $? -ne 0 ]; then
        log "FATAL: Gagal membuat interface. $ADD_OUT"
        echo "FAIL: Driver Error"
        exit 1
    fi
    
    iw dev $MAIN_IF set power_save off > /dev/null 2>&1
    ip link set $VIRT_IF up
    sleep 1

    # Setup NetworkManager
    log "Mengkonfigurasi NetworkManager Profile..."
    nmcli connection delete "$NM_PROFILE_NAME" > /dev/null 2>&1
    
    nmcli con add type wifi ifname $VIRT_IF con-name "$NM_PROFILE_NAME" autoconnect yes ssid "$SSID_NAME" > /dev/null
    nmcli con modify "$NM_PROFILE_NAME" connection.interface-name $VIRT_IF
    nmcli con modify "$NM_PROFILE_NAME" 802-11-wireless.mode ap
    nmcli con modify "$NM_PROFILE_NAME" ipv4.method shared
    nmcli con modify "$NM_PROFILE_NAME" 802-11-wireless.band $HW_MODE
    nmcli con modify "$NM_PROFILE_NAME" 802-11-wireless.channel $CURRENT_CHANNEL
    nmcli con modify "$NM_PROFILE_NAME" wifi-sec.key-mgmt wpa-psk
    nmcli con modify "$NM_PROFILE_NAME" wifi-sec.psk "$WIFI_PASSWORD"
    nmcli con modify "$NM_PROFILE_NAME" wifi-sec.pmf disable
    nmcli con modify "$NM_PROFILE_NAME" wifi.cloned-mac-address random

    # Firewall
    if command -v ufw > /dev/null; then
        log "Setting Firewall Rules..."
        ufw allow in on $VIRT_IF > /dev/null 2>&1
        ufw route allow in on $VIRT_IF out on $MAIN_IF > /dev/null 2>&1
        ufw allow in on $VIRT_IF to any port 67 proto udp > /dev/null 2>&1
        ufw allow in on $VIRT_IF to any port 68 proto udp > /dev/null 2>&1
        ufw allow in on $VIRT_IF to any port 53 > /dev/null 2>&1
    fi

    # Nyalakan
    nmcli device set $VIRT_IF autoconnect no 2>/dev/null
    log "Mengaktifkan koneksi..."
    OUTPUT=$(nmcli connection up "$NM_PROFILE_NAME" 2>&1)
    
    if [ $? -eq 0 ]; then 
        log "Hotspot BERHASIL dinyalakan."
        echo "SUCCESS"
    else 
        log "GAGAL menyalakan hotspot. Output NM: $OUTPUT"
        echo "FAIL: $OUTPUT"
        iw dev $VIRT_IF del > /dev/null 2>&1
    fi
}

function stop_hotspot() {
    log "--- Mematikan Hotspot ---"
    echo "Stopping..."
    if command -v ufw > /dev/null; then
        ufw delete allow in on $VIRT_IF > /dev/null 2>&1
        ufw delete route allow in on $VIRT_IF out on $MAIN_IF > /dev/null 2>&1
    fi
    nmcli connection delete "$NM_PROFILE_NAME" > /dev/null 2>&1
    ip link set $VIRT_IF down > /dev/null 2>&1
    iw dev $VIRT_IF del > /dev/null 2>&1
    log "Hotspot dimatikan."
    echo "STOPPED"
}

function check_status() {
    if ip link show $VIRT_IF > /dev/null 2>&1; then
         if ip addr show $VIRT_IF | grep -q "inet"; then
             echo "ACTIVE"
             return
         fi
    fi
    echo "INACTIVE"
}

function list_clients() {
    if ip link show $VIRT_IF > /dev/null 2>&1; then
        iw dev $VIRT_IF station dump | grep Station | awk '{print $2}' | while read -r mac; do
            ip=$(arp -an -i $VIRT_IF | grep "$mac" | awk '{print $2}' | tr -d '()')
            if [ -z "$ip" ]; then ip="Connecting..."; fi
            hostname="Unknown"
            LEASE_FILE=$(find /var/lib/NetworkManager/ -name "*.leases" 2>/dev/null | head -n 1)
            if [ -f "$LEASE_FILE" ]; then
                name_found=$(grep "$mac" "$LEASE_FILE" | awk '{print $4}')
                if [ ! -z "$name_found" ] && [ "$name_found" != "*" ]; then hostname=$name_found; fi
            fi
            echo "$mac|$ip|$hostname"
        done
    else echo "INACTIVE"; fi
}

function kick_client() {
    if [ -z "$2" ]; then echo "Need MAC"; exit 1; fi
    log "Kicking client: $2"
    iw dev $VIRT_IF station del $2
    echo "KICKED $2"
}

case "$1" in
    on) start_hotspot ;;
    off) stop_hotspot ;;
    status) list_clients ;;
    check) check_status ;;
    kick) kick_client "$@" ;;
    *) echo "Usage: $0 {on|off|status|check|kick}" ;;
esac
