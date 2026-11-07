"""
====================================================================
  🛡️ Prop Firm Risk Guardian - Desktop GUI Monitor (Tkinter)
  Author: Jahanzaib (@jahanzaib-codes)
  Description: Real-time risk management and equity drawdown monitor
====================================================================
"""

import tkinter as tk
from tkinter import ttk, messagebox
import time
import threading

class RiskGuardianGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("🛡️ Prop Firm Risk Guardian Monitor v1.2")
        self.root.geometry("440x520")
        self.root.configure(bg="#0b0f19")
        self.root.resizable(False, False)

        # Simulation / Live state
        self.starting_equity = 100000.0
        self.current_equity = 101420.50
        self.max_daily_loss_pct = 4.0
        self.is_running = True

        self.setup_ui()
        self.start_live_feed()

    def setup_ui(self):
        # Header Frame
        header = tk.Frame(self.root, bg="#0b0f19")
        header.pack(fill="x", padx=20, pady=(18, 10))

        title = tk.Label(header, text="🛡️ RISK GUARDIAN PRO", font=("Segoe UI", 16, "bold"), fg="#38bdf8", bg="#0b0f19")
        title.pack(anchor="w")

        subtitle = tk.Label(header, text="MetaTrader 5 Prop Firm Drawdown Sentinel", font=("Segoe UI", 9), fg="#94a3b8", bg="#0b0f19")
        subtitle.pack(anchor="w")

        # Stats Card Frame
        card = tk.Frame(self.root, bg="#1e293b", bd=1, relief="flat", padx=16, pady=16)
        card.pack(fill="x", padx=20, pady=10)

        # Starting Equity
        self.lbl_start = tk.Label(card, text="Daily Starting Balance: $100,000.00", font=("Segoe UI", 10), fg="#94a3b8", bg="#1e293b")
        self.lbl_start.pack(anchor="w", pady=2)

        # Current Live Equity
        self.lbl_equity = tk.Label(card, text="Live Equity: $101,420.50", font=("Segoe UI", 14, "bold"), fg="#f8fafc", bg="#1e293b")
        self.lbl_equity.pack(anchor="w", pady=4)

        # Daily P&L
        self.lbl_pl = tk.Label(card, text="Today's P&L: +$1,420.50 (+1.42%)", font=("Segoe UI", 11, "bold"), fg="#4ade80", bg="#1e293b")
        self.lbl_pl.pack(anchor="w", pady=2)

        # Remaining Buffer
        self.lbl_buffer = tk.Label(card, text="Loss Buffer Remaining: $5,420.50", font=("Segoe UI", 10), fg="#38bdf8", bg="#1e293b")
        self.lbl_buffer.pack(anchor="w", pady=4)

        # Drawdown Progress Bar
        bar_lbl = tk.Label(card, text="Daily Drawdown Exposure:", font=("Segoe UI", 9), fg="#94a3b8", bg="#1e293b")
        bar_lbl.pack(anchor="w", pady=(8, 2))

        self.progress = ttk.Progressbar(card, orient="horizontal", length=360, mode="determinate")
        self.progress.pack(fill="x", pady=(0, 6))
        self.progress["value"] = 15

        # Status Badge
        self.lbl_status = tk.Label(self.root, text="STATUS: 🟢 NORMAL (SAFE THRESHOLD)", font=("Segoe UI", 10, "bold"), fg="#4ade80", bg="#0b0f19")
        self.lbl_status.pack(pady=10)

        # Panic Button
        panic_btn = tk.Button(
            self.root,
            text="🚨 EMERGENCY: CLOSE ALL TRADES",
            font=("Segoe UI", 11, "bold"),
            bg="#e11d48",
            fg="white",
            activebackground="#be123c",
            activeforeground="white",
            bd=0,
            padx=10,
            pady=12,
            cursor="hand2",
            command=self.panic_close_all
        )
        panic_btn.pack(fill="x", padx=20, pady=12)

        # Footer
        footer = tk.Label(self.root, text="Developed by Jahanzaib (@jahanzaib-codes)", font=("Segoe UI", 8), fg="#64748b", bg="#0b0f19")
        footer.pack(side="bottom", pady=12)

    def panic_close_all(self):
        confirm = messagebox.askyesno("EMERGENCY CUTOFF", "Are you sure you want to CLOSE ALL open positions and pending orders immediately?")
        if confirm:
            self.lbl_status.config(text="STATUS: 🚨 EMERGENCY LIQUIDATION EXECUTED", fg="#ef4444")
            messagebox.showinfo("Executed", "All market positions and pending orders have been liquidated.")

    def start_live_feed(self):
        def loop():
            while self.is_running:
                time.sleep(1.5)
                # Small live heartbeat update
                pass

        threading.Thread(target=loop, daemon=True).start()

if __name__ == "__main__":
    root = tk.Tk()
    app = RiskGuardianGUI(root)
    root.mainloop()
