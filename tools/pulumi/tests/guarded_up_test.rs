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

//! Integration tests for //tools/pulumi:guarded-up with stubbed `pulumi` and `sleep`.

mod common;
use common::*;

const CONFLICT: &str = "error: [409] Conflict: concurrent update in progress";

fn run_guarded(
    up_fail_times: u32,
    second_preview_destructive: bool,
) -> (std::process::Output, Vec<String>, String) {
    let d = tempdir("guarded-up");
    let stubs = d.join("stubs");
    let calls = d.join("calls.log");
    let sleeps = d.join("sleeps.log");
    write_exec(
        &stubs.join("sleep"),
        "#!/usr/bin/env bash\necho \"$1\" >> \"$SLEEP_LOG\"\n",
    );
    write_exec(
        &stubs.join("pulumi"),
        r#"#!/usr/bin/env bash
set -euo pipefail
sub="${1:-}"
case "$sub" in
  preview)
    p=0
    [ -f "$PREVIEW_COUNT" ] && p="$(cat "$PREVIEW_COUNT")"
    p=$((p + 1))
    echo "$p" > "$PREVIEW_COUNT"
    echo "preview:$p" >> "$CALL_LOG"
    if [ "$p" -ge 2 ] && [ "${SECOND_PREVIEW_DESTRUCTIVE:-0}" = "1" ]; then
      echo '{"steps":[{"op":"delete","urn":"urn:pulumi:p::s::t::res"}],"changeSummary":{"delete":1}}'
    else
      echo '{"steps":[{"op":"same","urn":"urn:pulumi:p::s::t::res"}],"changeSummary":{"same":1}}'
    fi
    exit 0
    ;;
  up)
    u=0
    [ -f "$UP_COUNT" ] && u="$(cat "$UP_COUNT")"
    u=$((u + 1))
    echo "$u" > "$UP_COUNT"
    echo "up:$u" >> "$CALL_LOG"
    if [ "$u" -le "${UP_FAIL_TIMES:-0}" ]; then
      echo "$CONFLICT_MSG" >&2
      exit 23
    fi
    echo "Updating (production):"
    exit 0
    ;;
  *)
    exit 99
    ;;
esac
"#,
    );
    let mut c = cmd(
        &bin("GUARDED_UP_BIN"),
        &format!("{}:/usr/bin:/bin", stubs.display()),
    );
    c.env("CALL_LOG", &calls)
        .env("SLEEP_LOG", &sleeps)
        .env("PREVIEW_COUNT", d.join("preview.count"))
        .env("UP_COUNT", d.join("up.count"))
        .env("UP_FAIL_TIMES", up_fail_times.to_string())
        .env(
            "SECOND_PREVIEW_DESTRUCTIVE",
            if second_preview_destructive { "1" } else { "0" },
        )
        .env("CONFLICT_MSG", CONFLICT)
        .env("PULUMI_CONFLICT_RETRY_DELAY", "1")
        .env("PULUMI_CONFLICT_MAX_DELAY", "2")
        .arg("sentry production");
    let o = run(c);
    let call_lines = read(&calls).lines().map(str::to_string).collect();
    (o, call_lines, read(&sleeps))
}

#[test]
fn happy_path_runs_preview_guard_then_up() {
    let (o, calls, sleeps) = run_guarded(0, false);
    assert_eq!(code(&o), 0, "stderr: {}", stderr(&o));
    assert_eq!(calls, vec!["preview:1", "up:1"]);
    assert_eq!(sleeps, "");
    assert!(stdout(&o).contains("plan-guard (sentry production): non-destructive"));
    assert!(stdout(&o).contains("Updating (production):"));
}

#[test]
fn conflict_409_on_up_reruns_preview_and_guard_before_next_up() {
    let (o, calls, sleeps) = run_guarded(1, false);
    assert_eq!(code(&o), 0, "stderr: {}", stderr(&o));
    assert_eq!(calls, vec!["preview:1", "up:1", "preview:2", "up:2"]);
    assert_eq!(sleeps, "1\n");
}

#[test]
fn conflict_409_followed_by_destructive_preview_stops_before_up() {
    let (o, calls, sleeps) = run_guarded(1, true);
    assert_eq!(code(&o), 1);
    assert_eq!(calls, vec!["preview:1", "up:1", "preview:2"]);
    assert_eq!(sleeps, "1\n");
    assert!(stderr(&o).contains("Refusing to apply sentry production"));
}

#[test]
fn duplicate_key_in_preview_plan_stops_before_up() {
    let d = tempdir("guarded-up-dup-key");
    let stubs = d.join("stubs");
    let calls = d.join("calls.log");
    write_exec(
        &stubs.join("pulumi"),
        r#"#!/usr/bin/env bash
set -euo pipefail
sub="${1:-}"
case "$sub" in
  preview)
    echo "preview:1" >> "$CALL_LOG"
    echo '{"steps":[{"op":"same","op":"delete","urn":"urn:pulumi:p::s::t::res"}],"changeSummary":{"same":1}}'
    exit 0
    ;;
  up)
    echo "up:1" >> "$CALL_LOG"
    echo "Updating (production):"
    exit 0
    ;;
  *)
    exit 99
    ;;
esac
"#,
    );
    let mut c = cmd(
        &bin("GUARDED_UP_BIN"),
        &format!("{}:/usr/bin:/bin", stubs.display()),
    );
    c.env("CALL_LOG", &calls).arg("sentry-pagerduty production");
    let o = run(c);
    let call_lines: Vec<String> = read(&calls).lines().map(str::to_string).collect();
    assert_eq!(code(&o), 1, "stderr: {}", stderr(&o));
    assert_eq!(
        call_lines,
        vec!["preview:1"],
        "duplicate key in preview JSON must stop guarded-up before pulumi up"
    );
    assert!(
        stderr(&o).contains("duplicate JSON object key"),
        "expected duplicate-key error in stderr, got: {}",
        stderr(&o)
    );
}

#[test]
fn bad_cli_usage_exits_2() {
    for args in [
        &[][..],
        &["a", "b"][..],
        &[""][..],
        &["a", "--allow-destroy-from-event"][..],
        &["a", "--bogus"][..],
    ] {
        let mut c = cmd(&bin("GUARDED_UP_BIN"), "/usr/bin:/bin");
        c.args(args);
        let o = run(c);
        assert_eq!(code(&o), 2, "args: {args:?}");
        assert!(stderr(&o).contains("usage: guarded-up"));
    }
}

#[test]
fn approved_delete_is_applied_and_unapproved_one_is_not() {
    const URN: &str =
        "urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-old";
    for (approved, want_rc, want_calls) in [
        (true, 0, vec!["preview:1", "up:1"]),
        (false, 1, vec!["preview:1"]),
    ] {
        let d = tempdir("guarded-up-allow");
        let stubs = d.join("stubs");
        let calls = d.join("calls.log");
        write_exec(
            &stubs.join("pulumi"),
            &format!(
                r#"#!/usr/bin/env bash
set -euo pipefail
case "${{1:-}}" in
  preview)
    echo "preview:1" >> "$CALL_LOG"
    echo '{{"steps":[{{"op":"delete","urn":"{URN}"}}],"changeSummary":{{"delete":1}}}}'
    ;;
  up)
    echo "up:1" >> "$CALL_LOG"
    ;;
  *) exit 99 ;;
esac
"#
            ),
        );
        let msg = if approved {
            format!("Allow-destroy: {URN}")
        } else {
            "no approval here".to_string()
        };
        let event = d.join("event.json");
        std::fs::write(
            &event,
            format!(r#"{{"commits":[{{"message":"chore: x\n\n{msg}"}}]}}"#),
        )
        .unwrap();
        let mut c = cmd(
            &bin("GUARDED_UP_BIN"),
            &format!("{}:/usr/bin:/bin", stubs.display()),
        );
        c.env("CALL_LOG", &calls)
            .arg("sentry production")
            .arg("--allow-destroy-from-event")
            .arg(&event);
        let o = run(c);
        let got: Vec<String> = read(&calls).lines().map(str::to_string).collect();
        assert_eq!(
            code(&o),
            want_rc,
            "approved={approved} stderr: {}",
            stderr(&o)
        );
        assert_eq!(got, want_calls, "approved={approved}");
    }
}

#[test]
fn approval_still_holds_on_the_replan_after_a_409() {
    const URN: &str =
        "urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-old";
    let d = tempdir("guarded-up-allow-409");
    let stubs = d.join("stubs");
    let calls = d.join("calls.log");
    write_exec(&stubs.join("sleep"), "#!/usr/bin/env bash\nexit 0\n");
    write_exec(
        &stubs.join("pulumi"),
        &format!(
            r#"#!/usr/bin/env bash
set -euo pipefail
case "${{1:-}}" in
  preview)
    echo "preview" >> "$CALL_LOG"
    echo '{{"steps":[{{"op":"delete","urn":"{URN}"}}],"changeSummary":{{"delete":1}}}}'
    ;;
  up)
    echo "up" >> "$CALL_LOG"
    if [ ! -f "$UP_ONCE" ]; then
      touch "$UP_ONCE"
      echo "error: [409] Conflict: concurrent update in progress" >&2
      exit 23
    fi
    ;;
  *) exit 99 ;;
esac
"#
        ),
    );
    let event = d.join("event.json");
    std::fs::write(
        &event,
        format!(r#"{{"commits":[{{"message":"chore: x\n\nAllow-destroy: {URN}"}}]}}"#),
    )
    .unwrap();
    let mut c = cmd(
        &bin("GUARDED_UP_BIN"),
        &format!("{}:/usr/bin:/bin", stubs.display()),
    );
    c.env("CALL_LOG", &calls)
        .env("UP_ONCE", d.join("up.once"))
        .env("PULUMI_CONFLICT_RETRY_DELAY", "1")
        .env("PULUMI_CONFLICT_MAX_DELAY", "1")
        .arg("sentry production")
        .arg("--allow-destroy-from-event")
        .arg(&event);
    let o = run(c);
    let got: Vec<String> = read(&calls).lines().map(str::to_string).collect();
    assert_eq!(code(&o), 0, "stderr: {}", stderr(&o));
    assert_eq!(got, vec!["preview", "up", "preview", "up"]);
    assert_eq!(
        stdout(&o).matches("approved by Allow-destroy").count(),
        2,
        "both plans must be checked against the approval: {}",
        stdout(&o)
    );
}
