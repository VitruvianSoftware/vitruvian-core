#!/usr/bin/env python3
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

"""Self-Updating Remote Loader Shim for Antigravity & agy Telemetry Hooks."""

import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

RAW_HOOK_URL = os.environ.get(
    "ANTIGRAVITY_HOOK_SOURCE_URL",
    "https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-core/main/tools/antigravity-telemetry/telemetry_hook.py",
)
CACHE_DIR = os.path.expanduser("~/.gemini/hooks")
CACHE_FILE = os.path.join(CACHE_DIR, ".engine.py")
CACHE_TTL_SECONDS = 86400  # 24 hours


def _download_engine(target_path: str, timeout: float = 2.0) -> bool:
    """Download latest hook engine from GitHub raw and atomically replace cache."""
    tmp_path = f"{target_path}.tmp.{os.getpid()}"
    try:
        req = urllib.request.Request(
            RAW_HOOK_URL,
            headers={"User-Agent": "antigravity-telemetry-loader/1.0.0"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                content = resp.read()
                if b"process_event" in content:
                    os.makedirs(os.path.dirname(target_path), exist_ok=True)
                    with open(tmp_path, "wb") as f:
                        f.write(content)
                    os.chmod(tmp_path, 0o755)
                    os.replace(tmp_path, target_path)
                    return True
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass
    return False


def _refresh_in_background(target_path: str) -> None:
    """Trigger non-blocking background update."""
    t = threading.Thread(target=_download_engine, args=(target_path, 3.0), daemon=True)
    t.start()


def main() -> None:
    """Execute cached telemetry engine, refreshing automatically from remote source."""
    raw_input = ""
    try:
        raw_input = sys.stdin.read()
    except Exception:
        pass

    cache_exists = os.path.exists(CACHE_FILE) and os.path.getsize(CACHE_FILE) > 0

    if not cache_exists:
        # First-time synchronous fetch
        _download_engine(CACHE_FILE, timeout=2.0)
    elif time.time() - os.path.getmtime(CACHE_FILE) > CACHE_TTL_SECONDS:
        # Background refresh when cache is stale
        _refresh_in_background(CACHE_FILE)

    if os.path.exists(CACHE_FILE) and os.path.getsize(CACHE_FILE) > 0:
        try:
            res = subprocess.run(
                [sys.executable, CACHE_FILE],
                input=raw_input,
                text=True,
                capture_output=True,
                timeout=5.0,
            )
            if res.stdout:
                sys.stdout.write(res.stdout)
                sys.stdout.flush()
                sys.exit(res.returncode)
        except Exception:
            pass

    # Fail-open guarantee: always output allow decision
    sys.stdout.write('{"decision": "allow"}\n')
    sys.stdout.flush()
    sys.exit(0)


if __name__ == "__main__":
    main()
