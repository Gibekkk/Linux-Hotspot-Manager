#!/bin/bash

# Pastikan dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "Mohon jalankan sebagai root: sudo bash install.sh"
  exit
fi

# --- KONFIGURASI UTAMA ---
APP_VERSION="1.3" # Versi Baru
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
    echo "Error: File instalasi tidak lengkap."
    exit 1
fi

# 2. Install Dependencies
echo "[1/8] Menginstall dependencies..."
apt-get update -qq
apt-get install -y python3-tk python3-pil.imagetk dnsmasq-base jq iw network-manager ufw policykit-1 curl qrencode

# 3. Setup Direktori Sistem
echo "[2/8] Membuat direktori aplikasi..."
mkdir -p "$INSTALL_DIR"
echo "$APP_VERSION" > "$INSTALL_DIR/version.txt"

# 4. Konfigurasi Interface Wi-Fi
echo "---------------------------------------"
echo "Daftar Interface Wi-Fi Anda:"
iw dev | awk '$1=="Interface"{print $2}'
echo "---------------------------------------"

read -p "Masukkan Interface UTAMA (sumber internet, misal wlp3s0): " MAIN_IF
read -p "Masukkan Interface VIRTUAL (untuk hotspot, misal wlp3s1): " VIRT_IF
read -p "Masukkan Nama Hotspot (SSID): " SSID_INPUT
read -p "Masukkan Password Hotspot (min 8 char): " PASS_INPUT

if [ -z "$SSID_INPUT" ]; then SSID_INPUT="Linux Hotspot"; fi
if [ -z "$PASS_INPUT" ]; then PASS_INPUT="12345678"; fi

echo "[3/8] Membuat konfigurasi..."
cat > "$INSTALL_DIR/wifi_config.json" <<EOF
{
    "main_interface": "$MAIN_IF",
    "virt_interface": "$VIRT_IF",
    "ssid": "$SSID_INPUT",
    "password": "$PASS_INPUT",
    "profile_name": "Hotspot-Manager-Profile"
}
EOF

cat > "$INSTALL_DIR/app_config.json" <<EOF
{
    "limit": 5,
    "blacklist": [],
    "custom_names": {}
}
EOF

# 5. Menyalin File Aplikasi
echo "[4/8] Menyalin file aplikasi..."
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
echo "[5/8] Membuat script uninstaller internal..."
cat > "$INSTALL_DIR/uninstall.sh" <<EOF
#!/bin/bash
echo "Mempersiapkan uninstall..."
if [ -f "$INSTALL_DIR/hotspot_ctrl.sh" ]; then
    bash "$INSTALL_DIR/hotspot_ctrl.sh" off > /dev/null 2>&1
    VIRT_IF=\$(jq -r '.virt_interface' "$INSTALL_DIR/wifi_config.json" 2>/dev/null)
    if [ ! -z "\$VIRT_IF" ]; then
        ip link set \$VIRT_IF down 2>/dev/null
        iw dev \$VIRT_IF del 2>/dev/null
    fi
fi
rm -f "$BIN_PATH"
rm -f "/usr/share/applications/linux-hotspot-manager.desktop"
rm -f "$LOG_FILE"
rm -rf "$INSTALL_DIR"
echo "Uninstall selesai."
EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

# 7. WRAPPER BINARY (CANGGIH)
echo "[6/8] Membuat command '$BIN_PATH'..."
cat > "$BIN_PATH" << 'EOF_WRAPPER'
#!/bin/bash

INSTALL_DIR="/opt/linux-hotspot-manager"
CONFIG_FILE="$INSTALL_DIR/wifi_config.json"
REPO_RAW="https://raw.githubusercontent.com/Gibekkk/Linux-Hotspot-Manager/main"
VERSION_FILE="$INSTALL_DIR/version.txt"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: Perintah ini membutuhkan akses root (sudo)."
        exit 1
    fi
}

get_local_version() {
    if [ -f "$VERSION_FILE" ]; then cat "$VERSION_FILE"; else echo "0.0"; fi
}

check_update_available() {
    LOCAL_VER=$(get_local_version)
    REMOTE_VER=$(curl -s --max-time 3 "$REPO_RAW/version.txt")
    if [[ ! -z "$REMOTE_VER" && "$REMOTE_VER" != "404: Not Found" ]]; then
        if [ "$LOCAL_VER" != "$REMOTE_VER" ]; then
            echo -e "\033[1;33m[UPDATE TERSEDIA]\033[0m Versi baru: $REMOTE_VER (Lokal: $LOCAL_VER)"
            echo "Jalankan: sudo linux-hotspot-manager --update"
        fi
    fi
}

# --- MAIN LOGIC ---

if [ -z "$1" ]; then
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
        check_root
        echo "Menyalakan hotspot..."
        bash "$INSTALL_DIR/hotspot_ctrl.sh" on
        ;;
        
    --off)
        check_root
        echo "Mematikan hotspot..."
        bash "$INSTALL_DIR/hotspot_ctrl.sh" off
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
        check_root
        echo "Merestart hotspot..."
        bash "$INSTALL_DIR/hotspot_ctrl.sh" off
        sleep 2
        bash "$INSTALL_DIR/hotspot_ctrl.sh" on
        ;;

    --config)
        check_root
        shift
        if [ -z "$1" ]; then
            echo "--- KONFIGURASI ULANG ---"
            iw dev | awk '$1=="Interface"{print $2}'
            read -p "Main Interface: " MAIN_IF
            read -p "Virtual Interface: " VIRT_IF
            read -p "SSID: " SSID
            read -p "Password: " PASS
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
        check_root
        echo "Memeriksa update..."
        LOCAL_VER=$(get_local_version)
        REMOTE_VER=$(curl -s "$REPO_RAW/version.txt")
        
        if [[ -z "$REMOTE_VER" || "$REMOTE_VER" == "404: Not Found" ]]; then
            echo "Error: Gagal cek versi."
            exit 1
        fi
        
        if [ "$LOCAL_VER" == "$REMOTE_VER" ]; then
            echo "Sudah versi terbaru ($LOCAL_VER)."
            read -p "Paksa update? (y/n): " FORCE
            if [[ "$FORCE" != "y" ]]; then exit 0; fi
        fi
        
        echo "Mengunduh update ($REMOTE_VER)..."
        
        # Cek status sebelum matikan
        IS_ACTIVE="no"
        if ip link show $(jq -r '.virt_interface' "$CONFIG_FILE") >/dev/null 2>&1; then
             if ip addr show $(jq -r '.virt_interface' "$CONFIG_FILE") | grep -q "inet"; then
                 IS_ACTIVE="yes"
             fi
        fi
        
        if [ "$IS_ACTIVE" == "yes" ]; then
            echo "Mematikan hotspot..."
            bash "$INSTALL_DIR/hotspot_ctrl.sh" off
        fi
        
        # Download Core Files
        curl -s "$REPO_RAW/hotspot_ctrl.sh" -o "$INSTALL_DIR/hotspot_ctrl.sh"
        curl -s "$REPO_RAW/hotspot_gui.py" -o "$INSTALL_DIR/hotspot_gui.py"
        echo "$REMOTE_VER" > "$VERSION_FILE"
        chmod +x "$INSTALL_DIR/hotspot_ctrl.sh"

        # Update Dependencies
        echo "Mengupdate dependencies..."
        apt-get update -qq
        apt-get install -y python3-tk python3-pil.imagetk dnsmasq-base jq iw network-manager ufw policykit-1 curl qrencode
        
        echo "Update selesai!"
        
        if [ "$IS_ACTIVE" == "yes" ]; then
            echo "Menyalakan kembali hotspot..."
            bash "$INSTALL_DIR/hotspot_ctrl.sh" on
        fi
        ;;

    --version)
        echo "Linux Hotspot Manager"
        echo "Versi Lokal : $(get_local_version)"
        REMOTE_VER=$(curl -s --max-time 3 "$REPO_RAW/version.txt")
        echo "Versi Github: ${REMOTE_VER:-Gagal}"
        ;;

    --uninstall)
        check_root
        bash "$INSTALL_DIR/uninstall.sh"
        ;;

    --help)
        echo "Linux Hotspot Manager CLI"
        echo "  --on                 Nyalakan hotspot"
        echo "  --off                Matikan hotspot"
        echo "  --status             Cek status, SSID, Pass"
        echo "  --restart            Restart hotspot"
        echo "  --config             Setup ulang"
        echo "  --config key=val...  Ubah config (ssid, password)"
        echo "  --update             Update aplikasi & dependencies"
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
echo "Coba jalankan: sudo linux-hotspot-manager --status"
echo ""

# 8. Prompt Hapus Installer
echo "[8/8] Pembersihan"
read -p "Hapus file installer ini? (y/n): " confirm
if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    rm -rf "$CURRENT_DIR"
    echo "File installer dihapus."
fi

exit 0
