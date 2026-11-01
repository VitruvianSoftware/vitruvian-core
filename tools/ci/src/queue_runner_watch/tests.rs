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

//! Black-box tests for //tools/ci:queue_runner_watch: each decision the
//! watcher makes, with a fake gh that answers the canary's state and the
//! variable's value and logs every call. Runs the REAL binary, as the
//! queue-runner-watch workflow does. Ported case for case from the former
//! queue-runner-watch_test.sh.

use ci_testkit::{bin, read, write_exe, Output, Run, TempDir};

const FAKE_GH: &str = r#"#!/usr/bin/env bash
echo "$*" >>"$FAKE_DIR/calls"
case "$*" in
  *"/jobs"*) if [ "${FAKE_NOJOB:-}" = 1 ]; then :; else echo "$FAKE_CANARY"; fi ;;
  # The real gh prints the API's error body on STDOUT for a 404, then exits 1.
  *"/variables/QUEUE_RUNNER_FALLBACK"*"--jq"*)
    if [ "$FAKE_VAR" = missing ]; then
      echo '{"message":"Not Found","documentation_url":"https://docs.github.com/rest/actions/variables#get-a-repository-variable","status":"404"}'
      exit 1
    fi
    echo "$FAKE_VAR" ;;
esac
"#;

struct Watch {
    dir: TempDir,
}

struct Ran {
    out: Output,
    calls: String,
}

impl Ran {
    fn wrote(&self, needle: &str) -> bool {
        self.calls.contains(needle)
    }
    fn no_write(&self) -> bool {
        !self.calls.lines().any(|l| {
            (l.contains("-X PATCH ") || l.contains("-X POST "))
                && l.contains("repos/o/r/actions/variables")
        })
    }
    fn why(&self) -> String {
        format!(
            "rc={} out={:?} calls={:?}",
            self.out.code,
            self.out.all(),
            self.calls
        )
    }
}

impl Watch {
    fn new() -> Watch {
        let dir = TempDir::new();
        write_exe(dir.join("gh"), FAKE_GH);
        Watch { dir }
    }

    /// The shell suite's run <canary state> <variable value> [nojob].
    fn run(&self, canary: &str, var: &str, nojob: bool) -> Ran {
        let _ = std::fs::remove_file(self.dir.join("calls"));
        let out = Run::new(&bin("BIN"))
            .env("FAKE_DIR", self.dir.path())
            .env("FAKE_CANARY", canary)
            .env("FAKE_VAR", var)
            .env("FAKE_NOJOB", if nojob { "1" } else { "" })
            .env("GH_BIN", self.dir.join("gh"))
            .env("REPO", "o/r")
            .env("RUN_ID", "7")
            .env("WAIT_SECONDS", "0")
            .env_remove("CANARY_JOB")
            .go();
        Ran {
            out,
            calls: read(self.dir.join("calls")),
        }
    }
}

const PATCH: &str = "-X PATCH repos/o/r/actions/variables/QUEUE_RUNNER_FALLBACK -f value=";

// == healthy canary ==

#[test]
fn a_canary_that_is_running_clears_the_fallback() {
    let r = Watch::new().run("in_progress ", "on", false);
    assert!(
        r.out.code == 0 && r.wrote(&format!("{PATCH}off")),
        "{}",
        r.why()
    );
}

#[test]
fn a_canary_that_finished_clears_the_fallback() {
    let r = Watch::new().run("completed success", "on", false);
    assert!(r.wrote("-f value=off"), "{}", r.why());
}

#[test]
fn already_off_writes_nothing() {
    let r = Watch::new().run("in_progress ", "off", false);
    assert!(r.out.code == 0 && r.no_write(), "{}", r.why());
}

// == unhealthy canary ==

#[test]
fn a_canary_nobody_took_sets_the_fallback_warns_and_is_cancelled() {
    let r = Watch::new().run("queued ", "off", false);
    assert!(
        r.out.code == 0
            && r.wrote(&format!("{PATCH}on"))
            && r.wrote("-X POST repos/o/r/actions/runs/7/cancel")
            && r.out.all().contains("::warning::"),
        "{}",
        r.why()
    );
}

#[test]
fn a_canary_that_failed_sets_the_fallback_with_nothing_to_cancel() {
    let r = Watch::new().run("completed failure", "off", false);
    assert!(r.wrote("-f value=on") && !r.wrote("/cancel"), "{}", r.why());
}

#[test]
fn a_canary_waiting_for_approval_or_capacity_sets_the_fallback() {
    let r = Watch::new().run("waiting ", "off", false);
    assert!(r.wrote("-f value=on"), "{}", r.why());
}

#[test]
fn already_on_is_not_rewritten_but_the_stuck_canary_is_still_cancelled() {
    let r = Watch::new().run("queued ", "on", false);
    assert!(
        r.out.code == 0 && r.no_write() && r.wrote("/cancel"),
        "{}",
        r.why()
    );
}

// == first run: the variable does not exist yet ==

#[test]
fn a_missing_variable_is_created_as_on() {
    let r = Watch::new().run("queued ", "missing", false);
    assert!(
        r.wrote("-X POST repos/o/r/actions/variables -f name=QUEUE_RUNNER_FALLBACK -f value=on"),
        "{}",
        r.why()
    );
}

#[test]
fn a_missing_variable_is_created_as_off_when_the_canary_runs() {
    let r = Watch::new().run("in_progress ", "missing", false);
    assert!(
        r.wrote("-X POST repos/o/r/actions/variables -f name=QUEUE_RUNNER_FALLBACK -f value=off"),
        "{}",
        r.why()
    );
}

// == cannot decide ==

#[test]
fn no_canary_job_in_the_run_fails_and_changes_nothing() {
    let r = Watch::new().run("", "on", true);
    assert!(r.out.code != 0 && r.no_write(), "{}", r.why());
    assert!(
        r.out.stderr.contains("no job named 'canary' in run 7"),
        "{}",
        r.why()
    );
}

#[test]
fn repo_and_run_id_are_required() {
    let w = Watch::new();
    for missing in ["REPO", "RUN_ID"] {
        let o = Run::new(&bin("BIN"))
            .env("FAKE_DIR", w.dir.path())
            .env("GH_BIN", w.dir.join("gh"))
            .env("REPO", "o/r")
            .env("RUN_ID", "7")
            .env("WAIT_SECONDS", "0")
            .env_remove(missing)
            .go();
        assert_ne!(o.code, 0, "ran without {missing}: {o:?}");
        assert_eq!(read(w.dir.join("calls")), "", "called gh without {missing}");
    }
}
