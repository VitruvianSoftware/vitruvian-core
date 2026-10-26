// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! gate-evaluator.sh — Synthetic Status Gate Aggregator Evaluator.
//! Evaluates upstream CI/presubmit job results with strict fail-closed
//! invariants. Exits 0 on legitimate success/skip, exits 1 on
//! failure/cancellation.

use shell_compat::{env_or, err, out};

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let orchestrate = env_or("ORCHESTRATE_RESULT", b"unknown");
    let pipeline_units = env_or("PIPELINE_UNITS_RESULT", b"unknown");
    let lint_naming = env_or("LINT_NAMING_RESULT", b"unknown");
    let license_check = env_or("LICENSE_CHECK_RESULT", b"unknown");
    let go_race = env_or("GO_RACE_RESULT", b"unknown");
    let docs_only = env_or("DOCS_ONLY", b"false");
    let affected_count_s = env_or("AFFECTED_COUNT", b"0");

    out(b"========================================================\n");
    out(b"          Presubmit Gate Status Aggregator              \n");
    out(b"========================================================\n");
    out(&shell_compat::cat(&[
        b"Orchestrator Result:    ",
        &orchestrate,
        b"\n",
    ]));
    out(&shell_compat::cat(&[
        b"Pipeline Units Result:  ",
        &pipeline_units,
        b" (Affected: ",
        &affected_count_s,
        b", Docs-only: ",
        &docs_only,
        b")\n",
    ]));
    out(&shell_compat::cat(&[
        b"Lint Naming Result:     ",
        &lint_naming,
        b"\n",
    ]));
    out(&shell_compat::cat(&[
        b"License Check Result:   ",
        &license_check,
        b"\n",
    ]));
    out(&shell_compat::cat(&[
        b"Go Race Result:         ",
        &go_race,
        b"\n",
    ]));
    out(b"========================================================\n");

    let mut failed = false;

    // Invariant 1: Orchestrator MUST succeed
    if orchestrate != b"success" {
        err(&shell_compat::cat(&[
            b"::error::Orchestrator failed or was cancelled (result: ",
            &orchestrate,
            b")\n",
        ]));
        failed = true;
    }

    // Invariant 2: Dynamic pipeline units must be success OR skipped (0 affected)
    match pipeline_units.as_slice() {
        b"success" => {
            out(b"\xe2\x9c\x93 Dynamic pipeline units passed cleanly.\n");
        }
        b"skipped" => {
            let affected_count: i64 = std::str::from_utf8(&affected_count_s)
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
            if docs_only == b"true" || affected_count == 0 {
                out(b"\xe2\x9c\x93 Dynamic pipeline units skipped cleanly (0 affected units / docs-only).\n");
            } else {
                err(&shell_compat::cat(&[
                    b"::error::Dynamic pipeline units were skipped unexpectedly when ",
                    &affected_count_s,
                    b" units were affected.\n",
                ]));
                failed = true;
            }
        }
        _ => {
            err(&shell_compat::cat(&[
                b"::error::Dynamic pipeline units failed or were cancelled (result: ",
                &pipeline_units,
                b")\n",
            ]));
            failed = true;
        }
    }

    // Invariant 3: Static invariant checks must succeed or be skipped
    let checks: [(&[u8], &[u8]); 3] = [
        (b"lint-naming", &lint_naming),
        (b"license-check", &license_check),
        (b"go-race", &go_race),
    ];
    for (name, res) in &checks {
        match res.as_ref() {
            b"success" | b"skipped" => {
                out(&shell_compat::cat(&[
                    b"\xe2\x9c\x93 ",
                    name,
                    b" check passed (",
                    res,
                    b").\n",
                ]));
            }
            _ => {
                err(&shell_compat::cat(&[
                    b"::error::Static check '",
                    name,
                    b"' failed (result: ",
                    res,
                    b")\n",
                ]));
                failed = true;
            }
        }
    }

    out(b"========================================================\n");
    if failed {
        out(
            b"\xe2\x9c\x97 GATE VERDICT: FAILED \xe2\x80\x94 one or more required checks failed.\n",
        );
        1
    } else {
        out(b"\xe2\x9c\x93 GATE VERDICT: ALL REQUIRED CHECKS PASSED\n");
        0
    }
}
