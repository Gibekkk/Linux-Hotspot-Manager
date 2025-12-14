#!/bin/bash

# --- 1. STRICT ROOT CHECK ---
# Sesuai permintaan: Tidak ada auto-magic. Jika bukan root, tolak.
if [ "$EUID" -ne 0 ]; then
  echo "Error: Installer harus dijalankan sebagai root."
  echo "Silakan ketik: sudo bash install.sh"
  exit 1
fi

# --- KONFIGURASI PATH ---
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALL_DIR="/opt/linux-hotspot-manager"
BIN_PATH="/usr/bin/linux-hotspot-manager"
DESKTOP_SRC="$CURRENT_DIR/Hotspot.desktop"
LOG_FILE="/var/log/linux-hotspot-manager.log"
REPO_RAW_URL="https://raw.githubusercontent.com/Gibekkk/Linux-Hotspot-Manager/main"

# --- 2. BACA VERSI DARI FILE (Version Control Fix) ---
if [ -f "$CURRENT_DIR/version.txt" ]; then
    # tr -d menghapus spasi/newline agar bersih
    APP_VERSION=$(cat "$CURRENT_DIR/version.txt" | tr -d ' \n\r')
else
    echo "Warning: version.txt tidak ditemukan. Menggunakan default 1.0"
    APP_VERSION="1.0"
fi

echo "=== INSTALLER LINUX HOTSPOT MANAGER V$APP_VERSION ==="

# Cek Kelengkapan File Utama
if [[ ! -f "$CURRENT_DIR/hotspot_gui.py" || ! -f "$CURRENT_DIR/hotspot_ctrl.sh" ]]; then
    echo "Error: File hotspot_gui.py atau hotspot_ctrl.sh tidak ditemukan."
    exit 1
fi

# --- 3. INSTALL DEPENDENCIES DARI REQUIREMENTS.TXT ---
echo "[1/8] Menginstall dependencies..."

# Default dependencies jika file txt hilang
DEPS="python3-tk python3-pil.imagetk dnsmasq-base jq iw network-manager ufw policykit-1 curl qrencode"

if [ -f "$CURRENT_DIR/requirements.txt" ]; then
    echo "Membaca requirements.txt..."
    # Membaca file, mengabaikan baris kosong/komentar, mengganti newline dengan spasi
    FILE_DEPS=$(grep -vE "^\s*#" "$CURRENT_DIR/requirements.txt" | tr '\n' ' ')
    if [ ! -z "$FILE_DEPS" ]; then
        DEPS=$FILE_DEPS
    fi
fi

echo "Paket yang diinstall: $DEPS"
apt-get update -qq
apt-get install -y $DEPS

# Setup Direktori
echo "[2/8] Membuat direktori aplikasi..."
mkdir -p "$INSTALL_DIR"

# PENTING: Salin version.txt asli ke sistem
echo "$APP_VERSION" > "$INSTALL_DIR/version.txt"
# Salin requirements.txt juga (untuk referensi uninstall/update)
if [ -f "$CURRENT_DIR/requirements.txt" ]; then
    cp "$CURRENT_DIR/requirements.txt" "$INSTALL_DIR/"
fi

# --- 4. CONFIG WIZARD (Smart Input) ---
echo "[3/8] Konfigurasi Jaringan..."

# Cek config lama
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
    
    # Loop Main Interface
    while true; do
        read -p "Main Interface (Default: ${AUTO_MAIN:-kosong}): " INPUT_MAIN
        MAIN_IF=${INPUT_MAIN:-$AUTO_MAIN}
        
        if [ -n "$MAIN_IF" ]; then
            if ip link show "$MAIN_IF" >/dev/null 2>&1; then break; else echo "Error: Interface tidak valid."; fi
        else
            echo "Error: Wajib diisi."; 
        fi
    done

    # Loop Virtual Interface
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
        if [ ${#PASS_INPUT} -ge 8 ]; then break; else echo "Error: Min 8 karakter."; fi
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

# Config App Default
if [ ! -f "$INSTALL_DIR/app_config.json" ]; then
cat > "$INSTALL_DIR/app_config.json" <<EOF
{
    "limit": 5,
    "blacklist": [],
    "custom_names": {}
}
EOF
fi

# Copy Files
echo "[5/8] Menyalin file aplikasi..."
cp "$CURRENT_DIR/hotspot_gui.py" "$INSTALL_DIR/"
cp "$CURRENT_DIR/hotspot_ctrl.sh" "$INSTALL_DIR/"

# Icon
ICON_SRC=$(find "$CURRENT_DIR" -maxdepth 1 -name "icon.png" -o -name "icon.jpeg" -o -name "icon.jpg" | head -n 1)
if [ -n "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$INSTALL_DIR/app_icon.png"
fi

# Desktop Entry
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

# Permissions
chmod +x "$INSTALL_DIR/hotspot_ctrl.sh"
chown -R root:root "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# Log Init
touch "$LOG_FILE"
chmod 666 "$LOG_FILE"
echo "$(date) - Installed V$APP_VERSION" > "$LOG_FILE"

# --- 5. UNINSTALLER (TOTAL CLEANUP) ---
echo "[6/8] Membuat uninstaller..."
cat > "$INSTALL_DIR/uninstall.sh" <<EOF
#!/bin/bash

# Strict Root Check untuk Uninstaller
if [ "\$EUID" -ne 0 ]; then
    echo "Error: Uninstall butuh akses root."
    echo "Gunakan: sudo linux-hotspot-manager --uninstall"
    exit 1
fi

echo "Mempersiapkan uninstall..."

# Matikan Hotspot
if [ -f "$INSTALL_DIR/hotspot_ctrl.sh" ]; then
    bash "$INSTALL_DIR/hotspot_ctrl.sh" off > /dev/null 2>&1
    
    # Force cleanup interface
    VIRT_IF=\$(jq -r '.virt_interface' "$INSTALL_DIR/wifi_config.json" 2>/dev/null)
    if [ ! -z "\$VIRT_IF" ]; then
        ip link set \$VIRT_IF down 2>/dev/null
        iw dev \$VIRT_IF del 2>/dev/null
    fi
fi

echo "Menghapus file binary dan shortcut..."
rm -f "$BIN_PATH"
rm -f "/usr/share/applications/linux-hotspot-manager.desktop"
rm -f "$LOG_FILE"

echo "Menghapus direktori utama (Config, Version, Requirements, Script)..."
rm -rf "$INSTALL_DIR"

echo "Uninstall selesai. Sistem bersih."
EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

# --- 6. WRAPPER BINARY (STRICT SUDO & FIX UPDATE) ---
echo "[7/8] Membuat command '$BIN_PATH'..."
rm -f "$BIN_PATH"

cat > "$BIN_PATH" << 'EOF_WRAPPER'
#!/bin/bash

INSTALL_DIR="/opt/linux-hotspot-manager"
CONFIG_FILE="$INSTALL_DIR/wifi_config.json"
REPO_RAW="https://raw.githubusercontent.com/Gibekkk/Linux-Hotspot-Manager/main"
VERSION_FILE="$INSTALL_DIR/version.txt"
LOG_FILE="/var/log/linux-hotspot-manager.log"

# Fungsi Cek Root (STRICT)
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: Perintah ini membutuhkan akses root."
        echo "Silakan jalankan dengan 'sudo'."
        exit 1
    fi
}

get_local_version() {
    if [ -f "$VERSION_FILE" ]; then 
        # Baca file, hapus spasi/newline
        cat "$VERSION_FILE" | tr -d ' \n\r'
    else 
        echo "0.0"
    fi
}

check_update_available() {
    LOCAL_VER=$(get_local_version)
    # Timeout 3 detik agar tidak hang jika offline
    REMOTE_VER=$(curl -s --max-time 3 "$REPO_RAW/version.txt" | tr -d ' \n\r')
    
    if [[ ! -z "$REMOTE_VER" && "$REMOTE_VER" != "404:NotFound" ]]; then
        if [ "$LOCAL_VER" != "$REMOTE_VER" ]; then
            echo -e "\033[1;33m[UPDATE TERSEDIA]\033[0m Versi baru: $REMOTE_VER (Lokal: $LOCAL_VER)"
            echo "Jalankan: sudo linux-hotspot-manager --update"
        fi
    fi
}

# --- MAIN LOGIC ---

# 1. Jika tanpa argumen -> Buka GUI (User Biasa OK via pkexec)
if [ $# -eq 0 ]; then
    check_update_available
    if [ -z "$DISPLAY" ]; then
        echo "Error: GUI butuh X11/Wayland. Gunakan --help."
        exit 1
    fi
    pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY python3 "$INSTALL_DIR/hotspot_gui.py"
    exit 0
fi

# 2. Parsing Argumen CLI
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

    --log)
        # Tidak butuh root untuk baca log (read-only)
        if [ -f "$LOG_FILE" ]; then less +G "$LOG_FILE"; else echo "Log kosong."; fi
        ;;

    --status)
        # Tidak butuh root, hanya baca config
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
        # Logika Config
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
        check_root
        echo "Memeriksa update..."
        LOCAL_VER=$(get_local_version)
        REMOTE_VER=$(curl -s "$REPO_RAW/version.txt" | tr -d ' \n\r')
        
        if [[ -z "$REMOTE_VER" || "$REMOTE_VER" == *"404"* ]]; then
            echo "Error: Gagal mengambil versi dari GitHub."
            exit 1
        fi
        
        if [ "$LOCAL_VER" == "$REMOTE_VER" ]; then
            echo "Aplikasi sudah versi terbaru ($LOCAL_VER)."
            read -p "Paksa update ulang? (y/n): " FORCE
            if [[ "$FORCE" != "y" ]]; then exit 0; fi
        fi
        
        echo "Mengunduh update ($REMOTE_VER)..."
        
        # Cek status sebelum matikan
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
        
        # Download Files
        curl -s "$REPO_RAW/hotspot_ctrl.sh" -o "$INSTALL_DIR/hotspot_ctrl.sh"
        curl -s "$REPO_RAW/hotspot_gui.py" -o "$INSTALL_DIR/hotspot_gui.py"
        
        # PENTING: Update version.txt lokal
        echo "$REMOTE_VER" > "$VERSION_FILE"
        chmod +x "$INSTALL_DIR/hotspot_ctrl.sh"

        # Update Dependencies (jika requirements.txt ada di repo)
        REQ_URL="$REPO_RAW/requirements.txt"
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
        echo "Versi Lokal : $(get_local_version)"
        REMOTE_VER=$(curl -s --max-time 3 "$REPO_RAW/version.txt" | tr -d ' \n\r')
        echo "Versi Github: ${REMOTE_VER:-Gagal}"
        ;;

    --uninstall)
        check_root
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

# 8. Prompt Hapus Installer (Default Yes)
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
