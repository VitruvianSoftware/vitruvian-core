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
"""argocd-admin-password :sync, the Rust port, against sync.sh: same exit
code, stdout, stderr, the same calls to fake bw, kubectl, htpasswd and
pulumi (and the environment they saw), and the same Bitwarden and stack
state left behind, on every case below.

    bazel test //tools/argocd-admin-password:sync_rs_parity_test
"""

import json
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, path_without, write, write_exec  # noqa: E402

PROJECT = "ws/infrastructure/pulumi/platform/dev-local"
ITEM = "argocd admin (dev-local)"


def real_jq():
    p = need_env("JQ_BIN")
    if p.startswith("external/"):
        p = "../" + p[len("external/") :]
    return os.path.abspath(p)


JQ = real_jq()

# Every fake logs its argv and the environment the script exported to it.
LOG = r"""log() { printf '%s | PWD=%s PULUMI_BACKEND_URL=%s KUBECONFIG=%s GOWORK=%s BW_SESSION=%s\n' "$*" "$PWD" "${PULUMI_BACKEND_URL-<unset>}" "${KUBECONFIG-<unset>}" "${GOWORK-<unset>}" "${BW_SESSION-<unset>}" >>"$STATE/calls.log"; }
"""

BW = (
    "#!/usr/bin/env bash\n"
    + LOG
    + r"""# create logs once its input has ended, i.e. after encode has run: the two
# run side by side in the script's pipeline.
[ "$1" = create ] || log "bw $*"
case "$1" in
  status) if [ -n "${FAKE_BW_STATUS+x}" ]; then printf '%s' "$FAKE_BW_STATUS"; else echo '{"serverUrl":null,"status":"unlocked"}'; fi
          echo "bw status noise" >&2 ;;
  sync) echo "Syncing complete."; echo "sync noise" >&2; exit "${FAKE_BW_SYNC_RC:-0}" ;;
  list) echo "list noise" >&2
        [ -f "$STATE/items.json" ] && cat "$STATE/items.json"
        exit "${FAKE_BW_LIST_RC:-0}" ;;
  encode) doc=$(cat); printf '%s' "$doc" >"$STATE/encoded.in"; printf 'ENC[%s]' "$doc"
          [ -n "${FAKE_BW_ENCODE_RC:-}" ] && { echo "encode failed" >&2; exit "$FAKE_BW_ENCODE_RC"; }
          exit 0 ;;
  create) in=$(cat); log "bw $*"; printf '%s\n' "$in" >"$STATE/created.in"
          [ -n "${FAKE_BW_CREATE_RC:-}" ] && { echo "create failed" >&2; exit "$FAKE_BW_CREATE_RC"; }
          doc=${in#ENC[}; doc=${doc%]}
          [ -z "${FAKE_BW_NOSAVE:-}" ] && printf '[%s]\n' "$doc" >"$STATE/items.json"
          echo '{"id":"new"}' ;;
  *) echo "fake bw: unexpected $*" >&2; exit 99 ;;
esac
"""
)

KUBECTL = (
    "#!/usr/bin/env bash\n"
    + LOG
    + r"""log "kubectl $*"
echo "kubectl noise" >&2
[ -n "${FAKE_SECRET_B64:-}" ] && printf '%s' "$FAKE_SECRET_B64"
exit "${FAKE_KUBECTL_RC:-0}"
"""
)

# A stand-in bcrypt: "$2y$10$" + the password's CRC, so verifying works and
# any password gives a stable hash.
HTPASSWD = (
    "#!/usr/bin/env bash\n"
    + LOG
    + r"""log "htpasswd $*"
pw=$(cat; echo x); pw=${pw%x}
tag=$(printf '%s' "$pw" | cksum | cut -d' ' -f1)
case "$1" in
  -niBC)
    [ -n "${FAKE_HTPASSWD_RC:-}" ] && { echo "htpasswd: failed" >&2; exit "$FAKE_HTPASSWD_RC"; }
    printf ':%s%s\n\n' "${FAKE_HTPASSWD_PREFIX:-\$2y\$10\$}" "$tag" ;;
  -vi)
    printf 'verify file: %s\n' "$(cat "$2")" >>"$STATE/calls.log"
    want=$(sed -n 's/^admin://p' "$2")
    case "$want" in "\$2a\$10\$$tag"|"\$2y\$10\$$tag") echo "Password for user admin correct."; exit 0 ;; esac
    echo "password verification failed" >&2; exit 3 ;;
esac
"""
)

PULUMI = (
    "#!/usr/bin/env bash\n"
    + LOG
    + r"""log "pulumi $*"
key=$3
case "$1 $2" in
  "config get")
    if [ -f "$STATE/cfg.$key" ]; then cat "$STATE/cfg.$key"; else echo "error: configuration key '$key' not found" >&2; exit 255; fi ;;
  "config set")
    key=$4
    [ "$key" = "${FAKE_PULUMI_SET_FAIL:-}" ] && { echo "error: cannot set $key" >&2; exit 7; }
    eval "val=\${$#}"
    printf '%s\n' "$val" >"$STATE/cfg.$key"
    echo "set $key" ;;
  *) echo "fake pulumi: unexpected $*" >&2; exit 99 ;;
esac
"""
)

HASH = "$2a$10$"  # + cksum of the password


def cksum(pw):
    # POSIX cksum (not zlib's crc32): CRC-32/CKSUM over the data and its length.
    crc = 0
    tbl = []
    for i in range(256):
        c = i << 24
        for _ in range(8):
            c = ((c << 1) ^ 0x04C11DB7) if c & 0x80000000 else (c << 1)
        tbl.append(c & 0xFFFFFFFF)
    data = pw.encode()
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ tbl[((crc >> 24) ^ b) & 0xFF]
    n = len(data)
    while n:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ tbl[((crc >> 24) ^ (n & 0xFF)) & 0xFF]
        n >>= 8
    return str((~crc) & 0xFFFFFFFF)


def item(password="s3cret", name=ITEM, extra=None):
    d = {"id": "1", "name": name, "login": {"username": "admin", "password": password}}
    if extra:
        d.update(extra)
    return d


def setup_with(
    items=None, items_raw=None, cfg=None, yaml="argocd_enabled: true\n", extra=None
):
    def setup(root):
        st = root + "/state"
        os.makedirs(st)
        write_exec(root + "/bin/bw", BW)
        write_exec(root + "/bin/kubectl", KUBECTL)
        write_exec(root + "/bin/htpasswd", HTPASSWD)
        write_exec(root + "/bin/pulumi", PULUMI)
        os.symlink(JQ, root + "/bin/jq")
        if yaml is not None:
            write(root + "/" + PROJECT + "/Pulumi.local.yaml", yaml)
        else:
            os.makedirs(root + "/" + PROJECT)
        if items_raw is not None:
            write(st + "/items.json", items_raw)
        elif items is not None:
            write(st + "/items.json", json.dumps(items))
        for k, v in (cfg or {}).items():
            write(st + "/cfg." + k, v + "\n")
        if extra:
            extra(root)

    return setup


ENV = {"STATE": "{root}/state", "BUILD_WORKSPACE_DIRECTORY": "{root}/ws"}
TIME = [(rb"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", b"<TIME>")]
# A random password (and so its stand-in hash) differs run to run.
RANDOM = TIME + [
    (rb'"password":"[A-Za-z0-9]{32}"', b'"password":"<RANDOM>"'),
    (rb"\$2([ay])\$10\$\d+", rb"$2\1$10$<CRC>"),
]


def case(name, setup, env=None, normalise=None, **kw):
    e = dict(ENV)
    e.update(env or {})
    return Case(name=name, env=e, setup=setup, normalise=(normalise or []) + TIME, **kw)


IN_SYNC = {
    "argocd_admin_password_bcrypt": HASH + cksum("s3cret"),
    "argocd_admin_password_mtime": "2026-01-02T03:04:05Z",
}


def cases():
    yield case("already in sync", setup_with([item()], cfg=IN_SYNC))
    yield case(
        "already in sync with a \\$2y hash",
        setup_with(
            [item()],
            cfg=dict(IN_SYNC, argocd_admin_password_bcrypt="$2y$10$" + cksum("s3cret")),
        ),
    )
    yield case(
        "stale hash is replaced",
        setup_with(
            [item()], cfg=dict(IN_SYNC, argocd_admin_password_bcrypt=HASH + "1")
        ),
    )
    yield case("no stack config yet", setup_with([item()]))
    yield case(
        "a hash but no mtime",
        setup_with(
            [item()], cfg={"argocd_admin_password_bcrypt": HASH + cksum("s3cret")}
        ),
    )
    yield case(
        "an mtime but no hash",
        setup_with([item()], cfg={"argocd_admin_password_mtime": "x"}),
    )
    yield case(
        "first run seeds from the live secret",
        setup_with([]),
        env={"FAKE_SECRET_B64": "bGl2ZS1wYXNzd29yZA=="},  # gitleaks:allow
    )
    yield case(
        "a live secret with trailing newlines",
        setup_with([{"name": "other"}]),
        env={"FAKE_SECRET_B64": "bGl2ZQoK"},
    )
    yield case(
        "a live secret with odd characters",
        setup_with(None),
        env={"FAKE_SECRET_B64": "cCJcf8OpL3g="},
    )
    yield case(
        "first run with no live secret makes a random password",
        setup_with(None),
        normalise=RANDOM,
    )
    yield case(
        "kubectl fails: random password",
        setup_with(None),
        env={"FAKE_KUBECTL_RC": "1", "FAKE_SECRET_B64": "eA=="},
        normalise=RANDOM,
    )
    yield case(
        "created but cannot be read back",
        setup_with(None),
        env={"FAKE_SECRET_B64": "eA==", "FAKE_BW_NOSAVE": "1"},
    )
    yield case(
        "bw create fails",
        setup_with(None),
        env={"FAKE_SECRET_B64": "eA==", "FAKE_BW_CREATE_RC": "4"},
    )
    yield case(
        "bw encode fails, create succeeds",
        setup_with(None),
        env={"FAKE_SECRET_B64": "eA==", "FAKE_BW_ENCODE_RC": "6"},
    )
    yield case(
        "bw encode and create both fail",
        setup_with(None),
        env={
            "FAKE_SECRET_B64": "eA==",
            "FAKE_BW_ENCODE_RC": "6",
            "FAKE_BW_CREATE_RC": "4",
        },
    )
    yield case(
        "locked", setup_with([item()]), env={"FAKE_BW_STATUS": '{"status":"locked"}'}
    )
    yield case(
        "status without a status", setup_with([item()]), env={"FAKE_BW_STATUS": "{}"}
    )
    yield case(
        "status is an array (a jq error)",
        setup_with([item()]),
        env={"FAKE_BW_STATUS": '{"status":"locked"}\n["x"]\n'},
    )
    yield case(
        "two status documents",
        setup_with([item()]),
        env={"FAKE_BW_STATUS": '{"status":"unlocked"} {"status":"unlocked"}'},
    )
    yield case(
        "status is a string",
        setup_with([item()]),
        env={"FAKE_BW_STATUS": '\n\n"unlocked"\n'},
    )
    yield case(
        "status is not JSON",
        setup_with([item()]),
        env={"FAKE_BW_STATUS": "You are not logged in."},
        normalise=[(rb"jq: parse error: [^\n]*", b"jq: parse error: <msg>")],
    )
    yield case(
        "no bw at all",
        setup_with([item()], extra=lambda r: os.remove(r + "/bin/bw")),
        env={"PATH": "{root}/bin:" + path_without("bw")},
    )
    yield case(
        "bw sync fails: carries on",
        setup_with([item()], cfg=IN_SYNC),
        env={"FAKE_BW_SYNC_RC": "2"},
    )
    yield case("bw list fails", setup_with([item()]), env={"FAKE_BW_LIST_RC": "1"})
    yield case("bw list is a string", setup_with(items_raw='"nope"'))
    yield case(
        "bw list holds a number",
        setup_with(
            items_raw='[{"name":"a"}, 3, {"name":"%s","login":{"password":"p"}}]' % ITEM
        ),
    )
    yield case(
        "bw list holds a long string",
        setup_with(items_raw='"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'),
    )
    yield case(
        "bw list is an object", setup_with(items_raw='{"a": %s}' % json.dumps(item()))
    )
    yield case(
        "the first of several matches wins",
        setup_with([item("first"), item("second")]),
    )
    yield case(
        "null and other entries are skipped",
        setup_with(items_raw='[null, {"name":"x"}, %s]' % json.dumps(item("p2"))),
    )
    yield case(
        "two list documents",
        setup_with(
            items_raw="[%s]\n[%s]\n" % (json.dumps(item("a")), json.dumps(item("b")))
        ),
    )
    yield case(
        "no password", setup_with([item(extra={"login": {"username": "admin"}})])
    )
    yield case("empty password", setup_with([item("")]))
    yield case("false password", setup_with([item(False)]))
    yield case("null login", setup_with([item(extra={"login": None})]))
    yield case("login is a string", setup_with([item(extra={"login": "admin"})]))
    yield case("numeric password", setup_with([item(1234)]))
    yield case(
        "no BUILD_WORKSPACE_DIRECTORY",
        setup_with([item()]),
        env={"BUILD_WORKSPACE_DIRECTORY": None},
    )
    yield case(
        "empty BUILD_WORKSPACE_DIRECTORY",
        setup_with([item()]),
        env={"BUILD_WORKSPACE_DIRECTORY": ""},
    )
    yield case(
        "workspace without the project",
        setup_with([item()]),
        env={"BUILD_WORKSPACE_DIRECTORY": "{root}/elsewhere"},
    )
    yield case(
        "a workspace path with a trailing slash",
        setup_with([item()]),
        env={"BUILD_WORKSPACE_DIRECTORY": "{root}/ws/"},
    )
    yield case("no Pulumi.local.yaml", setup_with([item()], yaml=None))
    yield case(
        "Pulumi.local.yaml without argocd", setup_with([item()], yaml="config: {}\n")
    )
    yield case("no HOME, no XDG_CACHE_HOME", setup_with([item()]), env={"HOME": None})
    yield case(
        "no HOME with XDG_CACHE_HOME",
        setup_with([item()]),
        env={"HOME": None, "XDG_CACHE_HOME": "{root}/xdg"},
    )
    yield case(
        "no HOME with XDG_CACHE_HOME and KUBECONFIG",
        setup_with([item()]),
        env={"HOME": None, "XDG_CACHE_HOME": "{root}/xdg", "KUBECONFIG": "/k"},
    )

    def cache(root):
        write(root + "/home/.cache/vitruvian-core/bw-session", "SESSION-FROM-CACHE\n\n")

    yield case("BW_SESSION from the cache", setup_with([item()], extra=cache))
    yield case(
        "BW_SESSION already set wins",
        setup_with([item()], extra=cache),
        env={"BW_SESSION": "MINE"},
    )
    yield case(
        "an empty BW_SESSION is filled from the cache",
        setup_with([item()], extra=cache),
        env={"BW_SESSION": ""},
    )

    def xdg_cache(root):
        write(root + "/xdg/vitruvian-core/bw-session", "XDG-SESSION")

    yield case(
        "the cache under XDG_CACHE_HOME",
        setup_with([item()], extra=xdg_cache),
        env={"XDG_CACHE_HOME": "{root}/xdg"},
    )

    def cache_dir(root):
        os.makedirs(root + "/home/.cache/vitruvian-core/bw-session")

    yield case("the cache is a directory", setup_with([item()], extra=cache_dir))
    yield case(
        "caller's PULUMI_BACKEND_URL and KUBECONFIG are kept",
        setup_with([item()]),
        env={
            "PULUMI_BACKEND_URL": "file:///tmp/x",
            "KUBECONFIG": "/etc/kube",
            "GOWORK": "on",
        },
    )
    yield case("htpasswd fails", setup_with([item()]), env={"FAKE_HTPASSWD_RC": "9"})
    yield case(
        "an unexpected bcrypt",
        setup_with([item()]),
        env={"FAKE_HTPASSWD_PREFIX": "$2b$12$"},
    )
    yield case(
        "no htpasswd at all",
        setup_with([item()], extra=lambda r: os.remove(r + "/bin/htpasswd")),
        env={"PATH": "{root}/bin:" + path_without("htpasswd")},
    )
    yield case(
        "saving the hash fails",
        setup_with([item()]),
        env={"FAKE_PULUMI_SET_FAIL": "argocd_admin_password_bcrypt"},
    )
    yield case(
        "saving the mtime fails",
        setup_with([item()]),
        env={"FAKE_PULUMI_SET_FAIL": "argocd_admin_password_mtime"},
    )
    yield case("a password with spaces and quotes", setup_with([item("a b'c\"d\\e")]))


def main():
    h = Harness(
        "argocd-admin-password sync parity",
        need_env("SYNC_SH"),
        need_env("SYNC_RS"),
    )
    for c in cases():
        h.check(c)
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
