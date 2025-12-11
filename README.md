# Linux Hotspot Manager

![Icon](icon.png)

**Linux Hotspot Manager** is a lightweight, powerful GUI tool to create a virtual Wi-Fi Hotspot (Repeater) on Linux. It allows you to share your internet connection (Ethernet or Wi-Fi) using a single Wi-Fi adapter or a secondary one, with advanced management features like client limits, blacklisting, and real-time monitoring.

Built with Python (Tkinter) and Bash, it leverages `NetworkManager`, `iw`, and `dnsmasq` to provide a stable and configurable hotspot experience.

## 🚀 Features

*   **Virtual Interface Support:** Creates a virtual interface (`__ap`) to run a hotspot while simultaneously connected to Wi-Fi (requires hardware support).
*   **Automatic Band Detection:** Automatically detects if your main Wi-Fi is 2.4GHz or 5GHz and adjusts the hotspot channel to prevent hardware conflicts.
*   **Client Management:**
    *   View connected devices (IP, MAC, Hostname).
    *   **Rename** devices for easier identification.
    *   **Kick** unwanted clients instantly.
    *   **Blacklist** MAC addresses permanently.
    *   **Limit** the maximum number of connected clients.
*   **Compatibility Fixes:** Disables PMF (Protected Management Frames) by default to ensure older Android/iOS devices can connect without "Authenticating..." loops.
*   **CLI Support:** Toggle hotspot on/off directly from the terminal without opening the GUI.
*   **Logging:** Comprehensive error logging for easy troubleshooting.

## 📋 Prerequisites

*   **OS:** Linux Mint, Ubuntu, Debian, or derivatives.
*   **Hardware:** A Wi-Fi card that supports **AP (Access Point) Mode**.
*   **Dependencies:** The installer will automatically install: `python3-tk`, `dnsmasq-base`, `jq`, `iw`, `network-manager`, `ufw`, `policykit-1`.

## 🛠️ Installation

1.  **Download** the latest release or clone this repository.
2.  Open a terminal in the folder containing the files.
3.  Run the installer script as root:

```bash
sudo bash install.sh
```

4.  Follow the on-screen instructions:
    *   Select your **Main Interface** (Source of Internet, e.g., `wlp3s0`).
    *   Select/Name your **Virtual Interface** (e.g., `wlp3s1`).
    *   Set your **SSID** and **Password**.

Once installed, you can find **Linux Hotspot Manager** in your application menu or run it via terminal.

## 💻 Usage

### Graphical User Interface (GUI)
Simply launch the application from your menu or run:
```bash
linux-hotspot-manager
```
*   **Start/Stop:** Click the toggle button.
*   **Manage Clients:** Right-click on a connected device in the list to Rename, Kick, or Blacklist.
*   **Settings:** Adjust the client limit or manage the blacklist via the buttons on the top right.

### Command Line Interface (CLI)
You can control the hotspot without the GUI (useful for scripts or quick toggles):

*   **Turn On:**
    ```bash
    linux-hotspot-manager --on
    ```
*   **Turn Off:**
    ```bash
    linux-hotspot-manager --off
    ```

## 🔍 Troubleshooting & Logs

If the hotspot fails to start or clients cannot connect:

1.  **Check the Logs:** The application logs all events to:
    ```
    /var/log/linux-hotspot-manager.log
    ```
    You can click the **"Lihat Log File"** button in the GUI error popup to open this file automatically.

2.  **Common Issues:**
    *   *Driver Crash:* Some Wi-Fi cards do not support simultaneous Station/AP mode on different channels. The app tries to lock the channel, but hardware limitations may apply.
    *   *Authentication Loop:* Ensure PMF is disabled (the app does this by default).

## 🗑️ Uninstallation

To completely remove the application, configuration files, and logs from your system, run:

```bash
linux-hotspot-manager --uninstall
```
*Or manually:* `sudo /usr/bin/hotspot-uninstall`

## 📂 File Structure

*   **Executable:** `/usr/bin/linux-hotspot-manager`
*   **Core Files:** `/opt/linux-hotspot-manager/`
*   **Logs:** `/var/log/linux-hotspot-manager.log`
*   **Config:** `/opt/linux-hotspot-manager/wifi_config.json`

## 📜 License

This project is open-source. Feel free to modify and distribute.
