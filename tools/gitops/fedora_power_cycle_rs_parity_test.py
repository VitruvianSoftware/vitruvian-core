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
"""fedora-power-cycle, the Rust port, against fedora_power_cycle.py: same
exit code, stdout, stderr and the same commands on the wire, on every input
here.

    bazel test //tools/gitops:fedora_power_cycle_rs_parity_test

Both run as programs under the name fedora_power_cycle.py, pointed with
--host/--port at a fake Kasa HS300 on localhost. Each case gets a fresh
strip per program; the strip decrypts every command it is sent and logs the
decrypted text, so the two must send the same bytes, not just similar JSON.

The inputs:
  * --status, --on, --off, --cycle and the default action (with --wait 0),
    and several actions at once, on strips whose outlets match by alias (in
    any case), by id, or not at all, with states of every JSON type;
  * strips that answer badly: nothing, a truncated header, a short payload,
    garbage, invalid UTF-8, a reset connection, values of the wrong type, a
    child without an id, a failure on the second command;
  * a strip that is not there (connection refused), ports out of range;
  * command lines argparse treats specially, at several terminal widths.

When Python crashes, its traceback names its own files and lines, which the
port cannot have, so there the header and the last line are compared.
"""

import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import fedora_power_cycle as fpc  # noqa: E402

TRACEBACK = "Traceback (most recent call last):"
NUC = "8006E93B6F541837D78FE0E0D9E0DAD62338476A05"


def _binary():
    path = os.environ.get("FEDORA_POWER_CYCLE_RS", "")
    if not path:
        raise unittest.SkipTest(
            "FEDORA_POWER_CYCLE_RS is not set; run this under bazel test"
        )
    return os.path.abspath(path)


def frame(text):
    """What a real strip sends: fpc.encrypt, which the tests trust."""
    return fpc.encrypt(text)


def sysinfo(children):
    return json.dumps({"system": {"get_sysinfo": {"children": children}}})


def child(alias, id_="X", state=0):
    return {"id": id_, "alias": alias, "state": state}


class Strip:
    """A fake HS300. `replies` is either a list of children, served as a
    stateful strip that applies set_relay_state, or a list of raw replies,
    one per connection (the last one repeats). A raw reply is bytes, or
    RESET to reset the connection once the command is read."""

    RESET = object()

    def __init__(self, children=None, raw=None):
        self.children = json.loads(json.dumps(children)) if children else None
        self.raw = raw
        self.log = []
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(16)
        self.port = self.sock.getsockname()[1]
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _read(self, conn, n):
        data = b""
        while len(data) < n:
            chunk = conn.recv(n - len(data))
            if not chunk:
                break
            data += chunk
        return data

    def _serve(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            with conn:
                conn.settimeout(5)
                try:
                    head = self._read(conn, 4)
                    (n,) = struct.unpack(">I", head) if len(head) == 4 else (0,)
                    text = fpc.decrypt(self._read(conn, n))
                except OSError:
                    continue
                index = len(self.log)
                self.log.append(text)
                reply = self._reply(index, text)
                try:
                    if reply is Strip.RESET:
                        conn.setsockopt(
                            socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0)
                        )
                    else:
                        conn.sendall(reply)
                except OSError:
                    pass

    def _reply(self, index, text):
        if self.raw is not None:
            return self.raw[min(index, len(self.raw) - 1)]
        cmd = json.loads(text)
        if "set_relay_state" in cmd.get("system", {}):
            ids = cmd.get("context", {}).get("child_ids", [])
            for c in self.children:
                if c.get("id") in ids:
                    c["state"] = cmd["system"]["set_relay_state"]["state"]
            return frame(json.dumps({"system": {"set_relay_state": {"err_code": 0}}}))
        return frame(sysinfo(self.children))

    def close(self):
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()
        self.thread.join(5)


def refused_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


# name -> (strip kwargs or None, argv after --host/--port, extra env)
NUC_ON = [child("TV"), child("NUC12I9", NUC, 1)]
NUC_OFF = [child("TV", "T", 1), child("NUC12I9", NUC, 0)]
BIG = [child(f"outlet {i} " + "x" * 40, f"ID{i}", i % 2) for i in range(200)]
BIG.append(child("rack NUC12I9", "BIGNUC", 1))

CASES = {
    # --status
    "status_on": (dict(children=NUC_ON), ["--status"]),
    "status_off": (dict(children=NUC_OFF), ["--status"]),
    "status_alias_any_case": (
        dict(children=[child("my nuc12I9 tower", "LOWER", 1)]),
        ["--status"],
    ),
    "status_no_match_uses_known_id": (
        dict(children=[child("TV", "T", 0), child("desk", NUC, 1)]),
        ["--status"],
    ),
    "status_no_match_no_id": (dict(children=[child("TV", "T", 1)]), ["--status"]),
    "status_no_children": (dict(raw=[frame("{}")]), ["--status"]),
    "status_state_missing": (
        dict(raw=[frame(sysinfo([{"id": "A", "alias": "NUC12I9"}]))]),
        ["--status"],
    ),
    "status_state_true": (dict(children=[child("NUC12I9", "A", True)]), ["--status"]),
    "status_state_float_one": (
        dict(children=[child("NUC12I9", "A", 1.0)]),
        ["--status"],
    ),
    "status_state_string_one": (
        dict(children=[child("NUC12I9", "A", "1")]),
        ["--status"],
    ),
    "status_state_two": (dict(children=[child("NUC12I9", "A", 2)]), ["--status"]),
    "status_state_null": (dict(children=[child("NUC12I9", "A", None)]), ["--status"]),
    "status_id_int": (dict(children=[child("NUC12I9", 7, 1)]), ["--status"]),
    "status_id_float": (dict(children=[child("NUC12I9", 1e16, 1)]), ["--status"]),
    "status_id_list": (
        dict(children=[child("NUC12I9", [1, "a", None], 1)]),
        ["--status"],
    ),
    "status_id_dict": (dict(children=[child("NUC12I9", {"k": True}, 1)]), ["--status"]),
    "status_big_payload": (dict(children=BIG), ["--status"]),
    "status_duplicate_keys": (
        dict(
            raw=[
                frame(
                    '{"system": {"get_sysinfo": {"children": [{"id": "A", "alias": "x",'
                    ' "alias": "NUC12I9", "state": 0, "state": 1}]}}}'
                )
            ]
        ),
        ["--status"],
    ),
    "status_unicode_alias_and_id": (
        dict(children=[child("Ñuc NUC12I9 é", "é\U0001f600", 1)]),
        ["--status"],
    ),
    "status_invalid_utf8_in_id": (
        dict(
            raw=[
                fpc.encrypt("x")[:0]
                + struct.pack(">I", 0)
                + b""  # placeholder, replaced below
            ]
        ),
        ["--status"],
    ),
    # actions
    "on": (dict(children=NUC_OFF), ["--on"]),
    "off": (dict(children=NUC_ON), ["--off"]),
    "off_unicode_id_on_the_wire": (
        dict(children=[child("NUC12I9", 'é\U0001f600\n"', 1)]),
        ["--off"],
    ),
    "off_int_id_on_the_wire": (
        dict(children=[child("NUC12I9", 12345678901234567890, 1)]),
        ["--off"],
    ),
    "cycle": (dict(children=NUC_ON), ["--cycle", "--wait", "0"]),
    "default_action_is_cycle": (dict(children=NUC_ON), ["--wait", "0"]),
    "status_wins_over_everything": (
        dict(children=NUC_ON),
        ["--on", "--off", "--cycle", "--status"],
    ),
    "off_wins_over_on": (dict(children=NUC_ON), ["--on", "--off"]),
    "on_wins_over_cycle": (dict(children=NUC_OFF), ["--cycle", "--on"]),
    "wait_spelled_oddly": (dict(children=NUC_ON), ["--wait", " +0_0 "]),
    "wait_negative": (dict(children=NUC_ON), ["--wait", "-1"]),
    "wait_equals_negative": (dict(children=NUC_ON), ["--wait=-3"]),
    "wait_too_large": (dict(children=NUC_ON), ["--wait", "99999999999999999999"]),
    "wait_just_too_large": (dict(children=NUC_ON), ["--wait", "9223372037"]),
    # strips that answer badly
    "no_reply": (dict(raw=[b""]), ["--status"]),
    "truncated_header": (dict(raw=[b"\x00\x00"]), ["--status"]),
    "short_payload": (
        dict(raw=[struct.pack(">I", 500) + frame(sysinfo(NUC_ON))[4:30]]),
        ["--status"],
    ),
    "empty_payload": (dict(raw=[struct.pack(">I", 0)]), ["--status"]),
    "garbage": (dict(raw=[frame("garbage")]), ["--status"]),
    "unterminated_json": (dict(raw=[frame('{"system": {"get_sy')]), ["--status"]),
    "json_extra_data": (dict(raw=[frame("{}\n{}")]), ["--status"]),
    "json_bom": (dict(raw=[frame("﻿{}")]), ["--status"]),
    "unencrypted_reply": (
        dict(raw=[struct.pack(">I", 2) + b"{}"]),
        ["--status"],
    ),
    "reset": (dict(raw=[Strip.RESET]), ["--status"]),
    "sysinfo_is_a_list": (dict(raw=[frame("[1, 2]")]), ["--status"]),
    "system_is_null": (dict(raw=[frame('{"system": null}')]), ["--status"]),
    "get_sysinfo_is_a_string": (
        dict(raw=[frame('{"system": {"get_sysinfo": "x"}}')]),
        ["--status"],
    ),
    "children_is_an_int": (
        dict(raw=[frame('{"system": {"get_sysinfo": {"children": 3}}}')]),
        ["--off"],
    ),
    "children_is_null": (
        dict(raw=[frame('{"system": {"get_sysinfo": {"children": null}}}')]),
        ["--off"],
    ),
    "children_is_a_dict": (
        dict(raw=[frame('{"system": {"get_sysinfo": {"children": {"a": 1}}}}')]),
        ["--off"],
    ),
    "children_is_empty_string": (
        dict(raw=[frame('{"system": {"get_sysinfo": {"children": ""}}}')]),
        ["--status"],
    ),
    "child_is_a_number": (dict(raw=[frame(sysinfo([1]))]), ["--status"]),
    "alias_is_null": (
        dict(raw=[frame(sysinfo([{"id": "A", "alias": None}]))]),
        ["--status"],
    ),
    "alias_is_a_number": (
        dict(raw=[frame(sysinfo([{"id": "A", "alias": 5}]))]),
        ["--on"],
    ),
    "child_without_id": (
        dict(raw=[frame(sysinfo([{"alias": "NUC12I9", "state": 1}]))]),
        ["--status"],
    ),
    "status_second_read_differs": (
        dict(raw=[frame(sysinfo(NUC_ON)), frame(sysinfo([1]))]),
        ["--status"],
    ),
    "set_fails_after_sysinfo": (dict(raw=[frame(sysinfo(NUC_ON)), b""]), ["--off"]),
    "cycle_fails_on_restore": (
        dict(raw=[frame(sysinfo(NUC_ON)), frame("{}"), frame("nope")]),
        ["--wait", "0"],
    ),
    "set_reply_is_ignored": (
        dict(raw=[frame(sysinfo(NUC_ON)), frame("[]")]),
        ["--on"],
    ),
}


def _bad_utf8_reply():
    # A sysinfo whose id holds bytes that are not UTF-8: decrypt replaces them.
    plain = sysinfo([{"id": "AB", "alias": "NUC12I9", "state": 1}]).encode()
    i = plain.index(b'"AB"') + 1
    plain = plain[:i] + b"\xff\xc3(" + plain[i + 2 :]
    key, out = 171, bytearray()
    for b in plain:
        key ^= b
        out.append(key)
    return struct.pack(">I", len(plain)) + bytes(out)


CASES["status_invalid_utf8_in_id"] = (dict(raw=[_bad_utf8_reply()]), ["--status"])

# Command lines: (argv, terminal width). None means no strip is needed.
ARGV_CASES = {
    "help": ["--help"],
    "help_short_glued": ["-hx"],
    "help_after_flags": ["--status", "-h"],
    "unknown_flag": ["--bogus"],
    "positional": ["now"],
    "wait_missing_value": ["--wait"],
    "wait_not_int": ["--wait", "x"],
    "wait_float": ["--wait", "1.5"],
    "port_not_int": ["--port", "nine"],
    "ambiguous_o": ["--o"],
    "ambiguous_h": ["--h"],
    "flag_with_value": ["--off=1"],
    "abbreviations": ["--st", "--of"],
    "after_dashes": ["--", "--status"],
}


class Parity(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls):
        rs = _binary()
        cls.tmp = tempfile.mkdtemp()
        cls.programs = {}
        for kind in ("py", "rs"):
            d = os.path.join(cls.tmp, kind)
            os.makedirs(d)
            cls.programs[kind] = os.path.join(d, "fedora_power_cycle.py")
        shutil.copy(os.path.join(HERE, "fedora_power_cycle.py"), cls.programs["py"])
        shutil.copy(rs, cls.programs["rs"])
        os.chmod(cls.programs["rs"], 0o755)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_one(self, kind, argv, columns=80):
        cmd = [self.programs[kind], *argv]
        if kind == "py":
            cmd = [sys.executable, *cmd]
        env = {
            k: v
            for k, v in os.environ.items()
            if k not in ("COLUMNS", "LINES", "PYTHONWARNINGS")
        }
        env["COLUMNS"] = str(columns)
        env["PYTHONIOENCODING"] = "utf-8"
        done = subprocess.run(
            cmd, capture_output=True, text=True, env=env, timeout=30, check=False
        )
        return done.returncode, done.stdout, done.stderr

    def compare(self, name, py, rs):
        (pc, pout, perr), (rc, rout, rerr) = py, rs
        self.assertEqual(
            pc, rc, f"{name}: exit\npy stderr:\n{perr}\nrs stderr:\n{rerr}"
        )
        self.assertEqual(pout, rout, f"{name}: stdout")
        if perr.startswith(TRACEBACK):
            self.assertTrue(rerr.startswith(TRACEBACK), f"{name}: rs stderr:\n{rerr}")
            self.assertEqual(
                perr.rstrip("\n").splitlines()[-1],
                rerr.rstrip("\n").splitlines()[-1],
                f"{name}: exception",
            )
        else:
            self.assertEqual(perr, rerr, f"{name}: stderr")

    def run_strip_case(self, name, strip_kwargs, argv):
        results, logs = {}, {}
        for kind in ("py", "rs"):
            strip = Strip(**strip_kwargs)
            try:
                results[kind] = self.run_one(
                    kind, ["--host", "127.0.0.1", "--port", str(strip.port), *argv]
                )
            finally:
                strip.close()
            logs[kind] = strip.log
        self.compare(name, results["py"], results["rs"])
        self.assertEqual(logs["py"], logs["rs"], f"{name}: commands sent")
        return results["py"], logs["py"]

    def test_strip_cases(self):
        for name, (kwargs, argv) in CASES.items():
            with self.subTest(name):
                self.run_strip_case(name, kwargs, argv)

    def test_command_lines(self):
        for name, argv in ARGV_CASES.items():
            for columns in (40, 80, 200):
                with self.subTest(f"{name}@{columns}"):
                    strip = Strip(children=NUC_ON)
                    try:
                        base = ["--host", "127.0.0.1", "--port", str(strip.port)]
                        py = self.run_one("py", base + argv, columns)
                        rs = self.run_one("rs", base + argv, columns)
                    finally:
                        strip.close()
                    self.compare(name, py, rs)

    def test_host_spellings(self):
        for name, spell in {
            "host": lambda p: ["--host", "127.0.0.1", "--port", str(p)],
            "ip": lambda p: ["--ip", "127.0.0.1", "--port", str(p)],
            "host_equals": lambda p: ["--host=127.0.0.1", f"--port={p}"],
            "last_wins": lambda p: [
                "--ip",
                "10.255.255.1",
                "--host",
                "127.0.0.1",
                "--port",
                str(p),
            ],
            "abbreviated": lambda p: ["--ho", "127.0.0.1", "--po", str(p)],
        }.items():
            with self.subTest(name):
                out = {}
                for kind in ("py", "rs"):
                    strip = Strip(children=NUC_ON)
                    try:
                        out[kind] = (
                            self.run_one(kind, spell(strip.port) + ["--status"]),
                            strip.log,
                        )
                    finally:
                        strip.close()
                self.compare(name, out["py"][0], out["rs"][0])
                self.assertEqual(out["py"][1], out["rs"][1])
                self.assertEqual(out["py"][0][0], 0, out["py"][0])

    def test_no_strip(self):
        port = refused_port()
        cases = {
            "refused": ["--port", str(port), "--status"],
            "port_too_large": ["--port", "70000", "--status"],
            "port_negative": ["--port", "-1", "--off"],
            "port_huge": ["--port", "99999999999999999999999", "--on"],
        }
        for name, argv in cases.items():
            with self.subTest(name):
                argv = ["--host", "127.0.0.1", *argv]
                self.compare(name, self.run_one("py", argv), self.run_one("rs", argv))


class TheHarnessBites(unittest.TestCase):
    """The comparisons above are only evidence if they can fail."""

    def test_a_different_command_is_seen(self):
        strip = Strip(children=NUC_ON)
        try:
            fpc.set_relay_state("127.0.0.1", NUC, 0, strip.port)
            fpc.set_relay_state("127.0.0.1", NUC, 1, strip.port)
        finally:
            strip.close()
        self.assertEqual(
            strip.log,
            [
                '{"context": {"child_ids": ["%s"]}, "system": {"set_relay_state": {"state": 0}}}'
                % NUC,
                '{"context": {"child_ids": ["%s"]}, "system": {"set_relay_state": {"state": 1}}}'
                % NUC,
            ],
        )
        self.assertNotEqual(strip.log[0], strip.log[1])

    def test_compare_rejects_a_different_exception(self):
        p = Parity("test_strip_cases")
        tb = TRACEBACK + "\n  File x\n"
        with self.assertRaises(AssertionError):
            p.compare(
                "x",
                (1, "", tb + "KeyError: 'id'\n"),
                (1, "", tb + "KeyError: 'alias'\n"),
            )
        with self.assertRaises(AssertionError):
            p.compare("x", (0, "ON\n", ""), (0, "OFF\n", ""))
        with self.assertRaises(AssertionError):
            p.compare("x", (2, "", "a\n"), (2, "", "b\n"))

    def test_python_reads_the_strip(self):
        strip = Strip(children=NUC_ON)
        try:
            self.assertEqual(fpc.find_child_id("127.0.0.1", strip.port), NUC)
            self.assertEqual(fpc.get_relay_state("127.0.0.1", NUC, strip.port), 1)
        finally:
            strip.close()


if __name__ == "__main__":
    unittest.main()
