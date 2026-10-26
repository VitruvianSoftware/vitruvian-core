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
"""sync-env-secrets, the Rust port, against sync-env-secrets.sh: same exit
code, stdout, stderr, the same calls to a fake `bw` (argv, the session it was
handed, what it was fed) and `gh` (argv and the secret on stdin), and the
same files left behind -- the fake vault, the local store, the cached
session and their modes -- on every case below.

    bazel test //tools/sync-env-secrets:sync_env_secrets_rs_parity_test

The script needs jq (the hermetic one, JQ_BIN); the port does not.
"""

import os
import signal
import subprocess
import sys
import time

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, path_without, write, write_exec  # noqa: E402

# A fake Bitwarden: the vault is a directory. An attachment is stored as its
# extracted contents, so a push compares by what was archived, not by the
# gzip bytes (which carry a timestamp).
BW = r"""#!/usr/bin/env bash
V="$VAULT"
# A stage of a pipeline logs only after its input is in, so concurrent
# stages (printf | bw encode | bw create item) log in a fixed order.
log() { printf '%s | session=%s\n' "$*" "${BW_SESSION-<unset>}" >>"$LOGDIR/bw.log"; }
case "$1 ${2:-}" in "encode "* | "create item") ;; *) log "$@" ;; esac
case "$1" in
  status)
    [ -n "${FAKE_STATUS_RAW:-}" ] && { printf '%s\n' "$FAKE_STATUS_RAW"; exit "${FAKE_STATUS_RC:-0}"; }
    if [ "${FAKE_UNAUTH:-0}" = 1 ]; then echo '{"status":"unauthenticated"}'
    elif [ "${BW_SESSION:-}" = good ]; then echo '{"status":"unlocked"}'
    else echo '{"status":"locked"}'; fi
    exit "${FAKE_STATUS_RC:-0}" ;;
  unlock)
    [ "${FAKE_UNLOCK_EMPTY:-0}" = 1 ] && exit 0
    if [ "${BW_PASSWORD:-}" = pw ]; then printf 'good'; exit 0; fi
    echo "Invalid master password." >&2; exit 1 ;;
  sync) [ "${FAKE_SYNC_FAIL:-0}" = 1 ] && { echo "sync failed" >&2; exit 1; }; echo "Syncing complete." ;;
  lock) echo "Your vault is locked." ;;
  list)
    [ -n "${FAKE_LIST_RAW:-}" ] && { printf '%s\n' "$FAKE_LIST_RAW"; exit 0; }
    if [ -f "$V/item" ]; then printf '[{"id":"item-1","name":"%s"},{"id":"item-2"}]\n' "$(cat "$V/item.name")"; else echo '[]'; fi ;;
  encode) data="$(cat)"; log "$@"; printf 'encoded<%s>\n' "$data" >>"$LOGDIR/bw.log"; printf 'B64:%s' "$data" ;;
  create)
    case "$2" in
      item)
        data="$(cat)"; log "$@"; printf 'create item got <%s>\n' "$data" >>"$LOGDIR/bw.log"
        [ "${FAKE_CREATE_FAIL:-0}" = 1 ] && { echo "create failed" >&2; exit 1; }
        mkdir -p "$V"; : >"$V/item"; printf '%s' "$data" >"$V/item.name"
        if [ -n "${FAKE_CREATE_REPLY:-}" ]; then echo "$FAKE_CREATE_REPLY"; else echo '{"id":"item-1"}'; fi ;;
      attachment)
        [ "${FAKE_ATTACH_FAIL:-0}" = 1 ] && { echo "attach failed" >&2; exit 1; }
        file="$5"; n=$(( $(ls -d "$V"/att-*.d 2>/dev/null | wc -l) + 1 ))
        mkdir -p "$V/att-$n.d"; basename "$file" >"$V/att-$n.name"
        tar -xzf "$file" -C "$V/att-$n.d"
        echo "{\"id\":\"att-$n\"}" ;;
    esac ;;
  get)
    case "$2" in
      item)
        [ -n "${FAKE_ITEM_RAW:-}" ] && { printf '%s\n' "$FAKE_ITEM_RAW"; exit 0; }
        printf '{"id":"%s","attachments":[' "$3"; sep=""
        for d in "$V"/att-*.d; do
          [ -d "$d" ] || continue; a="$(basename "$d" .d)"
          printf '%s{"id":"%s","fileName":"%s"}' "$sep" "$a" "$(cat "$V/$a.name")"; sep=","
        done
        echo ']}' ;;
      attachment)
        [ "${FAKE_GETATT_FAIL:-0}" = 1 ] && { echo "download failed" >&2; exit 1; }
        tar -czf "$7" -C "$V/$3.d" .
        # Hold the decrypted archive in place for the interrupt check.
        [ -n "${FAKE_GETATT_HOLD:-}" ] && { printf '%s\n' "$7" >"$LOGDIR/held"; sleep "$FAKE_GETATT_HOLD"; }
        : ;;
    esac ;;
  delete)
    [ "${FAKE_DELETE_FAIL:-0}" = 1 ] && { echo "delete failed" >&2; exit 1; }
    rm -rf "$V/$3.d" "$V/$3.name" ;;
  *) echo "fake bw: unexpected $*" >&2; exit 99 ;;
esac
"""

GH = r"""#!/usr/bin/env bash
data="$(cat)"
printf '%s <%s>\n' "$*" "$data" >>"$LOGDIR/gh.log"
for k in ${FAKE_GH_FAIL_ON:-}; do case "$*" in *" $k "*) echo "gh: HTTP 403" >&2; exit 4 ;; esac; done
exit 0
"""

STORE = "{root}/ws/tools/sync-env-secrets/secrets"
AGENT = "{root}/ws/tools/sync-env-secrets/agent-keys"


def setup_factory(
    store=None, agent=None, vault=None, cache=None, gh=True, bw=True, extra=None
):
    """store/agent: {relpath: (content, mode)}; vault: {attachment: (name, {relpath: content})}."""

    def setup(root):
        os.makedirs(root + "/log")
        if bw:
            write_exec(root + "/bin/bw", BW)
        if gh:
            write_exec(root + "/bin/gh", GH)
        os.symlink(JQ, root + "/bin/jq")
        for base, files in ((STORE, store), (AGENT, agent)):
            if files is None:
                continue
            b = base.replace("{root}", root)
            os.makedirs(b, exist_ok=True)
            for rel, spec in files.items():
                if spec == "DIR":
                    os.makedirs(os.path.join(b, rel), exist_ok=True)
                elif isinstance(spec, tuple) and spec[0] == "LINK":
                    os.symlink(spec[1], os.path.join(b, rel))
                else:
                    content, mode = spec
                    write(os.path.join(b, rel), content, mode)
        if vault is not None:
            os.makedirs(root + "/vault")
            if vault:
                write(root + "/vault/item", "")
                write(root + "/vault/item.name", "x")
            for att, (name, files) in vault.items():
                write(root + "/vault/%s.name" % att, name + "\n")
                for rel, content in files.items():
                    write(root + "/vault/%s.d/%s" % (att, rel), content, 0o600)
        if cache is not None:
            content, mode = cache
            write(root + "/xdg/vitruvian-core/bw-session", content, mode)
        if extra:
            extra(root)

    return setup


ENVSTORE = {
    "dev/API_KEY": ("k3y", 0o600),
    "dev/JSON_BLOB": ('{"a": 1,\n "b": "two"}\n', 0o600),
    "dev/README.md": ("notes", 0o644),
    "dev/.hidden": ("x", 0o600),
    "dev/sub": "DIR",
    "dev/Z_LAST": ("z", 0o600),
}


# serde_json and jq word a parse error differently; that there was one, and
# where it was reported, is what is compared.
JQ_NORMALISE = [
    (rb"(?m)^jq: parse error: .*$", b"jq: parse error: <message>"),
    (rb"jq: error \(at <stdin>:[0-9]+\)", b"jq: error (at <stdin>:N)"),
]


def case(name, args, env=None, setup=None, **kw):
    e = {
        "LOGDIR": "{root}/log",
        "VAULT": "{root}/vault",
        "BUILD_WORKSPACE_DIRECTORY": "{root}/ws",
        "XDG_CACHE_HOME": "{root}/xdg",
        "BW_SESSION": None,
        "BW_PASSWORD": None,
    }
    e.update(env or {})
    return Case(
        name=name,
        args=args,
        env=e,
        setup=setup or setup_factory(),
        normalise=JQ_NORMALISE,
        **kw,
    )


GOOD = {"BW_SESSION": "good"}
NO_GH_BW = {}
ITEM = {"att-1": ("deploy-env-secrets.tar.gz", {"dev/API_KEY": "old"})}


def cases():
    global NO_GH_BW
    NO_GH_BW = {"PATH": "{root}/bin:" + path_without("gh", "bw")}
    yield case("no subcommand", [])
    yield case("unknown subcommand", ["bogus"])
    # apply
    yield case("apply: no environment", ["apply"])
    yield case("apply: missing store", ["apply", "dev"])
    yield case(
        "apply: syncs every file", ["apply", "dev"], setup=setup_factory(store=ENVSTORE)
    )
    yield case(
        "apply: custom repo",
        ["apply", "dev"],
        env={"REPO": "o/r"},
        setup=setup_factory(store=ENVSTORE),
    )
    yield case(
        "apply: symlinked file",
        ["apply", "dev"],
        setup=setup_factory(store={"dev/A": ("a", 0o600), "dev/L": ("LINK", "A")}),
    )
    yield case(
        "apply: empty store",
        ["apply", "dev"],
        setup=setup_factory(store={"dev/README.md": ("x", 0o644)}),
    )
    yield case(
        "apply: gh fails mid-way",
        ["apply", "dev"],
        env={"FAKE_GH_FAIL_ON": "JSON_BLOB"},
        setup=setup_factory(store=ENVSTORE),
    )
    yield case(
        "apply: gh missing",
        ["apply", "dev"],
        env=NO_GH_BW,
        setup=setup_factory(store=ENVSTORE, gh=False),
    )
    yield case(
        "apply: unreadable secret",
        ["apply", "dev"],
        setup=setup_factory(store={"dev/A": ("a", 0o000), "dev/B": ("b", 0o600)}),
    )
    yield case(
        "apply: extra args ignored",
        ["apply", "dev", "more"],
        setup=setup_factory(store=ENVSTORE),
    )
    # session selection (through unlock)
    yield case("unlock: exported session", ["unlock"], env=GOOD)
    yield case(
        "unlock: cached session", ["unlock"], setup=setup_factory(cache=("good", 0o600))
    )
    yield case(
        "unlock: stale export, good cache",
        ["unlock"],
        env={"BW_SESSION": "stale"},
        setup=setup_factory(cache=("good\n", 0o644)),
    )
    yield case(
        "unlock: empty export",
        ["unlock"],
        env={"BW_SESSION": ""},
        setup=setup_factory(cache=("good", 0o600)),
    )
    yield case(
        "unlock: stale everywhere, no tty",
        ["unlock"],
        env={"BW_SESSION": "stale"},
        setup=setup_factory(cache=("stale", 0o600)),
    )
    yield case("unlock: BW_PASSWORD", ["unlock"], env={"BW_PASSWORD": "pw"})
    yield case("unlock: wrong BW_PASSWORD", ["unlock"], env={"BW_PASSWORD": "nope"})
    yield case(
        "unlock: empty session from bw",
        ["unlock"],
        env={"BW_PASSWORD": "pw", "FAKE_UNLOCK_EMPTY": "1"},
    )
    yield case("unlock: not logged in", ["unlock"], env={"FAKE_UNAUTH": "1"})
    yield case(
        "unlock: status not JSON",
        ["unlock"],
        env={"BW_SESSION": "good", "FAKE_STATUS_RAW": "garbage", "BW_PASSWORD": "pw"},
    )
    yield case(
        "unlock: status fails but says unlocked",
        ["unlock"],
        env={"BW_SESSION": "good", "FAKE_STATUS_RC": "1", "BW_PASSWORD": "pw"},
    )
    yield case(
        "unlock: status two values",
        ["unlock"],
        env={
            "BW_SESSION": "good",
            "FAKE_STATUS_RAW": '{"status":"unlocked"} {"status":"x"}',
            "BW_PASSWORD": "pw",
        },
    )
    yield case(
        "unlock: status a string",
        ["unlock"],
        env={"FAKE_STATUS_RAW": '"unlocked"', "BW_PASSWORD": "pw"},
    )
    yield case(
        "unlock: bw missing", ["unlock"], env=NO_GH_BW, setup=setup_factory(bw=False)
    )
    yield case(
        "unlock: cache dir exists",
        ["unlock"],
        env=GOOD,
        setup=setup_factory(extra=lambda r: os.makedirs(r + "/xdg/vitruvian-core")),
    )
    yield case(
        "unlock: XDG unset uses HOME",
        ["unlock"],
        env={"BW_SESSION": "good", "XDG_CACHE_HOME": None},
    )
    # lock
    yield case(
        "lock: with a cache", ["lock"], setup=setup_factory(cache=("good", 0o600))
    )
    yield case("lock: nothing cached", ["lock"])
    yield case(
        "lock: no bw",
        ["lock"],
        env=NO_GH_BW,
        setup=setup_factory(bw=False, cache=("x", 0o600)),
    )
    # bw-push
    yield case(
        "bw-push: creates the item",
        ["bw-push"],
        env=GOOD,
        setup=setup_factory(store=ENVSTORE, vault={}),
    )
    yield case(
        "bw-push: custom item name",
        ["bw-push"],
        env={"BW_SESSION": "good", "BW_ITEM": "team/other"},
        setup=setup_factory(store=ENVSTORE, vault={}),
    )
    yield case(
        "bw-push: replaces the old attachment",
        ["bw-push"],
        env=GOOD,
        setup=setup_factory(store=ENVSTORE, vault=ITEM),
    )
    yield case(
        "bw-push: removes every duplicate, keeps others",
        ["bw-push"],
        env=GOOD,
        setup=setup_factory(
            store=ENVSTORE,
            vault={
                "att-1": ("deploy-env-secrets.tar.gz", {"a": "1"}),
                "att-2": ("other.txt", {"b": "2"}),
                "att-3": ("deploy-env-secrets.tar.gz", {"c": "3"}),
            },
        ),
    )
    yield case(
        "bw-push: delete fails",
        ["bw-push"],
        env={"BW_SESSION": "good", "FAKE_DELETE_FAIL": "1"},
        setup=setup_factory(store=ENVSTORE, vault=ITEM),
    )
    yield case(
        "bw-push: create item fails",
        ["bw-push"],
        env={"BW_SESSION": "good", "FAKE_CREATE_FAIL": "1"},
        setup=setup_factory(store=ENVSTORE, vault={}),
    )
    yield case(
        "bw-push: create item without id",
        ["bw-push"],
        env={"BW_SESSION": "good", "FAKE_CREATE_REPLY": "{}"},
        setup=setup_factory(store=ENVSTORE, vault={}),
    )
    yield case(
        "bw-push: attach fails",
        ["bw-push"],
        env={"BW_SESSION": "good", "FAKE_ATTACH_FAIL": "1"},
        setup=setup_factory(store=ENVSTORE, vault=ITEM),
    )
    yield case(
        "bw-push: sync fails",
        ["bw-push"],
        env={"BW_SESSION": "good", "FAKE_SYNC_FAIL": "1"},
        setup=setup_factory(store=ENVSTORE, vault=ITEM),
    )
    yield case("bw-push: no store", ["bw-push"], env=GOOD)
    yield case("bw-push: locked", ["bw-push"], setup=setup_factory(store=ENVSTORE))
    yield case(
        "bw-push: list is not JSON",
        ["bw-push"],
        env={"BW_SESSION": "good", "FAKE_LIST_RAW": "oops"},
        setup=setup_factory(store=ENVSTORE, vault={}),
    )
    yield case(
        "bw-push: list is an object",
        ["bw-push"],
        env={"BW_SESSION": "good", "FAKE_LIST_RAW": '{"id":"x"}'},
        setup=setup_factory(store=ENVSTORE, vault={}),
    )
    yield case(
        "bw-push: item with odd attachments",
        ["bw-push"],
        env={
            "BW_SESSION": "good",
            "FAKE_ITEM_RAW": '{"attachments":[{"fileName":"deploy-env-secrets.tar.gz"},{"fileName":"x","id":"9"}]}',
        },
        setup=setup_factory(store=ENVSTORE, vault=ITEM),
    )
    # bw-pull
    yield case(
        "bw-pull: restores the store",
        ["bw-pull"],
        env=GOOD,
        setup=setup_factory(vault=ITEM),
    )
    yield case(
        "bw-pull: over an existing store",
        ["bw-pull"],
        env=GOOD,
        setup=setup_factory(store=ENVSTORE, vault=ITEM),
    )
    yield case("bw-pull: no item", ["bw-pull"], env=GOOD, setup=setup_factory(vault={}))
    yield case(
        "bw-pull: no attachment",
        ["bw-pull"],
        env=GOOD,
        setup=setup_factory(vault={"att-1": ("other.txt", {"a": "1"})}),
    )
    yield case(
        "bw-pull: duplicate attachments take the first",
        ["bw-pull"],
        env=GOOD,
        setup=setup_factory(
            vault={
                "att-1": ("deploy-env-secrets.tar.gz", {"one": "1"}),
                "att-2": ("deploy-env-secrets.tar.gz", {"two": "2"}),
            }
        ),
    )
    yield case(
        "bw-pull: download fails",
        ["bw-pull"],
        env={"BW_SESSION": "good", "FAKE_GETATT_FAIL": "1"},
        setup=setup_factory(vault=ITEM),
    )
    yield case(
        "bw-pull: item not JSON",
        ["bw-pull"],
        env={"BW_SESSION": "good", "FAKE_ITEM_RAW": "nope"},
        setup=setup_factory(vault=ITEM),
    )
    yield case(
        "bw-pull: item a string",
        ["bw-pull"],
        env={"BW_SESSION": "good", "FAKE_ITEM_RAW": '"str"'},
        setup=setup_factory(vault=ITEM),
    )
    yield case(
        "bw-push: item stream, last value good",
        ["bw-push"],
        env={
            "BW_SESSION": "good",
            "FAKE_ITEM_RAW": '[1] {"attachments":[{"fileName":"deploy-env-secrets.tar.gz","id":"att-1"}]}',
        },
        setup=setup_factory(store=ENVSTORE, vault=ITEM),
    )
    yield case(
        "bw-push: list with two values",
        ["bw-push"],
        env={"BW_SESSION": "good", "FAKE_LIST_RAW": '[{"id":"a"}] [{"id":"b"}]'},
        setup=setup_factory(store=ENVSTORE, vault=ITEM),
    )
    yield case(
        "bw-push: create reply not JSON",
        ["bw-push"],
        env={"BW_SESSION": "good", "FAKE_CREATE_REPLY": "oops"},
        setup=setup_factory(store=ENVSTORE, vault={}),
    )
    yield case(
        "bw-pull: via BW_PASSWORD",
        ["bw-pull"],
        env={"BW_PASSWORD": "pw"},
        setup=setup_factory(vault=ITEM),
    )
    # agent keys
    yield case("agent-keys-push: no store", ["agent-keys-push"], env=GOOD)
    yield case(
        "agent-keys-push: no pem files",
        ["agent-keys-push"],
        env=GOOD,
        setup=setup_factory(agent={"notes.txt": ("x", 0o600)}),
    )
    yield case(
        "agent-keys-push: loose key refused",
        ["agent-keys-push"],
        env=GOOD,
        setup=setup_factory(agent={"a.pem": ("k", 0o600), "b.pem": ("k", 0o644)}),
    )
    yield case(
        "agent-keys-push: group-readable key refused",
        ["agent-keys-push"],
        env=GOOD,
        setup=setup_factory(agent={"a.pem": ("k", 0o640)}),
    )
    yield case(
        "agent-keys-push: broken symlink",
        ["agent-keys-push"],
        env=GOOD,
        setup=setup_factory(agent={"a.pem": ("LINK", "missing")}),
    )
    yield case(
        "agent-keys-push: pushes",
        ["agent-keys-push"],
        env=GOOD,
        setup=setup_factory(
            agent={
                "wren.pem": ("w", 0o600),
                "atlas.pem": ("a", 0o600),
                "x.txt": ("t", 0o644),
            },
            vault={},
        ),
    )
    yield case(
        "agent-keys-push: custom item",
        ["agent-keys-push"],
        env={"BW_SESSION": "good", "AGENT_KEY_BW_ITEM": "keys/other"},
        setup=setup_factory(agent={"wren.pem": ("w", 0o600)}, vault={}),
    )
    yield case(
        "agent-keys-pull: restores with tight modes",
        ["agent-keys-pull"],
        env=GOOD,
        setup=setup_factory(
            vault={"att-1": ("agent-app-keys.tar.gz", {"wren.pem": "w"})}
        ),
    )
    yield case(
        "agent-keys-pull: no attachment",
        ["agent-keys-pull"],
        env=GOOD,
        setup=setup_factory(vault=ITEM),
    )
    # set (only the parts that need no terminal)
    yield case("set: no arguments", ["set"])
    yield case("set: no name", ["set", "dev"])
    yield case("set: empty name", ["set", "dev", ""])
    yield case(
        "set: bw missing",
        ["set", "dev", "KEY"],
        env=NO_GH_BW,
        setup=setup_factory(bw=False),
    )


JQ = ""


def find_jq():
    p = need_env("JQ_BIN")
    cands = [p]
    if p.startswith("external/"):
        cands.insert(0, "../" + p[len("external/") :])
    for c in cands:
        if os.path.exists(c):
            return os.path.abspath(c)
    print("jq not found at %s" % cands, file=sys.stderr)
    sys.exit(2)


def interrupt_check(h, impl):
    """SIGTERM mid-download: the decrypted archive's directory must be gone
    afterwards and the exit status 143, as the script's EXIT trap makes it.
    Not a side-by-side comparison (when each notices the signal differs: bash
    at once, the port once the running child returns), so each is held to
    the property on its own."""
    root = os.path.join(h.base, "interrupt", impl)
    os.makedirs(root + "/bin")
    os.makedirs(root + "/home")
    os.makedirs(root + "/tmp")
    setup_factory(vault=ITEM)(root)
    env = {
        "PATH": root + "/bin:" + h.base_path,
        "HOME": root + "/home",
        "TMPDIR": root + "/tmp",
        "LOGDIR": root + "/log",
        "VAULT": root + "/vault",
        "BUILD_WORKSPACE_DIRECTORY": root + "/ws",
        "XDG_CACHE_HOME": root + "/xdg",
        "BW_SESSION": "good",
        "FAKE_GETATT_HOLD": "3",
    }
    cmd = [h.bash, h.script, "bw-pull"] if impl == "sh" else [h.binary, "bw-pull"]
    p = subprocess.Popen(
        cmd, env=env, cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    held = root + "/log/held"
    deadline = time.time() + 30
    while not os.path.exists(held) and time.time() < deadline:
        time.sleep(0.05)
    time.sleep(0.2)
    archive = open(held).read().strip() if os.path.exists(held) else ""
    p.send_signal(signal.SIGTERM)
    rc = p.wait(timeout=60)
    time.sleep(3.5)  # the fake bw, orphaned under bash, finishes its sleep
    problems = []
    if not archive:
        problems.append("the download never started")
    elif os.path.exists(os.path.dirname(archive)):
        problems.append(
            "the decrypted archive's directory was left behind: "
            + os.path.dirname(archive)
        )
    if rc not in (143, -15):
        problems.append("exit status %d, want 143" % rc)
    h.count += 1
    if problems:
        h.failures += 1
        print(
            "  FAIL  interrupt mid-download cleans up (%s): %s"
            % (impl, "; ".join(problems))
        )
    else:
        print("  ok    interrupt mid-download cleans up (%s, rc=%d)" % (impl, rc))


def main():
    global JQ
    JQ = find_jq()
    h = Harness(
        "sync-env-secrets parity",
        need_env("SYNC_ENV_SECRETS_SH"),
        need_env("SYNC_ENV_SECRETS_RS"),
    )
    for c in cases():
        h.check(c)
    for impl in ("sh", "rs"):
        interrupt_check(h, impl)
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
