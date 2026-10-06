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
"""Out-of-band power management tool for bare-metal host `fedora` (Intel NUC 12 Extreme).

Host `fedora` is plugged into outlet 6 (alias: 'NUC12I9') of the TP-Link Kasa HS300
smart power strip at 192.168.86.48. This tool allows headless reboot / power-cycling
over the local LAN when `fedora` suffers an unrecoverable kernel lockup.
"""

import argparse
import json
import socket
import struct
import sys
import time

HS300_DEFAULT_IP = "192.168.86.48"
HS300_DEFAULT_PORT = 9999
OUTLET_ALIAS_MATCH = "NUC12I9"
OUTLET_DEFAULT_CHILD_ID = "8006E93B6F541837D78FE0E0D9E0DAD62338476A05"


def encrypt(string: str) -> bytes:
    key = 171
    result = struct.pack(">I", len(string))
    for char in string.encode("utf-8"):
        a = key ^ char
        key = a
        result += bytes([a])
    return result


def decrypt(data: bytes) -> str:
    key = 171
    result = []
    for byte in data:
        a = key ^ byte
        key = byte
        result.append(a)
    return bytes(result).decode("utf-8", errors="replace")


def send_kasa_command(ip: str, cmd_dict: dict, port: int = HS300_DEFAULT_PORT) -> dict:
    cmd_str = json.dumps(cmd_dict)
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect((ip, port))
        s.sendall(encrypt(cmd_str))
        header = s.recv(4)
        if len(header) < 4:
            raise RuntimeError("Truncated response header from Kasa strip")
        total_len = struct.unpack(">I", header)[0]
        payload = bytearray()
        while len(payload) < total_len:
            chunk = s.recv(min(4096, total_len - len(payload)))
            if not chunk:
                break
            payload.extend(chunk)
        return json.loads(decrypt(payload))
    finally:
        s.close()


def find_child_id(ip: str) -> str:
    sysinfo = send_kasa_command(ip, {"system": {"get_sysinfo": {}}})
    children = sysinfo.get("system", {}).get("get_sysinfo", {}).get("children", [])
    for child in children:
        if OUTLET_ALIAS_MATCH.lower() in child.get("alias", "").lower():
            return child["id"]
    return OUTLET_DEFAULT_CHILD_ID


def get_relay_state(ip: str, child_id: str) -> int:
    sysinfo = send_kasa_command(ip, {"system": {"get_sysinfo": {}}})
    children = sysinfo.get("system", {}).get("get_sysinfo", {}).get("children", [])
    for child in children:
        if child.get("id") == child_id or OUTLET_ALIAS_MATCH.lower() in child.get("alias", "").lower():
            return child.get("state", 0)
    return 0


def set_relay_state(ip: str, child_id: str, state: int) -> dict:
    cmd = {
        "context": {"child_ids": [child_id]},
        "system": {"set_relay_state": {"state": state}},
    }
    return send_kasa_command(ip, cmd)


def main():
    parser = argparse.ArgumentParser(description="Power-cycle host fedora via Kasa HS300 power strip.")
    parser.add_argument("--ip", default=HS300_DEFAULT_IP, help="IP of Kasa HS300 power strip")
    parser.add_argument("--status", action="store_true", help="Print current outlet power state")
    parser.add_argument("--cycle", action="store_true", help="Power-cycle outlet (OFF, wait, ON)")
    parser.add_argument("--off", action="store_true", help="Turn outlet OFF")
    parser.add_argument("--on", action="store_true", help="Turn outlet ON")
    parser.add_argument("--wait", type=int, default=8, help="Seconds to wait between OFF and ON (default: 8)")
    args = parser.parse_args()

    child_id = find_child_id(args.ip)

    if args.status:
        state = get_relay_state(args.ip, child_id)
        status_str = "ON" if state == 1 else "OFF"
        print(f"Outlet '{OUTLET_ALIAS_MATCH}' ({child_id}): {status_str}")
        sys.exit(0)

    if args.off:
        print(f"Turning OFF outlet '{OUTLET_ALIAS_MATCH}' ({child_id})...")
        set_relay_state(args.ip, child_id, 0)
        print("Done.")
        sys.exit(0)

    if args.on:
        print(f"Turning ON outlet '{OUTLET_ALIAS_MATCH}' ({child_id})...")
        set_relay_state(args.ip, child_id, 1)
        print("Done.")
        sys.exit(0)

    # Default to power-cycle if --cycle or no explicit action was specified
    print(f"Power-cycling host 'fedora' via outlet '{OUTLET_ALIAS_MATCH}' ({args.ip})...")
    print("Cutting power (relay state -> 0)...")
    set_relay_state(args.ip, child_id, 0)
    print(f"Waiting {args.wait} seconds...")
    time.sleep(args.wait)
    print("Restoring power (relay state -> 1)...")
    set_relay_state(args.ip, child_id, 1)
    print("Power-cycle complete. Host 'fedora' will reboot and rejoin the cluster automatically.")


if __name__ == "__main__":
    main()
