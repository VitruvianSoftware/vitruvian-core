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
"""Parity test suite verifying 100% exit-code and byte-for-byte diagnostic
parity between Python `conformance.py` and native Rust `conformance_rs` across
`reference-tool`, `reference-tool-2`, and every broken-tool scenario in
`conformance_test.py`."""

import contextlib
import io
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import conformance
import conformance_test


def find_rs_binary():
    if len(sys.argv) > 1 and os.path.exists(sys.argv[1]):
        return os.path.abspath(sys.argv[1])
    candidates = [
        os.path.join(os.path.dirname(HERE), "conformance-rs"),
        os.path.join(os.path.dirname(HERE), "conformance_rs"),
    ]
    for candidate in candidates:
        if os.path.exists(candidate):
            return os.path.abspath(candidate)
    raise FileNotFoundError(f"conformance-rs binary not found (checked {candidates})")


RS_BINARY = find_rs_binary()
PARITY_FAILURES = []
CASES_CHECKED = 0


def run_rs(folder, *options):
    proc = subprocess.run(
        [RS_BINARY, folder, "--via", sys.executable, *options],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode, proc.stdout


def parity_check(folder, *options):
    global CASES_CHECKED
    CASES_CHECKED += 1
    how = os.environ.get("BROKEN_HOW", "")
    if how == "never stops writing":
        # `never stops writing` writes a single BROKEN_PIDFILE in `folder`,
        # so run `conformance_rs` directly for that timing-sensitive check.
        return run_rs(folder, *options)

    # Start `conformance_rs` in the background while Python `conformance.main`
    # runs in-process so timeout tests execute in parallel.
    rs_proc = subprocess.Popen(
        [RS_BINARY, folder, "--via", sys.executable, *options],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    py_out_buf = io.StringIO()
    with contextlib.redirect_stdout(py_out_buf):
        py_status = conformance.main([folder, "--via", sys.executable, *options])
    py_printed = py_out_buf.getvalue()
    rs_printed, rs_stderr = rs_proc.communicate()
    rs_status = rs_proc.returncode

    if rs_status != py_status or rs_printed != py_printed:
        PARITY_FAILURES.append(
            f"parity mismatch for folder={folder!r} options={options!r} BROKEN_HOW={how!r}:\n"
            f"  python status={py_status}, rust status={rs_status}\n"
            f"  python stdout:\n{py_printed}\n"
            f"  rust stdout:\n{rs_printed}\n"
            f"  rust stderr:\n{rs_stderr}"
        )
    return rs_status, rs_printed


def main():
    conformance_test.check = parity_check
    rc = conformance_test.main()
    if PARITY_FAILURES:
        for failure in PARITY_FAILURES:
            print(failure, file=sys.stderr)
        print(
            f"conformance_rs_parity: FAILED ({len(PARITY_FAILURES)} mismatches across {CASES_CHECKED} runs)",
            file=sys.stderr,
        )
        return 1
    print(f"conformance_rs_parity: OK ({CASES_CHECKED} runs matched byte-for-byte)")
    return rc


if __name__ == "__main__":
    sys.exit(main())
