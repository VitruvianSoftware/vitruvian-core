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
# llvm-cache-stage.sh -- move the extracted LLVM toolchain between the Actions
# cache's FIXED folder and Bazel's repo contents cache, so that no file in this
# repo ever has to name the folder Bazel extracts LLVM into (#2456).
#
# WHY. Bazel names that folder after a hash of the llvm repo rule's whole
# definition -- not just llvm_versions. A rules_cc bump (#2419) moved it, and
# the cache kept pointing at the old, hand-copied name: every Bazel lane paid
# the full extraction for ~20 runs before anyone noticed (#2455). A hand-copied
# name will go stale again on the next toolchain-adjacent bump, so there isn't
# one any more:
#
#   restore  the cache unpacks into <stage>/<hash>/ (a path that never
#            changes); move each <hash>/ into <contents>/<hash>/ -- the same
#            bytes at the same final path the old pinned cache produced.
#   stage    after the build, find the folder that actually holds clang and
#            hard-link it into <stage>/, where the cache's post step saves it.
#   live     print the contents folder that actually holds clang.
#
# Moves and hard links stay on one filesystem, so neither copies the ~8GB tree.
#
# Usage:
#   llvm-cache-stage.sh restore <stage> <contents>   # prints the restored dir
#   llvm-cache-stage.sh stage   <stage> <contents>   # prints the staged hash
#   llvm-cache-stage.sh live    <contents>           # prints the live dir

set -euo pipefail

# The hash folder under <contents> whose candidate holds bin/clang, or nothing.
# Layout: <contents>/<hash>/<candidate>/bin/clang.
llvm_live_dir() {
  local contents="$1" clang
  clang="$(compgen -G "${contents}/*/*/bin/clang" | head -1 || true)"
  [ -n "$clang" ] || return 0
  dirname "$(dirname "$(dirname "$clang")")"
}

llvm_restore() {
  local stage="$1" contents="$2" d name restored=""
  [ -d "$stage" ] || return 0
  mkdir -p "$contents"
  for d in "$stage"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ -e "${contents}/${name}" ]; then
      # Something already put this hash in place (another cache layer). Keep
      # it: overwriting would be a guess about which copy Bazel will accept.
      echo "llvm-cache-stage: ${contents}/${name} already exists; leaving it" >&2
      restored="${contents}/${name}"
      continue
    fi
    mv "${d%/}" "${contents}/${name}"
    restored="${contents}/${name}"
  done
  # Leave no empty <stage> behind: the post step would save an EMPTY entry
  # under this key, and every later run would then hit it and gain nothing.
  rm -rf "$stage"
  [ -z "$restored" ] || echo "$restored"
}

llvm_stage() {
  local stage="$1" contents="$2" live
  live="$(llvm_live_dir "$contents")"
  if [ -z "$live" ]; then
    # Nothing extracted (a lane that never needed clang). With no <stage>,
    # the post step finds no path and saves nothing -- correct.
    echo "llvm-cache-stage: no extracted LLVM under ${contents}; nothing to stage" >&2
    return 0
  fi
  rm -rf "$stage"
  mkdir -p "$stage"
  # Hard links: instant, no extra disk, and the live tree stays in place for
  # any step that still runs Bazel after this one.
  if ! cp -al "$live" "$stage/" 2>/dev/null; then
    rm -rf "$stage"
    echo "llvm-cache-stage: cannot hard-link ${live} into ${stage} (different filesystems?); not staging rather than copying ~8GB" >&2
    return 1
  fi
  basename "$live"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    restore) [ $# -eq 3 ] || { echo "usage: $0 restore <stage> <contents>" >&2; return 2; }; llvm_restore "$2" "$3" ;;
    stage)   [ $# -eq 3 ] || { echo "usage: $0 stage <stage> <contents>" >&2; return 2; }; llvm_stage "$2" "$3" ;;
    live)    [ $# -eq 2 ] || { echo "usage: $0 live <contents>" >&2; return 2; }; llvm_live_dir "$2" ;;
    *) echo "usage: $0 {restore|stage|live} ..." >&2; return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
