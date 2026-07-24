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

# Guards the one release regression that silently breaks `go get`: the
# pulumi-library Go-module tag MUST be go/pkg/<name>/vX.Y.Z (SLASH before the
# version). A dash form (go/pkg/<name>-vX.Y.Z) is an "unknown revision" -- the
# 2026-07 cloud_run outage. Runs under `bazel test //...`, so it can't rot.
set -euo pipefail
SCRIPT="${1:?usage: publish-local_test.sh <path to publish-local.sh>}"

# Source only the pure helpers (the guard returns before main / any side effect).
PUBLISH_LOCAL_LIB_ONLY=1 . "$SCRIPT"

ok() { echo "ok: $*"; }
bad() {
  echo "FAIL: $*" >&2
  exit 1
}

got="$(go_module_tag cloud_run 0.3.0)"
[ "$got" = "go/pkg/cloud_run/v0.3.0" ] || bad "expected go/pkg/cloud_run/v0.3.0, got '$got'"
ok "go_module_tag composes the slash form"
case "$got" in
  *-v0.3.0) bad "tag used a DASH before the version -- this breaks 'go get' (cloud_run bug)" ;;
esac
ok "no dash-before-version"
case "$got" in
  */v0.3.0) ok "version is preceded by a slash" ;;
  *) bad "version is not slash-separated: '$got'" ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '{"pulumi/library/go/pkg/cloud_run":"1.2.3"}' >"$tmp/m.json"
v="$(manifest_version "$tmp/m.json")"
[ "$v" = "1.2.3" ] || bad "manifest_version expected 1.2.3, got '$v'"
ok "manifest_version reads the release-please value"

echo "publish-local: all lib tests passed."
