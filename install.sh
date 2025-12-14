#!/bin/bash

# --- 1. STRICT ROOT CHECK (Tanpa Auto-Sudo) ---
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Script ini WAJIB dijalankan sebagai root."
  echo "Silakan jalankan ulang dengan: sudo bash install.sh"
  exit 1
fi

# --- KONFIGURASI UTAMA ---
APP_VERSION="1.24" # Versi Installer Ini
# -------------------------

# --- KONFIGURASI PATH ---
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALL_DIR="/opt/linux-hotspot-manager"
BIN_PATH="/usr/bin/linux-hotspot-manager"
DESKTOP_SRC="$CURRENT_DIR/Hotspot.desktop"
LOG_FILE="/var/log/linux-hotspot-manager.log"
REPO_RAW_URL="https://raw.githubusercontent.com/Gibekkk/Linux-Hotspot-Manager/main"

# Deteksi Icon
ICON_SRC=$(find "$CURRENT_DIR" -maxdepth 1 -name "icon.png" -o -name "icon.jpeg" -o -name "icon.jpg" | head -n 1)

echo "=== INSTALLER LINUX HOTSPOT MANAGER V$APP_VERSION ==="

# 1. Cek Kelengkapan File Sumber
if [[ ! -f "$CURRENT_DIR/hotspot_gui.py" || ! -f "$CURRENT_DIR/hotspot_ctrl.sh" ]]; then
    echo "Error: File instalasi tidak lengkap (hotspot_gui.py atau hotspot_ctrl.sh hilang)."
    exit 1
fi

# 2. Install Dependencies
echo "[1/8] Menginstall dependencies..."
apt-get update -qq
apt-get install -y python3-tk python3-pil.imagetk dnsmasq-base jq iw network-manager ufw policykit-1 curl qrencode

# 3. Setup Direktori Sistem
echo "[2/8] Membuat direktori aplikasi..."
mkdir -p "$INSTALL_DIR"

# PENTING: Paksa tulis versi 1.24 ke file lokal
echo "$APP_VERSION" > "$INSTALL_DIR/version.txt"

# 4. Konfigurasi Interface Wi-Fi
echo "[3/8] Konfigurasi Jaringan..."

if [ -f "$INSTALL_DIR/wifi_config.json" ]; then
    read -p "Config lama ditemukan. Gunakan kembali? (Y/n): " USE_OLD
    USE_OLD=${USE_OLD:-Y}
fi

if [[ "$USE_OLD" == [yY]* && -f "$INSTALL_DIR/wifi_config.json" ]]; then
    echo "Menggunakan konfigurasi lama."
else
    echo "---------------------------------------"
    iw dev | awk '$1=="Interface"{print $2}'
    echo "---------------------------------------"

    AUTO_MAIN=$(ip route | grep default | awk '{print $5}' | head -n1)
    while true; do
        read -p "Main Interface (Default: ${AUTO_MAIN:-kosong}): " INPUT_MAIN
        MAIN_IF=${INPUT_MAIN:-$AUTO_MAIN}
        
        if [ -n "$MAIN_IF" ]; then
            if ip link show "$MAIN_IF" >/dev/null 2>&1; then break; else echo "Error: Interface tidak ditemukan."; fi
        else
            echo "Error: Interface wajib diisi."; 
        fi
    done

    while true; do
        read -p "Virtual Interface (Default: wlan_ap): " INPUT_VIRT
        VIRT_IF=${INPUT_VIRT:-"wlan_ap"}
        if [ "$VIRT_IF" != "$MAIN_IF" ]; then break; else echo "Error: Tidak boleh sama dengan Main Interface."; fi
    done

    read -p "SSID (Default: Linux Hotspot): " INPUT_SSID
    SSID_INPUT=${INPUT_SSID:-"Linux Hotspot"}

    while true; do
        read -p "Password (Default: 12345678): " INPUT_PASS
        PASS_INPUT=${INPUT_PASS:-"12345678"}
        if [ ${#PASS_INPUT} -ge 8 ]; then break; else echo "Error: Minimal 8 karakter."; fi
    done

    echo "[4/8] Menyimpan konfigurasi..."
    cat > "$INSTALL_DIR/wifi_config.json" <<EOF
{
    "main_interface": "$MAIN_IF",
    "virt_interface": "$VIRT_IF",
    "ssid": "$SSID_INPUT",
    "password": "$PASS_INPUT",
    "profile_name": "Hotspot-Manager-Profile"
}
EOF
fi

if [ ! -f "$INSTALL_DIR/app_config.json" ]; then
cat > "$INSTALL_DIR/app_config.json" <<EOF
{
    "limit": 5,
    "blacklist": [],
    "custom_names": {}
}
EOF
fi

# 5. Menyalin File Aplikasi
echo "[5/8] Menyalin file aplikasi..."
cp "$CURRENT_DIR/hotspot_gui.py" "$INSTALL_DIR/"
cp "$CURRENT_DIR/hotspot_ctrl.sh" "$INSTALL_DIR/"

if [ -n "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$INSTALL_DIR/app_icon.png"
fi

if [ -f "$DESKTOP_SRC" ]; then
    TARGET_DESKTOP="/usr/share/applications/linux-hotspot-manager.desktop"
    cp "$DESKTOP_SRC" "$TARGET_DESKTOP"
    sed -i "s|^Exec=.*|Exec=$BIN_PATH|" "$TARGET_DESKTOP"
    if [ -n "$ICON_SRC" ]; then
        sed -i "s|^Icon=.*|Icon=$INSTALL_DIR/app_icon.png|" "$TARGET_DESKTOP"
    else
        sed -i "s|^Icon=.*|Icon=network-wireless-hotspot|" "$TARGET_DESKTOP"
    fi
    chmod 644 "$TARGET_DESKTOP"
fi

chmod +x "$INSTALL_DIR/hotspot_ctrl.sh"
chown -R root:root "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

touch "$LOG_FILE"
chmod 666 "$LOG_FILE"
echo "$(date) - Installed V$APP_VERSION" > "$LOG_FILE"

# 6. Script Uninstaller
echo "[6/8] Membuat uninstaller..."
cat > "$INSTALL_DIR/uninstall.sh" <<EOF
#!/bin/bash
if [ "\$EUID" -ne 0 ]; then
    echo "ERROR: Uninstall butuh akses root (sudo)."
    exit 1
fi

echo "Mempersiapkan uninstall..."
if [ -f "$INSTALL_DIR/hotspot_ctrl.sh" ]; then
    bash "$INSTALL_DIR/hotspot_ctrl.sh" off > /dev/null 2>&1
    VIRT_IF=\$(jq -r '.virt_interface' "$INSTALL_DIR/wifi_config.json" 2>/dev/null)
    if [ ! -z "\$VIRT_IF" ]; then
        ip link set \$VIRT_IF down 2>/dev/null
        iw dev \$VIRT_IF del 2>/dev/null
    fi
fi

echo "Menghapus file sistem..."
rm -f "$BIN_PATH"
rm -f "/usr/share/applications/linux-hotspot-manager.desktop"
rm -f "$LOG_FILE"
rm -rf "$INSTALL_DIR"
echo "Uninstall selesai. Sistem bersih."
EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

# 7. WRAPPER BINARY (ANTI-CACHE & STRICT SUDO)
echo "[7/8] Membuat command '$BIN_PATH'..."
rm -f "$BIN_PATH"

cat > "$BIN_PATH" << 'EOF_WRAPPER'
#!/bin/bash

INSTALL_DIR="/opt/linux-hotspot-manager"
CONFIG_FILE="$INSTALL_DIR/wifi_config.json"
REPO_RAW="https://raw.githubusercontent.com/Gibekkk/Linux-Hotspot-Manager/main"
VERSION_FILE="$INSTALL_DIR/version.txt"
LOG_FILE="/var/log/linux-hotspot-manager.log"

# --- HELPER FUNCTIONS ---

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Perintah ini membutuhkan akses root."
        echo "Silakan jalankan dengan: sudo linux-hotspot-manager $1 ..."
        exit 1
    fi
}

get_local_version() {
    if [ -f "$VERSION_FILE" ]; then 
        cat "$VERSION_FILE" | tr -d ' \n\r'
    else 
        echo "0.0"
    fi
}

get_remote_version() {
    # Anti-Cache: Tambahkan parameter waktu (?t=timestamp)
    # Ini memaksa GitHub memberikan file terbaru, bukan cache
    curl -s --max-time 5 "${REPO_RAW}/version.txt?t=$(date +%s)" | tr -d ' \n\r'
}

check_update_available() {
    LOCAL_VER=$(get_local_version)
    REMOTE_VER=$(get_remote_version)
    
    if [ -z "$REMOTE_VER" ] || [[ "$REMOTE_VER" == *"404"* ]]; then
        return # Silent fail
    fi
    
    if [ "$LOCAL_VER" != "$REMOTE_VER" ]; then
        # Cek jika lokal lebih tinggi (Dev version)
        if [[ "$LOCAL_VER" > "$REMOTE_VER" ]]; then
             return
        fi
        echo -e "\033[1;33m[UPDATE TERSEDIA]\033[0m Versi GitHub: $REMOTE_VER (Lokal: $LOCAL_VER)"
        echo "Jalankan: sudo linux-hotspot-manager --update"
    fi
}

# --- MAIN LOGIC ---

if [ $# -eq 0 ]; then
    check_update_available
    if [ -z "$DISPLAY" ]; then
        echo "Error: GUI butuh X11/Wayland. Gunakan --help."
        exit 1
    fi
    pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY python3 "$INSTALL_DIR/hotspot_gui.py"
    exit 0
fi

case "$1" in
    --on)
        require_root
        echo "Menyalakan hotspot..."
        bash "$INSTALL_DIR/hotspot_ctrl.sh" on
        ;;
        
    --off)
        require_root
        echo "Mematikan hotspot..."
        bash "$INSTALL_DIR/hotspot_ctrl.sh" off
        ;;

    --log)
        if [ -f "$LOG_FILE" ]; then less +G "$LOG_FILE"; else echo "Log kosong."; fi
        ;;

    --status)
        if [ ! -f "$CONFIG_FILE" ]; then echo "Config tidak ditemukan."; exit 1; fi
        STATUS=$(bash "$INSTALL_DIR/hotspot_ctrl.sh" check)
        SSID=$(jq -r '.ssid' "$CONFIG_FILE")
        PASS=$(jq -r '.password' "$CONFIG_FILE")
        echo "--------------------------"
        echo "Status : $STATUS"
        echo "SSID   : $SSID"
        echo "Pass   : $PASS"
        echo "--------------------------"
        ;;
        
    --restart)
        require_root
        echo "Merestart hotspot..."
        bash "$INSTALL_DIR/hotspot_ctrl.sh" off
        sleep 2
        bash "$INSTALL_DIR/hotspot_ctrl.sh" on
        ;;

    --config)
        require_root
        shift
        if [ -z "$1" ]; then
            echo "--- KONFIGURASI ULANG ---"
            iw dev | awk '$1=="Interface"{print $2}'
            
            AUTO_MAIN=$(ip route | grep default | awk '{print $5}' | head -n1)
            read -p "Main Interface ($AUTO_MAIN): " MAIN_IF
            MAIN_IF=${MAIN_IF:-$AUTO_MAIN}
            
            read -p "Virtual Interface (wlan_ap): " VIRT_IF
            VIRT_IF=${VIRT_IF:-"wlan_ap"}
            
            read -p "SSID (Linux Hotspot): " SSID
            SSID=${SSID:-"Linux Hotspot"}
            
            read -p "Password (12345678): " PASS
            PASS=${PASS:-"12345678"}
            
            tmp=$(mktemp)
            jq --arg m "$MAIN_IF" --arg v "$VIRT_IF" --arg s "$SSID" --arg p "$PASS" \
               '.main_interface=$m | .virt_interface=$v | .ssid=$s | .password=$p' \
               "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
            echo "Tersimpan. Jalankan --restart."
        else
            while [ ! -z "$1" ]; do
                KEY=$(echo "$1" | cut -d'=' -f1)
                VAL=$(echo "$1" | cut -d'=' -f2-)
                if [[ "$KEY" =~ ^(ssid|password|main_interface|virt_interface)$ ]]; then
                    tmp=$(mktemp)
                    jq --arg v "$VAL" ".$KEY=\$v" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                    echo "Updated: $KEY -> $VAL"
                fi
                shift
            done
            echo "Tersimpan. Jalankan --restart."
        fi
        ;;

    --update)
        require_root
        echo "Memeriksa update..."
        LOCAL_VER=$(get_local_version)
        REMOTE_VER=$(get_remote_version)
        
        if [ -z "$REMOTE_VER" ] || [[ "$REMOTE_VER" == *"404"* ]]; then
            echo "Error: Gagal terhubung ke GitHub."
            exit 1
        fi
        
        if [ "$LOCAL_VER" == "$REMOTE_VER" ]; then
            echo "Aplikasi sudah versi terbaru ($LOCAL_VER)."
            read -p "Paksa update ulang? (y/n): " FORCE
            if [[ "$FORCE" != "y" ]]; then exit 0; fi
        fi

        if [[ "$LOCAL_VER" > "$REMOTE_VER" ]]; then
            echo "Versi lokal ($LOCAL_VER) lebih baru dari GitHub ($REMOTE_VER)."
            read -p "Downgrade ke versi GitHub? (y/n): " FORCE
            if [[ "$FORCE" != "y" ]]; then exit 0; fi
        fi
        
        echo "Mengunduh update ($REMOTE_VER)..."
        
        IS_ACTIVE="no"
        if ip link show $(jq -r '.virt_interface' "$CONFIG_FILE" 2>/dev/null) >/dev/null 2>&1; then
             if ip addr show $(jq -r '.virt_interface' "$CONFIG_FILE" 2>/dev/null) | grep -q "inet"; then
                 IS_ACTIVE="yes"
             fi
        fi
        
        if [ "$IS_ACTIVE" == "yes" ]; then
            echo "Mematikan hotspot sementara..."
            bash "$INSTALL_DIR/hotspot_ctrl.sh" off
        fi
        
        # Download Core Files (Anti-Cache)
        curl -s "${REPO_RAW}/hotspot_ctrl.sh?t=$(date +%s)" -o "$INSTALL_DIR/hotspot_ctrl.sh"
        curl -s "${REPO_RAW}/hotspot_gui.py?t=$(date +%s)" -o "$INSTALL_DIR/hotspot_gui.py"
        
        # UPDATE VERSION FILE LOKAL (PENTING)
        echo "$REMOTE_VER" > "$VERSION_FILE"
        
        chmod +x "$INSTALL_DIR/hotspot_ctrl.sh"

        REQ_URL="${REPO_RAW}/requirements.txt?t=$(date +%s)"
        if curl --output /dev/null --silent --head --fail "$REQ_URL"; then
            echo "Mengupdate dependencies..."
            DEPS=$(curl -s "$REQ_URL" | grep -vE "^\s*#" | tr '\n' ' ')
            if [ ! -z "$DEPS" ]; then
                apt-get update -qq
                apt-get install -y $DEPS
            fi
        fi
        
        echo "Update selesai! Versi sekarang: $REMOTE_VER"
        
        if [ "$IS_ACTIVE" == "yes" ]; then
            echo "Menyalakan kembali hotspot..."
            bash "$INSTALL_DIR/hotspot_ctrl.sh" on
        fi
        ;;

    --version)
        echo "Linux Hotspot Manager"
        LOCAL=$(get_local_version)
        echo "Versi Lokal : $LOCAL"
        
        REMOTE=$(get_remote_version)
        if [ -z "$REMOTE" ]; then
            echo "Versi Github: (Gagal terhubung)"
        else
            echo "Versi Github: $REMOTE"
        fi
        ;;

    --uninstall)
        require_root
        bash "$INSTALL_DIR/uninstall.sh"
        ;;

    --help)
        echo "Linux Hotspot Manager CLI"
        echo "  --on                 Nyalakan"
        echo "  --off                Matikan"
        echo "  --status             Cek status"
        echo "  --restart            Restart"
        echo "  --config             Setup ulang"
        echo "  --update             Update aplikasi"
        echo "  --version            Cek versi"
        echo "  --uninstall          Hapus aplikasi"
        ;;

    *)
        echo "Perintah salah. Gunakan --help."
        exit 1
        ;;
esac
EOF_WRAPPER

chmod +x "$BIN_PATH"

echo ""
echo "=== INSTALASI SUKSES ==="
echo "Jalankan linux-hotspot-manager --help untuk informasi lebih lanjut."
echo ""

# 8. Prompt Hapus Installer
echo "[8/8] Pembersihan"
read -p "Hapus file installer ini? (Y/n): " confirm
confirm=${confirm:-Y} 

if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    rm -rf "$CURRENT_DIR"
    echo "File installer dihapus."
else
    echo "File installer disimpan."
fi

exit 0
