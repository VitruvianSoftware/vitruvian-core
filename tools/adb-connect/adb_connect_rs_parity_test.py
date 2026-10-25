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

"""Parity: adb_connect.py and adb_connect_rs, side by side.

Each scenario runs both programs with the same arguments, environment,
user profile file and stand-in `adb`, `dns-sd` and `tailscale` programs
(shell scripts that print scripted output, keyed by their arguments, and
log every call). The two runs must agree on exit code, stdout, stderr and
the exact commands they ran, so CLI text, JSON, profile loading, the mDNS
and adb parsers and the subprocess behaviour are all compared at once.

Most scenarios set ADB_CONNECT_RS_SKIP_MDNS_WAIT=1, which on the Rust side
skips the fixed mDNS sleeps and lets each `dns-sd` exit on its own; the
Python side gets the same effect from a bootstrap that stubs
`time.sleep` (keeping its errors) and `Popen.terminate`. A few scenarios
run with real timing and real SIGTERMs.

Usage (Bazel passes both paths): adb_connect_rs_parity_test.py RUST_BIN PY_SRC
"""

import concurrent.futures
import os
import random
import shutil
import subprocess
import sys
import tempfile
import unittest

RUST_BIN = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else ""
PY_SRC = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else ""

TOOLS = ("adb", "dns-sd", "tailscale")

# The utilities the stand-ins need, by absolute path: PATH in the runs
# holds only the stand-ins, so a real adb or dns-sd can never answer.
_UTILS = {
    name: shutil.which(name) or f"/usr/bin/{name}"
    for name in ("od", "tr", "cat", "sleep")
}
_SH = shutil.which("sh") or "/bin/sh"

BOOTSTRAP = r"""
import os, runpy, subprocess, sys, time
# run_path sets sys.argv[0] to the script path, and argparse names the
# program after its basename: src is a link named like the Rust run's argv[0].
src = sys.argv[1]
sys.argv = [src] + sys.argv[2:]
if os.environ.get("ADB_CONNECT_RS_SKIP_MDNS_WAIT") == "1":
    _real_sleep = time.sleep
    def _sleep(secs):
        # Same errors as time.sleep (negative, NaN, inf), no waiting.
        return _real_sleep(0 if (secs >= 0 and secs < float("inf")) else secs)
    time.sleep = _sleep
    subprocess.Popen.terminate = lambda self: None
runpy.run_path(src, run_name="__main__")
"""

FAKE = """#!{sh}
D='{dir}'
key=$(printf '%s\\037' "$@" | {od} -An -v -tx1 | {tr} -d ' \\n')
printf '%s\\n' "$key" >> "$D/log"
n=$({cat} "$D/$key.count" 2>/dev/null || echo 0)
n=$((n+1))
echo "$n" > "$D/$key.count"
base="$D/$key"
if [ -f "$base.$n.out" ]; then base="$base.$n"; fi
if [ -f "$base.out" ]; then {cat} "$base.out"; fi
if [ -f "$base.err" ]; then {cat} "$base.err" >&2; fi
if [ -f "$base.sleep" ]; then exec {sleep} "$({cat} "$base.sleep")"; fi
rc=0
if [ -f "$base.rc" ]; then rc=$({cat} "$base.rc"); fi
exit "$rc"
"""


def arg_key(args):
    return "".join(a + "\x1f" for a in args).encode().hex() or "1f"


class R:
    """One scripted answer: stdout, stderr, exit code, optional hang."""

    def __init__(self, out="", err="", rc=0, sleep=None):
        self.out, self.err, self.rc, self.sleep = out, err, rc, sleep


class Scenario:
    def __init__(
        self,
        args,
        responses=(),
        missing=(),
        config=None,
        columns="80",
        prog="adb-connect",
        fast=True,
        crash=False,
        timeout=60,
    ):
        self.args = list(args)
        self.responses = list(responses)  # (tool, [args], R or [R, ...])
        self.missing = set(missing)
        self.config = config  # None, str, bytes, or DIR
        self.columns = columns
        self.prog = prog
        self.fast = fast
        self.crash = crash
        self.timeout = timeout


DIR = object()


def build_world(root, sc):
    fakebin = os.path.join(root, "bin")
    os.makedirs(fakebin)
    for tool in TOOLS:
        tdir = os.path.join(root, "fake", tool)
        os.makedirs(tdir)
        open(os.path.join(tdir, "log"), "w").close()
        if tool in sc.missing:
            continue
        path = os.path.join(fakebin, tool)
        with open(path, "w") as f:
            f.write(FAKE.format(sh=_SH, dir=tdir, **_UTILS))
        os.chmod(path, 0o755)
    for tool, args, answer in sc.responses:
        tdir = os.path.join(root, "fake", tool)
        answers = answer if isinstance(answer, list) else [answer]
        key = arg_key(args)
        for i, a in enumerate(answers, start=1):
            names = [f"{key}.{i}"] if len(answers) > 1 else []
            if i == len(answers):
                names.append(key)  # the last answer repeats
            for name in names:
                base = os.path.join(tdir, name)
                with open(base + ".out", "wb") as f:
                    f.write(a.out.encode() if isinstance(a.out, str) else a.out)
                if a.err:
                    with open(base + ".err", "w") as f:
                        f.write(a.err)
                if a.rc:
                    with open(base + ".rc", "w") as f:
                        f.write(str(a.rc))
                if a.sleep is not None:
                    with open(base + ".sleep", "w") as f:
                        f.write(str(a.sleep))
    home = os.path.join(root, "home")
    cfg_dir = os.path.join(home, ".config", "vitruvian")
    os.makedirs(cfg_dir)
    cfg = os.path.join(cfg_dir, "adb-devices.json")
    if sc.config is DIR:
        os.makedirs(cfg)
    elif isinstance(sc.config, str):
        with open(cfg, "w", newline="") as f:
            f.write(sc.config)
    elif isinstance(sc.config, bytes):
        with open(cfg, "wb") as f:
            f.write(sc.config)
    env = {
        "PATH": fakebin,
        "HOME": home,
        "PYTHONIOENCODING": "utf-8",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    if sc.columns is not None:
        env["COLUMNS"] = sc.columns
    if sc.fast:
        env["ADB_CONNECT_RS_SKIP_MDNS_WAIT"] = "1"
    return env


def read_log(root, tool):
    with open(os.path.join(root, "fake", tool, "log")) as f:
        calls = [
            bytes.fromhex(line.strip()).decode().split("\x1f")[:-1]
            for line in f
            if line.strip()
        ]
    if tool == "dns-sd":
        # The -B browses run concurrently; everything else is sequential.
        browses = sorted(c for c in calls if c[:1] == ["-B"])
        return browses, [c for c in calls if c[:1] != ["-B"]]
    return calls


def run_impl(which, sc):
    root = tempfile.mkdtemp(prefix=f"parity-{which}-")
    try:
        env = build_world(root, sc)
        if which == "py":
            link_dir = os.path.join(root, "py")
            os.makedirs(link_dir)
            link = os.path.join(link_dir, sc.prog)
            os.symlink(PY_SRC, link)
            cmd = [sys.executable, "-c", BOOTSTRAP, link] + sc.args
            exe = None
        else:
            cmd = [sc.prog] + sc.args
            exe = RUST_BIN
        proc = subprocess.run(
            cmd,
            executable=exe,
            env=env,
            cwd=root,
            capture_output=True,
            timeout=sc.timeout,
        )
        if sc.crash:
            # When the parent crashes immediately after Popen() (e.g. time.sleep
            # raising ValueError on a negative or NaN timeout), background
            # stand-in shell scripts may still be writing their log line.
            import time

            time.sleep(0.15)
        # The worlds live in different temporary folders; paths that show
        # up in output (the profile file's) are compared relative to them.
        out = proc.stdout.decode().replace(root, "<ROOT>")
        err = proc.stderr.decode().replace(root, "<ROOT>")
        logs = {tool: read_log(root, tool) for tool in TOOLS}
        return proc.returncode, out, err, logs
    finally:
        shutil.rmtree(root, ignore_errors=True)


# ------------------------------------------------------------- fixtures --


def browse(svc, *instances, extra=""):
    lines = [
        "",
        f"Browsing for {svc}.local.",
        "DATE: ---Tue 22 Sep 2026---",
        "19:09:12.601  ...STARTING...",
        "Timestamp     A/R    Flags  if Domain               Service Type         Instance Name",
    ]
    for inst in instances:
        lines.append(
            f"19:09:12.789  Add        2  13 local.               {svc}. {inst}"
        )
    return "\n".join(lines) + "\n" + extra


def lookup(inst, svc, host, port, txt=""):
    return (
        f"\nLookup {inst}.{svc}.local.\nDATE: ---Tue 22 Sep 2026---\n19:09:16.819  ...STARTING...\n"
        f"19:09:16.820  {inst}.{svc}.local. can be reached at {host}:{port} (interface 13)\n {txt}\n"
    )


def addr(host, ip):
    return (
        "DATE: ---Tue 22 Sep 2026---\n19:09:34.153  ...STARTING...\n"
        "Timestamp     A/R  Flags         IF  Hostname                               Address  TTL\n"
        f"19:09:34.153  Add  40000002      13  {host}                {ip}       120\n"
    )


TLS = "_adb-tls-connect._tcp"
LEGACY = "_adb._tcp"
PAIRING = "_adb-tls-pairing._tcp"

FOLD = "adb-66211FDDJ000XR-DYsKrZ"
P4 = "adb-98271FFBA007YW-OflOTi"
WATCH = "adb-58301WRBNL30SD-js57rs"
TV = "adb-24adbf003005591"

FOLD_TXT = r"given_name=James\ Pixel\ 11\ Pro\ Fold serial=66211FDDJ000XR v=2.0 api=37.0 name=Pixel\ 11\ Pro\ Fold"
P4_TXT = r"api= name=Pixel\ 4\ XL v=1"
WATCH_TXT = r"name=Pixel\ Watch\ 4 api=37.1"

TAILSCALE = """{"Peer": {
  "nodekey:mac": {"HostName": "james-mbp32", "OS": "macOS", "TailscaleIPs": ["100.103.234.45"], "Online": true},
  "nodekey:pixel": {"HostName": "James Pixel 11 Pro Fold", "DNSName": "james-pixel-11-pro-fold.coati-koi.ts.net.",
    "OS": "android", "TailscaleIPs": ["100.74.154.64", "fd7a:115c:a1e0::5b39:9a41"],
    "CurAddr": "192.168.86.36:48143", "Online": true, "Active": true}
}}"""

ADB_DEVICES = """List of devices attached
100.74.154.64:41067    device product:yogi model:Pixel_11_Pro_Fold device:yogi transport_id:1116
emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1001
"""

ADB_MULTI = """List of devices attached
192.168.86.31:5555     unauthorized transport_id:2
192.168.86.61:41295    device product:coral model:Pixel_4_XL device:coral transport_id:277
adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp device product:yogi model:Pixel_11_Pro_Fold device:yogi transport_id:1
adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp device product:coral model:Pixel_4_XL device:coral transport_id:276
"""

EMPTY_ADB = "List of devices attached\n\n"


def net_fold_only():
    return [
        ("dns-sd", ["-B", TLS, "local."], R(browse(TLS, FOLD))),
        (
            "dns-sd",
            ["-L", FOLD, TLS, "local."],
            R(lookup(FOLD, TLS, "Android_43W5CGQ4.local.", 41067, FOLD_TXT)),
        ),
        (
            "dns-sd",
            ["-G", "v4", "Android_43W5CGQ4.local."],
            R(addr("Android_43W5CGQ4.local.", "192.168.86.36")),
        ),
    ]


def net_household():
    """Fold, Pixel 4 XL, Pixel Watch 4 and the Sony TV (named via androidtvremote2)."""
    return [
        (
            "dns-sd",
            ["-B", TLS, "local."],
            R(
                browse(
                    TLS,
                    P4,
                    FOLD,
                    WATCH,
                    extra=(
                        "19:09:13.100  Rmv        0  13 local.               _adb-tls-connect._tcp. adb-stale-departed\n"
                    ),
                )
            ),
        ),
        ("dns-sd", ["-B", LEGACY, "local."], R(browse(LEGACY, TV))),
        (
            "dns-sd",
            ["-L", FOLD, TLS, "local."],
            R(lookup(FOLD, TLS, "Android_43W5CGQ4.local.", 46223, FOLD_TXT)),
        ),
        (
            "dns-sd",
            ["-L", P4, TLS, "local."],
            R(lookup(P4, TLS, "Android-2.local.", 41295, P4_TXT)),
        ),
        (
            "dns-sd",
            ["-L", WATCH, TLS, "local."],
            R(lookup(WATCH, TLS, "Android_A2G1X1TA.local.", 39643, WATCH_TXT)),
        ),
        (
            "dns-sd",
            ["-L", TV, LEGACY, "local."],
            R(lookup(TV, LEGACY, "Android.local.", 5555)),
        ),
        (
            "dns-sd",
            ["-B", "_androidtvremote2._tcp", "local."],
            R(
                "12:00:00.000  Add  3  13 local.  _androidtvremote2._tcp.  Living Room Sony TV\n"
                "12:00:00.001  Add  3  13 local.  _androidtvremote2._tcp.  Living Room Sony TV\n"
            ),
        ),
        (
            "dns-sd",
            ["-L", "Living Room Sony TV", "_androidtvremote2._tcp", "local."],
            R("x can be reached at android.local.:6466 (interface 13)\n"),
        ),
        (
            "dns-sd",
            ["-G", "v4", "Android_43W5CGQ4.local."],
            R(addr("Android_43W5CGQ4.local.", "192.168.86.36")),
        ),
        (
            "dns-sd",
            ["-G", "v4", "Android-2.local."],
            R(addr("Android-2.local.", "192.168.86.61")),
        ),
        (
            "dns-sd",
            ["-G", "v4", "Android_A2G1X1TA.local."],
            R(addr("Android_A2G1X1TA.local.", "192.168.86.70")),
        ),
        (
            "dns-sd",
            ["-G", "v4", "Android.local."],
            R(addr("Android.local.", "192.168.86.31")),
        ),
    ]


def ts(json_text=TAILSCALE, rc=0, sleep=None):
    return ("tailscale", ["status", "--json"], R(json_text, rc=rc, sleep=sleep))


def adb(args, *answers):
    return ("adb", args, list(answers) if len(answers) > 1 else answers[0])


def scenarios():
    s = {}

    # argparse: help at several widths, prog lengths, and its errors.
    for cols in ("80", "60", "40", "200", "30", "1", "0", "junk", None):
        s[f"help-cols-{cols}"] = Scenario(["--help"], columns=cols)
    s["help-long-prog"] = Scenario(
        ["-h"], prog="adb-connect-with-a-really-long-program-name-x"
    )
    s["help-long-prog-narrow"] = Scenario(
        ["-h"], prog="adb-connect-with-a-long-name", columns="50"
    )
    for i, argv in enumerate(
        [
            ["--bogus"],
            ["--di"],
            ["--d"],
            ["--p", "1"],
            ["--json=1"],
            ["--all="],
            ["--tcpip", "x"],
            ["--tcpip=1__0"],
            ["--timeout", "abc"],
            ["--timeout", "-inf"],
            ["-d"],
            ["--ip", "-x"],
            ["--all", "-d", "x"],
            ["--all", "--ip", "1.2.3.4"],
            ["--all", "--print-serial"],
            ["--"],
            ["--json", "--"],
            ["-d", "--", "x"],
            ["-hx"],
            ["-h=x"],
            ["-dfold", "-xyz"],
            ["--=x"],
            ["-", "x"],
            ["--all", "--", "--all"],
            ["--tcpip=--"],
            ["positional"],
            ["--discover", "-h", "--bogus"],
            ["--bogus", "--di"],
            ["-h", "--di"],
            ["--di", "-h"],
        ]
    ):
        s[f"argparse-{i}"] = Scenario(argv, columns="70")

    # --status
    s["status-text"] = Scenario(["--status"], [adb(["devices", "-l"], R(ADB_DEVICES))])
    s["status-json"] = Scenario(
        ["--status", "--json"], [adb(["devices", "-l"], R(ADB_MULTI))]
    )
    s["status-multi-text"] = Scenario(
        ["--status"], [adb(["devices", "-l"], R(ADB_MULTI))]
    )
    s["status-empty"] = Scenario(["--status"], [adb(["devices", "-l"], R(EMPTY_ADB))])
    s["status-adb-fails"] = Scenario(
        ["--status", "--json"], [adb(["devices", "-l"], R("boom", rc=1))]
    )
    s["status-no-adb"] = Scenario(["--status"], missing={"adb"})
    s["status-odd-lines"] = Scenario(
        ["--status", "--json"],
        [
            adb(
                ["devices", "-l"],
                R(
                    "List of devices attached\r\n  lonely  \r\nX1 device status:override id:other weird::prop model:\n"
                    "adb-SER-1._adb._tcp offline\n\x0bfoo bar\x1cbaz\n"
                ),
            )
        ],
    )
    s["status-serial-override"] = Scenario(
        ["--status"],
        [
            adb(
                ["devices", "-l"],
                R(
                    "List of devices attached\nadb-LABPHONE-x._adb-tls-connect._tcp device model:Mystery\n"
                ),
            )
        ],
        config='{"devices": [{"key": "lab", "serial": "labphone", "display_name": "Lab", "role": 7, "aliases": "lb"}]}',
    )
    s["status-non-utf8-adb"] = Scenario(
        ["--status"], [adb(["devices", "-l"], R(b"List\nX \xff device\n"))], crash=True
    )

    # --discover
    s["discover-json"] = Scenario(
        ["--discover", "--json"],
        net_household() + [ts(), adb(["devices", "-l"], R(ADB_MULTI))],
    )
    s["discover-text"] = Scenario(
        ["--list"], net_household() + [ts(), adb(["devices", "-l"], R(ADB_MULTI))]
    )
    s["discover-no-tailscale"] = Scenario(
        ["--discover", "--json", "--no-tailscale"], net_household()
    )
    s["discover-tailscale-missing"] = Scenario(
        ["--discover"], net_household(), missing={"tailscale"}
    )
    s["discover-tailscale-bad-json"] = Scenario(
        ["--discover", "--json"], net_household() + [ts("{nope")]
    )
    s["discover-tailscale-list"] = Scenario(
        ["--discover"], net_household() + [ts("[]")], crash=True
    )
    s["discover-tailscale-odd"] = Scenario(
        ["--discover", "--json"],
        net_household()
        + [
            ts(
                '{"Peer": {"a": {"OS": "Android", "HostName": "Pixel 4 XL", "TailscaleIPs": [":x", "100.9.9.9"], '
                '"Online": 1, "Active": null}, "b": {"OS": "android", "TailscaleIPs": []}}, "Self": NaN}'
            )
        ],
    )
    s["discover-tailscale-int-ip"] = Scenario(
        ["--discover"],
        net_household()
        + [ts('{"Peer": {"a": {"OS": "android", "TailscaleIPs": [5]}}}')],
        crash=True,
    )
    s["discover-nothing"] = Scenario(["--discover"])
    s["discover-nothing-json"] = Scenario(["--discover", "--json"], missing={"dns-sd"})
    s["discover-no-dns-sd-negative-timeout"] = Scenario(
        ["--discover", "--timeout", "-1"], missing={"dns-sd"}
    )
    s["discover-negative-timeout"] = Scenario(
        ["--discover", "--timeout", "-1"], crash=True
    )
    s["discover-nan-timeout"] = Scenario(["--discover", "--timeout", "nan"], crash=True)
    s["discover-stale-dupes"] = Scenario(
        ["--discover", "--json", "--no-tailscale"],
        [
            (
                "dns-sd",
                ["-B", TLS, "local."],
                R(browse(TLS, "adb-66211FDDJ000XR-old", "adb-66211FDDJ000XR-new")),
            ),
            (
                "dns-sd",
                ["-L", "adb-66211FDDJ000XR-old", TLS, "local."],
                R(lookup("adb-66211FDDJ000XR-old", TLS, "old.local.", 39000, FOLD_TXT)),
            ),
            (
                "dns-sd",
                ["-L", "adb-66211FDDJ000XR-new", TLS, "local."],
                R(lookup("adb-66211FDDJ000XR-new", TLS, "new.local.", 46223, FOLD_TXT)),
            ),
            ("dns-sd", ["-G", "v4", "new.local."], R(addr("new.local.", "10.0.0.2"))),
        ],
    )
    s["discover-hostname-fallback"] = Scenario(
        ["--discover", "--json", "--no-tailscale"],
        [
            ("dns-sd", ["-B", TLS, "local."], R(browse(TLS, "adb-LOCAL-1"))),
            (
                "dns-sd",
                ["-L", "adb-LOCAL-1", TLS, "local."],
                R(lookup("adb-LOCAL-1", TLS, "localhost.", 5037, "name=Local")),
            ),
        ],
    )
    s["discover-crlf-and-unicode"] = Scenario(
        ["--discover", "--json", "--no-tailscale"],
        [
            (
                "dns-sd",
                ["-B", TLS, "local."],
                R(browse(TLS, "adb-UNI-1").replace("\n", "\r\n")),
            ),
            (
                "dns-sd",
                ["-L", "adb-UNI-1", TLS, "local."],
                R(
                    lookup(
                        "adb-UNI-1",
                        TLS,
                        "uni.local.",
                        "0042",
                        "given_name=Café\\ Ω\\ \U0001f600 serial=uni-1",
                    ).replace("\n", "\r")
                ),
            ),
            ("dns-sd", ["-G", "v4", "uni.local."], R(addr("uni.local.", "10.0.0.3"))),
        ],
    )

    # --all
    s["all-json"] = Scenario(
        ["--all", "--json"],
        net_household()
        + [
            ts(),
            adb(["devices", "-l"], R(ADB_MULTI)),
            adb(
                ["disconnect", "192.168.86.61:41295"],
                R("disconnected 192.168.86.61:41295"),
            ),
        ],
    )
    s["all-text-connects"] = Scenario(
        ["--all"],
        net_household()
        + [
            ts(),
            adb(
                ["devices", "-l"],
                R(EMPTY_ADB),
                R(EMPTY_ADB),
                R(
                    f"List of devices attached\n{P4}._adb-tls-connect._tcp unauthorized\n"
                ),
            ),
            adb(
                ["connect", f"{FOLD}._adb-tls-connect._tcp"],
                R(f"connected to {FOLD}._adb-tls-connect._tcp"),
            ),
            adb(
                ["connect", f"{P4}._adb-tls-connect._tcp"],
                R(f"connected to {P4}._adb-tls-connect._tcp"),
            ),
            adb(
                ["connect", f"{WATCH}._adb-tls-connect._tcp"],
                R("", "failed to authenticate", rc=1),
            ),
        ],
    )
    s["all-tcpip"] = Scenario(
        ["--all", "--tcpip", "--json"],
        net_fold_only()
        + [
            ts(),
            adb(
                ["connect", "100.74.154.64:41067"],
                R("connected to 100.74.154.64:41067"),
            ),
            adb(
                ["-s", "100.74.154.64:41067", "tcpip", "5555"],
                R("", "error: closed", rc=1),
            ),
        ],
    )
    s["all-none"] = Scenario(["--all"])
    s["all-none-json"] = Scenario(
        ["--all", "--json"],
        [
            ("dns-sd", ["-B", LEGACY, "local."], R(browse(LEGACY, TV))),
            (
                "dns-sd",
                ["-L", TV, LEGACY, "local."],
                R(lookup(TV, LEGACY, "Android.local.", 5555, "name=TV")),
            ),
        ],
    )
    s["all-empty-device-is-falsy"] = Scenario(["--all", "-d", "", "--json"])

    # The default connect flow.
    connected_fold = (
        f"List of devices attached\n{FOLD}._adb-tls-connect._tcp device product:yogi\n"
    )
    s["connect-default"] = Scenario(
        [],
        net_fold_only()
        + [
            ts(),
            adb(["devices", "-l"], R(EMPTY_ADB), R(connected_fold)),
            adb(
                ["connect", f"{FOLD}._adb-tls-connect._tcp"],
                R(f"connected to {FOLD}._adb-tls-connect._tcp"),
            ),
        ],
    )
    s["connect-default-json"] = Scenario(
        ["--json"],
        net_fold_only()
        + [
            ts(),
            adb(["devices", "-l"], R(EMPTY_ADB), R(connected_fold)),
            adb(
                ["connect", f"{FOLD}._adb-tls-connect._tcp"],
                R(f"already connected to {FOLD}._adb-tls-connect._tcp\n"),
            ),
        ],
    )
    s["connect-already-attached"] = Scenario(
        ["-d", "fold", "--json"],
        net_household() + [ts(), adb(["devices", "-l"], R(ADB_MULTI))],
    )
    s["connect-print-serial"] = Scenario(
        ["--print-serial", "-d", "pixel4"],
        net_household() + [ts(), adb(["devices", "-l"], R(ADB_MULTI))],
    )
    s["connect-print-serial-fails"] = Scenario(
        ["--print-serial", "--device", "tv"],
        net_household() + [ts(), adb(["devices", "-l"], R(ADB_MULTI))],
    )
    s["connect-print-serial-no-stderr"] = Scenario(
        ["--print-serial", "--device", "tv", "--ip", "10.1.1.1"],
        net_household() + [ts(), adb(["connect", "10.1.1.1:5555"], R("nope"))],
    )
    s["connect-ambiguous-filter"] = Scenario(["-d", "pixel"], net_household() + [ts()])
    s["connect-ambiguous-filter-json"] = Scenario(
        ["-d", "PIXEL", "--json"], net_household() + [ts()]
    )
    s["connect-ambiguous-default"] = Scenario(
        [],
        [
            ("dns-sd", ["-B", TLS, "local."], R(browse(TLS, "adb-ZZZ-1", "adb-AAA-1"))),
            (
                "dns-sd",
                ["-L", "adb-ZZZ-1", TLS, "local."],
                R(lookup("adb-ZZZ-1", TLS, "z.local.", 1, "name=Galaxy")),
            ),
            (
                "dns-sd",
                ["-L", "adb-AAA-1", TLS, "local."],
                R(lookup("adb-AAA-1", TLS, "a.local.", 2, "name=Moto")),
            ),
        ],
    )
    s["connect-not-found"] = Scenario(["-d", "GalaxyS24"], net_fold_only() + [ts()])
    s["connect-not-found-json"] = Scenario(["--json"], missing={"dns-sd"})
    s["connect-tv-no-route"] = Scenario(
        ["-d", "sony"],
        net_household()
        + [
            ts(),
            adb(
                ["devices", "-l"],
                R(EMPTY_ADB),
                R("List of devices attached\n192.168.86.31:5555 device\n"),
            ),
            adb(
                ["connect", "192.168.86.31:5555"],
                R("failed to connect to '192.168.86.31:5555': No route to host"),
                R("connected to 192.168.86.31:5555"),
            ),
        ],
    )
    s["connect-tv-unauthorized"] = Scenario(
        ["-d", "tv"],
        net_household()
        + [
            ts(),
            adb(
                ["devices", "-l"],
                R(EMPTY_ADB),
                R("List of devices attached\n192.168.86.31:5555 unauthorized\n"),
            ),
            adb(
                ["connect", "192.168.86.31:5555"], R("connected to 192.168.86.31:5555")
            ),
        ],
    )
    s["connect-manual-ip-tcpip"] = Scenario(
        ["-d", "fold", "--ip", "10.9.8.7", "--tcpip", "7777"],
        net_fold_only()
        + [
            ts(),
            adb(["connect", "10.9.8.7:41067"], R("connected to 10.9.8.7:41067")),
            adb(
                ["-s", "10.9.8.7:41067", "tcpip", "7777"],
                R("restarting in TCP mode port: 7777"),
            ),
        ],
    )
    s["connect-tcpip-fails-text"] = Scenario(
        ["--tcpip"],
        net_fold_only()
        + [
            ts(),
            adb(
                ["connect", "100.74.154.64:41067"],
                R("connected to 100.74.154.64:41067"),
            ),
            adb(
                ["-s", "100.74.154.64:41067", "tcpip", "5555"],
                R("", "error: device offline", rc=1),
            ),
        ],
    )
    s["connect-tcpip-zero"] = Scenario(
        ["--tcpip", "0", "--json"],
        net_fold_only()
        + [
            ts(),
            adb(["devices", "-l"], R(EMPTY_ADB), R(connected_fold)),
            adb(
                ["connect", f"{FOLD}._adb-tls-connect._tcp"],
                R(f"connected to {FOLD}._adb-tls-connect._tcp"),
            ),
        ],
    )
    s["connect-disconnect-first"] = Scenario(
        ["--disconnect-first", "--no-tailscale"],
        net_fold_only()
        + [
            adb(["devices", "-l"], R(EMPTY_ADB), R(connected_fold)),
            adb(
                ["connect", f"{FOLD}._adb-tls-connect._tcp"],
                R(f"connected to {FOLD}._adb-tls-connect._tcp"),
            ),
        ],
    )
    s["connect-disconnect-first-device"] = Scenario(
        ["--disconnect-first", "-d", "pixel4", "--json"],
        net_household()
        + [
            ts(),
            adb(
                ["devices", "-l"],
                R(ADB_MULTI),
                R(EMPTY_ADB),
                R(f"List of devices attached\n{P4}._adb-tls-connect._tcp device\n"),
            ),
            adb(
                ["connect", f"{P4}._adb-tls-connect._tcp"],
                R(f"connected to {P4}._adb-tls-connect._tcp"),
            ),
        ],
    )
    s["connect-adb-missing"] = Scenario(
        ["-d", "fold"], net_fold_only() + [ts()], missing={"adb"}
    )
    s["connect-fails"] = Scenario(
        ["-d", "watch"],
        net_household()
        + [
            ts(),
            adb(
                ["connect", f"{WATCH}._adb-tls-connect._tcp"],
                R("failed to connect", "Connection refused\n", rc=1),
            ),
        ],
    )
    s["connect-tailscale-hangs"] = Scenario(
        ["--json", "-d", "fold"],
        net_fold_only()
        + [
            ts(sleep=10),
            adb(["devices", "-l"], R(EMPTY_ADB), R(connected_fold)),
            adb(
                ["connect", f"{FOLD}._adb-tls-connect._tcp"],
                R(f"connected to {FOLD}._adb-tls-connect._tcp"),
            ),
        ],
    )

    # --pair
    pair_net = [
        (
            "dns-sd",
            ["-B", PAIRING, "local."],
            R(browse(PAIRING, "adb-98271FFBA007YW-pair")),
        ),
        (
            "dns-sd",
            ["-L", "adb-98271FFBA007YW-pair", PAIRING, "local."],
            R(
                lookup(
                    "adb-98271FFBA007YW-pair",
                    PAIRING,
                    "Android-2.local.",
                    37379,
                    r"name=Pixel\ 4\ XL",
                )
            ),
        ),
        (
            "dns-sd",
            ["-G", "v4", "Android-2.local."],
            R(addr("Android-2.local.", "192.168.86.61")),
        ),
    ]
    paired = (
        "Successfully paired to 192.168.86.61:37379 [guid=adb-98271FFBA007YW-OflOTi]"
    )
    s["pair-bad-code"] = Scenario(["--pair", "12ab"])
    s["pair-bad-code-json"] = Scenario(["--pair", "1234567", "--json"])
    s["pair-empty-code-is-skipped"] = Scenario(
        ["--pair", "", "--json"], missing={"dns-sd"}
    )
    s["pair-nothing-advertising"] = Scenario(["--pair", "052698"])
    s["pair-success"] = Scenario(
        ["--pair", " 052698 "],
        pair_net + [ts(), adb(["pair", "192.168.86.61:37379", "052698"], R(paired))],
    )
    s["pair-success-json"] = Scenario(
        ["--pair", "052698", "--json", "-d", "coral"],
        pair_net + [adb(["pair", "192.168.86.61:37379", "052698"], R(paired))],
    )
    s["pair-fails"] = Scenario(
        ["--pair", "052698"],
        pair_net
        + [
            adb(
                ["pair", "192.168.86.61:37379", "052698"],
                R("", "Failed: wrong code", rc=1),
            )
        ],
    )
    s["pair-filter-miss"] = Scenario(["--pair", "052698", "-d", "fold"], pair_net)
    s["pair-two-advertisers"] = Scenario(
        ["--pair", "052698", "--json"],
        [
            (
                "dns-sd",
                ["-B", PAIRING, "local."],
                R(browse(PAIRING, "adb-A-1", "adb-B-1")),
            ),
            (
                "dns-sd",
                ["-L", "adb-A-1", PAIRING, "local."],
                R(lookup("adb-A-1", PAIRING, "a.local.", 1, "name=A")),
            ),
            (
                "dns-sd",
                ["-L", "adb-B-1", PAIRING, "local."],
                R(lookup("adb-B-1", PAIRING, "b.local.", 2, "name=B")),
            ),
        ],
    )
    s["pair-unresolvable"] = Scenario(
        ["--pair", "052698"],
        [("dns-sd", ["-B", PAIRING, "local."], R(browse(PAIRING, "adb-A-1")))],
    )
    s["pair-nan-timeout"] = Scenario(
        ["--pair", "052698", "--timeout", "nan"], crash=True
    )
    s["pair-negative-timeout"] = Scenario(["--pair", "052698", "--timeout", "-3"])

    # The user profile file.
    s["config-invalid-json"] = Scenario(
        ["--status"], [adb(["devices", "-l"], R(ADB_DEVICES))], config='{"devices": [}'
    )
    s["config-bom"] = Scenario(
        ["--status"], [adb(["devices", "-l"], R(ADB_DEVICES))], config='﻿{"devices": []}'
    )
    s["config-bad-utf8"] = Scenario(
        ["--status"],
        [adb(["devices", "-l"], R(ADB_DEVICES))],
        config=b'{"devices": ["\xe2\x82"]}',
    )
    s["config-crlf-error-position"] = Scenario(
        ["--status"],
        [adb(["devices", "-l"], R(ADB_DEVICES))],
        config='{\r\n"a": 1,\r\n}',
    )
    s["config-is-directory"] = Scenario(
        ["--status"], [adb(["devices", "-l"], R(ADB_DEVICES))], config=DIR
    )
    s["config-list"] = Scenario(
        ["--status", "--json"],
        [adb(["devices", "-l"], R(ADB_DEVICES))],
        config='[{"key": " FOLD ", "display_name": "My Fold", "role": "primary"}, "x", {"key": ""}]',
    )
    s["config-not-list"] = Scenario(
        ["--status"],
        [adb(["devices", "-l"], R(ADB_DEVICES))],
        config='{"devices": {"key": "x"}}',
    )
    s["config-scalar"] = Scenario(
        ["--status"], [adb(["devices", "-l"], R(ADB_DEVICES))], config="3.5"
    )
    s["config-extra-profile-select"] = Scenario(
        ["-d", "lab", "--json", "--no-tailscale"],
        net_household() + [adb(["devices", "-l"], R(EMPTY_ADB))],
        config='{"devices": [{"key": "lab", "serial": "98271FFBA007YW", "display_name": "Lab Pixel", '
        '"aliases": ["lab", "bench"], "codename": "coral", "model_patterns": ["pixel 4 xl"], "default": 1}]}',
    )
    s["config-nonstr-alias-crash"] = Scenario(
        ["-d", "nomatch"],
        net_household() + [ts()],
        config='{"devices": [{"key": "fold", "aliases": [1, 2]}]}',
        crash=True,
    )
    s["config-string-patterns"] = Scenario(
        ["--discover", "--json", "--no-tailscale"],
        net_household(),
        config='{"devices": [{"key": "odd", "model_patterns": "zq", "role": ["x"]}]}',
    )

    # Real timing: real sleeps, real SIGTERM to dns-sd that would run forever.
    s["timing-all-none"] = Scenario(
        ["--all", "--timeout", "0.5"],
        [
            ("dns-sd", ["-B", TLS, "local."], R(browse(TLS), sleep=30)),
            ("dns-sd", ["-B", LEGACY, "local."], R(browse(LEGACY), sleep=30)),
        ],
        fast=False,
    )
    s["timing-discover-one"] = Scenario(
        ["--discover", "--json", "--timeout", "0.5", "--no-tailscale"],
        [
            ("dns-sd", ["-B", TLS, "local."], R(browse(TLS, FOLD), sleep=30)),
            (
                "dns-sd",
                ["-L", FOLD, TLS, "local."],
                R(
                    lookup(FOLD, TLS, "Android_43W5CGQ4.local.", 41067, FOLD_TXT),
                    sleep=30,
                ),
            ),
            (
                "dns-sd",
                ["-G", "v4", "Android_43W5CGQ4.local."],
                R(addr("Android_43W5CGQ4.local.", "192.168.86.36"), sleep=30),
            ),
        ],
        fast=False,
    )

    # Generated mDNS answers: odd TXT records, escapes, junk lines.
    rng = random.Random(20261024)
    alphabet = list("abcXYZ019 _-=.:\\\t") + ["\\ ", "é", "Ω", " ", "\\\\", "="]
    for i in range(12):
        insts = [f"adb-R{i}{j}-{rng.randint(0, 99)}" for j in range(rng.randint(1, 3))]
        svc = rng.choice([TLS, LEGACY])
        responses = [
            (
                "dns-sd",
                ["-B", svc, "local."],
                R(browse(svc, *insts, extra="garbage line\n Add x\n")),
            )
        ]
        for inst in insts:
            txt = " ".join(
                rng.choice(["serial", "name", "given_name", "api", "v", "k-1"])
                + "="
                + "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 8)))
                for _ in range(rng.randint(0, 5))
            )
            host = rng.choice(["Android.local.", "h-1.local..", "bravia.local."])
            responses.append(
                (
                    "dns-sd",
                    ["-L", inst, svc, "local."],
                    R(lookup(inst, svc, host, rng.randint(1, 65535), txt)),
                )
            )
            norm = host.rstrip(".") + "."
            responses.append(
                (
                    "dns-sd",
                    ["-G", "v4", norm],
                    R(addr(norm, f"10.0.{i}.{rng.randint(1, 254)}")),
                )
            )
        flag = rng.choice(
            [
                ["--discover", "--json"],
                ["--discover"],
                ["--json"],
                ["-d", rng.choice(["r", "tv", "bravia", "x"]), "--json"],
            ]
        )
        s[f"fuzz-{i}"] = Scenario(
            flag + ["--no-tailscale"],
            responses + [adb(["devices", "-l"], R(EMPTY_ADB))],
        )
    return s


SCENARIOS = scenarios()
_RESULTS = {}


def _run_pair(name):
    sc = SCENARIOS[name]
    return name, (run_impl("py", sc), run_impl("rs", sc))


class ParityTest(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls):
        # Every scenario has its own world, so the fast ones run in
        # parallel. The real-timing ones run alone afterwards, so a busy
        # machine cannot squeeze their sleep-then-SIGTERM windows.
        fast = [n for n, sc in SCENARIOS.items() if sc.fast]
        slow = [n for n, sc in SCENARIOS.items() if not sc.fast]
        workers = max(2, min(8, os.cpu_count() or 2))
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            _RESULTS.update(pool.map(_run_pair, fast))
        _RESULTS.update(map(_run_pair, slow))

    def check(self, name):
        sc = SCENARIOS[name]
        py, rs = _RESULTS[name]
        py_code, py_out, py_err, py_logs = py
        rs_code, rs_out, rs_err, rs_logs = rs
        self.assertEqual(
            rs_code,
            py_code,
            f"{name}: exit code\npy stderr:\n{py_err}\nrs stderr:\n{rs_err}",
        )
        self.assertEqual(rs_out, py_out, f"{name}: stdout")
        if sc.crash:
            # An uncaught exception: same type and message, the traceback
            # frames themselves naturally differ.
            self.assertEqual(py_code, 1, f"{name}: expected Python to raise\n{py_err}")
            self.assertEqual(
                rs_err.strip().splitlines()[-1],
                py_err.strip().splitlines()[-1],
                f"{name}: exception",
            )
        else:
            self.assertNotIn("Traceback", py_err, f"{name}: Python raised")
            self.assertEqual(rs_err, py_err, f"{name}: stderr")
        self.assertEqual(rs_logs, py_logs, f"{name}: commands run")


def _make(name):
    return lambda self: self.check(name)


for _name in SCENARIOS:
    setattr(ParityTest, "test_" + _name.replace("-", "_"), _make(_name))


class HarnessTest(unittest.TestCase):
    def test_paths_were_given(self):
        self.assertTrue(os.access(RUST_BIN, os.X_OK), RUST_BIN)
        self.assertTrue(os.path.isfile(PY_SRC), PY_SRC)

    def test_stand_ins_answer_and_log(self):
        sc = Scenario([], [adb(["devices", "-l"], R("one"), R("two"))])
        root = tempfile.mkdtemp(prefix="parity-harness-")
        try:
            env = build_world(root, sc)

            def run():
                return subprocess.run(
                    ["adb", "devices", "-l"], env=env, capture_output=True, text=True
                ).stdout

            self.assertEqual([run(), run(), run()], ["one", "two", "two"])
            self.assertEqual(read_log(root, "adb"), [["devices", "-l"]] * 3)
        finally:
            shutil.rmtree(root, ignore_errors=True)

    def test_a_divergence_is_caught(self):
        # The comparison is not vacuous: different arguments, different output.
        a = run_impl("py", Scenario(["--pair", "12ab"]))
        b = run_impl(
            "rs", Scenario(["--status"], [adb(["devices", "-l"], R(ADB_DEVICES))])
        )
        self.assertNotEqual(a[:3], b[:3])


if __name__ == "__main__":
    # Anything after the two paths selects tests, as unittest's own argv would.
    unittest.main(argv=[sys.argv[0]] + sys.argv[3:], verbosity=2)
