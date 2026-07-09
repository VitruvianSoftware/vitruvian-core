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

# pulumi-summary_test.sh — regression guard for pulumi-summary.sh.
#
# Runs the digest against fixtures captured from REAL `pulumi {up,preview} --diff`
# output (tools/ci/testdata/pulumi/, pulumi v3.229.0) and asserts the parser
# handles every quirk: preview vs up tense, the double section `up --diff` emits,
# the "N changes. M unchanged" line, `+-` replacements, leaked color directives on
# failure, and URN-derived resource names.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/pulumi-summary.sh"
DATA="${HERE}/testdata/pulumi"

fails=0
run() { bash "$SCRIPT" "$1" "${DATA}/$2" "$3"; }

# assert_has <name> <output> <fixed-substring>
assert_has() {
  if printf '%s' "$2" | grep -qF -- "$3"; then
    printf '  ✓ %s\n' "$1"
  else
    printf '  ✗ %s — expected to find: %s\n' "$1" "$3" >&2
    fails=$((fails + 1))
  fi
}
# assert_missing <name> <output> <fixed-substring>
assert_missing() {
  if printf '%s' "$2" | grep -qF -- "$3"; then
    printf '  ✗ %s — should NOT contain: %s\n' "$1" "$3" >&2
    fails=$((fails + 1))
  else
    printf '  ✓ %s\n' "$1"
  fi
}
# assert_eq <name> <actual> <expected>
assert_eq() {
  if [ "$2" = "$3" ]; then
    printf '  ✓ %s\n' "$1"
  else
    printf '  ✗ %s — expected [%s] got [%s]\n' "$1" "$3" "$2" >&2
    fails=$((fails + 1))
  fi
}

# ── up --diff, mixed (create/replace/delete/same), success ─────────────────────
echo "up-mixed (deploy, success):"
out="$(run gcp-org up-mixed.txt 0)"
assert_has  "title: up + stack + succeeded" "$out" '## 🏗️ gcp-org · pulumi up · production · ✅ Succeeded'
assert_has  "counts row 1/0/2/1/2"          "$out" '| 1 | 0 | 2 | 1 | 2 |'
assert_has  "risk callout"                  "$out" '⚠️ **1 deleted, 2 replaced**'
assert_has  "deleted row bold + urn name"   "$out" '➖ **Deleted** | `random:index/randomString:RandomString` | **str-a**'
assert_has  "replaced row bold"             "$out" '♻️ **Replaced** | `random:index/randomPet:RandomPet` | **pet-b**'
assert_has  "created row not bold"          "$out" '➕ Created | `random:index/randomInteger:RandomInteger` | int-b'
# The double section `up --diff` emits must not double-count: exactly 4 change rows.
# Resource rows are the only lines with a backtick-wrapped Type cell, which
# distinguishes them from the counts-table header (also '| ➕ Created | …').
rows="$(printf '%s\n' "$out" | grep -cF '| `')"
assert_eq   "no double-count (4 rows)"      "$rows" "4"
# Destructive listed first: the deleted row precedes the created row.
del_ln="$(printf '%s\n' "$out" | grep -nF '➖ **Deleted** | `' | head -1 | cut -d: -f1)"
new_ln="$(printf '%s\n' "$out" | grep -nF '➕ Created | `' | head -1 | cut -d: -f1)"
if [ "${del_ln:-0}" -lt "${new_ln:-0}" ]; then echo "  ✓ destructive-first ordering"; else echo "  ✗ destructive-first ordering ($del_ln !< $new_ln)" >&2; fails=$((fails+1)); fi
assert_has  "collapsible log"               "$out" '<summary>📜 Full pulumi log</summary>'

# ── preview --diff, mixed, success ─────────────────────────────────────────────
echo "preview-mixed (preview, success):"
out="$(run gcp-org preview-mixed.txt 0)"
assert_has  "title: preview"                "$out" '· pulumi preview · production · ✅ Succeeded'
assert_has  "future-tense counts 1/0/2/1/2" "$out" '| 1 | 0 | 2 | 1 | 2 |'
assert_has  "risk callout"                  "$out" '⚠️ **1 deleted, 2 replaced**'

# ── up --diff, all creates ─────────────────────────────────────────────────────
echo "up-creates (all creates):"
out="$(run gcp-org up-creates.txt 0)"
assert_has  "counts 5/0/0/0/0"              "$out" '| 5 | 0 | 0 | 0 | 0 |'
assert_has  "no destructive"                "$out" '✅ No replaces or deletes.'
assert_has  "stack resource by urn name"    "$out" '➕ Created | `pulumi:pulumi:Stack` | pf-production'

# ── preview, no-op (all unchanged) ─────────────────────────────────────────────
echo "preview-noop (all unchanged):"
out="$(run gcp-org preview-noop.txt 0)"
assert_has  "counts 0/0/0/0/5"              "$out" '| 0 | 0 | 0 | 0 | 5 |'
assert_has  "empty resource table"          "$out" '_No resource-level changes._'
assert_has  "no destructive"                "$out" '✅ No replaces or deletes.'

# ── preview, real in-place update ──────────────────────────────────────────────
echo "preview-update (in-place update):"
out="$(run gcp-org preview-update.txt 0)"
assert_has  "counts 0/1/0/0/5"              "$out" '| 0 | 1 | 0 | 0 | 5 |'
assert_has  "updated row"                   "$out" '🔄 Updated | `command:local:Command` | cmd-a'

# ── up --diff, deploy failure ──────────────────────────────────────────────────
echo "up-fail (deploy failure):"
out="$(run gcp-bootstrap up-fail.txt 1)"
assert_has  "title: failed"                 "$out" '❌ Failed'
assert_has  "failure line + errored count"  "$out" '**pulumi up failed** (exit 1) · 💥 1 errored'
assert_has  "error surfaced"                "$out" 'error: update failed'
assert_missing "no leaked color directive"  "$out" '<{%'

# ── preview, program/type-check failure ────────────────────────────────────────
echo "preview-fail (type-check failure):"
out="$(run gcp-org preview-fail.txt 1)"
assert_has  "title: preview failed"         "$out" '· pulumi preview · production · ❌ Failed'
assert_has  "Error surfaced"                "$out" 'Error: random:index/randomPet:RandomPet is not assignable'
assert_missing "no leaked ANSI"             "$out" '['$'\x1b'

# ── row cap: destructive ops survive truncation ────────────────────────────────
echo "row cap (destructive survive):"
# up-creates has 5 change rows; cap at 2 → 3 dropped, note shown.
out="$(PULUMI_SUMMARY_ROW_MAX=2 run gcp-org up-creates.txt 0)"
capped="$(printf '%s\n' "$out" | grep -cF '| `')"
assert_eq   "table capped to 2 rows"        "$capped" "2"
assert_has  "truncation note (3 more)"      "$out" '… and 3 more'
# Mixed run capped at 1 → only the single most-destructive (delete) row survives.
out="$(PULUMI_SUMMARY_ROW_MAX=1 run gcp-org up-mixed.txt 0)"
assert_has  "destructive survives the cap"  "$out" '➖ **Deleted** | `random:index/randomString:RandomString` | **str-a**'
assert_has  "cap note present"              "$out" '… and 3 more'

# ── size clamp: a huge apply stays under the 65536-char comment limit ──────────
echo "size clamp (400-resource apply):"
big="$(mktemp)"
{
  echo "Updating (production):"
  echo "  pulumi:pulumi:Stack: (same)"
  i=0
  while [ "$i" -lt 400 ]; do
    printf '    + gcp:organizations/veryLongResourceTypeName:VeryLongResourceType%03d: (create)\n' "$i"
    printf '        [urn=urn:pulumi:production::proj::gcp:organizations/veryLongResourceTypeName:VeryLongResourceType%03d::a-really-quite-long-resource-name-number-%03d-with-lots-of-padding]\n' "$i" "$i"
    i=$((i + 1))
  done
  echo "Resources:"
  echo "    + 401 created"
} > "$big"
out="$(bash "$SCRIPT" gcp-networks "$big" 0)"
bytes="$(printf '%s' "$out" | wc -c | tr -d ' ')"
rm -f "$big"
if [ "$bytes" -le 65536 ]; then
  printf '  ✓ digest is %s bytes (≤ 65536)\n' "$bytes"
else
  printf '  ✗ digest is %s bytes (> 65536)\n' "$bytes" >&2; fails=$((fails + 1))
fi
assert_has  "row cap note present"          "$out" '… and 300 more'

# ── robustness: missing / empty output file ────────────────────────────────────
echo "robustness (empty output):"
empty="$(mktemp)"; : > "$empty"
out="$(bash "$SCRIPT" some-app "$empty" 0)"; rm -f "$empty"
assert_has  "renders with no pulumi output" "$out" '(no pulumi output captured)'
assert_has  "still shows a title"           "$out" '## 🏗️ some-app'

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS — all pulumi-summary assertions held"
else
  echo "FAIL — ${fails} assertion(s) failed" >&2
  exit 1
fi
