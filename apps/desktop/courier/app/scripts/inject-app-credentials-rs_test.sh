#!/bin/bash
# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Wrapper that runs inject_app_credentials_test.sh against the Rust binary.
# The test's line 206 calls `bash -x "$injector" "$app"` which only works for
# a shell script. This shim intercepts that call pattern and execs the Rust
# binary directly.
set -euo pipefail

mkdir -p "$TEST_TMPDIR/bash-shim"
cat >"$TEST_TMPDIR/bash-shim/bash" <<'SHIM'
#!/bin/bash
# Intercept `bash -x <non-script-binary> ...` and exec the binary directly.
for arg in "$@"; do
  case "$arg" in -x) continue ;; -*) continue ;; *)
    if [ -f "$arg" ] && [ -x "$arg" ]; then
      head_bytes="$(head -c 2 "$arg" 2>/dev/null || true)"
      if [ "$head_bytes" != "#!" ]; then
        # Drop flags preceding the binary (e.g. -x)
        while [ "$#" -gt 0 ]; do
          case "$1" in -*) shift ;; *) break ;; esac
        done
        exec "$@"
      fi
    fi
    break
    ;;
  esac
done
exec /bin/bash "$@"
SHIM
chmod 755 "$TEST_TMPDIR/bash-shim/bash"
export PATH="$TEST_TMPDIR/bash-shim:$PATH"

exec "$(dirname "$0")/scripts/inject_app_credentials_test.sh" "$@"
