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
"""The 13 tools/gitops shell tools against their Rust port, side by side.

Every case runs as `bash <script> ARGS` and as the Rust binary (gitops-cli,
invoked under the tool's name) in two identical sandboxes of fake kubectl,
kubeseal, bw, gh, curl, openssl, helm and sleep. Compared byte for byte:
exit code, stdout, stderr, every file left in the sandbox (the SealedSecrets
written, their modes), and the fakes' log of every call -- argv, the
environment that matters (KUBECONFIG, PWD, BW_SESSION, USER) and everything
fed on stdin (the secrets themselves).

    bazel test //tools/gitops:gitops_rs_parity_test

The scripts need jq (the hermetic one, JQ_BIN) and python3 (this test's own
interpreter); the port needs neither, except argocd-secret's YAML edit.
"""

import os
import shutil
import sys
import tempfile

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, path_without, write, write_exec  # noqa: E402

PY = os.path.realpath(sys.executable)
JQ = ""
WS = "{root}/ws"
SEALED = "ws/gitops/argocd/platform/sealed-secrets-manifests"

# ---------------------------------------------------------------------------
# fakes
# ---------------------------------------------------------------------------

# Every fake starts by logging its name and argv, one call per line, each
# argument in <>.
PRELUDE = r"""#!/usr/bin/env bash
L="${FAKE_LOG:?}"
LINE="$(printf '%s' "__NAME__"; for a in "$@"; do printf ' <%s>' "$a"; done)"
# One write per log line. A later stage of a pipeline logs only once its
# input is in (readin first), so the stages of one pipeline log in order.
logargs() { printf '%s\n' "$LINE" >>"$L"; }
readin() { IN="$(cat; echo x)"; IN="${IN%x}"; }
login() { printf '  stdin<%s>\n' "$IN" >>"$L"; }
"""

KUBECTL = r"""
logargs
printf '  env KUBECONFIG=%s PWD=%s USER=%s\n' "${KUBECONFIG-<unset>}" "$PWD" "${USER-<unset>}" >>"$L"
args="$*"
case "$args" in
  *"create secret generic"*)
    name=""; ns=""; prev=""; data=""
    for a in "$@"; do
      case "$prev" in generic) name="$a" ;; -n) ns="$a" ;; esac
      case "$a" in
        --from-file=*=/dev/stdin) k="${a#--from-file=}"; k="${k%%=*}"
          readin; login; v="$IN"; data="$data  $k: $(printf '%s' "$v" | base64 | tr -d '\n')"$'\n' ;;
        --from-file=*) k="${a#--from-file=}"; f="${k#*=}"; k="${k%%=*}"
          data="$data  $k: $(base64 <"$f" | tr -d '\n')"$'\n' ;;
        --from-literal=*) k="${a#--from-literal=}"; v="${k#*=}"; k="${k%%=*}"
          data="$data  $k: $(printf '%s' "$v" | base64 | tr -d '\n')"$'\n' ;;
      esac
      prev="$a"
    done
    [ "${FK_CREATE_RC:-0}" = 0 ] || { echo "error: failed to create secret" >&2; exit "$FK_CREATE_RC"; }
    printf 'apiVersion: v1\ndata:\n%skind: Secret\nmetadata:\n  name: %s\n  namespace: %s\n' "$data" "$name" "$ns" ;;
  *"get pods -l app=ntfy"* | *"get pods -l app.kubernetes.io/name=headscale"*)
    [ -n "${FK_NO_POD:-}" ] && { echo "error: array index out of bounds" >&2; exit 1; }
    printf '%s' "${FK_POD:-pod-0}" ;;
  *"get pods -l app.kubernetes.io/name=tempo"*)
    [ -n "${FK_TEMPO_PODS_RC:-}" ] && exit "$FK_TEMPO_PODS_RC"
    printf 'pod/tempo-0\npod/tempo-1\n' ;;
  *"ntfy user list"*)
    [ -n "${FK_USERS_STDOUT:-}" ] && printf '%b' "$FK_USERS_STDOUT"
    printf '%b' "${FK_USERS:-user github-actions (role: user, tier: none)\n}" >&2
    exit "${FK_EXEC_RC:-0}" ;;
  *" exec -i "*) readin; login; echo "exec ok"; exit "${FK_EXEC_RC:-0}" ;;
  *prometheus-server-0*)
    [ -n "${FK_PROM_FAIL:-}" ] && { echo "error: unable to upgrade connection" >&2; exit 1; }
    d='{"data":{"result":[{"value":[0,"1"]}]}}'; printf '%s\n' "${FK_PROM:-$d}" ;;
  *api/search*)
    d='{"traces":[{"traceID":"abc123"}]}'
    case "$args" in *tempo-1*) printf '%s\n' "${FK_SEARCH:-$d}" ;; *) echo '{"traces":[]}' ;; esac ;;
  *api/traces*) [ -n "${FK_TRACE_RC:-}" ] && exit "$FK_TRACE_RC"; d='{"batches":[]}'; printf '%s\n' "${FK_TRACE:-$d}" ;;
  *" exec "*) echo "exec ok: $args"; exit "${FK_EXEC_RC:-0}" ;;
  *"get secret argocd-initial-admin-secret"*)
    [ -n "${FK_ADMIN_PW_B64:-}" ] || { echo 'Error from server (NotFound)' >&2; exit 1; }
    printf '%s' "$FK_ADMIN_PW_B64" ;;
  *"get appproject"*) printf '%s' "${FK_ROLES-readonly backstage}"; exit "${FK_ROLES_RC:-0}" ;;
  *"get secret github-otel-webhook"*)
    [ -n "${FK_SECRET_FAIL:-}" ] && { echo "Error from server (Forbidden)" >&2; exit 1; }
    printf '%s' "${FK_WEBHOOK_B64-c2VjcmV0}" ;;
  *"get secret -l"*) [ -n "${FK_GET_RC:-}" ] && { echo "error: forbidden" >&2; exit "$FK_GET_RC"; }
    printf '%s\n' "${FK_KEYS_JSON:-}" ;;
  *"get secret argocd-secret"*) [ -n "${FK_GET_RC:-}" ] && { echo "error: forbidden" >&2; exit "$FK_GET_RC"; }
    printf '%s' "${FK_ARGOCD_YAML:-}" ;;
  *" apply "*) [ -n "${FK_APPLY_FILE_LOG:-}" ] && for a in "$@"; do [ -f "$a" ] && sed 's/^/  file| /' "$a" >>"$L"; done
    echo "applied"; exit "${FK_APPLY_RC:-0}" ;;
  *) echo "kubectl ok"; exit "${FK_RC:-0}" ;;
esac
"""

KUBESEAL = r"""
case "$*" in
  *--validate*) readin; logargs; printf '  validated %s bytes\n' "${#IN}" >>"$L"; exit "${FKS_VALIDATE_RC:-0}" ;;
esac
readin; logargs; login; in="$IN"
[ "${FKS_RC:-0}" = 0 ] || { echo "error: cannot fetch certificate" >&2; exit "$FKS_RC"; }
[ -n "${FKS_NOTHING:-}" ] && exit 0
pad=""; [ -z "${FKS_SHORT:-}" ] && pad="$(printf 'A%.0s' $(seq 1 220))"
printf '%s\n' "$in" | awk -v pad="$pad" '
  /^apiVersion:/ { print "apiVersion: bitnami.com/v1alpha1"; next }
  /^kind: Secret/ { print "kind: SealedSecret"; next }
  /^data:/ { print "spec:"; print "  encryptedData:"; d = 1; next }
  d && /^  [^ ]/ { i = index($0, ": "); printf "    %s: Ag%s%s\n", substr($0, 3, i - 3), substr($0, i + 2), pad; next }
  { d = 0; print }'
"""

BW = r"""
case "$1 ${2:-}" in "encode "* | "create item") readin ;; esac
logargs
case "$1 ${2:-}" in "encode "* | "create item") login ;; esac
printf '  env BW_SESSION=%s\n' "${BW_SESSION-<unset>}" >>"$L"
V="${FAKE_VAULT:?}"
item_json() {
  printf '{"id":"%s","name":"x","attachments":[' "${1}"; sep=""
  for n in "$V"/att-*.name; do
    [ -f "$n" ] || continue; a="$(basename "$n" .name)"
    printf '%s{"id":"%s","fileName":"%s"}' "$sep" "$a" "$(cat "$n")"; sep=","
  done
  printf ']}\n'
}
case "$1 ${2:-}" in
  "status "*) printf '{"status":"%s"}\n' "${FB_STATUS:-unlocked}"; exit "${FB_STATUS_RC:-0}" ;;
  "unlock "*) [ -n "${FB_UNLOCK_FAIL:-}" ] && { echo "Invalid master password." >&2; exit 1; }
    printf '%s' "${FB_UNLOCK_SESSION-sess-123}" ;;
  "sync "*) echo "Syncing complete." ;;
  "get item")
    if [ ! -f "$V/item" ]; then echo "Not found." >&2; exit 1; fi
    [ -n "${FB_ITEM_RAW:-}" ] && { printf '%s\n' "$FB_ITEM_RAW"; exit 0; }
    item_json "$(cat "$V/item")" ;;
  "encode ") printf 'ENC(%s)' "$(printf '%s' "$IN" | base64 | tr -d '\n')" ;;
  "create item") [ -n "${FB_CREATE_FAIL:-}" ] && { echo "create failed" >&2; exit 1; }
    echo item-new >"$V/item"; echo '{"id":"item-new"}' ;;
  "create attachment")
    [ -n "${FB_ATTACH_FAIL:-}" ] && { echo "attach failed" >&2; exit 1; }
    f="$4"; sed 's/^/  upload| /' "$f" >>"$L"
    [ -n "${FB_ATTACH_NOPERSIST:-}" ] && { echo '{"id":"lost"}'; exit 0; }
    n=$(( $(ls "$V"/att-*.name 2>/dev/null | wc -l) + 1 ))
    basename "$f" >"$V/att-$n.name"; cp "$f" "$V/att-$n.data"; echo "{\"id\":\"att-$n\"}" ;;
  "delete attachment") rm -f "$V/$3.name" "$V/$3.data" ;;
  "get attachment")
    for n in "$V"/att-*.name; do
      [ -f "$n" ] && [ "$(cat "$n")" = "$3" ] && { cp "${n%.name}.data" "$7"; exit 0; }
    done
    echo "Attachment not found." >&2; exit 1 ;;
  *) echo "fake bw: unexpected $*" >&2; exit 99 ;;
esac
"""

GH = r"""
logargs
case "$*" in
  "auth status"*) exit "${FG_AUTH_RC:-0}" ;;
  *"secret set"*) readin; login
    case "$*" in *dependabot*) [ -n "${FG_FAIL_DEPENDABOT:-}" ] && exit 1 ;; esac
    [ -n "${FG_FAIL:-}" ] && { echo "HTTP 403" >&2; exit 1; }
    exit 0 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 99 ;;
esac
"""

CURL = r"""
args="$*"
case "$args" in
  *"-d @-"* | *"--config -"*) readin; logargs; login ;;
  *) logargs ;;
esac
case "$args" in
  */api/v1/session*) d='{"token":"sess-tok"}'; printf '%s' "${FC_SESSION_REPLY-$d}"; exit "${FC_SESSION_RC:-0}" ;;
  */token*) [ -n "${FC_TOKEN_STDERR:-}" ] && echo "curl: (7) Failed to connect" >&2
    d='{"token":"minted-tok"}'; printf '%s' "${FC_TOKEN_REPLY-$d}"; exit "${FC_TOKEN_RC:-0}" ;;
  */v1/account*) exit "${FC_ACCOUNT_RC:-0}" ;;
  *X-Hub-Signature-256*)
    for a in "$@"; do case "$a" in @*) p="${a#@}" ;; "X-Hub-Signature-256: "*) s="${a#X-Hub-Signature-256: }" ;; esac; done
    sed 's/^/  payload| /' "$p" >>"$L"; echo >>"$L"
    want="sha256=$(__PY__ -c 'import hmac,hashlib,sys;print(hmac.new(b"secret",open(sys.argv[1],"rb").read(),hashlib.sha256).hexdigest())' "$p")"
    if [ "$s" = "$want" ]; then echo "  signature ok" >>"$L"; else echo "  signature BAD" >>"$L"; fi
    [ -n "${FC_SIGNED_RC:-}" ] && { printf 000; exit "$FC_SIGNED_RC"; }
    printf '%s' "${FC_SIGNED_CODE:-200}" ;;
  *) [ -n "${FC_UNSIGNED_RC:-}" ] && { printf 000; exit "$FC_UNSIGNED_RC"; }
    printf '%s' "${FC_UNSIGNED_CODE:-400}" ;;
esac
"""

OPENSSL = r"""
logargs
case "$*" in
  "rand -hex 32") [ -n "${FO_FAIL:-}" ] && exit 1; printf '%s\n' "${FO_HEX:-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}" ;;
  "rand -base64 "*) [ -n "${FO_FAIL:-}" ] && { echo "openssl: rand failed" >&2; exit 1; }
    printf '%b' "${FO_B64:-ab+cd/EF=gh1234567890IJklMN+opQRstUV/wxYZab12cd34ef56GH78ij90KLmnOPqrST+uvWXyz/0123456789ABCDEFGHIJ+KLMNOPQRSTUVWXYZabcdefghij/klmnopqrstuvwxyz==\n}" ;;
  "rsa "*) exit "${FO_RSA_RC:-0}" ;;
  *) echo "fake openssl: unexpected $*" >&2; exit 99 ;;
esac
"""

HELM = r"""
logargs
echo "helm ok"; exit "${FH_RC:-0}"
"""

SLEEP = r"""
logargs
exit 0
"""

# argocd-secret's strip_metadata, without PyYAML: the program arrives on
# stdin (logged, so both sides must send the same one); drop the volatile
# metadata lines from the file it names.
PY_STRIP = r"""
readin; logargs; printf '  program %s bytes\n' "${#IN}" >>"$L"
grep -v -e resourceVersion -e 'uid:' -e creationTimestamp "$2" >"$2.new"; mv "$2.new" "$2"
exit "${FP_RC:-0}"
"""


def fake(root, name, body):
    text = PRELUDE.replace("__NAME__", name) + body.replace("__PY__", PY)
    write_exec(root + "/bin/" + name, text)


def sandbox(
    tools=("kubectl", "kubeseal"),
    ws=True,
    sealed_dir=True,
    vault=None,
    key=None,
    extra=None,
):
    """A setup(root) for Case: the named fakes, jq and a real python3 on
    PATH, a workspace with the sealed-secrets directory, a fake vault
    ({name: data}), an ARC key (data, mode)."""
    bodies = {
        "kubectl": KUBECTL,
        "kubeseal": KUBESEAL,
        "bw": BW,
        "gh": GH,
        "curl": CURL,
        "openssl": OPENSSL,
        "helm": HELM,
        "sleep": SLEEP,
        "python3": PY_STRIP,
    }

    def setup(root):
        os.symlink(JQ, root + "/bin/jq")
        if "python3" not in tools:
            write_exec(root + "/bin/python3", '#!/bin/sh\nexec "%s" "$@"\n' % PY)
        for t in tools:
            fake(root, t, bodies[t])
        if ws:
            os.makedirs(root + "/ws")
            if sealed_dir:
                os.makedirs(root + "/" + SEALED)
        if vault is not None:
            os.makedirs(root + "/vault")
            if vault.get("item", True):
                write(root + "/vault/item", "item-1")
            for i, (name, data) in enumerate(vault.get("attachments", {}).items()):
                write(root + "/vault/att-%d.name" % (i + 1), name + "\n")
                write(root + "/vault/att-%d.data" % (i + 1), data)
        if key is not None:
            d = root + "/ws/tools/sync-env-secrets/agent-keys"
            os.makedirs(d)
            write(d + "/vitruvian-arc.pem", key[0], key[1])
        if extra:
            extra(root)

    return setup


def env(**kw):
    e = {
        "FAKE_LOG": "{root}/calls.log",
        "FAKE_VAULT": "{root}/vault",
        "BUILD_WORKSPACE_DIRECTORY": WS,
    }
    e.update(kw)
    return e


TMP_NAMES = [
    (
        rb"(?:<ROOT>)?(?:/[^\s/<>'\"]+)*/(sskeys|argocdsec|github-otel-webhook)\.[A-Za-z0-9.]+",
        rb"<TMP>/\1.XXXXXX",
    )
]


def without(*names):
    return "{root}/bin:" + path_without(*names)


# ---------------------------------------------------------------------------
# cases, per tool
# ---------------------------------------------------------------------------


def gitops_cmd():
    s = sandbox(tools=("kubectl", "kubeseal", "helm"))
    yield Case("no subcommand", [], env=env(), setup=s)
    yield Case("empty subcommand", [""], env=env(), setup=s)
    for sub in ("apply", "delete", "diff", "get", "patch"):
        yield Case(sub, [sub, "-f", "gitops/x.yaml"], env=env(), setup=s)
    yield Case(
        "apply fails: its status",
        ["apply", "-f", "x"],
        env=env(FK_APPLY_RC="3"),
        setup=s,
    )
    yield Case("get fails: its status", ["get", "x"], env=env(FK_RC="5"), setup=s)
    yield Case("status", ["status"], env=env(), setup=s)
    yield Case("status with args", ["status", "-l", "a=b"], env=env(), setup=s)
    yield Case(
        "helm", ["helm", "get", "values", "rel", "-n", "ns", "-a"], env=env(), setup=s
    )
    yield Case(
        "helm missing",
        ["helm", "list"],
        env=env(PATH=without("helm")),
        setup=sandbox(tools=("kubectl",)),
    )
    yield Case(
        "kubeseal (stdin passes through)",
        ["kubeseal", "--format", "yaml"],
        env=env(),
        stdin=b"apiVersion: v1\ndata:\n  k: dg==\nkind: Secret\n",
        setup=s,
    )
    yield Case(
        "kubeseal missing",
        ["kubeseal"],
        env=env(PATH=without("kubeseal")),
        setup=sandbox(tools=("kubectl",)),
    )
    yield Case(
        "kubectl missing",
        ["apply"],
        env=env(PATH=without("kubectl")),
        setup=sandbox(tools=()),
    )
    yield Case("unknown subcommand", ["bogus", "x"], env=env(), setup=s)
    yield Case(
        "KUBE_CONTEXT and KUBECONFIG from the caller",
        ["get", "pods"],
        env=env(KUBE_CONTEXT="lab-b", KUBECONFIG="/k/config"),
        setup=s,
    )
    yield Case(
        "empty KUBECONFIG gets the default",
        ["get", "pods"],
        env=env(KUBECONFIG=""),
        setup=s,
    )
    yield Case(
        "not under bazel run",
        ["apply"],
        env=env(BUILD_WORKSPACE_DIRECTORY=None),
        setup=s,
    )
    yield Case(
        "workspace missing",
        ["apply"],
        env=env(BUILD_WORKSPACE_DIRECTORY="{root}/nope"),
        setup=s,
    )


def seal_alert_ntfy():
    s = sandbox()
    yield Case(
        "password argument", ["hunter2-pw"], env=env(), setup=s
    )  # gitleaks:allow
    yield Case("password then --apply", ["pw-1", "--apply"], env=env(), setup=s)
    yield Case(
        "--apply first, last password wins", ["--apply", "a", "b"], env=env(), setup=s
    )
    yield Case("apply fails", ["pw", "--apply"], env=env(FK_APPLY_RC="4"), setup=s)
    yield Case("unknown flag", ["-x"], env=env(), setup=s)
    yield Case("a lone dash is a flag", ["-"], env=env(), setup=s)
    yield Case("prompted password", [], env=env(), stdin=b"  from stdin  \n", setup=s)
    yield Case(
        "prompt, no newline: read fails", [], env=env(), stdin=b"partial", setup=s
    )
    yield Case("prompt, no input", [], env=env(), stdin=b"", setup=s)
    yield Case("prompt, blank answer", [], env=env(), stdin=b"   \n", setup=s)
    yield Case(
        "kubeseal missing",
        ["pw"],
        env=env(PATH=without("kubeseal")),
        setup=sandbox(tools=("kubectl",)),
    )
    yield Case("kubeseal fails", ["pw"], env=env(FKS_RC="2"), setup=s)
    yield Case("kubectl create fails", ["pw"], env=env(FK_CREATE_RC="5"), setup=s)
    yield Case(
        "context and controller",
        ["pw"],
        env=env(
            KUBE_CONTEXT="lab-b",
            SEALED_SECRETS_NAMESPACE="ss",
            SEALED_SECRETS_CONTROLLER="ctl",
        ),
        setup=s,
    )
    yield Case(
        "no sealed-secrets directory",
        ["pw"],
        env=env(),
        setup=sandbox(sealed_dir=False),
    )
    yield Case(
        "not under bazel run", ["pw"], env=env(BUILD_WORKSPACE_DIRECTORY=None), setup=s
    )


def seal_argocd_backstage_token():
    tools = ("kubectl", "kubeseal", "curl")
    s = sandbox(tools=tools)
    tok = env(ARGOCD_AUTH_TOKEN="admin-tok")
    yield Case("caller's admin token", [], env=tok, setup=s)
    yield Case("--apply", ["--apply"], env=tok, setup=s)
    yield Case("--expires-in", ["--expires-in", "8760h"], env=tok, setup=s)
    yield Case("--expires-in needs a value", ["--expires-in"], env=tok, setup=s)
    yield Case("--expires-in empty", ["--expires-in", ""], env=tok, setup=s)
    yield Case("unknown argument", ["--nope"], env=tok, setup=s)
    yield Case(
        "admin password from the cluster",
        [],
        # base64 of: p@ss"w\oörd (quote, backslash, non-ASCII)
        env=env(FK_ADMIN_PW_B64="cEBzcyJ3XG/DtnJk"),  # gitleaks:allow
        setup=s,
    )
    yield Case("no admin secret", [], env=env(), setup=s)
    yield Case(
        "session reply without a token",
        [],
        env=env(FK_ADMIN_PW_B64="cHc=", FC_SESSION_REPLY='{"error":"bad"}'),
        setup=s,
    )
    yield Case(
        "session token null prints None",
        [],
        env=env(FK_ADMIN_PW_B64="cHc=", FC_SESSION_REPLY='{"token":null}'),
        setup=s,
    )
    yield Case(
        "role missing",
        [],
        env=env(ARGOCD_AUTH_TOKEN="t", FK_ROLES="readonly ci"),
        setup=s,
    )
    yield Case(
        "role check fails", [], env=env(ARGOCD_AUTH_TOKEN="t", FK_ROLES_RC="1"), setup=s
    )
    yield Case(
        "roles on lines",
        [],
        env=env(ARGOCD_AUTH_TOKEN="t", FK_ROLES="a\nbackstage"),
        setup=s,
    )
    yield Case(
        "mint refused",
        [],
        env=env(
            ARGOCD_AUTH_TOKEN="t",
            FC_TOKEN_REPLY='{"error":"permission denied: projects, update"}',
        ),
        setup=s,
    )
    yield Case(
        "mint error is cut to 200 characters",
        [],
        env=env(
            ARGOCD_AUTH_TOKEN="t",
            FC_TOKEN_REPLY='{"error":"%s","token":"x"}' % ("e" * 250),
        ),
        setup=s,
    )
    yield Case(
        "curl fails to connect, empty reply",
        [],
        env=env(
            ARGOCD_AUTH_TOKEN="t",
            FC_TOKEN_REPLY="{}",
            FC_TOKEN_STDERR="1",
            FC_TOKEN_RC="7",
        ),
        setup=s,
    )
    yield Case(
        "custom server URL",
        [],
        env=env(ARGOCD_AUTH_TOKEN="t", ARGOCD_SERVER_URL="https://argo.example"),
        setup=s,
    )
    yield Case(
        "kubeseal fails", [], env=env(ARGOCD_AUTH_TOKEN="t", FKS_RC="1"), setup=s
    )
    yield Case(
        "curl missing",
        [],
        env=env(ARGOCD_AUTH_TOKEN="t", PATH=without("curl")),
        setup=sandbox(tools=("kubectl", "kubeseal")),
    )


def seal_headplane_secret():
    tools = ("kubectl", "kubeseal", "openssl")
    s = sandbox(tools=tools)
    yield Case("generate and seal", [], env=env(), setup=s)
    yield Case("--apply", ["--apply"], env=env(), setup=s)
    yield Case("positional argument", ["x"], env=env(), setup=s)
    yield Case("unknown flag", ["--x"], env=env(), setup=s)
    yield Case("openssl output too short", [], env=env(FO_B64="ab+/cd==\n"), setup=s)
    yield Case("openssl fails", [], env=env(FO_FAIL="1"), setup=s)
    yield Case(
        "openssl missing",
        [],
        env=env(PATH=without("openssl")),
        setup=sandbox(tools=("kubectl", "kubeseal")),
    )
    yield Case("kubeseal fails", [], env=env(FKS_RC="3"), setup=s)


def seal_zitadel():
    tools = ("kubectl", "kubeseal", "openssl")
    s = sandbox(tools=tools)
    yield Case("generate, seal and validate", [], env=env(), setup=s)
    yield Case("takes no arguments", ["--apply"], env=env(), setup=s)
    yield Case("sealed value too short", [], env=env(FKS_SHORT="1"), setup=s)
    yield Case("kubeseal wrote nothing", [], env=env(FKS_NOTHING="1"), setup=s)
    yield Case("validate fails", [], env=env(FKS_VALIDATE_RC="1"), setup=s)
    yield Case("openssl output too short", [], env=env(FO_B64="abc\n"), setup=s)
    yield Case("kubeseal fails", [], env=env(FKS_RC="2"), setup=s)


KEYS_JSON = (
    '{"apiVersion":"v1","items":[{"apiVersion":"v1","data":{"tls.crt":"Y3J0","tls.key":"a2V5"},'  # gitleaks:allow
    '"kind":"Secret","metadata":{"annotations":{"keep":"me","kubectl.kubernetes.io/last-applied-configuration":"{}"},'
    '"creationTimestamp":"2026-01-01T00:00:00Z","generation":1,"labels":{"sealedsecrets.bitnami.com/sealed-secrets-key":"active"},'
    '"managedFields":[{"manager":"x"}],"name":"sealed-secrets-key1","namespace":"sealed-secrets","resourceVersion":"42","uid":"u-1"},'
    '"type":"kubernetes.io/tls"},{"kind":"ConfigMap","metadata":{"name":"other"}}],"kind":"List","metadata":{"resourceVersion":""}}'
)
KEYS_FILE = '{"items":[{"kind":"Secret","metadata":{"name":"k1"}},{"kind":"Secret","metadata":{"name":"k2"}}]}\n'


def sealed_secrets_keys():
    tools = ("kubectl", "bw")
    with_item = sandbox(
        tools=tools, vault={"attachments": {"sealed-secrets-keys.json": KEYS_FILE}}
    )
    old_att = sandbox(
        tools=tools,
        vault={"attachments": {"sealed-secrets-keys.json": "old", "other.txt": "x"}},
    )
    empty = sandbox(tools=tools, vault={"item": False})
    e = env(FK_KEYS_JSON=KEYS_JSON)
    yield Case("no subcommand", [], env=e, setup=with_item)
    yield Case(
        "backup: replaces the old attachment",
        ["backup"],
        env=e,
        setup=old_att,
        normalise=TMP_NAMES,
    )
    yield Case(
        "backup: creates the item", ["backup"], env=e, setup=empty, normalise=TMP_NAMES
    )
    yield Case(
        "backup: item create fails",
        ["backup"],
        env=env(FK_KEYS_JSON=KEYS_JSON, FB_CREATE_FAIL="1"),
        setup=empty,
        normalise=TMP_NAMES,
    )
    yield Case(
        "backup: no keys in the cluster",
        ["backup"],
        env=env(FK_KEYS_JSON='{"items":[],"kind":"List"}'),
        setup=old_att,
        normalise=TMP_NAMES,
    )
    yield Case(
        "backup: kubectl fails",
        ["backup"],
        env=env(FK_GET_RC="1"),
        setup=old_att,
        normalise=TMP_NAMES,
    )
    yield Case(
        "backup: upload fails",
        ["backup"],
        env=env(FK_KEYS_JSON=KEYS_JSON, FB_ATTACH_FAIL="1"),
        setup=old_att,
        normalise=TMP_NAMES,
    )
    yield Case(
        "backup: attachment does not persist",
        ["backup"],
        env=env(
            FK_KEYS_JSON=KEYS_JSON,  # gitleaks:allow
            FB_ATTACH_NOPERSIST="1",  # gitleaks:allow
        ),
        setup=empty,
        normalise=TMP_NAMES,
    )
    yield Case("restore", ["restore"], env=e, setup=with_item, normalise=TMP_NAMES)
    yield Case("restore: no item", ["restore"], env=e, setup=empty, normalise=TMP_NAMES)
    yield Case(
        "restore: no attachment",
        ["restore"],
        env=e,
        setup=sandbox(tools=tools, vault={"attachments": {}}),
        normalise=TMP_NAMES,
    )
    yield Case(
        "restore: empty attachment",
        ["restore"],
        env=e,
        setup=sandbox(
            tools=tools, vault={"attachments": {"sealed-secrets-keys.json": ""}}
        ),
        normalise=TMP_NAMES,
    )
    yield Case(
        "restore: attachment is not JSON",
        ["restore"],
        env=e,
        setup=sandbox(
            tools=tools, vault={"attachments": {"sealed-secrets-keys.json": "not json"}}
        ),
        normalise=TMP_NAMES,
    )
    yield Case(
        "restore: apply fails",
        ["restore"],
        env=env(FK_APPLY_RC="1"),
        setup=with_item,
        normalise=TMP_NAMES,
    )
    yield Case("verify", ["verify"], env=e, setup=with_item, normalise=TMP_NAMES)
    yield Case("verify: no item", ["verify"], env=e, setup=empty, normalise=TMP_NAMES)
    yield Case(
        "verify: no Secret in it",
        ["verify"],
        env=e,
        setup=sandbox(
            tools=tools,
            vault={"attachments": {"sealed-secrets-keys.json": '{"items":[]}'}},
        ),
        normalise=TMP_NAMES,
    )
    yield Case(
        "unknown subcommand", ["bogus"], env=e, setup=with_item, normalise=TMP_NAMES
    )
    yield Case(
        "not logged in",
        ["verify"],
        env=env(FB_STATUS="unauthenticated"),
        setup=with_item,
    )
    yield Case(
        "locked, no TTY", ["verify"], env=env(FB_STATUS="locked"), setup=with_item
    )
    yield Case(
        "locked, BW_PASSWORD unlocks",
        ["verify"],
        env=env(FB_STATUS="locked", BW_PASSWORD="pw"),
        setup=with_item,
        normalise=TMP_NAMES,
    )
    yield Case(
        "locked, unlock fails",
        ["verify"],
        env=env(FB_STATUS="locked", BW_PASSWORD="pw", FB_UNLOCK_FAIL="1"),
        setup=with_item,
    )
    yield Case(
        "locked, unlock returns nothing",
        ["verify"],
        env=env(FB_STATUS="locked", BW_PASSWORD="pw", FB_UNLOCK_SESSION=""),
        setup=with_item,
    )
    yield Case(
        "bw status fails: unknown",
        ["verify"],
        env=env(FB_STATUS_RC="1"),
        setup=with_item,
    )
    yield Case(
        "bw missing",
        ["verify"],
        env=env(PATH=without("bw")),
        setup=sandbox(tools=("kubectl",)),
    )
    yield Case(
        "namespace and item overrides",
        ["restore"],
        env=env(SS_NAMESPACE="ss", SS_CONTROLLER="ctl", SS_BW_ITEM="my item"),
        setup=with_item,
        normalise=TMP_NAMES,
    )


ARGOCD_YAML = """apiVersion: v1
data:
  accounts.mcp.tokens: W10=
  server.secretkey: c2s=
kind: Secret
metadata:
  creationTimestamp: "2026-01-01T00:00:00Z"
  name: argocd-secret
  namespace: argocd
  resourceVersion: "7"
  uid: u-2
type: Opaque
"""


def argocd_secret():
    tools = ("kubectl", "bw", "python3")
    good = ARGOCD_YAML
    with_item = sandbox(
        tools=tools, vault={"attachments": {"argocd-secret.yaml": good}}
    )
    empty = sandbox(tools=tools, vault={"item": False})
    e = env(FK_ARGOCD_YAML=good)
    yield Case("no subcommand", [], env=e, setup=with_item)
    yield Case("backup", ["backup"], env=e, setup=with_item, normalise=TMP_NAMES)
    yield Case(
        "backup: no item stops silently (no || true here)",
        ["backup"],
        env=e,
        setup=empty,
        normalise=TMP_NAMES,
    )
    yield Case(
        "backup: no server.secretkey",
        ["backup"],
        env=env(FK_ARGOCD_YAML="kind: Secret\ndata: {}\n"),
        setup=with_item,
        normalise=TMP_NAMES,
    )
    yield Case(
        "backup: not a Secret",
        ["backup"],
        env=env(FK_ARGOCD_YAML="kind: ConfigMap\n"),
        setup=with_item,
        normalise=TMP_NAMES,
    )
    yield Case(
        "backup: kubectl fails",
        ["backup"],
        env=env(FK_GET_RC="1"),
        setup=with_item,
        normalise=TMP_NAMES,
    )
    yield Case(
        "backup: strip fails",
        ["backup"],
        env=env(FK_ARGOCD_YAML=good, FP_RC="1"),
        setup=with_item,
        normalise=TMP_NAMES,
    )
    yield Case(
        "backup: upload fails",
        ["backup"],
        env=env(FK_ARGOCD_YAML=good, FB_ATTACH_FAIL="1"),
        setup=with_item,
        normalise=TMP_NAMES,
    )
    yield Case("restore", ["restore"], env=e, setup=with_item, normalise=TMP_NAMES)
    yield Case("restore: no item", ["restore"], env=e, setup=empty, normalise=TMP_NAMES)
    yield Case(
        "restore: no attachment",
        ["restore"],
        env=e,
        setup=sandbox(tools=tools, vault={"attachments": {}}),
        normalise=TMP_NAMES,
    )
    yield Case(
        "restore: invalid attachment",
        ["restore"],
        env=e,
        setup=sandbox(
            tools=tools, vault={"attachments": {"argocd-secret.yaml": "x: y\n"}}
        ),
        normalise=TMP_NAMES,
    )
    yield Case("verify", ["verify"], env=e, setup=with_item, normalise=TMP_NAMES)
    yield Case(
        "verify: missing the mcp tokens",
        ["verify"],
        env=e,
        setup=sandbox(
            tools=tools,
            vault={"attachments": {"argocd-secret.yaml": "server.secretkey: x\n"}},
        ),
        normalise=TMP_NAMES,
    )
    yield Case(
        "verify: no attachment",
        ["verify"],
        env=e,
        setup=sandbox(tools=tools, vault={"attachments": {}}),
        normalise=TMP_NAMES,
    )
    yield Case(
        "unknown subcommand", ["bogus"], env=e, setup=with_item, normalise=TMP_NAMES
    )
    yield Case(
        "not logged in",
        ["verify"],
        env=env(FB_STATUS="unauthenticated"),
        setup=with_item,
    )
    yield Case(
        "locked, no TTY", ["verify"], env=env(FB_STATUS="locked"), setup=with_item
    )
    yield Case(
        "locked, BW_PASSWORD unlocks",
        ["verify"],
        env=env(FB_STATUS="locked", BW_PASSWORD="pw"),
        setup=with_item,
        normalise=TMP_NAMES,
    )


def ntfy_bootstrap_users():
    tools = ("kubectl", "openssl")
    s = sandbox(tools=tools)
    yield Case("creates both users", ["vitruvian-alerts"], env=env(), setup=s)
    yield Case(
        "existing users are skipped",
        ["alerts"],
        env=env(
            FK_USERS_STDOUT="user alertmanager (role: user)\\nuser james (role: user)\\n"
        ),
        setup=s,
    )
    yield Case(
        "one user exists",
        ["alerts"],
        env=env(FK_USERS_STDOUT="user james (role: user)\\n"),
        setup=s,
    )
    yield Case(
        "a longer name is not a match",
        ["alerts"],
        env=env(FK_USERS_STDOUT="user jamesb (role: user)\\n"),
        setup=s,
    )
    yield Case("topic prompted", [], env=env(), stdin=b"from-stdin\n", setup=s)
    yield Case("topic prompt, no input", [], env=env(), stdin=b"", setup=s)
    yield Case("invalid topic", ["bad topic!"], env=env(), setup=s)
    yield Case("no pod", ["alerts"], env=env(FK_NO_POD="1"), setup=s)
    yield Case("exec fails: carries on", ["alerts"], env=env(FK_EXEC_RC="1"), setup=s)
    yield Case("openssl fails: carries on", ["alerts"], env=env(FO_FAIL="1"), setup=s)
    yield Case(
        "openssl missing",
        ["alerts"],
        env=env(PATH=without("openssl")),
        setup=sandbox(tools=("kubectl",)),
    )


def ntfy_manage_users():
    tools = ("kubectl", "openssl", "gh", "curl")
    s = sandbox(tools=tools)
    yield Case("no subcommand", [], env=env(), setup=s)
    yield Case("list", ["list"], env=env(), setup=s)
    yield Case("list fails", ["list"], env=env(FK_EXEC_RC="2"), setup=s)
    yield Case("add", ["add", "alice"], env=env(), setup=s)
    yield Case("add admin", ["add", "alice", "admin"], env=env(), setup=s)
    yield Case(
        "add, NTFY_PASSWORD given",
        ["add", "bob"],
        env=env(NTFY_PASSWORD="given-pw"),
        setup=s,
    )  # gitleaks:allow
    yield Case("add, bad role", ["add", "bob", "root"], env=env(), setup=s)
    yield Case("add, no user", ["add"], env=env(), setup=s)
    yield Case("add, exec fails", ["add", "bob"], env=env(FK_EXEC_RC="1"), setup=s)
    yield Case("add, openssl fails", ["add", "bob"], env=env(FO_FAIL="1"), setup=s)
    yield Case(
        "add, USER is exported", ["add", "carol"], env=env(USER="tester"), setup=s
    )
    yield Case("del", ["del", "alice"], env=env(), setup=s)
    yield Case("del, no user", ["del"], env=env(), setup=s)
    yield Case("change-pass", ["change-pass", "alice"], env=env(), setup=s)
    yield Case(
        "change-pass --gh-secret",
        ["change-pass", "github-actions", "--gh-secret", "NTFY_PW"],
        env=env(),
        setup=s,
    )
    yield Case(
        "change-pass --gh-secret, other repo and server",
        ["change-pass", "github-actions", "--gh-secret", "NTFY_PW"],
        env=env(GH_REPO="me/repo", NTFY_URL="https://ntfy.example"),
        setup=s,
    )
    yield Case(
        "change-pass --gh-secret, no such user",
        ["change-pass", "nobody", "--gh-secret", "NTFY_PW"],
        env=env(),
        setup=s,
    )
    yield Case(
        "change-pass --gh-secret, no name",
        ["change-pass", "github-actions", "--gh-secret"],
        env=env(),
        setup=s,
    )
    yield Case(
        "change-pass --gh-secret, gh signed out",
        ["change-pass", "github-actions", "--gh-secret", "N"],
        env=env(FG_AUTH_RC="1"),
        setup=s,
    )
    yield Case(
        "change-pass --gh-secret, secret store fails",
        ["change-pass", "github-actions", "--gh-secret", "N"],
        env=env(FG_FAIL="1"),
        setup=s,
    )
    yield Case(
        "change-pass --gh-secret, server rejects",
        ["change-pass", "github-actions", "--gh-secret", "N"],
        env=env(FC_ACCOUNT_RC="22"),
        setup=s,
    )
    yield Case(
        "change-pass --gh-secret, gh missing",
        ["change-pass", "github-actions", "--gh-secret", "N"],
        env=env(PATH=without("gh")),
        setup=sandbox(tools=("kubectl", "openssl", "curl")),
    )
    yield Case("change-role", ["change-role", "alice", "admin"], env=env(), setup=s)
    yield Case(
        "change-role, bad role", ["change-role", "alice", "x"], env=env(), setup=s
    )
    yield Case("change-role, no role", ["change-role", "alice"], env=env(), setup=s)
    yield Case("access", ["access", "alice", "alerts", "read-only"], env=env(), setup=s)
    yield Case(
        "access, no permission", ["access", "alice", "alerts"], env=env(), setup=s
    )
    yield Case("unknown subcommand", ["bogus"], env=env(), setup=s)
    yield Case("no pod", ["list"], env=env(FK_NO_POD="1"), setup=s)
    yield Case(
        "kubectl missing",
        ["list"],
        env=env(PATH=without("kubectl")),
        setup=sandbox(tools=()),
    )


def headscale_ops():
    s = sandbox(tools=("kubectl",))
    yield Case("no subcommand", [], env=env(), setup=s)
    yield Case("raw", ["raw", "nodes", "list", "-o", "json"], env=env(), setup=s)
    for sub in (
        "apikey-create",
        "apikey-list",
        "apikey-expire",
        "user-list",
        "node-list",
        "node-register",
        "preauthkey-create",
        "preauthkey-list",
    ):
        yield Case(sub, [sub, "--flag", "v"], env=env(), setup=s)
    yield Case(
        "user-create",
        ["user-create", "alice", "ignored"],
        env=env(USER="tester"),
        setup=s,
    )
    yield Case("user-create, no name", ["user-create"], env=env(), setup=s)
    yield Case(
        "user-destroy (name passed twice)",
        ["user-destroy", "alice", "--force"],
        env=env(),
        setup=s,
    )
    yield Case("node-delete", ["node-delete", "7"], env=env(), setup=s)
    yield Case("node-delete, no id", ["node-delete"], env=env(), setup=s)
    yield Case(
        "exec fails: its status", ["node-list"], env=env(FK_EXEC_RC="3"), setup=s
    )
    yield Case("unknown subcommand", ["bogus"], env=env(), setup=s)
    yield Case("no pod", ["node-list"], env=env(FK_NO_POD="1"), setup=s)


def rotate_otel():
    tools = ("kubectl", "kubeseal", "gh", "openssl")
    s = sandbox(tools=tools)
    n = TMP_NAMES
    yield Case("rotate", [], env=env(), setup=s, normalise=n)
    yield Case(
        "other repo and context",
        [],
        env=env(GH_REPO="me/r", KUBE_CONTEXT="lab-b"),
        setup=s,
        normalise=n,
    )
    yield Case("kubeseal fails", [], env=env(FKS_RC="1"), setup=s, normalise=n)
    yield Case("gh fails", [], env=env(FG_FAIL="1"), setup=s, normalise=n)
    yield Case(
        "dependabot store fails",
        [],
        env=env(FG_FAIL_DEPENDABOT="1"),
        setup=s,
        normalise=n,
    )
    yield Case("gh signed out", [], env=env(FG_AUTH_RC="1"), setup=s, normalise=n)
    yield Case("openssl fails", [], env=env(FO_FAIL="1"), setup=s, normalise=n)
    yield Case("short secret", [], env=env(FO_HEX="abc"), setup=s, normalise=n)
    yield Case(
        "gh missing",
        [],
        env=env(PATH=without("gh")),
        setup=sandbox(tools=("kubectl", "kubeseal", "openssl")),
        normalise=n,
    )


SMOKE_NORM = [
    # The run id is the clock; so are the payload's times and its signature
    # (checked by the fake curl itself: "signature ok").
    (rb"(?:(?<=%20)|(?<=%3D)|(?<![0-9]))1[0-9]{9}(?![0-9])", b"<EPOCH>"),
    (rb"sha256=[0-9a-f]{64}", b"sha256=<SIG>"),
    # The metric wait is by the clock (SMOKE_METRIC_WAIT_S): how many polls
    # fit in it varies, so a run of identical poll+sleep rounds counts once.
    (
        rb"(kubectl <-n> <monitoring>[^\n]*\n  env[^\n]*\nsleep <5>\n)(?:kubectl <-n> <monitoring>[^\n]*\n  env[^\n]*\nsleep <5>\n)+",
        rb"\1",
    ),
    (rb"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", b"<TIME>"),
    (rb"after [0-9]+s", b"after <N>s"),
    (rb"start%3D[0-9]+|start=[0-9]+", b"start=<T>"),
    (rb"end=[0-9]+", b"end=<T>"),
    # bash 3.2 keeps a continued line's indentation in $BASH_COMMAND.
    (rb"  +", b" "),
]


def cicd_smoke():
    tools = ("kubectl", "curl", "sleep")
    s = sandbox(tools=tools, ws=False)
    e = lambda **kw: env(SMOKE_METRIC_WAIT_S="2", KUBECONFIG="/dev/null", **kw)  # noqa: E731
    norm = SMOKE_NORM
    yield Case("healthy run", [], env=e(), setup=s, normalise=norm)
    yield Case(
        "metric never arrives",
        [],
        env=e(FK_PROM='{"data":{"result":[]}}'),
        setup=s,
        normalise=norm,
    )
    yield Case(
        "prometheus query fails", [], env=e(FK_PROM_FAIL="1"), setup=s, normalise=norm
    )
    yield Case(
        "secret read fails", [], env=e(FK_SECRET_FAIL="1"), setup=s, normalise=norm
    )
    yield Case("secret empty", [], env=e(FK_WEBHOOK_B64=""), setup=s, normalise=norm)
    yield Case(
        "unsigned accepted", [], env=e(FC_UNSIGNED_CODE="200"), setup=s, normalise=norm
    )
    yield Case(
        "unsigned curl fails", [], env=e(FC_UNSIGNED_RC="7"), setup=s, normalise=norm
    )
    yield Case(
        "signed rejected", [], env=e(FC_SIGNED_CODE="401"), setup=s, normalise=norm
    )
    yield Case(
        "signed curl fails", [], env=e(FC_SIGNED_RC="6"), setup=s, normalise=norm
    )
    yield Case(
        "tempo pods fail", [], env=e(FK_TEMPO_PODS_RC="3"), setup=s, normalise=norm
    )
    yield Case(
        "no trace", [], env=e(FK_SEARCH='{"traces":[]}'), setup=s, normalise=norm
    )
    yield Case("trace fetch fails", [], env=e(FK_TRACE_RC="4"), setup=s, normalise=norm)
    yield Case(
        "committer email leaks",
        [],
        env=e(FK_TRACE='{"attr":"smoke@example.invalid"}'),
        setup=s,
        normalise=norm,
    )
    yield Case("library mode", [], env=e(SMOKE_LIB_ONLY="1"), setup=s, normalise=norm)
    yield Case(
        "curl missing",
        [],
        env=e(PATH=without("curl")),
        setup=sandbox(tools=("kubectl", "sleep"), ws=False),
        normalise=norm,
    )


def seal_arc_github_app():
    tools = ("kubectl", "kubeseal", "openssl")
    pem = "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n"  # gitleaks:allow
    good = sandbox(tools=tools, key=(pem, 0o600))
    yield Case("seal", [], env=env(), setup=good)
    yield Case("--apply", ["--apply"], env=env(), setup=good)
    yield Case(
        "ids from the environment",
        [],
        env=env(ARC_APP_ID="1", ARC_INSTALLATION_ID="2"),
        setup=good,
    )
    yield Case("unknown argument", ["--nonsense"], env=env(), setup=good)
    yield Case("no key", [], env=env(), setup=sandbox(tools=tools))
    yield Case(
        "key not mode 600", [], env=env(), setup=sandbox(tools=tools, key=(pem, 0o644))
    )
    yield Case("not an RSA key", [], env=env(FO_RSA_RC="1"), setup=good)
    yield Case("kubeseal wrote no key", [], env=env(FKS_NOTHING="1"), setup=good)
    yield Case("kubeseal fails", [], env=env(FKS_RC="1"), setup=good)
    yield Case(
        "key path override",
        [],
        env=env(ARC_APP_KEY="tools/sync-env-secrets/agent-keys/vitruvian-arc.pem"),
        setup=good,
    )


TOOLS = [
    ("gitops-cmd", "gitops-cmd.sh", gitops_cmd),
    ("seal-alert-ntfy", "seal_alert_ntfy.sh", seal_alert_ntfy),
    (
        "seal-argocd-backstage-token",
        "seal_argocd_backstage_token.sh",
        seal_argocd_backstage_token,
    ),
    ("seal-headplane-secret", "seal_headplane_secret.sh", seal_headplane_secret),
    (
        "seal-zitadel-login-cookie-secret",
        "seal_zitadel_login_cookie_secret.sh",
        seal_zitadel,
    ),
    ("sealed-secrets-keys", "sealed_secrets_keys.sh", sealed_secrets_keys),
    ("argocd-secret", "argocd-secret.sh", argocd_secret),
    ("ntfy-bootstrap-users", "ntfy_bootstrap_users.sh", ntfy_bootstrap_users),
    ("ntfy-manage-users", "ntfy_manage_users.sh", ntfy_manage_users),
    ("headscale-ops", "headscale_ops.sh", headscale_ops),
    (
        "rotate-github-otel-webhook-secret",
        "rotate_github_otel_webhook_secret.sh",
        rotate_otel,
    ),
    ("cicd-telemetry-smoke", "cicd_telemetry_smoke.sh", cicd_smoke),
    ("seal-arc-github-app", "seal_arc_github_app.sh", seal_arc_github_app),
]


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


def main():
    global JQ
    JQ = find_jq()
    cli = os.path.abspath(need_env("GITOPS_CLI"))
    here = os.path.dirname(os.path.abspath(__file__))
    links = tempfile.mkdtemp(prefix="gitops-cli.", dir=os.environ.get("TEST_TMPDIR"))
    only = os.environ.get("GITOPS_PARITY_ONLY", "")
    failures = 0
    total = 0
    for name, script, cases in TOOLS:
        if only and only != name:
            continue
        # The binary runs the tool it is named after.
        link = os.path.join(links, name)
        os.symlink(cli, link)
        script_path = os.path.join(here, script)
        if not os.path.exists(script_path):
            script_path = os.path.join("tools", "gitops", script)
        print("== %s (%s)" % (name, script))
        h = Harness("%s parity" % name, script_path, link)
        for c in cases():
            h.check(c)
        failures += h.failures
        total += h.count
        h.finish()
    shutil.rmtree(links, ignore_errors=True)
    print()
    if failures:
        print("gitops parity: %d of %d case(s) differ" % (failures, total))
        return 1
    print(
        "gitops parity: all %d case(s) identical across %d tools" % (total, len(TOOLS))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
