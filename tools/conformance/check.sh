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
#
# `conformance:check` — repo version-conformance checker for vitruvian-core.
#
# Invoked via `bazel run //tools/conformance:check`. It enforces ONE policy: the
# monorepo runs a single CANONICAL version per tool — the latest it has adopted —
# and every consumer file MUST match it. The canonical versions are read LIVE from
# the repo's own source-of-truth files (never hardcoded here, so they never drift):
#     go    -> the `go X.Y.Z` directive in go.work
#     node  -> the major of .nvmrc
#     pnpm  -> the `packageManager` "pnpm@X.Y.Z" in the root package.json
#
# A deviation from canonical is allowed ONLY as a deliberate, TEMPORARY, justified
# pin recorded in tools/conformance/version-pins.tsv. This is NOT a static
# allowlist: the check fails on undeclared drift, on a STALE pin (whose file now
# matches canonical and so is no longer needed), on a pin past its review_by date,
# on a registry row that disagrees with the file it names, and on a malformed row.
# So the check both BLOCKS silent drift AND nags every pin toward removal.
#
# Per (file,tool) it prints a status glyph (✓ ok / ✗ fail / ⊘ pinned / ⚠ advisory),
# the found vs canonical version, and a `→ fix:` hint on ✗. The process exits
# NON-ZERO iff any ✗ — so this is a reliable CI gate.
#
# Portability: targets macOS (BSD userland) AND Linux. No GNU-only constructs
# (`grep -P`, `realpath`, `sed -i ''`); parsing uses POSIX awk/sed only. ISO dates
# are compared lexically (string compare), which is correct for YYYY-MM-DD.

set -u

# ---------------------------------------------------------------------------
# Repo root. `bazel run` sets BUILD_WORKSPACE_DIRECTORY to the workspace root;
# fall back to PWD so the script is still runnable standalone (e.g. for tests).
# ---------------------------------------------------------------------------
ROOT="${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
REGISTRY="$ROOT/tools/conformance/version-pins.tsv"
EXCEPTIONS_DOC="$ROOT/docs/engineering/version-pin-exceptions.md"
TODAY="$(date +%Y-%m-%d)"

# ---------------------------------------------------------------------------
# Colors — ONLY when stdout is an interactive TTY. Piped/redirected output and
# CI logs stay plain so the report greps cleanly.
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_RESET=$'\033[0m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_CYAN=$'\033[36m'
else
  C_RESET='' C_GREEN='' C_YELLOW='' C_RED='' C_DIM='' C_BOLD='' C_CYAN=''
fi

GLYPH_OK="✓"
GLYPH_FAIL="✗"
GLYPH_PIN="⊘"
GLYPH_WARN="⚠"

FAIL_COUNT=0
OK_COUNT=0
PIN_COUNT=0      # sanctioned (non-expired) pins surfaced this run
WARN_COUNT=0
OVERALL_FAIL=0

# ---------------------------------------------------------------------------
# Registry parsing.
#
# The registry is whitespace-aligned (.tsv is nominal), so we split each data
# row on runs of whitespace/tabs and treat the 6th field onward as a single
# free-text `reason`. Records are stashed in three associative seams keyed by
# "<file>|<tool>":  PIN_VALUE / PIN_REVIEW / PIN_OWNER / PIN_REASON, plus an
# ordered REGISTRY_ROWS list for the stale-pin sweep. Bash 3.2 (macOS default)
# has no associative arrays, so we emulate them with a flat lookup over a held
# copy of the parsed rows.
# ---------------------------------------------------------------------------
PARSED_ROWS=""           # one record per line: file<TAB>tool<TAB>val<TAB>review<TAB>owner<TAB>reason
US=$'\037'               # field separator inside a buffered report row
RS=$'\036'               # row separator

die() {
  printf '%s%s conformance%s — %s\n' "$C_RED" "$GLYPH_FAIL" "$C_RESET" "$1" >&2
  exit 2
}

# Validate YYYY-MM-DD (digits + real-ish month/day ranges; lexical compare needs
# zero-padded fields, which this enforces).
valid_date() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) return 0 ;;
    *) return 1 ;;
  esac
}

parse_registry() {
  [ -f "$REGISTRY" ] || die "registry not found: $REGISTRY"
  # Read line by line; skip blank / comment lines; split the rest on whitespace.
  # awk does the heavy lifting so the free-text reason (col 6+) is rejoined with
  # spaces and emitted with the other 5 fields tab-separated.
  PARSED_ROWS="$(
    awk '
      # strip CR for files saved on Windows; skip blanks + comments
      { sub(/\r$/, "") }
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*#/ { next }
      {
        n = split($0, f, /[ \t]+/)
        # split() on leading whitespace yields an empty f[1]; normalize by
        # rebuilding from the first non-empty field.
        start = 1
        if (f[1] == "") start = 2
        # required: file tool value review_by owner  (=> at least 5 real fields
        # before reason). Emit a sentinel "MALFORMED" line the shell will catch.
        nfields = n - start + 1
        if (nfields < 6) {
          printf "MALFORMED\t%s\n", $0
          next
        }
        file   = f[start]
        tool   = f[start+1]
        value  = f[start+2]
        review = f[start+3]
        owner  = f[start+4]
        reason = ""
        for (i = start+5; i <= n; i++) reason = reason (reason=="" ? "" : " ") f[i]
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", file, tool, value, review, owner, reason
      }
    ' "$REGISTRY"
  )"

  # Post-validate in the shell (awk emitted MALFORMED sentinels + we re-check dates
  # and the tool enum here so the error messages are precise).
  if [ -n "$PARSED_ROWS" ]; then
    while IFS="$(printf '\t')" read -r c1 rest; do
      [ -n "$c1" ] || continue
      if [ "$c1" = "MALFORMED" ]; then
        die "malformed registry row (need: file tool pinned_value review_by owner reason): $rest"
      fi
    done <<EOF
$PARSED_ROWS
EOF
    while IFS="$(printf '\t')" read -r r_file r_tool r_val r_review r_owner r_reason; do
      [ -n "$r_file" ] || continue
      case "$r_tool" in
        go|node|pnpm) : ;;
        *) die "registry row for '$r_file' has unknown tool '$r_tool' (want go|node|pnpm)" ;;
      esac
      valid_date "$r_review" \
        || die "registry row for '$r_file' ($r_tool) has bad review_by date '$r_review' (want YYYY-MM-DD)"
    done <<EOF
$PARSED_ROWS
EOF
  fi
}

# Look up a pin record for (file,tool). On hit, sets PIN_VALUE/PIN_REVIEW/
# PIN_OWNER/PIN_REASON and returns 0; otherwise returns 1.
PIN_VALUE="" PIN_REVIEW="" PIN_OWNER="" PIN_REASON=""
lookup_pin() {
  _lf="$1" _lt="$2"
  PIN_VALUE="" PIN_REVIEW="" PIN_OWNER="" PIN_REASON=""
  [ -n "$PARSED_ROWS" ] || return 1
  while IFS="$(printf '\t')" read -r r_file r_tool r_val r_review r_owner r_reason; do
    [ -n "$r_file" ] || continue
    if [ "$r_file" = "$_lf" ] && [ "$r_tool" = "$_lt" ]; then
      PIN_VALUE="$r_val"; PIN_REVIEW="$r_review"; PIN_OWNER="$r_owner"; PIN_REASON="$r_reason"
      return 0
    fi
  done <<EOF
$PARSED_ROWS
EOF
  return 1
}

# ---------------------------------------------------------------------------
# Canonical source-of-truth readers (the LATEST adopted version per tool).
# ---------------------------------------------------------------------------

# go.work `go X.Y.Z` directive.
canonical_go() {
  [ -f "$ROOT/go.work" ] || die "canonical source missing: go.work"
  awk '$1 == "go" { print $2; exit }' "$ROOT/go.work"
}

# .nvmrc major (e.g. "22" from "22.21.1" or "v22.21.1").
canonical_node() {
  [ -f "$ROOT/.nvmrc" ] || die "canonical source missing: .nvmrc"
  awk 'NR==1 { gsub(/^[ \tv]+|[ \t\r]+$/, ""); split($0, a, "."); print a[1]; exit }' "$ROOT/.nvmrc"
}

# root package.json `"packageManager": "pnpm@X.Y.Z"`.
canonical_pnpm() {
  [ -f "$ROOT/package.json" ] || die "canonical source missing: package.json"
  grep '"packageManager"' "$ROOT/package.json" 2>/dev/null \
    | sed -n 's/.*pnpm@\([0-9][0-9.]*\).*/\1/p' \
    | head -1
}

# ---------------------------------------------------------------------------
# Discovery. Walk $ROOT excluding any path containing /node_modules/ or /bazel-,
# or starting with bazel-. Scaffold templates under internal/scaffold/templates/
# are reference seeds for NEW external repos (their pins are intentionally
# decoupled from this repo's live toolchain, and the repo's own license-check
# already excludes them) — so they are not repo consumers and are skipped too.
# `find -prune` keeps the walk cheap and portable (BSD + GNU).
# ---------------------------------------------------------------------------
discover() {
  # $1 = -name glob
  find "$ROOT" \
    \( -path '*/node_modules/*' -o -path '*/bazel-*' -o -name 'bazel-*' \
       -o -path '*/internal/scaffold/templates/*' \) -prune \
    -o -type f -name "$1" -print 2>/dev/null \
    | LC_ALL=C sort
}

# Workspace-relative path (strip "$ROOT/").
rel() { printf '%s' "${1#"$ROOT"/}"; }

# Integer-compare two dotted versions' MAJOR field. echoes -1 / 0 / 1
# (found<canon / == / found>canon). Used for the go-safety "never newer" rule.
go_major() { printf '%s' "$1" | cut -d. -f1; }
go_minor() { printf '%s' "$1" | cut -d. -f2; }
go_patch() { v="$(printf '%s' "$1" | cut -d. -f3)"; printf '%s' "${v:-0}"; }

# Returns 0 if $1 (found) is strictly GREATER than $2 (canonical) as a Go version.
go_is_newer() {
  fM="$(go_major "$1")"; fm="$(go_minor "$1")"; fp="$(go_patch "$1")"
  cM="$(go_major "$2")"; cm="$(go_minor "$2")"; cp="$(go_patch "$2")"
  [ "${fM:-0}" -gt "${cM:-0}" ] && return 0
  [ "${fM:-0}" -lt "${cM:-0}" ] && return 1
  [ "${fm:-0}" -gt "${cm:-0}" ] && return 0
  [ "${fm:-0}" -lt "${cm:-0}" ] && return 1
  [ "${fp:-0}" -gt "${cp:-0}" ] && return 0
  return 1
}

# Effective Node major(s) a Dockerfile pins, in first-seen order. Handles BOTH a
# hardcoded `FROM node:<major>...` AND a parameterized `FROM node:${NODE_VERSION}...`
# whose value comes from an `ARG NODE_VERSION=<default>` (the preferred pattern —
# it keeps the version sourced from one place instead of hardcoded). A parameterized
# FROM whose ARG has NO default is build-time-provided (the deploy passes it from
# .nvmrc) and emits nothing — there is no static value to check. A Dockerfile with
# no `FROM node:` emits nothing.
df_node_majors() {
  awk '
    # Collect ARG defaults: `ARG NAME=VALUE` (a bare `ARG NAME` carries no default).
    toupper($1) == "ARG" {
      rest = $0
      sub(/^[[:space:]]*[Aa][Rr][Gg][[:space:]]+/, "", rest)
      eq = index(rest, "=")
      if (eq > 0) {
        nm = substr(rest, 1, eq - 1); vv = substr(rest, eq + 1)
        gsub(/[[:space:]]/, "", nm); sub(/[[:space:]].*/, "", vv)
        argval[nm] = vv
      }
    }
    toupper($1) == "FROM" {
      img = $2
      if (img ~ /^node:/) {
        tag = substr(img, 6)                 # strip "node:"
        if (tag ~ /^\$/) {                   # parameterized: ${NAME}... or $NAME...
          nm = tag
          sub(/^\$\{?/, "", nm)              # strip leading $ or ${
          sub(/[-}:].*/, "", nm)             # NAME ends at - } : or token-end
          val = argval[nm]
          if (val != "") {
            split(val, p, /[^0-9]/)
            if (p[1] != "" && !seen[p[1]]++) print p[1]
          }
        } else {                             # hardcoded major
          split(tag, p, /[^0-9]/)
          if (p[1] != "" && !seen[p[1]]++) print p[1]
        }
      }
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Report buffering, grouped by tool. Each row encoded as
#   <glyph>\t<color>\t<file>\t<found>\t<canonical>\t<note>\t<fixhint>
# ---------------------------------------------------------------------------
ROWS_GO=""
ROWS_NODE=""
ROWS_PNPM=""
ROWS_ADVISORY=""

emit() {
  # $1 group-var-name  $2 glyph  $3 color  $4 file  $5 found  $6 canon  $7 note  $8 fix
  _row="$2${US}$3${US}$4${US}$5${US}$6${US}$7${US}${8:-}${RS}"
  case "$1" in
    go)       ROWS_GO="${ROWS_GO}${_row}" ;;
    node)     ROWS_NODE="${ROWS_NODE}${_row}" ;;
    pnpm)     ROWS_PNPM="${ROWS_PNPM}${_row}" ;;
    advisory) ROWS_ADVISORY="${ROWS_ADVISORY}${_row}" ;;
  esac
}

# Core verdict for a discovered (file,tool,found,canonical). Records a report row
# and updates counters. `group` is the report bucket (go|node|pnpm). `is_go` flags
# the extra "never newer than the workspace" safety rule.
verdict() {
  group="$1" file="$2" tool="$3" found="$4" canon="$5" is_go="$6"

  # GO SAFETY: a module requiring NEWER Go than the workspace is ALWAYS a fail,
  # even if a pin claims to bless it (the workspace can't build it).
  if [ "$is_go" = "1" ] && go_is_newer "$found" "$canon"; then
    emit "$group" "$GLYPH_FAIL" "$C_RED" "$file" "$found" "$canon" \
      "requires newer Go than the workspace" \
      "lower this module's go directive to <= $canon, or bump go.work first"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); return
  fi

  if [ "$found" = "$canon" ]; then
    emit "$group" "$GLYPH_OK" "$C_GREEN" "$file" "$found" "$canon" "" ""
    OK_COUNT=$((OK_COUNT + 1)); return
  fi

  # found != canonical -> consult the registry.
  if lookup_pin "$file" "$tool"; then
    if [ "$PIN_VALUE" = "$found" ]; then
      # Sanctioned pin. Surface it, then check expiry.
      if [ "$TODAY" \> "$PIN_REVIEW" ]; then
        emit "$group" "$GLYPH_FAIL" "$C_RED" "$file" "$found" "$canon" \
          "EXPIRED pin (review_by $PIN_REVIEW, owner $PIN_OWNER) — re-justify or remove" \
          "retire the pin: align $file to canonical $canon and delete its row from version-pins.tsv"
        OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
      else
        emit "$group" "$GLYPH_PIN" "$C_CYAN" "$file" "$found" "$canon" \
          "PINNED until $PIN_REVIEW ($PIN_OWNER): $PIN_REASON" ""
        PIN_COUNT=$((PIN_COUNT + 1))
      fi
    else
      # Registry disagrees with reality.
      emit "$group" "$GLYPH_FAIL" "$C_RED" "$file" "$found" "$canon" \
        "registry is STALE: says pinned_value $PIN_VALUE but file is $found" \
        "update or remove this row in version-pins.tsv to match $file"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    return
  fi

  # No pin record at all -> undeclared drift.
  emit "$group" "$GLYPH_FAIL" "$C_RED" "$file" "$found" "$canon" \
    "DRIFT: matches neither canonical $canon nor a registered pin" \
    "align $file to $canon, or add a justified row to version-pins.tsv"
  OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ---------------------------------------------------------------------------
# CHECK: Go. Every go.mod's `go` directive vs go.work's.
# ---------------------------------------------------------------------------
check_go() {
  canon="$(canonical_go)"
  [ -n "$canon" ] || die "could not read canonical go version from go.work"
  # NB: feed the loop from a here-doc, NOT `discover | while`. A pipe runs the
  # loop body in a SUBSHELL, so counter/row mutations would be lost. The here-doc
  # keeps the body in the current shell.
  _list="$(discover "go.mod")"
  while IFS= read -r gomod; do
    [ -n "$gomod" ] || continue
    found="$(awk '$1 == "go" { print $2; exit }' "$gomod")"
    [ -n "$found" ] || continue   # a go.mod with no go directive is not our concern
    verdict "go" "$(rel "$gomod")" "go" "$found" "$canon" "1"
  done <<EOF
$_list
EOF
}

# ---------------------------------------------------------------------------
# CHECK: Node. Every Dockerfile; the effective node major (see df_node_majors —
# a hardcoded `FROM node:<major>` OR a parameterized `FROM node:${NODE_VERSION}`
# resolved through its `ARG NODE_VERSION` default) vs .nvmrc's major. Dockerfiles
# with no node FROM — or a parameterized FROM with no ARG default (build-provided)
# — are skipped silently. A multi-stage Dockerfile contributes one row PER distinct
# node major it pins (so a file mixing node:20 and node:22 surfaces both).
# ---------------------------------------------------------------------------
check_node() {
  canon="$(canonical_node)"
  [ -n "$canon" ] || die "could not read canonical node major from .nvmrc"
  _list="$(discover "Dockerfile*")"
  while IFS= read -r dockerfile; do
    [ -n "$dockerfile" ] || continue
    # Distinct effective node majors (hardcoded or ARG-resolved), first-seen order.
    majors="$(df_node_majors "$dockerfile")"
    [ -n "$majors" ] || continue
    # Inner loop also via here-doc (same subshell reason as above).
    _df_rel="$(rel "$dockerfile")"
    while IFS= read -r maj; do
      [ -n "$maj" ] || continue
      verdict "node" "$_df_rel" "node" "$maj" "$canon" "0"
    done <<INNER
$majors
INNER
  done <<EOF
$_list
EOF
}

# ---------------------------------------------------------------------------
# CHECK: pnpm. Every package.json that DECLARES packageManager; its pnpm@X.Y.Z
# vs the root's. package.json files without the field are skipped.
# ---------------------------------------------------------------------------
check_pnpm() {
  canon="$(canonical_pnpm)"
  [ -n "$canon" ] || die "could not read canonical pnpm version from root package.json"
  _list="$(discover "package.json")"
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    grep -q '"packageManager"' "$pkg" 2>/dev/null || continue
    found="$(sed -n 's/.*pnpm@\([0-9][0-9.]*\).*/\1/p' "$pkg" | head -1)"
    [ -n "$found" ] || continue   # declares packageManager but not pnpm (e.g. npm@) -> not ours
    verdict "pnpm" "$(rel "$pkg")" "pnpm" "$found" "$canon" "0"
  done <<EOF
$_list
EOF
}

# ---------------------------------------------------------------------------
# STALE-PIN SWEEP. For every registry row, if its file now MATCHES canonical for
# that tool, the pin is dead weight -> ✗ STALE. This catches a pin whose file was
# already aligned but whose row was never deleted (the verdict() path above only
# sees a stale pin when the file STILL deviates; this sweep covers the aligned
# case). Rows whose file is missing are also flagged (nothing left to pin).
# ---------------------------------------------------------------------------
stale_sweep() {
  [ -n "$PARSED_ROWS" ] || return 0
  c_go="$(canonical_go)"; c_node="$(canonical_node)"; c_pnpm="$(canonical_pnpm)"
  while IFS="$(printf '\t')" read -r r_file r_tool r_val r_review r_owner r_reason; do
    [ -n "$r_file" ] || continue
    fpath="$ROOT/$r_file"
    if [ ! -f "$fpath" ]; then
      emit "$r_tool" "$GLYPH_FAIL" "$C_RED" "$r_file" "(missing)" "" \
        "STALE pin: $r_file no longer exists — delete this row from version-pins.tsv" \
        "delete the row for $r_file ($r_tool) from version-pins.tsv"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); continue
    fi
    case "$r_tool" in
      go)
        canon="$c_go"
        cur="$(awk '$1 == "go" { print $2; exit }' "$fpath")"
        ;;
      node)
        canon="$c_node"
        cur="$(df_node_majors "$fpath" | head -1)"
        ;;
      pnpm)
        canon="$c_pnpm"
        cur="$(sed -n 's/.*pnpm@\([0-9][0-9.]*\).*/\1/p' "$fpath" | head -1)"
        ;;
      *) continue ;;
    esac
    if [ -n "$cur" ] && [ "$cur" = "$canon" ]; then
      emit "$r_tool" "$GLYPH_FAIL" "$C_RED" "$r_file" "$cur" "$canon" \
        "STALE pin: $r_file now matches canonical — pin no longer needed" \
        "delete this row from version-pins.tsv ($r_file matches canonical $canon)"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done <<EOF
$PARSED_ROWS
EOF
}

# ---------------------------------------------------------------------------
# DOC SYNC. Every registry pin MUST be documented in the human-readable
# exceptions doc (its why + removal plan), so the registry and the doc can't
# drift apart. The .tsv is authoritative for the GATE; the doc is the narrative
# record — this assertion keeps them paired by requiring the doc to mention each
# pinned file's path. (Forward direction only: a pin with no doc entry fails.)
# ---------------------------------------------------------------------------
doc_sync() {
  [ -n "$PARSED_ROWS" ] || return 0
  if [ ! -f "$EXCEPTIONS_DOC" ]; then
    die "exceptions doc missing: docs/engineering/version-pin-exceptions.md (every pin must be documented there)"
  fi
  while IFS="$(printf '\t')" read -r r_file r_tool r_val r_review r_owner r_reason; do
    [ -n "$r_file" ] || continue
    if ! grep -qF "$r_file" "$EXCEPTIONS_DOC"; then
      emit "$r_tool" "$GLYPH_FAIL" "$C_RED" "$r_file" "" "" \
        "UNDOCUMENTED pin: not described in docs/engineering/version-pin-exceptions.md" \
        "document this exception (why + removal plan) in version-pin-exceptions.md"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done <<EOF
$PARSED_ROWS
EOF
}

# ---------------------------------------------------------------------------
# ADVISORY (⚠, NEVER fails): any app whose Dockerfile runs `pnpm` but whose
# co-located package.json declares NO packageManager pin. That mismatch is the
# class of bug behind deploy #284 (the image resolves a different pnpm than the
# repo's). We pair a Dockerfile with the package.json in its own directory.
# ---------------------------------------------------------------------------
advisory_pnpm() {
  _list="$(discover "Dockerfile*")"
  while IFS= read -r dockerfile; do
    [ -n "$dockerfile" ] || continue
    grep -qiE '(^|[[:space:]])pnpm([[:space:]]|$)' "$dockerfile" 2>/dev/null || continue
    dir="$(dirname "$dockerfile")"
    pkg="$dir/package.json"
    if [ -f "$pkg" ]; then
      grep -q '"packageManager"' "$pkg" 2>/dev/null && continue   # has a pin -> fine
      note="Dockerfile runs pnpm but $(rel "$pkg") has no packageManager pin"
    else
      note="Dockerfile runs pnpm but its dir has no package.json with a packageManager pin"
    fi
    emit "advisory" "$GLYPH_WARN" "$C_YELLOW" "$(rel "$dockerfile")" "" "" "$note" \
      "add \"packageManager\": \"pnpm@<root version>\" so the image pins the repo's pnpm"
    WARN_COUNT=$((WARN_COUNT + 1))
  done <<EOF
$_list
EOF
}

# ---------------------------------------------------------------------------
# Rendering. Print one group block per tool (go/node/pnpm) then the advisory
# block. Columns are aligned within each block.
# ---------------------------------------------------------------------------
print_group() {
  title="$1" rows="$2"
  [ -n "$rows" ] || return 0
  printf '\n%s%s%s\n' "$C_BOLD" "$title" "$C_RESET"

  # width pass
  w_file=4 w_found=5 w_canon=9
  old_ifs="$IFS"; IFS="$RS"
  for row in $rows; do
    [ -n "$row" ] || continue
    file="$(printf '%s' "$row" | awk -F"$US" '{print $3}')"
    found="$(printf '%s' "$row" | awk -F"$US" '{print $4}')"
    canon="$(printf '%s' "$row" | awk -F"$US" '{print $5}')"
    [ "${#file}" -gt "$w_file" ] && w_file=${#file}
    [ "${#found}" -gt "$w_found" ] && w_found=${#found}
    [ "${#canon}" -gt "$w_canon" ] && w_canon=${#canon}
  done
  IFS="$old_ifs"

  IFS="$RS"
  for row in $rows; do
    [ -n "$row" ] || continue
    glyph="$(printf '%s' "$row" | awk -F"$US" '{print $1}')"
    color="$(printf '%s' "$row" | awk -F"$US" '{print $2}')"
    file="$(printf '%s'  "$row" | awk -F"$US" '{print $3}')"
    found="$(printf '%s' "$row" | awk -F"$US" '{print $4}')"
    canon="$(printf '%s' "$row" | awk -F"$US" '{print $5}')"
    note="$(printf '%s'  "$row" | awk -F"$US" '{print $6}')"
    fix="$(printf '%s'   "$row" | awk -F"$US" '{print $7}')"

    printf '  %s%s%s  %-*s  found %-*s  canon %-*s' \
      "$color" "$glyph" "$C_RESET" \
      "$w_file" "$file" "$w_found" "$found" "$w_canon" "$canon"
    [ -n "$note" ] && printf '  %s%s%s' "$C_DIM" "$note" "$C_RESET"
    printf '\n'
    [ -n "$fix" ] && printf '       %s→ fix: %s%s\n' "$C_DIM" "$fix" "$C_RESET"
  done
  IFS="$old_ifs"
}

# ===========================================================================
# MAIN
# ===========================================================================
parse_registry

check_go
check_node
check_pnpm
stale_sweep
doc_sync
advisory_pnpm

echo
printf '%s%sconformance%s — %s\n' "$C_BOLD" "$C_GREEN" "$C_RESET" "vitruvian-core version conformance"
printf '%scanonical: go %s (go.work) · node %s (.nvmrc) · pnpm %s (package.json)%s\n' \
  "$C_DIM" "$(canonical_go)" "$(canonical_node)" "$(canonical_pnpm)" "$C_RESET"

print_group "Go (go.mod → go.work)" "$ROWS_GO"
print_group "Node (Dockerfile FROM node → .nvmrc major)" "$ROWS_NODE"
print_group "pnpm (package.json packageManager → root)" "$ROWS_PNPM"
print_group "Advisory — pnpm Dockerfile without a packageManager pin" "$ROWS_ADVISORY"

# Count active (non-expired, sanctioned) pin rows in the registry for the summary.
ACTIVE_PINS=0
if [ -n "$PARSED_ROWS" ]; then
  ACTIVE_PINS="$(printf '%s\n' "$PARSED_ROWS" | grep -c '.' || true)"
fi

echo
if [ "$OVERALL_FAIL" -ne 0 ]; then
  printf '%s%s FAIL%s — %d ok, %d pinned, %d advisory, %d fail. (%d active pins in version-pins.tsv)\n' \
    "$C_RED" "$GLYPH_FAIL" "$C_RESET" "$OK_COUNT" "$PIN_COUNT" "$WARN_COUNT" "$FAIL_COUNT" "$ACTIVE_PINS"
else
  printf '%s%s PASS%s — %d ok, %d pinned, %d advisory, %d fail. (%d active pins in version-pins.tsv)\n' \
    "$C_GREEN" "$GLYPH_OK" "$C_RESET" "$OK_COUNT" "$PIN_COUNT" "$WARN_COUNT" "$FAIL_COUNT" "$ACTIVE_PINS"
fi
printf '%severy file must match canonical; deviations live only as justified, temporary pins in tools/conformance/version-pins.tsv%s\n' \
  "$C_DIM" "$C_RESET"

exit "$OVERALL_FAIL"
