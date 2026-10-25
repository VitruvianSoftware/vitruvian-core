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
"""apple-signing, the Rust port, against apple-signing.sh: same exit code,
stdout, stderr, the same calls to fake gh, bw, xcrun, security and curl
(and what was piped to them), and the same files left behind, on every case
below. openssl is the real one: one throwaway key and certificate are made
here and copied into both sandboxes, so everything derived from them is
comparable; the random .p12 password and bundle are normalised.

    bazel test //tools/apple-signing:apple_signing_rs_parity_test
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

_PY = shutil.which("python3") or sys.executable
_SSL = (
    shutil.which("openssl", path="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin")
    or "openssl"
)
BASE_PATH = ":".join(
    dict.fromkeys(
        [
            os.path.dirname(_PY),
            os.path.dirname(_SSL),
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
    )
)

LOG = 'printf "%s\\n" "$*" >>"$STATE/calls.log"\n'

GH = (
    "#!/usr/bin/env bash\n"
    + r"""if [ "$1 $2" = "secret set" ]; then
  v=$(cat)
  case "$3" in *P12|*PASSWORD) shown="len=${#v}" ;; *) shown="value=$v" ;; esac
  printf 'gh secret set %s %s %s | %s GH_TOKEN=%s GITHUB_TOKEN=%s\n' "$3" "$4" "$5" "$shown" "${GH_TOKEN-<unset>}" "${GITHUB_TOKEN-<unset>}" >>"$STATE/calls.log"
  [ "$3" = "${FAKE_GH_SET_FAIL:-}" ] && { echo "gh: HTTP 403" >&2; exit 4; }
  exit 0
elif [ "$1 $2" = "secret list" ]; then
  printf 'gh secret list %s %s\n' "$3" "$4" >>"$STATE/calls.log"
  cat "$STATE/gh-list" 2>/dev/null
  exit "${FAKE_GH_LIST_RC:-0}"
fi
echo "fake gh: unexpected $*" >&2; exit 99
"""
)

BW = (
    "#!/usr/bin/env bash\n"
    + r"""case $1 in
  status) echo "bw status" >>"$STATE/calls.log"
          if [ -n "${FAKE_BW_STATUS+x}" ]; then printf '%s' "$FAKE_BW_STATUS"; else echo '{"status":"unlocked"}'; fi ;;
  unlock) echo "bw unlock $*" >>"$STATE/calls.log"; [ -n "${FAKE_UNLOCK_RC:-}" ] && exit "$FAKE_UNLOCK_RC"; printf 'SESSION-123\n' ;;
  sync) echo "bw sync BW_SESSION=${BW_SESSION-<unset>}" >>"$STATE/calls.log"; echo synced; exit "${FAKE_SYNC_RC:-0}" ;;
  list) echo "bw $*" >>"$STATE/calls.log"
        if [ -f "$STATE/bw-items" ]; then cat "$STATE/bw-items"; else echo '[]'; fi
        exit "${FAKE_LIST_RC:-0}" ;;
  encode) d=$(cat; echo x); d=${d%x}; printf '%s' "$d" >>"$STATE/encoded.log"; printf '%s' "$d" ;;
  create) d=$(cat); echo "bw create $2 ($(printf '%s' "$d" | wc -c | tr -d ' ') bytes)" >>"$STATE/calls.log"
          [ -n "${FAKE_CREATE_RC:-}" ] && { echo "bw: create failed" >&2; exit "$FAKE_CREATE_RC"; }
          echo '{"id":"x"}' ;;
  *) echo "fake bw: unexpected $*" >&2; exit 99 ;;
esac
"""
)

XCRUN = (
    "#!/usr/bin/env bash\n"
    + LOG
    + r"""case "$2" in
  info) printf '%b' "${FAKE_INFO:-  id: $3\n  status: ${FAKE_STATUS:-In Progress}\n}" ;;
  history) echo "  id: sub-1"; echo "  status: Accepted" ;;
  log) echo '{"status": "Invalid", "issues": []}' ;;
esac
[ -z "${XCRUN_FAILS:-}" ] || { echo "xcrun: Error: HTTP status code: 401" >&2; exit 69; }
"""
)

SECURITY = (
    "#!/usr/bin/env bash\n"
    + r"""echo "security $1 $2 $3" >>"$STATE/calls.log"
case "$1" in
  find-certificate) exit "${FAKE_FIND_CERT_RC:-0}" ;;
  find-identity) printf '%b' "${FAKE_IDENTITIES:-  1) ABC \"Developer ID Application: TEST (TEAM123)\"\n     1 valid identities found\n}" ;;
  import) [ "$2" = developer-id.p12 ] && [ -n "${FAKE_IMPORT_P12_RC:-}" ] && exit "$FAKE_IMPORT_P12_RC"; exit 0 ;;
esac
"""
)

CURL = (
    "#!/usr/bin/env bash\n"
    + LOG
    + r"""[ -n "${FAKE_CURL_RC:-}" ] && { echo "curl: (6) Could not resolve host" >&2; exit "$FAKE_CURL_RC"; }
printf 'CA CERT' >"$3"
"""
)

GH_LIST_FULL = "".join(
    "VITRUVIAN_%s\t2026-10-01T00:00:00Z\n" % s
    for s in (
        "SIGNING_CERT_P12",
        "SIGNING_CERT_PASSWORD",
        "NOTARY_API_KEY_P8",
        "NOTARY_KEY_ID",
        "NOTARY_ISSUER_ID",
    )
)

SUBJECT = "/CN=Developer ID Application: TEST (TEAM123)/OU=TEAM123/O=TEST/C=US"

# Made once, copied into every sandbox.
FIX = tempfile.mkdtemp(prefix="apple-fixtures.", dir=os.environ.get("TEST_TMPDIR"))


def ssl(*args, stdin=None):
    subprocess.run([_SSL] + list(args), check=True, input=stdin, capture_output=True)


def make_fixtures():
    ssl("genrsa", "-out", FIX + "/developer-id.key", "2048")
    os.chmod(FIX + "/developer-id.key", 0o600)
    csr = subprocess.run(
        [_SSL, "req", "-new", "-key", FIX + "/developer-id.key", "-subj", SUBJECT],
        check=True,
        capture_output=True,
    ).stdout
    ssl(
        "x509",
        "-req",
        "-signkey",
        FIX + "/developer-id.key",
        "-days",
        "2",
        "-outform",
        "der",
        "-out",
        FIX + "/developer-id.cer",
        stdin=csr,
    )
    # A certificate with a name Apple would not issue, for the same key.
    csr2 = subprocess.run(
        [
            _SSL,
            "req",
            "-new",
            "-key",
            FIX + "/developer-id.key",
            "-subj",
            "/CN=Apple Development: X/OU=T2/C=US",
        ],
        check=True,
        capture_output=True,
    ).stdout
    ssl(
        "x509",
        "-req",
        "-signkey",
        FIX + "/developer-id.key",
        "-days",
        "2",
        "-outform",
        "der",
        "-out",
        FIX + "/development.cer",
        stdin=csr2,
    )
    # A certificate for another key.
    ssl(
        "req",
        "-x509",
        "-newkey",
        "rsa:2048",
        "-nodes",
        "-keyout",
        FIX + "/other.key",
        "-days",
        "2",
        "-outform",
        "der",
        "-out",
        FIX + "/other.cer",
        "-subj",
        SUBJECT,
    )


def setup_with(
    key=True,
    cer="developer-id.cer",
    p8="fake-p8\n",
    p8_at="AuthKey_K1.p8",
    gh_list=GH_LIST_FULL,
    bw_items=None,
    notary_env=None,
    signing_key_p8=False,
    extra=None,
):
    def setup(root):
        os.makedirs(root + "/state")
        for name, body in (
            ("gh", GH),
            ("bw", BW),
            ("xcrun", XCRUN),
            ("security", SECURITY),
            ("curl", CURL),
        ):
            write_exec(root + "/bin/" + name, body)
        sd = root + "/signing"
        if key or cer or notary_env is not None:
            os.makedirs(sd, mode=0o700)
        if key:
            shutil.copy(FIX + "/developer-id.key", sd + "/developer-id.key")
            os.chmod(sd + "/developer-id.key", 0o600)
        if cer:
            shutil.copy(FIX + "/" + cer, sd + "/developer-id.cer")
            os.chmod(sd + "/developer-id.cer", 0o644)
        if p8 is not None:
            write(root + "/" + p8_at, p8)
        if gh_list is not None:
            write(root + "/state/gh-list", gh_list)
        if bw_items is not None:
            write(root + "/state/bw-items", bw_items)
        if notary_env is not None:
            write(sd + "/notary.env", notary_env)
        if signing_key_p8:
            write(sd + "/AuthKey_K1.p8", "fake-p8\n")
        if extra:
            extra(root)

    return setup


# The bundle and its password are random; everything else is fixed.
RANDOM = [
    (rb'("name": "p12 password", "value": ")[A-Za-z0-9]{32}"', rb'\1<P>"'),
    (rb'("notes": ")MI[A-Za-z0-9+/=]+"', rb'\1<P12 BASE64>"'),
    (rb"value=MI[A-Za-z0-9+/=]+", b"value=<P12 BASE64>"),
    # p12.b64, left behind when a Bitwarden step fails.
    (rb"(?m)^MII[A-Za-z0-9+/=]{100,}$", b"<P12 BASE64>"),
    (rb"\(\d+ bytes\)", b"(N bytes)"),
    (rb"len=\d+", lambda m: m.group(0) if m.group(0) in (b"len=32",) else b"len=<N>"),
    (rb"(?s)-----BEGIN ([A-Z ]+)-----.*?-----END \1-----", rb"<PEM \1>"),
]

ENV = {
    "STATE": "{root}/state",
    "APPLE_SIGNING_DIR": "{root}/signing",
    "GH_TOKEN": "ambient",
    "GITHUB_TOKEN": "ambient2",
}
# The bundle is random; macOS's /usr/bin/python3 shim caches under
# $HOME/Library, and the port runs no python.
IGNORE = [r"signing/developer-id\.p12$", r"home/Library(/|$)"]


def case(name, setup, args, env=None, normalise=None, ignore=None, **kw):
    e = dict(ENV)
    e.update(env or {})
    return Case(
        name=name,
        args=args,
        env=e,
        setup=setup,
        normalise=RANDOM + (normalise or []),
        ignore=IGNORE + (ignore or []),
        **kw,
    )


PY_ERR = [
    (
        rb"(?ms)^(Traceback \(most recent call last\):.*?^\S[^\n]*\n|apple-signing: bw (list|status): [^\n]*\n)",
        b"<python error>\n",
    )
]

SECRETS = ["secrets", "K1", "ISS", "{root}/AuthKey_K1.p8"]


def cases():
    yield case("no command", setup_with(), [])
    yield case("an empty command", setup_with(), [""])
    yield case("unknown command", setup_with(), ["nope", "x"])
    yield case("secrets with two arguments", setup_with(), ["secrets", "K1", "ISS"])
    yield case(
        "notary-status with two arguments", setup_with(), ["notary-status", "a", "b"]
    )
    yield case(
        "no HOME and no APPLE_SIGNING_DIR",
        setup_with(),
        ["check"],
        env={"HOME": None, "APPLE_SIGNING_DIR": None},
    )
    yield case(
        "an empty APPLE_SIGNING_DIR falls back to HOME",
        setup_with(),
        ["check"],
        env={"APPLE_SIGNING_DIR": ""},
    )

    # csr: a fresh key and request (their bytes are random: compared as PEM
    # blocks, with their modes).
    yield case("csr", setup_with(key=False, cer=None), ["csr", "ignored"])
    yield case(
        "csr in a folder that does not exist yet",
        setup_with(key=False, cer=None),
        ["csr"],
        env={"APPLE_SIGNING_DIR": "{root}/new/deeper"},
    )
    yield case("csr refuses to overwrite a key", setup_with(), ["csr"])

    # secrets: the refusals.
    yield case("secrets without a key", setup_with(key=False), SECRETS)
    yield case("secrets without a certificate", setup_with(cer=None), SECRETS)
    yield case("secrets without the API key file", setup_with(p8=None), SECRETS)
    yield case(
        "secrets with a certificate for another key",
        setup_with(cer="other.cer"),
        SECRETS,
    )
    yield case(
        "secrets with a certificate that is not Developer ID",
        setup_with(cer="development.cer"),
        SECRETS,
    )
    yield case(
        "Apple rejects the API key", setup_with(), SECRETS, env={"XCRUN_FAILS": "1"}
    )

    # secrets: the full run.
    yield case("secrets", setup_with(), SECRETS)
    yield case(
        "secrets, 3 of 5 secrets afterwards",
        setup_with(gh_list=GH_LIST_FULL.split("\n", 2)[2]),
        SECRETS,
    )
    yield case(
        "secrets with the key already in place",
        setup_with(p8_at="signing/AuthKey_K1.p8"),
        ["secrets", "K1", "ISS", "{root}/signing/AuthKey_K1.p8"],
    )
    yield case(
        "secrets with a relative key path (resolved after cd, as the script does)",
        setup_with(),
        ["secrets", "K1", "ISS", "AuthKey_K1.p8"],
    )
    yield case(
        "secrets with a CRLF API key", setup_with(p8="line1\r\nline2\r\n"), SECRETS
    )
    yield case(
        "secrets with non-ASCII IDs",
        setup_with(p8_at="AuthKey_Ké.p8"),
        ["secrets", "Ké", "Iß😀", "{root}/AuthKey_Ké.p8"],
    )
    yield case(
        "secrets, Bitwarden locked",
        setup_with(),
        SECRETS,
        env={"FAKE_BW_STATUS": '{"status": "locked"}'},
    )
    yield case(
        "secrets, unlock fails",
        setup_with(),
        SECRETS,
        env={"FAKE_BW_STATUS": '{"status": "locked"}', "FAKE_UNLOCK_RC": "3"},
    )
    yield case(
        "secrets, status not JSON",
        setup_with(),
        SECRETS,
        env={"FAKE_BW_STATUS": "not json"},
        normalise=PY_ERR,
    )
    yield case(
        "secrets, status without status",
        setup_with(),
        SECRETS,
        env={"FAKE_BW_STATUS": "{}"},
        normalise=PY_ERR,
    )
    yield case(
        "secrets, status with a newline",
        setup_with(),
        SECRETS,
        env={"FAKE_BW_STATUS": '{"status": "unlocked\\n"}'},
    )
    yield case(
        "secrets, bw sync fails", setup_with(), SECRETS, env={"FAKE_SYNC_RC": "5"}
    )
    yield case(
        "secrets, a gh secret fails",
        setup_with(),
        SECRETS,
        env={"FAKE_GH_SET_FAIL": "VITRUVIAN_NOTARY_KEY_ID"},
    )
    yield case(
        "secrets, bw create fails", setup_with(), SECRETS, env={"FAKE_CREATE_RC": "8"}
    )
    yield case(
        "secrets, items already in Bitwarden",
        setup_with(
            bw_items='[{"name":"Apple Developer ID Application certificate (p12)"},'
            '{"name":"App Store Connect API key (notary)"},'
            '{"name":"Apple Developer ID private key + certificate (PEM)"}]'
        ),
        SECRETS,
    )
    yield case(
        "secrets, a match before a bad entry",
        setup_with(bw_items='[{"name":"App Store Connect API key (notary)"}, 3]'),
        SECRETS,
        normalise=PY_ERR,
    )
    yield case(
        "secrets, bw list not JSON",
        setup_with(bw_items="oops"),
        SECRETS,
        normalise=PY_ERR,
    )
    yield case(
        "secrets, bw list fails after a match",
        setup_with(bw_items='[{"name":"App Store Connect API key (notary)"}]'),
        SECRETS,
        env={"FAKE_LIST_RC": "2"},
    )
    yield case(
        "secrets, no CA yet: downloads it",
        setup_with(),
        SECRETS,
        env={"FAKE_FIND_CERT_RC": "44"},
    )
    yield case(
        "secrets, CA download fails",
        setup_with(),
        SECRETS,
        env={"FAKE_FIND_CERT_RC": "44", "FAKE_CURL_RC": "6"},
    )
    yield case(
        "secrets, identity already in the keychain",
        setup_with(),
        SECRETS,
        env={"FAKE_IMPORT_P12_RC": "1"},
    )
    yield case(
        "secrets on a machine without security",
        setup_with(extra=lambda r: os.remove(r + "/bin/security")),
        SECRETS,
        env={"PATH": "{root}/bin:" + path_without("security", base=BASE_PATH)},
    )
    yield case(
        "secrets with another repo and prefix",
        setup_with(gh_list=GH_LIST_FULL.replace("VITRUVIAN_", "OTHER_")),
        SECRETS,
        env={"APPLE_SIGNING_REPO": "me/repo", "APPLE_SIGNING_SECRET_PREFIX": "OTHER"},
    )

    # check
    yield case("check, all set", setup_with(), ["check", "extra"])
    yield case("check, nothing set", setup_with(gh_list="", cer=None), ["check"])
    yield case(
        "check, gh list fails", setup_with(), ["check"], env={"FAKE_GH_LIST_RC": "1"}
    )
    yield case(
        "check counts only real secret lines",
        setup_with(
            gh_list=GH_LIST_FULL
            + "VITRUVIAN_NOTARY_KEY_IDX\t1\nVITRUVIAN_NOTARY_KEY_ID\n"
        ),
        ["check"],
    )
    yield case(
        "check with space-separated lines",
        setup_with(gh_list=GH_LIST_FULL.replace("\t", " ")),
        ["check"],
    )
    yield case(
        "check without security",
        setup_with(extra=lambda r: os.remove(r + "/bin/security")),
        ["check"],
        env={"PATH": "{root}/bin:" + path_without("security", base=BASE_PATH)},
    )
    yield case(
        "check, no identities",
        setup_with(),
        ["check"],
        env={"FAKE_IDENTITIES": "     0 valid identities found\\n"},
    )

    # notary-status
    NE = "KEY_ID=K1\nISSUER_ID=ISS\n"
    yield case(
        "notary-status lists submissions",
        setup_with(notary_env=NE, signing_key_p8=True),
        ["notary-status"],
    )
    yield case(
        "notary-status, history fails",
        setup_with(notary_env=NE, signing_key_p8=True),
        ["notary-status"],
        env={"XCRUN_FAILS": "1"},
    )
    yield case(
        "notary-status of one in progress",
        setup_with(notary_env=NE, signing_key_p8=True),
        ["notary-status", "sub-1"],
    )
    yield case(
        "notary-status of a finished one",
        setup_with(notary_env=NE, signing_key_p8=True),
        ["notary-status", "sub-1"],
        env={"FAKE_STATUS": "Invalid"},
    )
    yield case(
        "notary-status, info fails",
        setup_with(notary_env=NE, signing_key_p8=True),
        ["notary-status", "sub-1"],
        env={"XCRUN_FAILS": "1"},
    )
    yield case(
        "notary-status, info without a status line",
        setup_with(notary_env=NE, signing_key_p8=True),
        ["notary-status", "sub-1"],
        env={"FAKE_INFO": "  id: sub-1\\n\\n\\n"},
    )
    yield case(
        "notary-status, two status lines",
        setup_with(notary_env=NE, signing_key_p8=True),
        ["notary-status", "sub-1"],
        env={"FAKE_INFO": "status: Accepted\\n   status: In Progress\\n"},
    )
    yield case("notary-status without notary.env", setup_with(), ["notary-status"])
    yield case(
        "notary-status with an empty KEY_ID",
        setup_with(notary_env="KEY_ID=\nISSUER_ID=ISS\n"),
        ["notary-status"],
    )
    yield case(
        "notary-status with quoted values",
        setup_with(notary_env="KEY_ID='K1'\nISSUER_ID=\"ISS\"\n", signing_key_p8=True),
        ["notary-status"],
    )
    yield case(
        "notary-status without the API key",
        setup_with(notary_env=NE),
        ["notary-status"],
    )


def main():
    make_fixtures()
    h = Harness(
        "apple-signing parity",
        need_env("APPLE_SIGNING_SH"),
        need_env("APPLE_SIGNING_RS"),
        base_path=BASE_PATH,
    )
    for c in cases():
        h.check(c)
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
