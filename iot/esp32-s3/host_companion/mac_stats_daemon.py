#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# /// script
# dependencies = [
#     "pyserial",
# ]
# ///
"""
mac_stats_daemon.py
Enhanced host companion daemon for macOS.
Streams host telemetry (1 Hz) and active frontmost application profiles
(debounced at 250ms) to the ESP32-S3 Mac Controller over USB CDC serial.
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

from app_profiles import (
    FrontmostAppDetector,
    get_profile_for_app,
    build_app_payload,
)
from agent_ci_monitor import (
    AgentCIMonitor,
    serialize_agent_ci_packet,
)

def get_cpu_percent() -> int:
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

def get_ram_percent() -> int:
    try:
        vm = subprocess.check_output("vm_stat", shell=True).decode()
        lines = vm.split("\n")
        active_pages = 0
        inactive_pages = 0
        free_pages = 0
        speculative_pages = 0
        wired_pages = 0
        compressed_pages = 0

        for line in lines:
            if "Pages free:" in line:
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

def handle_esp_command(cmd_line: str, monitor: AgentCIMonitor):
    """Processes inbound action commands received from ESP32 touch button presses."""
    try:
        data = json.loads(cmd_line.strip())
        cmd = (data.get("cmd") or data.get("action") or "").lower()
        if not cmd:
            return

        print(f"[CMD] Inbound command from ESP32: {cmd}", flush=True)

        workspace_dir = getattr(monitor, "workspace_dir", None)

        if cmd in ("run_checks", "refresh", "refresh_ci"):
            print(f"[CMD] Triggering immediate CI & agent poll...", flush=True)
            monitor.trigger_refresh()
            if cmd == "run_checks":
                try:
                    subprocess.Popen(
                        ["gh", "pr", "checks"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        cwd=workspace_dir,
                    )
                except Exception:
                    pass
        elif cmd in ("open_pr", "open_ci"):
            print("[CMD] Opening PR / repo in browser...", flush=True)
            try:
                payload = monitor.get_payload()
                pr_num = payload.get("ci", {}).get("pr", 0)
                if pr_num and pr_num > 0:
                    subprocess.Popen(
                        ["gh", "pr", "view", str(pr_num), "--web"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        cwd=workspace_dir,
                    )
                else:
                    subprocess.Popen(
                        ["gh", "repo", "view", "--web"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        cwd=workspace_dir,
                    )
            except Exception as e:
                print(f"[CMD] Error opening browser: {e}", flush=True)
        elif cmd == "focus_agent":
            print("[CMD] Focusing active agent application...", flush=True)
            try:
                script = 'tell application "Antigravity" to activate'
                subprocess.Popen(["osascript", "-e", script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass
    except Exception as e:
        print(f"[CMD] Failed to process command '{cmd_line}': {e}", flush=True)

def main():
    print("ESP32-S3 Mac Desktop Companion Daemon starting...")
    port = None
    detector = FrontmostAppDetector(debounce_seconds=0.25)
    monitor = AgentCIMonitor(agent_interval=3.0, ci_interval=10.0)
    monitor.start()

    last_stats_time = 0.0
    last_agent_ci_time = 0.0
    last_sent_app_name = None
    last_agent_state = None
    last_ci_status = None

    try:
        while True:
            if port is None or not os.path.exists(port):
                port = find_esp_port()
                if not port:
                    print("Waiting for ESP32-S3 USB connection (/dev/cu.usbmodem*)...")
                    time.sleep(1.5)
                    continue
                print(f"Connected to ESP32-S3 on port: {port}")

            try:
                with serial.Serial(port, 115200, timeout=1) as ser:
                    # 1. Force immediate app profile transmission on initial connection
                    initial_bundle = detector.update(force_immediate=True)
                    initial_profile = get_profile_for_app(initial_bundle, detector.confirmed_app_name)
                    app_payload = build_app_payload(initial_profile)
                    ser.write((json.dumps(app_payload) + "\n").encode("utf-8"))
                    ser.flush()
                    last_sent_app_name = initial_profile["app"]
                    print(f"[INIT] Sent initial app profile: {last_sent_app_name}")

                    # 2. Send initial stats immediately
                    cpu = get_cpu_percent()
                    ram = get_ram_percent()
                    now_str = datetime.now().strftime("%I:%M %p")
                    stats_payload = {
                        "type": "stats",
                        "cpu": cpu,
                        "ram": ram,
                        "time": now_str
                    }
                    ser.write((json.dumps(stats_payload) + "\n").encode("utf-8"))
                    ser.flush()
                    last_stats_time = time.monotonic()
                    print(f"[INIT] Sent initial stats: {stats_payload}", flush=True)

                    # 3. Send initial agent_ci payload immediately on connect
                    initial_agent_ci = monitor.get_payload()
                    ser.write(serialize_agent_ci_packet(initial_agent_ci).encode("utf-8"))
                    ser.flush()
                    last_agent_ci_time = time.monotonic()
                    last_agent_state = initial_agent_ci.get("agent", {}).get("state")
                    last_ci_status = initial_agent_ci.get("ci", {}).get("status")
                    print(f"[INIT] Sent initial agent/CI: agent={last_agent_state}, ci={last_ci_status}", flush=True)

                    while True:
                        now = time.monotonic()

                        # 1. Frontmost App Check (runs every ~50ms)
                        new_bundle = detector.update()
                        if new_bundle is not None:
                            profile = get_profile_for_app(new_bundle, detector.confirmed_app_name)
                            if profile["app"] != last_sent_app_name:
                                payload = build_app_payload(profile)
                                ser.write((json.dumps(payload) + "\n").encode("utf-8"))
                                ser.flush()
                                last_sent_app_name = profile["app"]
                                print(f"[APP] Focus changed -> {last_sent_app_name} ({new_bundle})", flush=True)

                        # 2. Telemetry Check (1.0 Hz)
                        if now - last_stats_time >= 1.0:
                            cpu = get_cpu_percent()
                            ram = get_ram_percent()
                            now_str = datetime.now().strftime("%I:%M %p")

                            stats_payload = {
                                "type": "stats",
                                "cpu": cpu,
                                "ram": ram,
                                "time": now_str
                            }
                            ser.write((json.dumps(stats_payload) + "\n").encode("utf-8"))
                            ser.flush()
                            last_stats_time = now

                        # 3. Agent & CI Status Check (every 5.0s or immediate on state transition)
                        current_agent_ci = monitor.get_payload()
                        cur_agent_state = current_agent_ci.get("agent", {}).get("state")
                        cur_ci_status = current_agent_ci.get("ci", {}).get("status")
                        state_changed = (cur_agent_state != last_agent_state) or (cur_ci_status != last_ci_status)

                        if (now - last_agent_ci_time >= 5.0) or state_changed:
                            ser.write(serialize_agent_ci_packet(current_agent_ci).encode("utf-8"))
                            ser.flush()
                            last_agent_ci_time = now
                            last_agent_state = cur_agent_state
                            last_ci_status = cur_ci_status
                            if state_changed:
                                print(f"[AGENT_CI] State transition -> agent={cur_agent_state}, ci={cur_ci_status}", flush=True)

                        # 4. Check Inbound Serial Commands from ESP32 Touch Buttons
                        while ser.in_waiting > 0:
                            line = ser.readline().decode("utf-8", errors="ignore").strip()
                            if line.startswith("{") and line.endswith("}"):
                                handle_esp_command(line, monitor)

                        # Non-blocking loop sleep
                        time.sleep(0.05)

            except Exception as e:
                print(f"Connection lost: {e}")
                port = None
                last_sent_app_name = None
                time.sleep(1.5)

    finally:
        monitor.stop()

if __name__ == "__main__":
    main()
