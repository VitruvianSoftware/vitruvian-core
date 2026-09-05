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


# ---------------------------------------------------------------------------
# Wi-Fi provisioning (Zero-Typing Companion Sync)
# ---------------------------------------------------------------------------
def get_active_wifi_ssid(interface: str = "en0"):
    """Returns the SSID the Mac is currently joined to, or None.

    Primary source is `networksetup -getairportnetwork` (stable CLI contract);
    fallback is `ipconfig getsummary`, which still reports the SSID on macOS
    releases where the airport utility has been removed.
    """
    try:
        out = subprocess.check_output(
            ["networksetup", "-getairportnetwork", interface],
            stderr=subprocess.DEVNULL,
            timeout=5,
        ).decode("utf-8", errors="ignore")
        # Success shape: "Current Wi-Fi Network: MyNetwork"
        if ":" in out and "not associated" not in out.lower():
            ssid = out.split(":", 1)[1].strip()
            if ssid:
                return ssid
    except Exception:
        pass

    try:
        out = subprocess.check_output(
            ["ipconfig", "getsummary", interface],
            stderr=subprocess.DEVNULL,
            timeout=5,
        ).decode("utf-8", errors="ignore")
        for line in out.splitlines():
            stripped = line.strip()
            if stripped.startswith("SSID") and ":" in stripped:
                ssid = stripped.split(":", 1)[1].strip()
                if ssid and ssid != "<redacted>":
                    return ssid
    except Exception:
        pass
    return None


def get_wifi_password(ssid: str, interactive: bool = True):
    """Resolves the WPA2 passphrase for `ssid`.

    Order: VITRUVIAN_WIFI_PASS env override (no keychain UI, good for
    scripting), then the macOS keychain (may show a system prompt), then an
    interactive getpass when running on a TTY. Returns None if unavailable —
    an empty string is a valid answer (open network).
    """
    env_pass = os.environ.get("VITRUVIAN_WIFI_PASS")
    if env_pass is not None:
        return env_pass

    try:
        out = subprocess.check_output(
            [
                "security",
                "find-generic-password",
                "-D",
                "AirPort network password",
                "-a",
                ssid,
                "-w",
            ],
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
        return out.decode("utf-8", errors="ignore").rstrip("\n")
    except Exception:
        pass

    if interactive and sys.stdin.isatty():
        import getpass

        return getpass.getpass(f"Wi-Fi passphrase for '{ssid}' (blank if open): ")
    return None


def build_wifi_set_payload(ssid: str, password) -> dict:
    return {"cmd": "wifi_set", "ssid": ssid, "pass": password or ""}


def serialize_wifi_set_packet(ssid: str, password) -> str:
    """Newline-framed UTF-8 JSON, matching the wire protocol in docs/protocol.md."""
    return json.dumps(build_wifi_set_payload(ssid, password)) + "\n"


def handle_wifi_sync_request(ser, interactive: bool = False) -> bool:
    """Answers a device {"cmd":"wifi_sync"} by beaming this Mac's credentials."""
    ssid = get_active_wifi_ssid()
    if not ssid:
        if interactive and sys.stdin.isatty():
            print("[WIFI] Mac Wi-Fi is currently off or not connected.")
            try:
                ssid = input("Enter Wi-Fi SSID to provision: ").strip()
            except (EOFError, KeyboardInterrupt):
                return False
            if not ssid:
                return False
        else:
            print(
                "[WIFI] No active Wi-Fi network detected on this Mac (Wi-Fi power may be off)",
                flush=True,
            )
            if ser:
                try:
                    ser.write(
                        b'{"type":"wifi_sync_error","error":"Mac Wi-Fi is off"}\n'
                    )
                    ser.flush()
                except Exception:
                    pass
            return False
    password = get_wifi_password(ssid, interactive=interactive)
    if password is None:
        print(
            f"[WIFI] No passphrase available for '{ssid}' "
            "(set VITRUVIAN_WIFI_PASS or run with --wifi-sync for a prompt)",
            flush=True,
        )
        if ser:
            try:
                ser.write(
                    b'{"type":"wifi_sync_error","error":"No password in keychain"}\n'
                )
                ser.flush()
            except Exception:
                pass
        return False
    ser.write(serialize_wifi_set_packet(ssid, password).encode("utf-8"))
    ser.flush()
    print(f"[WIFI] Sent wifi_set for SSID '{ssid}'", flush=True)
    return True


def handle_esp_command(cmd_line: str, monitor: AgentCIMonitor, ser=None):
    """Processes inbound action commands received from ESP32 touch button presses."""
    try:
        data = json.loads(cmd_line.strip())

        # Radio telemetry frames carry "type", not "cmd" — log and return.
        pkt_type = data.get("type")
        if pkt_type in ("wifi_status", "ble_status"):
            print(
                f"[RADIO] {pkt_type}: state={data.get('state')} "
                f"ssid={data.get('ssid', '')} ip={data.get('ip', '')} "
                f"host={data.get('host', '')}",
                flush=True,
            )
            return

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
        elif cmd == "wifi_sync":
            # Zero-Typing Companion Sync: the user tapped [Sync from Mac].
            if ser is None:
                print(
                    "[WIFI] wifi_sync received but no serial handle available",
                    flush=True,
                )
            else:
                handle_wifi_sync_request(ser, interactive=False)
        elif cmd == "focus_agent":
            print("[CMD] Focusing active agent application...", flush=True)
            try:
                script = 'tell application "Antigravity" to activate'
                subprocess.Popen(
                    ["osascript", "-e", script],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except Exception:
                pass
    except Exception as e:
        print(f"[CMD] Failed to process command '{cmd_line}': {e}", flush=True)


def run_wifi_sync_once() -> int:
    """`--wifi-sync`: explicit one-shot provisioning from the terminal."""
    port = find_esp_port()
    if not port:
        print("No ESP32-S3 found (/dev/cu.usbmodem*). Plug the companion in first.")
        return 1
    with serial.Serial(port, 115200, timeout=2) as ser:
        if not handle_wifi_sync_request(ser, interactive=True):
            return 1
        # Watch the device's wifi_status telemetry for the join result.
        deadline = time.monotonic() + 20.0
        while time.monotonic() < deadline:
            line = ser.readline().decode("utf-8", errors="ignore").strip()
            if not (line.startswith("{") and line.endswith("}")):
                continue
            try:
                data = json.loads(line)
            except ValueError:
                continue
            if data.get("type") == "wifi_status":
                state = data.get("state")
                print(f"[WIFI] Device: state={state} ip={data.get('ip', '')}")
                if state == "connected":
                    return 0
        print(
            "[WIFI] Timed out waiting for join confirmation; check the device screen."
        )
        return 1


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
                    initial_profile = get_profile_for_app(
                        initial_bundle, detector.confirmed_app_name
                    )
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
                        "time": now_str,
                    }
                    ser.write((json.dumps(stats_payload) + "\n").encode("utf-8"))
                    ser.flush()
                    last_stats_time = time.monotonic()
                    print(f"[INIT] Sent initial stats: {stats_payload}", flush=True)

                    # 3. Send initial agent_ci payload immediately on connect
                    initial_agent_ci = monitor.get_payload()
                    ser.write(
                        serialize_agent_ci_packet(initial_agent_ci).encode("utf-8")
                    )
                    ser.flush()
                    last_agent_ci_time = time.monotonic()
                    last_agent_state = initial_agent_ci.get("agent", {}).get("state")
                    last_ci_status = initial_agent_ci.get("ci", {}).get("status")
                    print(
                        f"[INIT] Sent initial agent/CI: agent={last_agent_state}, ci={last_ci_status}",
                        flush=True,
                    )

                    while True:
                        now = time.monotonic()

                        # 1. Frontmost App Check (runs every ~50ms)
                        new_bundle = detector.update()
                        if new_bundle is not None:
                            profile = get_profile_for_app(
                                new_bundle, detector.confirmed_app_name
                            )
                            if profile["app"] != last_sent_app_name:
                                payload = build_app_payload(profile)
                                ser.write((json.dumps(payload) + "\n").encode("utf-8"))
                                ser.flush()
                                last_sent_app_name = profile["app"]
                                print(
                                    f"[APP] Focus changed -> {last_sent_app_name} ({new_bundle})",
                                    flush=True,
                                )

                        # 2. Telemetry Check (1.0 Hz)
                        if now - last_stats_time >= 1.0:
                            cpu = get_cpu_percent()
                            ram = get_ram_percent()
                            now_str = datetime.now().strftime("%I:%M %p")

                            stats_payload = {
                                "type": "stats",
                                "cpu": cpu,
                                "ram": ram,
                                "time": now_str,
                            }
                            ser.write(
                                (json.dumps(stats_payload) + "\n").encode("utf-8")
                            )
                            ser.flush()
                            last_stats_time = now

                        # 3. Agent & CI Status Check (every 5.0s or immediate on state transition)
                        current_agent_ci = monitor.get_payload()
                        cur_agent_state = current_agent_ci.get("agent", {}).get("state")
                        cur_ci_status = current_agent_ci.get("ci", {}).get("status")
                        state_changed = (cur_agent_state != last_agent_state) or (
                            cur_ci_status != last_ci_status
                        )

                        if (now - last_agent_ci_time >= 5.0) or state_changed:
                            ser.write(
                                serialize_agent_ci_packet(current_agent_ci).encode(
                                    "utf-8"
                                )
                            )
                            ser.flush()
                            last_agent_ci_time = now
                            last_agent_state = cur_agent_state
                            last_ci_status = cur_ci_status
                            if state_changed:
                                print(
                                    f"[AGENT_CI] State transition -> agent={cur_agent_state}, ci={cur_ci_status}",
                                    flush=True,
                                )

                        # 4. Check Inbound Serial Commands from ESP32 Touch Buttons
                        while ser.in_waiting > 0:
                            line = (
                                ser.readline().decode("utf-8", errors="ignore").strip()
                            )
                            if line.startswith("{") and line.endswith("}"):
                                handle_esp_command(line, monitor, ser)

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
    if "--wifi-sync" in sys.argv[1:]:
        sys.exit(run_wifi_sync_once())
    main()
