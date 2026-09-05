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

import argparse
import glob
import json
import os
import socket
import subprocess
import sys
import time
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
# Untethered transport: mDNS discovery + UDP telemetry (Milestone 6)
# ---------------------------------------------------------------------------
# The firmware speaks one wire protocol over two transports (docs/protocol.md).
# USB CDC stays the preferred link -- it is lower latency and needs no
# discovery -- and the UDP path takes over whenever the cable is out.

MDNS_HOSTNAME = "vitruvian-companion.local"
NET_TELEMETRY_PORT = 8266

# The device answers whichever socket addressed it, so one unconnected UDP
# socket serves both directions.
UDP_RECV_BUFSIZE = 2048

# The firmware pushes wifi_status/ble_status every 5 s once it has a client.
# Three missed reports means the device is gone (asleep, re-IP'd, off-net) and
# the session is torn down so discovery can run again.
WIFI_LIVENESS_TIMEOUT_S = 20.0


def resolve_companion_host(hint=None, hostname=MDNS_HOSTNAME):
    """Resolves the companion's IPv4 address, or None if it cannot be found.

    `hint` (--wifi-host) wins and may itself be a name or a literal address.
    Otherwise the mDNS name the firmware publishes is resolved through the OS
    resolver -- on macOS that is mDNSResponder, so no extra dependency is
    needed for the common case.
    """
    target = hint or hostname
    try:
        return socket.gethostbyname(target)
    except (socket.gaierror, OSError):
        pass

    # A hint is an explicit instruction: do not silently fall back to discovery.
    if hint:
        return None

    return discover_companion_via_zeroconf()


def discover_companion_via_zeroconf(
    timeout: float = 3.0, service: str = "_vitruvian._tcp.local."
):
    """Browses for the `_vitruvian._tcp` service if python-zeroconf is present.

    Optional by design: the daemon's declared dependencies stay at pyserial, and
    this is only reached on hosts whose resolver does not do mDNS itself.
    """
    try:
        from zeroconf import ServiceBrowser, Zeroconf
    except ImportError:
        return None

    found = []

    class _Listener:
        def add_service(self, zc, type_, name):
            info = zc.get_service_info(type_, name, timeout=int(timeout * 1000))
            if info and info.addresses:
                found.append(socket.inet_ntoa(info.addresses[0]))

        def update_service(self, zc, type_, name):
            pass

        def remove_service(self, zc, type_, name):
            pass

    zc = Zeroconf()
    try:
        ServiceBrowser(zc, service, _Listener())
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and not found:
            time.sleep(0.1)
    finally:
        zc.close()
    return found[0] if found else None


class SerialTransport:
    """USB CDC link. Wraps a pyserial handle in the transport interface."""

    kind = "usb"

    def __init__(self, ser, port: str):
        self._ser = ser
        self.port = port
        self.description = f"USB CDC {port}"

    def write(self, data: bytes):
        self._ser.write(data)

    def flush(self):
        self._ser.flush()

    def send_packet(self, payload: dict):
        self.write((json.dumps(payload) + "\n").encode("utf-8"))
        self.flush()

    def read_lines(self):
        lines = []
        while self._ser.in_waiting > 0:
            line = self._ser.readline().decode("utf-8", errors="ignore").strip()
            if line:
                lines.append(line)
        return lines

    def close(self):
        pass  # the caller's `with serial.Serial(...)` owns the handle


class UdpTransport:
    """Untethered link: newline-framed JSON datagrams to the device's :8266.

    Non-blocking so the caller's 20 Hz loop is never stalled by a quiet device;
    datagrams from anywhere other than the companion are dropped, so a stray
    broadcast on the LAN cannot be mistaken for a button press.
    """

    kind = "wifi"

    def __init__(self, host: str, port: int = NET_TELEMETRY_PORT):
        self.host = host
        self.port = port
        self.description = f"Wi-Fi UDP {host}:{port}"
        self._addr = (host, port)
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setblocking(False)
        self._sock.bind(("", 0))

    @property
    def local_port(self) -> int:
        return self._sock.getsockname()[1]

    def write(self, data: bytes):
        self._sock.sendto(data, self._addr)

    def flush(self):
        pass  # datagrams leave on send

    def send_packet(self, payload: dict):
        self.write((json.dumps(payload) + "\n").encode("utf-8"))

    def read_lines(self):
        lines = []
        while True:
            try:
                data, addr = self._sock.recvfrom(UDP_RECV_BUFSIZE)
            except (BlockingIOError, InterruptedError):
                break
            except OSError:
                break
            if addr[0] != self.host:
                continue
            for line in data.decode("utf-8", errors="ignore").splitlines():
                line = line.strip()
                if line:
                    lines.append(line)
        return lines

    def close(self):
        try:
            self._sock.close()
        except OSError:
            pass


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


def handle_esp_command(cmd_line: str, monitor: AgentCIMonitor, link=None):
    """Processes inbound action commands received from ESP32 touch button presses.

    `link` is whichever transport the command arrived on -- a SerialTransport, a
    UdpTransport, or a raw pyserial handle from --wifi-sync. Only write()/flush()
    are used, so the three are interchangeable here and a button press is
    answered on the channel that carried it.
    """
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
            if link is None:
                print(
                    "[WIFI] wifi_sync received but no transport available",
                    flush=True,
                )
            else:
                handle_wifi_sync_request(link, interactive=False)
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
        elif cmd == "hid_action":
            mod = int(data.get("mod", 0))
            key = int(data.get("key", 0))
            cons = int(data.get("cons", 0))
            print(
                f"[CMD] Executing untethered HID action over Wi-Fi: mod={mod}, key={key}, cons={cons}",
                flush=True,
            )
            execute_mac_shortcut(mod, key, cons)
    except Exception as e:
        print(f"[CMD] Failed to process command '{cmd_line}': {e}", flush=True)


def execute_mac_shortcut(mod: int, key: int, cons: int):
    """Executes keyboard / consumer actions on macOS via AppleScript."""
    # Consumer control actions
    if cons != 0:
        if cons in (0xE2, 226, 1):  # Mute toggle
            script = "set volume with output muted (not (output muted of (get volume settings)))"
            try:
                subprocess.Popen(
                    ["osascript", "-e", script],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except Exception:
                pass
            return
        if cons in (0xE9, 233):  # Volume Up
            script = "set volume output volume ((output volume of (get volume settings)) + 6)"
            try:
                subprocess.Popen(
                    ["osascript", "-e", script],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except Exception:
                pass
            return
        if cons in (0xEA, 234):  # Volume Down
            script = "set volume output volume ((output volume of (get volume settings)) - 6)"
            try:
                subprocess.Popen(
                    ["osascript", "-e", script],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except Exception:
                pass
            return

    # Modifiers: MOD_CTRL=1, MOD_SHIFT=2, MOD_ALT=4, MOD_CMD=8
    modifiers = []
    if mod & 1:
        modifiers.append("control down")
    if mod & 2:
        modifiers.append("shift down")
    if mod & 4:
        modifiers.append("option down")
    if mod & 8:
        modifiers.append("command down")

    using_clause = ""
    if len(modifiers) == 1:
        using_clause = f" using {modifiers[0]}"
    elif len(modifiers) > 1:
        using_clause = f" using {{{', '.join(modifiers)}}}"

    # Key codes mapping:
    # 218: Up Arrow (126), 217: Down Arrow (125), 216: Left Arrow (123), 215: Right Arrow (124)
    # 204: F11 (103), 32: Space (49), 176: Return (36), 177: Escape (53), 178: Backspace (51), 179: Tab (48)
    key_map = {
        218: 126,  # Up Arrow (Mission Control)
        217: 125,  # Down Arrow
        216: 123,  # Left Arrow (Space Left)
        215: 124,  # Right Arrow (Space Right)
        204: 103,  # F11 (Show Desktop)
        32: 49,  # Space (Spotlight)
        176: 36,  # Return
        177: 53,  # Escape
        178: 51,  # Backspace
        179: 48,  # Tab
    }

    if key in key_map:
        code = key_map[key]
        script = f'tell application "System Events" to key code {code}{using_clause}'
    elif 32 <= key <= 126:
        char = chr(key)
        if char == '"':
            char = '\\"'
        script = f'tell application "System Events" to keystroke "{char}"{using_clause}'
    else:
        return

    try:
        subprocess.Popen(
            ["osascript", "-e", script],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception as e:
        print(f"[CMD] Error executing shortcut '{script}': {e}", flush=True)


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


class StreamSession:
    """One connected session over a single transport.

    Holds the cadence state (last-sent timestamps and last-sent values) so the
    USB and Wi-Fi paths run byte-identical logic -- the only difference between
    them is which object `transport` is.
    """

    STATS_INTERVAL_S = 1.0
    AGENT_CI_INTERVAL_S = 5.0
    USB_RECHECK_INTERVAL_S = 2.0

    def __init__(self, transport, detector, monitor, allow_usb_takeover: bool = True):
        self.transport = transport
        self.detector = detector
        self.monitor = monitor
        # False under --wifi-only: without this the session would tear itself
        # down every 2 s on a machine that happens to have the cable plugged in,
        # only for open_transport() to hand back the same Wi-Fi link.
        self.allow_usb_takeover = allow_usb_takeover
        self.last_stats_time = 0.0
        self.last_agent_ci_time = 0.0
        self.last_sent_app_name = None
        self.last_agent_state = None
        self.last_ci_status = None
        self.last_inbound_time = time.monotonic()
        self.last_usb_check = time.monotonic()

    # -- outbound ----------------------------------------------------------
    def send_app_profile(self, force: bool = False):
        bundle = self.detector.update(force_immediate=force)
        if bundle is None and not force:
            return
        profile = get_profile_for_app(bundle, self.detector.confirmed_app_name)
        if not force and profile["app"] == self.last_sent_app_name:
            return
        self.transport.send_packet(build_app_payload(profile))
        self.last_sent_app_name = profile["app"]
        print(
            f"[APP] Focus -> {self.last_sent_app_name} ({bundle}) via {self.transport.kind}",
            flush=True,
        )

    def send_stats(self):
        payload = {
            "type": "stats",
            "cpu": get_cpu_percent(),
            "ram": get_ram_percent(),
            "time": datetime.now().strftime("%I:%M %p"),
        }
        self.transport.send_packet(payload)
        self.last_stats_time = time.monotonic()

    def send_agent_ci(self, force: bool = False):
        payload = self.monitor.get_payload()
        agent_state = payload.get("agent", {}).get("state")
        ci_status = payload.get("ci", {}).get("status")
        changed = (agent_state != self.last_agent_state) or (
            ci_status != self.last_ci_status
        )
        due = (time.monotonic() - self.last_agent_ci_time) >= self.AGENT_CI_INTERVAL_S

        if not (force or changed or due):
            return
        self.transport.write(serialize_agent_ci_packet(payload).encode("utf-8"))
        self.transport.flush()
        self.last_agent_ci_time = time.monotonic()
        self.last_agent_state = agent_state
        self.last_ci_status = ci_status
        if changed and not force:
            print(
                f"[AGENT_CI] State transition -> agent={agent_state}, ci={ci_status}",
                flush=True,
            )

    # -- session -----------------------------------------------------------
    def prime(self):
        """Sends one of everything so the decks are populated on connect."""
        self.send_app_profile(force=True)
        self.send_stats()
        self.send_agent_ci(force=True)
        print(
            f"[INIT] Primed {self.transport.description}: app={self.last_sent_app_name}, "
            f"agent={self.last_agent_state}, ci={self.last_ci_status}",
            flush=True,
        )

    def pump(self) -> bool:
        """One iteration. Returns False when the session should be torn down."""
        now = time.monotonic()

        self.send_app_profile()
        if now - self.last_stats_time >= self.STATS_INTERVAL_S:
            self.send_stats()
        self.send_agent_ci()

        for line in self.transport.read_lines():
            self.last_inbound_time = time.monotonic()
            if line.startswith("{") and line.endswith("}"):
                handle_esp_command(line, self.monitor, self.transport)

        if self.transport.kind == "wifi":
            # UDP sends never fail loudly, so liveness comes from the device's
            # own 5 s radio telemetry rather than from write errors.
            if time.monotonic() - self.last_inbound_time > WIFI_LIVENESS_TIMEOUT_S:
                print(
                    f"[NET] No reply from {self.transport.host} for "
                    f"{WIFI_LIVENESS_TIMEOUT_S:.0f}s; re-discovering",
                    flush=True,
                )
                return False
            # Plugging the cable back in should hand the link straight back to
            # USB rather than waiting for the Wi-Fi session to fail.
            if (
                self.allow_usb_takeover
                and now - self.last_usb_check >= self.USB_RECHECK_INTERVAL_S
            ):
                self.last_usb_check = now
                if find_esp_port():
                    print(
                        "[NET] USB cable detected; switching back to the wired link",
                        flush=True,
                    )
                    return False

        return True


def run_session(transport, detector, monitor, allow_usb_takeover: bool = True) -> None:
    session = StreamSession(transport, detector, monitor, allow_usb_takeover)
    session.prime()
    while session.pump():
        time.sleep(0.05)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        prog="mac_stats_daemon",
        description="Streams macOS telemetry to the ESP32-S3 companion over USB CDC or Wi-Fi.",
    )
    parser.add_argument(
        "--wifi-host",
        metavar="HOST",
        help=f"Companion address or hostname; skips mDNS discovery of {MDNS_HOSTNAME}.",
    )
    parser.add_argument(
        "--wifi-port",
        type=int,
        default=NET_TELEMETRY_PORT,
        help=f"Companion UDP telemetry port (default: {NET_TELEMETRY_PORT}).",
    )
    parser.add_argument(
        "--usb-only",
        action="store_true",
        help="Never fall back to Wi-Fi; wait for the cable.",
    )
    parser.add_argument(
        "--wifi-only",
        action="store_true",
        help="Never use USB CDC, even when the cable is plugged in.",
    )
    parser.add_argument(
        "--wifi-sync",
        action="store_true",
        help="One-shot: beam this Mac's Wi-Fi credentials to a tethered companion and exit.",
    )
    return parser.parse_args(argv)


def open_transport(args):
    """Picks a link for this session: USB when the cable is in, else Wi-Fi.

    Returns (transport, cleanup) where `cleanup` is a context manager to close,
    or (None, None) when neither link is available right now.
    """
    if not args.wifi_only:
        port = find_esp_port()
        if port:
            ser = serial.Serial(port, 115200, timeout=1)
            return SerialTransport(ser, port), ser

    if args.usb_only:
        return None, None

    host = resolve_companion_host(args.wifi_host)
    if not host:
        return None, None

    transport = UdpTransport(host, args.wifi_port)
    return transport, transport


def main(argv=None):
    args = parse_args(argv)
    print("ESP32-S3 Mac Desktop Companion Daemon starting...")

    detector = FrontmostAppDetector(debounce_seconds=0.25)
    monitor = AgentCIMonitor(agent_interval=3.0, ci_interval=10.0)
    monitor.start()

    waiting_logged = False
    try:
        while True:
            transport, handle = open_transport(args)
            if transport is None:
                if not waiting_logged:
                    if args.usb_only:
                        target = "USB connection (/dev/cu.usbmodem*)"
                    elif args.wifi_only:
                        target = f"{args.wifi_host or MDNS_HOSTNAME} on the network"
                    else:
                        target = f"USB (/dev/cu.usbmodem*) or {args.wifi_host or MDNS_HOSTNAME}"
                    print(f"Waiting for the ESP32-S3 on {target}...")
                    waiting_logged = True
                time.sleep(1.5)
                continue

            waiting_logged = False
            print(f"Connected to ESP32-S3 over {transport.description}")
            try:
                run_session(
                    transport, detector, monitor, allow_usb_takeover=not args.wifi_only
                )
            except KeyboardInterrupt:
                raise
            except Exception as e:
                print(f"Connection lost: {e}")
                time.sleep(1.5)
            finally:
                transport.close()
                if handle is not transport:
                    handle.close()
    except KeyboardInterrupt:
        print("\nShutting down.")
    finally:
        monitor.stop()


if __name__ == "__main__":
    _args = parse_args()
    if _args.wifi_sync:
        sys.exit(run_wifi_sync_once())
    main()
