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

"""setup.sh / bootstrap.sh against their Rust ports, side by side.

Every scenario builds the same scratch tree at the same path twice, runs the
script in one and the binary in the other with identical arguments and
environment, and requires identical stdout, stderr and exit code, the same npm
and git calls in the same order (with the `$PWD` each saw), and the same files
left behind -- the stand-in terminal, the login marker, the two-factor
counters, and any leaked clone directory included.

Stderr is compared byte for byte except where the port documents a divergence
(src/lib.rs): Python's traceback frames (its final `Error:` line is still
compared), and bash's `script: line N:` prefix on its own diagnostics.
"""

import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.getcwd()


def _abs(var):
    return os.path.join(HERE, os.environ[var])


SETUP_SH = _abs("NTP_SETUP_SH")
SETUP_RS = _abs("NTP_SETUP_RS")
BOOTSTRAP_SH = _abs("NTP_BOOTSTRAP_SH")
BOOTSTRAP_RS = _abs("NTP_BOOTSTRAP_RS")

STUB_NPM = r"""#!/usr/bin/env bash
printf 'npm|%s|%s\n' "$PWD" "$*" >> "${CALLS:-/dev/null}"
counter() { local f="${CALLS}.$1" n=0; [ -f "$f" ] && n="$(cat "$f")"; echo $((n + 1)) > "$f"; echo "$n"; }
emit_otp() {
  echo "npm error code EOTP" >&2
  echo "npm error Open this URL in your browser to authenticate:" >&2
  echo "npm error   https://www.npmjs.com/auth/cli/STUBID" >&2
}
otp_blocked() {
  [ -n "${STUB_EOTP:-}" ] && return 0
  [ -n "${STUB_OTP_UNTIL:-}" ] || return 1
  [ "$(counter otp)" -lt "$STUB_OTP_UNTIL" ]
}
if [ "$1" = "--version" ]; then echo "${STUB_VERSION:-11.19.0}"; exit 0; fi
if [ "$1" = "trust" ] && [ "$2" = "github" ] && [ "${3:-}" = "--help" ]; then
  echo "npm trust github <pkg> --repo <r> --file <f> [--yes]"
  [ -z "${STUB_NO_ALLOW_PUBLISH:-}" ] && echo "  --allow-publish"
  exit "${STUB_HELP_RC:-0}"
fi
case "$1" in
  whoami)
    if [ -n "${STUB_LOGGED_IN:-}" ] || { [ -n "${STUB_LOGIN_MARKER:-}" ] && [ -f "$STUB_LOGIN_MARKER" ]; }; then
      echo "${STUB_WHO:-ipv1337}"; exit 0
    fi
    echo "npm error code ENEEDAUTH" >&2; exit 1 ;;
  login)
    [ -n "${STUB_LOGIN_USELESS:-}" ] && exit 0
    [ -n "${STUB_LOGIN_FAILS:-}" ] && { echo "npm error login failed" >&2; exit 1; }
    [ -n "${STUB_LOGIN_MARKER:-}" ] && : > "$STUB_LOGIN_MARKER"
    echo "Logged in on https://registry.npmjs.org/."; exit 0 ;;
  view)
    if [ -n "${STUB_REGISTRY_ONLY:-}" ]; then
      for n in ${STUB_ON_REGISTRY:-}; do [ "$n" = "$2" ] && { echo 1.0.0; exit 0; }; done
      echo "npm error code E404" >&2; exit 1
    fi
    for n in ${STUB_UNPUBLISHED:-}; do [ "$n" = "$2" ] && { echo "npm error code E404" >&2; exit 1; }; done
    echo "1.0.0"; exit 0 ;;
  install) [ -n "${STUB_INSTALL_FAILS:-}" ] && { echo "npm error install broke" >&2; exit 1; }
    echo "added 3 packages"; exit 0 ;;
  run) [ -n "${STUB_BUILD_FAILS:-}" ] && { echo "npm error build broke" >&2; exit 3; }
    echo "> tsc -b"; exit 0 ;;
  publish)
    if [ -n "${STUB_PUBLISH_FAILS:-}" ]; then
      echo "npm notice packing" ; echo "npm error code E403" >&2; echo "npm error forbidden" >&2; exit 1
    fi
    if [ -n "${STUB_PUBLISH_EOTP:-}" ] || [ -n "${STUB_PUBLISH_EOTP_UNTIL:-}" ]; then
      n="$(counter potp)"
      if [ -n "${STUB_PUBLISH_EOTP:-}" ] || [ "$n" -lt "$STUB_PUBLISH_EOTP_UNTIL" ]; then emit_otp; exit 1; fi
    fi
    echo "npm notice Publishing to https://registry.npmjs.org/" >&2
    echo "+ $(basename "$PWD")@0.4.0"
    printf '\n\n'
    exit 0 ;;
esac
if [ "$1" = "trust" ] && [ "$2" = "list" ]; then
  for n in ${STUB_UNPUBLISHED:-}; do [ "$n" = "$3" ] && { echo "npm error code E404" >&2; exit 1; }; done
  if otp_blocked; then emit_otp; exit 1; fi
  for n in ${STUB_ALREADY:-}; do [ "$n" = "$3" ] && { printf '%b\n' "${STUB_LIST_LINE:-release.yml}"; exit "${STUB_LIST_RC:-0}"; }; done
  exit 0
fi
if [ "$1" = "access" ] && [ "$2" = "set" ]; then
  if otp_blocked; then emit_otp; exit 1; fi
  if [ -n "${STUB_ACCESS_FAILS:-}" ]; then echo "npm error code E403" >&2; echo "npm error nope" >&2; exit 1; fi
  echo "TRUST_OK_VISIBLE"; exit 0
fi
if [ "$1" = "trust" ] && [ "$2" = "github" ]; then
  if otp_blocked; then emit_otp; exit 1; fi
  if [ -n "${STUB_GH_DUPLICATE:-}" ]; then echo "npm error Trusted publisher ALREADY Configured" >&2; exit 1; fi
  if [ -n "${STUB_GH_ERROR:-}" ]; then
    echo "npm notice working"; echo "npm error code E500" >&2; echo "NPM ERROR second line" >&2
    echo "npm error third line" >&2; exit 1
  fi
  echo "TRUST_OK_VISIBLE"; exit 0
fi
exit 0
"""

STUB_GIT = r"""#!/usr/bin/env bash
printf 'git|%s|%s\n' "$PWD" "$*" >> "${CALLS:-/dev/null}"
if [ "$1" = "clone" ]; then
  dest="${@: -1}"
  if [ -n "${STUB_CLONE_FAILS:-}" ]; then echo "fatal: repository not found" >&2; exit 128; fi
  cp -R "$STUB_MIRROR_TEMPLATE/." "$dest/"
  exit 0
fi
for g in /usr/bin/git /bin/git /usr/local/bin/git /opt/homebrew/bin/git; do [ -x "$g" ] && exec "$g" "$@"; done
exit 127
"""

FAKE_SETUP = """#!/usr/bin/env bash
echo "SETUP_RAN args=[$*] npm=${NPM:-} pwd=$PWD"
echo "setup stderr" >&2
exit 7
"""


def write(path, data, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data.encode() if isinstance(data, str) else data)
    if mode:
        os.chmod(path, mode)


def pkg(path, body):
    write(
        path, body if isinstance(body, (str, bytes)) else __import__("json").dumps(body)
    )


# --- trees ----------------------------------------------------------------------


def base_tree(w):
    write(f"{w}/bin/npm", STUB_NPM, 0o755)
    write(f"{w}/bin/git", STUB_GIT, 0o755)
    write(f"{w}/bin/fake_setup.sh", FAKE_SETUP, 0o755)
    os.makedirs(f"{w}/tmp")
    os.makedirs(f"{w}/home")
    os.makedirs(f"{w}/repo", exist_ok=True)


def setup_tree(w):
    base_tree(w)
    r = f"{w}/repo"
    pkg(
        f"{r}/pulumi/library/ts/packages/a/package.json",
        {"name": "@v/a", "version": "1.0.0", "private": False},
    )
    pkg(
        f"{r}/mcp-slack/package.json",
        {"name": "@v/mcp", "version": "1.0.0", "private": False},
    )
    pkg(
        f"{r}/vitruvian-sdk/kits/typescript/package.json",
        {"name": "@v/kit", "version": "1.0.0", "private": False},
    )
    pkg(
        f"{r}/pulumi/library/ts/packages/priv/package.json",
        {"name": "@v/priv", "version": "1.0.0", "private": True},
    )


def odd_json_tree(w):
    """Valid JSON with every type Python's print() renders differently."""
    setup_tree(w)
    p = f"{w}/repo/pulumi/library/ts/packages"
    pkg(f"{p}/e1/package.json", '{"name":"@v/e1","private":"false"}')
    pkg(f"{p}/e2/package.json", '{"name":"@v/e2","private":0}')
    pkg(f"{p}/e3/package.json", '{"name":null}')
    pkg(f"{p}/e4/package.json", '{"name":5,"private":null}')
    pkg(f"{p}/e5/package.json", '{"name":"a b"}')
    pkg(f"{p}/e6/package.json", '{"name":"@v/ü-näme"}')
    pkg(
        f"{p}/e7/package.json",
        '{"name":"@v/first","private":true,"name":"@v/dup","private":[]}',
    )
    pkg(f"{p}/e8/package.json", '{"name":1.5e-7}')
    pkg(f"{p}/e9/package.json", '{"name":"x\\ny"}')
    pkg(f"{p}/e10/package.json", '{"name":"@v/t\\tab"}')
    pkg(f"{p}/e11/package.json", '{"name":"@v/trail  "}')
    pkg(f"{p}/e12/package.json", '{"name":["l",1,{"k":true}],"private":{}}')
    pkg(f"{p}/e13/package.json", '{"name":1e20}')
    pkg(f"{p}/e14/package.json", '{"name":"it\'s"}')
    pkg(f"{p}/e15/package.json", '{"name":""}')
    pkg(f"{p}/e16/package.json", '{"name":true}')
    pkg(f"{p}/package.json", {"name": "@v/depth1"})
    pkg(f"{p}/deep/x/package.json", {"name": "@v/depth3"})
    pkg(f"{p}/node_modules/package.json", {"name": "@v/nm1"})
    pkg(f"{p}/node_modules/z/package.json", {"name": "@v/nm2"})
    os.makedirs(f"{p}/isdir/package.json/inner")
    os.symlink("a", f"{p}/lnk")
    for d in ("A", "_", "-", "Z~"):
        pkg(f"{p}/{d}/package.json", {"name": f"@v/sort{d}"})


def bad_json_tree(w):
    setup_tree(w)
    p = f"{w}/repo/pulumi/library/ts/packages"
    pkg(f"{p}/b1/package.json", "{not json")
    pkg(f"{p}/b2/package.json", "[1, 2]")
    pkg(f"{p}/b3/package.json", '"just a string"')
    pkg(f"{p}/b4/package.json", b"\xef\xbb\xbf{}")
    pkg(f"{p}/b5/package.json", "")
    pkg(f"{p}/b6/package.json", "{} {}")


def all_roots_tree(w):
    base_tree(w)
    r = f"{w}/repo"
    for root, name in [
        ("packages/pulumi/library/ts/packages/x", "@v/px"),
        ("apps/mcp/slack", "@v/slack"),
        ("packages/vitruvian-sdk/kits/typescript", "@v/pkit"),
        ("packages/vitruvian-sdk/kits/typescript/sub", "@v/psub"),
    ]:
        pkg(f"{r}/{root}/package.json", {"name": name})


def mirror_pkgs(m, deps="^8.0.0"):
    def mk(d, name, spec, private=False, extra=None):
        body = {
            "name": name,
            "version": "0.4.0",
            "main": "dist/index.js",
            "dependencies": {"@pulumi/gcp": spec},
        }
        if private:
            body["private"] = True
        if extra:
            body.update(extra)
        pkg(f"{m}/ts/packages/{d}/package.json", body)

    mk("new", "@v/new", deps)
    mk("old", "@v/old", "^8.0.0")
    mk("priv", "@v/priv", "^8.0.0", private=True)
    return mk


def bootstrap_tree(w, deps="^8.0.0", repo_setup=True):
    if repo_setup:
        setup_tree(w)
    else:
        base_tree(w)
    mirror_pkgs(f"{w}/mirror", deps)
    mirror_pkgs(f"{w}/template", deps)
    return f"{w}/mirror"


# --- running and comparing ----------------------------------------------------------

TMP_RE = re.compile(rb"tmp\.[A-Za-z0-9]+")


def snapshot(w):
    snap = {}
    for dirpath, dirnames, filenames in os.walk(w):
        if dirpath == w:
            # $HOME: python3 drops its bytecode cache there on macOS.
            dirnames[:] = [d for d in dirnames if d != "home"]
        for n in sorted(dirnames + filenames):
            p = os.path.join(dirpath, n)
            rel = TMP_RE.sub(b"tmp.X", os.path.relpath(p, w).encode())
            st = os.lstat(p)
            if stat.S_ISLNK(st.st_mode):
                snap[rel] = b"-> " + os.readlink(p).encode()
            elif stat.S_ISDIR(st.st_mode):
                snap[rel] = b"<dir>"
            else:
                with open(p, "rb") as f:
                    snap[rel] = TMP_RE.sub(b"tmp.X", f.read())
    return snap


DIAG_RE = re.compile(r"^.*?: line \d+: (.*)$")
TRACEBACK_RE = re.compile(r"Traceback \(most recent call last\):\n(?:[ \t].*\n)*")


def normalize_stderr(sh_err, rs_err, prog, drop_re):
    """Apply the documented stderr divergences, nothing else."""
    sh = TRACEBACK_RE.sub("", sh_err.decode("utf-8", "replace"))
    sh_lines = []
    for line in sh.split("\n"):
        m = DIAG_RE.match(line)
        sh_lines.append("DIAG: " + m.group(1) if m else line)
    rs_lines = []
    for line in rs_err.decode("utf-8", "replace").split("\n"):
        for pre in (prog + ": ",):
            if line.startswith(pre) and ("DIAG: " + line[len(pre) :]) in sh_lines:
                line = "DIAG: " + line[len(pre) :]
        rs_lines.append(line)
    if drop_re:
        sh_lines = [ln for ln in sh_lines if not re.search(drop_re, ln)]
        rs_lines = [ln for ln in rs_lines if not re.search(drop_re, ln)]
    return "\n".join(sh_lines), "\n".join(rs_lines)


class Scenario:
    def __init__(
        self, name, tool, tree, args=(), env=None, cwd="repo", drop=None, stdin=None
    ):
        self.name, self.tool, self.tree, self.args = name, tool, tree, list(args)
        self.env, self.cwd, self.drop, self.stdin = env or {}, cwd, drop, stdin


def run_one(sc, impl, w):
    sc.tree(w)
    env = {
        "PATH": f"{w}/bin:/usr/bin:/bin",
        "HOME": f"{w}/home",
        "TMPDIR": f"{w}/tmp",
        "LC_ALL": "C",
        "CALLS": f"{w}/calls",
        "BUILD_WORKSPACE_DIRECTORY": f"{w}/repo",
        "DELAY_SECONDS": "0",
    }
    for k, v in sc.env.items():
        v = v.replace("@W", w) if isinstance(v, str) else v
        if v is None:
            env.pop(k, None)
        else:
            env[k] = v
    if sc.tool == "setup":
        cmd = ["bash", SETUP_SH] if impl == "sh" else [SETUP_RS]
    else:
        cmd = ["bash", BOOTSTRAP_SH] if impl == "sh" else [BOOTSTRAP_RS]
    if impl == "sh":
        cmd[0] = shutil.which("bash", path=env["PATH"]) or "/bin/bash"
    stdin = subprocess.DEVNULL
    if sc.stdin is not None:
        stdin = subprocess.PIPE
    p = subprocess.run(
        cmd + [a.replace("@W", w) for a in sc.args],
        cwd=os.path.join(w, sc.cwd),
        env=env,
        input=sc.stdin.encode() if sc.stdin is not None else None,
        stdin=None if sc.stdin is not None else stdin,
        capture_output=True,
        timeout=120,
    )
    return p.returncode, p.stdout, p.stderr, snapshot(w)


ALL_ON = {"STUB_LOGGED_IN": "1"}
TTY = {"NPM_TP_TTY_PATH": "@W/faketty"}


def S(name, *a, **k):
    return Scenario(name, "setup", *a, **k)


def B(name, *a, **k):
    return Scenario(name, "bootstrap", *a, **k)


def env(*dicts, **kw):
    out = {}
    for d in dicts:
        out.update(d)
    out.update(kw)
    return out


def list_tree(rows, extra=None):
    def tree(w):
        setup_tree(w)
        pkg(f"{w}/repo/somewhere/new/package.json", {"name": "@v/new"})
        pkg(f"{w}/repo/other place/package.json", {"name": "@v/spaced"})
        if extra:
            extra(w)
        write(f"{w}/list", rows)

    return tree


def npm_dirs_tree(w):
    setup_tree(w)
    for d in ("bad", "good", "dirnpm/npm"):
        os.makedirs(f"{w}/{d}", exist_ok=True)
    shutil.copy(f"{w}/bin/npm", f"{w}/good/npm")
    write(
        f"{w}/bad/npm",
        f'#!/usr/bin/env bash\nexport STUB_NO_ALLOW_PUBLISH=1\nSTUB_VERSION=11.11.0 exec "{w}/bin/npm" "$@"\n',
        0o755,
    )
    write(f"{w}/noexec/npm", "#!/usr/bin/env bash\nexit 0\n", 0o644)
    os.remove(f"{w}/bin/npm")


def symlinked_root_tree(w):
    setup_tree(w)
    os.symlink(f"{w}/repo", f"{w}/link")


def symlinked_search_root(w):
    setup_tree(w)
    shutil.move(f"{w}/repo/mcp-slack", f"{w}/real-slack")
    os.symlink(f"{w}/real-slack", f"{w}/repo/mcp-slack")


def empty_repo(w):
    base_tree(w)


def tty_dir_tree(w):
    setup_tree(w)
    os.makedirs(f"{w}/ttydir")


SETUP_SCENARIOS = [
    # From setup_test.sh, then around each of its edges.
    S("default-sweep", setup_tree, env=ALL_ON),
    S("dry-run", setup_tree, ["--dry-run"], env=ALL_ON),
    S("harden", setup_tree, ["--harden"], env=ALL_ON),
    S("harden-dry-run", setup_tree, ["--harden", "--dry-run"], env=ALL_ON),
    S("harden-fails", setup_tree, ["--harden"], env=env(ALL_ON, STUB_ACCESS_FAILS="1")),
    S(
        "harden-eotp-breaks",
        setup_tree,
        ["--harden"],
        env=env(ALL_ON, TTY, STUB_EOTP="1", OTP_WAIT_SECONDS="0"),
    ),
    S(
        "harden-eotp-clears",
        setup_tree,
        ["--harden"],
        env=env(
            ALL_ON, TTY, STUB_OTP_UNTIL="1", OTP_WAIT_SECONDS="6", OTP_POLL_SECONDS="1"
        ),
    ),
    S(
        "flags-repeated",
        setup_tree,
        ["--dry-run", "--dry-run", "--no-login"],
        env=ALL_ON,
    ),
    S("unknown-flag", setup_tree, ["--dry-run", "--bogus", "--also-bogus"], env=ALL_ON),
    S("unknown-flag-first", setup_tree, ["-h"], env=ALL_ON),
    S("already", setup_tree, env=env(ALL_ON, STUB_ALREADY="@v/a")),
    S(
        "already-list-fails",
        setup_tree,
        env=env(ALL_ON, STUB_ALREADY="@v/a", STUB_LIST_RC="1"),
    ),
    S("duplicate", setup_tree, env=env(ALL_ON, STUB_GH_DUPLICATE="1")),
    S("gh-error-excerpt", setup_tree, env=env(ALL_ON, STUB_GH_ERROR="1")),
    S("unpublished", setup_tree, env=env(ALL_ON, STUB_UNPUBLISHED="@v/a @v/kit")),
    S(
        "unpublished-harden",
        setup_tree,
        ["--harden"],
        env=env(ALL_ON, STUB_UNPUBLISHED="@v/mcp"),
    ),
    # Two-factor: a stand-in terminal, no terminal, a "terminal" that cannot be opened.
    S(
        "eotp-never-tty",
        setup_tree,
        env=env(
            ALL_ON,
            TTY,
            NPM_TP_TTY_OK="1",
            STUB_EOTP="1",
            OTP_WAIT_SECONDS="2",
            OTP_POLL_SECONDS="1",
        ),
    ),
    S(
        "eotp-clears-tty",
        setup_tree,
        env=env(
            ALL_ON, TTY, STUB_OTP_UNTIL="2", OTP_WAIT_SECONDS="20", OTP_POLL_SECONDS="1"
        ),
    ),
    S(
        "eotp-clears-no-tty",
        setup_tree,
        env=env(
            ALL_ON,
            NPM_TP_TTY_PATH="@W/no/such/tty",
            STUB_OTP_UNTIL="2",
            OTP_WAIT_SECONDS="20",
            OTP_POLL_SECONDS="1",
        ),
    ),
    S(
        "eotp-tty-is-dir",
        tty_dir_tree,
        env=env(
            ALL_ON,
            NPM_TP_TTY_PATH="@W/ttydir",
            STUB_OTP_UNTIL="2",
            OTP_WAIT_SECONDS="20",
            OTP_POLL_SECONDS="1",
        ),
    ),
    S(
        "eotp-wait-zero",
        setup_tree,
        env=env(ALL_ON, TTY, STUB_EOTP="1", OTP_WAIT_SECONDS="0"),
    ),
    S(
        "eotp-wait-not-int",
        setup_tree,
        env=env(ALL_ON, TTY, STUB_EOTP="1", OTP_WAIT_SECONDS="soon"),
    ),
    S(
        "eotp-dev-tty",
        setup_tree,
        env=env(ALL_ON, STUB_OTP_UNTIL="1", OTP_WAIT_SECONDS="4", OTP_POLL_SECONDS="1"),
    ),
    # Login.
    S("not-logged-in-no-tty", setup_tree),
    S("no-login", setup_tree, ["--no-login"], env={"NPM_TP_TTY_OK": "1"}),
    S(
        "login-flow",
        setup_tree,
        env={"NPM_TP_TTY_OK": "1", "STUB_LOGIN_MARKER": "@W/loggedin"},
    ),
    S(
        "login-useless",
        setup_tree,
        env={"NPM_TP_TTY_OK": "1", "STUB_LOGIN_USELESS": "1"},
    ),
    S("login-fails", setup_tree, env={"NPM_TP_TTY_OK": "1", "STUB_LOGIN_FAILS": "1"}),
    # Choosing an npm.
    S(
        "npm-bad-then-good",
        npm_dirs_tree,
        ["--dry-run"],
        env=env(ALL_ON, PATH="@W/bad:@W/good:/usr/bin:/bin"),
    ),
    S("npm-only-bad", npm_dirs_tree, env=env(ALL_ON, PATH="@W/bad:/usr/bin:/bin")),
    S(
        "npm-explicit-bad",
        npm_dirs_tree,
        env=env(ALL_ON, PATH="@W/good:/usr/bin:/bin", NPM="@W/bad/npm"),
    ),
    S(
        "npm-explicit-good",
        npm_dirs_tree,
        ["--dry-run"],
        env=env(ALL_ON, PATH="@W/bad:/usr/bin:/bin", NPM="@W/good/npm"),
    ),
    S(
        "npm-explicit-flag",
        npm_dirs_tree,
        env=env(ALL_ON, PATH="@W/bad:@W/good:/usr/bin:/bin", NPM_EXPLICIT="1"),
    ),
    S(
        "npm-explicit-name",
        npm_dirs_tree,
        ["--dry-run"],
        env=env(ALL_ON, PATH="@W/bad:@W/good:/usr/bin:/bin", NPM="npm"),
    ),
    S("npm-missing", npm_dirs_tree, env=env(ALL_ON, PATH="@W/nowhere:/usr/bin:/bin")),
    S("npm-missing-explicit", npm_dirs_tree, env=env(ALL_ON, NPM="@W/nope/npm")),
    S(
        "npm-skips-dir-and-noexec",
        npm_dirs_tree,
        ["--dry-run"],
        env=env(
            ALL_ON, PATH="@W/dirnpm:@W/noexec:@W/bad/:@W/good:@W/good:/usr/bin:/bin"
        ),
    ),
    S("npm-help-exits-nonzero", setup_tree, env=env(ALL_ON, STUB_HELP_RC="1")),
    # Discovery.
    S("odd-json", odd_json_tree, env=ALL_ON),
    S("odd-json-dry", odd_json_tree, ["--dry-run"], env=ALL_ON),
    S(
        "bad-json",
        bad_json_tree,
        ["--dry-run"],
        env=ALL_ON,
        drop=r"JSONDecodeError|UnicodeDecodeError",
    ),
    S("all-roots", all_roots_tree, env=ALL_ON),
    S("no-manifests", empty_repo, env=ALL_ON),
    S("symlinked-search-root", symlinked_search_root, ["--dry-run"], env=ALL_ON),
    S(
        "workspace-from-pwd",
        setup_tree,
        ["--dry-run"],
        env=env(ALL_ON, BUILD_WORKSPACE_DIRECTORY=None),
    ),
    S(
        "workspace-logical-pwd",
        symlinked_root_tree,
        env=env(ALL_ON, BUILD_WORKSPACE_DIRECTORY="@W/bin/..//./link/"),
    ),
    S(
        "workspace-dotdot-through-missing",
        symlinked_root_tree,
        env=env(ALL_ON, BUILD_WORKSPACE_DIRECTORY="@W/link/./bin/../"),
    ),
    S(
        "workspace-missing",
        setup_tree,
        env=env(ALL_ON, BUILD_WORKSPACE_DIRECTORY="@W/nope"),
    ),
    # The caller's list.
    S(
        "list-valid",
        list_tree("somewhere/new/package.json\tExample/new-mirror\tpublish.yml\n"),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-harden",
        list_tree(
            "somewhere/new/package.json\tExample/new-mirror\tpublish.yml\nmcp-slack/package.json\tx/y\tz.yml\n"
        ),
        ["--harden"],
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-missing-file",
        list_tree("somewhere/gone/package.json\tExample/new-mirror\tpublish.yml\n"),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-short-row",
        list_tree("somewhere/new/package.json\tExample/new-mirror\n"),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-extra-field",
        list_tree("somewhere/new/package.json\tExample/new-mirror\tp.yml\textra\n"),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-double-tab",
        list_tree("somewhere/new/package.json\t\tExample/new-mirror\tpublish.yml\n"),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-leading-tab",
        list_tree("\tsomewhere/new/package.json\tExample/new-mirror\tpublish.yml\n"),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-trailing-tab-blank-lines",
        list_tree("\n\t\t\nsomewhere/new/package.json\tE/m\tpublish.yml\t\n\n"),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-unterminated-only",
        list_tree("somewhere/new/package.json\tE/m\tpublish.yml"),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-unterminated-last",
        list_tree(
            "mcp-slack/package.json\tE/m\tp.yml\nsomewhere/new/package.json\tE/m\tpublish.yml"
        ),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-crlf-and-spaces",
        list_tree("other place/package.json\tE/space repo\tpublish.yml\r\n"),
        env=env(
            ALL_ON,
            NPM_TP_PACKAGES="@W/list",
            STUB_ALREADY="@v/spaced",
            STUB_LIST_LINE="publish.yml\\r",
        ),
    ),
    S(
        "list-duplicate-rows",
        list_tree(
            "mcp-slack/package.json\tA/one\tone.yml\nmcp-slack/package.json\tB/two\ttwo.yml\n"
        ),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    S(
        "list-unreadable",
        setup_tree,
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/no-such-list"),
    ),
    S("list-blank-only", list_tree("\n\n"), env=env(ALL_ON, NPM_TP_PACKAGES="@W/list")),
    S(
        "list-escapes-for-awk",
        list_tree("other place/package.json\tE/m\tpublish.yml\n"),
        env=env(ALL_ON, NPM_TP_PACKAGES="@W/list"),
    ),
    # `grep -q "$workflow"` is a regular expression.
    S(
        "wf-dot",
        setup_tree,
        env=env(ALL_ON, STUB_ALREADY="@v/a", WORKFLOW_FILE="rel.ase.yml"),
    ),
    S(
        "wf-escaped-dot",
        setup_tree,
        env=env(
            ALL_ON,
            STUB_ALREADY="@v/a",
            STUB_LIST_LINE="releaseXyml",
            WORKFLOW_FILE="release\\.yml",
        ),
    ),
    S(
        "wf-anchors",
        setup_tree,
        env=env(
            ALL_ON,
            STUB_ALREADY="@v/a @v/mcp",
            STUB_LIST_LINE="  release.yml",
            WORKFLOW_FILE="^release.yml$",
        ),
    ),
    S(
        "wf-end-anchor",
        setup_tree,
        env=env(
            ALL_ON,
            STUB_ALREADY="@v/a",
            STUB_LIST_LINE="x\\nyy release.yml",
            WORKFLOW_FILE="yml$",
        ),
    ),
    S(
        "wf-star",
        setup_tree,
        env=env(
            ALL_ON,
            STUB_ALREADY="@v/a",
            STUB_LIST_LINE="rlease.yml",
            WORKFLOW_FILE="re*lease",
        ),
    ),
    S(
        "wf-bracket",
        setup_tree,
        env=env(ALL_ON, STUB_ALREADY="@v/a", WORKFLOW_FILE="[r]elease.yml"),
    ),
    S(
        "wf-leading-dash",
        setup_tree,
        env=env(ALL_ON, STUB_ALREADY="@v/a", WORKFLOW_FILE="-v"),
    ),
    S(
        "wf-group",
        setup_tree,
        env=env(ALL_ON, STUB_ALREADY="@v/a", WORKFLOW_FILE="\\(rel\\)ease"),
    ),
    # Pacing.
    S("delay-invalid", setup_tree, env=env(ALL_ON, DELAY_SECONDS="abc")),
    S("delay-fraction", setup_tree, env=env(ALL_ON, DELAY_SECONDS="0.01")),
]

BOOT_ENV = {
    "MIRROR_DIR": "@W/mirror",
    "SETUP_SH": "@W/bin/fake_setup.sh",
    "NPM_TP_TTY_OK": "1",
    "STUB_REGISTRY_ONLY": "1",
}
REPO_PKGS = "@v/old @v/a @v/mcp @v/kit"
BL = env(BOOT_ENV, STUB_LOGGED_IN="1", STUB_ON_REGISTRY="@v/old")


def proto_tree(spec):
    return lambda w: bootstrap_tree(w, spec)


def many_bad_deps(w):
    bootstrap_tree(w)
    pkg(
        f"{w}/mirror/ts/packages/new/package.json",
        '{"name":"@v/new","optionalDependencies":{"o":"link:../o"},'
        '"dependencies":{"z":"workspace:*","a":"^1","c":"catalog:","n":1,"f":"file:x:y","w":"workspace:"},'
        '"peerDependencies":{"p":"catalog:peer"}}',
    )
    pkg(
        f"{w}/mirror/ts/packages/zz/package.json",
        '{"name":"@v/zz","dependencies":{"q\\nr":"catalog:"}}',
    )


def deps_wrong_type(w):
    bootstrap_tree(w)
    pkg(
        f"{w}/mirror/ts/packages/new/package.json",
        '{"name":"@v/new","dependencies":["@pulumi/gcp"]}',
    )


def deps_falsy(w):
    bootstrap_tree(w)
    pkg(
        f"{w}/mirror/ts/packages/new/package.json",
        '{"name":"@v/new","dependencies":0,"peerDependencies":"","optionalDependencies":null}',
    )


def no_ts_packages(w):
    setup_tree(w)
    os.makedirs(f"{w}/mirror/ts")


def depth1_and_odd(w):
    bootstrap_tree(w)
    pkg(f"{w}/mirror/ts/packages/package.json", {"name": "@v/root"})
    pkg(f"{w}/mirror/ts/packages/odd/package.json", '{"name":null}')
    pkg(f"{w}/mirror/ts/packages/bad/package.json", "{nope")


def spaced_mirror(w):
    setup_tree(w)
    mirror_pkgs(f"{w}/mir ror")


def clone_tree(w):
    bootstrap_tree(w)
    shutil.rmtree(f"{w}/mirror")


BOOTSTRAP_SCENARIOS = [
    B(f"guard-{p.split(':')[0]}", proto_tree(p), env=BL)
    for p in ("catalog:", "workspace:^1.0.0", "file:../x", "link:../x")
] + [
    B("guard-many", many_bad_deps, env=BL),
    B("deps-wrong-type", deps_wrong_type, env=BL),
    B("deps-falsy", deps_falsy, env=BL),
    B("happy-handoff-setup-sh", bootstrap_tree, env=BL),
    B("nothing-to-do", bootstrap_tree, env=env(BL, STUB_ON_REGISTRY="@v/new @v/old")),
    B("dry-run", bootstrap_tree, ["--dry-run"], env=BL),
    B("help", bootstrap_tree, ["--help"], env=BL),
    B("help-short-after-flag", bootstrap_tree, ["--dry-run", "-h", "--bogus"], env=BL),
    B("unknown-before-help", bootstrap_tree, ["--bogus", "--help"], env=BL),
    B("build-fails", bootstrap_tree, env=env(BL, STUB_BUILD_FAILS="1")),
    B("install-fails", bootstrap_tree, env=env(BL, STUB_INSTALL_FAILS="1")),
    B("publish-fails", bootstrap_tree, env=env(BL, STUB_PUBLISH_FAILS="1")),
    B(
        "publish-eotp-clears",
        bootstrap_tree,
        env=env(
            BL, OTP_WAIT_SECONDS="20", OTP_POLL_SECONDS="1", STUB_PUBLISH_EOTP_UNTIL="2"
        ),
    ),
    B(
        "publish-eotp-never",
        bootstrap_tree,
        env=env(BL, OTP_WAIT_SECONDS="2", OTP_POLL_SECONDS="1", STUB_PUBLISH_EOTP="1"),
    ),
    B(
        "publish-eotp-wait-zero",
        bootstrap_tree,
        env=env(BL, OTP_WAIT_SECONDS="0", STUB_PUBLISH_EOTP="1"),
    ),
    B(
        "no-login",
        bootstrap_tree,
        ["--no-login"],
        env=env(BOOT_ENV, STUB_ON_REGISTRY="@v/old"),
    ),
    B(
        "not-logged-in-no-tty",
        bootstrap_tree,
        env=env(BOOT_ENV, NPM_TP_TTY_OK=None, STUB_ON_REGISTRY="@v/old"),
    ),
    B(
        "login-flow",
        bootstrap_tree,
        env=env(BOOT_ENV, STUB_ON_REGISTRY="@v/old", STUB_LOGIN_MARKER="@W/loggedin"),
    ),
    B(
        "login-fails",
        bootstrap_tree,
        env=env(BOOT_ENV, STUB_ON_REGISTRY="@v/old", STUB_LOGIN_FAILS="1"),
    ),
    B(
        "login-useless",
        bootstrap_tree,
        env=env(BOOT_ENV, STUB_ON_REGISTRY="@v/old", STUB_LOGIN_USELESS="1"),
    ),
    B("no-ts-packages", no_ts_packages, env=BL),
    B(
        "depth1-and-odd-manifests",
        depth1_and_odd,
        ["--dry-run"],
        env=BL,
        drop=r"JSONDecodeError|UnicodeDecodeError",
    ),
    B(
        "spaced-mirror-splits",
        spaced_mirror,
        env=env(BL, MIRROR_DIR="@W/mir ror"),
        drop=None,
    ),
    B("relative-mirror", bootstrap_tree, env=env(BL, MIRROR_DIR="../bin/../mirror")),
    B(
        "clone",
        clone_tree,
        env=env(
            BL,
            MIRROR_DIR=None,
            STUB_MIRROR_TEMPLATE="@W/template",
            MIRROR_REPO="Example/lib",
        ),
    ),
    B(
        "clone-fails-leaks-dir",
        clone_tree,
        env=env(BL, MIRROR_DIR=None, STUB_CLONE_FAILS="1"),
    ),
    B(
        "clone-dry-run-cleans-up",
        clone_tree,
        ["--dry-run"],
        env=env(BL, MIRROR_DIR=None, STUB_MIRROR_TEMPLATE="@W/template"),
    ),
    # The hand-off with no SETUP_SH: the script runs the setup.sh beside it,
    # the port its own setup. Same result required, end to end.
    B(
        "handoff-real-setup",
        bootstrap_tree,
        env=env(BL, SETUP_SH=None, STUB_ON_REGISTRY=REPO_PKGS),
    ),
    B(
        "handoff-setup-sh-missing",
        bootstrap_tree,
        env=env(
            BL,
            SETUP_SH="@W/no/setup.sh",
            STUB_ON_REGISTRY=REPO_PKGS,
            STUB_ALREADY="@v/a",
        ),
    ),
    B(
        "handoff-real-setup-fails",
        bootstrap_tree,
        env=env(BL, SETUP_SH=None, STUB_ON_REGISTRY=REPO_PKGS, STUB_GH_ERROR="1"),
    ),
    B("handoff-real-setup-unpublished", bootstrap_tree, env=env(BL, SETUP_SH=None)),
]


class Parity(unittest.TestCase):
    maxDiff = None

    def check(self, sc):
        root = tempfile.mkdtemp(prefix="ntp-parity-")
        w = os.path.join(root, "w")
        try:
            results = {}
            for impl in ("sh", "rs"):
                os.makedirs(w)
                results[impl] = run_one(sc, impl, w)
                shutil.rmtree(w)
        finally:
            shutil.rmtree(root, ignore_errors=True)
        (src, so, se, sf), (rrc, ro, re_, rf) = results["sh"], results["rs"]
        ctx = f"[{sc.tool}:{sc.name}]"
        self.assertEqual(
            ro.decode("utf-8", "replace"),
            so.decode("utf-8", "replace"),
            f"{ctx} stdout",
        )
        prog = (
            "npm-trusted-publisher"
            if sc.tool == "setup"
            else "npm-trusted-publisher-bootstrap"
        )
        a, b = normalize_stderr(se, re_, prog, sc.drop)
        if sc.tool == "bootstrap" and "handoff-real" in sc.name:
            # The hand-off runs setup, whose diagnostics carry its own prefix.
            a, b = normalize_stderr(
                a.encode(), b.encode(), "npm-trusted-publisher", sc.drop
            )
        self.assertEqual(b, a, f"{ctx} stderr")
        self.assertEqual(
            rrc, src, f"{ctx} exit code\nstdout:\n{so.decode()}\nstderr:\n{se.decode()}"
        )
        self.assertEqual(sorted(rf), sorted(sf), f"{ctx} file set")
        for k in sf:
            self.assertEqual(rf[k], sf[k], f"{ctx} file {k!r}")
        return src, so

    def test_setup(self):
        for sc in SETUP_SCENARIOS:
            with self.subTest(sc.name):
                self.check(sc)

    def test_bootstrap(self):
        for sc in BOOTSTRAP_SCENARIOS:
            with self.subTest(sc.name):
                self.check(sc)

    def test_scenarios_reach_their_branches(self):
        """A parity test over scenarios that all fail the same early way
        proves nothing: pin that the key ones get where they are meant to."""
        want = {
            "default-sweep": (0, "3 configured, 0 already set, 0 failed"),
            "eotp-clears-tty": (0, "3 configured"),
            "eotp-never-tty": (1, "0 configured"),
            "harden": (0, "3 set to mfa=publish"),
            "list-valid": (0, "1 configured"),
            "list-double-tab": (1, "1 failed"),
            "wf-dot": (0, "1 already set"),
            "wf-bracket": (0, "1 already set"),
            "odd-json": (0, "configured"),
            "npm-bad-then-good": (0, "lacks --allow-publish"),
            "login-flow": (0, "starting `npm login`"),
            "workspace-logical-pwd": (0, "3 configured"),
        }
        by_name = {s.name: s for s in SETUP_SCENARIOS}
        for name, (rc, text) in want.items():
            with self.subTest(name):
                got_rc, out = self.check(by_name[name])
                self.assertEqual(got_rc, rc)
                self.assertIn(text, out.decode())
        bwant = {
            "happy-handoff-setup-sh": (7, "SETUP_RAN"),
            "handoff-real-setup": (0, "3 configured, 0 already set, 0 failed"),
            "clone": (7, "1 published, 0 failed"),
            "publish-eotp-clears": (7, "1 published, 0 failed"),
            "guard-catalog": (2, "@pulumi/gcp -> catalog: (dependencies)"),
            "help": (0, "# Usage:"),
        }
        by_name = {s.name: s for s in BOOTSTRAP_SCENARIOS}
        for name, (rc, text) in bwant.items():
            with self.subTest(name):
                got_rc, out = self.check(by_name[name])
                self.assertEqual(got_rc, rc)
                self.assertIn(text, out.decode())


if __name__ == "__main__":
    unittest.main(verbosity=2)
