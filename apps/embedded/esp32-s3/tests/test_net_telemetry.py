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

"""Test suite for Direction 1: the untethered wireless companion link.

Covers:
1. mDNS resolution of `vitruvian-companion.local`, the --wifi-host override,
   and the optional python-zeroconf fallback.
2. UdpTransport over a real loopback socket: framing, datagram splitting, and
   rejection of packets from anything but the companion.
3. SerialTransport parity -- the USB and Wi-Fi paths must expose one interface.
4. StreamSession cadence, liveness teardown, and USB re-acquisition.
5. open_transport link selection under --usb-only / --wifi-only.
6. The firmware's link arbitration model (USB > Wi-Fi > standby) and the Tile 0
   badge it drives.
7. Firmware source invariants: the mDNS hostname/service/port, the UDP port,
   and identical routing of both channels into packet_router_handle.
"""

import json
import os
import socket
import sys
import time
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(
    0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../host_companion"))
)

if "serial" not in sys.modules:
    sys.modules["serial"] = MagicMock()

import mac_stats_daemon
from mac_stats_daemon import (
    MDNS_HOSTNAME,
    NET_TELEMETRY_PORT,
    SerialTransport,
    StreamSession,
    UdpTransport,
    WIFI_LIVENESS_TIMEOUT_S,
    open_transport,
    parse_args,
    resolve_companion_host,
)

SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../src"))
INCLUDE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../include"))


def read_source(*parts) -> str:
    """Reads a firmware source file VERBATIM (no comment stripping).

    Filtering the text before asserting on it is how a source-level test grows
    a blind spot, so these assertions run against exactly what the compiler
    sees.
    """
    return open(os.path.join(*parts), encoding="utf-8").read()


class TestCompanionDiscovery(unittest.TestCase):
    """mDNS resolution and the explicit --wifi-host override."""

    @patch("mac_stats_daemon.socket.gethostbyname", return_value="192.168.1.42")
    def test_resolves_mdns_hostname_by_default(self, mock_resolve):
        self.assertEqual(resolve_companion_host(), "192.168.1.42")
        mock_resolve.assert_called_once_with(MDNS_HOSTNAME)

    def test_mdns_hostname_matches_firmware(self):
        version_h = read_source(INCLUDE_DIR, "version.h")
        self.assertIn('#define MDNS_HOSTNAME     "vitruvian-companion"', version_h)
        self.assertEqual(MDNS_HOSTNAME, "vitruvian-companion.local")

    @patch("mac_stats_daemon.socket.gethostbyname", return_value="10.0.0.9")
    def test_hint_overrides_discovery(self, mock_resolve):
        self.assertEqual(resolve_companion_host("desk-companion"), "10.0.0.9")
        mock_resolve.assert_called_once_with("desk-companion")

    @patch("mac_stats_daemon.socket.gethostbyname", return_value="10.0.0.9")
    def test_literal_ip_hint_passes_through(self, mock_resolve):
        self.assertEqual(resolve_companion_host("10.0.0.9"), "10.0.0.9")

    @patch("mac_stats_daemon.discover_companion_via_zeroconf")
    @patch("mac_stats_daemon.socket.gethostbyname", side_effect=socket.gaierror)
    def test_explicit_hint_never_falls_back_to_discovery(self, mock_resolve, mock_zc):
        # An unreachable --wifi-host is an error, not an invitation to go find
        # some other device on the LAN.
        self.assertIsNone(resolve_companion_host("10.0.0.9"))
        mock_zc.assert_not_called()

    @patch(
        "mac_stats_daemon.discover_companion_via_zeroconf", return_value="192.168.1.77"
    )
    @patch("mac_stats_daemon.socket.gethostbyname", side_effect=socket.gaierror)
    def test_zeroconf_fallback_when_resolver_lacks_mdns(self, mock_resolve, mock_zc):
        self.assertEqual(resolve_companion_host(), "192.168.1.77")

    @patch("mac_stats_daemon.discover_companion_via_zeroconf", return_value=None)
    @patch("mac_stats_daemon.socket.gethostbyname", side_effect=OSError)
    def test_no_device_returns_none(self, mock_resolve, mock_zc):
        self.assertIsNone(resolve_companion_host())

    def test_zeroconf_absent_is_not_an_error(self):
        # The daemon's declared dependency set is pyserial only; a missing
        # zeroconf must degrade to "not found", never to an ImportError.
        with patch.dict(sys.modules, {"zeroconf": None}):
            self.assertIsNone(mac_stats_daemon.discover_companion_via_zeroconf())


class FakeCompanion:
    """A loopback UDP socket standing in for the ESP32-S3's :8266 listener."""

    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.settimeout(2.0)
        self.port = self.sock.getsockname()[1]
        self.last_peer = None

    def recv_lines(self):
        data, peer = self.sock.recvfrom(4096)
        self.last_peer = peer
        return [line for line in data.decode().splitlines() if line]

    def send(self, text: str, to=None):
        self.sock.sendto(text.encode(), to or self.last_peer)

    def close(self):
        self.sock.close()


def read_lines_until(transport, expected: int, timeout: float = 2.0):
    """Polls the non-blocking transport until `expected` lines have arrived.

    Loopback delivery is fast but not synchronous, and a bare single read would
    make these tests flaky on a loaded machine.
    """
    deadline = time.monotonic() + timeout
    lines = []
    while time.monotonic() < deadline and len(lines) < expected:
        lines.extend(transport.read_lines())
        if len(lines) < expected:
            time.sleep(0.01)
    return lines


class TestUdpTransport(unittest.TestCase):
    """UDP telemetry over a real socket pair -- no mocks in the data path."""

    def setUp(self):
        self.device = FakeCompanion()
        self.transport = UdpTransport("127.0.0.1", self.device.port)
        self.addCleanup(self.device.close)
        self.addCleanup(self.transport.close)

    def test_default_port_is_8266(self):
        self.assertEqual(NET_TELEMETRY_PORT, 8266)
        t = UdpTransport("127.0.0.1")
        self.addCleanup(t.close)
        self.assertEqual(t.port, 8266)

    def test_send_packet_is_newline_framed_json(self):
        self.transport.send_packet({"type": "stats", "cpu": 41, "ram": 62})
        lines = self.device.recv_lines()
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(lines[0]), {"type": "stats", "cpu": 41, "ram": 62})

    def test_agent_ci_packet_round_trips_intact(self):
        payload = {
            "type": "agent_ci",
            "agent": {"name": "Claude Code", "state": "running", "task": "Wiring UDP"},
            "ci": {"repo": "vitruvian-core", "branch": "main", "status": "passing"},
        }
        self.transport.send_packet(payload)
        self.assertEqual(json.loads(self.device.recv_lines()[0]), payload)

    def test_read_lines_is_empty_when_quiet(self):
        self.assertEqual(self.transport.read_lines(), [])

    def test_inbound_button_command_is_received(self):
        self.transport.send_packet({"type": "stats", "cpu": 1})
        self.device.recv_lines()  # learn the daemon's ephemeral port
        self.device.send('{"cmd":"run_checks","action":"run_checks"}\n')
        lines = read_lines_until(self.transport, 1)
        self.assertEqual(json.loads(lines[0])["cmd"], "run_checks")

    def test_multiple_lines_in_one_datagram_are_split(self):
        self.transport.send_packet({"type": "stats"})
        self.device.recv_lines()
        self.device.send('{"type":"wifi_status"}\n{"type":"ble_status"}\n')
        lines = read_lines_until(self.transport, 2)
        self.assertEqual(len(lines), 2)
        self.assertEqual(json.loads(lines[1])["type"], "ble_status")

    def test_datagram_from_a_foreign_host_is_dropped(self):
        self.transport.send_packet({"type": "stats"})
        self.device.recv_lines()
        intruder = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.addCleanup(intruder.close)
        # A stray broadcast must not be mistaken for a button press.
        intruder.sendto(
            b'{"cmd":"open_pr"}\n', ("127.0.0.1", self.transport.local_port)
        )
        with patch.object(self.transport, "host", "192.168.1.55"):
            self.assertEqual(read_lines_until(self.transport, 1, timeout=0.5), [])

    def test_transport_is_labelled_wifi(self):
        self.assertEqual(self.transport.kind, "wifi")
        self.assertIn("UDP", self.transport.description)


class TestSerialTransport(unittest.TestCase):
    """The USB path must expose exactly the interface the Wi-Fi path does."""

    def setUp(self):
        self.ser = MagicMock()
        self.transport = SerialTransport(self.ser, "/dev/cu.usbmodem1101")

    def test_send_packet_framing_matches_udp(self):
        self.transport.send_packet({"type": "stats", "cpu": 7})
        payload = self.ser.write.call_args[0][0]
        self.assertTrue(payload.endswith(b"\n"))
        self.assertEqual(json.loads(payload.decode())["cpu"], 7)

    def test_read_lines_drains_the_buffer(self):
        self.ser.in_waiting = 1
        lines_out = [b'{"cmd":"run_checks"}\n', b'{"cmd":"open_pr"}\n']

        def readline():
            if not lines_out:
                self.ser.in_waiting = 0
                return b""
            value = lines_out.pop(0)
            if not lines_out:
                self.ser.in_waiting = 0
            return value

        self.ser.readline.side_effect = readline
        self.assertEqual(len(self.transport.read_lines()), 2)

    def test_interface_parity_with_udp_transport(self):
        for method in ("write", "flush", "send_packet", "read_lines", "close"):
            self.assertTrue(hasattr(SerialTransport, method), method)
            self.assertTrue(hasattr(UdpTransport, method), method)

    def test_transport_is_labelled_usb(self):
        self.assertEqual(self.transport.kind, "usb")


class RecordingTransport:
    kind = "wifi"
    host = "192.168.1.42"
    description = "test"

    def __init__(self):
        self.packets = []
        self.inbound = []

    def write(self, data):
        self.packets.append(json.loads(data.decode().strip()))

    def flush(self):
        pass

    def send_packet(self, payload):
        self.packets.append(payload)

    def read_lines(self):
        out, self.inbound = self.inbound, []
        return out

    def close(self):
        pass


class TestStreamSession(unittest.TestCase):
    """Cadence, liveness, and USB re-acquisition, independent of transport."""

    def setUp(self):
        self.transport = RecordingTransport()
        self.detector = MagicMock()
        self.detector.update.return_value = "com.apple.Terminal"
        self.detector.confirmed_app_name = "Terminal"
        self.monitor = MagicMock()
        self.monitor.get_payload.return_value = {
            "type": "agent_ci",
            "agent": {"state": "idle"},
            "ci": {"status": "passing"},
        }
        patcher = patch(
            "mac_stats_daemon.get_profile_for_app",
            return_value={"app": "Terminal", "color": "#30D158", "buttons": []},
        )
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher2 = patch(
            "mac_stats_daemon.build_app_payload",
            side_effect=lambda p: {"type": "app", "app": p["app"], "buttons": []},
        )
        patcher2.start()
        self.addCleanup(patcher2.stop)
        patcher3 = patch("mac_stats_daemon.get_cpu_percent", return_value=33)
        patcher3.start()
        self.addCleanup(patcher3.stop)
        patcher4 = patch("mac_stats_daemon.get_ram_percent", return_value=55)
        patcher4.start()
        self.addCleanup(patcher4.stop)

        self.session = StreamSession(self.transport, self.detector, self.monitor)

    def test_prime_sends_app_stats_and_agent_ci(self):
        self.session.prime()
        types = [p.get("type") for p in self.transport.packets]
        self.assertEqual(types, ["app", "stats", "agent_ci"])

    def test_stats_are_rate_limited_to_1hz(self):
        self.session.prime()
        self.transport.packets.clear()
        for _ in range(5):
            self.session.pump()
        self.assertEqual(
            [p for p in self.transport.packets if p["type"] == "stats"], []
        )

    def test_unchanged_app_focus_is_not_resent(self):
        self.session.prime()
        self.transport.packets.clear()
        self.session.pump()
        self.assertEqual([p for p in self.transport.packets if p["type"] == "app"], [])

    def test_inbound_command_is_dispatched(self):
        self.session.prime()
        self.transport.inbound = ['{"cmd":"run_checks"}']
        with patch("mac_stats_daemon.handle_esp_command") as mock_handle:
            self.session.pump()
        mock_handle.assert_called_once()
        self.assertIs(mock_handle.call_args[0][2], self.transport)

    def test_wifi_session_tears_down_after_liveness_timeout(self):
        self.session.prime()
        self.session.last_inbound_time -= WIFI_LIVENESS_TIMEOUT_S + 1
        with patch("mac_stats_daemon.find_esp_port", return_value=None):
            self.assertFalse(self.session.pump())

    def test_device_telemetry_keeps_the_wifi_session_alive(self):
        self.session.prime()
        self.session.last_inbound_time -= WIFI_LIVENESS_TIMEOUT_S + 1
        self.transport.inbound = ['{"type":"wifi_status","state":"connected"}']
        with patch("mac_stats_daemon.find_esp_port", return_value=None):
            self.assertTrue(self.session.pump())

    def test_wifi_session_yields_when_the_cable_returns(self):
        self.session.prime()
        self.session.last_usb_check -= StreamSession.USB_RECHECK_INTERVAL_S + 1
        with patch(
            "mac_stats_daemon.find_esp_port", return_value="/dev/cu.usbmodem1101"
        ):
            self.assertFalse(self.session.pump())

    def test_wifi_only_session_ignores_the_cable(self):
        # Otherwise --wifi-only tears the session down every 2 s on any machine
        # that happens to have a cable plugged in, and rebuilds the same link.
        session = StreamSession(
            self.transport, self.detector, self.monitor, allow_usb_takeover=False
        )
        session.prime()
        session.last_usb_check -= StreamSession.USB_RECHECK_INTERVAL_S + 1
        with patch(
            "mac_stats_daemon.find_esp_port", return_value="/dev/cu.usbmodem1101"
        ):
            self.assertTrue(session.pump())

    def test_usb_session_ignores_liveness_and_cable_checks(self):
        self.transport.kind = "usb"
        self.session.prime()
        self.session.last_inbound_time -= WIFI_LIVENESS_TIMEOUT_S + 100
        self.assertTrue(self.session.pump())

    @patch("mac_stats_daemon.subprocess.Popen")
    def test_hid_action_keyboard_shortcut(self, mock_popen):
        mac_stats_daemon.handle_esp_command(
            '{"cmd":"hid_action","mod":1,"key":218,"cons":0}',
            self.monitor,
            self.transport,
        )
        mock_popen.assert_called_once()
        args = mock_popen.call_args[0][0]
        self.assertEqual(args[0], "osascript")
        self.assertIn("key code 126", args[2])
        self.assertIn("control down", args[2])

    @patch("mac_stats_daemon.subprocess.Popen")
    def test_hid_action_consumer_mute(self, mock_popen):
        mac_stats_daemon.handle_esp_command(
            '{"cmd":"hid_action","mod":0,"key":0,"cons":226}',
            self.monitor,
            self.transport,
        )
        mock_popen.assert_called_once()
        args = mock_popen.call_args[0][0]
        self.assertEqual(args[0], "osascript")
        self.assertEqual(
            args[2],
            "set volume output muted (not (output muted of (get volume settings)))",
        )

    @patch("mac_stats_daemon.subprocess.Popen")
    def test_hid_action_display_sleep(self, mock_popen):
        mac_stats_daemon.handle_esp_command(
            '{"cmd":"hid_action","mod":0,"key":0,"cons":48}',
            self.monitor,
            self.transport,
        )
        mock_popen.assert_called_once()
        args = mock_popen.call_args[0][0]
        self.assertEqual(args[0], "pmset")
        self.assertEqual(args[1], "displaysleepnow")


class TestTransportSelection(unittest.TestCase):
    """open_transport: USB is preferred, Wi-Fi is the fallback."""

    @patch("mac_stats_daemon.find_esp_port", return_value="/dev/cu.usbmodem1101")
    def test_usb_wins_when_the_cable_is_in(self, mock_port):
        with patch.object(mac_stats_daemon.serial, "Serial") as mock_serial:
            transport, handle = open_transport(parse_args([]))
        self.assertEqual(transport.kind, "usb")
        mock_serial.assert_called_once()

    @patch("mac_stats_daemon.resolve_companion_host", return_value="192.168.1.42")
    @patch("mac_stats_daemon.find_esp_port", return_value=None)
    def test_falls_back_to_wifi_when_untethered(self, mock_port, mock_resolve):
        transport, handle = open_transport(parse_args([]))
        self.addCleanup(transport.close)
        self.assertEqual(transport.kind, "wifi")
        self.assertEqual(transport.host, "192.168.1.42")
        self.assertIs(handle, transport)

    @patch("mac_stats_daemon.resolve_companion_host", return_value="192.168.1.42")
    @patch("mac_stats_daemon.find_esp_port", return_value="/dev/cu.usbmodem1101")
    def test_wifi_only_skips_the_cable(self, mock_port, mock_resolve):
        transport, _ = open_transport(parse_args(["--wifi-only"]))
        self.addCleanup(transport.close)
        self.assertEqual(transport.kind, "wifi")

    @patch("mac_stats_daemon.resolve_companion_host", return_value="192.168.1.42")
    @patch("mac_stats_daemon.find_esp_port", return_value=None)
    def test_usb_only_never_opens_a_socket(self, mock_port, mock_resolve):
        transport, handle = open_transport(parse_args(["--usb-only"]))
        self.assertIsNone(transport)
        mock_resolve.assert_not_called()

    @patch("mac_stats_daemon.resolve_companion_host", return_value=None)
    @patch("mac_stats_daemon.find_esp_port", return_value=None)
    def test_no_link_available_returns_none(self, mock_port, mock_resolve):
        self.assertEqual(open_transport(parse_args([])), (None, None))

    @patch("mac_stats_daemon.resolve_companion_host", return_value="10.0.0.5")
    @patch("mac_stats_daemon.find_esp_port", return_value=None)
    def test_wifi_host_flag_is_passed_to_discovery(self, mock_port, mock_resolve):
        transport, _ = open_transport(parse_args(["--wifi-host", "desk.local"]))
        self.addCleanup(transport.close)
        mock_resolve.assert_called_once_with("desk.local")

    def test_wifi_port_flag_overrides_the_default(self):
        self.assertEqual(parse_args(["--wifi-port", "9000"]).wifi_port, 9000)
        self.assertEqual(parse_args([]).wifi_port, NET_TELEMETRY_PORT)


# ---------------------------------------------------------------------------
# Firmware model: link arbitration (packet_router.cpp) and the Tile 0 badge
# ---------------------------------------------------------------------------
LINK_ACTIVE_WINDOW_MS = 3000

USB_GREEN = 0x30D158
WIFI_CYAN = 0x64D2FF
STANDBY_ORANGE = 0xFF9F0A


class LinkModel:
    """Mirrors packet_router_active_channel() + ui_update_link_status()."""

    def __init__(self):
        self.last_usb_rx_ms = 0
        self.last_net_rx_ms = 0

    def receive(self, channel: str, now_ms: int):
        if channel == "usb":
            self.last_usb_rx_ms = now_ms
        elif channel == "net":
            self.last_net_rx_ms = now_ms

    def active_channel(self, now_ms: int) -> str:
        if self.last_usb_rx_ms and now_ms - self.last_usb_rx_ms < LINK_ACTIVE_WINDOW_MS:
            return "usb"
        if self.last_net_rx_ms and now_ms - self.last_net_rx_ms < LINK_ACTIVE_WINDOW_MS:
            return "net"
        return "none"

    def badge(self, now_ms: int, ip: str = ""):
        channel = self.active_channel(now_ms)
        if channel == "usb":
            return ("● USB", USB_GREEN)
        if channel == "net":
            return ("wifi Wi-Fi", WIFI_CYAN)
        if ip:
            return (f"● {ip}", USB_GREEN)
        return ("● Standby", STANDBY_ORANGE)


class TestLinkArbitration(unittest.TestCase):
    """USB > Wi-Fi > standby, with a 3 s liveness window on each channel."""

    def setUp(self):
        self.link = LinkModel()

    def test_nothing_received_is_standby(self):
        self.assertEqual(self.link.active_channel(0), "none")
        self.assertEqual(self.link.badge(0), ("● Standby", STANDBY_ORANGE))

    def test_usb_packet_lights_the_usb_badge(self):
        self.link.receive("usb", 1000)
        self.assertEqual(self.link.badge(1500), ("● USB", USB_GREEN))

    def test_wifi_packet_lights_the_wifi_badge_in_cyan(self):
        self.link.receive("net", 1000)
        label, color = self.link.badge(1500)
        self.assertEqual(color, WIFI_CYAN)
        self.assertIn("Wi-Fi", label)

    def test_usb_outranks_wifi_while_both_are_live(self):
        self.link.receive("net", 1000)
        self.link.receive("usb", 1000)
        self.assertEqual(self.link.active_channel(1100), "usb")

    def test_wifi_takes_over_when_usb_goes_quiet(self):
        self.link.receive("usb", 1000)
        self.link.receive("net", 3500)
        # USB last spoke at t=1000, so it is stale by t=4100.
        self.assertEqual(self.link.active_channel(4100), "net")

    def test_channel_expires_after_exactly_3s(self):
        self.link.receive("usb", 1000)
        self.assertEqual(
            self.link.active_channel(1000 + LINK_ACTIVE_WINDOW_MS - 1), "usb"
        )
        self.assertEqual(self.link.active_channel(1000 + LINK_ACTIVE_WINDOW_MS), "none")

    def test_idle_but_connected_shows_the_ip_not_standby(self):
        self.link.receive("usb", 1000)
        label, color = self.link.badge(9000, ip="192.168.1.42")
        self.assertEqual(label, "● 192.168.1.42")
        self.assertEqual(color, USB_GREEN)

    def test_idle_and_offline_shows_standby(self):
        self.link.receive("net", 1000)
        self.assertEqual(self.link.badge(9000, ip=""), ("● Standby", STANDBY_ORANGE))


class TestFirmwareWiring(unittest.TestCase):
    """Source invariants the Python model above is only meaningful against."""

    def test_mdns_service_and_port_are_advertised(self):
        wifi_mgr = read_source(SRC_DIR, "wifi_manager.cpp")
        self.assertIn("MDNS.begin(MDNS_HOSTNAME)", wifi_mgr)
        self.assertIn(
            "MDNS.addService(MDNS_SERVICE, MDNS_PROTO, NET_TELEMETRY_PORT)", wifi_mgr
        )
        version_h = read_source(INCLUDE_DIR, "version.h")
        self.assertIn('#define MDNS_SERVICE      "vitruvian"', version_h)
        self.assertIn('#define MDNS_PROTO        "tcp"', version_h)
        self.assertIn("#define NET_TELEMETRY_PORT 8266", version_h)

    def test_mdns_txt_records_match_the_design(self):
        wifi_mgr = read_source(SRC_DIR, "wifi_manager.cpp")
        for key in ('"version"', '"chip"', '"id"'):
            self.assertIn(f"addServiceTxt(MDNS_SERVICE, MDNS_PROTO, {key}", wifi_mgr)

    def test_mdns_is_restarted_across_link_transitions(self):
        wifi_mgr = read_source(SRC_DIR, "wifi_manager.cpp")
        # The responder binds to the station netif, so it cannot survive a
        # reconnect, a radio-off, or the SoftAP portal taking the interface.
        self.assertIn("mdns_start();", wifi_mgr)
        self.assertGreaterEqual(wifi_mgr.count("mdns_stop();"), 3)

    def test_udp_listener_binds_the_advertised_port(self):
        net = read_source(SRC_DIR, "net_telemetry.cpp")
        self.assertIn("udp.begin(NET_TELEMETRY_PORT)", net)

    def test_both_channels_route_through_one_dispatcher(self):
        main_cpp = read_source(SRC_DIR, "main.cpp")
        self.assertIn("packet_router_handle(json, len, LINK_CHANNEL_NET)", main_cpp)
        self.assertIn(
            "packet_router_handle(line.c_str(), line.length(), LINK_CHANNEL_USB)",
            main_cpp,
        )

    def test_link_window_constant_matches_the_model(self):
        router_h = read_source(SRC_DIR, "packet_router.h")
        self.assertIn(
            f"#define LINK_ACTIVE_WINDOW_MS {LINK_ACTIVE_WINDOW_MS}UL", router_h
        )

    def test_badge_colors_match_the_model(self):
        ui = read_source(SRC_DIR, "ui.cpp")
        self.assertIn('lv_label_set_text(label_link, "● USB")', ui)
        self.assertIn('LV_SYMBOL_WIFI " Wi-Fi"', ui)
        self.assertIn(f"lv_color_hex(0x{WIFI_CYAN:06X})", ui)
        self.assertIn(f"lv_color_hex(0x{STANDBY_ORANGE:06X})", ui)

    def test_button_commands_leave_over_the_active_channel(self):
        ui = read_source(SRC_DIR, "ui.cpp")
        # Hard-coding Serial.println here would strand every button press the
        # moment the cable is unplugged.
        self.assertIn('packet_router_emit("{\\"cmd\\":\\"run_checks\\"', ui)
        self.assertIn('packet_router_emit("{\\"cmd\\":\\"open_pr\\"', ui)
        self.assertIn('packet_router_emit("{\\"cmd\\":\\"wifi_sync\\"}")', ui)

    def test_outbound_prefers_udp_when_untethered(self):
        router = read_source(SRC_DIR, "packet_router.cpp")
        self.assertIn("net_telemetry_send_line(json)", router)

    def test_ota_endpoints_are_authenticated(self):
        ota = read_source(SRC_DIR, "ota_manager.cpp")
        self.assertIn("ArduinoOTA.setPassword(ota_password)", ota)
        self.assertIn("ota_server->authenticate(OTA_HTTP_USER, ota_password)", ota)
        self.assertIn('ota_server->on("/update", HTTP_POST', ota)

    def test_ota_and_portal_never_share_port_80(self):
        ui = read_source(SRC_DIR, "ui.cpp")
        # The provisioning portal binds :80 too; the OTA server must be down
        # BEFORE the portal starts or the portal's bind silently loses.
        portal_call = ui.index("wifi_manager_start_portal();")
        self.assertIn("ota_manager_stop();", ui[portal_call - 400 : portal_call])

    def test_ota_never_tears_down_mid_flash(self):
        ota = read_source(SRC_DIR, "ota_manager.cpp")
        stop_body = ota[ota.index("void ota_manager_stop()") :]
        stop_body = stop_body[: stop_body.index("\n}")]
        self.assertIn("if (updating) return;", stop_body)

    def test_mac_hid_cpp_has_wifi_fallback(self):
        src = read_source(SRC_DIR, "mac_hid.cpp")
        self.assertIn("packet_router_emit", src)
        self.assertIn(r"\"cmd\":\"hid_action\"", src)
        self.assertIn("trigger_display_sleep", src)

    def test_ui_cpp_has_display_sleep_button(self):
        ui = read_source(SRC_DIR, "ui.cpp")
        self.assertIn("Display\\nSleep", ui)
        self.assertIn("trigger_display_sleep()", ui)

    def test_display_sleep_sends_the_keyboard_power_chord(self):
        """The button must send Ctrl+Shift+Power, not consumer usage 0x30.

        0x30 is "Power" on the HID consumer page. macOS does not act on it, so
        this button did nothing: the Android app sent the identical code to a
        real Mac and the display stayed on. Ctrl+Shift+Power on the KEYBOARD
        page is what Control Center's "Put Display to Sleep" does, and it is
        verified working from the phone over the same report layout.

        Pinned because the failure is completely silent -- the button draws, the
        press registers, the report is accepted, and the display simply does not
        sleep. The neighbouring tests only assert trigger_display_sleep EXISTS,
        which is why the broken code sat here passing.
        """
        src = read_source(SRC_DIR, "mac_hid.cpp")
        body = src[src.index("void trigger_display_sleep()") :]
        body = body[: body.index("\n}")]

        self.assertIn("MOD_CTRL | MOD_SHIFT", body)
        self.assertIn("KEY_SYSTEM_POWER", body)
        self.assertNotIn("0x0030", body)
        self.assertNotIn("CONSUMER_CONTROL_DISPLAY_SLEEP", body)

        # Keyboard Power is usage 0x66; +136 is the raw-usage encoding that
        # both USBHIDKeyboard::press() and ble_hid_send() decode by subtracting.
        self.assertIn("(0x66 + 136)", src)


if __name__ == "__main__":
    unittest.main()
