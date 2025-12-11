#!/bin/bash

# Pastikan dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "Mohon jalankan sebagai root: sudo bash uninstall.sh"
  exit
fi

INSTALL_DIR="/opt/linux-hotspot-manager"
BIN_PATH="/usr/bin/hotspot"
DESKTOP_ENTRY="/usr/share/applications/linux-hotspot-manager.desktop"

echo "=== UNINSTALLER LINUX HOTSPOT MANAGER ==="

if [ -f "$BIN_PATH" ]; then
    echo "Menghapus binary ($BIN_PATH)..."
    rm "$BIN_PATH"
fi

if [ -f "$DESKTOP_ENTRY" ]; then
    echo "Menghapus shortcut menu..."
    rm "$DESKTOP_ENTRY"
fi

if [ -d "$INSTALL_DIR" ]; then
    echo "Menghapus file aplikasi dan konfigurasi ($INSTALL_DIR)..."
    # Matikan hotspot dulu jika menyala (opsional, best effort)
    bash "$INSTALL_DIR/hotspot_ctrl.sh" off > /dev/null 2>&1
    rm -rf "$INSTALL_DIR"
else
    echo "Direktori aplikasi tidak ditemukan."
fi

echo "=== UNINSTALL SELESAI ==="
echo "Aplikasi telah dihapus dari sistem."
