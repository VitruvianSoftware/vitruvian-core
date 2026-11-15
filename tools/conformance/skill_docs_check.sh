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

# Checks that every relative markdown link and every backticked package path
# (outside fenced code blocks) in the given markdown files resolves to an
# existing file or directory in the Bazel runfiles tree (or workspace).
#
# Usage: skill_docs_check.sh --root <pkg_rel_dir> <markdown_file>...

set -euo pipefail

PKG_ROOT=""
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      PKG_ROOT="${2:?--root requires a value}"
      shift 2
      ;;
    --)
      shift
      FILES+=("$@")
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$PKG_ROOT" || ${#FILES[@]} -eq 0 ]]; then
  echo "Usage: $0 --root <pkg_rel_dir> <markdown_file>..." >&2
  exit 2
fi

# Enter Bazel runfiles _main if PKG_ROOT is not already present in the current directory.
if [[ ! -d "$PKG_ROOT" ]]; then
  if [[ -n "${RUNFILES_DIR:-}" && -d "${RUNFILES_DIR}/_main" ]]; then
    cd "${RUNFILES_DIR}/_main"
  elif [[ -n "${TEST_SRCDIR:-}" && -d "${TEST_SRCDIR}/_main" ]]; then
    cd "${TEST_SRCDIR}/_main"
  fi
fi

if [[ ! -d "$PKG_ROOT" ]]; then
  echo "FAIL: package root directory does not exist: $PKG_ROOT" >&2
  exit 1
fi

# Normalize a POSIX path without requiring the final component to exist
# (resolves `.` and `..` lexically).
normalize_path() {
  local raw="$1"
  awk -v p="$raw" 'BEGIN {
    n = split(p, parts, "/");
    sp = 0;
    for (i = 1; i <= n; i++) {
      if (parts[i] == "" || parts[i] == ".") continue;
      if (parts[i] == "..") {
        if (sp > 0 && stack[sp] != "..") { sp--; }
        else { stack[++sp] = ".."; }
      } else {
        stack[++sp] = parts[i];
      }
    }
    if (sp == 0) { print "."; exit; }
    out = stack[1];
    for (i = 2; i <= sp; i++) out = out "/" stack[i];
    print out;
  }'
}

errors=0

check_file() {
  local md_file="$1"
  local md_dir
  md_dir="$(dirname "$md_file")"

  if [[ ! -f "$md_file" ]]; then
    echo "FAIL: markdown file not found: $md_file" >&2
    errors=$((errors + 1))
    return
  fi

  # Extract candidate references outside fenced code blocks as:
  #   LINK\t<lineno>\t<target>
  #   PATH\t<lineno>\t<token>
  local refs
  refs="$(awk '
    BEGIN { in_fence = 0 }
    /^[[:space:]]*```/ { in_fence = !in_fence; next }
    in_fence { next }
    {
      # 1. Markdown links: [...](target)
      line = $0
      while (match(line, /\[[^]]*\]\([^)]+\)/)) {
        seg = substr(line, RSTART, RLENGTH)
        sub(/^[^)]*\(/, "", seg)
        sub(/\)$/, "", seg)
        # Strip optional title after whitespace
        sub(/[[:space:]].*$/, "", seg)
        print "LINK\t" NR "\t" seg
        line = substr(line, RSTART + RLENGTH)
      }
      # 2. Backticked path tokens: `prefix/...`
      line = $0
      while (match(line, /`[^`]+`/)) {
        tok = substr(line, RSTART + 1, RLENGTH - 2)
        if (tok ~ /^(src|api|cli|infra|extension|go|ts|docs|rules|macos|scripts|testdata|\.github)\/[A-Za-z0-9_.\-\/]+$/ &&
            tok !~ /\.\./) {
          print "PATH\t" NR "\t" tok
        }
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$md_file")"

  while IFS=$'\t' read -r kind lineno raw_ref; do
    [[ -z "$kind" ]] && continue
    if [[ "$kind" == "LINK" ]]; then
      # Skip external URLs, anchors, and IDE/extension schemes.
      case "$raw_ref" in
        http://* | https://* | mailto:* | chrome-extension://* | sidecar://* | "#"*)
          continue
          ;;
      esac
      local clean="${raw_ref%%#*}"
      clean="${clean%%\?*}"
      [[ -z "$clean" ]] && continue
      local resolved
      resolved="$(normalize_path "${md_dir}/${clean}")"
      if [[ ! -e "$resolved" ]]; then
        echo "FAIL: ${md_file}:${lineno}: broken relative link '${raw_ref}' (resolved to '${resolved}')" >&2
        errors=$((errors + 1))
      fi
    elif [[ "$kind" == "PATH" ]]; then
      local clean="${raw_ref%/}"
      local resolved_pkg
      resolved_pkg="$(normalize_path "${PKG_ROOT}/${clean}")"
      local resolved_rel
      resolved_rel="$(normalize_path "${md_dir}/${clean}")"
      if [[ ! -e "$resolved_pkg" && ! -e "$resolved_rel" ]]; then
        echo "FAIL: ${md_file}:${lineno}: missing referenced path '${raw_ref}' (checked '${resolved_pkg}' and '${resolved_rel}')" >&2
        errors=$((errors + 1))
      fi
    fi
  done <<< "$refs"
}

for f in "${FILES[@]}"; do
  check_file "$f"
done

if [[ $errors -gt 0 ]]; then
  echo "skill_docs_check: $errors broken link(s)/path(s) found." >&2
  exit 1
fi

echo "skill_docs_check: checked ${#FILES[@]} file(s) under ${PKG_ROOT}; all links and paths exist."
