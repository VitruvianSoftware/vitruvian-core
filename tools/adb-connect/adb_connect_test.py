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
import unittest
from unittest.mock import MagicMock, patch

import os
import sys

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


if __name__ == "__main__":
    unittest.main()
