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
# It ALSO enforces the JS dependency CATALOG (the `catalog:` block in
# pnpm-workspace.yaml — the single declaration hub for versions meant to be
# uniform across workspaces, the JS arm of the One Version Rule). Once a dep is in
# the catalog, every workspace package.json that declares it MUST reference it as
# "catalog:" (or a named "catalog:<group>"), never a literal range — otherwise the
# version can silently drift back out of the hub. A literal-range declaration of a
# cataloged dep is a ✗; a catalog entry no workspace uses is a ✗ (dead config);
# and a dep declared in 2+ workspaces with differing ranges is a ⚠ advisory
# (a catalog candidate). See docs/dependency-versioning/javascript.md.
#
# It ALSO enforces MERGE-QUEUE required-check consistency (#458): every required
# status check that `repo_config` gates the merge queue on (its default
# `checks = []string{...}` list) MUST report in BOTH places a merge is gated:
#   1. the `merge_group` event — else GitHub wedges the queue "pending" forever
#      waiting on a check that never reports (a phantom/renamed check is a ✗); and
#   2. every `pull_request` — a required check whose workflow carries a workflow-
#      level `pull_request` `paths:`/`paths-ignore:` filter does NOT run (never
#      reports) on a PR outside those paths, so that PR can never become mergeable
#      (this wedged the whole repo once: promoting two path-filtered gates to
#      required blocked every docs/Go PR). That is a ✗ PR-BLOCKED — drop the
#      workflow-level paths filter and gate the WORK via a step instead.
# A matrix value that can't be confirmed for an existing merge_group job is a ⚠.
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
WORKSPACE_YAML="$ROOT/pnpm-workspace.yaml"
REPO_CONFIG_MAIN="$ROOT/infrastructure/pulumi/repo_config/main.go"
WORKFLOWS_DIR="$ROOT/.github/workflows"
TODAY="$(date +%Y-%m-%d)"

# Workspaces that build STANDALONE — their own `docker build <dir>` and/or a
# Copybara one-way mirror — have no monorepo pnpm-workspace.yaml at build time,
# so their package.json must resolve on its own and CANNOT use `catalog:`. They
# are exempt from catalog adherence: a concrete version is correct (⊘), and a
# `catalog:` reference is the FAILURE there (it breaks the standalone build —
# this is the oauth-user-inspector deploy regression #391 caused). Space-separated
# workspace directories.
CATALOG_EXEMPT="oauth-user-inspector"

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

# Dependency NAMES that live in the pnpm catalog — both the default `catalog:`
# block and any `catalogs:` named groups in pnpm-workspace.yaml. These are the
# deps whose version is declared once; every workspace must reference them as
# "catalog:" rather than a literal range.
catalog_names() {
  [ -f "$WORKSPACE_YAML" ] || return 0
  awk '
    # A column-0 key line decides whether the following indented block is a
    # catalog block (default `catalog:` or named `catalogs:`); any other
    # top-level key (e.g. packageExtensions:) turns extraction back off.
    /^[^[:space:]#]/ {
      incat = ($0 ~ /^catalog:[[:space:]]*$/ || $0 ~ /^catalogs:[[:space:]]*$/) ? 1 : 0
      next
    }
    # Inside a catalog block a dependency entry is "<indent>key: value" with a
    # non-empty value; a named-group header ("  react18:") has no value -> skip.
    incat && match($0, /:[[:space:]]*[^[:space:]]/) {
      key = $0
      sub(/:[[:space:]]*[^[:space:]].*$/, "", key)
      gsub(/^[[:space:]]+/, "", key)
      print key
    }
  ' "$WORKSPACE_YAML" | sed -e 's/["'"'"']//g' | LC_ALL=C sort -u
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
ROWS_CATALOG=""
ROWS_ADVISORY=""
ROWS_CAT_ADVISORY=""
ROWS_VIS=""
ROWS_MERGEQ=""
ROWS_SWEEP=""
ROWS_IAC=""

emit() {
  # $1 group-var-name  $2 glyph  $3 color  $4 file  $5 found  $6 canon  $7 note  $8 fix
  _row="$2${US}$3${US}$4${US}$5${US}$6${US}$7${US}${8:-}${RS}"
  case "$1" in
    go)           ROWS_GO="${ROWS_GO}${_row}" ;;
    node)         ROWS_NODE="${ROWS_NODE}${_row}" ;;
    pnpm)         ROWS_PNPM="${ROWS_PNPM}${_row}" ;;
    catalog)      ROWS_CATALOG="${ROWS_CATALOG}${_row}" ;;
    advisory)     ROWS_ADVISORY="${ROWS_ADVISORY}${_row}" ;;
    cat_advisory) ROWS_CAT_ADVISORY="${ROWS_CAT_ADVISORY}${_row}" ;;
    vis)          ROWS_VIS="${ROWS_VIS}${_row}" ;;
    mergeq)       ROWS_MERGEQ="${ROWS_MERGEQ}${_row}" ;;
    sweep)        ROWS_SWEEP="${ROWS_SWEEP}${_row}" ;;
    iac)          ROWS_IAC="${ROWS_IAC}${_row}" ;;
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
# CHECK: catalog adherence. Once a dependency is in the pnpm catalog, EVERY
# workspace package.json that declares it MUST reference it as "catalog:" (or a
# named "catalog:<group>"), never a literal range — otherwise the version can
# silently drift back out of the single declaration hub. A ✓ row is emitted for
# each correct reference, a ✗ for a literal-range bypass. CATALOG_NAMES_FILE holds
# the cataloged dep names (one per line), populated in MAIN.
#
# CATALOG_EXEMPT workspaces (standalone-built) invert the rule: a concrete
# version is correct (⊘ sanctioned) and a `catalog:` reference is the ✗, because
# catalog: cannot resolve without the monorepo workspace file at build time.
# ---------------------------------------------------------------------------
check_catalog() {
  [ -s "$CATALOG_NAMES_FILE" ] || return 0   # no catalog -> nothing to enforce
  _list="$(discover "package.json")"
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    _rel="$(rel "$pkg")"
    # Every cataloged-dep declaration in this file, as "name<TAB>value". The
    # name must equal a cataloged dep, so script lines like "test": "jest" (name
    # is "test") and a "jest": { ... } config object (value is not a string) are
    # not matched.
    _decls="$(
      awk '
        FNR==NR { if ($0 != "") iscat[$0]=1; next }
        match($0, /^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*"[^"]*"/) {
          name=$0; sub(/^[[:space:]]*"/,"",name); sub(/".*$/,"",name)
          val=$0;  sub(/^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*"/,"",val); sub(/".*$/,"",val)
          if (name in iscat) print name "\t" val
        }
      ' "$CATALOG_NAMES_FILE" "$pkg"
    )"
    [ -n "$_decls" ] || continue
    # Exempt (standalone-built) workspaces invert the rule.
    _ws="${_rel%%/*}"
    _exempt=0
    case " $CATALOG_EXEMPT " in *" $_ws "*) _exempt=1 ;; esac
    while IFS="$(printf '\t')" read -r dep val; do
      [ -n "$dep" ] || continue
      if [ "$_exempt" = "1" ]; then
        case "$val" in
          catalog:*)
            emit "catalog" "$GLYPH_FAIL" "$C_RED" "$_rel" "$val" "concrete" \
              "'$dep' uses catalog: but $_ws builds standalone (no workspace catalog at build time)" \
              "pin a concrete version of \"$dep\" in $_rel — catalog: cannot resolve in the standalone/Docker build"
            OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
          *)
            emit "catalog" "$GLYPH_PIN" "$C_CYAN" "$_rel" "$val" "concrete" \
              "exempt: $_ws builds standalone, so a concrete version is required (catalog: would break it)" ""
            PIN_COUNT=$((PIN_COUNT + 1)) ;;
        esac
        continue
      fi
      case "$val" in
        catalog:*)
          emit "catalog" "$GLYPH_OK" "$C_GREEN" "$_rel" "$val" "catalog:" "$dep" ""
          OK_COUNT=$((OK_COUNT + 1)) ;;
        *)
          emit "catalog" "$GLYPH_FAIL" "$C_RED" "$_rel" "$val" "catalog:" \
            "'$dep' is in the catalog but declared as a literal range here" \
            "set \"$dep\": \"catalog:\" in $_rel (or a named \"catalog:<group>\" for intentional divergence)"
          OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
      esac
    done <<EOF
$_decls
EOF
  done <<EOF
$_list
EOF
}

# ---------------------------------------------------------------------------
# CATALOG ORPHAN SWEEP. A catalog entry that NO workspace package.json declares
# is dead config -> ✗ (mirrors the stale-pin sweep). Keeps the catalog honest:
# it only carries deps actually in use.
# ---------------------------------------------------------------------------
catalog_orphan_sweep() {
  [ -s "$CATALOG_NAMES_FILE" ] || return 0
  _pkgs="$(discover "package.json" | tr '\n' ' ')"
  # Names declared by some package.json (any value), as a sorted unique list.
  _declared="$(
    awk '
      match($0, /^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*"[^"]*"/) {
        name=$0; sub(/^[[:space:]]*"/,"",name); sub(/".*$/,"",name); print name
      }
    ' $_pkgs 2>/dev/null | LC_ALL=C sort -u
  )"
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    if ! printf '%s\n' "$_declared" | grep -qx "$dep"; then
      emit "catalog" "$GLYPH_FAIL" "$C_RED" "pnpm-workspace.yaml" "(unused)" "" \
        "catalog entry '$dep' is declared by no workspace" \
        "remove '$dep' from the catalog in pnpm-workspace.yaml"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done < "$CATALOG_NAMES_FILE"
}

# ---------------------------------------------------------------------------
# ADVISORY (⚠, NEVER fails): a dependency NOT in the catalog that is declared by
# 2+ workspaces with 2+ distinct ranges. That divergence is exactly what the
# catalog exists to prevent -> surface it as a migration candidate. Only scans
# the dependency blocks (so a "scripts" entry can't masquerade as a dep).
# ---------------------------------------------------------------------------
advisory_catalog() {
  _pkgs="$(discover "package.json" | tr '\n' ' ')"
  _cands="$(
    awk '
      FNR==NR { if ($0 != "") iscat[$0]=1; next }
      FNR==1  { indeps=0 }
      /^[[:space:]]*"(dependencies|devDependencies|optionalDependencies|peerDependencies)"[[:space:]]*:[[:space:]]*\{/ { indeps=1; next }
      indeps && /^[[:space:]]*\}/ { indeps=0; next }
      indeps && match($0, /^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*"[^"]*"/) {
        name=$0; sub(/^[[:space:]]*"/,"",name); sub(/".*$/,"",name)
        val=$0;  sub(/^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*"/,"",val); sub(/".*$/,"",val)
        if (name in iscat) next
        if (val ~ /^(workspace:|catalog:)/) next
        pk = name SUBSEP val
        if (!(pk in seenpair)) { seenpair[pk]=1; rcount[name]++; rlist[name]=rlist[name] (rlist[name]==""?"":", ") val }
        fk = name SUBSEP FILENAME
        if (!(fk in seenfile)) { seenfile[fk]=1; fcount[name]++ }
      }
      END { for (nm in rcount) if (rcount[nm] >= 2 && fcount[nm] >= 2) print nm "\t" rlist[nm] }
    ' "$CATALOG_NAMES_FILE" $_pkgs 2>/dev/null | LC_ALL=C sort
  )"
  [ -n "$_cands" ] || return 0
  while IFS="$(printf '\t')" read -r dep ranges; do
    [ -n "$dep" ] || continue
    emit "cat_advisory" "$GLYPH_WARN" "$C_YELLOW" "$dep" "" "" \
      "declared in 2+ workspaces with differing ranges: $ranges" \
      "converge and add '$dep' to the catalog (or a named catalog if the split is intentional)"
    WARN_COUNT=$((WARN_COUNT + 1))
  done <<EOF
$_cands
EOF
}

# ---------------------------------------------------------------------------
# CHECK: merge-queue required-check name consistency (#458 / §7.1-E).
#
# repo_config/main.go declares the merge-queue ruleset's REQUIRED status checks
# (the default `checks = []string{...}` gate set). GitHub wedges the queue
# "pending" forever if a required check NAME doesn't match a job that actually
# reports on the `merge_group` event — a rename on either side is a silent trap.
# This asserts every required check is produced by some job in a workflow that
# triggers on merge_group:
#   ✓  exact match to a producible context
#   ⚠  base job runs on merge_group but the matrix value is unconfirmed (advisory)
#   ✗  no merge_group job produces this check (the queue would wedge) — fail
# The producible set is parsed from the workflows: a job's context is its `name:`
# (or job-id), with single-dimension matrices (inline `[a,b]` or block list)
# expanded to "<base> (<value>)". POSIX awk only; single-dim matrices.
# ---------------------------------------------------------------------------
check_merge_queue() {
  [ -f "$REPO_CONFIG_MAIN" ] || return 0
  [ -d "$WORKFLOWS_DIR" ] || return 0

  # Required-check names: the quoted strings in the default `checks = []string{...}`.
  required="$(awk '
    /checks = \[\]string\{/ { grab=1 }
    grab {
      s=$0
      while (match(s, /"[^"]*"/)) { print substr(s, RSTART+1, RLENGTH-2); s=substr(s, RSTART+RLENGTH) }
      if (index($0,"}")>0) exit
    }' "$REPO_CONFIG_MAIN")"
  [ -n "$required" ] || return 0   # no declared gate set -> nothing to assert

  # Producible check contexts across every workflow triggering on merge_group,
  # each tagged <context>\t<pr_paths> where pr_paths=1 iff that workflow's
  # `pull_request` trigger carries a workflow-level `paths:`/`paths-ignore:`
  # filter. A required check whose workflow is pr-paths-filtered does NOT report
  # on a PR outside those paths, which blocks that PR from becoming mergeable —
  # a different wedge from the merge_group one, so we detect both.
  producible_raw="$(
    for wf in "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml; do
      [ -f "$wf" ] || continue
      awk '
        BEGIN{in_on=0;has_mg=0;in_pr=0;pr_paths=0;in_jobs=0;jobid="";jobname="";nvals=0;cb=0;nout=0}
        function strip(s){gsub(/^[ \t]+|[ \t\r]+$/,"",s);return s}
        function unq(s){gsub(/^[\047"]+|[\047"]+$/,"",s);return s}
        function ind(l,  i){i=0;while(substr(l,i+1,1)==" ")i++;return i}
        function flush(  i,disp){
          if(jobid=="")return
          disp=(jobname!=""?jobname:jobid)
          if(nvals>0){for(i=1;i<=nvals;i++)out[++nout]=disp" ("vals[i]")"}else out[++nout]=disp
          jobid="";jobname="";nvals=0;cb=0}
        {line=$0;sub(/\r$/,"",line);I=ind(line);k=strip(line)}
        /^on:[ \t]*\[/{if(line ~ /merge_group/)has_mg=1}
        /^on:[ \t]*$/{in_on=1;next}
        in_on==1{
          if(I==0&&k!=""){in_on=0;in_pr=0}
          else{
            if(k ~ /^merge_group:/)has_mg=1
            if(I==2&&k ~ /^pull_request:/)in_pr=1
            else if(I<=2&&k!=""&&k !~ /^pull_request:/)in_pr=0
            if(in_pr==1&&I>=4&&(k ~ /^paths:/||k ~ /^paths-ignore:/))pr_paths=1
          }
        }
        /^jobs:[ \t]*$/{in_jobs=1;next}
        in_jobs==1&&I==0&&k!=""&&k !~ /^#/{flush();in_jobs=0}
        in_jobs==1{
          if(I==2&&k ~ /:$/&&k !~ /^#/){flush();j=k;sub(/:.*$/,"",j);jobid=strip(j);next}
          if(I==4&&k ~ /^name:/){v=k;sub(/^name:[ \t]*/,"",v);jobname=unq(strip(v));next}
          if(I==8&&k ~ /:[ \t]*\[/){lv=k;sub(/^[^:]*:[ \t]*\[/,"",lv);sub(/\].*$/,"",lv);n=split(lv,a,",");for(i=1;i<=n;i++){x=unq(strip(a[i]));if(x!="")vals[++nvals]=x};next}
          if(I==8&&k ~ /:$/&&k !~ /^(include|exclude):$/){cb=1;next}
          if(cb==1){if(I>=10&&k ~ /^-[ \t]*/){x=k;sub(/^-[ \t]*/,"",x);x=unq(strip(x));if(x!="")vals[++nvals]=x;next}else if(k!="")cb=0}
        }
        END{flush();if(!has_mg)exit 3;for(i=1;i<=nout;i++)print out[i] "\t" pr_paths}
      ' "$wf" 2>/dev/null
    done | LC_ALL=C sort -u
  )"
  producible="$(printf '%s\n' "$producible_raw" | awk -F'\t' 'NF{print $1}' | LC_ALL=C sort -u)"
  # Bases (matrix suffix stripped) whose workflow has a pull_request paths filter.
  prpaths_bases="$(printf '%s\n' "$producible_raw" | awk -F'\t' '$2==1{c=$1;sub(/ \(.*\)$/,"",c);print c}' | LC_ALL=C sort -u)"

  # Fail LOUD (not 10 confusing MISSING rows) if extraction yielded nothing while
  # a gate set is declared — means the workflows or this parser changed.
  if [ -z "$producible" ]; then
    emit "mergeq" "$GLYPH_FAIL" "$C_RED" "(all)" "required" "MISSING" \
      "extracted 0 merge_group check contexts from .github/workflows — workflows or parser changed" \
      "confirm ci.yaml/tidy-check.yaml/conformance-check.yaml still trigger on merge_group with the expected jobs"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); return
  fi

  # Bases = producible contexts with any " (value)" suffix stripped.
  bases="$(printf '%s\n' "$producible" | sed 's/ (.*)$//' | LC_ALL=C sort -u)"

  while IFS= read -r rc; do
    [ -n "$rc" ] || continue
    if printf '%s\n' "$producible" | grep -qxF "$rc"; then
      rcbase="$(printf '%s' "$rc" | sed 's/ (.*)$//')"
      if printf '%s\n' "$prpaths_bases" | grep -qxF "$rcbase"; then
        # Reports on merge_group, but its workflow won't report on PRs outside
        # its pull_request `paths:` — so any such PR can never become mergeable.
        emit "mergeq" "$GLYPH_FAIL" "$C_RED" "$rc" "required" "PR-BLOCKED" \
          "workflow has a pull_request 'paths:' filter, so this required check does NOT report on PRs outside those paths — wedging their mergeability" \
          "drop the workflow-level pull_request 'paths:' filter (gate the WORK via a step instead) so the check always reports"
        OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
      else
        emit "mergeq" "$GLYPH_OK" "$C_GREEN" "$rc" "required" "producible" "reports on merge_group + every PR" ""
        OK_COUNT=$((OK_COUNT + 1))
      fi
    else
      rcbase="$(printf '%s' "$rc" | sed 's/ (.*)$//')"
      if [ "$rcbase" != "$rc" ] && printf '%s\n' "$bases" | grep -qxF "$rcbase"; then
        emit "mergeq" "$GLYPH_WARN" "$C_YELLOW" "$rc" "required" "job ok" \
          "job '$rcbase' runs on merge_group but its matrix value is unconfirmed — verify the matrix still emits this context" ""
        WARN_COUNT=$((WARN_COUNT + 1))
      else
        emit "mergeq" "$GLYPH_FAIL" "$C_RED" "$rc" "required" "MISSING" \
          "no job produces this required check on the merge_group event — the queue will wedge pending" \
          "align repo_config/main.go's required-check list or the workflow job name so they match"
        OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    fi
  done <<EOF
$required
EOF
}

# ---------------------------------------------------------------------------
# Scheduled full-sweep backstop pairing. ci.yaml's merge_group / push lanes
# build only AFFECTED targets (target-determinator); that demotion from the old
# unconditional per-merge //... sweep is safe ONLY while a scheduled whole-graph
# sweep exists to catch under-attributed changes (e.g. an empty affected set
# for a touched-but-unreferenced data file). This check makes the pairing
# structural: deleting periodic-full-sweep.yaml, dropping its `schedule:`, or
# narrowing it below //... FAILS conformance. Enforced unconditionally — the
# repo has adopted affected-scoped merges, and a scheduled sweep is harmless
# even if a lane is later reverted to a full sweep.
# ---------------------------------------------------------------------------
check_sweep_backstop() {
  sweep="$WORKFLOWS_DIR/periodic-full-sweep.yaml"
  sweep_rel=".github/workflows/periodic-full-sweep.yaml"

  if [ ! -f "$sweep" ]; then
    emit "sweep" "$GLYPH_FAIL" "$C_RED" "$sweep_rel" "missing" "scheduled //... sweep" \
      "ci.yaml merge_group/push lanes are affected-scoped but the whole-graph backstop workflow is gone" \
      "restore periodic-full-sweep.yaml (scheduled full bazel build+test //...) or revert the lanes to unconditional full sweeps"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); return
  fi

  ok=1
  # A real cron schedule: a `schedule:` block with a `- cron:` entry under it.
  if ! grep -E '^[[:space:]]*schedule:' "$sweep" >/dev/null 2>&1 \
     || ! grep -E '^[[:space:]]*-[[:space:]]*cron:' "$sweep" >/dev/null 2>&1; then
    emit "sweep" "$GLYPH_FAIL" "$C_RED" "$sweep_rel" "no schedule" "cron schedule" \
      "the backstop workflow exists but has no schedule/cron trigger — it would never run on its own" \
      "restore the schedule: cron trigger (nightly) in periodic-full-sweep.yaml"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
  fi
  # Whole-graph scope: both a bazel build and a bazel test over //... .
  if ! grep -E 'bazel[[:space:]]+build[[:space:]].*//\.\.\.' "$sweep" >/dev/null 2>&1 \
     || ! grep -E 'bazel[[:space:]]+test[[:space:]].*//\.\.\.' "$sweep" >/dev/null 2>&1; then
    emit "sweep" "$GLYPH_FAIL" "$C_RED" "$sweep_rel" "narrowed" "build+test //..." \
      "the backstop workflow no longer builds AND tests the whole //... graph" \
      "keep both 'bazel build //...' and 'bazel test //...' in periodic-full-sweep.yaml"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    emit "sweep" "$GLYPH_OK" "$C_GREEN" "$sweep_rel" "scheduled" "build+test //..." \
      "whole-graph backstop present — affected-scoped merge_group/push lanes are covered" ""
    OK_COUNT=$((OK_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# App visibility firewall (#82). Inter-app isolation rests on two invariants:
#   1. every app root BUILD declares
#      package(default_visibility = ["//<app>:__subpackages__"]), and
#   2. NO target inside an app is "//visibility:public" unless it is a
#      justified, reviewed exception in tools/conformance/public-targets.tsv
#      (format: <BUILD-file-path>\t<target>\t<justification>).
# Rationale: `bazel run`/`bazel build <label>` from the CLI, workflows, and
# GoReleaser ignores visibility (it gates dependency EDGES only), so app
# "products" (binaries, images, published packages) need no public visibility.
# The only legitimate public targets are ones with GENERATED cross-app
# consumers (e.g. pnpm workspace packages, whose rules_js store links dep on
# them from the repo-root package). Widening the public surface must therefore
# be a deliberate allowlist edit reviewed by the platform team, never a silent
# BUILD change. A stale allowlist row (target no longer public) is a ✗ so dead
# exceptions get cleaned up, mirroring the version-pins policy.
# ---------------------------------------------------------------------------
PUBLIC_ALLOWLIST="$ROOT/tools/conformance/public-targets.tsv"
APP_DIRS="tabula devx homelab mcp-slack nexus-agent oauth-user-inspector"

check_app_visibility() {
  # --- 1. root boundary declaration per app. --------------------------------
  for app in $APP_DIRS; do
    rootbuild=""
    for cand in "$ROOT/$app/BUILD" "$ROOT/$app/BUILD.bazel"; do
      if [ -f "$cand" ]; then rootbuild="$cand"; break; fi
    done
    if [ -z "$rootbuild" ] || ! grep -F "package(default_visibility = [\"//$app:__subpackages__\"])" "$rootbuild" >/dev/null 2>&1; then
      emit "vis" "$GLYPH_FAIL" "$C_RED" "$app/BUILD" "no boundary" "app-scoped default" \
        "app root BUILD does not declare the inter-app boundary (#82)" \
        "add package(default_visibility = [\"//$app:__subpackages__\"]) to $app/BUILD"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    else
      emit "vis" "$GLYPH_OK" "$C_GREEN" "$app/BUILD" "boundary" "app-scoped default" \
        "package default_visibility scopes to //$app:__subpackages__" ""
      OK_COUNT=$((OK_COUNT + 1))
    fi
  done

  # --- 2. public targets inside apps must be allowlisted. -------------------
  # Collect "<relpath>\t<target>" for every literal "//visibility:public"
  # inside an app BUILD file (nearest preceding `name = "..."` names the
  # target; a package(default_visibility=public) would surface with an empty
  # target name and correctly fail as unlisted).
  # The awk program lives OUTSIDE the $(...) below: macOS /bin/bash 3.2's
  # command-substitution parser naively counts parentheses even inside
  # single-quoted strings, so the unbalanced "(" in the package\( pattern
  # would be a syntax error if it appeared inside the substitution. A
  # package() statement resets the attribution so a package-level public
  # default is never blamed on the previous rule's name.
  vis_awk='
    /^package\(/ { n = "(package default)" }
    /name = "/ { n = $0; sub(/.*name = "/, "", n); sub(/".*/, "", n) }
    /"\/\/visibility:public"/ { print f "\t" n }
  '
  found_public="$(
    for app in $APP_DIRS; do
      find "$ROOT/$app" \( -name BUILD -o -name BUILD.bazel \) \
        -not -path "*/node_modules/*" -not -path "*/bazel-*" 2>/dev/null \
        | LC_ALL=C sort | while IFS= read -r bf; do
            rel="${bf#"$ROOT"/}"
            awk -v f="$rel" "$vis_awk" "$bf"
          done
    done
  )"

  seen_keys=""
  if [ -n "$found_public" ]; then
    while IFS="$(printf '\t')" read -r pfile ptarget; do
      [ -n "$pfile" ] || continue
      key="$pfile:$ptarget"
      seen_keys="$seen_keys$key
"
      just=""
      if [ -f "$PUBLIC_ALLOWLIST" ]; then
        just="$(awk -F'\t' -v f="$pfile" -v t="$ptarget" \
          '!/^#/ && $1 == f && $2 == t { print $3; exit }' "$PUBLIC_ALLOWLIST")"
      fi
      if [ -n "$just" ]; then
        emit "vis" "$GLYPH_PIN" "$C_YELLOW" "$pfile" ":$ptarget" "allowlisted public" "$just" ""
        PIN_COUNT=$((PIN_COUNT + 1))
      else
        emit "vis" "$GLYPH_FAIL" "$C_RED" "$pfile" ":$ptarget" "app-internal" \
          "//visibility:public inside an app without an allowlist entry -- the inter-app firewall (#82) has a hole" \
          "narrow to //<app>:__subpackages__ (CLI/workflow 'bazel run|build <label>' needs no visibility), or add a justified row to tools/conformance/public-targets.tsv"
        OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    done <<EOF
$found_public
EOF
  fi

  # --- 3. stale allowlist rows (listed but no longer public) are failures. --
  if [ -f "$PUBLIC_ALLOWLIST" ]; then
    while IFS="$(printf '\t')" read -r afile atarget ajust; do
      case "$afile" in ''|'#'*) continue ;; esac
      if ! printf '%s' "$seen_keys" | grep -qxF "$afile:$atarget"; then
        emit "vis" "$GLYPH_FAIL" "$C_RED" "$afile" ":$atarget" "allowlist row" \
          "allowlisted target is no longer //visibility:public (or moved) -- stale exception" \
          "remove the row from tools/conformance/public-targets.tsv"
        OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    done < "$PUBLIC_ALLOWLIST"
  fi
}

# ---------------------------------------------------------------------------
# IaC destructive-import guard (#499). The pulumiverse/zitadel provider marks
# several ApplicationOidc fields replace-triggering, and import does NOT
# populate them — so `pulumi.Import` of a zitadel OIDC app plans a REPLACEMENT
# that deletes the LIVE client (2026-06-26 incident: hosted login broke with
# Errors.App.NotFound; recovery runbook in PR #310). The zitadel-apps stack
# must CREATE and own its apps, never adopt them. This guard fails conformance
# on any pulumi.Import usage in that stack. Scoped to zitadel-apps only:
# repo_config's imports (repo, variables, branch protection) are the correct
# brownfield-adoption pattern for the GitHub provider and stay allowed.
# ---------------------------------------------------------------------------
check_zitadel_import() {
  zdir="$ROOT/infrastructure/pulumi/zitadel-apps"
  [ -d "$zdir" ] || return 0
  hits="$(grep -rn 'pulumi\.Import(' "$zdir" --include='*.go' 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    # Heredoc (not a pipe) so emit/counter mutations happen in THIS shell.
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      hitfile="${line%%:*}"
      hitline="$(printf '%s' "$line" | cut -d: -f2)"
      emit "iac" "$GLYPH_FAIL" "$C_RED" "${hitfile#"$ROOT"/}:$hitline" "pulumi.Import" "create-only" \
        "importing a zitadel ApplicationOidc force-replaces and DELETES the live OIDC client (PR #310 incident)" \
        "remove the pulumi.Import option -- the zitadel-apps stack must CREATE and own its apps"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    done <<EOF
$hits
EOF
  else
    emit "iac" "$GLYPH_OK" "$C_GREEN" "infrastructure/pulumi/zitadel-apps" "no imports" "create-only" \
      "zitadel-apps creates and owns its OIDC apps (no destructive adopt)" ""
    OK_COUNT=$((OK_COUNT + 1))
  fi
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

# Cataloged dep names (default + named catalogs) used by the catalog checks.
# Built once; removed at the end of MAIN.
CATALOG_NAMES_FILE="$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/conf-catnames.$$")"
catalog_names > "$CATALOG_NAMES_FILE" 2>/dev/null || true

check_go
check_node
check_pnpm
stale_sweep
doc_sync
advisory_pnpm
check_catalog
catalog_orphan_sweep
advisory_catalog
check_app_visibility
check_merge_queue
check_sweep_backstop
check_zitadel_import

echo
printf '%s%sconformance%s — %s\n' "$C_BOLD" "$C_GREEN" "$C_RESET" "vitruvian-core version conformance"
printf '%scanonical: go %s (go.work) · node %s (.nvmrc) · pnpm %s (package.json)%s\n' \
  "$C_DIM" "$(canonical_go)" "$(canonical_node)" "$(canonical_pnpm)" "$C_RESET"

print_group "Go (go.mod → go.work)" "$ROWS_GO"
print_group "Node (Dockerfile FROM node → .nvmrc major)" "$ROWS_NODE"
print_group "pnpm (package.json packageManager → root)" "$ROWS_PNPM"
print_group "Catalog (package.json → pnpm-workspace.yaml catalog)" "$ROWS_CATALOG"
print_group "App visibility firewall (#82: app-scoped defaults + public allowlist)" "$ROWS_VIS"
print_group "Merge-queue required checks (repo_config → workflow merge_group jobs)" "$ROWS_MERGEQ"
print_group "Full-sweep backstop (affected-scoped lanes → scheduled //... sweep)" "$ROWS_SWEEP"
print_group "IaC destructive-import guard (zitadel-apps must create, never import)" "$ROWS_IAC"
print_group "Advisory — pnpm Dockerfile without a packageManager pin" "$ROWS_ADVISORY"
print_group "Advisory — shared deps not in the catalog (drift candidates)" "$ROWS_CAT_ADVISORY"

rm -f "$CATALOG_NAMES_FILE"

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
