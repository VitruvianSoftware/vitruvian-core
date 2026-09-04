#!/usr/bin/env python3
# /// script
# dependencies = [
#     "pyserial",
# ]
# ///
"""
mac_stats_daemon.py
Lightweight host daemon for macOS. Sends CPU, RAM, and Time to the ESP32-S3 over USB CDC.
Usage:
    uv run host_companion/mac_stats_daemon.py
"""

import os
import sys
import time
import glob
import json
import subprocess
from datetime import datetime
import serial

def get_cpu_percent():
    try:
        # Fast 1-sample top command for macOS
        cmd = "top -l 1 -n 0 | grep 'CPU usage'"
        output = subprocess.check_output(cmd, shell=True).decode()
        parts = output.split(",")
        user = float(parts[0].split(":")[1].replace("% user", "").strip())
        sys_pct = float(parts[1].replace("% sys", "").strip())
        return int(round(user + sys_pct))
    except Exception:
        return 0

def get_ram_percent():
    try:
        vm = subprocess.check_output("vm_stat", shell=True).decode()
        lines = vm.split("\n")
        page_size = 4096
        free_pages = 0
        active_pages = 0
        inactive_pages = 0
        speculative_pages = 0
        wired_pages = 0
        compressed_pages = 0

        for line in lines:
            if "page size of" in line:
                page_size = int(line.split()[7])
            elif "Pages free:" in line:
                free_pages = int(line.split()[-1].rstrip("."))
            elif "Pages active:" in line:
                active_pages = int(line.split()[-1].rstrip("."))
            elif "Pages inactive:" in line:
                inactive_pages = int(line.split()[-1].rstrip("."))
            elif "Pages speculative:" in line:
                speculative_pages = int(line.split()[-1].rstrip("."))
            elif "Pages wired down:" in line:
                wired_pages = int(line.split()[-1].rstrip("."))
            elif "Pages occupied by compressor:" in line:
                compressed_pages = int(line.split()[-1].rstrip("."))

        used_pages = active_pages + wired_pages + compressed_pages
        total_pages = used_pages + inactive_pages + free_pages + speculative_pages
        if total_pages > 0:
            return int(round((used_pages / total_pages) * 100))
        return 0
    except Exception:
        return 0

def find_esp_port():
    ports = glob.glob("/dev/cu.usbmodem*")
    if ports:
        return sorted(ports)[0]
    return None

def main():
    print("ESP32-S3 Mac Desktop Stats Companion starting...")
    port = None

    while True:
        if port is None or not os.path.exists(port):
            port = find_esp_port()
            if not port:
                print("Waiting for ESP32-S3 USB connection (/dev/cu.usbmodem*)...")
                time.sleep(2)
                continue
            print(f"Connected to ESP32-S3 on port: {port}")

        try:
            with serial.Serial(port, 115200, timeout=1) as ser:
                while True:
                    cpu = get_cpu_percent()
                    ram = get_ram_percent()
                    now_str = datetime.now().strftime("%I:%M %p")

                    payload = {
                        "cpu": cpu,
                        "ram": ram,
                        "time": now_str
                    }
                    msg = json.dumps(payload) + "\n"
                    ser.write(msg.encode("utf-8"))
                    ser.flush()
                    print(f"Sent: {payload}", flush=True)
                    time.sleep(1)
        except Exception as e:
            print(f"Connection lost: {e}")
            port = None
            time.sleep(2)

if __name__ == "__main__":
    main()
