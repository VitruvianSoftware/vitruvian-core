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
"""github-app-key, the Rust port, against set-key.sh: same exit code,
stdout, stderr, the same calls to a fake `gh` (argv, and the key it was
handed on stdin), the same manifest form, and the same files left behind,
on every case below. The App JWT carries the time, so the fake decodes it
and logs its header, its claims with the times taken out, its lifetime and
whether its RS256 signature verifies against the key's public half.

    bazel test //tools/github-app-key:github_app_key_rs_parity_test
"""

import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, path_without, write, write_exec  # noqa: E402

GH = r"""#!/usr/bin/env bash
line="$*"
jwt=""
for a in "$@"; do case "$a" in "Authorization: Bearer "*) jwt="${a#Authorization: Bearer }" ;; esac; done
if [ -n "$jwt" ]; then
  dec() { local x; x="$(printf '%s' "$1" | tr '_-' '/+')"; while [ $(( ${#x} % 4 )) -ne 0 ]; do x="$x="; done; printf '%s' "$x" | openssl base64 -d -A; }
  h="${jwt%%.*}"; r="${jwt#*.}"; p="${r%%.*}"; s="${r#*.}"
  hdr="$(dec "$h")"; pl="$(dec "$p")"
  iat="$(printf '%s' "$pl" | sed -n 's/.*"iat":\([0-9]*\).*/\1/p')"
  exp="$(printf '%s' "$pl" | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')"
  claims="$(printf '%s' "$pl" | sed 's/"iat":[0-9]*/"iat":T/; s/"exp":[0-9]*/"exp":T/')"
  t="$(mktemp -d "$LOGDIR/jwt.XXXXXX")"
  dec "$s" >"$t/sig"; printf '%s' "$h.$p" >"$t/signed"
  if openssl dgst -sha256 -verify "$PUBKEY" -signature "$t/sig" "$t/signed" >/dev/null 2>&1; then v=ok; else v=BAD; fi
  rm -rf "$t"
  line="${line/"$jwt"/<JWT $hdr $claims life=$((exp - iat)) sig=$v>}"
fi
case "$line" in
  "auth status"*) [ "${FAKE_AUTH_FAIL:-0}" = 1 ] && exit 1; echo "Logged in" ; printf '%s\n' "$line" >>"$LOGDIR/gh.log"; exit 0 ;;
esac
printf '%s\n' "$line" >>"$LOGDIR/gh.log"
case "$line" in
  *"secret set"*)
    n=$(( $(ls "$LOGDIR"/stdin.* 2>/dev/null | wc -l) + 1 ))
    cat >"$LOGDIR/stdin.$n"
    [ "${FAKE_SECRET_FAIL:-0}" = 1 ] && { echo "HTTP 403" >&2; exit 4; }
    echo "set" ;;
  *"--method POST /app-manifests/"*"/conversions"*)
    [ "${FAKE_CONVERT_FAIL:-0}" = 1 ] && { echo "HTTP 404" >&2; exit 1; }
    [ -n "${FAKE_CONVERT_RAW:-}" ] && { echo "$FAKE_CONVERT_RAW"; exit 0; }
    echo "${FAKE_SLUG} ${FAKE_NEW_CLIENT:-Iv23liNEWCLIENTID00} $(openssl base64 -A <"$KEYFILE")" ;;
  *"<JWT"*"/app --jq .slug"*)
    [ "${FAKE_REJECT:-0}" = 1 ] && { echo "HTTP 401" >&2; exit 1; }
    echo "${FAKE_SLUG}" ;;
  *"<JWT"*"/app --jq .id"*)
    [ "${FAKE_ID_FAIL:-0}" = 1 ] && { echo "HTTP 500" >&2; exit 3; }
    echo "${FAKE_APP_ID}" ;;
  *"<JWT"*"/installation"*) [ "${FAKE_INSTALLED:-1}" = 1 ] || { echo "HTTP 404" >&2; exit 1; }; echo 42 ;;
  *"rulesets --jq"*) [ "${FAKE_RULESETS_FAIL:-0}" = 1 ] && { echo "HTTP 502" >&2; exit 1; }; printf '%s\n' ${FAKE_RULESETS-17645603} ;;
  *"rulesets/"*" --jq"*) [ "${FAKE_BYPASS_FAIL:-0}" = 1 ] && { echo "HTTP 500" >&2; exit 6; }; printf '%s\n' ${FAKE_BYPASS:-} ;;
  *) echo "fake gh: unexpected: $line" >&2; exit 99 ;;
esac
"""

OPEN = r"""#!/usr/bin/env bash
printf 'open %s\n' "$*" >>"$LOGDIR/gh.log"
cp "$1" "$LOGDIR/form.html"
[ "${FAKE_OPEN_FAIL:-0}" = 1 ] && exit 7
exit 0
"""

KEY = ""
PUB = ""
OTHER = ""


def setup_factory(dl=None, pem=None, gh=True, extra=None):
    """dl: {name: (key|'other'|'junk', mtime)}; pem: name of a --pem copy under {root}/k/."""

    def setup(root):
        os.makedirs(root + "/log")
        os.makedirs(root + "/dl")
        if gh:
            write_exec(root + "/bin/gh", GH)
        write_exec(root + "/bin/open", OPEN)
        shutil.copy(KEY, root + "/key.pem")
        shutil.copy(PUB, root + "/pub.pem")
        for name, (which, mtime) in (dl or {}).items():
            src = {"key": KEY, "other": OTHER}.get(which)
            p = root + "/dl/" + name
            if src:
                shutil.copy(src, p)
            else:
                write(p, "not a key\n")
            os.utime(p, (mtime, mtime))
        if pem:
            os.makedirs(root + "/k")
            shutil.copy(KEY, root + "/k/" + pem)
        if extra:
            extra(root)

    return setup


RENOVATE = {
    "FAKE_SLUG": "vitruvian-renovate",
    "FAKE_APP_ID": "5112449",
    "FAKE_BYPASS": "3863936",
}
COPYBARA = {
    "FAKE_SLUG": "vitruvian-copybara-sync",
    "FAKE_APP_ID": "3863936",
}


def case(name, args, env=None, setup=None, **kw):
    e = {
        "LOGDIR": "{root}/log",
        "KEYFILE": "{root}/key.pem",
        "PUBKEY": "{root}/pub.pem",
        "GITHUB_APP_KEY_DOWNLOADS": "{root}/dl",
    }
    e.update(env or {})
    return Case(name=name, args=args, env=e, setup=setup or setup_factory(), **kw)


def cases():
    P = "{root}/k/renovate.pem"
    pem = setup_factory(pem="renovate.pem")
    yield case("--list", ["--list"])
    yield case("--list after an app", ["renovate", "--list"])
    yield case("--help", ["--help"])
    yield case("-h", ["-h"])
    yield case("no arguments", [])
    yield case("unknown flag", ["--nope"])
    yield case("unknown flag before --list", ["-x", "--list"])
    yield case("--pem without a value", ["renovate", "--pem"])
    yield case("unknown app", ["no-such-app", "--yes"])
    yield case("--create with --pem", ["renovate", "--create", "--pem", P], setup=pem)
    yield case(
        "renovate: stores and deletes (--yes)",
        ["renovate", "--pem", P, "--yes"],
        env=RENOVATE,
        setup=pem,
    )
    yield case(
        "renovate: no tty keeps the .pem",
        ["renovate", "--pem", P],
        env=RENOVATE,
        setup=pem,
    )
    yield case(
        "renovate: another repo",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, GITHUB_APP_KEY_REPO="Org/repo"),
        setup=pem,
    )
    yield case(
        "last app named wins",
        ["copybara-sync", "renovate", "--pem", P, "--yes"],
        env=RENOVATE,
        setup=pem,
    )
    yield case(
        "finds the newest download",
        ["renovate", "--yes"],
        env=RENOVATE,
        setup=setup_factory(
            dl={
                "vitruvian-renovate.2026-01-01.private-key.pem": ("junk", 1_000_000),
                "vitruvian-renovate.2026-09-28.private-key.pem": ("key", 2_000_000),
                "vitruvian-copybara-sync.2026-09-29.private-key.pem": (
                    "junk",
                    3_000_000,
                ),
                "other.pem": ("junk", 4_000_000),
            }
        ),
    )
    yield case(
        "equal mtimes: first by name",
        ["renovate"],
        env=RENOVATE,
        setup=setup_factory(
            dl={
                "vitruvian-renovate.b.private-key.pem": ("junk", 2_000_000),
                "vitruvian-renovate.a.private-key.pem": ("key", 2_000_000),
            }
        ),
    )
    yield case("no download found", ["renovate", "--yes"], env=RENOVATE)
    yield case(
        "default downloads dir",
        ["renovate", "--yes"],
        env=dict(RENOVATE, GITHUB_APP_KEY_DOWNLOADS=None),
    )
    yield case(
        "--pem is not a file", ["renovate", "--pem", "{root}/dl", "--yes"], env=RENOVATE
    )
    yield case(
        "--pem missing", ["renovate", "--pem", "{root}/nope.pem", "--yes"], env=RENOVATE
    )
    yield case(
        "not a private key",
        ["renovate", "--pem", "{root}/bad.pem", "--yes"],
        env=RENOVATE,
        setup=setup_factory(extra=lambda r: write(r + "/bad.pem", "not a key\n")),
    )
    yield case(
        "a different key: signature does not verify",
        ["renovate", "--pem", "{root}/other.pem", "--yes"],
        env=RENOVATE,
        setup=setup_factory(extra=lambda r: shutil.copy(OTHER, r + "/other.pem")),
    )
    yield case(
        "key for a different App",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_SLUG="vitruvian-copybara-sync"),
        setup=pem,
    )
    yield case(
        "key GitHub rejects",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_REJECT="1"),
        setup=pem,
    )
    yield case(
        "App id lookup fails",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_ID_FAIL="1"),
        setup=pem,
    )
    yield case(
        "App not installed",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_INSTALLED="0"),
        setup=pem,
    )
    yield case(
        "on a bypass list",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_BYPASS="3863936 5112449"),
        setup=pem,
    )
    yield case(
        "bypass on the second ruleset",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_RULESETS="1 2", FAKE_BYPASS="5112449"),
        setup=pem,
    )
    yield case(
        "no rulesets",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_RULESETS=""),
        setup=pem,
    )
    yield case(
        "rulesets list fails",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_RULESETS_FAIL="1"),
        setup=pem,
    )
    yield case(
        "ruleset read fails",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_BYPASS_FAIL="1"),
        setup=pem,
    )
    yield case(
        "App id prefix is not a match",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_BYPASS="51124490 511244"),
        setup=pem,
    )
    yield case(
        "empty App id, empty bypass list",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_APP_ID="", FAKE_BYPASS=""),
        setup=pem,
    )
    yield case(
        "secret set fails",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_SECRET_FAIL="1"),
        setup=pem,
    )
    yield case(
        "copybara-sync: both stores, bypass allowed",
        ["copybara-sync", "--pem", "{root}/k/c.pem", "--yes"],
        env=COPYBARA,
        setup=setup_factory(pem="c.pem"),
    )
    yield case(
        "gh not signed in",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, FAKE_AUTH_FAIL="1"),
        setup=pem,
    )
    yield case(
        "gh missing",
        ["renovate", "--pem", P, "--yes"],
        env=dict(RENOVATE, PATH="{root}/bin:" + path_without("gh")),
        setup=setup_factory(pem="renovate.pem", gh=False),
    )
    create_env = dict(RENOVATE, TMPDIR="{root}/tmp")
    yield case(
        "--create: full flow",
        ["renovate", "--create"],
        env=create_env,
        stdin=b"the-code\n\n",
    )
    yield case(
        "--create: code with blanks",
        ["renovate", "--create", "--yes"],
        env=create_env,
        stdin=b"  the-code  \n\n",
    )
    yield case(
        "--create: no browser",
        ["renovate", "--create"],
        env=dict(create_env, GITHUB_APP_KEY_NO_BROWSER="1"),
        stdin=b"c\n\n",
    )
    yield case(
        "--create: opener fails",
        ["renovate", "--create"],
        env=dict(create_env, FAKE_OPEN_FAIL="1"),
        stdin=b"c\n\n",
    )
    yield case(
        "--create: no code", ["renovate", "--create"], env=create_env, stdin=b"\n"
    )
    yield case(
        "--create: no stdin", ["renovate", "--create"], env=create_env, stdin=b""
    )
    yield case(
        "--create: code rejected",
        ["renovate", "--create"],
        env=dict(create_env, FAKE_CONVERT_FAIL="1"),
        stdin=b"c\n\n",
    )
    yield case(
        "--create: renamed App",
        ["renovate", "--create"],
        env=dict(create_env, FAKE_SLUG="someone-elses-app"),
        stdin=b"c\n\n",
    )
    yield case(
        "--create: same client ID",
        ["renovate", "--create"],
        env=dict(create_env, FAKE_NEW_CLIENT="Iv23liR87u9iun3Br4GZ"),
        stdin=b"c\n",
    )
    yield case(
        "--create: copybara-sync",
        ["copybara-sync", "--create"],
        env=dict(COPYBARA, TMPDIR="{root}/tmp"),
        stdin=b"c\n\n",
    )
    yield case(
        "--create: bad key data",
        ["renovate", "--create"],
        env=dict(
            create_env, FAKE_CONVERT_RAW="vitruvian-renovate Iv23liX bm90IGEga2V5Cg=="
        ),
        stdin=b"c\n\n",
    )
    yield case(
        "--create: TMPDIR default",
        ["renovate", "--create"],
        env=dict(RENOVATE, TMPDIR=None, FAKE_CONVERT_FAIL="1"),
        stdin=b"c\n",
    )


def keypair(d, name):
    k = os.path.join(d, name + ".pem")
    subprocess.run(
        [
            "openssl",
            "genpkey",
            "-algorithm",
            "RSA",
            "-pkeyopt",
            "rsa_keygen_bits:2048",
            "-out",
            k,
        ],
        check=True,
        stderr=subprocess.DEVNULL,
    )
    return k


def main():
    global KEY, PUB, OTHER
    d = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
    KEY = keypair(d, "key")
    OTHER = keypair(d, "other")
    PUB = os.path.join(d, "pub.pem")
    subprocess.run(["openssl", "pkey", "-in", KEY, "-pubout", "-out", PUB], check=True)
    h = Harness(
        "github-app-key parity",
        need_env("GITHUB_APP_KEY_SH"),
        need_env("GITHUB_APP_KEY_RS"),
    )
    for c in cases():
        h.check(c)
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
