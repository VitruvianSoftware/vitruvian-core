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
# It ALSO enforces POSTSUBMIT CONCURRENCY KEYING: a workflow that gates main
# (triggers on both `push: branches: [main]` and `merge_group`) must key its
# non-PR runs on `github.sha`. A `github.ref`-keyed (or constant) group puts
# every push-to-main run in ONE group, and GitHub evicts an already-PENDING run
# there when a newer one queues — so a burst of merges lands commits on main
# with no verdict at all, regardless of `cancel-in-progress`.
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
REPO_CONFIG_MAIN="$ROOT/infrastructure/pulumi/platform/repo_config/main.go"
WORKFLOWS_DIR="$ROOT/.github/workflows"
TODAY="$(date +%Y-%m-%d)"

# Workspaces that build STANDALONE — their own `docker build <dir>` and/or a
# Copybara one-way mirror — have no monorepo pnpm-workspace.yaml at build time,
# so their package.json must resolve on its own and CANNOT use `catalog:`. They
# are exempt from catalog adherence: a concrete version is correct (⊘), and a
# `catalog:` reference is the FAILURE there (it breaks the standalone build —
# this is the oauth-user-inspector deploy regression #391 caused). Space-separated
# entries — a top-level workspace dir, or a deeper path prefix for a standalone
# artifact nested inside another tree (e.g. a CrossGuard policy pack that runs
# its own `npm install` at `pulumi preview` time).
CATALOG_EXEMPT="oauth-user-inspector pulumi/examples/go-foundation/policy-library pulumi/examples/ts-foundation"

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
ROWS_CONCUR=""
ROWS_TIMEOUT=""
ROWS_SWEEP=""
ROWS_IAC=""
ROWS_META=""
ROWS_COPYBARA=""
ROWS_RELEASE=""
ROWS_LOCALPATH=""
ROWS_GATE=""
ROWS_DURABLE=""
ROWS_PULUMI=""

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
    concur)       ROWS_CONCUR="${ROWS_CONCUR}${_row}" ;;
    timeout)      ROWS_TIMEOUT="${ROWS_TIMEOUT}${_row}" ;;
    sweep)        ROWS_SWEEP="${ROWS_SWEEP}${_row}" ;;
    iac)          ROWS_IAC="${ROWS_IAC}${_row}" ;;
    meta)         ROWS_META="${ROWS_META}${_row}" ;;
    copybara)     ROWS_COPYBARA="${ROWS_COPYBARA}${_row}" ;;
    release)      ROWS_RELEASE="${ROWS_RELEASE}${_row}" ;;
    localpath)    ROWS_LOCALPATH="${ROWS_LOCALPATH}${_row}" ;;
    gate)         ROWS_GATE="${ROWS_GATE}${_row}" ;;
    durable)      ROWS_DURABLE="${ROWS_DURABLE}${_row}" ;;
    pulumi)       ROWS_PULUMI="${ROWS_PULUMI}${_row}" ;;
    # An unrouted group silently DISCARDS its rows: the check still increments
    # FAIL_COUNT, so the run fails with a number and no explanation of what
    # broke. That is what `pulumi` did -- check_pulumi_project_names (the
    # duplicate-stack-name guard) could only ever report an unattributed "1
    # fail". Fail loudly instead of losing the row.
    *)
      printf 'conformance: internal error - emit() has no bucket for group %s\n' "$1" >&2
      OVERALL_FAIL=1
      ;;
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
    # Exempt (standalone-built) workspaces invert the rule. Match a top-level
    # dir (first path segment) or a deeper path-prefix entry (nested artifact).
    _ws="${_rel%%/*}"
    _exempt=0
    case " $CATALOG_EXEMPT " in *" $_ws "*) _exempt=1 ;; esac
    for _ex in $CATALOG_EXEMPT; do
      case "$_rel" in "$_ex"/*) _exempt=1; _ws="$_ex" ;; esac
    done
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
  #
  # Comments are stripped FIRST. The list is heavily commented, and a naive
  # scrape treats a double-quoted word inside a `//` comment as a required check
  # name -- which then reports as MISSING and fails this guard with a phantom
  # entry that exists nowhere in repo_config. (Writing `wedge a PR "pending"` in
  # a comment there really did invent a required check called `pending`.)
  # strip_comment is quote-aware so a `//` inside a string literal survives.
  required="$(awk '
    function strip_comment(line,   i, inq, c) {
      inq = 0
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "\"") { inq = !inq; continue }
        if (!inq && c == "/" && substr(line, i + 1, 1) == "/") return substr(line, 1, i - 1)
      }
      return line
    }
    /checks = \[\]string\{/ { grab=1 }
    grab {
      s = strip_comment($0)
      while (match(s, /"[^"]*"/)) { print substr(s, RSTART+1, RLENGTH-2); s=substr(s, RSTART+RLENGTH) }
      if (index(s,"}")>0) exit
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
# Postsubmit concurrency keying. A verification workflow that gates main (it
# triggers on BOTH `push: branches: [main]` and `merge_group`) must give every
# pushed commit its OWN concurrency group, or its postsubmit verdict can be
# thrown away.
#
# `cancel-in-progress: false` (or `== 'pull_request'`) does NOT achieve that on
# its own: GitHub additionally cancels an already-PENDING run in a group when a
# newer one queues behind the running one. A group keyed only on `github.ref`
# puts every push-to-main run into ONE group, so a burst of merges silently
# evicts the middle commits' runs — they land on main with no verdict. Seen for
# real on fb3859bd (2026-07-28) and 322f7ea7 (2026-07-29) before the sha-keyed
# fix; the same trap cost tabula-e2e its postsubmit lane in #1311.
#
# The rule is textual and deliberately loose: a group that mentions
# `github.ref` MUST also mention `github.sha`, so the non-PR events fall back to
# a per-commit key. It does not constrain the PR lane (superseding a PR's own
# older run is wanted) and it does not touch deploy/preview workflows, which do
# not carry the push+merge_group verification signature.
# ---------------------------------------------------------------------------
check_postsubmit_concurrency() {
  found_any=0
  for wf in "$WORKFLOWS_DIR"/*.yaml "$WORKFLOWS_DIR"/*.yml; do
    [ -f "$wf" ] || continue
    wf_rel=".github/workflows$(printf '%s' "${wf##*/}" | sed 's|^|/|')"

    # Verification signature: `push:` restricted to main AND a `merge_group:`
    # trigger. Parsed with awk over the top-level `on:` block only, so a
    # `merge_group` mention in a comment or a job body cannot fake it.
    sig="$(awk '
      /^on:[ \t]*$/            { in_on=1; next }
      in_on && /^[A-Za-z_]/    { in_on=0 }
      in_on && /^[ \t]*#/      { next }
      in_on && /^  merge_group:/ { mg=1 }
      in_on && /^  push:/      { in_push=1; next }
      in_on && in_push && /^  [A-Za-z_]/ { in_push=0 }
      in_on && in_push && /branches:.*main/ { pushmain=1 }
      END { if (mg && pushmain) print "yes" }
    ' "$wf")"
    [ "$sig" = "yes" ] || continue
    found_any=$((found_any + 1))

    group="$(awk '
      /^concurrency:[ \t]*$/ { in_c=1; next }
      in_c && /^[A-Za-z_]/   { in_c=0 }
      in_c && /^[ \t]*group:/ { sub(/^[ \t]*group:[ \t]*/, ""); print; exit }
    ' "$wf")"

    if [ -z "$group" ]; then
      # No concurrency block at all is safe: every run gets its own lane.
      emit "concur" "$GLYPH_OK" "$C_GREEN" "$wf_rel" "none" "per-commit" \
        "no concurrency group — every push/merge_group run keeps its verdict" ""
      OK_COUNT=$((OK_COUNT + 1)); continue
    fi

    case "$group" in
      *github.ref*)
        case "$group" in
          *github.sha*)
            emit "concur" "$GLYPH_OK" "$C_GREEN" "$wf_rel" "ref+sha" "per-commit" \
              "PR lane supersedes by ref; push/merge_group key on sha" ""
            OK_COUNT=$((OK_COUNT + 1)) ;;
          *)
            emit "concur" "$GLYPH_FAIL" "$C_RED" "$wf_rel" "ref-only" "per-commit" \
              "every push-to-main run shares one group — a merge burst evicts the middle commits' PENDING runs, landing them with no verdict" \
              "key non-PR events on the commit: group: \${{ github.workflow }}-\${{ github.event_name }}-\${{ github.event_name == 'pull_request' && github.ref || github.sha }}"
            OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        esac ;;
      *)
        # A constant group serializes ALL pushes into one lane — same eviction.
        case "$group" in
          *github.sha*)
            emit "concur" "$GLYPH_OK" "$C_GREEN" "$wf_rel" "sha" "per-commit" \
              "keyed on the commit — no cross-commit eviction" ""
            OK_COUNT=$((OK_COUNT + 1)) ;;
          *)
            emit "concur" "$GLYPH_FAIL" "$C_RED" "$wf_rel" "constant" "per-commit" \
              "a constant group serializes every run into one lane — queued runs get evicted by newer ones" \
              "key non-PR events on the commit (add \${{ github.sha }} to the group)"
            OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        esac ;;
    esac
  done

  # A zero-match sweep means the parser (or the workflow layout) drifted, not
  # that the repo suddenly has no main-gating workflows. Fail loudly.
  if [ "$found_any" -eq 0 ]; then
    emit "concur" "$GLYPH_FAIL" "$C_RED" ".github/workflows" "0 matched" ">=1" \
      "no workflow matched the push-to-main + merge_group signature — the parser or the workflow layout changed" \
      "confirm ci.yaml still triggers on both 'push: branches: [main]' and 'merge_group:'"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# CHECK: every workflow job declares `timeout-minutes` (#209 / epic #200).
#
# A job without `timeout-minutes` inherits GitHub's default of 360 MINUTES. A
# hung step (a wedged network call, a prompt nobody answers, a deadlocked test)
# therefore holds a runner for six hours instead of failing fast — pure wasted
# compute, and on a serialized lane it blocks every queued run behind it.
#
# #209 set explicit timeouts across all ~59 workflows, but nothing ENFORCED it,
# so the invariant decayed the moment a new workflow was added: renovate.yaml
# (#1344) shipped the repo's only unbounded job one day after landing. This
# closes that loop — the rule now fails CI instead of relying on review.
#
# A job that only delegates (`uses:` a reusable workflow) is EXEMPT: the timeout
# belongs to the callee's own jobs, and `timeout-minutes` is not even a valid key
# on a workflow-call job. Parsed with POSIX awk over the `jobs:` block, keyed on
# indentation (job ids at 2, job keys at 4), so a `timeout-minutes` inside a
# step's `with:` block can't satisfy the job-level requirement.
# ---------------------------------------------------------------------------
check_job_timeouts() {
  [ -d "$WORKFLOWS_DIR" ] || return 0
  seen_jobs=0
  for wf in "$WORKFLOWS_DIR"/*.yaml "$WORKFLOWS_DIR"/*.yml; do
    [ -f "$wf" ] || continue
    wf_rel=".github/workflows/${wf##*/}"

    # Emits "<jobid>\t<has_timeout>\t<is_call>" for every job in the workflow.
    #
    # Indentation is DISCOVERED, never assumed: this repo mixes 2-space and
    # 4-space workflow styles (the copybara/dependabot lanes indent by 4), so a
    # hardcoded "job ids at column 2" parser silently skips those files and the
    # whole check passes vacuously for them. `jobind` is taken from the first job
    # entry and `keyind` from the first key inside each job, so a job-level
    # `timeout-minutes` is distinguished from one nested in a step's `with:`
    # regardless of the file's indent width.
    jobs_report="$(awk '
      function ind(l,  i){i=0;while(substr(l,i+1,1)==" ")i++;return i}
      function flush(){ if(jobid!="") print jobid "\t" to "\t" call; jobid="";to=0;call=0;keyind=-1 }
      BEGIN { jobind=-1; keyind=-1 }
      { line=$0; sub(/\r$/,"",line); I=ind(line) }
      /^jobs:[ \t]*$/ { in_jobs=1; next }
      !in_jobs { next }
      line ~ /^[ \t]*#/ { next }
      line !~ /[^ \t]/  { next }
      # A new top-level key ends the jobs block.
      I==0 { flush(); in_jobs=0; next }
      # First entry under `jobs:` fixes the job-id indent for this file.
      jobind<0 { jobind=I }
      # Job id: a bare "<name>:" at the job-id indent.
      I==jobind && line ~ /^[ ]*[A-Za-z0-9_.-]+:[ \t]*$/ {
        flush(); jobid=line; sub(/^[ ]*/,"",jobid); sub(/:[ \t]*$/,"",jobid); next
      }
      jobid=="" { next }
      # First key inside this job fixes the job-level key indent.
      keyind<0 && I>jobind { keyind=I }
      I==keyind && line ~ /^[ ]*timeout-minutes:/ { to=1; next }
      I==keyind && line ~ /^[ ]*uses:/            { call=1; next }
      END { flush() }
    ' "$wf")"

    [ -n "$jobs_report" ] || continue
    printf '%s\n' "$jobs_report" | while IFS="$(printf '\t')" read -r jid has_to is_call; do
      [ -n "$jid" ] || continue
      printf 'x\n' >>"$TIMEOUT_TALLY"
      [ "$is_call" = "1" ] && continue
      [ "$has_to" = "1" ] && continue
      printf '%s\t%s\n' "$wf_rel" "$jid" >>"$TIMEOUT_MISSING"
    done
  done

  seen_jobs="$(wc -l <"$TIMEOUT_TALLY" 2>/dev/null | tr -d ' ')"
  [ -n "$seen_jobs" ] || seen_jobs=0

  if [ -s "$TIMEOUT_MISSING" ]; then
    while IFS="$(printf '\t')" read -r wfr jid; do
      [ -n "$wfr" ] || continue
      emit "timeout" "$GLYPH_FAIL" "$C_RED" "$wfr" "$jid" "timeout-minutes" \
        "job has no timeout-minutes — it inherits GitHub's 360-minute default, so a hung step burns a runner for 6h" \
        "add a 'timeout-minutes:' to the '$jid' job sized to its normal runtime plus headroom"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    done <"$TIMEOUT_MISSING"
  fi

  # A zero-job sweep means the parser (or the workflow layout) drifted, not that
  # the repo suddenly has no jobs. Fail loudly rather than pass vacuously.
  if [ "$seen_jobs" -eq 0 ]; then
    emit "timeout" "$GLYPH_FAIL" "$C_RED" ".github/workflows" "0 jobs" ">=1" \
      "no workflow jobs parsed — the parser or the workflow layout changed" \
      "confirm .github/workflows/*.yaml still declare jobs under a top-level 'jobs:' key"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
  elif [ ! -s "$TIMEOUT_MISSING" ]; then
    emit "timeout" "$GLYPH_OK" "$C_GREEN" ".github/workflows" "$seen_jobs jobs" "all bounded" \
      "every non-delegating job declares timeout-minutes" ""
    OK_COUNT=$((OK_COUNT + 1))
  fi
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
  zdir="$ROOT/infrastructure/pulumi/platform/zitadel-apps"
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
    emit "iac" "$GLYPH_OK" "$C_GREEN" "infrastructure/pulumi/platform/zitadel-apps" "no imports" "create-only" \
      "zitadel-apps creates and owns its OIDC apps (no destructive adopt)" ""
    OK_COUNT=$((OK_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# Copybara infra-leak guard. Every publicly-mirrored component subtree (the
# components in tools/copybara/copy.bara.sky) may co-locate its PER-APP Pulumi
# deployment stacks under `<app>/infra/` (repo-wide convention). Those stacks
# carry internal GCP details (project ids, service accounts, WIF wiring) that
# must NEVER reach a public mirror. The config enforces this STRUCTURALLY:
# `_monorepo_only()` lists `<component>/infra/**`, and every generated workflow
# excludes `_monorepo_only_files` from its export origin_files AND its import
# destination_files. This check fails if that structural guarantee is ever
# weakened — so a future co-located app cannot silently start leaking.
# ---------------------------------------------------------------------------
COPYBARA_CONFIG_FILE="$ROOT/tools/copybara/copy.bara.sky"

# Every Pulumi.yaml `name:` must be UNIQUE across the repo. Pulumi keys STACK
# STATE on that name, so two programs sharing one produces a stack collision:
# the second program adopts the first's resources and reconciles them against
# the wrong project. It applies cleanly and is silently wrong.
#
# This is not hypothetical. During the tabula bu2 migration it happened FOUR
# times, because the name lives inside Pulumi.yaml, is conventionally written
# with underscores, and therefore survives both a directory rename and a
# hyphenated find-and-replace. The worst instance had tabula's new app stack
# named `pulumi_tabula` -- the same as the existing personal-project program --
# so the bu2 deploy inherited 21 resources pointing at the old project.
check_pulumi_project_names() {
  # Scope: the LIVE deployed tree only. pulumi/examples/** are scaffold
  # templates (ts- and go-foundation carry the same names by design, and the
  # example mirrors the live stage names) -- they are never deployed into the
  # same Pulumi organization, so they cannot collide.
  pulumi_names() {
    grep -rh --include='Pulumi.yaml' -E '^name:[[:space:]]*\S+' \
      infrastructure/pulumi */infra 2>/dev/null | sed -E 's/^name:[[:space:]]*//'
  }
  dupes="$(pulumi_names | sort | uniq -d)"
  [ -z "$dupes" ] && { emit "pulumi" "$GLYPH_OK" "$C_GREEN" "Pulumi.yaml" "unique" "unique" \
      "every Pulumi project name is unique" ""; return 0; }
  for d in $dupes; do
    where="$(grep -rl --include='Pulumi.yaml' -E "^name:[[:space:]]*${d}\$" infrastructure/pulumi */infra 2>/dev/null | sed 's|^\./||' | tr '\n' ' ')"
    emit "pulumi" "$GLYPH_FAIL" "$C_RED" "Pulumi.yaml" "duplicate: $d" "unique" \
      "Pulumi project name '$d' is declared by more than one program ($where) - they SHARE stack state, so one will adopt the other's resources and reconcile them against the wrong target" \
      "give each program a distinct name: in its Pulumi.yaml (renaming the directory is NOT enough - the name is independent of the path)"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
  done
}

# A customDomain must live UNDER the cloudflareZone declared beside it.
#
# Both the Cloud Run DomainMapping's grey-cloud CNAME and the domain-ownership
# verification TXT (tools/ci/ensure-site-verification.sh) are written into the
# zone named by `cloudflareZone`. If that zone is not the registrable parent of
# `customDomain`, both land on the WRONG domain: the CNAME is created somewhere
# it can never serve the hostname, and the verification token is planted on a
# zone Google will not consult for it -- leaving the DomainMapping stuck at
# "Caller is not authorized to administer the domain" with DNS that looks
# superficially fine.
#
# This is a live hazard now that apps span two zones by convention (OSS apps on
# ipv1337.dev, paid/commercial on vitruviansoftware.dev): a config copied from
# an app on the other zone carries the source app's cloudflareZone, and nothing
# downstream cross-checks the two keys against each other.
check_custom_domain_zone() {
  ok=1
  for f in */infra/*/Pulumi.*.yaml; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in Pulumi.yaml) continue ;; esac
    # Namespace-agnostic: the Pulumi config namespace is per-app and is not
    # derivable from the project name (tabula's is `tabula-app`, its project
    # `pulumi_tabula_app`).
    dom="$(sed -n "s/^[[:space:]]*[A-Za-z0-9_.-]\{1,\}:customDomain:[[:space:]]*//p" "$f" | head -n1 | tr -d "\"'")"
    [ -n "$dom" ] || continue
    zone="$(sed -n "s/^[[:space:]]*[A-Za-z0-9_.-]\{1,\}:cloudflareZone:[[:space:]]*//p" "$f" | head -n1 | tr -d "\"'")"
    rel="${f#./}"
    if [ -z "$zone" ]; then
      emit "pulumi" "$GLYPH_FAIL" "$C_RED" "$rel" "no cloudflareZone" "zone declared" \
        "$rel sets customDomain=$dom but declares no cloudflareZone - the CNAME and the ownership-verification TXT would have no zone to be written into" \
        "add the registrable parent zone, e.g. '<ns>:cloudflareZone: ${dom#*.}'"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
      continue
    fi
    case "$dom" in
      "$zone" | *".$zone") ;;
      *)
        emit "pulumi" "$GLYPH_FAIL" "$C_RED" "$rel" "$dom not under $zone" "domain under zone" \
          "$rel maps customDomain=$dom into cloudflareZone=$zone, but $dom is not $zone or a subdomain of it - the grey-cloud CNAME and the google-site-verification TXT would both be written to the WRONG zone" \
          "set cloudflareZone (and its pinned cloudflareZoneId) to the zone that actually contains $dom"
        OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
        ;;
    esac
  done
  [ "$ok" = 1 ] && emit "pulumi" "$GLYPH_OK" "$C_GREEN" "customDomain" "under its zone" "under its zone" \
    "every customDomain is a subdomain of the cloudflareZone declared beside it" ""
}

# Release-unit boundary guard for CO-LOCATED app infrastructure.
#
# A release-please package claims every commit touching files under its path.
# Since app infra moved next to the app it serves (`<app>/infra/`), a purely
# INFRASTRUCTURE change now lands inside an APPLICATION's release unit -- so a
# `feat:` commit touching `<app>/infra/**` bumps the app's semver and writes a
# changelog entry for a feature the app does not have. The resulting release
# commit rewrites <app>/package.json + CHANGELOG.md, which matches the app's
# deploy path filter, so it also DEPLOYS an unchanged artifact.
#
# That is not hypothetical: it shipped oauth-user-inspector 1.1.0 (#995 ->
# #997), whose sole changelog line credits a foundation change, and triggered a
# full dev->nonprod->prod promotion of byte-identical code.
#
# The fix is release-please's per-package `exclude-paths` (repo-root-relative;
# a commit is dropped when ALL of its files under that package path match --
# verified against release-please src/util/commit-exclude.ts). This check makes
# that mandatory, so the NEXT app to co-locate its infra cannot silently
# reintroduce the bug. It is the release-side sibling of the Copybara
# infra-leak guard above: same `<app>/infra/` convention, different automation
# that has to be taught the artifact boundary.
# Leaked local-filesystem path guard.
#
# A developer/agent machine path must never reach a committed file. It is
# meaningless to everyone else, it leaks the author's directory layout, and
# when it lands in a config KEY it silently breaks the consumer.
#
# This is not hypothetical. Generating the stage-5 stack configs from an
# UNQUOTED zsh heredoc turned `$env:apps` into zsh's `:a` (absolute path)
# history modifier and `$env:region` into `:r` (remove extension), producing:
#
#   foundation-app-infra-bu1-<abs path to the author worktree>/developmentpps:
#   foundation-app-infra-bu1-developmentegion:
#
# Both parse as valid YAML, so nothing complained until the stage-5 deploy
# failed with "config name ... exceeds max length of 128". Committed, merged,
# and only caught by a live deploy.
#
# Lesson encoded here: generate config with a real templating language, and let
# CI — not a deploy — catch it when that slips.
# CI gate global-impact list drift guard.
#
# deploy-affected.sh and affected-targets.sh each carry a "global-impact"
# allowlist: a change under tools/ OUTSIDE the allowlist forces affected=true
# (fail open). The two lists MUST be identical -- affected-targets.sh picks
# which tests run, deploy-affected.sh picks whether a live deploy runs, and a
# divergence means CI and deploy disagree about what a change can affect.
#
# They were kept in sync only by a comment saying "same set as
# affected-targets.sh". This enforces it.
#
# Why it matters concretely: tools/conformance/ was NOT allowlisted, so editing
# the conformance script alone marked tabula's deploy targets affected and ran
# a live Cloud Run deploy. `bazel query somepath(<deploy targets>,
# //tools/conformance/... )` returns EMPTY -- no deployable artifact depends on
# it -- so that deploy could never have shipped anything different. It did,
# however, re-run a deploy that was already failing for unrelated reasons and
# painted an unrelated PR's merge red.
check_ci_gate_lists_match() {
  da="$ROOT/tools/ci/deploy-affected.sh"; ta="$ROOT/tools/ci/affected-targets.sh"
  a="$(grep -o "\^tools/([^']*)" "$da" 2>/dev/null | head -1)"
  b="$(grep -o "\^tools/([^']*)" "$ta" 2>/dev/null | head -1)"
  if [ -z "$a" ] || [ -z "$b" ]; then
    emit "gate" "$GLYPH_FAIL" "$C_RED" "tools/ci/*-affected*.sh" "pattern not found" "one per file" \
      "could not locate the global-impact allowlist in one of the gate scripts - the guard cannot verify them" \
      "check the '^tools/(...)' pattern still exists in both deploy-affected.sh and affected-targets.sh"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); return 1
  fi
  if [ "$a" = "$b" ]; then
    emit "gate" "$GLYPH_OK" "$C_GREEN" "tools/ci/*-affected*.sh" "identical" "identical" \
      "the deploy gate and the test gate agree on global-impact paths" ""
    return 0
  fi
  emit "gate" "$GLYPH_FAIL" "$C_RED" "tools/ci/*-affected*.sh" "diverged" "identical" \
    "deploy-affected.sh and affected-targets.sh disagree on the global-impact allowlist, so CI and deploy disagree about what a change can affect" \
    "make the '^tools/(...)' patterns identical in both files"
  OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); return 1
}

# The rollout sequencer (//tools/deploy:cloud-run.sh) is allowlisted OUT of the
# global-impact guard shared by tools/ci/{affected-targets,deploy-affected}.sh,
# so changing it no longer forces a full //... sweep. That is safe for the TEST
# gate -- target-determinator tracks the tools/deploy/defs.bzl load edge and the
# srcs=["//tools/deploy:cloud-run.sh"] edge onto each app's `:deploy` target.
#
# It is NOT automatically safe for the DEPLOY gate: that gate's TD universe is
# DEPLOY_TARGETS (the image/zip artifacts), which do NOT depend on `:deploy`, so
# nothing in it would notice a sequencer change. Every workflow that actually
# runs a rollout must therefore name tools/deploy/ in its OWN trigger set --
# EXTRA_PATH_REGEX for the graph-gated apps, a push `paths:` glob for the
# path-gated ones -- or a candidate->smoke->promote change could merge and never
# be deployed. This guard makes that coupling structural instead of a comment.
check_deploy_sequencer_gate() {
  _allow="$(grep -o "\^tools/([^']*)" "$ROOT/tools/ci/affected-targets.sh" 2>/dev/null | head -1)"
  case "$_allow" in
    *"|deploy/|"*) ;;
    *)
      emit "gate" "$GLYPH_OK" "$C_GREEN" "tools/deploy" "force-sweeps" "n/a" \
        "tools/deploy is not allowlisted, so the global-impact guard still covers a sequencer change" ""
      return 0 ;;
  esac

  _missing=""
  for _wf in "$ROOT"/.github/workflows/*.yaml "$ROOT"/.github/workflows/*.yml; do
    [ -f "$_wf" ] || continue
    # Only the CALLERS of the reusable rollout workflow actually deploy.
    grep -qE '^[[:space:]]*uses:[[:space:]]*\./\.github/workflows/_deploy-cloud-run\.yaml' "$_wf" 2>/dev/null || continue
    # Must appear in a real trigger (EXTRA_PATH_REGEX or a paths: glob) -- a
    # passing mention in a comment must NOT satisfy this.
    if ! grep -qE '^[[:space:]]*(EXTRA_PATH_REGEX:.*tools/deploy/|-[[:space:]]*"tools/deploy/)' "$_wf" 2>/dev/null; then
      _missing="${_missing} $(basename "$_wf")"
    fi
  done

  if [ -z "$_missing" ]; then
    emit "gate" "$GLYPH_OK" "$C_GREEN" "_deploy-cloud-run.yaml callers" "trigger on tools/deploy/" "all callers" \
      "every Cloud Run rollout workflow redeploys when the sequencer changes" ""
    return 0
  fi

  emit "gate" "$GLYPH_FAIL" "$C_RED" "${_missing# }" "no tools/deploy/ trigger" "tools/deploy/" \
    "tools/deploy/ is allowlisted out of the global-impact guard, so these rollout workflows would NOT redeploy when the candidate->smoke->promote sequencer changes" \
    "add tools/deploy/ to the workflow's EXTRA_PATH_REGEX (graph-gated apps), or 'tools/deploy/**' to its push paths: (path-gated apps)"
  OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); return 1
}

# ---------------------------------------------------------------------------
# Deploy durable-base guard (#1351, issue item 2). A workflow that gates a
# Cloud-Run/publish lane via tools/ci/deploy-affected.sh diffs `BEFORE_REV`
# against HEAD to decide whether to deploy. These lanes (tabula-deploy,
# tabula-dev-latest, oauth-user-inspector-deploy) deliberately COALESCE queued
# pushes onto one constant concurrency group — serializing on purpose, because
# two commits racing the same live env + shared build Artifact Registry is
# worse than a queued wait. That is the OPPOSITE shape from the postsubmit
# GATING lanes check_postsubmit_concurrency guards above, which key on
# github.sha because they CAN run in parallel.
#
# A constant group is exactly what makes github.event.before unsafe as a diff
# base: GitHub evicts an already-PENDING run when a newer one queues behind it
# (the #1311/#1335 mechanism), and event.before is fixed at the EVICTED run's
# own push — a range no successor run ever re-diffs, so that commit's deploy
# is skipped PERMANENTLY, not deferred (#1351).
#
# The fix is a durable base (tools/ci/resolve-deploy-base.sh), not a sha-keyed
# group, so this guard asserts THREE directions per workflow:
#   1. every deploy-affected.sh caller also invokes resolve-deploy-base.sh
#      (the durable-base pattern is wired in, not silently reverted);
#   2. its concurrency group is STILL a coalescing (non-sha) one — keying it
#      on github.sha here would be the #1335 fix applied to the WRONG lane
#      shape: it would let two commits race the same env/build AR, exactly
#      what the constant group exists to prevent; and
#   3. NOTHING in the push-triggered chain masks a failed deploy as a
#      successful run. resolve-deploy-base.sh's whole premise is that
#      `gh run list -s success` genuinely means the deploy happened (verified
#      by hand at #1351's review: no `continue-on-error` anywhere in
#      gate -> build -> deploy, including the reusable
#      _deploy-cloud-run.yaml). A future `continue-on-error: true` anywhere
#      in that chain would let a run whose deploy FAILED still conclude
#      success — resolve-deploy-base.sh would then adopt that failed commit
#      as the durable base, and every real change since would be silently
#      skipped: #1351 reintroduced, and quieter, because conformance would
#      otherwise never catch it. This turns that one-time grep into an
#      enforced invariant instead of a fact only true the day it was checked.
# ---------------------------------------------------------------------------
check_deploy_durable_base() {
  [ -d "$WORKFLOWS_DIR" ] || return 0
  found_any=0
  for wf in "$WORKFLOWS_DIR"/*.yaml "$WORKFLOWS_DIR"/*.yml; do
    [ -f "$wf" ] || continue
    # Anchored to an actual `run:` invocation, not a passing mention -- a
    # comment, or (like deploy-affected-test.yaml's own `paths:` trigger)
    # this script's regression-test workflow, must NOT satisfy the signature.
    grep -qE '^[[:space:]]*run:[[:space:]]*bash tools/ci/deploy-affected\.sh[[:space:]]*$' "$wf" 2>/dev/null || continue
    found_any=$((found_any + 1))
    wf_rel=".github/workflows/${wf##*/}"

    has_resolver=0
    grep -qE '^[[:space:]]*run:[[:space:]]*bash tools/ci/resolve-deploy-base\.sh[[:space:]]*$' "$wf" 2>/dev/null && has_resolver=1

    group="$(awk '
      /^concurrency:[ \t]*$/ { in_c=1; next }
      in_c && /^[A-Za-z_]/   { in_c=0 }
      in_c && /^[ \t]*group:/ { sub(/^[ \t]*group:[ \t]*/, ""); print; exit }
    ' "$wf")"
    sha_keyed=0
    case "$group" in *github.sha*) sha_keyed=1 ;; esac

    # Anchored to the real YAML key (any indentation), not a passing prose
    # mention of the term. Follows the ONE reusable-workflow edge the push
    # chain's deploy job actually executes -- a mask inside
    # _deploy-cloud-run.yaml is exactly as dangerous as one in the caller.
    masked=0
    mask_where=""
    if grep -qE '^[[:space:]]*continue-on-error:' "$wf" 2>/dev/null; then
      masked=1
      mask_where="$wf_rel"
    fi
    if grep -qE '^[[:space:]]*uses:[[:space:]]*\./\.github/workflows/_deploy-cloud-run\.yaml' "$wf" 2>/dev/null; then
      # Single-hop by design (Aegis review, #1352): follows only the ONE
      # reusable-workflow edge today's topology has. A mask hiding behind a
      # SECOND reusable layer, or a caller adopting a different reusable
      # deploy workflow, needs a new edge added here to stay caught.
      _callee="$WORKFLOWS_DIR/_deploy-cloud-run.yaml"
      if [ -f "$_callee" ] && grep -qE '^[[:space:]]*continue-on-error:' "$_callee" 2>/dev/null; then
        masked=1
        mask_where="${mask_where:+$mask_where, }.github/workflows/_deploy-cloud-run.yaml"
      fi
    fi

    if [ "$has_resolver" -eq 1 ] && [ "$sha_keyed" -eq 0 ] && [ "$masked" -eq 0 ]; then
      emit "durable" "$GLYPH_OK" "$C_GREEN" "$wf_rel" "durable base" "coalescing, unmasked" \
        "diffs from resolve-deploy-base.sh's durable base; group still coalesces queued pushes; no continue-on-error in the deploy chain to fake a success verdict" ""
      OK_COUNT=$((OK_COUNT + 1))
      continue
    fi

    if [ "$has_resolver" -eq 0 ]; then
      emit "durable" "$GLYPH_FAIL" "$C_RED" "$wf_rel" "event.before" "resolve-deploy-base.sh" \
        "runs deploy-affected.sh but never resolve-deploy-base.sh — BEFORE_REV traces back to github.event.before, which a run dropped by the constant concurrency group (#1311/#1335 eviction) can skip forever (#1351)" \
        "add a step running tools/ci/resolve-deploy-base.sh before the gate step and feed BEFORE_REV: \${{ steps.<id>.outputs.base_sha || github.event.before }}"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    if [ "$sha_keyed" -eq 1 ]; then
      emit "durable" "$GLYPH_FAIL" "$C_RED" "$wf_rel" "sha-keyed" "coalescing" \
        "concurrency group keys on github.sha — that lets two commits deploy against the SAME live env + build Artifact Registry concurrently; sha-keying is the #1335 fix for GATING lanes (which CAN run in parallel), not this DEPLOY lane shape, which must serialize" \
        "key the group on a constant string (e.g. group: ${wf_rel##*/}) and rely on tools/ci/resolve-deploy-base.sh for eviction-safety instead of per-commit isolation"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    if [ "$masked" -eq 1 ]; then
      emit "durable" "$GLYPH_FAIL" "$C_RED" "$wf_rel" "continue-on-error" "no masking" \
        "continue-on-error in ${mask_where} lets a failed deploy step still conclude the run success — resolve-deploy-base.sh would then adopt that FAILED commit as the durable base, silently skipping every real change since (a subtler #1351 that conformance would otherwise never catch)" \
        "remove continue-on-error from the push-triggered deploy chain (gate -> build -> deploy), including inside _deploy-cloud-run.yaml — a masked failure there breaks the invariant the durable base depends on"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done

  # A zero-match sweep means the parser (or the workflow layout) drifted, not
  # that the repo suddenly has no coalescing deploy lanes. Fail loudly.
  if [ "$found_any" -eq 0 ]; then
    emit "durable" "$GLYPH_FAIL" "$C_RED" ".github/workflows" "0 matched" ">=1" \
      "no workflow invokes tools/ci/deploy-affected.sh — the parser or the workflow layout changed" \
      "confirm tabula-deploy.yaml / tabula-dev-latest.yaml / oauth-user-inspector-deploy.yaml still call tools/ci/deploy-affected.sh"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

check_no_local_paths() {
  # Scope: committed text likely to be machine-generated. Docs legitimately
  # quote example paths, and this file names the pattern it greps for.
  # Deliberately NARROW: match only paths that can only come from someone's own
  # working copy — an agent worktree, or a home-rooted path into this repo's
  # checkout. Container/remote paths like /home/vscode/go, /home/k3s/storage and
  # /home/kubernetes/bin are legitimate values, not leaks, so a blanket
  # /home/... pattern would be pure noise and get ignored.
  if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    emit "localpath" "$GLYPH_FAIL" "$C_RED" "tree" "not a git repo" "scannable" \
      "the leaked-local-path guard cannot scan - it would report green without looking" \
      "check \$ROOT ($ROOT) is the git worktree"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); return 1
  fi
  hits="$(git -C "$ROOT" grep -nI -E '\.claude-worktrees/|/(Users|home)/[^/ \"]+/[^ \"]*vitruvian-core' -- \
      '*.yaml' '*.yml' '*.json' '*.go' '*.ts' '*.tsx' '*.sh' '*.sky' '*.bzl' 2>/dev/null \
    | grep -v '^tools/conformance/check.sh:' \
    | grep -v -E '^(docs|devx/docs)/' || true)"
  if [ -z "$hits" ]; then
    emit "localpath" "$GLYPH_OK" "$C_GREEN" "tree" "no local paths" "none" \
      "no committed file embeds a developer machine path" ""
    return 0
  fi
  printf '%s\n' "$hits" | while IFS= read -r h; do
    [ -z "$h" ] && continue
    emit "localpath" "$GLYPH_FAIL" "$C_RED" "${h%%:*}" "local path" "none" \
      "embeds a developer machine path: ${h#*:}" \
      "remove it - if this file is generated, generate it with a real template, not a shell heredoc (zsh applies :a/:r history modifiers inside \$var:word)"
  done
  OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

# Every pulumi-library package must carry BOTH release-please files, and its
# `component` must match its directory.
#
# release-please needs a per-package `.release-please-manifest.json` beside the
# config; without it the release job dies with "Missing required manifest
# versions" and the package NEVER PUBLISHES — which in turn blocks anything that
# consumes it by version, since library consumers pin published versions rather
# than local paths.
#
# The `component` is the release TAG PREFIX. A package whose config was copied
# from a sibling keeps the SOURCE package's component, so it would publish under
# another package's tag namespace. Both mistakes shipped together when pkg/neon
# and pkg/upstash were added by copying pkg/pubsub's config: the manifest was
# missing and both components still read "go-pubsub".
check_release_please_packages() {
  ok=1
  for cfg in pulumi/library/go/pkg/*/release-please-config.json; do
    [ -e "$cfg" ] || continue
    dir="$(dirname "$cfg")"
    pkg="$(basename "$dir")"
    rel="${cfg#./}"
    if [ ! -e "$dir/.release-please-manifest.json" ]; then
      emit "pulumi" "$GLYPH_FAIL" "$C_RED" "$rel" "no manifest" "manifest present" \
        "$dir has release-please-config.json but no .release-please-manifest.json - the release job fails with \"Missing required manifest versions\" and this package never publishes" \
        "add $dir/.release-please-manifest.json containing {\"$dir\": \"0.0.0\"}"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
    fi
    # Convention: "go-" + the directory with underscores as hyphens
    # (pkg/cai_monitoring -> go-cai-monitoring).
    want="go-$(printf '%s' "$pkg" | tr '_' '-')"
    got="$(sed -n 's/.*"component"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" | head -n1)"
    if [ -n "$got" ] && [ "$got" != "$want" ]; then
      emit "pulumi" "$GLYPH_FAIL" "$C_RED" "$rel" "component: $got" "$want" \
        "$rel declares component '$got' but lives in $dir - the component is the release TAG PREFIX, so this package would publish under another package's tag namespace (the signature of a config copied from a sibling)" \
        "set \"component\": \"$want\""
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
    fi
  done
  [ "$ok" = 1 ] && emit "pulumi" "$GLYPH_OK" "$C_GREEN" "release-please" "config+manifest" "config+manifest" \
    "every pulumi-library package has both release-please files and a matching component" ""
}

check_release_infra_exclude() {
  ok=1
  seen=0
  for cfg in "$ROOT"/*/release-please-config.json; do
    [ -f "$cfg" ] || continue
    seen=$((seen + 1))
    rel="${cfg#"$ROOT"/}"
    app="${rel%%/*}"
    [ -d "$ROOT/$app/infra" ] || continue   # only co-located apps are at risk
    excluded="$(python3 - "$cfg" "$app" <<'PY'
import json, sys
cfg, app = sys.argv[1], sys.argv[2]
pkg = json.load(open(cfg)).get("packages", {}).get(app, {})
print("yes" if f"{app}/infra" in (pkg.get("exclude-paths") or []) else "no")
PY
)"
    if [ "$excluded" = "yes" ]; then
      emit "release" "$GLYPH_OK" "$C_GREEN" "$rel" "$app/infra excluded" "excluded"         "co-located infra is outside the app's release unit" ""
    else
      emit "release" "$GLYPH_FAIL" "$C_RED" "$rel" "$app/infra NOT excluded" "excluded"         "$app co-locates infra at $app/infra, so an infrastructure-only commit bumps the APP's version and triggers a deploy of unchanged code"         "add \"exclude-paths\": [\"$app/infra\"] to packages[\"$app\"] in $rel (paths are repo-root-relative)"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
    fi
  done
  # A guard that silently inspects NOTHING is worse than no guard: it reports
  # green forever. This one previously used a CWD-relative glob and matched
  # zero files under `bazel run`, so it passed without checking anything.
  if [ "$seen" -eq 0 ]; then
    emit "release" "$GLYPH_FAIL" "$C_RED" "*/release-please-config.json" "none found" "at least 1" \
      "the release-unit guard found no release-please configs to inspect - it is running blind, not passing" \
      "check the glob resolves from \$ROOT ($ROOT)"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
  fi
  return $((1 - ok))
}

check_copybara_infra_exclude() {
  cb="$COPYBARA_CONFIG_FILE"
  [ -f "$cb" ] || return 0
  cbrel="tools/copybara/copy.bara.sky"
  ok=1

  # 1. The structural exclude: _monorepo_only()'s returned list must contain
  #    the `<component>/infra/**` entry.
  monorepo_only_body="$(awk '/^def _monorepo_only\(/{f=1} f{print} f&&/^ *\]/{exit}' "$cb")"
  if ! printf '%s' "$monorepo_only_body" | grep -qF 'component + "/infra/**"'; then
    emit "copybara" "$GLYPH_FAIL" "$C_RED" "$cbrel" "no infra exclude" "component + \"/infra/**\"" \
      "_monorepo_only() no longer lists <component>/infra/** — a mirrored app's co-located Pulumi stacks (internal GCP details) would be EXPORTED to its public mirror" \
      "add 'component + \"/infra/**\"' back to the _monorepo_only() list in tools/copybara/copy.bara.sky"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
  fi

  # 2. The generator must still route BOTH directions through the monorepo-only
  #    exclude list: the export's origin_files and every import's
  #    destination_files (a destination_files regression would let a PR-import
  #    DELETE the monorepo's infra/ dirs).
  if ! grep -qE 'origin_files = glob\(\[_subtree \+ "/\*\*"\], exclude = _monorepo_only_files' "$cb"; then
    emit "copybara" "$GLYPH_FAIL" "$C_RED" "$cbrel" "export not excluding" "origin_files excludes _monorepo_only_files" \
      "the export workflow's origin_files no longer excludes _monorepo_only_files — BUILD files and <app>/infra/** would be exported to the public mirrors" \
      "restore 'exclude = _monorepo_only_files + _origin_exclude' on the export origin_files glob"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
  fi
  if ! grep -qE 'destination_files = glob\(\[_subtree \+ "/\*\*"\], exclude = _monorepo_only_files\)' "$cb"; then
    emit "copybara" "$GLYPH_FAIL" "$C_RED" "$cbrel" "import not excluding" "destination_files excludes _monorepo_only_files" \
      "the import workflows' destination_files no longer exclude _monorepo_only_files — an import could delete the monorepo's <app>/infra/** (and BUILD files)" \
      "restore 'exclude = _monorepo_only_files' on the import destination_files globs"
    OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); ok=0
  fi

  [ "$ok" -eq 1 ] || return 0

  # 3. Report every mirrored subtree that actually has an on-disk infra/ dir as
  #    covered (names what the guard is protecting today). Subtree defaults to
  #    the component name; explicit "subtree": overrides it (pulumi-library etc).
  covered=""
  subtrees="$(awk '
    /"name":/    { gsub(/[",]/, "", $2); name=$2; sub_=""; next }
    /"subtree":/ { gsub(/[",]/, "", $2); sub_=$2; next }
    /"standalone_rev_id":/ { print (sub_ != "" ? sub_ : name) }
  ' "$cb" | sort -u)"
  for st in $subtrees; do
    [ -d "$ROOT/$st/infra" ] && covered="$covered $st/infra"
  done
  if [ -n "$covered" ]; then
    for c in $covered; do
      emit "copybara" "$GLYPH_OK" "$C_GREEN" "$c" "monorepo-only" "never exported" \
        "co-located per-app Pulumi stacks are excluded from the public-mirror export (structural _monorepo_only guarantee)" ""
      OK_COUNT=$((OK_COUNT + 1))
    done
  else
    emit "copybara" "$GLYPH_OK" "$C_GREEN" "$cbrel" "structural exclude" "never exported" \
      "<component>/infra/** is monorepo-only for every mirrored component (none on disk yet)" ""
    OK_COUNT=$((OK_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# App metadata catalog (#500). Every app directory carries a machine-readable
# catalog-info.yaml (Backstage Component) that is the single per-app source
# for ownership + deploy identity. Enforced invariants:
#   1. the file exists for every app in APP_DIRS;
#   2. metadata.name equals the app directory name (no copy-paste drift);
#   3. spec.owner equals the CODEOWNERS team for /<app>/ (stripped of the
#      @VitruvianSoftware/ org prefix) — ownership is declared ONCE, in
#      CODEOWNERS, and the catalog must agree with it;
#   4. the repo-root catalog-info.yaml Location lists the app's file, so a
#      catalog consumer discovers every app from the root.
# ---------------------------------------------------------------------------
CODEOWNERS_FILE="$ROOT/.github/CODEOWNERS"

check_app_metadata() {
  for app in $APP_DIRS; do
    mf="$ROOT/$app/catalog-info.yaml"
    if [ ! -f "$mf" ]; then
      emit "meta" "$GLYPH_FAIL" "$C_RED" "$app/catalog-info.yaml" "missing" "app metadata" \
        "app has no machine-readable metadata (#500)" \
        "add $app/catalog-info.yaml (Component with owner = the CODEOWNERS team)"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1)); continue
    fi

    mname="$(awk '$1 == "name:" { print $2; exit }' "$mf")"
    mowner="$(awk '$1 == "owner:" { print $2; exit }' "$mf")"
    # CODEOWNERS line: "/<app>/ @VitruvianSoftware/<team>" -> "<team>".
    coteam="$(awk -v p="/$app/" '$1 == p { sub(".*/", "", $2); print $2; exit }' "$CODEOWNERS_FILE" 2>/dev/null)"

    if [ "$mname" != "$app" ]; then
      emit "meta" "$GLYPH_FAIL" "$C_RED" "$app/catalog-info.yaml" "name:$mname" "name:$app" \
        "metadata.name must equal the app directory name" \
        "set metadata.name: $app"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    elif [ -z "$coteam" ]; then
      emit "meta" "$GLYPH_WARN" "$C_YELLOW" "$app/catalog-info.yaml" "owner:$mowner" "(no CODEOWNERS row)" \
        "no /$app/ line in .github/CODEOWNERS to validate the owner against" ""
      WARN_COUNT=$((WARN_COUNT + 1))
    elif [ "$mowner" != "$coteam" ]; then
      emit "meta" "$GLYPH_FAIL" "$C_RED" "$app/catalog-info.yaml" "owner:$mowner" "owner:$coteam" \
        "spec.owner disagrees with the CODEOWNERS team for /$app/ -- ownership is declared once, in CODEOWNERS" \
        "set spec.owner: $coteam"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    elif ! grep -F "./$app/catalog-info.yaml" "$ROOT/catalog-info.yaml" >/dev/null 2>&1; then
      emit "meta" "$GLYPH_FAIL" "$C_RED" "catalog-info.yaml" "missing target" "./$app/catalog-info.yaml" \
        "the root Location does not list this app's catalog file -- consumers can't discover it" \
        "add ./$app/catalog-info.yaml to the root catalog-info.yaml Location targets"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    else
      emit "meta" "$GLYPH_OK" "$C_GREEN" "$app/catalog-info.yaml" "owner:$mowner" "owner:$coteam" \
        "name + owner match CODEOWNERS; listed in the root Location" ""
      OK_COUNT=$((OK_COUNT + 1))
    fi
  done
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

# Scratch files for check_job_timeouts. Its per-workflow tally is accumulated
# inside a `while read` on the right of a pipe — a SUBSHELL, so a plain variable
# would be discarded when it exits. Files survive; removed at the end of MAIN.
TIMEOUT_TALLY="$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/conf-totally.$$")"
TIMEOUT_MISSING="$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/conf-tomissing.$$")"
: > "$TIMEOUT_TALLY"
: > "$TIMEOUT_MISSING"

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
check_app_metadata
check_merge_queue
check_postsubmit_concurrency
check_job_timeouts
check_sweep_backstop
check_zitadel_import
check_pulumi_project_names
check_custom_domain_zone
check_release_please_packages
check_copybara_infra_exclude

check_release_infra_exclude
check_no_local_paths
check_ci_gate_lists_match
check_deploy_sequencer_gate
check_deploy_durable_base
echo
printf '%s%sconformance%s — %s\n' "$C_BOLD" "$C_GREEN" "$C_RESET" "vitruvian-core version conformance"
printf '%scanonical: go %s (go.work) · node %s (.nvmrc) · pnpm %s (package.json)%s\n' \
  "$C_DIM" "$(canonical_go)" "$(canonical_node)" "$(canonical_pnpm)" "$C_RESET"

print_group "Go (go.mod → go.work)" "$ROWS_GO"
print_group "Node (Dockerfile FROM node → .nvmrc major)" "$ROWS_NODE"
print_group "pnpm (package.json packageManager → root)" "$ROWS_PNPM"
print_group "Catalog (package.json → pnpm-workspace.yaml catalog)" "$ROWS_CATALOG"
print_group "App visibility firewall (#82: app-scoped defaults + public allowlist)" "$ROWS_VIS"
print_group "App metadata catalog (#500: catalog-info.yaml ↔ CODEOWNERS)" "$ROWS_META"
print_group "Merge-queue required checks (repo_config → workflow merge_group jobs)" "$ROWS_MERGEQ"
print_group "Postsubmit concurrency (main-gating lanes must key non-PR runs per commit)" "$ROWS_CONCUR"
print_group "Job timeouts (#209: every job bounded — no 6h default-timeout runners)" "$ROWS_TIMEOUT"
print_group "Full-sweep backstop (affected-scoped lanes → scheduled //... sweep)" "$ROWS_SWEEP"
print_group "IaC destructive-import guard (zitadel-apps must create, never import)" "$ROWS_IAC"
print_group "Pulumi program identity (unique project names · customDomain under its zone)" "$ROWS_PULUMI"
print_group "Copybara infra-leak guard (<app>/infra/ is monorepo-only, never mirrored)" "$ROWS_COPYBARA"
print_group "Release-unit guard (co-located <app>/infra/ must not bump the app version)" "$ROWS_RELEASE"
print_group "Leaked local-path guard (no committed file may embed a machine path)" "$ROWS_LOCALPATH"
print_group "CI gate guard (deploy + test gates must share one global-impact list)" "$ROWS_GATE"
print_group "Deploy durable-base guard (#1351: coalescing deploy lanes must not diff from github.event.before directly)" "$ROWS_DURABLE"
print_group "Advisory — pnpm Dockerfile without a packageManager pin" "$ROWS_ADVISORY"
print_group "Advisory — shared deps not in the catalog (drift candidates)" "$ROWS_CAT_ADVISORY"

rm -f "$CATALOG_NAMES_FILE" "$TIMEOUT_TALLY" "$TIMEOUT_MISSING"

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
