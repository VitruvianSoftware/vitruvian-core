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

# pulumi-summary.sh — render a markdown digest of a `pulumi up`/`pulumi preview`
# run so foundation CI surfaces the deploy signal (creates / updates / replaces /
# deletes) on the Actions run page ($GITHUB_STEP_SUMMARY) and, for previews, in
# the sticky PR comment. One script feeds both sinks so they never drift.
#
#   Usage: pulumi-summary.sh <phase-label> <pulumi-output-file> <exit-code>
#
# The markdown (written to stdout) contains:
#   - a title:   ## 🏗️ <label> · pulumi up|preview · <stack> · ✅ Succeeded / ❌ Failed
#                (the error is surfaced right under the title on failure)
#   - a counts table:  ➕ Created / 🔄 Updated / ♻️ Replaced / ➖ Deleted / ⚪ Unchanged
#   - a risk callout:  ⚠️ N deleted, M replaced  (destructive ops listed first + bold)
#                      or ✅ No replaces or deletes
#   - a per-resource table:  Action · Type · Name  (from `pulumi … --diff`)
#   - a collapsible <details> with the full raw log
#
# ── pulumi output format quirks this parser handles (verified against real
#    `pulumi {up,preview} --diff` output from v3.229.0) ─────────────────────────
#   1. `up --diff` prints TWO sections — a "Previewing update (stack):" section
#      followed by an "Updating (stack):" section — each with its own resource
#      list and its own `Resources:` block. We parse ONLY the last section so
#      counts/resources are never double-reported; for `preview` there is a
#      single "Previewing update (stack):" section.
#   2. The `Resources:` summary uses future tense on preview ("+ 1 to create")
#      and past tense on up ("+ 1 created"). We key off the action WORD, not the
#      symbol, so both tenses parse identically.
#   3. When a run has both changes and no-op resources the unchanged count rides
#      a "N changes. M unchanged" line rather than a plain "M unchanged" line.
#   4. Replacements print as "+-N to replace" / "+-N replaced" (a `+-` glyph with
#      no space before the count) and as "+-<type>: (replace)" resource headers.
#   5. On failure the `errored` count can leak pulumi color directives, e.g.
#      "<{%fg 1%}>1 errored<{%reset%}>"; other lines can carry raw ANSI. Both are
#      stripped before parsing.
#   6. A resource's Name is not on its header line — it is the final `::` segment
#      of the following `[urn=…]` line.

set -euo pipefail

usage() {
  echo "usage: pulumi-summary.sh <phase-label> <pulumi-output-file> <exit-code>" >&2
  exit 2
}

LABEL="${1:-}"
OUT_FILE="${2:-}"
EXIT_CODE="${3:-}"
[ -n "$LABEL" ] && [ -n "$OUT_FILE" ] && [ -n "$EXIT_CODE" ] || usage

# Cap the raw log so the combined digest stays under GitHub's 65536-char comment
# limit (the same output also feeds the step summary, whose ceiling is far higher).
RAW_MAX="${PULUMI_SUMMARY_RAW_MAX:-40000}"

[[ "$EXIT_CODE" =~ ^[0-9]+$ ]] || EXIT_CODE=1

# ── 1. Clean the log: strip ANSI escapes, pulumi color directives, and CRs ──────
CLEAN="$(mktemp "${TMPDIR:-/tmp}/pulumi-summary.XXXXXX")"
trap 'rm -f "$CLEAN"' EXIT
if [ -f "$OUT_FILE" ]; then
  # Strip ANSI CSI escapes (ESC = $'\x1b'), pulumi color directives, and CRs.
  sed -E -e 's/'$'\x1b''\[[0-9;]*[a-zA-Z]//g' \
         -e 's/<\{%[^%]*%\}>//g' \
         -e 's/\r$//' \
         "$OUT_FILE" > "$CLEAN"
fi

# ── 2. Parse counts + per-resource rows + error lines with a POSIX awk pass ─────
# Emits tab-separated records:
#   META\t<KEY>\t<VALUE>
#   RES\t<rank>\t<action>\t<type>\t<name>
#   ERR\t<error line>
PARSED="$(
  awk '
    BEGIN { n = 0 }
    { L[++n] = $0 }

    function paren(s,   x) { x = s; sub(/^[^(]*\(/, "", x); sub(/\).*$/, "", x); return x }
    # First count matching "<digits> <word(s)>" on a Resources: line.
    function num(s, kw,   re, m) {
      re = "[0-9]+ (" kw ")"
      if (match(s, re)) { m = substr(s, RSTART, RLENGTH); sub(/ .*$/, "", m); return m }
      return ""
    }

    END {
      # Locate the LAST section header — the authoritative section (see quirk #1).
      start = 1; op = ""; stack = ""
      for (i = 1; i <= n; i++) {
        if (L[i] ~ /^Updating \(/)               { start = i; op = "up";      stack = paren(L[i]) }
        else if (L[i] ~ /^Previewing update \(/) { start = i; op = "preview"; stack = paren(L[i]) }
      }

      created = 0; updated = 0; replaced = 0; deleted = 0; unchanged = 0; errored = 0
      inres = 0
      for (i = start; i <= n; i++) {
        line = L[i]
        if (line ~ /^Resources:/) { inres = 1; continue }
        if (inres == 1) {
          if (line ~ /^[ \t]*$/ || line ~ /^Duration:/) { inres = 0; continue }
          v = num(line, "created|to create");   if (v != "") created   = v
          v = num(line, "updated|to update");   if (v != "") updated   = v
          v = num(line, "replaced|to replace"); if (v != "") replaced  = v
          v = num(line, "deleted|to delete");   if (v != "") deleted   = v
          v = num(line, "unchanged");           if (v != "") unchanged = v
          v = num(line, "errored");             if (v != "") errored   = v
        }
      }

      # Per-resource headers within the authoritative section. Only the four
      # mutating actions the counts table tracks are listed; `same` (no-op) and
      # read-only ops (read/refresh) are excluded so the table == the changes.
      hdr = ": \\((create|update|delete|replace)\\)[ \t]*$"
      for (i = start; i <= n; i++) {
        line = L[i]
        if (line ~ hdr) {
          a = line; sub(/^.*: \(/, "", a); sub(/\).*$/, "", a)
          t = line; sub(/: \((create|update|delete|replace)\)[ \t]*$/, "", t)
          sub(/^[ \t]*[-+~]*[ \t]*/, "", t)
          name = ""
          for (j = i + 1; j <= n && j <= i + 8; j++) {
            if (L[j] ~ /\[urn=/) { u = L[j]; sub(/^.*::/, "", u); sub(/\].*$/, "", u); name = u; break }
            if (L[j] ~ hdr) break
          }
          rank = 4
          if (a == "delete")       rank = 0
          else if (a == "replace") rank = 1
          else if (a == "update")  rank = 2
          else if (a == "create")  rank = 3
          printf "RES\t%d\t%s\t%s\t%s\n", rank, a, t, name
        }
      }

      # Error lines (scanned across the whole log — errors can precede the last
      # section, e.g. program/type-check failures during preview).
      ecount = 0
      for (i = 1; i <= n; i++) {
        if ((L[i] ~ /^error:/ || L[i] ~ /^Error:/) && ecount < 20) { printf "ERR\t%s\n", L[i]; ecount++ }
      }

      printf "META\tOP\t%s\n",        op
      printf "META\tSTACK\t%s\n",     stack
      printf "META\tCREATED\t%d\n",   created
      printf "META\tUPDATED\t%d\n",   updated
      printf "META\tREPLACED\t%d\n",  replaced
      printf "META\tDELETED\t%d\n",   deleted
      printf "META\tUNCHANGED\t%d\n", unchanged
      printf "META\tERRORED\t%d\n",   errored
    }
  ' "$CLEAN"
)"

meta() { printf '%s\n' "$PARSED" | awk -F'\t' -v k="$1" '$1=="META" && $2==k {print $3; exit}'; }

OP="$(meta OP)"
STACK="$(meta STACK)"
CREATED="$(meta CREATED)";   CREATED="${CREATED:-0}"
UPDATED="$(meta UPDATED)";   UPDATED="${UPDATED:-0}"
REPLACED="$(meta REPLACED)"; REPLACED="${REPLACED:-0}"
DELETED="$(meta DELETED)";   DELETED="${DELETED:-0}"
UNCHANGED="$(meta UNCHANGED)"; UNCHANGED="${UNCHANGED:-0}"
ERRORED="$(meta ERRORED)";   ERRORED="${ERRORED:-0}"

case "$OP" in
  up)      OP_DISPLAY="pulumi up" ;;
  preview) OP_DISPLAY="pulumi preview" ;;
  *)       OP_DISPLAY="pulumi" ;;
esac

# ── 3. Emit the markdown digest ────────────────────────────────────────────────

# Escape a markdown table cell (pipes only — types/names are otherwise plain).
cell() { printf '%s' "$1" | sed -e 's/|/\\|/g'; }

ROW_MAX="${PULUMI_SUMMARY_ROW_MAX:-100}"
ROW_TOTAL="$(printf '%s\n' "$PARSED" | awk -F'\t' '$1=="RES"{n++} END{print n+0}')"

# Everything above the raw-log <details> is rendered into a buffer so its size
# can be measured — the collapsible log then gets whatever budget remains under
# the comment limit (see the size clamp below).
render_head() {
  local title="## 🏗️ ${LABEL} · ${OP_DISPLAY}"
  [ -n "$STACK" ] && title="${title} · ${STACK}"
  if [ "$EXIT_CODE" -eq 0 ]; then
    title="${title} · ✅ Succeeded"
  else
    title="${title} · ❌ Failed"
  fi
  printf '%s\n\n' "$title"

  # Surface the error on failure.
  if [ "$EXIT_CODE" -ne 0 ]; then
    if [ "$ERRORED" -gt 0 ]; then
      printf '> ❌ **%s failed** (exit %s) · 💥 %s errored\n\n' "$OP_DISPLAY" "$EXIT_CODE" "$ERRORED"
    else
      printf '> ❌ **%s failed** (exit %s)\n\n' "$OP_DISPLAY" "$EXIT_CODE"
    fi
    local errs
    errs="$(printf '%s\n' "$PARSED" | awk -F'\t' '$1=="ERR"{print $2}')"
    if [ -n "$errs" ]; then
      printf '```text\n%s\n```\n\n' "$errs"
    else
      printf '_No `error:` line was captured — see the full log below._\n\n'
    fi
  fi

  # Counts table.
  printf '### Resource changes\n\n'
  printf '| ➕ Created | 🔄 Updated | ♻️ Replaced | ➖ Deleted | ⚪ Unchanged |\n'
  printf '| --: | --: | --: | --: | --: |\n'
  printf '| %s | %s | %s | %s | %s |\n\n' "$CREATED" "$UPDATED" "$REPLACED" "$DELETED" "$UNCHANGED"

  # Risk callout.
  local destructive=$((DELETED + REPLACED))
  if [ "$destructive" -gt 0 ]; then
    printf '> ⚠️ **%s deleted, %s replaced** — destructive operations are listed first below.\n\n' "$DELETED" "$REPLACED"
  else
    printf '> ✅ No replaces or deletes.\n\n'
  fi

  # Per-resource table (destructive first, destructive rows bold). The row cap
  # keeps a big first-apply from blowing past the comment limit; because rows are
  # sorted destructive-first, a cap only ever drops low-risk creates/updates —
  # every replace/delete stays visible.
  local rows shown=0 _kind _rank action type name emoji lbl tcell ncell
  rows="$(printf '%s\n' "$PARSED" | awk -F'\t' '$1=="RES"{print}' | sort -t"$(printf '\t')" -k2,2n -s || true)"
  printf '### Resources\n\n'
  if [ "$ROW_TOTAL" -eq 0 ]; then
    printf '_No resource-level changes._\n\n'
  else
    printf '| Action | Type | Name |\n'
    printf '| :-- | :-- | :-- |\n'
    while IFS="$(printf '\t')" read -r _kind _rank action type name; do
      [ -n "$action" ] || continue
      shown=$((shown + 1))
      [ "$shown" -gt "$ROW_MAX" ] && break
      case "$action" in
        create)  emoji="➕"; lbl="Created" ;;
        update)  emoji="🔄"; lbl="Updated" ;;
        replace) emoji="♻️"; lbl="Replaced" ;;
        delete)  emoji="➖"; lbl="Deleted" ;;
        *)       emoji="•"; lbl="$action" ;;
      esac
      tcell="\`$(cell "$type")\`"
      ncell="$(cell "$name")"
      if [ "$action" = "delete" ] || [ "$action" = "replace" ]; then
        printf '| %s **%s** | %s | **%s** |\n' "$emoji" "$lbl" "$tcell" "$ncell"
      else
        printf '| %s %s | %s | %s |\n' "$emoji" "$lbl" "$tcell" "$ncell"
      fi
    done <<EOF
$rows
EOF
    if [ "$ROW_TOTAL" -gt "$ROW_MAX" ]; then
      printf '\n_… and %s more (destructive ops shown first; full detail in the log below)._\n' "$((ROW_TOTAL - ROW_MAX))"
    fi
    printf '\n'
  fi
}

HEAD="$(render_head)"
printf '%s\n\n' "$HEAD"

# Collapsible full log — clamped so title + tables + log together stay under
# GitHub's 65536-char comment limit (the same digest also feeds the sticky PR
# comment). The raw log gets min(RAW_MAX, whatever the head leaves unused).
COMMENT_LIMIT="${PULUMI_SUMMARY_COMMENT_LIMIT:-63000}"
HEAD_BYTES="$(printf '%s' "$HEAD" | wc -c | tr -d ' ')"
RAW_ALLOW=$(( COMMENT_LIMIT - HEAD_BYTES - 200 ))   # 200 ≈ the <details> wrapper
[ "$RAW_ALLOW" -lt 0 ] && RAW_ALLOW=0
[ "$RAW_ALLOW" -gt "$RAW_MAX" ] && RAW_ALLOW="$RAW_MAX"

printf '<details>\n<summary>📜 Full pulumi log</summary>\n\n'
printf '```text\n'
CLEAN_SIZE=0
[ -f "$CLEAN" ] && CLEAN_SIZE="$(wc -c < "$CLEAN" | tr -d ' ')"
if [ "$CLEAN_SIZE" -eq 0 ]; then
  printf '(no pulumi output captured)\n'
elif [ "$RAW_ALLOW" -eq 0 ]; then
  printf '(log omitted — digest is at the comment size limit; see the raw job output)\n'
elif [ "$CLEAN_SIZE" -gt "$RAW_ALLOW" ]; then
  printf '… log truncated to last %s bytes (full log in the raw job output) …\n\n' "$RAW_ALLOW"
  tail -c "$RAW_ALLOW" "$CLEAN"
else
  cat "$CLEAN"
fi
printf '\n```\n\n</details>\n'
