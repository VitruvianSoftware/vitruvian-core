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
# `doctor` — developer-environment checker for the vitruvian-core monorepo.
#
# Invoked via `bazel run //<pkg>:doctor` (the `doctor(...)` macro in
# //tools/doctor:defs.bzl bakes in the per-package args). It verifies that the
# local toolchain matches what the repo expects, reading EXPECTED versions from
# the repo's own source-of-truth files (.bazelversion / .nvmrc / package.json /
# go.mod) so a version is never hardcoded here and never drifts.
#
# Per tool it prints a status glyph (✓ ok / ⚠ warn / ✗ fail), the found version,
# the expected version (for pinned tools), and a `→ fix:` hint on trouble. The
# process exits NON-ZERO when a REQUIRED tool is missing or a REQUIRED pinned
# tool has a major/minor mismatch (or, for required docker, the daemon is down),
# so a per-app `:doctor` is a reliable pre-flight gate. Optional tools never fail
# the run — they only ever warn.
#
# Portability: targets macOS (BSD userland) AND Linux. No GNU-only constructs
# (`grep -P`, `realpath`, `sed -i ''`); parsing uses POSIX awk/sed only.

set -u

# ---------------------------------------------------------------------------
# Repo root. `bazel run` sets BUILD_WORKSPACE_DIRECTORY to the workspace root;
# fall back to PWD so the script is still runnable standalone (e.g. for tests).
# ---------------------------------------------------------------------------
ROOT="${BUILD_WORKSPACE_DIRECTORY:-$PWD}"

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
else
  C_RESET='' C_GREEN='' C_YELLOW='' C_RED='' C_DIM='' C_BOLD=''
fi

GLYPH_OK="✓"
GLYPH_WARN="⚠"
GLYPH_FAIL="✗"

# ---------------------------------------------------------------------------
# Arg parsing. The macro passes:
#   --label "<title>"   human-readable scope name for the report header
#   --required <csv>    comma-joined tool keys that must pass (gate)
#   --optional <csv>    comma-joined tool keys that only warn
#   --gomod <relpath>   workspace-relative go.mod to read the `go X.Y.Z` pin from
# ---------------------------------------------------------------------------
LABEL=""
REQUIRED_CSV=""
OPTIONAL_CSV=""
GOMOD_REL=""

# NB: bazel's `args` attribute word-splits each element, so a multi-word label
# like "vitruvian-core (core toolchain)" arrives as several argv tokens, not one.
# We therefore collect every token after --label up to the next --flag and
# rejoin them with spaces, rather than assuming the value is a single arg.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --label)
      shift
      LABEL=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --*) break ;;
          *) LABEL="${LABEL:+$LABEL }$1"; shift ;;
        esac
      done
      ;;
    --required) REQUIRED_CSV="${2:-}"; shift 2 ;;
    --optional) OPTIONAL_CSV="${2:-}"; shift 2 ;;
    --gomod) GOMOD_REL="${2:-}"; shift 2 ;;
    *) echo "doctor: ignoring unknown arg '$1'" >&2; shift ;;
  esac
done

# Split a comma-separated list into space-separated keys (drops empties). Done
# with a subshell + IFS so we never rely on bash arrays for the public seam.
csv_to_keys() {
  printf '%s' "$1" | tr ',' ' '
}

REQUIRED_KEYS="$(csv_to_keys "$REQUIRED_CSV")"
OPTIONAL_KEYS="$(csv_to_keys "$OPTIONAL_CSV")"

# ---------------------------------------------------------------------------
# Source-of-truth readers. Each returns the EXPECTED version string, or empty
# if the file/field is absent (the probe then degrades to presence-only).
# ---------------------------------------------------------------------------

# .bazelversion is a bare version on the first line (e.g. "9.1.1").
expected_bazel() {
  [ -f "$ROOT/.bazelversion" ] || return 0
  # head -1 then strip surrounding whitespace; portable awk.
  awk 'NR==1 { gsub(/^[ \t]+|[ \t\r]+$/, ""); print; exit }' "$ROOT/.bazelversion"
}

# .nvmrc is a bare version, optionally prefixed with "v" (e.g. "22.21.1" or "v22.21.1").
expected_node() {
  [ -f "$ROOT/.nvmrc" ] || return 0
  awk 'NR==1 { gsub(/^[ \tv]+|[ \t\r]+$/, ""); print; exit }' "$ROOT/.nvmrc"
}

# package.json `"packageManager": "pnpm@X.Y.Z"` — pull the X.Y.Z after pnpm@.
expected_pnpm() {
  [ -f "$ROOT/package.json" ] || return 0
  # Grab the packageManager line, isolate the pnpm@<ver> token, strip the rest.
  grep '"packageManager"' "$ROOT/package.json" 2>/dev/null \
    | sed -n 's/.*pnpm@\([0-9][0-9.]*\).*/\1/p' \
    | head -1
}

# go.mod `go X.Y.Z` directive — only consulted when --gomod was passed.
expected_go() {
  [ -n "$GOMOD_REL" ] || return 0
  gomod="$ROOT/$GOMOD_REL"
  [ -f "$gomod" ] || return 0
  # First line matching `^go <ver>`; print the version field only.
  awk '$1 == "go" { print $2; exit }' "$gomod"
}

# ---------------------------------------------------------------------------
# Version normalization + comparison.
# ---------------------------------------------------------------------------

# Extract the first dotted numeric version (X.Y or X.Y.Z) from arbitrary CLI
# output. Fully portable (macOS BSD + Linux): a naive greedy `.*` sed prefix
# eats leading digits (turning "v26.4.0" into "6.4.0"), so instead we split the
# string on every non [0-9.] char into separate lines, then take the first line
# that starts with a digit and contains a dot. Trailing dots are trimmed.
extract_version() {
  printf '%s\n' "$1" \
    | tr -c '0-9.' '\n' \
    | grep '^[0-9][0-9]*\.[0-9]' \
    | head -1 \
    | sed 's/\.*$//'
}

field() { printf '%s' "$1" | cut -d. -f"$2"; }

# Compare found vs expected. Echoes one of: ok | patch | mismatch | unknown.
#   ok       -> major.minor.patch all equal
#   patch    -> major+minor equal, patch differs (acceptable, noted)
#   mismatch -> major or minor differ (a failing condition for pinned tools)
#   unknown  -> couldn't parse one side
compare_versions() {
  found="$1" expected="$2"
  [ -n "$found" ] && [ -n "$expected" ] || { echo "unknown"; return; }
  fmaj="$(field "$found" 1)";  emaj="$(field "$expected" 1)"
  fmin="$(field "$found" 2)";  emin="$(field "$expected" 2)"
  fpat="$(field "$found" 3)";  epat="$(field "$expected" 3)"
  # Default a missing patch to 0 so "22.21" vs "22.21.1" compares sanely.
  fpat="${fpat:-0}"; epat="${epat:-0}"
  if [ "$fmaj" != "$emaj" ] || [ "$fmin" != "$emin" ]; then
    echo "mismatch"
  elif [ "$fpat" != "$epat" ]; then
    echo "patch"
  else
    echo "ok"
  fi
}

# ---------------------------------------------------------------------------
# Per-tool version probes. Each echoes a parsed version string (or empty if it
# couldn't determine one). They assume the tool is already known to be present.
# Stderr is silenced so a tool that prints usage on `--version` stays quiet.
# ---------------------------------------------------------------------------
probe_version() {
  key="$1"
  raw=""
  case "$key" in
    bazel)
      # `bazel version` prints "Build label: 9.1.1" (the real Bazel version),
      # plus a "Bazelisk version:" line we must NOT pick up. Parse the label.
      raw="$(bazel version 2>/dev/null | sed -n 's/^Build label:[ \t]*//p' | head -1)"
      # Fallback to the whole output if the label line isn't present.
      [ -n "$raw" ] || raw="$(bazel version 2>/dev/null)"
      ;;
    node)     raw="$(node --version 2>/dev/null)" ;;            # e.g. v22.21.1
    pnpm)     raw="$(pnpm --version 2>/dev/null)" ;;            # e.g. 10.20.0
    go)       raw="$(go version 2>/dev/null)" ;;               # go version go1.25.5 ...
    git)      raw="$(git --version 2>/dev/null)" ;;            # git version 2.54.0
    gh)       raw="$(gh --version 2>/dev/null | head -1)" ;;   # gh version 2.95.0 (...)
    gcloud)   raw="$(gcloud --version 2>/dev/null | head -1)" ;;
    docker)   raw="$(docker --version 2>/dev/null)" ;;         # Docker version 29.6.0, build ...
    direnv)   raw="$(direnv --version 2>/dev/null)" ;;
    mage)     raw="$(mage --version 2>/dev/null | head -2 | tr '\n' ' ')" ;;
    mise)     raw="$(mise --version 2>/dev/null | head -1)" ;;
    lima)     raw="$(limactl --version 2>/dev/null | head -1)" ;;  # limactl version 2.1.3
    swift)    raw="$(swift --version 2>/dev/null | head -1)" ;;
    python3)  raw="$(python3 --version 2>&1 | head -1)" ;;     # Python 3.14.6 (may go to stderr)
    goreleaser) raw="$(goreleaser --version 2>/dev/null | head -5 | tr '\n' ' ')" ;;
    *)        raw="$($key --version 2>/dev/null | head -1)" ;; # generic fallback
  esac
  printf '%s' "$(extract_version "$raw")"
}

# The binary that backs a tool key (mostly identity; lima -> limactl).
tool_binary() {
  case "$1" in
    lima) echo "limactl" ;;
    *)    echo "$1" ;;
  esac
}

# Is this a PINNED tool (version is compared against a source-of-truth file)?
is_pinned() {
  case "$1" in
    bazel|node|pnpm|go) return 0 ;;
    *) return 1 ;;
  esac
}

# Expected version for a pinned key (empty for non-pinned).
expected_for() {
  case "$1" in
    bazel) expected_bazel ;;
    node)  expected_node ;;
    pnpm)  expected_pnpm ;;
    go)    expected_go ;;
    *)     printf '' ;;
  esac
}

# A short, actionable fix hint per tool (printed on warn/fail).
fix_hint() {
  case "$1" in
    bazel)  echo "install Bazelisk so \`bazel\` honors .bazelversion" ;;
    node)   echo "nvm use (reads .nvmrc)" ;;
    pnpm)   echo "corepack enable" ;;
    go)     echo "install Go ${2:-<expected>}" ;;
    git)    echo "install git (xcode-select --install or your package manager)" ;;
    gh)     echo "install GitHub CLI: https://cli.github.com/" ;;
    gcloud) echo "install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install" ;;
    docker) echo "start Docker/colima" ;;
    direnv) echo "install direnv + hook your shell: https://direnv.net/" ;;
    mage)   echo "install mage: https://magefile.org/" ;;
    mise)   echo "install mise: https://mise.jdx.dev/" ;;
    lima)   echo "install Lima: https://lima-vm.io/" ;;
    swift)  echo "install Swift toolchain (Xcode or swift.org)" ;;
    python3) echo "install Python 3: https://www.python.org/downloads/" ;;
    goreleaser) echo "install GoReleaser: https://goreleaser.com/install/" ;;
    *)      echo "install $1" ;;
  esac
}

# ---------------------------------------------------------------------------
# docker daemon liveness — `docker --version` works even with the daemon down,
# so a meaningful health check must talk to the daemon. Returns 0 if reachable.
# ---------------------------------------------------------------------------
docker_daemon_up() {
  docker info >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Reporting. We buffer rows and column-align at the end so the table lines up
# regardless of tool-name / version width. Each row is encoded as
#   <glyph>\t<color>\t<tool>\t<found>\t<expected>\t<hint>
# joined with a unit separator we won't see in real values.
# ---------------------------------------------------------------------------
ROWS=""
US=$'\037' # field separator within a row
RS=$'\036' # row separator

add_row() {
  # $1 glyph  $2 color  $3 tool  $4 found  $5 expected  $6 hint
  ROWS="${ROWS}$1${US}$2${US}$3${US}$4${US}$5${US}$6${RS}"
}

OVERALL_FAIL=0 # becomes 1 if any required check fails -> non-zero exit
WARN_COUNT=0
FAIL_COUNT=0
OK_COUNT=0

# Evaluate a single tool key. $2 = "required" | "optional".
check_tool() {
  key="$1" tier="$2"
  bin="$(tool_binary "$key")"

  # --- presence ---
  if ! command -v "$bin" >/dev/null 2>&1; then
    if [ "$tier" = "required" ]; then
      add_row "$GLYPH_FAIL" "$C_RED" "$key" "not found" "$(expected_for "$key")" "$(fix_hint "$key" "$(expected_for "$key")")"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    else
      add_row "$GLYPH_WARN" "$C_YELLOW" "$key" "not found" "$(expected_for "$key")" "$(fix_hint "$key" "$(expected_for "$key")")"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
    return
  fi

  found="$(probe_version "$key")"
  [ -n "$found" ] || found="present"
  expected="$(expected_for "$key")"

  # --- docker daemon health (in addition to presence) ---
  if [ "$key" = "docker" ]; then
    if docker_daemon_up; then
      add_row "$GLYPH_OK" "$C_GREEN" "$key" "$found" "" ""
      OK_COUNT=$((OK_COUNT + 1))
    elif [ "$tier" = "required" ]; then
      add_row "$GLYPH_FAIL" "$C_RED" "$key" "${found} (daemon down)" "" "$(fix_hint docker)"
      OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
    else
      add_row "$GLYPH_WARN" "$C_YELLOW" "$key" "${found} (daemon down)" "" "$(fix_hint docker)"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
    return
  fi

  # --- pinned: compare against source-of-truth ---
  if is_pinned "$key" && [ -n "$expected" ]; then
    verdict="$(compare_versions "$found" "$expected")"
    case "$verdict" in
      ok)
        add_row "$GLYPH_OK" "$C_GREEN" "$key" "$found" "$expected" ""
        OK_COUNT=$((OK_COUNT + 1))
        ;;
      patch)
        # Patch-only drift is acceptable; surface it as an OK with a note.
        add_row "$GLYPH_OK" "$C_GREEN" "$key" "$found" "$expected" "patch differs (ok)"
        OK_COUNT=$((OK_COUNT + 1))
        ;;
      mismatch)
        if [ "$tier" = "required" ]; then
          add_row "$GLYPH_FAIL" "$C_RED" "$key" "$found" "$expected" "$(fix_hint "$key" "$expected")"
          OVERALL_FAIL=1; FAIL_COUNT=$((FAIL_COUNT + 1))
        else
          add_row "$GLYPH_WARN" "$C_YELLOW" "$key" "$found" "$expected" "$(fix_hint "$key" "$expected")"
          WARN_COUNT=$((WARN_COUNT + 1))
        fi
        ;;
      *)
        # Couldn't parse a version to compare — warn but don't gate on it.
        add_row "$GLYPH_WARN" "$C_YELLOW" "$key" "$found" "$expected" "could not parse version"
        WARN_COUNT=$((WARN_COUNT + 1))
        ;;
    esac
    return
  fi

  # --- non-pinned (or pinned w/ no source-of-truth): presence is enough ---
  add_row "$GLYPH_OK" "$C_GREEN" "$key" "$found" "" ""
  OK_COUNT=$((OK_COUNT + 1))
}

# ---------------------------------------------------------------------------
# Run the checks. Required first, then optional, preserving declared order.
# ---------------------------------------------------------------------------
for k in $REQUIRED_KEYS; do
  [ -n "$k" ] && check_tool "$k" "required"
done
for k in $OPTIONAL_KEYS; do
  [ -n "$k" ] && check_tool "$k" "optional"
done

# ---------------------------------------------------------------------------
# Render the report. First pass computes column widths; second pass prints.
# ---------------------------------------------------------------------------
echo
printf '%s%sdoctor%s — %s\n' "$C_BOLD" "$C_GREEN" "$C_RESET" "${LABEL:-vitruvian-core}"
echo "${C_DIM}developer-environment check${C_RESET}"
echo

# Compute max widths for tool / found / expected columns.
w_tool=4 w_found=5 w_exp=8
old_ifs="$IFS"
IFS="$RS"
for row in $ROWS; do
  [ -n "$row" ] || continue
  IFS="$US"
  # shellcheck disable=SC2086
  set -- $row
  IFS="$RS"
  tool="$3"; found="$4"; exp="$5"
  [ "${#tool}" -gt "$w_tool" ] && w_tool=${#tool}
  [ "${#found}" -gt "$w_found" ] && w_found=${#found}
  [ "${#exp}" -gt "$w_exp" ] && w_exp=${#exp}
done
IFS="$old_ifs"

# Header row for the table.
printf '  %-2s  %-*s  %-*s  %-*s\n' "" "$w_tool" "TOOL" "$w_found" "FOUND" "$w_exp" "EXPECTED"

IFS="$RS"
for row in $ROWS; do
  [ -n "$row" ] || continue
  # Decode the six fields. Using a here-construct keeps it POSIX.
  glyph="$(printf '%s' "$row" | awk -F"$US" '{print $1}')"
  color="$(printf '%s' "$row" | awk -F"$US" '{print $2}')"
  tool="$(printf '%s'  "$row" | awk -F"$US" '{print $3}')"
  found="$(printf '%s' "$row" | awk -F"$US" '{print $4}')"
  exp="$(printf '%s'   "$row" | awk -F"$US" '{print $5}')"
  hint="$(printf '%s'  "$row" | awk -F"$US" '{print $6}')"

  printf '  %s%s%s  %-*s  %-*s  %-*s' \
    "$color" "$glyph" "$C_RESET" \
    "$w_tool" "$tool" "$w_found" "$found" "$w_exp" "$exp"
  if [ -n "$hint" ]; then
    printf '  %s→ fix: %s%s' "$C_DIM" "$hint" "$C_RESET"
  fi
  printf '\n'
done
IFS="$old_ifs"

echo
# ---------------------------------------------------------------------------
# One-line PASS/FAIL summary + a pointer to CONTRIBUTING.md.
# ---------------------------------------------------------------------------
if [ "$OVERALL_FAIL" -ne 0 ]; then
  printf '%s%s FAIL%s — %d ok, %d warn, %d fail. Required checks did not pass.\n' \
    "$C_RED" "$GLYPH_FAIL" "$C_RESET" "$OK_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
else
  printf '%s%s PASS%s — %d ok, %d warn, %d fail.\n' \
    "$C_GREEN" "$GLYPH_OK" "$C_RESET" "$OK_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
fi
echo "${C_DIM}See CONTRIBUTING.md for the full toolchain setup.${C_RESET}"

exit "$OVERALL_FAIL"
