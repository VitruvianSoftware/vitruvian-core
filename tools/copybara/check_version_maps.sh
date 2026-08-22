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

# check_version_maps.sh — the export version maps in copy.bara.sky must match
# what this repo actually publishes.
#
# WHY. Two mirrors consume published artefacts rather than in-tree sources, so
# the export rewrites in-tree references to concrete published versions:
#
#   * ts-foundation: pnpm `workspace:*` -> `@vitruviansoftware/foundation-<n>@X`
#   * go-foundation: an in-tree `replace` -> `require <mod> vX.Y.Z`
#
# Both use a HAND-MAINTAINED map whose only safeguard was the comment "Keep in
# sync". Neither was. Measured 2026-08-22: **28 of 28** ts entries and 7 of 14 go
# entries had drifted, and the ts-example-foundation mirror had been failing
# since at least 2026-08-18 with
#
#   npm error notarget No matching version found for
#             @vitruviansoftware/foundation-bootstrap@^0.2.1
#
# -- a version that was never published and never will be (`^0.2.1` on a 0.x
# line means >=0.2.1 <0.3.0, and the package is at 0.4.x).
#
# This is the third hand-maintained cross-repo mapping to drift silently in one
# day; the other two were the mirror's release-please-config.json and the pnpm
# catalog map. The pattern is always the same: a mapping the monorepo cannot see
# the effect of, guarded only by a comment.
#
# Checked OFFLINE against the repo's own versions rather than the registry: the
# publish audit already asserts repo == registry, so repo is the right source of
# truth here and this needs no network.
#
# Exit: 0 in sync · 1 drift or a missing entry · 2 the maps could not be parsed
set -euo pipefail
cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SKY="${SKY:-tools/copybara/copy.bara.sky}"
TS_ROOT="${TS_ROOT:-pulumi/library/ts/packages}"
GO_ROOT="${GO_ROOT:-pulumi/library/go/pkg}"
TS_EXAMPLE="${TS_EXAMPLE:-pulumi/examples/ts-foundation}"

[ -f "$SKY" ] || { echo "check-version-maps: $SKY not found" >&2; exit 2; }

python3 - "$SKY" "$TS_ROOT" "$GO_ROOT" "$TS_EXAMPLE" <<'PYEOF'
import json, os, re, sys, glob

sky, ts_root, go_root, ts_example = sys.argv[1:5]
src = open(sky).read()

def parse_map(name):
    m = re.search(re.escape(name) + r'\s*=\s*\{(.*?)\n\}', src, re.S)
    if not m:
        print("check-version-maps: could not parse %s" % name, file=sys.stderr)
        sys.exit(2)
    return dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', m.group(1)))

problems = []

# --- TypeScript ------------------------------------------------------------
ts = parse_map("_TS_EXAMPLE_LIB_VERSIONS")
for key, mapped in sorted(ts.items()):
    pj = os.path.join(ts_root, key, "package.json")
    if not os.path.exists(pj):
        problems.append("ts  %-28s maps to a package that does not exist (%s)" % (key, pj))
        continue
    actual = json.load(open(pj)).get("version")
    if actual != mapped:
        problems.append("ts  %-28s map=%-9s repo=%s" % (key, mapped, actual))

# Every workspace:* foundation dep the example declares MUST have an entry, or
# the export leaves `workspace:*` in the mirror and npm cannot resolve it.
needed = set()
for pj in glob.glob(os.path.join(ts_example, "**", "package.json"), recursive=True):
    if "node_modules" in pj:
        continue
    d = json.load(open(pj))
    for field in ("dependencies", "devDependencies"):
        for dep, spec in (d.get(field) or {}).items():
            if dep.startswith("@vitruviansoftware/foundation-") and str(spec).startswith("workspace:"):
                needed.add(dep.split("foundation-", 1)[1])
for miss in sorted(needed - set(ts)):
    problems.append("ts  %-28s used by the example as workspace:* but ABSENT from the map" % miss)

# --- Go --------------------------------------------------------------------
go = parse_map("_GO_EXAMPLE_LIB_VERSIONS")
for key, mapped in sorted(go.items()):
    base = re.sub(r"/v\d+$", "", key)          # bootstrap/v2 -> bootstrap
    mf = os.path.join(go_root, base, ".release-please-manifest.json")
    if not os.path.exists(mf):
        problems.append("go  %-28s maps to a module with no manifest (%s)" % (key, mf))
        continue
    actual = list(json.load(open(mf)).values())[0]
    if actual != mapped:
        problems.append("go  %-28s map=%-9s repo=%s" % (key, mapped, actual))

if problems:
    print("check-version-maps: %d problem(s) in %s" % (len(problems), sky), file=sys.stderr)
    for p in problems:
        print("  " + p, file=sys.stderr)
    print("", file=sys.stderr)
    print("  These maps rewrite in-tree references to PUBLISHED versions on export.", file=sys.stderr)
    print("  A stale entry ships a mirror that cannot resolve its own dependencies.", file=sys.stderr)
    sys.exit(1)

print("check-version-maps: %d ts + %d go entries all match the repo." % (len(ts), len(go)))
PYEOF
