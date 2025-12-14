import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import subprocess
import os
import threading
import json
import time
import fcntl
import sys
import logging

# --- KONFIGURASI FILE & PATH ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT_PATH = os.path.join(BASE_DIR, "hotspot_ctrl.sh")
APP_CONFIG_FILE = os.path.join(BASE_DIR, "app_config.json")
WIFI_CONFIG_FILE = os.path.join(BASE_DIR, "wifi_config.json")
VERSION_FILE = os.path.join(BASE_DIR, "version.txt")
LOCK_FILE = "/tmp/linux_hotspot.lock"
LOG_FILE = "/var/log/linux-hotspot-manager.log"
QR_TEMP_FILE = "/tmp/hotspot_qr.png"

# Setup Logging
logging.basicConfig(filename=LOG_FILE, level=logging.INFO, 
                    format='%(asctime)s [GUI] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

class HotspotApp:
    def __init__(self, root):
        self.lock_file = open(LOCK_FILE, 'w')
        try:
            fcntl.lockf(self.lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except IOError:
            messagebox.showerror("Error", "Linux Hotspot Manager sudah berjalan!")
            sys.exit(1)

        logging.info("Aplikasi GUI dimulai.")
        self.root = root
        
        # Ambil Versi
        self.app_version = self.get_version()
        self.root.title(f"Linux Hotspot Manager V{self.app_version}")
        self.root.geometry("680x550")
        
        style = ttk.Style()
        style.configure("Overlay.TFrame", background="#f0f0f0") 

        self.is_active = False
        self.config = self.load_config()

        if os.geteuid() != 0:
            logging.error("User bukan root. Keluar.")
            messagebox.showerror("Error", "Aplikasi ini membutuhkan akses root!\nJalankan dengan: sudo linux-hotspot-manager")
            root.destroy()
            return

        # --- LAYOUT ---
        main_frame = ttk.Frame(root, padding="15")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Footer
        footer_frame = ttk.Frame(main_frame)
        footer_frame.pack(side=tk.BOTTOM, fill=tk.X, pady=(5, 0))
        self.count_var = tk.StringVar(value="Total: 0")
        ttk.Label(footer_frame, textvariable=self.count_var, font=("Helvetica", 9)).pack(side=tk.RIGHT)
        ttk.Label(footer_frame, text=f"Linux Hotspot Manager V{self.app_version}", font=("Helvetica", 9, "italic"), foreground="gray").pack(side=tk.LEFT)

        # Header
        top_container = ttk.Frame(main_frame)
        top_container.pack(side=tk.TOP, fill=tk.X)

        self.header = ttk.Label(top_container, text="Wi-Fi Repeater Controller", font=("Helvetica", 16, "bold"))
        self.header.pack(pady=(0, 5))
        
        # Info SSID & QR Button
        info_frame = ttk.Frame(top_container)
        info_frame.pack(pady=(0, 15))
        
        self.ssid_label = ttk.Label(info_frame, text=self.get_ssid_info(), font=("Helvetica", 10), foreground="#555")
        self.ssid_label.pack(side=tk.LEFT, padx=5)
        
        self.qr_btn = ttk.Button(info_frame, text="Show QR", width=8, command=self.show_qr_code)
        self.qr_btn.pack(side=tk.LEFT, padx=5)

        # Status & Settings
        ctrl_frame = ttk.Frame(top_container)
        ctrl_frame.pack(fill=tk.X, pady=5)

        self.status_var = tk.StringVar(value="Status: Checking...")
        self.status_label = ttk.Label(ctrl_frame, textvariable=self.status_var, font=("Helvetica", 11, "bold"))
        self.status_label.pack(side=tk.LEFT)

        settings_frame = ttk.Frame(ctrl_frame)
        settings_frame.pack(side=tk.RIGHT)
        
        ttk.Label(settings_frame, text="Limit Client:").pack(side=tk.LEFT, padx=5)
        self.limit_var = tk.IntVar(value=self.config.get("limit", 5))
        self.limit_spin = ttk.Spinbox(settings_frame, from_=1, to=50, textvariable=self.limit_var, width=3, command=self.save_config)
        self.limit_spin.pack(side=tk.LEFT, padx=(0, 10))

        self.bl_btn = ttk.Button(settings_frame, text="Manage Blacklist", command=self.open_blacklist_overlay)
        self.bl_btn.pack(side=tk.LEFT)

        # Toggle Button
        self.btn_text = tk.StringVar(value="Loading...")
        self.toggle_btn = ttk.Button(top_container, textvariable=self.btn_text, command=self.toggle_hotspot)
        self.toggle_btn.pack(fill=tk.X, pady=10)

        # Table
        ttk.Label(top_container, text="Connected Devices (Klik Kanan untuk Opsi):").pack(anchor="w")
        table_frame = ttk.Frame(main_frame)
        table_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True, pady=5)

        columns = ('name', 'ip', 'mac')
        self.tree = ttk.Treeview(table_frame, columns=columns, show='headings')
        self.tree.heading('name', text='Device Name')
        self.tree.heading('ip', text='IP Address')
        self.tree.heading('mac', text='MAC Address')
        
        self.tree.column('name', width=220, stretch=True)
        self.tree.column('ip', width=120, stretch=False)
        self.tree.column('mac', width=150, stretch=False)
        
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar = ttk.Scrollbar(table_frame, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscroll=scrollbar.set)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.context_menu = tk.Menu(self.root, tearoff=0)
        self.context_menu.add_command(label="Rename Device", command=self.rename_device)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="Disconnect (Kick)", command=self.kick_selected)
        self.context_menu.add_command(label="Add to Blacklist", command=self.blacklist_selected)
        
        self.tree.bind("<Button-3>", self.show_context_menu)
        self.root.bind("<Button-1>", self.close_context_menu)

        self.check_real_status()
        self.check_clients_loop()

    # --- CORE ---
    def get_version(self):
        if os.path.exists(VERSION_FILE):
            try:
                with open(VERSION_FILE, 'r') as f: return f.read().strip()
            except: return "1.0"
        return "1.0"

    def load_config(self):
        default_conf = {"limit": 5, "blacklist": [], "custom_names": {}}
        if os.path.exists(APP_CONFIG_FILE):
            try:
                with open(APP_CONFIG_FILE, 'r') as f: return json.load(f)
            except: return default_conf
        return default_conf
    
    def get_ssid_info(self):
        try:
            with open(WIFI_CONFIG_FILE, 'r') as f:
                data = json.load(f)
                return f"SSID: {data.get('ssid', 'Unknown')} | Pass: {data.get('password', '***')}"
        except:
            return "Config Error"

    def save_config(self):
        self.config["limit"] = self.limit_var.get()
        with open(APP_CONFIG_FILE, 'w') as f: json.dump(self.config, f, indent=4)

    def run_script(self, args):
        cmd = [SCRIPT_PATH] + args if isinstance(args, list) else [SCRIPT_PATH, args]
        try:
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            return result.stdout.strip()
        except Exception as e:
            logging.error(f"Script Error: {str(e)}")
            return str(e)

    def check_real_status(self):
        output = self.run_script("check")
        if output.strip() == "ACTIVE":
            self.is_active = True
            self.status_var.set("Status: ON (Running)")
            self.status_label.configure(foreground="green")
            self.btn_text.set("Matikan Hotspot")
            return True
        else:
            self.is_active = False
            self.status_var.set("Status: OFF")
            self.status_label.configure(foreground="red")
            self.btn_text.set("Nyalakan Hotspot")
            return False
            
    # --- QR CODE FEATURE ---
    def show_qr_code(self):
        try:
            with open(WIFI_CONFIG_FILE, 'r') as f:
                data = json.load(f)
                ssid = data.get('ssid')
                password = data.get('password')
                
            if not ssid or not password:
                messagebox.showerror("Error", "Config tidak valid.")
                return

            # Format String WiFi: WIFI:T:WPA;S:MySSID;P:MyPassword;;
            # Gunakan qrencode (CLI tool) untuk generate PNG
            qr_string = f"WIFI:T:WPA;S:{ssid};P:{password};;"
            cmd = ["qrencode", "-o", QR_TEMP_FILE, "-s", "6", "-l", "M", qr_string]
            
            subprocess.run(cmd, check=True)
            
            # Tampilkan di Window Baru
            qr_win = tk.Toplevel(self.root)
            qr_win.title("Scan to Connect")
            qr_win.geometry("300x350")
            
            # Load Image
            img = tk.PhotoImage(file=QR_TEMP_FILE)
            
            lbl_img = ttk.Label(qr_win, image=img)
            lbl_img.image = img # Keep reference
            lbl_img.pack(pady=20)
            
            ttk.Label(qr_win, text=f"SSID: {ssid}", font=("Helvetica", 10, "bold")).pack()
            ttk.Label(qr_win, text=f"Pass: {password}", font=("Helvetica", 9)).pack()
            ttk.Button(qr_win, text="Tutup", command=qr_win.destroy).pack(pady=10)
            
        except FileNotFoundError:
             messagebox.showerror("Error", "Tool 'qrencode' belum terinstall.\nSilakan update aplikasi.")
        except Exception as e:
             messagebox.showerror("Error", f"Gagal generate QR: {e}")

    def open_log_file(self):
        try:
            subprocess.Popen(['xdg-open', LOG_FILE])
        except Exception as e:
            messagebox.showerror("Error", f"Gagal membuka log: {e}")

    def show_copyable_error(self, title, message):
        err_win = tk.Toplevel(self.root)
        err_win.title(title)
        err_win.geometry("600x450")
        
        lbl = ttk.Label(err_win, text="Terjadi kesalahan. Silakan cek log untuk detail.", font=("Helvetica", 10, "bold"), foreground="red")
        lbl.pack(pady=10)

        txt_frame = ttk.Frame(err_win)
        txt_frame.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        txt = tk.Text(txt_frame, wrap="word", height=10)
        txt.pack(side="left", fill="both", expand=True)
        sb = ttk.Scrollbar(txt_frame, orient="vertical", command=txt.yview)
        sb.pack(side="right", fill="y")
        txt.configure(yscrollcommand=sb.set)
        txt.insert("1.0", message)
        txt.bind("<Key>", lambda e: "break") 
        
        btn_frame = ttk.Frame(err_win)
        btn_frame.pack(pady=10)
        ttk.Button(btn_frame, text="Lihat Log File", command=self.open_log_file).pack(side=tk.LEFT, padx=10)
        ttk.Button(btn_frame, text="Tutup", command=err_win.destroy).pack(side=tk.LEFT, padx=10)

    def toggle_hotspot(self):
        self.toggle_btn.state(['disabled'])
        threading.Thread(target=self._toggle_thread).start()

    def _toggle_thread(self):
        if not self.is_active:
            logging.info("User menekan tombol START.")
            self.status_var.set("Status: Starting...")
            out = self.run_script("on")
            
            if "SUCCESS" in out:
                logging.info("Hotspot berhasil menyala.")
                success_start = False
                for i in range(15): 
                    self.status_var.set(f"Status: Verifying... ({i+1}/15)")
                    time.sleep(1)
                    if self.run_script("check").strip() == "ACTIVE":
                        success_start = True
                        break
                
                if success_start:
                    self.is_active = True
                    self.check_real_status()
                else:
                    self.is_active = True
                    self.status_var.set("Status: ON (Warning: Slow Check)")
                    self.status_label.configure(foreground="orange")
                    self.btn_text.set("Matikan Hotspot")
            else:
                logging.error(f"Gagal menyalakan hotspot. Output: {out}")
                self.root.after(0, lambda: self.show_copyable_error("Gagal Menyalakan", f"Error Log:\n{out}\n\nCek file log untuk detail lengkap."))
                self.status_var.set("Status: Error")
                self.check_real_status()
        else:
            logging.info("User menekan tombol STOP.")
            self.status_var.set("Status: Stopping...")
            self.run_script("off")
            self.is_active = False
            self.status_var.set("Status: OFF")
            self.status_label.configure(foreground="red")
            self.btn_text.set("Nyalakan Hotspot")
            self.tree.delete(*self.tree.get_children())
            self.count_var.set("Total: 0")
        
        self.toggle_btn.state(['!disabled'])

    # --- UI EVENTS ---
    def show_context_menu(self, event):
        item = self.tree.identify_row(event.y)
        if item:
            self.tree.selection_set(item)
            self.context_menu.post(event.x_root, event.y_root)
    
    def close_context_menu(self, event):
        self.context_menu.unpost()

    # --- ACTIONS ---
    def rename_device(self):
        sel = self.tree.selection()
        if not sel: return
        item = self.tree.item(sel)
        mac = item['values'][2]
        current_name = item['values'][0]
        new_name = simpledialog.askstring("Rename", f"Nama baru untuk {mac}:", initialvalue=current_name)
        if new_name:
            self.config["custom_names"][mac] = new_name
            self.save_config()
            self.update_client_list()

    def kick_selected(self):
        sel = self.tree.selection()
        if not sel: return
        mac = self.tree.item(sel)['values'][2]
        logging.info(f"User kick device: {mac}")
        self.run_script(["kick", mac])

    def blacklist_selected(self):
        sel = self.tree.selection()
        if not sel: return
        mac = self.tree.item(sel)['values'][2]
        if messagebox.askyesno("Blacklist", f"Blokir permanen {mac}?"):
            logging.info(f"User blacklist device: {mac}")
            if mac not in self.config["blacklist"]:
                self.config["blacklist"].append(mac)
                self.save_config()
                self.run_script(["kick", mac])
                messagebox.showinfo("Info", "Device diblokir.")

    # --- BLACKLIST OVERLAY ---
    def open_blacklist_overlay(self):
        self.overlay = ttk.Frame(self.root, style="Overlay.TFrame", padding=20)
        self.overlay.place(relx=0, rely=0, relwidth=1, relheight=1)
        
        ttk.Label(self.overlay, text="Blacklist Manager", font=("Helvetica", 14, "bold")).pack(pady=(0, 20))
        
        bl_frame = ttk.Frame(self.overlay)
        bl_frame.pack(fill=tk.BOTH, expand=True)

        cols = ('name', 'mac')
        bl_tree = ttk.Treeview(bl_frame, columns=cols, show='headings')
        bl_tree.heading('name', text='Saved Name')
        bl_tree.heading('mac', text='MAC Address')
        bl_tree.column('name', width=150, stretch=True)
        bl_tree.column('mac', width=150, stretch=False)
        
        bl_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        sb = ttk.Scrollbar(bl_frame, orient=tk.VERTICAL, command=bl_tree.yview)
        bl_tree.configure(yscroll=sb.set)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        
        for mac in self.config["blacklist"]:
            name = self.config["custom_names"].get(mac, "Unknown")
            bl_tree.insert('', tk.END, values=(name, mac))
            
        def remove_bl():
            sel = bl_tree.selection()
            if not sel: return
            item = bl_tree.item(sel)
            mac = item['values'][1]
            logging.info(f"User remove blacklist: {mac}")
            self.config["blacklist"].remove(mac)
            self.save_config()
            bl_tree.delete(sel)
        
        def close_overlay():
            self.overlay.destroy()
            
        btn_frame = ttk.Frame(self.overlay)
        btn_frame.pack(pady=20)
        ttk.Button(btn_frame, text="Hapus dari Blacklist", command=remove_bl).pack(side=tk.LEFT, padx=10)
        ttk.Button(btn_frame, text="Tutup / Kembali", command=close_overlay).pack(side=tk.LEFT, padx=10)

    # --- LOOP ---
    def check_clients_loop(self):
        if self.is_active:
            threading.Thread(target=self.update_client_list, daemon=True).start()
        self.root.after(3000, self.check_clients_loop)

    def update_client_list(self):
        output = self.run_script("status")
        if "INACTIVE" in output: return

        lines = output.split('\n')
        current_clients = []
        for line in lines:
            if "|" in line:
                parts = line.split('|')
                if len(parts) == 3:
                    mac, ip, sys_name = parts
                    if mac in self.config["blacklist"]:
                        self.run_script(["kick", mac])
                        continue 
                    display_name = self.config["custom_names"].get(mac, sys_name)
                    if display_name == "Unknown": display_name = f"Device ({mac[-5:]})"
                    current_clients.append((display_name, ip, mac))

        limit = self.limit_var.get()
        if len(current_clients) > limit:
            victim = current_clients[-1]
            logging.info(f"Limit reached ({limit}). Kicking: {victim[2]}")
            self.run_script(["kick", victim[2]])
            current_clients.pop()

        selected_items = self.tree.selection()
        selected_macs = [self.tree.item(i)['values'][2] for i in selected_items] if selected_items else []

        self.tree.delete(*self.tree.get_children())
        for c in current_clients:
            item_id = self.tree.insert('', tk.END, values=c)
            if c[2] in selected_macs: self.tree.selection_add(item_id)
            
        self.count_var.set(f"Total: {len(current_clients)} / Limit: {limit}")

if __name__ == "__main__":
    root = tk.Tk()
    app = HotspotApp(root)
    root.mainloop()
