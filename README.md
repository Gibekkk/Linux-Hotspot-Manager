# Linux Hotspot Manager

**Linux Hotspot Manager** is a robust and user-friendly tool to create a virtual Wi-Fi Hotspot (Repeater) on Linux. It allows you to share your internet connection (Ethernet or Wi-Fi) using a single Wi-Fi adapter by creating a virtual interface, eliminating the need for a secondary Wi-Fi card.

Built with Python (Tkinter) and Bash, it integrates seamlessly with `NetworkManager`, `iw`, and `dnsmasq` to provide a stable hotspot experience with advanced management features.

## 🚀 Key Features

*   **Virtual Interface Support:** Run a hotspot (`__ap` mode) while simultaneously connected to a Wi-Fi network on the same adapter.
*   **Dual Mode Control:**
    *   **GUI:** User-friendly interface to manage everything visually.
    *   **CLI:** Powerful terminal commands for automation and quick toggles.
*   **Client Management:**
    *   Real-time monitoring of connected devices (IP, MAC, Hostname).
    *   **Rename** devices for easier identification.
    *   **Kick** unwanted clients instantly.
    *   **Blacklist** MAC addresses permanently.
    *   **Limit** the maximum number of connected clients.
*   **Easy Connection:** Generate **QR Codes** directly within the app for smartphones to connect instantly.
*   **Smart Configuration:** Change SSID, Password, and Interfaces directly via GUI or Terminal without editing files manually.
*   **Auto-Update System:** Built-in feature to check and pull the latest updates from GitHub automatically.
*   **Compatibility Fixes:** Disables PMF (Protected Management Frames) by default to ensure older Android/iOS devices can connect.

## 📋 Prerequisites

*   **OS:** Linux Mint, Ubuntu, Debian, or compatible derivatives.
*   **Hardware:** A Wi-Fi card that supports **AP (Access Point) Mode**.
*   **Root Access:** The application requires `sudo` privileges to manage network interfaces.

## 🛠️ Installation

1.  **Download** the repository or clone it.
2.  Open a terminal in the folder containing the files.
3.  Run the installer script:

```bash
sudo bash install.sh
```
4.  Follow the on-screen instructions to set up your interfaces and password.
    *   *The installer will automatically install all necessary dependencies (python3-tk, qrencode, dnsmasq, etc).*

Once installed, you can launch **Linux Hotspot Manager** from your application menu.

## 💻 Usage

### Graphical User Interface (GUI)
Launch via the application menu or run `linux-hotspot-manager` in the terminal.

*   **Start/Stop:** Toggle the hotspot status.
*   **Show QR:** Display a QR code for devices to scan and connect.
*   **Config Wi-Fi:** Change SSID, Password, and Interfaces via a popup menu.
*   **Manage Clients:** Right-click on a device in the list to Rename, Kick, or Blacklist.
*   **Logs:** View system logs directly inside the application if errors occur.

### Command Line Interface (CLI)
You can manage the hotspot entirely from the terminal using `sudo linux-hotspot-manager [OPTION]`:

| Option | Description |
| :--- | :--- |
| `--on` | Turn on the hotspot. |
| `--off` | Turn off the hotspot. |
| `--restart` | Restart the hotspot (apply new configs). |
| `--status` | Check current status, SSID, and Password. |
| `--log` | View application logs (press `q` to exit). |
| `--config` | Run the interactive configuration wizard. |
| `--config key=value` | Change specific settings (e.g., `ssid="MyNet"` `password="12345678"`). |
| `--update` | Check for updates and upgrade the application automatically. |
| `--version` | Check installed and remote versions. |
| `--uninstall` | Remove the application from the system. |

## ⚙️ Configuration

You can change the configuration in three ways:
1.  **Via GUI:** Click the "Config Wi-Fi" button.
2.  **Via CLI (Interactive):** Run `sudo linux-hotspot-manager --config`.
3.  **Via CLI (Direct):**
    ```bash
    sudo linux-hotspot-manager --config ssid="NewName" password="NewPassword"
    ```
    *Don't forget to restart the hotspot after changing settings.*

## 🔍 Troubleshooting

If the hotspot fails to start:
1.  **Check Logs:** Run `linux-hotspot-manager --log` or click "Lihat Log" in the GUI error popup.
2.  **Interface Issue:** Ensure your Wi-Fi card supports Virtual Interfaces. Some older cards may not support running Station and AP mode simultaneously.
3.  **5GHz vs 2.4GHz:** The application automatically tries to match the hotspot channel with your main Wi-Fi connection to avoid hardware conflicts.

## 🗑️ Uninstallation

To completely remove the application, configuration files, and logs:

```bash
sudo linux-hotspot-manager --uninstall
```

## 📜 License

This project is open-source. Feel free to modify and distribute.
