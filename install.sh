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

# Deteksi Icon
ICON_SRC=$(find "$CURRENT_DIR" -maxdepth 1 -name "icon.png" -o -name "icon.jpeg" -o -name "icon.jpg" | head -n 1)

echo "=== INSTALLER LINUX HOTSPOT MANAGER ==="

# 1. Cek Kelengkapan File Sumber
if [[ ! -f "$CURRENT_DIR/hotspot_gui.py" || ! -f "$CURRENT_DIR/hotspot_ctrl.sh" ]]; then
    echo "Error: File instalasi tidak lengkap."
    exit 1
fi

# 2. Install Dependencies
echo "[1/7] Menginstall dependencies..."
apt-get update -qq
apt-get install -y python3-tk dnsmasq-base jq iw network-manager ufw policykit-1

# 3. Setup Direktori Sistem
echo "[2/7] Membuat direktori aplikasi..."
mkdir -p "$INSTALL_DIR"

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

echo "[3/7] Membuat konfigurasi..."
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
echo "[4/7] Menyalin file aplikasi..."
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

# Setup Log File (Create empty file)
touch "$LOG_FILE"
chmod 666 "$LOG_FILE" # Allow write
echo "$(date) - Installed" > "$LOG_FILE"

# 6. Membuat Script Uninstaller Internal
echo "[5/7] Membuat script uninstaller internal..."
cat > "$INSTALL_DIR/uninstall.sh" <<EOF
#!/bin/bash
# Internal Uninstaller Script

echo "Mempersiapkan uninstall..."

if [ -f "$INSTALL_DIR/hotspot_ctrl.sh" ]; then
    echo "Mematikan hotspot..."
    bash "$INSTALL_DIR/hotspot_ctrl.sh" off > /dev/null 2>&1
    VIRT_IF=\$(jq -r '.virt_interface' "$INSTALL_DIR/wifi_config.json" 2>/dev/null)
    if [ ! -z "\$VIRT_IF" ]; then
        ip link set \$VIRT_IF down 2>/dev/null
        iw dev \$VIRT_IF del 2>/dev/null
    fi
    sleep 2
fi

echo "Menghapus file aplikasi..."
rm -f "$BIN_PATH"
rm -f "/usr/share/applications/linux-hotspot-manager.desktop"
rm -f "$LOG_FILE"
rm -rf "$INSTALL_DIR"

echo "Uninstall selesai."
EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

# 7. Membuat Wrapper Binary
echo "[6/7] Membuat command '$BIN_PATH'..."
cat > "$BIN_PATH" <<EOF
#!/bin/bash
INSTALL_DIR="$INSTALL_DIR"
case "\$1" in
  --uninstall) pkexec "\$INSTALL_DIR/uninstall.sh" ;;
  --on) echo "Menyalakan hotspot..."; pkexec "\$INSTALL_DIR/hotspot_ctrl.sh" on ;;
  --off) echo "Mematikan hotspot..."; pkexec "\$INSTALL_DIR/hotspot_ctrl.sh" off ;;
  *)
    if [ -z "\$DISPLAY" ]; then
        echo "Error: GUI membutuhkan X11/Wayland."
        exit 1
    fi
    pkexec env DISPLAY=\$DISPLAY XAUTHORITY=\$XAUTHORITY python3 "\$INSTALL_DIR/hotspot_gui.py"
    ;;
esac
EOF
chmod +x "$BIN_PATH"

echo ""
echo "=== INSTALASI SUKSES ==="
echo "Log file tersedia di: $LOG_FILE"
echo ""

# 8. Prompt Hapus Installer
echo "[7/7] Pembersihan"
read -p "Apakah Anda ingin menghapus file installer ini? (y/n): " confirm
if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    rm -rf "$CURRENT_DIR"
    echo "File installer dihapus."
fi

exit 0
