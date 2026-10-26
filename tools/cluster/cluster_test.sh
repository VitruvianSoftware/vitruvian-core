#!/usr/bin/env bash
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

# usage: cluster_test.sh <cluster_cmd.sh | the Rust binary>
#
# Holds either implementation to one contract with a stand-in kubectl that
# records its arguments, KUBECONFIG and working directory, and answers the
# diagnostics' queries with canned tables. No cluster is touched.
set -euo pipefail

PROG="$1"
case "$PROG" in /*) ;; *) PROG="$PWD/$PROG" ;; esac
run() {
	case "$PROG" in
	*.sh) bash "$PROG" "$@" ;;
	*) "$PROG" "$@" ;;
	esac
}

ok() { echo "ok: $*"; }
fail() {
	echo "FAIL: $*" >&2
	exit 1
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws" "$T/home"
cat >"$T/bin/kubectl" <<'STUB'
#!/bin/sh
echo "kubectl $* | KUBECONFIG=$KUBECONFIG | cwd=$(pwd)" >>"$LOG"
case "$*" in
*"get pods -A"*) printf 'nuc9\nnuc8\nnuc9\nnuc7\nnuc9\nnuc8\n' ;;
*"get pv"*) printf 'PV CLAIM NS PINNED_NODE\npv-1 data-0 minio nuc9\npv-2 cache other nuc8\npv-3 data-1 minio nuc7\n' ;;
*"get pods -o name"*) printf 'pod/minio-0\npod/minio-1\n' ;;
*" exec "*) exit "${EXEC_RC:-0}" ;;
esac
exit 0
STUB
chmod +x "$T/bin/kubectl"
export LOG="$T/log" PATH="$T/bin:$PATH" HOME="$T/home" BUILD_WORKSPACE_DIRECTORY="$T/ws"
unset KUBECONFIG KUBE_CONTEXT MINIO_NS

: >"$LOG"
run drain nuc9 --timeout=5m >/dev/null
[[ "$(cat "$LOG")" == "kubectl --context default drain --ignore-daemonsets --delete-emptydir-data nuc9 --timeout=5m | KUBECONFIG=$T/home/.kube/cluster.yaml | cwd=$T/ws" ]] ||
	fail "drain: $(cat "$LOG")"
ok "drain: safe defaults, default context and kubeconfig, run from the workspace"

: >"$LOG"
KUBE_CONTEXT=lab KUBECONFIG=/k.yaml run label-node nuc9i5 a=b --overwrite >/dev/null
[[ "$(cat "$LOG")" == "kubectl --context lab label node nuc9i5 a=b --overwrite | KUBECONFIG=/k.yaml | cwd=$T/ws" ]] ||
	fail "label-node: $(cat "$LOG")"
ok "label-node: context and kubeconfig come from the environment"

out="$(run balance)"
[[ "$(awk '{print $1, $2}' <<<"$out")" == $'3 nuc9\n2 nuc8\n1 nuc7' ]] || fail "balance: $out"
ok "balance: pods per node, busiest first"

out="$(run minio-status)"
grep -q '^pv-1 data-0 minio nuc9$' <<<"$out" || fail "minio-status: PV rows: $out"
grep -q 'pv-2' <<<"$out" && fail "minio-status: another namespace's PV leaked: $out"
grep -q 'kubectl --context default -n minio exec minio-0 -- sh -c' "$LOG" || fail "minio-status: mc not run in the first pod: $(cat "$LOG")"
out="$(EXEC_RC=1 run minio-status)"
grep -q '^(mc admin info unavailable' <<<"$out" || fail "minio-status: exec failure not reported: $out"
ok "minio-status: pods, the namespace's PVs, mc in the first pod"

rc=0
out="$(run bogus 2>&1)" || rc=$?
[[ "$rc" -eq 2 && "$out" == "ERROR: unknown cluster op 'bogus' (kubectl|cordon|uncordon|drain|delete-node|label-node|balance|placement|minio-status)" ]] ||
	fail "unknown op: rc=$rc $out"
ok "an unknown op exits 2"

rc=0
out="$(
	unset BUILD_WORKSPACE_DIRECTORY
	run cordon x 2>&1
)" || rc=$?
[[ "$rc" -eq 1 && "$out" == *"BUILD_WORKSPACE_DIRECTORY: this target must be run via bazel run, not bazel build" ]] || fail "no workspace: rc=$rc $out"
ok "outside bazel run it refuses"

rc=0
out="$(PATH=/usr/bin:/bin run cordon x 2>&1)" || rc=$?
[[ "$rc" -eq 1 && "$out" == "ERROR: kubectl not found on PATH." ]] || fail "no kubectl: rc=$rc $out"
ok "without kubectl it refuses"

echo "All cluster tests passed."
