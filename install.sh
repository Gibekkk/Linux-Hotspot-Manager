#!/bin/bash

# Pastikan dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "Mohon jalankan sebagai root: sudo bash install.sh"
  exit
fi

# --- KONFIGURASI PATH ---
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALL_DIR="/opt/linux-hotspot-manager"
BIN_PATH="/usr/bin/linux-hotspot-manager"
DESKTOP_SRC="$CURRENT_DIR/Hotspot.desktop"
LOG_FILE="/var/log/linux-hotspot-manager.log"
APP_VERSION="1.0" # Versi saat ini
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
apt-get install -y python3-tk dnsmasq-base jq iw network-manager ufw policykit-1 curl

# 3. Setup Direktori Sistem
echo "[2/8] Membuat direktori aplikasi..."
mkdir -p "$INSTALL_DIR"

# Simpan Versi Lokal
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

# Handling Icon
if [ -n "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$INSTALL_DIR/app_icon.png"
fi

# Handling Desktop Entry
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

# Set Permissions
chmod +x "$INSTALL_DIR/hotspot_ctrl.sh"
chown -R root:root "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# Setup Log File
touch "$LOG_FILE"
chmod 666 "$LOG_FILE"
echo "$(date) - Installed V$APP_VERSION" > "$LOG_FILE"

# 6. Membuat Script Uninstaller Internal
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

# 7. MEMBUAT WRAPPER BINARY CANGGIH
echo "[6/8] Membuat command '$BIN_PATH'..."
cat > "$BIN_PATH" << 'EOF_WRAPPER'
#!/bin/bash

# --- CONFIG ---
INSTALL_DIR="/opt/linux-hotspot-manager"
CONFIG_FILE="$INSTALL_DIR/wifi_config.json"
REPO_RAW="https://raw.githubusercontent.com/Gibekkk/Linux-Hotspot-Manager/main"
VERSION_FILE="$INSTALL_DIR/version.txt"

# --- HELPER FUNCTIONS ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: Perintah ini membutuhkan akses root."
        echo "Silakan jalankan dengan: sudo linux-hotspot-manager $1 ..."
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

# Jika dijalankan tanpa argumen, buka GUI (pakai pkexec)
if [ -z "$1" ]; then
    check_update_available
    if [ -z "$DISPLAY" ]; then
        echo "Error: GUI butuh X11/Wayland. Gunakan --help untuk mode terminal."
        exit 1
    fi
    pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY python3 "$INSTALL_DIR/hotspot_gui.py"
    exit 0
fi

# Parsing Argumen CLI
case "$1" in
    --on)
        check_root "--on"
        echo "Menyalakan hotspot..."
        bash "$INSTALL_DIR/hotspot_ctrl.sh" on
        ;;
        
    --off)
        check_root "--off"
        echo "Mematikan hotspot..."
        bash "$INSTALL_DIR/hotspot_ctrl.sh" off
        ;;
        
    --restart)
        check_root "--restart"
        echo "Merestart hotspot..."
        bash "$INSTALL_DIR/hotspot_ctrl.sh" off
        sleep 2
        bash "$INSTALL_DIR/hotspot_ctrl.sh" on
        ;;

    --config)
        check_root "--config"
        shift # Hapus --config dari argumen
        
        if [ -z "$1" ]; then
            # Mode Interaktif (Tanya Ulang Semua)
            echo "--- KONFIGURASI ULANG ---"
            echo "Interface saat ini:"
            iw dev | awk '$1=="Interface"{print $2}'
            echo "-------------------------"
            
            read -p "Main Interface (Internet): " MAIN_IF
            read -p "Virtual Interface (Hotspot): " VIRT_IF
            read -p "SSID: " SSID
            read -p "Password: " PASS
            
            # Update JSON
            tmp=$(mktemp)
            jq --arg m "$MAIN_IF" --arg v "$VIRT_IF" --arg s "$SSID" --arg p "$PASS" \
               '.main_interface=$m | .virt_interface=$v | .ssid=$s | .password=$p' \
               "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
               
            echo "Konfigurasi disimpan. Jalankan --restart untuk menerapkan."
        else
            # Mode Inline (key=value)
            while [ ! -z "$1" ]; do
                KEY=$(echo "$1" | cut -d'=' -f1)
                VAL=$(echo "$1" | cut -d'=' -f2-)
                
                if [[ "$KEY" =~ ^(ssid|password|main_interface|virt_interface)$ ]]; then
                    tmp=$(mktemp)
                    jq --arg v "$VAL" ".$KEY=\$v" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                    echo "Updated: $KEY -> $VAL"
                else
                    echo "Warning: Config '$KEY' tidak valid. Diabaikan."
                fi
                shift
            done
            echo "Konfigurasi disimpan. Jangan lupa --restart."
        fi
        ;;

    --update)
        check_root "--update"
        echo "Memeriksa update..."
        LOCAL_VER=$(get_local_version)
        REMOTE_VER=$(curl -s "$REPO_RAW/version.txt")
        
        if [[ -z "$REMOTE_VER" || "$REMOTE_VER" == "404: Not Found" ]]; then
            echo "Error: Gagal cek versi ke GitHub."
            exit 1
        fi
        
        if [ "$LOCAL_VER" == "$REMOTE_VER" ]; then
            echo "Aplikasi sudah versi terbaru ($LOCAL_VER)."
            read -p "Paksa update ulang? (y/n): " FORCE
            if [[ "$FORCE" != "y" ]]; then exit 0; fi
        fi
        
        echo "Mengunduh update ($REMOTE_VER)..."
        
        # Cek status hotspot
        IS_ACTIVE="no"
        if ip link show $(jq -r '.virt_interface' "$CONFIG_FILE") >/dev/null 2>&1; then
             if ip addr show $(jq -r '.virt_interface' "$CONFIG_FILE") | grep -q "inet"; then
                 IS_ACTIVE="yes"
             fi
        fi
        
        if [ "$IS_ACTIVE" == "yes" ]; then
            echo "Mematikan hotspot untuk update..."
            bash "$INSTALL_DIR/hotspot_ctrl.sh" off
        fi
        
        # Download Files
        curl -s "$REPO_RAW/hotspot_ctrl.sh" -o "$INSTALL_DIR/hotspot_ctrl.sh"
        curl -s "$REPO_RAW/hotspot_gui.py" -o "$INSTALL_DIR/hotspot_gui.py"
        echo "$REMOTE_VER" > "$VERSION_FILE"
        
        chmod +x "$INSTALL_DIR/hotspot_ctrl.sh"
        
        echo "Update selesai!"
        
        if [ "$IS_ACTIVE" == "yes" ]; then
            echo "Menyalakan kembali hotspot..."
            bash "$INSTALL_DIR/hotspot_ctrl.sh" on
        fi
        ;;

    --version)
        echo "Linux Hotspot Manager"
        echo "Versi Lokal : $(get_local_version)"
        echo "Cek Online..."
        REMOTE_VER=$(curl -s --max-time 3 "$REPO_RAW/version.txt")
        if [[ ! -z "$REMOTE_VER" ]]; then
            echo "Versi Github: $REMOTE_VER"
        else
            echo "Versi Github: Gagal terhubung."
        fi
        ;;

    --uninstall)
        check_root "--uninstall"
        bash "$INSTALL_DIR/uninstall.sh"
        ;;

    --help)
        echo "Linux Hotspot Manager CLI"
        echo "Usage: linux-hotspot-manager [OPTION]"
        echo ""
        echo "  (tanpa argumen)      Buka GUI"
        echo "  --on                 Nyalakan hotspot"
        echo "  --off                Matikan hotspot"
        echo "  --restart            Restart hotspot (terapkan config baru)"
        echo "  --config             Wizard konfigurasi ulang (Interaktif)"
        echo "  --config key=val...  Ubah config spesifik (ssid, password, dll)"
        echo "                       Contoh: sudo linux-hotspot-manager --config ssid=\"Nama\" password=\"123\""
        echo "  --update             Update aplikasi dari GitHub"
        echo "  --version            Cek versi"
        echo "  --uninstall          Hapus aplikasi"
        echo "  --help               Tampilkan pesan ini"
        ;;

    *)
        echo "Perintah tidak dikenal: $1"
        echo "Gunakan --help untuk bantuan."
        exit 1
        ;;
esac
EOF_WRAPPER

chmod +x "$BIN_PATH"

echo ""
echo "=== INSTALASI SUKSES ==="
echo "Perintah CLI tersedia (Gunakan sudo):"
echo "  linux-hotspot-manager --config ssid=\"Baru\""
echo "  linux-hotspot-manager --restart"
echo "  linux-hotspot-manager --update"
echo "  linux-hotspot-manager --help"
echo ""

# 8. Prompt Hapus Installer
echo "[8/8] Pembersihan"
read -p "Apakah Anda ingin menghapus file installer ini? (y/n): " confirm
if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    rm -rf "$CURRENT_DIR"
    echo "File installer dihapus."
fi

exit 0
