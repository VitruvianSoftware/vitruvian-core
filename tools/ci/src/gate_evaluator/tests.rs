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

//! Black-box tests for //tools/ci:gate_evaluator, the presubmit gate that
//! turns upstream job results into one pass/fail. Ported case for case from
//! the former gate-evaluator_test.sh: each case runs the REAL binary with only
//! the result variables it names, so a variable leaking in from the runner
//! cannot decide the verdict.

use ci_testkit::{assert_has, bin, Output, Run};

/// Every input the evaluator reads; cleared before each case.
const INPUTS: [&str; 7] = [
    "ORCHESTRATE_RESULT",
    "PIPELINE_UNITS_RESULT",
    "LINT_NAMING_RESULT",
    "LICENSE_CHECK_RESULT",
    "GO_RACE_RESULT",
    "DOCS_ONLY",
    "AFFECTED_COUNT",
];

fn evaluate(vars: &[(&str, &str)]) -> Output {
    let mut run = Run::new(&bin("BIN"));
    for k in INPUTS {
        run = run.env_remove(k);
    }
    for (k, v) in vars {
        run = run.env(k, v);
    }
    run.go()
}

// Shell case 1: "All jobs green passes gate" (expected exit 0).
#[test]
fn all_jobs_green_passes_gate() {
    let o = evaluate(&[
        ("ORCHESTRATE_RESULT", "success"),
        ("PIPELINE_UNITS_RESULT", "success"),
        ("LINT_NAMING_RESULT", "success"),
        ("LICENSE_CHECK_RESULT", "success"),
        ("GO_RACE_RESULT", "success"),
        ("AFFECTED_COUNT", "2"),
    ]);
    assert_eq!(o.code, 0, "all green must pass\n{}", o.all());
    assert_has(
        &o.stdout,
        "GATE VERDICT: ALL REQUIRED CHECKS PASSED",
        "verdict",
    );
}

// Shell case 2: "Docs-only skip passes gate" (expected exit 0).
#[test]
fn docs_only_skip_passes_gate() {
    let o = evaluate(&[
        ("ORCHESTRATE_RESULT", "success"),
        ("PIPELINE_UNITS_RESULT", "skipped"),
        ("LINT_NAMING_RESULT", "success"),
        ("LICENSE_CHECK_RESULT", "success"),
        ("GO_RACE_RESULT", "skipped"),
        ("DOCS_ONLY", "true"),
        ("AFFECTED_COUNT", "0"),
    ]);
    assert_eq!(o.code, 0, "a docs-only skip must pass\n{}", o.all());
    assert_has(&o.stdout, "skipped cleanly", "skip line");
}

// Shell case 3: "Dynamic unit failure fails gate" (expected exit 1).
#[test]
fn dynamic_unit_failure_fails_gate() {
    let o = evaluate(&[
        ("ORCHESTRATE_RESULT", "success"),
        ("PIPELINE_UNITS_RESULT", "failure"),
        ("LINT_NAMING_RESULT", "success"),
        ("LICENSE_CHECK_RESULT", "success"),
        ("GO_RACE_RESULT", "success"),
    ]);
    assert_eq!(o.code, 1, "a failed unit must fail the gate\n{}", o.all());
    assert_has(
        &o.stderr,
        "::error::Dynamic pipeline units failed",
        "error line",
    );
}

// Shell case 4: "Orchestrator failure fails gate" (expected exit 1).
#[test]
fn orchestrator_failure_fails_gate() {
    let o = evaluate(&[
        ("ORCHESTRATE_RESULT", "failure"),
        ("PIPELINE_UNITS_RESULT", "skipped"),
        ("LINT_NAMING_RESULT", "success"),
    ]);
    assert_eq!(
        o.code,
        1,
        "a failed orchestrator must fail the gate\n{}",
        o.all()
    );
    assert_has(&o.stderr, "::error::Orchestrator failed", "error line");
}

// Shell case 5: "Lint naming failure fails gate" (expected exit 1).
#[test]
fn lint_naming_failure_fails_gate() {
    let o = evaluate(&[
        ("ORCHESTRATE_RESULT", "success"),
        ("PIPELINE_UNITS_RESULT", "success"),
        ("LINT_NAMING_RESULT", "failure"),
    ]);
    assert_eq!(
        o.code,
        1,
        "a failed static check must fail the gate\n{}",
        o.all()
    );
    assert_has(
        &o.stderr,
        "::error::Static check 'lint-naming' failed",
        "error line",
    );
}

// Shell cases 4 and 5 leave LICENSE_CHECK_RESULT unset, which reads as
// "unknown" and fails the gate on its own -- so they pass even when the
// invariant they name is broken. These variants keep every OTHER input green,
// so the named result is the only thing that can fail the gate.
fn all_green_except(name: &str, value: &str) -> Output {
    let mut vars = vec![
        ("ORCHESTRATE_RESULT", "success"),
        ("PIPELINE_UNITS_RESULT", "success"),
        ("LINT_NAMING_RESULT", "success"),
        ("LICENSE_CHECK_RESULT", "success"),
        ("GO_RACE_RESULT", "success"),
        ("AFFECTED_COUNT", "2"),
    ];
    for v in vars.iter_mut() {
        if v.0 == name {
            v.1 = value;
        }
    }
    evaluate(&vars)
}

#[test]
fn orchestrator_failure_alone_fails_gate() {
    let o = all_green_except("ORCHESTRATE_RESULT", "failure");
    assert_eq!(
        o.code,
        1,
        "an orchestrator failure alone must fail\n{}",
        o.all()
    );
}

#[test]
fn each_static_check_failure_alone_fails_gate() {
    for (var, name) in [
        ("LINT_NAMING_RESULT", "lint-naming"),
        ("LICENSE_CHECK_RESULT", "license-check"),
        ("GO_RACE_RESULT", "go-race"),
    ] {
        let o = all_green_except(var, "failure");
        assert_eq!(o.code, 1, "{var}=failure alone must fail\n{}", o.all());
        assert_has(
            &o.stderr,
            &format!("::error::Static check '{name}' failed"),
            var,
        );
    }
}

#[test]
fn skipped_units_with_affected_units_fails_gate() {
    let o = all_green_except("PIPELINE_UNITS_RESULT", "skipped");
    assert_eq!(
        o.code,
        1,
        "skipped units with 2 affected must fail\n{}",
        o.all()
    );
}
