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

"""check-loopback.sh against the Rust binary, side by side, on real sockets.

This process opens the listening sockets itself (loopback only, wildcard,
IPv6, several at once, none) and both implementations inspect them the way
they do in a service_test: /proc/net/tcp on Linux, /usr/sbin/lsof on macOS.
A stand-in port helper records the label it is asked about. Exit status,
stdout, stderr and that record must match byte for byte, after the
program's own path is replaced by <prog>.

PARITY_BASH picks the bash that runs the script (default: bash on PATH).
bash 3.2 and bash 5 give different exit statuses for a helper path that does
not exist; the port follows bash 5, so that scenario runs only under bash 4+.
"""

import os
import shutil
import socket
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
SH = os.path.join(HERE, os.environ["CHECK_LOOPBACK_SH"])
RS = os.path.join(HERE, os.environ["CHECK_LOOPBACK_RS"])
BASH = os.environ.get("PARITY_BASH") or shutil.which("bash") or "bash"
BASH_MAJOR = int(
    subprocess.run(
        [BASH, "-c", 'echo "${BASH_VERSINFO[0]}"'], capture_output=True, text=True
    ).stdout.strip()
)

HELPER = """#!/bin/sh
echo "asked: $# [$1]" >>"$PORT_LOG"
if [ -n "${PORT_STDERR:-}" ]; then echo "$PORT_STDERR" >&2; fi
printf '%s' "$PORT_VALUE"
exit "${PORT_RC:-0}"
"""


def has_ipv6():
    try:
        s = socket.socket(socket.AF_INET6)
        s.bind(("::1", 0))
        s.close()
        return True
    except OSError:
        return False


class Parity(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.work = os.path.realpath(tempfile.mkdtemp())
        self.helper = os.path.join(self.work, "port-helper")
        with open(self.helper, "w") as f:
            f.write(HELPER)
        os.chmod(self.helper, 0o755)
        self.log = os.path.join(self.work, "log")
        self.socks = []
        self.count = 0

    def tearDown(self):
        for s in self.socks:
            s.close()
        shutil.rmtree(self.work)

    def listen(self, family, addr, port=0, reuse=False):
        s = socket.socket(family)
        if reuse:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if hasattr(socket, "SO_REUSEPORT"):
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        if family == socket.AF_INET6:
            s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        s.bind((addr, port))
        s.listen()
        self.socks.append(s)
        return s.getsockname()[1]

    def free_port(self):
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()
        return port

    def run_one(self, cmd, prog, env):
        open(self.log, "w").close()
        full = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": self.work,
            "PORT_LOG": self.log,
            "ITEST_SERVICE_LABEL": "@@//apps/x:redis",
            "GET_ASSIGNED_PORT_BIN": self.helper,
        }
        full.update(env)
        full = {k: v for k, v in full.items() if v is not None}
        p = subprocess.run(cmd, env=full, cwd=self.work, capture_output=True)
        with open(self.log, "rb") as f:
            record = f.read()

        def norm(b):
            return b.replace(prog.encode(), b"<prog>")

        return p.returncode, norm(p.stdout), norm(p.stderr), record

    def both(self, env, bash5_only=False, expect_rc=None):
        if bash5_only and BASH_MAJOR < 4:
            print(f"skip under bash {BASH_MAJOR}: {env}")
            return None
        self.count += 1
        got_sh = self.run_one([BASH, SH], SH, env)
        got_rs = self.run_one([RS], RS, env)
        self.assertEqual(got_sh, got_rs, str(env))
        if expect_rc is not None:
            self.assertEqual(got_rs[0], expect_rc, got_rs)
        return got_rs

    def test_loopback_only_passes(self):
        port = self.listen(socket.AF_INET, "127.0.0.1")
        rc, out, _, rec = self.both({"PORT_VALUE": f"{port}\n"}, expect_rc=0)
        self.assertEqual(
            out, f"ok: @@//apps/x:redis listens on 127.0.0.1:{port} only\n".encode()
        )
        self.assertEqual(rec, b"asked: 1 [@@//apps/x:redis]\n")
        # Trailing newlines are dropped, as $(...) drops them.
        self.both({"PORT_VALUE": f"{port}\n\n\n"}, expect_rc=0)
        self.both({"PORT_VALUE": f"{port}", "PORT_STDERR": "helper noise"}, expect_rc=0)

    def test_wildcard_fails(self):
        port = self.listen(socket.AF_INET, "0.0.0.0")
        self.both({"PORT_VALUE": str(port)}, expect_rc=1)

    def test_loopback_and_wildcard_fail(self):
        port = self.listen(socket.AF_INET, "127.0.0.1", reuse=True)
        try:
            self.listen(socket.AF_INET, "0.0.0.0", port, reuse=True)
        except OSError:
            self.skipTest("this kernel will not share the port")
        self.both({"PORT_VALUE": str(port)}, expect_rc=1)

    def test_two_loopback_sockets_count_once(self):
        port = self.listen(socket.AF_INET, "127.0.0.1", reuse=True)
        try:
            self.listen(socket.AF_INET, "127.0.0.1", port, reuse=True)
        except OSError:
            self.skipTest("this kernel will not share the port")
        self.both({"PORT_VALUE": str(port)}, expect_rc=0)

    def test_ipv6(self):
        if not has_ipv6():
            self.skipTest("no IPv6 here")
        port = self.listen(socket.AF_INET, "127.0.0.1")
        try:
            self.listen(socket.AF_INET6, "::1", port)
        except OSError:
            self.skipTest("::1 port taken")
        self.both({"PORT_VALUE": str(port)}, expect_rc=1)
        port6 = self.listen(socket.AF_INET6, "::")
        self.both({"PORT_VALUE": str(port6)}, expect_rc=1)

    def test_nothing_listening(self):
        self.both({"PORT_VALUE": str(self.free_port())})

    def test_odd_ports(self):
        port = self.listen(socket.AF_INET, "127.0.0.1")
        for value in ("abc", "08", "0x10", f" {port}", f"{port} ", "-1", "99999"):
            self.both({"PORT_VALUE": value})

    def test_setup_failures(self):
        self.both({"ITEST_SERVICE_LABEL": None}, expect_rc=1)
        self.both({"ITEST_SERVICE_LABEL": ""}, expect_rc=1)
        self.both({"GET_ASSIGNED_PORT_BIN": None}, expect_rc=1)
        self.both({"GET_ASSIGNED_PORT_BIN": ""}, expect_rc=1)
        self.both({"ITEST_SERVICE_LABEL": None, "GET_ASSIGNED_PORT_BIN": None})
        self.both({"PORT_VALUE": ""}, expect_rc=1)
        self.both({"PORT_VALUE": "\n"}, expect_rc=1)
        self.both(
            {"PORT_VALUE": "1", "PORT_RC": "3", "PORT_STDERR": "boom"}, expect_rc=3
        )
        self.both({"GET_ASSIGNED_PORT_BIN": "no-such-helper"}, expect_rc=127)
        self.both(
            {"GET_ASSIGNED_PORT_BIN": os.path.join(self.work, "gone")}, bash5_only=True
        )

    def test_harness_sees_a_difference(self):
        port = self.listen(socket.AF_INET, "127.0.0.1")
        a = self.run_one([BASH, SH], SH, {"PORT_VALUE": str(port)})
        b = self.run_one(
            [RS], RS, {"PORT_VALUE": str(port), "ITEST_SERVICE_LABEL": "other"}
        )
        self.assertNotEqual(a, b)


if __name__ == "__main__":
    unittest.main(verbosity=2)
