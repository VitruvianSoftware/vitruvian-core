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

"""Unit tests for tools/adb-connect/adb_connect.py."""

import json
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

# Ensure local dir is on sys.path for direct execution and Bazel runfiles
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import adb_connect


SAMPLE_DNS_SD_BROWSE_OUTPUT = """
Browsing for _adb-tls-connect._tcp.local.
DATE: ---Tue 22 Sep 2026---
19:09:12.601  ...STARTING...
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
19:09:12.789  Add        2  13 local.               _adb-tls-connect._tcp. adb-66211FDDJ000XR-DYsKrZ
"""

SAMPLE_DNS_SD_LOOKUP_OUTPUT = """
Lookup adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp.local.
DATE: ---Tue 22 Sep 2026---
19:09:16.819  ...STARTING...
19:09:16.820  adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp.local. can be reached at Android_43W5CGQ4.local.:41067 (interface 13)
 given_name=James\\ Pixel\\ 11\\ Pro\\ Fold serial=66211FDDJ000XR v=2.0 api=37.0 name=Pixel\\ 11\\ Pro\\ Fold
"""

SAMPLE_DNS_SD_LOOKUP_PIXEL4_OUTPUT = """
Lookup adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp.local.
DATE: ---Fri 23 Oct 2026---
21:18:57.645  ...STARTING...
21:18:57.645  adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp.local. can be reached at Android-2.local.:41295 (interface 13)
 api= name=Pixel\\ 4\\ XL v=1
"""

SAMPLE_DNS_SD_ADDR_OUTPUT = """
DATE: ---Tue 22 Sep 2026---
19:09:34.153  ...STARTING...
Timestamp     A/R  Flags         IF  Hostname                               Address                                      TTL
19:09:34.153  Add  40000002      13  Android_43W5CGQ4.local.                192.168.86.36                                120
"""

SAMPLE_TAILSCALE_STATUS_JSON = {
    "Peer": {
        "nodekey:mac": {
            "HostName": "james-mbp32",
            "OS": "macOS",
            "TailscaleIPs": ["100.103.234.45"],
            "Online": True,
        },
        "nodekey:pixel": {
            "HostName": "James Pixel 11 Pro Fold",
            "DNSName": "james-pixel-11-pro-fold.coati-koi.ts.net.",
            "OS": "android",
            "TailscaleIPs": ["100.74.154.64", "fd7a:115c:a1e0::5b39:9a41"],
            "CurAddr": "192.168.86.36:48143",
            "Online": True,
            "Active": True,
        },
    }
}

SAMPLE_ADB_DEVICES_OUTPUT = """List of devices attached
100.74.154.64:41067    device product:yogi model:Pixel_11_Pro_Fold device:yogi transport_id:1116
emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1001
"""

SAMPLE_ADB_MULTI_DEVICES_OUTPUT = """List of devices attached
192.168.86.31:5555     unauthorized transport_id:2
192.168.86.61:41295    device product:coral model:Pixel_4_XL device:coral transport_id:277
adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp device product:yogi model:Pixel_11_Pro_Fold device:yogi transport_id:1
adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp device product:coral model:Pixel_4_XL device:coral transport_id:276
"""

SAMPLE_DNS_SD_BROWSE_TCP_OUTPUT = """
Browsing for _adb._tcp.local.
DATE: ---Thu 22 Oct 2026---
20:16:35.945  ...STARTING...
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
20:16:35.946  Add        2  13 local.               _adb._tcp.           adb-24adbf003005591
"""

SAMPLE_DNS_SD_LOOKUP_TCP_OUTPUT = """
Lookup adb-24adbf003005591._adb._tcp.local.
DATE: ---Thu 22 Oct 2026---
20:16:50.334  ...STARTING...
20:16:50.335  adb-24adbf003005591._adb._tcp.local. can be reached at Android.local.:5555 (interface 13)
"""


class AdbConnectTests(unittest.TestCase):
    def test_browse_mdns_instances_parsing(self):
        with patch("subprocess.Popen") as mock_popen:
            mock_proc = MagicMock()
            mock_proc.communicate.return_value = (SAMPLE_DNS_SD_BROWSE_OUTPUT, "")
            mock_popen.return_value = mock_proc

            instances = adb_connect.browse_mdns_instances(timeout_s=0.01)
            self.assertEqual(instances, ["adb-66211FDDJ000XR-DYsKrZ"])

    def test_resolve_mdns_instance_parsing(self):
        with patch("subprocess.Popen") as mock_popen:
            mock_proc = MagicMock()
            mock_proc.communicate.return_value = (SAMPLE_DNS_SD_LOOKUP_OUTPUT, "")
            mock_popen.return_value = mock_proc

            resolved = adb_connect.resolve_mdns_instance(
                "adb-66211FDDJ000XR-DYsKrZ", timeout_s=0.01
            )
            self.assertIsNotNone(resolved)
            self.assertEqual(resolved["instance"], "adb-66211FDDJ000XR-DYsKrZ")
            self.assertEqual(resolved["hostname"], "Android_43W5CGQ4.local.")
            self.assertEqual(resolved["port"], 41067)
            self.assertEqual(resolved["given_name"], "James Pixel 11 Pro Fold")
            self.assertEqual(resolved["serial"], "66211FDDJ000XR")
            self.assertEqual(resolved["name"], "Pixel 11 Pro Fold")
            self.assertEqual(resolved["api"], "37.0")

    def test_resolve_mdns_instance_pixel4_extracts_serial_from_instance_name(self):
        with patch("subprocess.Popen") as mock_popen:
            mock_proc = MagicMock()
            mock_proc.communicate.return_value = (
                SAMPLE_DNS_SD_LOOKUP_PIXEL4_OUTPUT,
                "",
            )
            mock_popen.return_value = mock_proc

            resolved = adb_connect.resolve_mdns_instance(
                "adb-98271FFBA007YW-OflOTi", timeout_s=0.01
            )
            self.assertIsNotNone(resolved)
            self.assertEqual(resolved["serial"], "98271FFBA007YW")
            self.assertEqual(resolved["name"], "Pixel 4 XL")
            self.assertEqual(resolved["port"], 41295)

    def test_resolve_hostname_ipv4_parsing(self):
        with patch("subprocess.Popen") as mock_popen:
            mock_proc = MagicMock()
            mock_proc.communicate.return_value = (SAMPLE_DNS_SD_ADDR_OUTPUT, "")
            mock_popen.return_value = mock_proc

            ip = adb_connect.resolve_hostname_ipv4(
                "Android_43W5CGQ4.local.", timeout_s=0.01
            )
            self.assertEqual(ip, "192.168.86.36")

    def test_get_tailscale_android_peers(self):
        with patch.object(
            adb_connect,
            "run_command",
            return_value=(0, json.dumps(SAMPLE_TAILSCALE_STATUS_JSON), ""),
        ):
            peers = adb_connect.get_tailscale_android_peers()
            self.assertEqual(len(peers), 1)
            self.assertEqual(peers[0]["hostname"], "James Pixel 11 Pro Fold")
            self.assertEqual(peers[0]["tailscale_ip"], "100.74.154.64")
            self.assertTrue(peers[0]["online"])

    def test_find_target_device_prefer_tailscale(self):
        with (
            patch.object(
                adb_connect,
                "browse_mdns_instances",
                return_value=["adb-66211FDDJ000XR-DYsKrZ"],
            ),
            patch.object(
                adb_connect,
                "resolve_mdns_instance",
                return_value={
                    "instance": "adb-66211FDDJ000XR-DYsKrZ",
                    "hostname": "Android_43W5CGQ4.local.",
                    "port": 41067,
                    "serial": "66211FDDJ000XR",
                    "name": "Pixel 11 Pro Fold",
                    "given_name": "James Pixel 11 Pro Fold",
                    "api": "37.0",
                },
            ),
            patch.object(
                adb_connect,
                "get_tailscale_android_peers",
                return_value=[
                    {
                        "hostname": "James Pixel 11 Pro Fold",
                        "tailscale_ip": "100.74.154.64",
                        "active": True,
                    }
                ],
            ),
        ):
            target = adb_connect.find_target_device(prefer_tailscale=True)
            self.assertIsNotNone(target)
            self.assertEqual(target["target_ip"], "100.74.154.64")
            self.assertEqual(target["endpoint"], "100.74.154.64:41067")
            self.assertEqual(target["connection_type"], "tailscale")

    def test_find_target_device_fallback_lan(self):
        with (
            patch.object(
                adb_connect,
                "browse_mdns_instances",
                return_value=["adb-66211FDDJ000XR-DYsKrZ"],
            ),
            patch.object(
                adb_connect,
                "resolve_mdns_instance",
                return_value={
                    "instance": "adb-66211FDDJ000XR-DYsKrZ",
                    "hostname": "Android_43W5CGQ4.local.",
                    "port": 41067,
                    "serial": "66211FDDJ000XR",
                    "name": "Pixel 11 Pro Fold",
                    "given_name": "James Pixel 11 Pro Fold",
                    "api": "37.0",
                },
            ),
            patch.object(adb_connect, "get_tailscale_android_peers", return_value=[]),
            patch.object(
                adb_connect, "resolve_hostname_ipv4", return_value="192.168.86.36"
            ),
        ):
            target = adb_connect.find_target_device(prefer_tailscale=False)
            self.assertIsNotNone(target)
            self.assertEqual(target["target_ip"], "192.168.86.36")
            self.assertEqual(target["endpoint"], "192.168.86.36:41067")
            self.assertEqual(target["connection_type"], "lan_ip")

    def test_find_target_device_filter_mismatch(self):
        with (
            patch.object(
                adb_connect,
                "browse_mdns_instances",
                return_value=["adb-66211FDDJ000XR-DYsKrZ"],
            ),
            patch.object(
                adb_connect,
                "resolve_mdns_instance",
                return_value={
                    "instance": "adb-66211FDDJ000XR-DYsKrZ",
                    "hostname": "Android_43W5CGQ4.local.",
                    "port": 41067,
                    "serial": "66211FDDJ000XR",
                    "name": "Pixel 11 Pro Fold",
                    "given_name": "James Pixel 11 Pro Fold",
                    "api": "37.0",
                },
            ),
        ):
            target = adb_connect.find_target_device(device_filter="GalaxyS24")
            self.assertIsNone(target)

    def test_get_adb_attached_devices(self):
        with patch.object(
            adb_connect,
            "run_command",
            return_value=(0, SAMPLE_ADB_DEVICES_OUTPUT, ""),
        ):
            devices = adb_connect.get_adb_attached_devices()
            self.assertEqual(len(devices), 2)
            self.assertEqual(devices[0]["id"], "100.74.154.64:41067")
            self.assertEqual(devices[0]["status"], "device")
            self.assertEqual(devices[0]["model"], "Pixel_11_Pro_Fold")
            self.assertEqual(devices[1]["id"], "emulator-5554")

    def test_connect_device_success(self):
        target = {
            "endpoint": "100.74.154.64:41067",
            "given_name": "James Pixel 11 Pro Fold",
            "name": "Pixel 11 Pro Fold",
            "serial": "66211FDDJ000XR",
            "connection_type": "tailscale",
            "port": 41067,
        }
        with patch.object(
            adb_connect,
            "run_command",
            return_value=(0, "connected to 100.74.154.64:41067", ""),
        ):
            result = adb_connect.connect_device(target)
            self.assertTrue(result["success"])
            self.assertEqual(result["endpoint"], "100.74.154.64:41067")

    def test_connect_device_with_tcpip(self):
        target = {
            "endpoint": "100.74.154.64:41067",
            "given_name": "James Pixel 11 Pro Fold",
            "name": "Pixel 11 Pro Fold",
            "serial": "66211FDDJ000XR",
            "connection_type": "tailscale",
            "port": 41067,
        }
        with patch.object(
            adb_connect,
            "run_command",
            side_effect=[
                (0, "connected to 100.74.154.64:41067", ""),
                (0, "restarting in TCP mode port: 5555", ""),
            ],
        ):
            result = adb_connect.connect_device(target, set_tcpip=5555)
            self.assertTrue(result["success"])
            self.assertIn("tcpip_mode", result)
            self.assertTrue(result["tcpip_mode"]["success"])
            self.assertEqual(result["tcpip_mode"]["requested_port"], 5555)

    def test_browse_and_resolve_legacy_adb_tcp_tv(self):
        with patch("subprocess.Popen") as mock_popen:
            mock_proc_tls = MagicMock()
            mock_proc_tls.communicate.return_value = ("", "")
            mock_proc_tcp = MagicMock()
            mock_proc_tcp.communicate.return_value = (
                SAMPLE_DNS_SD_BROWSE_TCP_OUTPUT,
                "",
            )
            mock_popen.side_effect = [mock_proc_tls, mock_proc_tcp]

            instances = adb_connect.browse_mdns_instances(timeout_s=0.01)
            self.assertEqual(instances, ["adb-24adbf003005591"])

        with (
            patch.object(
                adb_connect,
                "_lookup_mdns_service",
                return_value=SAMPLE_DNS_SD_LOOKUP_TCP_OUTPUT,
            ) as mock_lookup,
            patch.object(
                adb_connect,
                "browse_androidtv_remote_names",
                return_value={"android.local.": "Living Room Sony TV"},
            ),
        ):
            resolved = adb_connect.resolve_mdns_instance(
                "adb-24adbf003005591", timeout_s=0.01
            )
            self.assertIsNotNone(resolved)
            mock_lookup.assert_called_once_with(
                "adb-24adbf003005591", "_adb._tcp", 0.01
            )
            self.assertEqual(resolved["instance"], "adb-24adbf003005591")
            self.assertEqual(resolved["hostname"], "Android.local.")
            self.assertEqual(resolved["port"], 5555)
            self.assertEqual(resolved["serial"], "24adbf003005591")
            self.assertEqual(resolved["given_name"], "Living Room Sony TV")
            self.assertEqual(resolved["service_type"], "_adb._tcp")

    def test_browse_mdns_ignores_rmv_departure_lines(self):
        browse_with_rmv = (
            SAMPLE_DNS_SD_BROWSE_OUTPUT
            + "19:09:13.100  Rmv        0  13 local.               _adb-tls-connect._tcp. adb-stale-departed\n"
        )
        with patch("subprocess.Popen") as mock_popen:
            mock_proc = MagicMock()
            mock_proc.communicate.return_value = (browse_with_rmv, "")
            mock_popen.return_value = mock_proc

            instances = adb_connect.browse_mdns_instances(timeout_s=0.01)
            self.assertEqual(instances, ["adb-66211FDDJ000XR-DYsKrZ"])

    def test_find_target_device_tv_does_not_use_unrelated_phone_tailscale_ip(self):
        with (
            patch.object(
                adb_connect,
                "browse_mdns_instances",
                return_value=["adb-66211FDDJ000XR-DYsKrZ", "adb-24adbf003005591"],
            ),
            patch.object(
                adb_connect,
                "resolve_mdns_instance",
                side_effect=[
                    {
                        "instance": "adb-66211FDDJ000XR-DYsKrZ",
                        "hostname": "Android_43W5CGQ4.local.",
                        "port": 41067,
                        "serial": "66211FDDJ000XR",
                        "name": "Pixel 11 Pro Fold",
                        "given_name": "James Pixel 11 Pro Fold",
                        "api": "37.0",
                        "service_type": "_adb-tls-connect._tcp",
                    },
                    {
                        "instance": "adb-24adbf003005591",
                        "hostname": "Android.local.",
                        "port": 5555,
                        "serial": "24adbf003005591",
                        "name": "Living Room Sony TV",
                        "given_name": "Living Room Sony TV",
                        "api": "",
                        "service_type": "_adb._tcp",
                    },
                ],
            ),
            patch.object(
                adb_connect,
                "get_tailscale_android_peers",
                return_value=[
                    {
                        "hostname": "James Pixel 11 Pro Fold",
                        "tailscale_ip": "100.74.154.64",
                        "active": True,
                    }
                ],
            ),
            patch.object(
                adb_connect, "resolve_hostname_ipv4", return_value="192.168.86.31"
            ),
        ):
            target = adb_connect.find_target_device(
                device_filter="Sony", prefer_tailscale=True
            )
            self.assertIsNotNone(target)
            self.assertEqual(target["target_ip"], "192.168.86.31")
            self.assertEqual(target["endpoint"], "192.168.86.31:5555")
            self.assertEqual(target["connection_type"], "lan_ip")

    def test_connect_device_recovers_from_no_route_to_host(self):
        target = {
            "endpoint": "192.168.86.31:5555",
            "given_name": "Living Room Sony TV",
            "name": "Living Room Sony TV",
            "serial": "24adbf003005591",
            "connection_type": "lan_ip",
            "port": 5555,
        }
        with patch.object(
            adb_connect,
            "run_command",
            side_effect=[
                (
                    0,
                    "failed to connect to '192.168.86.31:5555': No route to host",
                    "",
                ),
                (0, "", ""),
                (0, "connected to 192.168.86.31:5555", ""),
            ],
        ) as mock_run:
            result = adb_connect.connect_device(target)
            self.assertTrue(result["success"])
            self.assertEqual(mock_run.call_count, 3)

    def test_default_selection_prefers_primary_phone_over_tv_and_secondary(self):
        devices = [
            {
                "instance": "adb-98271FFBA007YW-OflOTi",
                "hostname": "Android-2.local.",
                "port": 41295,
                "serial": "98271FFBA007YW",
                "name": "Pixel 4 XL",
                "given_name": "Pixel 4 XL",
                "service_type": "_adb-tls-connect._tcp",
            },
            {
                "instance": "adb-66211FDDJ000XR-DYsKrZ",
                "hostname": "Android_43W5CGQ4.local.",
                "port": 46223,
                "serial": "66211FDDJ000XR",
                "name": "Pixel 11 Pro Fold",
                "given_name": "James Pixel 11 Pro Fold",
                "service_type": "_adb-tls-connect._tcp",
            },
            {
                "instance": "adb-24adbf003005591",
                "hostname": "Android.local.",
                "port": 5555,
                "serial": "24adbf003005591",
                "name": "Living Room Sony TV",
                "given_name": "Living Room Sony TV",
                "service_type": "_adb._tcp",
            },
        ]
        # Default selection (no filter) must pick primary phone (Pixel 11 Pro Fold), NOT the TV at index -1
        selected = adb_connect.select_target_device(devices, device_filter=None)
        self.assertIsNotNone(selected)
        self.assertEqual(selected["profile_key"], "fold")
        self.assertEqual(selected["serial"], "66211FDDJ000XR")

        # Exact alias selection for pixel4 / coral / secondary
        for alias in ("pixel4", "coral", "secondary", "Pixel 4"):
            p4 = adb_connect.select_target_device(devices, device_filter=alias)
            self.assertIsNotNone(p4)
            self.assertEqual(p4["profile_key"], "pixel4")
            self.assertEqual(p4["serial"], "98271FFBA007YW")

        # Ambiguous substring 'pixel' matches both Pixel 11 Pro Fold and Pixel 4 XL
        with self.assertRaises(adb_connect.AmbiguousDeviceError):
            adb_connect.select_target_device(devices, device_filter="pixel")

    def test_pixel_watch_4_profile_matching_and_no_default_autoselect(self):
        watch_dev = {
            "instance": "adb-58301WRBNL30SD-js57rs",
            "hostname": "Android_A2G1X1TA.local.",
            "port": 39643,
            "serial": "58301WRBNL30SD",
            "name": "Pixel Watch 4",
            "given_name": "Pixel Watch 4",
            "api": "37.1",
            "service_type": "_adb-tls-connect._tcp",
        }
        # Default selection (no filter) must NOT auto-select a Wear OS watch
        self.assertIsNone(
            adb_connect.select_target_device([watch_dev], device_filter=None)
        )

        # Explicit alias selection resolves the watch profile
        for alias in (
            "watch",
            "pixel-watch",
            "pixelwatch4",
            "pw4",
            "kenari",
            "kenari_lte",
            "wear",
            "Pixel Watch 4",
        ):
            selected = adb_connect.select_target_device(
                [watch_dev], device_filter=alias
            )
            self.assertIsNotNone(selected, f"Failed for alias {alias}")
            self.assertEqual(selected["profile_key"], "watch")
            self.assertEqual(selected["role"], "watch")
            self.assertEqual(selected["codename"], "kenari_lte")
            self.assertEqual(selected["serial"], "58301WRBNL30SD")

    def test_default_selection_never_picks_tv_when_only_tv_on_network(self):
        only_tv = [
            {
                "instance": "adb-24adbf003005591",
                "hostname": "Android.local.",
                "port": 5555,
                "serial": "24adbf003005591",
                "name": "Living Room Sony TV",
                "given_name": "Living Room Sony TV",
                "service_type": "_adb._tcp",
            }
        ]
        self.assertIsNone(adb_connect.select_target_device(only_tv, device_filter=None))
        tv = adb_connect.select_target_device(only_tv, device_filter="tv")
        self.assertIsNotNone(tv)
        self.assertEqual(tv["profile_key"], "tv")

    def test_connect_device_avoids_duplicate_and_cleans_up_ip_transport(self):
        with patch.object(
            adb_connect,
            "run_command",
            return_value=(0, SAMPLE_ADB_MULTI_DEVICES_OUTPUT, ""),
        ):
            attached = adb_connect.get_adb_attached_devices()

        target_pixel4 = {
            "instance": "adb-98271FFBA007YW-OflOTi",
            "endpoint": "192.168.86.61:41295",
            "target_ip": "192.168.86.61",
            "given_name": "Pixel 4 XL",
            "name": "Pixel 4 XL",
            "profile_key": "pixel4",
            "codename": "coral",
            "serial": "98271FFBA007YW",
            "connection_type": "lan_ip",
            "port": 41295,
        }

        with patch.object(
            adb_connect,
            "run_command",
            return_value=(0, "disconnected 192.168.86.61:41295", ""),
        ) as mock_run:
            result = adb_connect.connect_device(
                target_pixel4, attached_devices=attached
            )
            self.assertTrue(result["success"])
            self.assertEqual(
                result["endpoint"],
                "adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp",
            )
            self.assertEqual(result["connection_type"], "mdns_tls")
            self.assertEqual(result["deduplicated_endpoints"], ["192.168.86.61:41295"])
            # Only disconnected the duplicate IP entry; did NOT call `adb connect` again
            mock_run.assert_called_once_with(
                ["adb", "disconnect", "192.168.86.61:41295"], timeout=3.0
            )

    def test_find_existing_adb_transport_does_not_confuse_different_phone_of_same_model(
        self,
    ):
        attached = [
            {
                "id": "192.168.86.99:40000",
                "status": "device",
                "product": "coral",
                "model": "Pixel_4_XL",
                "device": "coral",
            }
        ]
        target = {
            "instance": "adb-98271FFBA007YW-OflOTi",
            "endpoint": "192.168.86.61:41295",
            "target_ip": "192.168.86.61",
            "port": 41295,
            "serial": "98271FFBA007YW",
            "codename": "coral",
        }
        existing, duplicates = adb_connect.find_existing_adb_transport(target, attached)
        self.assertIsNone(existing)
        self.assertEqual(duplicates, [])

    def test_connect_device_reports_failure_when_device_is_unauthorized(self):
        with patch.object(
            adb_connect,
            "run_command",
            return_value=(0, SAMPLE_ADB_MULTI_DEVICES_OUTPUT, ""),
        ):
            attached = adb_connect.get_adb_attached_devices()

        target_tv = {
            "instance": "adb-24adbf003005591",
            "endpoint": "192.168.86.31:5555",
            "target_ip": "192.168.86.31",
            "given_name": "Living Room Sony TV",
            "name": "Living Room Sony TV",
            "profile_key": "tv",
            "serial": "24adbf003005591",
            "connection_type": "lan_ip",
            "port": 5555,
        }
        result = adb_connect.connect_device(target_tv, attached_devices=attached)
        self.assertFalse(result["success"])
        self.assertEqual(result["adb_status"], "unauthorized")
        self.assertIn("unauthorized", result["stderr"])

    def test_connect_device_uses_mdns_endpoint_for_unattached_tls_phone(self):
        target_phone = {
            "instance": "adb-98271FFBA007YW-OflOTi",
            "endpoint": "192.168.86.61:41295",
            "mdns_endpoint": "adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp",
            "target_ip": "192.168.86.61",
            "given_name": "Pixel 4 XL",
            "name": "Pixel 4 XL",
            "profile_key": "pixel4",
            "serial": "98271FFBA007YW",
            "connection_type": "lan_ip",
            "port": 41295,
        }
        with (
            patch.object(
                adb_connect,
                "run_command",
                return_value=(
                    0,
                    "connected to adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp",
                    "",
                ),
            ) as mock_run,
            patch.object(
                adb_connect,
                "get_adb_attached_devices",
                return_value=[
                    {
                        "id": "adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp",
                        "status": "device",
                        "serial": "98271FFBA007YW",
                    }
                ],
            ),
        ):
            res = adb_connect.connect_device(target_phone, attached_devices=[])
            self.assertTrue(res["success"])
            self.assertEqual(
                res["endpoint"],
                "adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp",
            )
            self.assertEqual(res["connection_type"], "mdns_tls")
            mock_run.assert_called_once_with(
                ["adb", "connect", "adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp"],
                timeout=5.0,
            )

    def test_serial_in_custom_profile_wins_over_builtin_model_pattern(self):
        profiles = adb_connect.load_device_profiles()
        profiles.append(
            {
                "key": "pixel4-lab",
                "display_name": "Pixel 4 XL Lab",
                "serial": "SECONDPIXEL4SERIAL",
                "codename": "coral",
                "role": "secondary",
                "default": False,
                "aliases": ("pixel4-lab",),
                "model_patterns": ("pixel 4 xl",),
            }
        )
        second_p4 = {
            "instance": "adb-SECONDPIXEL4SERIAL-xyz",
            "serial": "SECONDPIXEL4SERIAL",
            "name": "Pixel 4 XL",
            "given_name": "Pixel 4 XL",
            "service_type": "_adb-tls-connect._tcp",
        }
        matched = adb_connect.match_device_profile(second_p4, profiles=profiles)
        self.assertIsNotNone(matched)
        self.assertEqual(matched["key"], "pixel4-lab")

    def test_deduplicate_devices_by_serial_collapses_stale_mdns_entries(self):
        stale_and_fresh = [
            {
                "instance": "adb-66211FDDJ000XR-old",
                "hostname": "Android_43W5CGQ4.local.",
                "port": 39000,
                "serial": "66211FDDJ000XR",
                "name": "Pixel 11 Pro Fold",
                "given_name": "James Pixel 11 Pro Fold",
                "service_type": "_adb-tls-connect._tcp",
            },
            {
                "instance": "adb-66211FDDJ000XR-new",
                "hostname": "Android_43W5CGQ4.local.",
                "port": 46223,
                "serial": "66211FDDJ000XR",
                "name": "Pixel 11 Pro Fold",
                "given_name": "James Pixel 11 Pro Fold",
                "service_type": "_adb-tls-connect._tcp",
            },
        ]
        selected = adb_connect.select_target_device(
            stale_and_fresh, device_filter="fold"
        )
        self.assertIsNotNone(selected)
        self.assertEqual(selected["instance"], "adb-66211FDDJ000XR-new")
        self.assertEqual(selected["port"], 46223)

    def test_pair_device_validates_code_and_uses_lan(self):
        bad_res = adb_connect.pair_device("12ab")
        self.assertFalse(bad_res["success"])
        self.assertIn("6-digit", bad_res["error"])

        with (
            patch.object(
                adb_connect,
                "browse_mdns_instances",
                return_value=["adb-98271FFBA007YW-pair"],
            ),
            patch.object(
                adb_connect,
                "resolve_mdns_instance",
                return_value={
                    "instance": "adb-98271FFBA007YW-pair",
                    "hostname": "Android-2.local.",
                    "port": 37379,
                    "serial": "98271FFBA007YW",
                    "name": "Pixel 4 XL",
                    "given_name": "Pixel 4 XL",
                    "api": "",
                    "service_type": "_adb-tls-pairing._tcp",
                },
            ),
            patch.object(
                adb_connect, "resolve_hostname_ipv4", return_value="192.168.86.61"
            ),
            patch.object(
                adb_connect,
                "run_command",
                return_value=(
                    0,
                    "Successfully paired to 192.168.86.61:37379 [guid=adb-98271FFBA007YW-OflOTi]",
                    "",
                ),
            ) as mock_run,
        ):
            res = adb_connect.pair_device("052698")
            self.assertTrue(res["success"])
            self.assertEqual(res["endpoint"], "192.168.86.61:37379")
            self.assertEqual(res["pairing_code"], "***")
            mock_run.assert_called_once_with(
                ["adb", "pair", "192.168.86.61:37379", "052698"], timeout=10.0
            )

    def test_load_device_profiles_merges_user_config(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
            json.dump(
                {
                    "devices": [
                        {"key": "Fold", "serial": "66211FDDJ000XR"},
                        {"key": "pixel4", "serial": "98271FFBA007YW"},
                        {"key": 12345, "serial": "INVALID_KEY"},
                    ]
                },
                tf,
            )
            tf_path = tf.name

        try:
            profiles = adb_connect.load_device_profiles(config_path=tf_path)
            by_key = {p["key"]: p for p in profiles}
            self.assertEqual(by_key["fold"]["serial"], "66211FDDJ000XR")
            self.assertEqual(by_key["pixel4"]["serial"], "98271FFBA007YW")
            self.assertNotIn(12345, by_key)
        finally:
            os.remove(tf_path)


if __name__ == "__main__":
    unittest.main()
