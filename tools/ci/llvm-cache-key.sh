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
# llvm-cache-key.sh — derive the Actions cache key for the extracted LLVM
# toolchain (the llvm-cache-restore composite). Prints the key to stdout.
#
# WHY /etc/os-release is part of the key. toolchains_llvm picks its LLVM
# distribution in `_linux_dist()`, which does:
#
#     for line in rctx.read("/etc/os-release").splitlines():
#
# An `rctx.read()` of a path outside the repo is a RECORDED INPUT of the
# `llvm_toolchain_llvm` repo rule. Bazel 9 re-reads every recorded input on
# each build and REJECTS the cached repo contents when a digest moved -- so
# the key has to move with that file or the cache goes to dead weight:
#
#   1. GitHub rolls a runner-image point release (24.04.4 -> 24.04.5, image
#      20260831.293 -> 20260907.300). /etc/os-release changes.
#   2. The key was keyed only on MODULE.bazel, so it still HITS. ~2.2GB of
#      the old image's extraction is downloaded and unpacked (~28-38s).
#   3. Bazel's recorded-inputs check rejects all of it and re-extracts LLVM
#      anyway (98-264s, per the llvm-cache-restore header).
#   4. actions/cache does not save on an exact primary-key hit ("Cache hit
#      occurred on the primary key ..., not saving cache"), so the freshly
#      extracted contents are NEVER persisted -- step 2-3 repeats on every
#      run, on every lane, until MODULE.bazel happens to change.
#
# That is not a slow rot: it turns red the moment the new image reaches a
# runner, because the llvm-cache-tripwire composite (correctly) fails a job
# that restored a hit and re-extracted anyway. Observed 2026-09-08 on #2242.
#
# Keying on the file's digest makes the image roll a one-run cache MISS -- the
# tripwire's benign "expected once" branch -- and the post step then saves an
# entry that actually validates. Hash the WHOLE file, not a parsed field:
# Bazel digests the whole file, so anything narrower would call two files
# identical that Bazel calls different, which is the bug all over again.
#
# Deliberately NO restore-keys: a prefix match would restore an entry built
# under a different /etc/os-release, which is exactly the rejected-contents
# state this exists to avoid. A miss is correct and self-healing.
#
# Usage: llvm-cache-key.sh <runner-os> <module-bazel-hash> [os-release-path]

set -euo pipefail

# llvm_cache_key(runner_os, module_hash, os_release_path) -- pure, no GitHub
# context, so it is unit-testable standalone. A missing/unreadable os-release
# (macOS, a slim container) degrades to a fixed marker rather than failing:
# the pinned content path is Linux-only anyway, and a key that cannot be
# derived must still be stable rather than random.
llvm_cache_key() {
  local runner_os="$1" module_hash="$2" os_release_path="${3:-/etc/os-release}"
  local osrel digest
  if [ -r "${os_release_path}" ]; then
    # `local osrel="$(...)"` would MASK the command substitution's exit status
    # behind local's own -- so a missing digest tool silently produced an empty
    # segment, collapsing every os-release back onto one key: the exact bug
    # this script exists to prevent, reintroduced invisibly. Assign separately
    # and fail closed. sha256sum is coreutils (Linux runners); shasum is the
    # macOS/BSD spelling, needed because the unit test runs on a dev machine.
    digest=""
    if command -v sha256sum >/dev/null 2>&1; then
      digest="$(sha256sum "${os_release_path}")" || digest=""
    elif command -v shasum >/dev/null 2>&1; then
      digest="$(shasum -a 256 "${os_release_path}")" || digest=""
    fi
    if [ -z "${digest}" ]; then
      echo "::error::llvm-cache-key: no sha256 tool (sha256sum/shasum) could digest ${os_release_path}; refusing to emit a key that would silently ignore it" >&2
      return 1
    fi
    osrel="${digest:0:16}"
  else
    osrel="noosrelease"
  fi
  printf 'llvm-contents-v2-%s-%s-%s' "${runner_os}" "${osrel}" "${module_hash}"
}

main() {
  local runner_os="${1:?runner os required}" module_hash="${2:?MODULE.bazel hash required}"
  local os_release_path="${3:-/etc/os-release}"
  llvm_cache_key "${runner_os}" "${module_hash}" "${os_release_path}"
}

# Source-safe: main() runs only when executed, not when sourced by the tests.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
