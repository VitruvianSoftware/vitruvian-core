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
# Every kubeseal call in these tools must pass --context. kubeseal fetches the
# sealing key from a cluster; without --context it uses the kubeconfig's
# current context, so KUBE_CONTEXT=<other cluster> would seal with the WRONG
# cluster's key and the target controller could never decrypt the secret.
# A call spans backslash-continued lines, so those are joined first, and only
# the kubeseal part of a pipeline is checked.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bad=0; seen=0
for f in "$DIR"/*.sh; do
  case "$f" in *_test.sh) continue ;; esac
  while IFS= read -r call; do
    seen=$((seen+1))
    # shellcheck disable=SC2016 # the literal text $KCTX is what we match
    case "$call" in
      *'--context "$KCTX"'*) ;;
      *) echo "FAIL $(basename "$f"): kubeseal without --context \"\$KCTX\": $call"; bad=1 ;;
    esac
  done < <(awk '
    { line = $0 }
    buf != "" { line = buf " " line; buf = "" }
    /\\$/ { sub(/\\$/, "", line); buf = line; next }
    line ~ /^[[:space:]]*#/ { next }
    # Keep only the kubeseal command itself (up to the next pipe): a
    # kubectl --context earlier in the same pipeline must not count.
    match(line, /(\||exec)[[:space:]]*kubeseal[[:space:]]/) {
      rest = substr(line, RSTART + RLENGTH)
      if ((p = index(rest, "|")) > 0) rest = substr(rest, 1, p - 1)
      print "kubeseal " rest
    }
  ' "$f")
done
# Guard the guard: if the scan finds nothing, it proves nothing.
[ "$seen" -ge 5 ] || { echo "FAIL only $seen kubeseal calls found -- expected at least 5; is the scan broken?"; exit 1; }
[ "$bad" = 0 ] && echo "PASS all $seen kubeseal calls pass --context"
exit "$bad"
