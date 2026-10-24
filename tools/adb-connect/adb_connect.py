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

"""Zero-touch Android Wireless Debugging auto-discovery, pairing, and connection tool.

Discovers active Android Wireless Debugging (ADB over TLS) instances via mDNS /
Bonjour (_adb-tls-connect._tcp and _adb._tcp), maps devices to known hardware
profiles and aliases (fold, pixel4, tv), avoids duplicate ADB transports when
mDNS auto-connect is active, supports zero-port mDNS pairing (--pair), and
connects adb automatically without manual port entry.
"""

import argparse
import json
import os
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


ADB_MDNS_SERVICES = (
    "_adb-tls-connect._tcp",
    "_adb._tcp",
)

ADB_PAIRING_SERVICE = "_adb-tls-pairing._tcp"

# Built-in declarative device catalog keyed by stable profile alias.
# Uses non-sensitive model/codename identifiers in-repo; optional per-machine
# serial overrides can be placed in ~/.config/vitruvian/adb-devices.json.
KNOWN_DEVICE_PROFILES: List[Dict[str, Any]] = [
    {
        "key": "fold",
        "display_name": "Pixel 11 Pro Fold",
        "role": "primary",
        "default": True,
        "codename": "yogi",
        "service_type": "_adb-tls-connect._tcp",
        "aliases": (
            "fold",
            "pixel-fold",
            "pixelfold",
            "pixel-11-pro-fold",
            "pixel11",
            "yogi",
            "primary",
        ),
        "model_patterns": (
            "pixel 11 pro fold",
            "pixel_11_pro_fold",
            "yogi",
        ),
    },
    {
        "key": "pixel4",
        "display_name": "Pixel 4 XL",
        "role": "secondary",
        "default": False,
        "codename": "coral",
        "service_type": "_adb-tls-connect._tcp",
        "aliases": (
            "pixel4",
            "pixel-4",
            "pixel-4-xl",
            "pixel4xl",
            "coral",
            "secondary",
            "test",
        ),
        "model_patterns": (
            "pixel 4 xl",
            "pixel_4_xl",
            "coral",
        ),
    },
    {
        "key": "tv",
        "display_name": "Living Room Sony TV",
        "role": "tv",
        "default": False,
        "codename": "bravia",
        "service_type": "_adb._tcp",
        "aliases": (
            "tv",
            "sony",
            "bravia",
            "sony-tv",
            "living-room-tv",
            "android-tv",
        ),
        "model_patterns": (
            "bravia",
            "living room sony tv",
        ),
    },
]

# Cache mapping instance_name -> discovered mDNS service type from the most recent browse
_INSTANCE_SERVICE_HINTS: Dict[str, str] = {}


class AmbiguousDeviceError(ValueError):
    """Raised when multiple devices match a filter or default selection is ambiguous."""

    def __init__(self, message: str, candidates: List[Dict[str, Any]]) -> None:
        super().__init__(message)
        self.candidates = candidates


def load_device_profiles(config_path: Optional[str] = None) -> List[Dict[str, Any]]:
    """Load built-in device profiles merged with optional ~/.config/vitruvian/adb-devices.json."""
    profiles = [dict(p) for p in KNOWN_DEVICE_PROFILES]
    path = config_path or os.path.expanduser("~/.config/vitruvian/adb-devices.json")
    if not os.path.isfile(path):
        return profiles

    try:
        with open(path, "r", encoding="utf-8") as f:
            user_data = json.load(f)
    except Exception as exc:
        print(
            f"Warning: ignoring invalid JSON in {path}: {exc}",
            file=sys.stderr,
        )
        return profiles

    entries = user_data.get("devices", []) if isinstance(user_data, dict) else user_data
    if not isinstance(entries, list):
        return profiles

    by_key = {p["key"]: p for p in profiles}
    extra_profiles: List[Dict[str, Any]] = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        raw_key = entry.get("key")
        if not isinstance(raw_key, str) or not raw_key.strip():
            continue
        k = raw_key.strip().lower()
        normalized = dict(entry)
        normalized["key"] = k
        if k in by_key:
            merged = dict(by_key[k])
            merged.update(normalized)
            by_key[k] = merged
        else:
            extra_profiles.append(normalized)

    return list(by_key.values()) + extra_profiles


def extract_serial_from_id(identifier: str) -> str:
    """Extract hardware serial from an mDNS instance or adb transport identifier."""
    if not identifier:
        return ""
    clean = identifier
    for suffix in ("._adb-tls-connect._tcp", "._adb._tcp", "._adb-tls-pairing._tcp"):
        if clean.endswith(suffix):
            clean = clean[: -len(suffix)]
            break
    if clean.startswith("adb-"):
        raw = clean[len("adb-") :]
        return raw.split("-")[0] if "-" in raw else raw
    return ""


def match_device_profile(
    dev: Dict[str, Any],
    profiles: Optional[List[Dict[str, Any]]] = None,
) -> Optional[Dict[str, Any]]:
    """Match a discovered or attached device dictionary to a known device profile.

    Performs a two-pass lookup:
      Pass 1: Exact hardware serial match across all profiles (so user-configured
              serials for a second device of the same model win over generic model names).
      Pass 2: Codename and model pattern match (respecting service_type constraints for TV).
    """
    catalog = profiles if profiles is not None else load_device_profiles()
    dev_serial = (
        dev.get("serial") or extract_serial_from_id(dev.get("instance", ""))
    ).lower()
    dev_codename = (dev.get("device") or dev.get("product") or "").lower()
    dev_svc = dev.get("service_type", "")
    haystack = " ".join(
        str(dev.get(field, ""))
        for field in ("given_name", "name", "model", "device", "product", "instance")
    ).lower()

    # Pass 1: Hardware serial match across all profiles
    if dev_serial:
        for prof in catalog:
            prof_serial = str(prof.get("serial", "")).lower()
            if prof_serial and prof_serial == dev_serial:
                return prof

    # Pass 2: Codename / model pattern match
    for prof in catalog:
        prof_svc = prof.get("service_type", "")
        if prof_svc == "_adb._tcp" and dev_svc and dev_svc != "_adb._tcp":
            continue

        prof_code = str(prof.get("codename", "")).lower()
        if prof_code and dev_codename and prof_code == dev_codename:
            return prof

        for pat in prof.get("model_patterns", ()):
            if pat.lower() in haystack:
                return prof

    return None


def enrich_device_with_profile(
    dev: Dict[str, Any],
    profiles: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Attach profile metadata (profile_key, role, aliases, is_default) to a device dict."""
    prof = match_device_profile(dev, profiles=profiles)
    if prof:
        dev["profile_key"] = prof["key"]
        dev["role"] = prof.get("role", "secondary")
        dev["is_default"] = bool(prof.get("default", False))
        dev["aliases"] = list(prof.get("aliases", ()))
        dev["codename"] = prof.get("codename", "")
        if not dev.get("name"):
            dev["name"] = prof.get("display_name", "")
        if not dev.get("given_name"):
            dev["given_name"] = prof.get("display_name", "")
    else:
        dev.setdefault("profile_key", "")
        dev.setdefault(
            "role", "tv" if dev.get("service_type") == "_adb._tcp" else "phone"
        )
        dev.setdefault("is_default", False)
        dev.setdefault("aliases", [])
        dev.setdefault("codename", dev.get("device", ""))
    return dev


def browse_mdns_instances(
    timeout_s: float = 1.5,
    service_types: Tuple[str, ...] = ADB_MDNS_SERVICES,
) -> List[str]:
    """Browse local network for ADB mDNS service instances (_adb-tls-connect._tcp and _adb._tcp)."""
    procs = []
    for svc in service_types:
        try:
            proc = subprocess.Popen(
                ["dns-sd", "-B", svc, "local."],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            procs.append((svc, proc))
        except Exception:
            continue

    if not procs:
        return []

    time.sleep(timeout_s)

    instances: List[str] = []
    for svc, proc in procs:
        try:
            proc.terminate()
            stdout, _ = proc.communicate()
        except Exception:
            continue
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
            tokens = line_str.split()
            if len(tokens) >= 2 and tokens[1] == "Rmv":
                continue
            for candidate_svc in (svc,) + tuple(s for s in service_types if s != svc):
                candidate_marker = f"{candidate_svc}."
                if candidate_marker in line_str:
                    parts = line_str.split(candidate_marker)
                    if len(parts) > 1 and parts[1].strip():
                        instance = parts[1].strip()
                        _INSTANCE_SERVICE_HINTS[instance] = candidate_svc
                        if instance not in instances:
                            instances.append(instance)
                    break
    return instances


def browse_androidtv_remote_names(timeout_s: float = 0.8) -> Dict[str, str]:
    """Map .local hostnames to friendly Android TV names via _androidtvremote2._tcp."""
    try:
        proc = subprocess.Popen(
            ["dns-sd", "-B", "_androidtvremote2._tcp", "local."],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(timeout_s)
        proc.terminate()
        stdout, _ = proc.communicate()
    except (FileNotFoundError, Exception):
        return {}

    tv_instances: List[str] = []
    for line in stdout.splitlines():
        if "_androidtvremote2._tcp." in line and "Add" in line:
            parts = line.split("_androidtvremote2._tcp.")
            if len(parts) > 1 and parts[1].strip():
                inst = parts[1].strip()
                if inst not in tv_instances:
                    tv_instances.append(inst)

    host_to_name: Dict[str, str] = {}
    for inst in tv_instances:
        try:
            lproc = subprocess.Popen(
                ["dns-sd", "-L", inst, "_androidtvremote2._tcp", "local."],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            time.sleep(0.5)
            lproc.terminate()
            lout, _ = lproc.communicate()
            reach_match = re.search(r"can be reached at (.*?):(\d+)", lout)
            if reach_match:
                host = reach_match.group(1).rstrip(".") + "."
                host_to_name[host.lower()] = inst
        except Exception:
            continue
    return host_to_name


def _lookup_mdns_service(
    instance_name: str, service_type: str, timeout_s: float
) -> str:
    """Run dns-sd -L for a specific mDNS service type and return stdout."""
    try:
        proc = subprocess.Popen(
            ["dns-sd", "-L", instance_name, service_type, "local."],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(timeout_s)
        proc.terminate()
        stdout, _ = proc.communicate()
        return stdout
    except (FileNotFoundError, Exception):
        return ""


def resolve_mdns_instance(
    instance_name: str,
    timeout_s: float = 1.2,
    service_hint: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    """Resolve an mDNS instance to retrieve its hostname, port, and TXT attributes."""
    hint = service_hint or _INSTANCE_SERVICE_HINTS.get(instance_name)
    all_services = ADB_MDNS_SERVICES + (ADB_PAIRING_SERVICE,)
    ordered_services = (
        (hint,) + tuple(s for s in ADB_MDNS_SERVICES if s != hint)
        if hint in all_services
        else ADB_MDNS_SERVICES
    )

    reach_match = None
    stdout = ""
    service_type = ordered_services[0]
    for svc in ordered_services:
        stdout = _lookup_mdns_service(instance_name, svc, timeout_s)
        reach_match = re.search(r"can be reached at (.*?):(\d+)", stdout)
        if reach_match:
            service_type = svc
            break

    if not reach_match:
        return None

    hostname = reach_match.group(1).rstrip(".") + "."
    port = int(reach_match.group(2))

    # Parse TXT records: key=value (supporting escaped spaces like "Pixel\ 11\ Pro")
    attrs: Dict[str, str] = {}
    for match in re.finditer(r"([a-zA-Z0-9_-]+)=((?:\\.|[^\s])+)", stdout):
        k, v = match.group(1), match.group(2)
        attrs[k] = v.replace(r"\ ", " ").strip()

    serial = attrs.get("serial", "")
    if not serial and instance_name.startswith("adb-"):
        # Extract serial from instance name (e.g. adb-24adbf003005591 or adb-98271FFBA007YW-OflOTi)
        serial = extract_serial_from_id(instance_name)

    name = attrs.get("name", "")
    given_name = attrs.get("given_name") or name

    if not given_name and service_type == "_adb._tcp":
        tv_names = browse_androidtv_remote_names(timeout_s=min(timeout_s, 0.8))
        tv_label = tv_names.get(hostname.lower(), "")
        if tv_label:
            given_name = tv_label
            name = name or tv_label

    return {
        "instance": instance_name,
        "hostname": hostname,
        "port": port,
        "serial": serial,
        "name": name,
        "given_name": given_name,
        "api": attrs.get("api", ""),
        "service_type": service_type,
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


def _device_sort_key(dev: Dict[str, Any]) -> Tuple[int, int, int, str]:
    """Deterministic ordering: (is_tls_phone, is_default, role_rank, serial)."""
    svc = dev.get("service_type", "_adb-tls-connect._tcp")
    is_tls = 0 if svc == "_adb-tls-connect._tcp" else 1
    is_default = 0 if dev.get("is_default", False) else 1
    role = dev.get("role", "")
    role_rank = {"primary": 0, "secondary": 1, "phone": 2, "tv": 3}.get(role, 2)
    serial = str(dev.get("serial", ""))
    return (is_tls, is_default, role_rank, serial)


def deduplicate_devices_by_serial(
    devices: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """Collapse multiple mDNS announcements for the same hardware serial (keeping the latest)."""
    by_key: Dict[str, Dict[str, Any]] = {}
    order: List[str] = []
    for idx, dev in enumerate(devices):
        serial = (
            dev.get("serial") or extract_serial_from_id(dev.get("instance", ""))
        ).lower()
        dedup_key = (
            f"serial:{serial}" if serial else f"idx:{idx}:{dev.get('instance', '')}"
        )
        if dedup_key not in by_key:
            order.append(dedup_key)
        by_key[dedup_key] = dev
    return [by_key[k] for k in order]


def select_target_device(
    resolved_devices: List[Dict[str, Any]],
    device_filter: Optional[str] = None,
    profiles: Optional[List[Dict[str, Any]]] = None,
) -> Optional[Dict[str, Any]]:
    """Select target device deterministically using known profiles, aliases, and service types.

    Raises AmbiguousDeviceError if multiple distinct devices match a filter or
    if multiple unrecognized phones are present with no default.
    """
    if not resolved_devices:
        return None

    catalog = profiles if profiles is not None else load_device_profiles()
    deduped = deduplicate_devices_by_serial(resolved_devices)
    enriched = [enrich_device_with_profile(dict(d), profiles=catalog) for d in deduped]

    if device_filter:
        filt = device_filter.strip().lower()
        # 1. Exact match on profile key, alias, codename, serial, or instance name
        exact_matches = [
            dev
            for dev in enriched
            if filt == dev.get("profile_key", "").lower()
            or filt in [a.lower() for a in dev.get("aliases", [])]
            or filt == dev.get("codename", "").lower()
            or (dev.get("serial") and filt == dev["serial"].lower())
            or filt == dev.get("instance", "").lower()
        ]
        if len(exact_matches) == 1:
            return exact_matches[0]
        if len(exact_matches) > 1:
            labels = [
                f"{d.get('given_name') or d.get('name') or d.get('instance')} "
                f"(--device {d.get('serial') or d.get('instance')})"
                for d in exact_matches
            ]
            raise AmbiguousDeviceError(
                f"Filter '{device_filter}' matched {len(exact_matches)} devices: "
                + ", ".join(labels)
                + ". Specify an unambiguous serial.",
                exact_matches,
            )

        # 2. Substring match across metadata fields
        sub_matches = []
        for dev in enriched:
            fields = (
                dev.get("instance", ""),
                dev.get("given_name", ""),
                dev.get("serial", ""),
                dev.get("name", ""),
                dev.get("hostname", ""),
                dev.get("profile_key", ""),
                " ".join(dev.get("aliases", [])),
            )
            if any(filt in f.lower() for f in fields if f):
                sub_matches.append(dev)

        if not sub_matches:
            return None
        if len(sub_matches) > 1:
            labels = [
                f"{d.get('given_name') or d.get('name') or d.get('instance')} "
                f"(--device {d.get('profile_key') or d.get('serial')})"
                for d in sub_matches
            ]
            raise AmbiguousDeviceError(
                f"Filter '{device_filter}' matched {len(sub_matches)} devices: "
                + ", ".join(labels)
                + ". Specify an unambiguous alias or serial.",
                sub_matches,
            )
        return sub_matches[0]

    # No filter provided:
    # Only auto-select _adb-tls-connect._tcp phones; never auto-select a legacy _adb._tcp TV.
    tls_phones = [
        d
        for d in enriched
        if d.get("service_type", "_adb-tls-connect._tcp") != "_adb._tcp"
    ]
    if not tls_phones:
        return None

    # 1. If a phone matches the primary/default profile, select it.
    defaults = [d for d in tls_phones if d.get("is_default", False)]
    if len(defaults) == 1:
        return defaults[0]

    # 2. If only one phone is present, select it.
    if len(tls_phones) == 1:
        return tls_phones[0]

    # 3. Multiple non-default phones: refuse and list candidates.
    tls_phones.sort(key=_device_sort_key)
    raise AmbiguousDeviceError(
        "Multiple Android phones discovered ("
        + ", ".join(
            f"{d.get('given_name') or d.get('name') or d.get('instance')} "
            f"[--device {d.get('profile_key') or d.get('serial')}]"
            for d in tls_phones
        )
        + "); pass --device <alias> or --all.",
        tls_phones,
    )


def resolve_device_endpoint(
    selected_device: Dict[str, Any],
    prefer_tailscale: bool = True,
    total_devices_count: int = 1,
    ts_peers: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Populate target_ip, connection_type, and endpoint for a selected device."""
    peers = (
        ts_peers
        if ts_peers is not None
        else (get_tailscale_android_peers() if prefer_tailscale else [])
    )
    target_ip = None
    connection_type = "mdns_lan"
    is_legacy_adb = selected_device.get("service_type") == "_adb._tcp"

    if prefer_tailscale and peers:
        # Match Tailscale peer to device name (avoid matching empty strings or
        # routing a non-Tailscale _adb._tcp TV to an unrelated active phone peer)
        for peer in peers:
            peer_name = peer["hostname"].lower()
            dev_name = selected_device.get("given_name", "").lower()
            dev_model = selected_device.get("name", "").lower()
            name_matches = bool(
                peer_name
                and (
                    (dev_name and (dev_name in peer_name or peer_name in dev_name))
                    or (dev_model and dev_model in peer_name)
                )
            )
            fallback_active = (
                not is_legacy_adb
                and total_devices_count == 1
                and peer.get("active", False)
            )
            if name_matches or fallback_active:
                if peer.get("tailscale_ip"):
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
    if (
        selected_device.get("instance")
        and selected_device.get("service_type", "_adb-tls-connect._tcp")
        == "_adb-tls-connect._tcp"
    ):
        selected_device["mdns_endpoint"] = (
            f"{selected_device['instance']}._adb-tls-connect._tcp"
        )
    return selected_device


def discover_all_devices(
    prefer_tailscale: bool = True,
    scan_timeout: float = 1.5,
) -> List[Dict[str, Any]]:
    """Discover and resolve all mDNS-advertised Android devices on the network."""
    instances = browse_mdns_instances(timeout_s=scan_timeout)
    if not instances:
        return []

    profiles = load_device_profiles()
    raw_devices: List[Dict[str, Any]] = []
    for inst in instances:
        dev = resolve_mdns_instance(inst)
        if dev:
            raw_devices.append(dev)

    resolved_devices = deduplicate_devices_by_serial(raw_devices)
    for dev in resolved_devices:
        enrich_device_with_profile(dev, profiles=profiles)

    ts_peers = get_tailscale_android_peers() if prefer_tailscale else []
    for dev in resolved_devices:
        resolve_device_endpoint(
            dev,
            prefer_tailscale=prefer_tailscale,
            total_devices_count=len(resolved_devices),
            ts_peers=ts_peers,
        )

    resolved_devices.sort(key=_device_sort_key)
    return resolved_devices


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

    selected_device = select_target_device(
        resolved_devices, device_filter=device_filter
    )
    if not selected_device:
        return None

    return resolve_device_endpoint(
        selected_device,
        prefer_tailscale=prefer_tailscale,
        total_devices_count=len(resolved_devices),
    )


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
            serial = extract_serial_from_id(parts[0])
            if serial:
                dev_info["serial"] = serial
            devices.append(dev_info)
    return devices


def find_existing_adb_transport(
    target_device: Dict[str, Any],
    attached_devices: List[Dict[str, str]],
) -> Tuple[Optional[Dict[str, str]], List[str]]:
    """Check if target_device is already attached in `adb devices -l` by serial or exact endpoint.

    Never matches on generic model/codename alone so a second phone of the same model
    is never confused with the target.
    Returns (primary_attached_entry, duplicate_endpoints_to_disconnect).
    """
    target_serial = (
        target_device.get("serial")
        or extract_serial_from_id(target_device.get("instance", ""))
    ).lower()
    target_endpoint = target_device.get("endpoint", "")
    target_lan = (
        f"{target_device.get('target_ip')}:{target_device.get('port')}"
        if target_device.get("target_ip") and target_device.get("port")
        else ""
    )

    matching_entries: List[Dict[str, str]] = []
    for entry in attached_devices:
        entry_id = entry.get("id", "")
        entry_serial = (entry.get("serial") or extract_serial_from_id(entry_id)).lower()

        if (
            (target_serial and entry_serial and target_serial == entry_serial)
            or (target_endpoint and entry_id == target_endpoint)
            or (target_lan and entry_id == target_lan)
        ):
            matching_entries.append(entry)

    if not matching_entries:
        return None, []

    # Prefer healthy `device` entries that use `_adb-tls-connect._tcp` mDNS transport
    healthy_tls = [
        e
        for e in matching_entries
        if e.get("status") == "device" and "_adb-tls-connect._tcp" in e.get("id", "")
    ]
    healthy_any = [e for e in matching_entries if e.get("status") == "device"]

    primary = (
        healthy_tls[0]
        if healthy_tls
        else (healthy_any[0] if healthy_any else matching_entries[0])
    )
    duplicates = [
        e["id"]
        for e in matching_entries
        if e["id"] != primary["id"]
        and not e["id"].startswith("adb-")
        and primary.get("status") == "device"
    ]
    return primary, duplicates


def connect_device(
    target_device: Dict[str, Any],
    set_tcpip: Optional[int] = None,
    attached_devices: Optional[List[Dict[str, str]]] = None,
) -> Dict[str, Any]:
    """Connect adb to target device endpoint, avoiding duplicate transports and rejecting unauthorized state."""
    if attached_devices is not None and not set_tcpip:
        existing, duplicates = find_existing_adb_transport(
            target_device, attached_devices
        )
        for dup_id in duplicates:
            run_command(["adb", "disconnect", dup_id], timeout=3.0)

        if existing:
            attached_id = existing["id"]
            status = existing.get("status", "unknown")
            if status == "device":
                return {
                    "success": True,
                    "endpoint": attached_id,
                    "adb_serial": attached_id,
                    "adb_status": "device",
                    "device": target_device.get("given_name")
                    or target_device.get("name", ""),
                    "profile": target_device.get("profile_key", ""),
                    "serial": target_device.get("serial", ""),
                    "connection_type": (
                        "mdns_tls"
                        if "_adb-tls-connect._tcp" in attached_id
                        else target_device.get("connection_type", "lan_ip")
                    ),
                    "port": target_device.get("port", 0),
                    "deduplicated_endpoints": duplicates,
                    "stdout": f"already connected to {attached_id}",
                    "stderr": "",
                }
            if status in ("unauthorized", "offline"):
                return {
                    "success": False,
                    "endpoint": attached_id,
                    "adb_serial": attached_id,
                    "adb_status": status,
                    "device": target_device.get("given_name")
                    or target_device.get("name", ""),
                    "profile": target_device.get("profile_key", ""),
                    "serial": target_device.get("serial", ""),
                    "connection_type": target_device.get("connection_type", "lan_ip"),
                    "port": target_device.get("port", 0),
                    "stdout": "",
                    "stderr": (
                        f"Device {attached_id} is {status}; accept the debugging authorization "
                        "prompt on the screen."
                    ),
                }

    # When attached_devices tracking is active (live CLI run without manual --ip or --tcpip),
    # prefer connecting _adb-tls-connect._tcp phones by their mDNS service name so adb does not
    # register a second duplicate transport alongside its own mDNS auto-connect.
    connect_target = (
        target_device.get("mdns_endpoint")
        if (
            attached_devices is not None
            and not set_tcpip
            and target_device.get("connection_type") != "manual_override"
            and target_device.get("mdns_endpoint")
        )
        else target_device["endpoint"]
    )

    code, stdout, stderr = run_command(["adb", "connect", connect_target], timeout=5.0)

    combined = f"{stdout}\n{stderr}".lower()
    if "no route to host" in combined:
        # Recover from stale macOS adb server daemon lacking Local Network TCC permission
        run_command(["adb", "kill-server"], timeout=3.0)
        code, stdout, stderr = run_command(
            ["adb", "connect", connect_target], timeout=5.0
        )

    success = (code == 0) and (
        "connected to" in stdout.lower() or "already connected" in stdout.lower()
    )
    if success and attached_devices is not None:
        refreshed = get_adb_attached_devices()
        post_entry, _ = find_existing_adb_transport(target_device, refreshed)
        if post_entry and post_entry.get("status") != "device":
            st = post_entry.get("status", "unauthorized")
            success = False
            stderr = (
                f"Device {post_entry['id']} is {st}; accept the debugging authorization "
                "prompt on the screen."
            )

    result: Dict[str, Any] = {
        "success": success,
        "endpoint": connect_target,
        "adb_serial": connect_target,
        "device": target_device["given_name"] or target_device["name"],
        "serial": target_device["serial"],
        "connection_type": (
            "mdns_tls"
            if "_adb-tls-connect._tcp" in connect_target
            else target_device["connection_type"]
        ),
        "port": target_device["port"],
        "stdout": stdout.strip(),
        "stderr": stderr.strip(),
    }
    if target_device.get("profile_key"):
        result["profile"] = target_device["profile_key"]

    if success and set_tcpip:
        tcpip_code, tcpip_out, tcpip_err = run_command(
            ["adb", "-s", connect_target, "tcpip", str(set_tcpip)], timeout=5.0
        )
        result["tcpip_mode"] = {
            "requested_port": set_tcpip,
            "success": tcpip_code == 0,
            "stdout": tcpip_out.strip(),
            "stderr": tcpip_err.strip(),
        }

    return result


def pair_device(
    pairing_code: str,
    device_filter: Optional[str] = None,
    scan_timeout: float = 2.0,
) -> Dict[str, Any]:
    """Auto-discover _adb-tls-pairing._tcp via mDNS and pair using a 6-digit code."""
    clean_code = pairing_code.strip()
    if not re.match(r"^\d{6}$", clean_code):
        return {
            "success": False,
            "error": "Pairing code must be a 6-digit number.",
        }

    instances = browse_mdns_instances(
        timeout_s=scan_timeout,
        service_types=(ADB_PAIRING_SERVICE,),
    )
    if not instances:
        return {
            "success": False,
            "error": (
                "No device advertising Wireless Debugging pairing (_adb-tls-pairing._tcp). "
                "Open 'Pair device with pairing code' on the phone and try again."
            ),
        }

    profiles = load_device_profiles()
    candidates: List[Dict[str, Any]] = []
    for inst in instances:
        dev = resolve_mdns_instance(
            inst, timeout_s=1.2, service_hint=ADB_PAIRING_SERVICE
        )
        if dev:
            enrich_device_with_profile(dev, profiles=profiles)
            candidates.append(dev)

    if not candidates:
        return {
            "success": False,
            "error": "Failed to resolve pairing service endpoint over mDNS.",
        }

    try:
        target = (
            select_target_device(
                candidates, device_filter=device_filter, profiles=profiles
            )
            if (device_filter or len(candidates) == 1)
            else None
        )
    except AmbiguousDeviceError as e:
        return {"success": False, "error": str(e)}

    if not target:
        return {
            "success": False,
            "error": (
                f"Multiple devices advertising pairing ({len(candidates)}). "
                "Specify --device to choose one."
            ),
        }

    # Pairing must always use local LAN IP/hostname, never Tailscale
    resolve_device_endpoint(target, prefer_tailscale=False, total_devices_count=1)
    endpoint = target["endpoint"]

    code, stdout, stderr = run_command(
        ["adb", "pair", endpoint, clean_code], timeout=10.0
    )
    paired = (code == 0) and ("successfully paired" in stdout.lower())

    return {
        "success": paired,
        "endpoint": endpoint,
        "device": target.get("given_name") or target.get("name") or target["instance"],
        "serial": target.get("serial", ""),
        "port": target["port"],
        "pairing_code": "***",
        "stdout": stdout.strip(),
        "stderr": stderr.strip(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Auto-discover Android Wireless Debugging port and connect adb.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "-d",
        "--device",
        type=str,
        help="Filter by device alias (fold, pixel4, tv), model, codename, or serial.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Connect all discovered Wireless Debugging phones (_adb-tls-connect._tcp).",
    )
    parser.add_argument(
        "--discover",
        "--list",
        dest="discover",
        action="store_true",
        help="Discover all mDNS Android devices on the network and show their aliases and status.",
    )
    parser.add_argument(
        "--pair",
        type=str,
        metavar="CODE",
        help="Pair with a device using a 6-digit pairing code (auto-discovers pairing port via mDNS).",
    )
    parser.add_argument(
        "--print-serial",
        action="store_true",
        help="Print only the resolved ADB transport identifier (for ANDROID_SERIAL) and exit.",
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
        help="Disconnect existing ADB session(s) before attempting to discover and connect.",
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

    if args.all and (args.device or args.ip or args.print_serial):
        parser.error("--all cannot be combined with --device, --ip, or --print-serial.")

    if args.status:
        devices = get_adb_attached_devices()
        profiles = load_device_profiles()
        for d in devices:
            enrich_device_with_profile(d, profiles=profiles)
        if args.json:
            print(json.dumps({"devices": devices}, indent=2))
        else:
            if not devices:
                print("No adb devices currently attached.")
            else:
                print(f"Attached adb devices ({len(devices)}):")
                for d in devices:
                    alias_tag = (
                        f" alias:{d['profile_key']}" if d.get("profile_key") else ""
                    )
                    print(
                        f"  • {d['id']} [{d['status']}] "
                        f"model:{d.get('model', 'unknown')}{alias_tag}"
                    )
        return 0

    if args.pair:
        pair_res = pair_device(
            args.pair, device_filter=args.device, scan_timeout=max(args.timeout, 2.0)
        )
        if args.json:
            print(json.dumps(pair_res, indent=2))
        else:
            if pair_res["success"]:
                print(f"✓ {pair_res['stdout']}")
            else:
                print(
                    f"✗ Pairing failed: {pair_res.get('error') or pair_res.get('stderr') or pair_res.get('stdout')}",
                    file=sys.stderr,
                )
        return 0 if pair_res["success"] else 2

    if args.discover:
        discovered = discover_all_devices(
            prefer_tailscale=not args.no_tailscale,
            scan_timeout=args.timeout,
        )
        attached = get_adb_attached_devices()
        for dev in discovered:
            existing, duplicates = find_existing_adb_transport(dev, attached)
            dev["adb_status"] = existing["status"] if existing else "not_attached"
            dev["adb_transport_id"] = existing["id"] if existing else ""
            dev["duplicate_transports"] = duplicates

        if args.json:
            print(json.dumps({"discovered": discovered}, indent=2))
        else:
            if not discovered:
                print("No Android mDNS services discovered on the local network.")
            else:
                print(f"Discovered Android mDNS devices ({len(discovered)}):")
                for d in discovered:
                    label = d.get("given_name") or d.get("name") or d["instance"]
                    alias = d.get("profile_key") or "-"
                    role = d.get("role") or "-"
                    status = d.get("adb_status", "not_attached")
                    print(
                        f"  • {label} (alias: {alias}, role: {role}, serial: {d.get('serial') or 'unknown'})\n"
                        f"    service: {d.get('service_type')} | endpoint: {d['endpoint']} ({d['connection_type']}) | adb: {status}"
                    )
        return 0

    if args.all:
        discovered = discover_all_devices(
            prefer_tailscale=not args.no_tailscale,
            scan_timeout=args.timeout,
        )
        phones = [
            d for d in discovered if d.get("service_type") == "_adb-tls-connect._tcp"
        ]
        if not phones:
            msg = "No Wireless Debugging phones (_adb-tls-connect._tcp) discovered."
            if args.json:
                print(json.dumps({"success": False, "error": msg, "results": []}))
            else:
                print(f"Error: {msg}", file=sys.stderr)
            return 1

        attached = get_adb_attached_devices()
        results = []
        for phone in phones:
            res = connect_device(phone, set_tcpip=args.tcpip, attached_devices=attached)
            results.append(res)

        all_ok = all(r["success"] for r in results)
        if args.json:
            print(json.dumps({"success": all_ok, "results": results}, indent=2))
        else:
            for r in results:
                mark = "✓" if r["success"] else "✗"
                print(
                    f"{mark} {r['device']} ({r.get('profile') or r['serial']}): {r['stdout'] or r['stderr']}"
                )
        return 0 if all_ok else 2

    if args.disconnect_first and not args.device:
        run_command(["adb", "disconnect"], timeout=2.0)

    if not args.json and not args.print_serial:
        print("Scanning local network for Android Wireless Debugging (mDNS)...")

    try:
        target = find_target_device(
            device_filter=args.device,
            prefer_tailscale=not args.no_tailscale,
            scan_timeout=args.timeout,
        )
    except AmbiguousDeviceError as e:
        if args.json:
            print(json.dumps({"success": False, "error": str(e)}))
        else:
            print(f"Error: {e}", file=sys.stderr)
        return 1

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

    attached = get_adb_attached_devices()
    if args.disconnect_first and args.device:
        existing, duplicates = find_existing_adb_transport(target, attached)
        if existing:
            run_command(["adb", "disconnect", existing["id"]], timeout=2.0)
        for dup_id in duplicates:
            run_command(["adb", "disconnect", dup_id], timeout=2.0)
        attached = get_adb_attached_devices()

    if not args.json and not args.print_serial:
        dev_label = target["given_name"] or target["name"] or "Android Device"
        alias_suffix = (
            f" [{target['profile_key']}]" if target.get("profile_key") else ""
        )
        print(
            f"Found: {dev_label}{alias_suffix} (port {target['port']}, via {target['connection_type']})"
        )
        print(f"Connecting adb to {target['endpoint']}...")

    result = connect_device(
        target,
        set_tcpip=args.tcpip,
        attached_devices=None if args.ip else attached,
    )

    if args.print_serial:
        if result["success"]:
            print(result.get("adb_serial") or result["endpoint"])
            return 0
        print(
            f"Error: {result.get('stderr') or ('failed to connect to ' + target['endpoint'])}",
            file=sys.stderr,
        )
        return 2

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
