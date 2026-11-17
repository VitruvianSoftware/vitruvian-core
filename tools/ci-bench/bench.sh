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

# THROWAWAY: shared helpers for .github/workflows/bench-ci-speed.yaml on the
# exp/ci-speed-bench branch. This branch is never merged.
#
#   bench.sh compression   A/B --remote_cache_compression on one runner
#   bench.sh downloader    repo-cache tarball vs origin vs BuildBuddy remote downloader
#
# Env: BUILDBUDDY_API_KEY, BENCH_TARGETS (space separated), BENCH_EXTRA (space
# separated extra bazel flags).
set -euo pipefail

now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }

# Bytes received on every non-loopback interface since boot.
rx() {
  python3 - <<'PY'
import platform, subprocess
total = 0
if platform.system() == "Linux":
    for line in open("/proc/net/dev").read().splitlines()[2:]:
        name, rest = line.split(":", 1)
        if name.strip() != "lo":
            total += int(rest.split()[0])
else:
    out = subprocess.run(["netstat", "-ibn"], capture_output=True, text=True).stdout
    for line in out.splitlines()[1:]:
        f = line.split()
        if len(f) < 10 or f[0].startswith("lo") or "<Link#" not in line:
            continue
        total += int(f[-5])
print(total)
PY
}

read -r -a TARGETS <<<"${BENCH_TARGETS:-//none}"
EXTRA=()
if [ -n "${BENCH_EXTRA:-}" ]; then read -r -a EXTRA <<<"${BENCH_EXTRA}"; fi
BASE=(--config=remotecache "--remote_header=x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}")
if [ "${#EXTRA[@]}" -gt 0 ]; then BASE+=("${EXTRA[@]}"); fi

row() { # label seconds rx_mb note
  printf 'BENCH|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"
  printf '| %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4" >>"$GITHUB_STEP_SUMMARY"
}

# timed <label> <bazel args...>
timed() {
  local label=$1
  shift
  local log="$RUNNER_TEMP/bench-${label// /_}.log"
  local r0 t0 t1 r1 rc=0
  r0=$(rx)
  t0=$(now)
  bazel "$@" >"$log" 2>&1 || rc=$?
  t1=$(now)
  r1=$(rx)
  if [ "$rc" -ne 0 ]; then
    tail -n 60 "$log"
    row "$label" "FAILED rc=$rc" "-" "-"
    return "$rc"
  fi
  local note
  note=$(grep -Eo '[0-9,]+ process(es)?: .*' "$log" | tail -n 1 || true)
  [ -n "$note" ] || note=$(grep -Eo 'Analyzed [0-9]+ targets? \(.*' "$log" | tail -n 1 || true)
  row "$label" "$(python3 -c "print(f'{$t1-$t0:.1f}')")" "$(python3 -c "print(f'{($r1-$r0)/1e6:.0f}')")" "$note"
}

{
  echo "### bench: $1 on $(uname -s)"
  echo ""
  echo "| run | seconds | MB received | bazel |"
  echo "|---|---|---|---|"
} >>"$GITHUB_STEP_SUMMARY"

case "$1" in
compression)
  timed "prime (fetch + analysis)" build --nobuild "${BASE[@]}" "${TARGETS[@]}"
  i=0
  for spec in "toplevel off" "toplevel on" "toplevel on" "toplevel off" "all off" "all on" "all on" "all off"; do
    i=$((i + 1))
    mode=${spec% *}
    comp=${spec#* }
    flags=("--remote_download_outputs=${mode}")
    if [ "$comp" = on ]; then flags+=(--remote_cache_compression); else flags+=(--noremote_cache_compression); fi
    bazel clean >/dev/null 2>&1
    bazel build --nobuild "${BASE[@]}" "${flags[@]}" "${TARGETS[@]}" >/dev/null 2>&1
    timed "${i} ${mode} compression=${comp}" build "${BASE[@]}" "${flags[@]}" "${TARGETS[@]}"
  done
  ;;
downloader)
  repo_cache="$HOME/.cache/bazel-repo"
  DL=(--experimental_remote_downloader=grpcs://remote.buildbuddy.io --experimental_remote_downloader_local_fallback)
  wipe() {
    bazel clean --expunge >/dev/null 2>&1 || true
    rm -rf "$repo_cache"
    mkdir -p "$repo_cache"
  }
  found_kb=$(du -sk "$repo_cache" 2>/dev/null | cut -f1 || echo 0)
  echo "repository cache as found: $((found_kb / 1024)) MB"
  if [ "${found_kb:-0}" -gt 1000000 ]; then
    timed "1 tarball restored ($((found_kb / 1024)) MB), analysis" build --nobuild "${BASE[@]}" "${TARGETS[@]}"
    wipe
  fi
  timed "2 no cache, origin downloads" build --nobuild "${BASE[@]}" "${TARGETS[@]}"
  wipe
  timed "3 remote downloader, first use" build --nobuild "${BASE[@]}" "${DL[@]}" "${TARGETS[@]}"
  wipe
  timed "4 remote downloader, warm" build --nobuild "${BASE[@]}" "${DL[@]}" "${TARGETS[@]}"
  wipe
  timed "5 no cache, origin downloads (again)" build --nobuild "${BASE[@]}" "${TARGETS[@]}"
  ;;
split)
  # Fetch + analysis only, repository cache wiped before every run, so each
  # run pays for exactly the toolchains its targets need.
  repo_cache="$HOME/.cache/bazel-repo"
  wipe() {
    bazel clean --expunge >/dev/null 2>&1 || true
    rm -rf "$repo_cache"
    mkdir -p "$repo_cache"
  }
  P=//apps/desktop/vitruvian-courier/app
  VIEW=("$P:VitruvianCourierViewTests")
  SWIFT=("$P:VitruvianCourierViewTests" "$P:VitruvianCourierCoreTests")
  REST=("$P:VitruvianCourierCoreTests" "$P:app_holds_engine_test" "$P:engine_contract_test" "$P:inject_app_credentials_test" "$P:release_engine_has_no_seed_test")
  ALL=("${VIEW[@]}" "${REST[@]}")
  wipe
  timed "1 view tests only" build --nobuild "${BASE[@]}" "${VIEW[@]}"
  wipe
  timed "2 view + core tests" build --nobuild "${BASE[@]}" "${SWIFT[@]}"
  wipe
  timed "3 all six (today's unit)" build --nobuild "${BASE[@]}" "${ALL[@]}"
  wipe
  timed "4 all six (today's unit)" build --nobuild "${BASE[@]}" "${ALL[@]}"
  wipe
  timed "5 the five without view tests" build --nobuild "${BASE[@]}" "${REST[@]}"
  wipe
  timed "6 view + core tests" build --nobuild "${BASE[@]}" "${SWIFT[@]}"
  wipe
  timed "7 view tests only" build --nobuild "${BASE[@]}" "${VIEW[@]}"
  ;;
*)
  echo "usage: bench.sh compression|downloader|split" >&2
  exit 2
  ;;
esac
