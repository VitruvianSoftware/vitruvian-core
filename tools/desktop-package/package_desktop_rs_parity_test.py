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

"""package-desktop.sh against the Rust binary (:package-desktop), side by side.

Every scenario runs twice in the same freshly built case directory, once
with the script (under PARITY_BASH, default bash on PATH) and once with the
binary, and the two runs must agree on:

  * the exit status, stdout and stderr;
  * every call to the stand-in tools (codesign, security, hdiutil, lipo,
    xcrun, gh, git, python3, file, sleep), arguments in order;
  * the whole case directory afterwards (dist, the tap, $TMPDIR leftovers):
    names, types, modes and contents.

Real ditto / zip / tar / shasum / base64 / find / cp do the work they do in
a release, so the artifacts are real. PATH holds only the stand-ins and a
chosen set of real tools, so a scenario can take a tool away.

Before comparing, the program's own path becomes <prog> (bash names the
script where the port names itself), each mktemp directory becomes tmp.N in
order of first mention, and the date column of `ls -lh` is masked. The mock
app has fixed timestamps, so ditto's archives (macOS) are compared byte for
byte; zip and tar, the fallbacks without ditto (Linux, or a scenario that
takes ditto away), stamp the current time into what they make, so there
SHA-256 values are masked and archives compared by size.

The helpers are also replayed through the probe (:package-desktop-rs-probe)
against the script's functions, sourced as a library.

Run under the C locale: bash sorts pathname expansions by the locale's
collation and the port in byte order, which is the C locale's.
"""

import hashlib
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
SH = os.path.join(HERE, os.environ["PACKAGE_DESKTOP_SH"])
RS = os.path.join(HERE, os.environ["PACKAGE_DESKTOP_RS"])
PROBE = os.path.join(HERE, os.environ["PACKAGE_DESKTOP_PROBE"])
BASH = os.environ.get("PARITY_BASH") or shutil.which("bash") or "bash"
SYSTEM_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"

REAL_TOOLS = """sh bash env cat cp mv rm mkdir ln ls chmod touch find grep sed head
cut tr basename dirname mktemp sort awk printf base64 xattr ditto zip unzip tar
shasum sha256sum uname date wc fold od cmp test expr true false""".split()
HAVE_DITTO = shutil.which("ditto", path=SYSTEM_PATH) is not None

STUBS = {
    "codesign": r"""
log codesign "$@"
case " $* " in *" --verify "*) exit "${CODESIGN_VERIFY_RC:-0}" ;; esac
exit "${CODESIGN_RC:-0}"
""",
    "security": r"""
log security "$@"
printf '%b' "${SECURITY_OUT-}"
exit "${SECURITY_RC:-0}"
""",
    "hdiutil": r"""
log hdiutil "$@"
case "$1" in
  detach) echo "hdiutil: detach failed - No such file or directory" >&2; exit 1 ;;
  create)
    n=0; [ -f "$CASE/hdiutil.fails" ] && n="$(cat "$CASE/hdiutil.fails")"
    if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$CASE/hdiutil.fails"; echo "hdiutil: create failed" >&2; exit 1; fi
    rw=""; src=""; prev=""
    for a in "$@"; do
      [ "$prev" = "-ov" ] && rw="$a"
      [ "$prev" = "-srcfolder" ] && src="$a"
      prev="$a"
    done
    { echo "UDRW image"; ls -1A "$src"; } > "$rw" ;;
  convert)
    out=""; prev=""
    for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
    { echo "UDZO image of:"; cat "$2"; } > "$out"
    exit "${HDIUTIL_CONVERT_RC:-0}" ;;
esac
""",
    "lipo": r"""
log lipo "$@"
case "$1" in
  -info) printf '%b' "${LIPO_INFO-Architectures in the fat file: $2 are: x86_64 arm64\n}"; exit "${LIPO_INFO_RC:-0}" ;;
esac
exit "${LIPO_RC:-0}"
""",
    "xcrun": r"""
log xcrun "$@"
if [ "$1 $2" = "notarytool submit" ]; then
  key=""; prev=""
  for a in "$@"; do [ "$prev" = "--key" ] && key="$a"; prev="$a"; done
  echo "key file starts: $(head -1 "$key" 2>/dev/null)" >> "$LOG"
  [ -f "$3" ] || echo "submitted a missing file" >> "$LOG"
  exit "${XCRUN_SUBMIT_RC:-0}"
fi
exit "${XCRUN_STAPLE_RC:-0}"
""",
    "gh": r"""
log gh "$@"
case "$1 $2" in
  "release upload")
    name="$(basename "$4")"
    if [ "$name" != "${GH_STUB_DROP:-}" ] && [ -s "$4" ]; then echo "$name" >> "$CASE/gh.state"; fi
    exit "${GH_UPLOAD_RC:-0}" ;;
  "release view")
    cat "$CASE/gh.state" 2>/dev/null || true
    exit "${GH_VIEW_RC:-0}" ;;
esac
exit 1
""",
    "git": r"""
log git "$@"
case "$1" in
  clone) [ "${GIT_CLONE_RC:-0}" = 0 ] || exit "$GIT_CLONE_RC"; for a in "$@"; do last="$a"; done; mkdir -p "$last" ;;
esac
case " $* " in
  *" diff --cached --quiet "*) exit "${GIT_DIFF_RC:-1}" ;;
  *" push "*) exit "${GIT_PUSH_RC:-0}" ;;
esac
exit 0
""",
    "python3": r"""
log python3 "$@"
echo "sync says hello"
exit "${PY_RC:-0}"
""",
    "file": r"""
case "$2" in
  */MacOS/*|*.dylib|*/Frameworks/*) echo "Mach-O universal binary with 2 architectures" ;;
  *) echo "ASCII text" ;;
esac
exit "${FILE_RC:-0}"
""",
    "sleep": r"""
log sleep "$@"
""",
}

STUB_HEAD = r"""#!/bin/sh
log() {
  { printf '%s' "$1"; shift; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$LOG"
}
"""

PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>2.3.4</string>
</dict>
</plist>
"""

# Built from parts so the file holds nothing shaped like a real private key.
DASHES = "-----"
PEM = f"{DASHES}BEGIN PRIVATE KEY{DASHES}\nTEST\n{DASHES}END PRIVATE KEY{DASHES}"

TMP_RE = re.compile(rb"tmp\.[A-Za-z0-9]{6,}")
DATE_RE = re.compile(rb"\b[A-Z][a-z]{2} +\d{1,2} +(\d{1,2}:\d{2}|\d{4})\b")
SHA_RE = re.compile(rb"\b[0-9a-f]{64}\b")


def b64(text):
    import base64

    return base64.b64encode(text.encode()).decode()


class Case:
    """One scenario's directory: the stand-ins, the tools, the mock app."""

    def __init__(self, root, omit=(), app="MockApp.app", sync_script=True):
        self.root = root
        if os.path.exists(root):
            shutil.rmtree(root)
        os.makedirs(root)
        self.stubs = os.path.join(root, "stubs")
        self.tools = os.path.join(root, "tools-bin")
        self.tmp = os.path.join(root, "tmpdir")
        self.log = os.path.join(root, "calls.log")
        for d in (self.stubs, self.tools, self.tmp):
            os.makedirs(d)
        for name, body in STUBS.items():
            if name in omit:
                continue
            path = os.path.join(self.stubs, name)
            with open(path, "w") as f:
                f.write(STUB_HEAD + body)
            os.chmod(path, 0o755)
        for name in REAL_TOOLS:
            if name in omit:
                continue
            real = shutil.which(name, path=SYSTEM_PATH)
            if real:
                os.symlink(real, os.path.join(self.tools, name))
        open(self.log, "w").close()
        self.app = os.path.join(root, app)
        os.makedirs(os.path.join(self.app, "Contents", "MacOS"))
        os.makedirs(os.path.join(self.app, "Contents", "Frameworks"))
        os.makedirs(os.path.join(self.app, "Contents", "Resources"))
        exe = os.path.join(
            self.app,
            "Contents",
            "MacOS",
            app[: -len(".app")] if app.endswith(".app") else app,
        )
        with open(exe, "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(exe, 0o755)
        with open(
            os.path.join(self.app, "Contents", "Frameworks", "Lib.dylib"), "w"
        ) as f:
            f.write("not really a dylib\n")
        with open(
            os.path.join(self.app, "Contents", "Resources", "notes.txt"), "w"
        ) as f:
            f.write("resources\n")
        with open(os.path.join(self.app, "Contents", "Info.plist"), "w") as f:
            f.write(PLIST)
        # A stand-in repository root beside the program, as in a checkout.
        self.fake_root = os.path.join(root, "repo")
        os.makedirs(os.path.join(self.fake_root, "tools", "desktop-package"))
        if sync_script:
            os.makedirs(os.path.join(self.fake_root, "tools", "sync-downloads"))
            open(
                os.path.join(
                    self.fake_root, "tools", "sync-downloads", "sync_downloads.py"
                ),
                "w",
            ).close()
        self.dist = os.path.join(root, "dist")

    def pin_times(self):
        """Fixed times on the app, so its archives are the same bytes on both runs."""
        if not os.path.isdir(self.app):
            return
        for dirpath, dirnames, filenames in os.walk(self.app, topdown=False):
            for name in filenames + dirnames:
                os.utime(
                    os.path.join(dirpath, name),
                    (1700000000, 1700000000),
                    follow_symlinks=False,
                )
        os.utime(self.app, (1700000000, 1700000000))

    def install(self, src, name):
        dst = os.path.join(self.fake_root, "tools", "desktop-package", name)
        shutil.copyfile(src, dst)
        os.chmod(dst, 0o755)
        return dst


def snapshot(root, mask_archives):
    """Every entry under root: path, type, mode and content."""
    entries = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(dirnames + filenames):
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root)
            st = os.lstat(path)
            mode = stat.S_IMODE(st.st_mode)
            if rel.startswith(
                os.path.join("repo", "tools", "desktop-package", "package-desktop")
            ):
                continue  # the program under test itself
            if stat.S_ISLNK(st.st_mode):
                entries.append((rel, "link", os.readlink(path).encode()))
            elif stat.S_ISDIR(st.st_mode):
                if name in ("stubs", "tools-bin") and dirpath == root:
                    continue
                entries.append((rel, "dir", oct(mode).encode()))
            else:
                with open(path, "rb") as f:
                    data = f.read()
                if mask_archives and (name.endswith(".zip") or name.endswith(".tgz")):
                    data = b"an archive" if data else b"empty"
                elif b"\0" in data or len(data) > 1 << 20:
                    data = b"sha256:" + hashlib.sha256(data).hexdigest().encode()
                entries.append((rel, "file " + oct(mode), data))
        dirnames[:] = [
            d for d in dirnames if not (dirpath == root and d in ("stubs", "tools-bin"))
        ]
    return entries


class Parity(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls):
        cls.work = os.path.realpath(tempfile.mkdtemp())
        cls.count = 0

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work)
        print(f"{cls.count} scenarios matched")

    def run_side(self, which, args, env, case_kwargs, prepare, cwd_rel):
        root = os.path.join(self.work, "case")
        case = Case(root, **case_kwargs)
        if which == "sh":
            prog = case.install(SH, "package-desktop.sh")
            cmd = [BASH, prog]
        else:
            prog = case.install(RS, "package-desktop")
            cmd = [prog]
        if prepare:
            prepare(case)
        case.pin_times()
        full = {
            "PATH": case.stubs + ":" + case.tools,
            "HOME": root,
            "TMPDIR": case.tmp,
            "LOG": case.log,
            "CASE": root,
        }
        for k, v in env.items():
            if v is None:
                full.pop(k, None)
            else:
                full[k] = v.replace("{case}", root)
        argv = [a.replace("{case}", root) for a in args]
        cwd = os.path.join(root, cwd_rel) if cwd_rel else root
        p = subprocess.run(cmd + argv, env=full, cwd=cwd, capture_output=True)
        with open(case.log, "rb") as f:
            calls = f.read()
        # zip and tar (the fallbacks without ditto) stamp the current time
        # into what they make.
        stamped = not HAVE_DITTO or "ditto" in case_kwargs.get("omit", ())
        tree = snapshot(root, mask_archives=stamped)
        return self.normalise(
            prog, p.returncode, p.stdout, p.stderr, calls, tree, stamped
        )

    def normalise(self, prog, rc, stdout, stderr, calls, tree, stamped):
        texts = (
            [stdout, stderr, calls]
            + [t[2] for t in tree]
            + [t[0].encode() for t in tree]
        )
        names = {}
        for t in texts:
            for m in TMP_RE.finditer(t):
                names.setdefault(m.group(0), b"tmp.%d" % (len(names) + 1))

        def fix(b):
            b = b.replace(prog.encode(), b"<prog>")
            b = TMP_RE.sub(lambda m: names[m.group(0)], b)
            b = DATE_RE.sub(b"<date>", b)
            if stamped:
                b = SHA_RE.sub(b"<sha256>", b)
            return b

        # Sorted after renaming: mktemp's random names would otherwise order
        # the same leftovers differently on each run.
        tree = sorted((fix(rel.encode()), kind, fix(data)) for rel, kind, data in tree)
        return rc, fix(stdout), fix(stderr), fix(calls), tree

    def both(
        self, args, env=None, expect_rc=None, prepare=None, cwd=None, **case_kwargs
    ):
        env = env or {}
        self.__class__.count += 1
        got_sh = self.run_side("sh", args, env, case_kwargs, prepare, cwd)
        got_rs = self.run_side("rs", args, env, case_kwargs, prepare, cwd)
        label = f"{args} env={env} case={case_kwargs}"
        for i, part in enumerate(("exit status", "stdout", "stderr", "tool calls")):
            self.assertEqual(got_sh[i], got_rs[i], f"{part} differ: {label}")
        self.assertEqual(got_sh[4], got_rs[4], f"files differ: {label}")
        if expect_rc is not None:
            self.assertEqual(
                got_rs[0],
                expect_rc,
                f"{label}\n{got_rs[1].decode()}\n{got_rs[2].decode()}",
            )
        return got_rs

    # -- shorthand -----------------------------------------------------------

    def pkg(self, extra=(), env=None, expect_rc=None, app="{case}/MockApp.app", **kw):
        args = [
            "--app-path",
            app,
            "--dist-dir",
            "{case}/dist",
            "--version",
            "2.3.4",
        ] + list(extra)
        return self.both(args, env, expect_rc, **kw)

    # -- options ---------------------------------------------------------------

    def test_options(self):
        self.both([], expect_rc=1)
        self.both(["--help"], expect_rc=0)
        self.both(["-h", "--bogus"], expect_rc=0)
        self.both(["--bogus"], expect_rc=1)
        self.both(["--dry-run", "extra"], expect_rc=1)
        for opt in (
            "--app-path",
            "--archive",
            "--app-name",
            "--version",
            "--dist-dir",
            "--cask-name",
            "--cask-desc",
            "--cask-homepage",
            "--entitlements",
            "--repo",
            "--tag",
            "--require-asset",
        ):
            self.both(["--dry-run", opt], expect_rc=1)
        self.both(["--app-path", "{case}/nope.app", "--dry-run"], expect_rc=1)
        self.both(["--archive", "{case}/nope.zip", "--dry-run"], expect_rc=1)

    # -- packaging -------------------------------------------------------------

    def test_dry_runs(self):
        self.pkg(["--skip-signing", "--skip-dmg", "--dry-run"], expect_rc=0)
        self.pkg(["--skip-dmg", "--dry-run"], expect_rc=0)
        self.pkg(["--dry-run"], expect_rc=0)
        self.pkg(["--dry-run", "--skip-thinning"], expect_rc=0)
        self.pkg(["--dry-run", "--skip-signing"], expect_rc=0)

    def test_signing(self):
        ent = ["--entitlements", "{case}/MockApp.app/Contents/Info.plist"]
        self.pkg(["--skip-dmg", "--dry-run"] + ent, expect_rc=0)
        self.pkg(
            ["--skip-dmg", "--dry-run", "--entitlements", "{case}/missing.plist"],
            expect_rc=0,
        )
        self.pkg(
            ["--dry-run"] + ent,
            {"SIGNING_IDENTITY": "Developer ID Application: Env (T1)"},
            expect_rc=0,
        )
        listing = (
            '  1) AAAA "Apple Development: dev (X)"\\n'
            '  2) BBBB "Developer ID Application: Vitruvian (TEAM1)"\\n'
            '  3) CCCC "Developer ID Application: Second (TEAM2)"\\n'
            "     3 valid identities found\\n"
        )
        self.pkg(["--dry-run"], {"SECURITY_OUT": listing}, expect_rc=0)
        self.pkg(
            ["--skip-dmg", "--dry-run"], {"SECURITY_OUT": listing, "SECURITY_RC": "1"}
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            {"SECURITY_OUT": 'Developer ID Application a"b"c"d\\n'},
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            {"SECURITY_OUT": "Developer ID Application no quotes\\n"},
        )
        self.pkg(["--skip-dmg", "--dry-run"], {"CODESIGN_RC": "1"}, expect_rc=1)
        self.pkg(["--skip-dmg", "--dry-run"], {"CODESIGN_VERIFY_RC": "3"}, expect_rc=3)
        self.pkg(["--skip-dmg", "--dry-run"], omit=("codesign",), expect_rc=0)
        self.pkg(["--skip-dmg", "--dry-run"], omit=("security",), expect_rc=0)
        self.pkg(["--skip-dmg", "--dry-run"], {"FILE_RC": "1"}, expect_rc=0)

    def test_dmg_and_thinning(self):
        self.pkg(
            ["--dry-run"],
            {"LIPO_INFO": "Non-fat file: x is architecture: arm64\\n"},
            expect_rc=0,
        )
        self.pkg(
            ["--dry-run"],
            {"LIPO_INFO": "Architectures: arm64\\nand x86_64\\n"},
            expect_rc=0,
        )
        self.pkg(["--dry-run"], {"LIPO_INFO_RC": "1"}, expect_rc=0)
        self.pkg(["--dry-run"], {"LIPO_RC": "2"}, expect_rc=2)
        self.pkg(["--dry-run"], omit=("lipo",), expect_rc=0)
        self.pkg(["--dry-run"], {"HDIUTIL_CONVERT_RC": "4"}, expect_rc=4)
        self.pkg(["--dry-run"], omit=("hdiutil",), expect_rc=1)

        def fails(n):
            def prep(case):
                with open(os.path.join(case.root, "hdiutil.fails"), "w") as f:
                    f.write(str(n))

            return prep

        self.pkg(["--dry-run", "--skip-thinning"], prepare=fails(2), expect_rc=0)
        self.pkg(["--dry-run", "--skip-thinning"], prepare=fails(3), expect_rc=1)

    def test_zip_fallbacks(self):
        self.pkg(["--skip-signing", "--skip-dmg", "--dry-run"], omit=("ditto",))
        self.pkg(["--skip-signing", "--skip-dmg", "--dry-run"], omit=("ditto", "zip"))
        self.pkg(
            ["--skip-signing", "--skip-dmg", "--dry-run"], omit=("ditto", "zip", "tar")
        )
        self.pkg(["--skip-signing", "--skip-dmg", "--dry-run"], omit=("shasum",))
        self.pkg(
            ["--skip-signing", "--skip-dmg", "--dry-run"],
            omit=("shasum", "sha256sum"),
            expect_rc=1,
        )

    def test_notarization(self):
        creds = {"NOTARY_KEY_ID": "K1", "NOTARY_ISSUER_ID": "ISS"}

        # A .app is zipped with ditto before submission, unguarded: without
        # ditto (Linux) the script, and the port, stop there with 127.
        def app_rc(rc):
            return rc if HAVE_DITTO else 127

        self.pkg(["--dry-run"], dict(creds, NOTARY_API_KEY_P8=PEM), expect_rc=app_rc(0))
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            dict(creds, NOTARY_API_KEY_P8=b64(PEM + "\n")),
            expect_rc=app_rc(0),
        )
        wrapped = (
            "\n".join(b64(PEM + "\n")[i : i + 20] for i in range(0, 80, 20))
            + b64(PEM + "\n")[80:]
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            dict(creds, NOTARY_API_KEY_P8=wrapped),
            expect_rc=app_rc(0),
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            dict(creds, NOTARY_API_KEY_P8="not a key at all"),  # gitleaks:allow
            expect_rc=1,
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            dict(creds, NOTARY_API_KEY_P8="%%%%"),  # gitleaks:allow
            expect_rc=1,
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            dict(creds, NOTARY_KEY_FILE="{case}/AuthKey.p8"),
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            dict(creds, NOTARY_API_KEY_P8=PEM, XCRUN_SUBMIT_RC="5"),
            expect_rc=app_rc(5),
        )
        self.pkg(
            ["--dry-run", "--skip-thinning"],
            dict(creds, NOTARY_API_KEY_P8=PEM, XCRUN_STAPLE_RC="6"),
            expect_rc=app_rc(6),
        )
        # DMGs alone: no ditto needed, so the same everywhere.
        self.pkg(
            ["--dry-run", "--skip-thinning", "--skip-signing"],
            dict(creds, NOTARY_API_KEY_P8=PEM),
            expect_rc=0,
        )
        self.pkg(
            ["--dry-run", "--skip-thinning", "--skip-signing"],
            dict(creds, NOTARY_API_KEY_P8=PEM, XCRUN_SUBMIT_RC="5"),
            expect_rc=5,
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            {"NOTARY_KEY_ID": "K1", "NOTARY_API_KEY_P8": PEM},
            expect_rc=0,
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            dict(creds, NOTARY_API_KEY_P8=PEM),
            omit=("xcrun",),
            expect_rc=127,
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            dict(creds, NOTARY_API_KEY_P8=b64(PEM)),
            omit=("base64",),
            expect_rc=1,
        )

    def test_release_runs(self):
        tool = "MockApp-2.3.4-tool.zip"

        def preseed(case):
            os.makedirs(case.dist, exist_ok=True)
            with open(os.path.join(case.dist, tool), "w") as f:
                f.write("tool\n")

        rel = ["--skip-dmg", "--tag", "mock-app-v2.3.4", "--require-asset", tool]
        self.pkg(
            rel,
            {"GH_TOKEN": "stub", "VERIFY_RETRY_SECONDS": "0"},
            prepare=preseed,
            expect_rc=0,
        )
        self.pkg(
            rel,
            {"GITHUB_TOKEN": "stub", "VERIFY_RETRY_SECONDS": "0"},
            prepare=preseed,
            expect_rc=0,
        )
        self.pkg(
            rel,
            {"GH_TOKEN": "stub", "GH_STUB_DROP": tool},
            prepare=preseed,
            expect_rc=1,
        )
        self.pkg(
            rel,
            {"GH_TOKEN": "stub", "GH_STUB_DROP": tool, "GITHUB_ACTIONS": "true"},
            prepare=preseed,
            expect_rc=1,
        )
        self.pkg(rel, {}, prepare=preseed, expect_rc=1)
        self.pkg(
            rel, {"GH_TOKEN": "stub", "GH_UPLOAD_RC": "7"}, prepare=preseed, expect_rc=7
        )
        self.pkg(
            rel, {"GH_TOKEN": "stub", "GH_VIEW_RC": "8"}, prepare=preseed, expect_rc=8
        )
        self.pkg(
            rel, {"GH_TOKEN": "stub"}, prepare=preseed, omit=("gh",), expect_rc=127
        )
        self.pkg(["--skip-dmg", "--dry-run", "--require-asset", tool], expect_rc=1)
        self.pkg(
            ["--skip-dmg", "--dry-run", "--require-asset", tool],
            prepare=preseed,
            expect_rc=0,
        )
        self.pkg(
            ["--skip-dmg", "--dry-run", "--require-asset", tool],
            {"GITHUB_ACTIONS": "1"},
        )
        self.pkg(
            ["--skip-dmg", "--skip-signing"], {"TAG": "env-tag-v2.3.4", "GH_TOKEN": "s"}
        )
        self.pkg(
            ["--skip-dmg", "--skip-signing"],
            {"RELEASE_TAG": "rel-v2.3.4", "GH_TOKEN": "s"},
        )
        self.pkg(
            ["--skip-dmg", "--skip-signing", "--tag", "t-v1", "--repo", "me/x"],
            {"GH_TOKEN": "s"},
        )

    def test_tap_and_sync(self):
        rel = ["--skip-dmg", "--tag", "mock-app-v2.3.4"]
        env = {"GH_TOKEN": "stub", "HOMEBREW_TAP_TOKEN": "tap-token"}
        self.pkg(rel, env, expect_rc=0)
        self.pkg(rel, dict(env, GIT_DIFF_RC="0"), expect_rc=0)
        self.pkg(rel, dict(env, GIT_CLONE_RC="128"), expect_rc=128)
        self.pkg(rel, dict(env, GIT_PUSH_RC="9"), expect_rc=9)
        self.pkg(rel, dict(env, PY_RC="3"), expect_rc=3)
        self.pkg(rel, env, sync_script=False, expect_rc=0)
        self.pkg(
            rel, dict(env, BUILD_WORKSPACE_DIRECTORY="{case}/repo"), sync_script=True
        )
        self.pkg(rel, dict(env, BUILD_WORKSPACE_DIRECTORY="{case}"), expect_rc=0)
        self.pkg(
            ["--skip-dmg", "--dry-run", "--sync-downloads"],
            {"HOMEBREW_TAP_TOKEN": "t"},
            expect_rc=0,
        )
        self.pkg(
            ["--skip-dmg", "--dry-run", "--sync-downloads"],
            sync_script=False,
            expect_rc=0,
        )
        self.pkg(
            ["--skip-dmg", "--dry-run", "--sync-downloads"],
            omit=("python3",),
            expect_rc=127,
        )

    def test_inputs_and_metadata(self):
        # Version from Info.plist (PlistBuddy, on macOS), else the tag.
        self.both(
            [
                "--app-path",
                "{case}/MockApp.app",
                "--dist-dir",
                "{case}/dist",
                "--skip-dmg",
                "--dry-run",
            ]
        )
        self.both(
            [
                "--app-path",
                "{case}/MockApp.app",
                "--dist-dir",
                "{case}/dist",
                "--skip-dmg",
                "--dry-run",
                "--tag",
                "x-v9.8.7",
            ]
        )

        def no_plist(case):
            os.remove(os.path.join(case.app, "Contents", "Info.plist"))

        self.both(
            [
                "--app-path",
                "{case}/MockApp.app",
                "--dist-dir",
                "{case}/dist",
                "--skip-dmg",
                "--dry-run",
            ],
            prepare=no_plist,
            expect_rc=1,
        )
        self.both(
            [
                "--app-path",
                "{case}/MockApp.app",
                "--dist-dir",
                "{case}/dist",
                "--skip-dmg",
                "--dry-run",
                "--tag",
                "home-speaker-v1.11.0-beta.2",
            ],
            prepare=no_plist,
            expect_rc=0,
        )
        self.pkg(
            [
                "--skip-dmg",
                "--dry-run",
                "--app-name",
                "Other",
                "--cask-name",
                "c",
                "--cask-desc",
                "d",
                "--cask-homepage",
                "h",
            ],
            expect_rc=0,
        )
        self.pkg(
            ["--skip-dmg", "--dry-run"],
            {"GITHUB_REPOSITORY": "someone/else"},
            expect_rc=0,
        )
        self.both(
            [
                "--app-path",
                "{case}/HTTPServer.app/",
                "--dist-dir",
                "{case}/dist",
                "--version",
                "1.0",
                "--skip-dmg",
                "--dry-run",
            ],
            app="HTTPServer.app",
            expect_rc=0,
        )
        self.both(
            [
                "--app-path",
                "{case}/My App.app",
                "--dist-dir",
                "{case}/dist",
                "--version",
                "1.0",
                "--skip-dmg",
                "--dry-run",
            ],
            app="My App.app",
            expect_rc=0,
        )
        # Relative dist directory, from the case directory. Without ditto the
        # script zips from inside the staging directory, where a relative
        # output path does not resolve, so zip fails (exit 15); the port
        # keeps that.
        self.both(
            [
                "--app-path",
                "MockApp.app",
                "--dist-dir",
                "out/",
                "--version",
                "2.3.4",
                "--skip-dmg",
                "--dry-run",
            ],
            expect_rc=0 if HAVE_DITTO else 15,
        )
        self.both(
            [
                "--app-path",
                "MockApp.app",
                "--version",
                "2.3.4",
                "--skip-dmg",
                "--dry-run",
                "--skip-signing",
            ],
            expect_rc=0 if HAVE_DITTO else 15,
        )

        def blocked(case):
            with open(os.path.join(case.root, "dist"), "w") as f:
                f.write("a file where dist should be\n")

        self.pkg(["--skip-dmg", "--dry-run"], prepare=blocked, expect_rc=1)

        def extra_files(case):
            os.makedirs(os.path.join(case.dist, "MockApp-2.3.4-dir.zip"))
            with open(os.path.join(case.dist, "MockApp-2.3.4-old.dmg"), "w") as f:
                f.write("old\n")
            with open(os.path.join(case.dist, "MockApp-2.3.4-empty.zip"), "w") as f:
                pass

        self.pkg(["--skip-dmg", "--dry-run"], prepare=extra_files, expect_rc=0)

    def test_archives(self):
        def make_archive(inner):
            def prep(case):
                staging = os.path.join(case.root, "arc")
                os.makedirs(os.path.join(staging, inner) if inner else staging)
                target = os.path.join(staging, inner) if inner else staging
                shutil.copytree(
                    case.app, os.path.join(target, "Packed.app"), symlinks=True
                )
                with open(os.path.join(staging, "README"), "w") as f:
                    f.write("x\n")
                for dirpath, dirnames, filenames in os.walk(staging, topdown=False):
                    for name in filenames + dirnames:
                        os.utime(os.path.join(dirpath, name), (1700000000, 1700000000))
                out = os.path.join(case.root, "app.zip")
                subprocess.run(
                    ["zip", "-q", "-r", "-X", out, "."], cwd=staging, check=True
                )
                shutil.rmtree(staging)

            return prep

        if shutil.which("zip", path=SYSTEM_PATH) is None:
            self.skipTest("no zip here to build an archive with")
        base = [
            "--archive",
            "{case}/app.zip",
            "--dist-dir",
            "{case}/dist",
            "--version",
            "1.0",
            "--skip-dmg",
            "--dry-run",
        ]
        self.both(base, prepare=make_archive(""), expect_rc=0)
        self.both(base, prepare=make_archive("sub"), expect_rc=0)
        self.both(base, prepare=make_archive("a/b"), expect_rc=1)
        self.both(base, prepare=make_archive(""), omit=("ditto",), expect_rc=0)
        self.both(base, prepare=make_archive(""), omit=("ditto", "unzip"))
        self.both(
            base + ["--app-path", "{case}/MockApp.app"],
            prepare=make_archive(""),
            expect_rc=0,
        )

    def test_verify_only(self):
        tool = "MockApp-2.3.4-tool.zip"

        def released(names):
            def prep(case):
                with open(os.path.join(case.root, "gh.state"), "w") as f:
                    f.write("".join(n + "\n" for n in names))

            return prep

        full = []
        for n in ("universal.zip", "macOS.zip", "tool.zip"):
            full += [f"MockApp-2.3.4-{n}", f"MockApp-2.3.4-{n}.sha256"]
        v = [
            "--verify-only",
            "--app-name",
            "MockApp",
            "--tag",
            "mock-app-v2.3.4",
            "--skip-dmg",
        ]
        self.both(
            v + ["--require-asset", tool],
            {"VERIFY_RETRY_SECONDS": "0"},
            prepare=released(full),
            expect_rc=0,
        )
        self.both(v, prepare=released(full[:3]), expect_rc=1)
        self.both(v, {"VERIFY_RETRY_SECONDS": ""}, prepare=released([]), expect_rc=1)
        self.both(
            v, {"GITHUB_ACTIONS": "true"}, prepare=released(full[:1]), expect_rc=1
        )
        self.both(
            v[:-1] + ["--require-asset", tool], prepare=released(full), expect_rc=1
        )
        self.both(["--verify-only", "--tag", "x-v1.0"], expect_rc=1)
        self.both(["--verify-only", "--app-name", "MockApp"], expect_rc=1)
        self.both(
            [
                "--verify-only",
                "--app-name",
                "MockApp",
                "--version",
                "2.3.4",
                "--dist-dir",
                "{case}/dist",
            ],
            expect_rc=1,
        )
        self.both(
            [
                "--verify-only",
                "--app-name",
                "MockApp",
                "--tag",
                "mock-app-v2.3.4",
                "--dry-run",
                "--skip-dmg",
                "--dist-dir",
                "{case}/dist",
            ],
            expect_rc=1,
        )
        self.both(v, {"GH_VIEW_RC": "4"}, prepare=released(full), expect_rc=4)
        self.both(v, omit=("gh",), expect_rc=127)

    def test_harness_sees_a_difference(self):
        a = self.run_side("sh", ["--help"], {}, {}, None, None)
        b = self.run_side("rs", ["--bogus"], {}, {}, None, None)
        self.assertNotEqual(a, b)


class Helpers(unittest.TestCase):
    """The probe's helpers against the script's functions, sourced."""

    maxDiff = None

    ENV = {"PATH": SYSTEM_PATH, "LC_ALL": "C"}

    def shell(self, fn, *args):
        script = 'PACKAGE_DESKTOP_LIB_ONLY=1 . "$1"; shift; "$@"'
        p = subprocess.run(
            [BASH, "-c", script, "_", SH, fn] + list(args),
            capture_output=True,
            env=self.ENV,
        )
        return p.returncode, p.stdout, p.stderr

    def probe(self, fn, *args):
        p = subprocess.run([PROBE, fn] + list(args), capture_output=True, env=self.ENV)
        return p.returncode, p.stdout, p.stderr

    def same(self, fn, *args):
        self.assertEqual(self.shell(fn, *args), self.probe(fn, *args), f"{fn} {args}")

    def test_clean_version(self):
        for raw in (
            "home-speaker-v1.11.0",
            "vitruvian-v3.37.1",
            "nexus-agent-v1.20.1",
            "v2.0.4",
            "4.5.6",
            "nexus-agent-1.20.1",
            "vitruvian-v3.38.0-beta.1",
            "x-v12.3",
            "1.2.3.4",
            "1.2.3-",
            "1.2-rc",
            "app-v-latest",
            "app-vnext",
            "vnext",
            "",
            "a.1.2",
            "v1",
            "1.",
            ".1.2",
            "v1.2.3+build",
            "tag-v1.2.3-rc.1-x_y",
            "99999999999999999999.1",
            "x-v-v2",
            "1.2.3--",
            "a-1.2-b.3",
        ):
            self.same("clean_version", raw)

    def test_cask_name(self):
        for name in (
            "HomeSpeaker",
            "NexusAgent",
            "Vitruvian",
            "MyNewDesktopClient",
            "HTTPServer",
            "App2Go",
            "ABC",
            "aBCd",
            "Mock App",
            "",
            "x",
            "XMLHttpRequest",
            "iOSApp",
            "A1B2",
            "ÄpfelApp",
            "already-kebab",
        ):
            self.same("cask_name_for_app", name)

    def test_cask_formula(self):
        self.same(
            "generate_cask_ruby",
            "t",
            "1.0.0",
            "sha",
            "https://u",
            "TestApp",
            "A test app",
            "https://h",
        )
        self.same("generate_cask_ruby", "t", "1.0.0", "", "https://u", "TestApp")
        self.same(
            "generate_cask_ruby", "t", "1.0.0", "", "https://u", "TestApp", "", ""
        )
        self.same(
            "generate_cask_ruby", 'q"uote', "1", "s", "u", "A $B `c`", "d\\n", "%s"
        )

    def test_asset_lists(self):
        self.same("expected_artifact_names", "TestApp", "1.0.0")
        for flags in (
            ("false", "false"),
            ("true", "false"),
            ("false", "true"),
            ("true", "true"),
            ("yes", "1"),
        ):
            self.same("required_release_assets", "A", "1.0", *flags)
            self.same(
                "required_release_assets", "A", "1.0", *flags, "A-1.0-tool.zip", "x y"
            )
        self.same("required_release_assets", "A", "1.0")
        self.same("required_release_assets", "A", "1.0", "false")
        for req, present in (
            ("a\nb", "b\na\nc"),
            ("a\nb\nc", "b"),
            ("a.zip", "a.zip.sha256"),
            ("", ""),
            ("a\n\nb\n", ""),
            ("a", "a\n"),
            (" a", "a"),
            ("a*", "ab"),
            ("-v", "-v"),
        ):
            self.same("missing_assets", req, present)

    def test_notary_key(self):
        work = tempfile.mkdtemp()
        try:
            for value in (
                PEM,
                b64(PEM + "\n"),
                "not a key at all",
                "%%%",
                b64("hello"),
                " " + b64(PEM) + "\r\n",
            ):
                a = os.path.join(work, "a")
                b = os.path.join(work, "b")
                sh = self.shell("notary_key_to_file", value, a)
                rs = self.probe("notary_key_to_file", value, b)
                self.assertEqual(sh, rs, value)
                with open(a, "rb") as fa, open(b, "rb") as fb:
                    self.assertEqual(fa.read(), fb.read(), value)
        finally:
            shutil.rmtree(work)


if __name__ == "__main__":
    unittest.main(verbosity=2)
