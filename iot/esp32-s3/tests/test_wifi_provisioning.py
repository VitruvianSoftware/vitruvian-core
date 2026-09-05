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

"""Test suite for Milestone 5: Wi-Fi & Bluetooth wireless provisioning.

Covers:
1. macOS active-SSID detection (networksetup primary, ipconfig fallback).
2. Passphrase resolution order: env override, keychain, interactive prompt.
3. wifi_set wire packet serialization, framing, and special-character safety.
4. Zero-Typing Companion Sync: device wifi_sync -> daemon wifi_set round trip.
5. Inbound wifi_status / ble_status telemetry handling.
6. Firmware NVS persistence model (namespace wifi_config: enabled/ssid/pass/ip)
   mirroring wifi_manager.cpp validation and power-cycle behavior.
7. Firmware serial dispatch model for cmd/type packet branching in main.cpp.
8. --wifi-sync one-shot CLI provisioning flow.
"""

import json
import os
import subprocess
import sys
import unittest
from unittest.mock import MagicMock, patch

# Allow importing local modules from host_companion
sys.path.insert(
    0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../host_companion"))
)

# Ensure serial module is mocked if pyserial is not installed in the environment
if "serial" not in sys.modules:
    sys.modules["serial"] = MagicMock()

import mac_stats_daemon
from mac_stats_daemon import (
    build_wifi_set_payload,
    get_active_wifi_ssid,
    get_wifi_password,
    handle_esp_command,
    handle_wifi_sync_request,
    run_wifi_sync_once,
    serialize_wifi_set_packet,
)

NETWORKSETUP_JOINED = "Current Wi-Fi Network: HomeNet\n"
NETWORKSETUP_NOT_ASSOCIATED = "You are not associated with an AirPort network.\n"
IPCONFIG_SUMMARY = (
    "<dictionary> {\n"
    "  BSSID : 11:22:33:44:55:66\n"
    "  SSID : FallbackNet\n"
    "  Security : WPA2_PSK\n"
    "}\n"
)


class TestSsidDetection(unittest.TestCase):
    """macOS active Wi-Fi SSID detection."""

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_networksetup_joined(self, mock_out):
        mock_out.return_value = NETWORKSETUP_JOINED.encode()
        self.assertEqual(get_active_wifi_ssid(), "HomeNet")

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_networksetup_queries_requested_interface(self, mock_out):
        mock_out.return_value = NETWORKSETUP_JOINED.encode()
        get_active_wifi_ssid(interface="en1")
        args = mock_out.call_args[0][0]
        self.assertIn("en1", args)
        self.assertIn("networksetup", args[0])

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_ssid_containing_colon_is_preserved(self, mock_out):
        mock_out.return_value = b"Current Wi-Fi Network: Cafe: Guest 5G\n"
        self.assertEqual(get_active_wifi_ssid(), "Cafe: Guest 5G")

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_not_associated_falls_back_to_ipconfig(self, mock_out):
        mock_out.side_effect = [
            NETWORKSETUP_NOT_ASSOCIATED.encode(),
            IPCONFIG_SUMMARY.encode(),
        ]
        self.assertEqual(get_active_wifi_ssid(), "FallbackNet")
        self.assertEqual(mock_out.call_count, 2)

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_networksetup_error_falls_back_to_ipconfig(self, mock_out):
        mock_out.side_effect = [
            subprocess.CalledProcessError(1, "networksetup"),
            IPCONFIG_SUMMARY.encode(),
        ]
        self.assertEqual(get_active_wifi_ssid(), "FallbackNet")

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_no_network_anywhere_returns_none(self, mock_out):
        mock_out.side_effect = [
            NETWORKSETUP_NOT_ASSOCIATED.encode(),
            subprocess.CalledProcessError(1, "ipconfig"),
        ]
        self.assertIsNone(get_active_wifi_ssid())

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_redacted_ipconfig_ssid_is_ignored(self, mock_out):
        redacted = IPCONFIG_SUMMARY.replace("FallbackNet", "<redacted>")
        mock_out.side_effect = [
            NETWORKSETUP_NOT_ASSOCIATED.encode(),
            redacted.encode(),
        ]
        self.assertIsNone(get_active_wifi_ssid())

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_unicode_ssid(self, mock_out):
        mock_out.return_value = "Current Wi-Fi Network: Café ⚡\n".encode("utf-8")
        self.assertEqual(get_active_wifi_ssid(), "Café ⚡")


class TestPasswordResolution(unittest.TestCase):
    """Passphrase lookup order: env override -> keychain -> prompt."""

    @patch.dict(os.environ, {"VITRUVIAN_WIFI_PASS": "EnvSecret123"})
    def test_env_override_wins(self):
        with patch("mac_stats_daemon.subprocess.check_output") as mock_out:
            self.assertEqual(get_wifi_password("HomeNet"), "EnvSecret123")
            mock_out.assert_not_called()

    @patch.dict(os.environ, {"VITRUVIAN_WIFI_PASS": ""})
    def test_env_override_empty_means_open_network(self):
        self.assertEqual(get_wifi_password("OpenNet"), "")

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_keychain_lookup(self, mock_out):
        os.environ.pop("VITRUVIAN_WIFI_PASS", None)
        mock_out.return_value = b"KeychainSecret\n"
        self.assertEqual(
            get_wifi_password("HomeNet", interactive=False), "KeychainSecret"
        )
        args = mock_out.call_args[0][0]
        self.assertEqual(args[0], "security")
        self.assertIn("HomeNet", args)

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_keychain_strips_only_trailing_newline(self, mock_out):
        os.environ.pop("VITRUVIAN_WIFI_PASS", None)
        mock_out.return_value = b"pass with spaces  \n"
        self.assertEqual(
            get_wifi_password("HomeNet", interactive=False), "pass with spaces  "
        )

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_keychain_miss_non_interactive_returns_none(self, mock_out):
        os.environ.pop("VITRUVIAN_WIFI_PASS", None)
        mock_out.side_effect = subprocess.CalledProcessError(44, "security")
        self.assertIsNone(get_wifi_password("HomeNet", interactive=False))

    @patch("mac_stats_daemon.subprocess.check_output")
    def test_unicode_password(self, mock_out):
        os.environ.pop("VITRUVIAN_WIFI_PASS", None)
        mock_out.return_value = "pässwörd❤\n".encode("utf-8")
        self.assertEqual(get_wifi_password("HomeNet", interactive=False), "pässwörd❤")


class TestWifiSetSerialization(unittest.TestCase):
    """wifi_set wire packet shape, framing, and escaping."""

    def test_payload_shape(self):
        payload = build_wifi_set_payload("HomeNet", "Secret123")
        self.assertEqual(
            payload, {"cmd": "wifi_set", "ssid": "HomeNet", "pass": "Secret123"}
        )

    def test_none_password_serializes_as_empty(self):
        payload = build_wifi_set_payload("OpenNet", None)
        self.assertEqual(payload["pass"], "")

    def test_packet_is_newline_framed_single_line(self):
        packet = serialize_wifi_set_packet("HomeNet", "Secret123")
        self.assertTrue(packet.endswith("\n"))
        self.assertEqual(packet.count("\n"), 1)
        self.assertTrue(packet.startswith("{"))

    def test_round_trip_with_special_characters(self):
        ssid = 'Quo"ted \\Back\\slash'
        password = "p@$$ 'quote' \"dquote\" \\ / ünicode \U0001f512"
        packet = serialize_wifi_set_packet(ssid, password)
        decoded = json.loads(packet)
        self.assertEqual(decoded["ssid"], ssid)
        self.assertEqual(decoded["pass"], password)

    def test_max_length_wpa2_packet_fits_wire_limit(self):
        # WPA2 bounds: 32-octet SSID, 63-char passphrase; protocol caps
        # packets at 1024 bytes (docs/protocol.md §1).
        packet = serialize_wifi_set_packet("S" * 32, "p" * 63)
        self.assertLess(len(packet.encode("utf-8")), 1024)

    def test_packet_parseable_by_arduinojson_conventions(self):
        # ArduinoJson v7 requires plain UTF-8 object framing with string values.
        decoded = json.loads(serialize_wifi_set_packet("HomeNet", "Secret123"))
        self.assertIsInstance(decoded["cmd"], str)
        self.assertIsInstance(decoded["ssid"], str)
        self.assertIsInstance(decoded["pass"], str)


class TestWifiSyncHandling(unittest.TestCase):
    """Zero-Typing Companion Sync: device wifi_sync -> daemon wifi_set."""

    def setUp(self):
        self.monitor = MagicMock()
        self.ser = MagicMock()

    @patch("mac_stats_daemon.get_wifi_password", return_value="Secret123")
    @patch("mac_stats_daemon.get_active_wifi_ssid", return_value="HomeNet")
    def test_wifi_sync_round_trip(self, mock_ssid, mock_pass):
        handle_esp_command('{"cmd":"wifi_sync"}', self.monitor, self.ser)
        written = self.ser.write.call_args[0][0].decode("utf-8")
        decoded = json.loads(written)
        self.assertEqual(decoded["cmd"], "wifi_set")
        self.assertEqual(decoded["ssid"], "HomeNet")
        self.assertEqual(decoded["pass"], "Secret123")
        self.ser.flush.assert_called_once()

    @patch("mac_stats_daemon.get_wifi_password", return_value="Secret123")
    @patch("mac_stats_daemon.get_active_wifi_ssid", return_value="HomeNet")
    def test_daemon_loop_sync_is_non_interactive(self, mock_ssid, mock_pass):
        # The background daemon must never block on a getpass prompt.
        handle_esp_command('{"cmd":"wifi_sync"}', self.monitor, self.ser)
        self.assertFalse(mock_pass.call_args[1]["interactive"])

    @patch("mac_stats_daemon.get_active_wifi_ssid", return_value=None)
    def test_wifi_sync_without_active_network_writes_nothing(self, mock_ssid):
        handle_esp_command('{"cmd":"wifi_sync"}', self.monitor, self.ser)
        self.ser.write.assert_not_called()

    @patch("mac_stats_daemon.get_wifi_password", return_value=None)
    @patch("mac_stats_daemon.get_active_wifi_ssid", return_value="HomeNet")
    def test_wifi_sync_without_password_writes_nothing(self, mock_ssid, mock_pass):
        handle_esp_command('{"cmd":"wifi_sync"}', self.monitor, self.ser)
        self.ser.write.assert_not_called()

    def test_wifi_sync_without_serial_handle_does_not_crash(self):
        handle_esp_command('{"cmd":"wifi_sync"}', self.monitor, None)

    @patch("mac_stats_daemon.get_wifi_password", return_value="")
    @patch("mac_stats_daemon.get_active_wifi_ssid", return_value="OpenNet")
    def test_open_network_syncs_empty_passphrase(self, mock_ssid, mock_pass):
        handle_esp_command('{"cmd":"wifi_sync"}', self.monitor, self.ser)
        decoded = json.loads(self.ser.write.call_args[0][0].decode("utf-8"))
        self.assertEqual(decoded["pass"], "")

    def test_wifi_status_telemetry_is_logged_not_dispatched(self):
        handle_esp_command(
            '{"type":"wifi_status","state":"connected","ssid":"HomeNet","ip":"192.168.1.50"}',
            self.monitor,
            self.ser,
        )
        self.monitor.trigger_refresh.assert_not_called()
        self.ser.write.assert_not_called()

    def test_ble_status_telemetry_is_logged_not_dispatched(self):
        handle_esp_command(
            '{"type":"ble_status","state":"advertising","host":"","adv_seconds":58}',
            self.monitor,
            self.ser,
        )
        self.monitor.trigger_refresh.assert_not_called()
        self.ser.write.assert_not_called()

    def test_existing_commands_still_route(self):
        handle_esp_command('{"cmd":"run_checks"}', self.monitor, self.ser)
        self.monitor.trigger_refresh.assert_called_once()


# ---------------------------------------------------------------------------
# Firmware model: NVS persistence (mirrors wifi_manager.cpp)
# ---------------------------------------------------------------------------
WIFI_SSID_MAX_LEN = 32  # wifi_manager.h
WIFI_PASS_MAX_LEN = 64  # buffer size; max stored passphrase is 63 + NUL


class FirmwareNvsSim:
    """Python model of the firmware's Preferences usage for namespace
    "wifi_config" (keys: enabled, ssid, pass, ip), including the input
    validation in wifi_manager_set_credentials()."""

    def __init__(self, flash=None):
        self.flash = flash if flash is not None else {}

    def _ns(self):
        return self.flash.setdefault("wifi_config", {})

    def set_enabled(self, enabled):
        self._ns()["enabled"] = bool(enabled)

    def set_credentials(self, ssid, password):
        if not ssid or len(ssid.encode("utf-8")) > WIFI_SSID_MAX_LEN:
            return False
        if password and len(password.encode("utf-8")) > WIFI_PASS_MAX_LEN - 1:
            return False
        ns = self._ns()
        ns["enabled"] = True
        ns["ssid"] = ssid
        ns["pass"] = password or ""
        return True

    def set_last_ip(self, ip):
        self._ns()["ip"] = ip

    def power_cycle(self):
        # NVS survives reboot; RAM state is rebuilt from flash.
        return FirmwareNvsSim(flash=self.flash)

    def load(self):
        ns = self.flash.get("wifi_config", {})
        return {
            "enabled": ns.get("enabled", False),
            "ssid": ns.get("ssid", ""),
            "pass": ns.get("pass", ""),
            "ip": ns.get("ip", ""),
        }


class TestFirmwareNvsModel(unittest.TestCase):
    """NVS serialization semantics for the wifi_config namespace."""

    def test_defaults_before_provisioning(self):
        nvs = FirmwareNvsSim()
        state = nvs.load()
        self.assertFalse(state["enabled"])
        self.assertEqual(state["ssid"], "")
        self.assertEqual(state["pass"], "")

    def test_save_and_power_cycle_recovery(self):
        nvs = FirmwareNvsSim()
        self.assertTrue(nvs.set_credentials("HomeNet", "Secret123"))
        nvs.set_last_ip("192.168.1.50")
        rebooted = nvs.power_cycle().load()
        self.assertTrue(rebooted["enabled"])
        self.assertEqual(rebooted["ssid"], "HomeNet")
        self.assertEqual(rebooted["pass"], "Secret123")
        self.assertEqual(rebooted["ip"], "192.168.1.50")

    def test_provisioning_implies_radio_enabled(self):
        # Least-friction rule: syncing credentials turns the radio on.
        nvs = FirmwareNvsSim()
        nvs.set_enabled(False)
        nvs.set_credentials("HomeNet", "Secret123")
        self.assertTrue(nvs.load()["enabled"])

    def test_radio_disable_survives_reboot(self):
        nvs = FirmwareNvsSim()
        nvs.set_credentials("HomeNet", "Secret123")
        nvs.set_enabled(False)
        self.assertFalse(nvs.power_cycle().load()["enabled"])

    def test_rejects_empty_ssid(self):
        self.assertFalse(FirmwareNvsSim().set_credentials("", "Secret123"))

    def test_rejects_oversize_ssid(self):
        self.assertFalse(FirmwareNvsSim().set_credentials("S" * 33, "Secret123"))

    def test_accepts_max_length_ssid(self):
        self.assertTrue(FirmwareNvsSim().set_credentials("S" * 32, "Secret123"))

    def test_rejects_oversize_passphrase(self):
        self.assertFalse(FirmwareNvsSim().set_credentials("HomeNet", "p" * 64))

    def test_accepts_max_length_wpa2_passphrase(self):
        self.assertTrue(FirmwareNvsSim().set_credentials("HomeNet", "p" * 63))

    def test_accepts_open_network(self):
        nvs = FirmwareNvsSim()
        self.assertTrue(nvs.set_credentials("OpenNet", ""))
        self.assertEqual(nvs.load()["pass"], "")

    def test_multibyte_ssid_measured_in_octets(self):
        # 11 four-byte emoji = 44 octets > 32: over the 802.11 limit even
        # though the character count is small.
        self.assertFalse(FirmwareNvsSim().set_credentials("\U0001f512" * 11, "x"))
        self.assertTrue(FirmwareNvsSim().set_credentials("\U0001f512" * 8, "x"))

    def test_reprovisioning_overwrites_previous_network(self):
        nvs = FirmwareNvsSim()
        nvs.set_credentials("OldNet", "OldPass99")
        nvs.set_credentials("NewNet", "NewPass99")
        state = nvs.power_cycle().load()
        self.assertEqual(state["ssid"], "NewNet")
        self.assertEqual(state["pass"], "NewPass99")


def firmware_dispatch(packet: dict) -> str:
    """Mirrors the cmd/type branch ordering in main.cpp's serial dispatcher."""
    cmd = packet.get("cmd", "")
    pkt_type = packet.get("type", "")
    if cmd == "wifi_set":
        return "wifi_set"
    if cmd in ("wifi_status", "radio_status"):
        return "radio_status_query"
    if pkt_type == "stats" or (pkt_type == "" and "cpu" in packet):
        return "stats"
    if pkt_type == "app":
        return "app"
    if pkt_type == "agent_ci":
        return "agent_ci"
    if pkt_type == "deck_config":
        return "deck_config"
    return "ignored"


class TestFirmwareDispatchModel(unittest.TestCase):
    """Serial packet branching parity with main.cpp."""

    def test_wifi_set_routes_to_provisioning(self):
        self.assertEqual(
            firmware_dispatch({"cmd": "wifi_set", "ssid": "HomeNet", "pass": "x"}),
            "wifi_set",
        )

    def test_wifi_set_takes_priority_over_type(self):
        # A malformed hybrid frame must not double-dispatch.
        self.assertEqual(
            firmware_dispatch({"cmd": "wifi_set", "type": "stats", "ssid": "N"}),
            "wifi_set",
        )

    def test_radio_status_query(self):
        self.assertEqual(
            firmware_dispatch({"cmd": "wifi_status"}), "radio_status_query"
        )

    def test_legacy_and_typed_packets_unaffected(self):
        self.assertEqual(firmware_dispatch({"type": "stats", "cpu": 5}), "stats")
        self.assertEqual(firmware_dispatch({"cpu": 5}), "stats")
        self.assertEqual(firmware_dispatch({"type": "app"}), "app")
        self.assertEqual(firmware_dispatch({"type": "agent_ci"}), "agent_ci")
        self.assertEqual(firmware_dispatch({"type": "deck_config"}), "deck_config")

    def test_unknown_packets_ignored(self):
        self.assertEqual(firmware_dispatch({"cmd": "wifi_sync"}), "ignored")


class TestWifiSyncCli(unittest.TestCase):
    """--wifi-sync one-shot terminal provisioning."""

    @patch("mac_stats_daemon.find_esp_port", return_value=None)
    def test_no_device_returns_error(self, mock_port):
        self.assertEqual(run_wifi_sync_once(), 1)

    @patch("mac_stats_daemon.handle_wifi_sync_request", return_value=True)
    @patch("mac_stats_daemon.find_esp_port", return_value="/dev/cu.usbmodem1101")
    def test_success_on_connected_telemetry(self, mock_port, mock_sync):
        ser = MagicMock()
        ser.readline.return_value = (
            b'{"type":"wifi_status","state":"connected","ip":"192.168.1.50"}\n'
        )
        with patch.object(mac_stats_daemon.serial, "Serial") as mock_serial:
            mock_serial.return_value.__enter__.return_value = ser
            self.assertEqual(run_wifi_sync_once(), 0)
        self.assertTrue(mock_sync.call_args[1]["interactive"])

    @patch("mac_stats_daemon.handle_wifi_sync_request", return_value=False)
    @patch("mac_stats_daemon.find_esp_port", return_value="/dev/cu.usbmodem1101")
    def test_failed_credential_lookup_returns_error(self, mock_port, mock_sync):
        with patch.object(mac_stats_daemon.serial, "Serial") as mock_serial:
            mock_serial.return_value.__enter__.return_value = MagicMock()
            self.assertEqual(run_wifi_sync_once(), 1)


if __name__ == "__main__":
    unittest.main()
