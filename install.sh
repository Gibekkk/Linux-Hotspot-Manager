#!/bin/bash

# Pastikan dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "Mohon jalankan sebagai root: sudo bash install.sh"
  exit
fi

# --- KONFIGURASI PATH ---
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALL_DIR="/opt/linux-hotspot-manager"
BIN_PATH="/usr/bin/hotspot"
UNINSTALLER_PATH="/usr/bin/hotspot-uninstall"
DESKTOP_SRC="$CURRENT_DIR/Hotspot.desktop"

# Deteksi Icon (Mencari png atau jpeg/jpg)
ICON_SRC=$(find "$CURRENT_DIR" -maxdepth 1 -name "icon.png" -o -name "icon.jpeg" -o -name "icon.jpg" | head -n 1)

echo "=== INSTALLER LINUX HOTSPOT MANAGER ==="

# 1. Cek Kelengkapan File Sumber
if [[ ! -f "$CURRENT_DIR/hotspot_gui.py" || ! -f "$CURRENT_DIR/hotspot_ctrl.sh" ]]; then
    echo "Error: File instalasi tidak lengkap (hotspot_gui.py atau hotspot_ctrl.sh hilang)."
    exit 1
fi

# 2. Install Dependencies
echo "[1/7] Menginstall dependencies..."
apt-get update -qq
apt-get install -y python3-tk dnsmasq-base jq iw network-manager ufw policykit-1

# 3. Setup Direktori Sistem
echo "[2/7] Membuat direktori aplikasi di $INSTALL_DIR..."
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

# Buat app_config.json default
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

# Handling Icon (Rename jadi standar 'app_icon.png' di tujuan agar mudah)
if [ -n "$ICON_SRC" ]; then
    echo "Icon ditemukan: $ICON_SRC"
    cp "$ICON_SRC" "$INSTALL_DIR/app_icon.png"
else
    echo "Warning: Icon tidak ditemukan. Menggunakan icon default sistem."
fi

# Handling Desktop Entry
if [ -f "$DESKTOP_SRC" ]; then
    TARGET_DESKTOP="/usr/share/applications/linux-hotspot-manager.desktop"
    cp "$DESKTOP_SRC" "$TARGET_DESKTOP"
    
    # MODIFIKASI OTOMATIS FILE DESKTOP
    # 1. Pastikan Exec mengarah ke /usr/bin/hotspot
    sed -i "s|^Exec=.*|Exec=$BIN_PATH|" "$TARGET_DESKTOP"
    
    # 2. Pastikan Icon mengarah ke /opt/.../app_icon.png
    if [ -n "$ICON_SRC" ]; then
        sed -i "s|^Icon=.*|Icon=$INSTALL_DIR/app_icon.png|" "$TARGET_DESKTOP"
    else
        sed -i "s|^Icon=.*|Icon=network-wireless-hotspot|" "$TARGET_DESKTOP"
    fi
    
    chmod 644 "$TARGET_DESKTOP"
else
    echo "Warning: Hotspot.desktop tidak ditemukan."
fi

# Set Permissions
chmod +x "$INSTALL_DIR/hotspot_ctrl.sh"
chown -R root:root "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# 6. Membuat Wrapper Binary (/usr/bin/hotspot)
echo "[5/7] Membuat command 'hotspot'..."
cat > "$BIN_PATH" <<EOF
#!/bin/bash
if [ -z "\$DISPLAY" ]; then
    echo "Error: Aplikasi ini membutuhkan GUI."
    exit 1
fi
pkexec env DISPLAY=\$DISPLAY XAUTHORITY=\$XAUTHORITY python3 $INSTALL_DIR/hotspot_gui.py
EOF
chmod +x "$BIN_PATH"

# 7. Membuat Uninstaller (/usr/bin/hotspot-uninstall)
echo "[6/7] Membuat uninstaller..."
cat > "$UNINSTALLER_PATH" <<EOF
#!/bin/bash
# Uninstaller Linux Hotspot Manager

if [ "\$EUID" -ne 0 ]; then
  echo "Mohon jalankan sebagai root: sudo hotspot-uninstall"
  exit
fi

echo "Mempersiapkan uninstall..."

# --- STEP PENTING: MATIKAN HOTSPOT DULU ---
if [ -f "$INSTALL_DIR/hotspot_ctrl.sh" ]; then
    echo "Memastikan hotspot mati..."
    # Panggil fungsi off dari script controller
    bash "$INSTALL_DIR/hotspot_ctrl.sh" off > /dev/null 2>&1
    
    # Double check: Hapus interface virtual paksa jika masih nyangkut
    VIRT_IF=\$(jq -r '.virt_interface' "$INSTALL_DIR/wifi_config.json" 2>/dev/null)
    if [ ! -z "\$VIRT_IF" ]; then
        ip link set \$VIRT_IF down 2>/dev/null
        iw dev \$VIRT_IF del 2>/dev/null
    fi
    sleep 2
fi
# ------------------------------------------

echo "Menghapus file aplikasi..."
rm -rf "$INSTALL_DIR"
rm -f "$BIN_PATH"
rm -f "/usr/share/applications/linux-hotspot-manager.desktop"

# Hapus diri sendiri
rm -f "\$0"

echo "Uninstall selesai. Semua bersih."
EOF
chmod +x "$UNINSTALLER_PATH"

echo ""
echo "=== INSTALASI SUKSES ==="
echo "Jalankan dengan perintah: hotspot"
echo "Atau cari di menu aplikasi: Linux Hotspot Manager"
echo "Untuk menghapus aplikasi: sudo hotspot-uninstall"
echo ""
echo "[7/7] Membersihkan file installer..."

# 8. Self-Destruct (Menghapus folder tempat installer ini berada)
rm -rf "$CURRENT_DIR"

exit 0
