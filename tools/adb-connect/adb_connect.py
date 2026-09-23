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

"""Zero-touch Android Wireless Debugging auto-discovery and connection tool.

Discovers active Android Wireless Debugging (ADB over TLS) instances via mDNS /
Bonjour (_adb-tls-connect._tcp), extracts dynamic port and device metadata,
resolves reachability (preferring fixed Tailscale mesh IP, falling back to LAN IP),
and connects adb automatically without manual port entry.
"""

import argparse
import json
import re
import socket
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Tuple


def run_command(
    cmd: List[str], timeout: Optional[float] = None
) -> Tuple[int, str, str]:
    """Execute a command and return (exit_code, stdout, stderr)."""
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "Command timed out"
    except FileNotFoundError as e:
        return 127, "", str(e)


def browse_mdns_instances(timeout_s: float = 1.5) -> List[str]:
    """Browse local network for _adb-tls-connect._tcp mDNS service instances."""
    try:
        proc = subprocess.Popen(
            ["dns-sd", "-B", "_adb-tls-connect._tcp", "local."],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(timeout_s)
        proc.terminate()
        stdout, _ = proc.communicate()
    except (FileNotFoundError, Exception):
        return []

    instances: List[str] = []
    for line in stdout.splitlines():
        line_str = line.strip()
        if (
            not line_str
            or line_str.startswith("Browsing for")
            or "STARTING" in line_str
            or "Timestamp" in line_str
            or line_str.startswith("DATE:")
        ):
            continue
        if "_adb-tls-connect._tcp." in line_str:
            parts = line_str.split("_adb-tls-connect._tcp.")
            if len(parts) > 1 and parts[1].strip():
                instance = parts[1].strip()
                if instance not in instances:
                    instances.append(instance)
    return instances


def resolve_mdns_instance(
    instance_name: str, timeout_s: float = 1.2
) -> Optional[Dict[str, Any]]:
    """Resolve an mDNS instance to retrieve its hostname, port, and TXT attributes."""
    try:
        proc = subprocess.Popen(
            ["dns-sd", "-L", instance_name, "_adb-tls-connect._tcp", "local."],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(timeout_s)
        proc.terminate()
        stdout, _ = proc.communicate()
    except (FileNotFoundError, Exception):
        return None

    # Matches: can be reached at <hostname>:<port>
    reach_match = re.search(r"can be reached at (.*?):(\d+)", stdout)
    if not reach_match:
        return None

    hostname = reach_match.group(1).rstrip(".") + "."
    port = int(reach_match.group(2))

    # Parse TXT records: key=value (supporting escaped spaces like "Pixel\ 11\ Pro")
    attrs: Dict[str, str] = {}
    for match in re.finditer(r"([a-zA-Z0-9_-]+)=((?:\\.|[^\s])+)", stdout):
        k, v = match.group(1), match.group(2)
        attrs[k] = v.replace(r"\ ", " ").strip()

    given_name = attrs.get("given_name")
    return {
        "instance": instance_name,
        "hostname": hostname,
        "port": port,
        "serial": attrs.get("serial", ""),
        "name": attrs.get("name", ""),
        "given_name": given_name or attrs.get("name", ""),
        "api": attrs.get("api", ""),
    }


def resolve_hostname_ipv4(hostname: str, timeout_s: float = 1.2) -> Optional[str]:
    """Resolve a .local hostname to IPv4 address using dns-sd -G v4."""
    try:
        proc = subprocess.Popen(
            ["dns-sd", "-G", "v4", hostname],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(timeout_s)
        proc.terminate()
        stdout, _ = proc.communicate()
    except (FileNotFoundError, Exception):
        stdout = ""

    # Parse IP from table: Timestamp A/R Flags IF Hostname Address TTL
    for line in stdout.splitlines():
        parts = line.strip().split()
        if len(parts) >= 6:
            candidate_ip = parts[5]
            if re.match(r"^\d+\.\d+\.\d+\.\d+$", candidate_ip):
                return candidate_ip

    # Fallback to socket gethostbyname
    try:
        clean_host = hostname.rstrip(".")
        return socket.gethostbyname(clean_host)
    except Exception:
        return None


def get_tailscale_android_peers() -> List[Dict[str, Any]]:
    """Inspect Tailscale status to find online Android nodes."""
    code, stdout, _ = run_command(["tailscale", "status", "--json"], timeout=2.0)
    if code != 0 or not stdout:
        return []

    try:
        data = json.loads(stdout)
    except Exception:
        return []

    peers: List[Dict[str, Any]] = []
    peer_dict = data.get("Peer", {})
    for node in peer_dict.values():
        if node.get("OS", "").lower() == "android":
            ips = [ip for ip in node.get("TailscaleIPs", []) if ":" not in ip]
            peers.append(
                {
                    "hostname": node.get("HostName", ""),
                    "dns_name": node.get("DNSName", "").rstrip("."),
                    "tailscale_ip": ips[0] if ips else None,
                    "cur_addr": node.get("CurAddr", ""),
                    "online": node.get("Online", False),
                    "active": node.get("Active", False),
                }
            )
    return peers


def find_target_device(
    device_filter: Optional[str] = None,
    prefer_tailscale: bool = True,
    scan_timeout: float = 1.5,
) -> Optional[Dict[str, Any]]:
    """Scan and resolve target Android wireless debugging device."""
    instances = browse_mdns_instances(timeout_s=scan_timeout)
    if not instances:
        return None

    resolved_devices: List[Dict[str, Any]] = []
    for inst in instances:
        dev = resolve_mdns_instance(inst)
        if dev:
            resolved_devices.append(dev)

    if not resolved_devices:
        return None

    # Apply filter if provided
    selected_device = None
    if device_filter:
        filt = device_filter.lower()
        for dev in resolved_devices:
            if (
                filt in dev["instance"].lower()
                or filt in dev["given_name"].lower()
                or filt in dev["serial"].lower()
                or filt in dev["name"].lower()
            ):
                selected_device = dev
                break
    else:
        selected_device = resolved_devices[-1]

    if not selected_device:
        return None

    # Resolve connection IP
    ts_peers = get_tailscale_android_peers() if prefer_tailscale else []
    target_ip = None
    connection_type = "mdns_lan"

    if prefer_tailscale and ts_peers:
        # Match Tailscale peer to device name
        for peer in ts_peers:
            peer_name = peer["hostname"].lower()
            dev_name = selected_device["given_name"].lower()
            dev_model = selected_device["name"].lower()
            if (
                dev_name in peer_name
                or peer_name in dev_name
                or dev_model in peer_name
                or peer.get("active", False)
            ):
                if peer["tailscale_ip"]:
                    target_ip = peer["tailscale_ip"]
                    connection_type = "tailscale"
                    break

    if not target_ip:
        lan_ip = resolve_hostname_ipv4(selected_device["hostname"])
        if lan_ip:
            target_ip = lan_ip
            connection_type = "lan_ip"
        else:
            target_ip = selected_device["hostname"]
            connection_type = "hostname"

    selected_device["target_ip"] = target_ip
    selected_device["connection_type"] = connection_type
    selected_device["endpoint"] = f"{target_ip}:{selected_device['port']}"
    return selected_device


def get_adb_attached_devices() -> List[Dict[str, str]]:
    """Query `adb devices -l` and return list of attached devices."""
    code, stdout, _ = run_command(["adb", "devices", "-l"], timeout=3.0)
    if code != 0:
        return []

    devices = []
    for line in stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("List of devices"):
            continue
        parts = line.split()
        if len(parts) >= 2:
            dev_info = {"id": parts[0], "status": parts[1]}
            for prop in parts[2:]:
                if ":" in prop:
                    k, v = prop.split(":", 1)
                    dev_info[k] = v
            devices.append(dev_info)
    return devices


def connect_device(
    target_device: Dict[str, Any],
    set_tcpip: Optional[int] = None,
) -> Dict[str, Any]:
    """Connect adb to target device endpoint."""
    endpoint = target_device["endpoint"]
    code, stdout, stderr = run_command(["adb", "connect", endpoint], timeout=5.0)

    success = (code == 0) and (
        "connected to" in stdout.lower() or "already connected" in stdout.lower()
    )
    result = {
        "success": success,
        "endpoint": endpoint,
        "device": target_device["given_name"] or target_device["name"],
        "serial": target_device["serial"],
        "connection_type": target_device["connection_type"],
        "port": target_device["port"],
        "stdout": stdout.strip(),
        "stderr": stderr.strip(),
    }

    if success and set_tcpip:
        tcpip_code, tcpip_out, tcpip_err = run_command(
            ["adb", "-s", endpoint, "tcpip", str(set_tcpip)], timeout=5.0
        )
        result["tcpip_mode"] = {
            "requested_port": set_tcpip,
            "success": tcpip_code == 0,
            "stdout": tcpip_out.strip(),
            "stderr": tcpip_err.strip(),
        }

    return result


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Auto-discover Android Wireless Debugging port and connect adb.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "-d",
        "--device",
        type=str,
        help="Filter by device name, model, or serial substring.",
    )
    parser.add_argument(
        "--ip",
        type=str,
        help="Override target IP address instead of auto-resolving.",
    )
    parser.add_argument(
        "--no-tailscale",
        action="store_true",
        help="Disable Tailscale IP preference; use direct local network IP.",
    )
    parser.add_argument(
        "--disconnect-first",
        action="store_true",
        help="Run `adb disconnect` before attempting to discover and connect.",
    )
    parser.add_argument(
        "--tcpip",
        nargs="?",
        const=5555,
        type=int,
        help="Switch ADB to static TCP/IP mode on specified port (default: 5555) once connected.",
    )
    parser.add_argument(
        "--status",
        action="store_true",
        help="Show currently connected ADB devices and exit.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output structured JSON instead of human-readable text.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=1.5,
        help="mDNS discovery timeout in seconds.",
    )

    args = parser.parse_args()

    if args.status:
        devices = get_adb_attached_devices()
        if args.json:
            print(json.dumps({"devices": devices}, indent=2))
        else:
            if not devices:
                print("No adb devices currently attached.")
            else:
                print(f"Attached adb devices ({len(devices)}):")
                for d in devices:
                    print(
                        f"  • {d['id']} [{d['status']}] model:{d.get('model', 'unknown')}"
                    )
        return 0

    if args.disconnect_first:
        run_command(["adb", "disconnect"], timeout=2.0)

    if not args.json:
        print("Scanning local network for Android Wireless Debugging (mDNS)...")

    target = find_target_device(
        device_filter=args.device,
        prefer_tailscale=not args.no_tailscale,
        scan_timeout=args.timeout,
    )

    if not target:
        msg = "No Android Wireless Debugging instances discovered via mDNS."
        if args.json:
            print(json.dumps({"success": False, "error": msg}))
        else:
            print(f"Error: {msg}", file=sys.stderr)
            print(
                "Ensure Wireless Debugging is toggled ON in Developer Options.",
                file=sys.stderr,
            )
        return 1

    if args.ip:
        target["target_ip"] = args.ip
        target["endpoint"] = f"{args.ip}:{target['port']}"
        target["connection_type"] = "manual_override"

    if not args.json:
        dev_label = target["given_name"] or target["name"] or "Android Device"
        print(
            f"Found: {dev_label} (port {target['port']}, via {target['connection_type']})"
        )
        print(f"Connecting adb to {target['endpoint']}...")

    result = connect_device(target, set_tcpip=args.tcpip)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if result["success"]:
            print(f"✓ {result['stdout']}")
            if "tcpip_mode" in result:
                tcp = result["tcpip_mode"]
                if tcp["success"]:
                    print(
                        f"✓ Restarted adbd in TCP/IP mode on port {tcp['requested_port']}."
                    )
                else:
                    print(
                        f"⚠ Failed to switch to TCP/IP mode: {tcp['stderr']}",
                        file=sys.stderr,
                    )
        else:
            print(
                f"✗ Failed to connect: {result['stderr'] or result['stdout']}",
                file=sys.stderr,
            )

    return 0 if result["success"] else 2


if __name__ == "__main__":
    sys.exit(main())
