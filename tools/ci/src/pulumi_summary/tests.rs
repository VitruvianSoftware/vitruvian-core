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

//! Black-box tests for //tools/ci:pulumi_summary, the digest
//! .github/actions/pulumi-summary renders from a `pulumi preview`/`up` log
//! onto the step summary and the sticky PR comment, and whose GITHUB_OUTPUT
//! counts the deploy gates key off. Runs the REAL binary on the fixtures
//! captured from real `pulumi {up,preview} --diff` output (testdata/pulumi,
//! pulumi v3.229.0). Ported case for case from the former
//! pulumi-summary_test.sh, plus byte-for-byte goldens produced by that script
//! (testdata/pulumi/*.digest.txt) and the parser details its sed/awk fixed.

use ci_testkit::{assert_has, assert_lacks, bin, read, write, Output, Run, TempDir};
use std::path::{Path, PathBuf};

fn data(name: &str) -> PathBuf {
    let p = Path::new("tools/ci/testdata/pulumi").join(name);
    std::fs::canonicalize(&p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))
}

fn run_file(label: &str, file: &Path, code: &str, env: &[(&str, &str)]) -> Output {
    let mut r = Run::new(&bin("BIN"))
        .env_remove("PULUMI_SUMMARY_RAW_MAX")
        .env_remove("PULUMI_SUMMARY_ROW_MAX")
        .env_remove("PULUMI_SUMMARY_COMMENT_LIMIT")
        .arg(label)
        .arg(file)
        .arg(code);
    for (k, v) in env {
        r = r.env(k, v);
    }
    r.go()
}

fn run(label: &str, fixture: &str, code: &str) -> Output {
    run_file(label, &data(fixture), code, &[])
}

/// Resource rows are the only lines with a backtick-wrapped Type cell.
fn resource_rows(out: &str) -> usize {
    out.lines().filter(|l| l.contains("| `")).count()
}

fn line_of(out: &str, needle: &str) -> usize {
    out.lines()
        .position(|l| l.contains(needle))
        .unwrap_or_else(|| panic!("no line with {needle:?}\n{out}"))
}

/// The counts a run appends to GITHUB_OUTPUT.
fn outputs(log: &str, code: &str) -> String {
    let t = TempDir::new();
    let plan = t.join("plan.txt");
    write(&plan, log);
    let gho = t.join("gho");
    write(&gho, "");
    let o = run_file(
        "gate-test",
        &plan,
        code,
        &[("GITHUB_OUTPUT", gho.to_str().unwrap())],
    );
    assert_eq!(o.code, 0, "{o:?}");
    read(&gho)
}

// --- byte-for-byte against the retired script ------------------------------

#[test]
fn up_mixed_digest_is_byte_identical_to_the_script() {
    let o = run("gcp-org", "up-mixed.txt", "0");
    assert_eq!(o.code, 0);
    assert_eq!(o.stdout, read(data("up-mixed.digest.txt")));
}

#[test]
fn up_fail_digest_is_byte_identical_to_the_script() {
    let o = run("gcp-bootstrap", "up-fail.txt", "1");
    assert_eq!(o.code, 0, "a failed pulumi run still renders, exit 0");
    assert_eq!(o.stdout, read(data("up-fail.digest.txt")));
}

// --- up --diff, mixed (create/replace/delete/same), success -----------------

#[test]
fn up_mixed_counts_destructive_rows_and_order() {
    let out = run("gcp-org", "up-mixed.txt", "0").stdout;
    assert_has(
        &out,
        "## 🏗️ gcp-org · pulumi up · production · ✅ Succeeded",
        "title",
    );
    assert_has(&out, "| 1 | 0 | 2 | 1 | 2 |", "counts row 1/0/2/1/2");
    assert_has(&out, "⚠️ **1 deleted, 2 replaced**", "risk callout");
    assert_has(
        &out,
        "➖ **Deleted** | `random:index/randomString:RandomString` | **str-a**",
        "deleted row bold + urn name",
    );
    assert_has(
        &out,
        "♻️ **Replaced** | `random:index/randomPet:RandomPet` | **pet-b**",
        "replaced row bold",
    );
    assert_has(
        &out,
        "➕ Created | `random:index/randomInteger:RandomInteger` | int-b",
        "created row not bold",
    );
    // `up --diff` prints two sections; only the last one counts.
    assert_eq!(resource_rows(&out), 4, "no double-count\n{out}");
    assert!(
        line_of(&out, "➖ **Deleted** | `") < line_of(&out, "➕ Created | `"),
        "destructive listed first\n{out}"
    );
    assert_has(
        &out,
        "<summary>📜 Full pulumi log</summary>",
        "collapsible log",
    );
}

// --- preview --diff, mixed, success -----------------------------------------

#[test]
fn preview_mixed_reads_future_tense_counts() {
    let out = run("gcp-org", "preview-mixed.txt", "0").stdout;
    assert_has(
        &out,
        "· pulumi preview · production · ✅ Succeeded",
        "title: preview",
    );
    assert_has(&out, "| 1 | 0 | 2 | 1 | 2 |", "future-tense counts");
    assert_has(&out, "⚠️ **1 deleted, 2 replaced**", "risk callout");
}

// --- up --diff, all creates -------------------------------------------------

#[test]
fn up_creates_is_not_destructive() {
    let out = run("gcp-org", "up-creates.txt", "0").stdout;
    assert_has(&out, "| 5 | 0 | 0 | 0 | 0 |", "counts 5/0/0/0/0");
    assert_has(&out, "✅ No replaces or deletes.", "no destructive");
    assert_has(
        &out,
        "➕ Created | `pulumi:pulumi:Stack` | pf-production",
        "stack resource by urn name",
    );
}

// --- preview, no-op ---------------------------------------------------------

#[test]
fn preview_noop_has_an_empty_resource_table() {
    let out = run("gcp-org", "preview-noop.txt", "0").stdout;
    assert_has(&out, "| 0 | 0 | 0 | 0 | 5 |", "counts 0/0/0/0/5");
    assert_has(&out, "_No resource-level changes._", "empty resource table");
    assert_has(&out, "✅ No replaces or deletes.", "no destructive");
}

// --- preview, in-place update -----------------------------------------------

#[test]
fn preview_update_lists_the_updated_row() {
    let out = run("gcp-org", "preview-update.txt", "0").stdout;
    assert_has(&out, "| 0 | 1 | 0 | 0 | 5 |", "counts 0/1/0/0/5");
    assert_has(
        &out,
        "🔄 Updated | `command:local:Command` | cmd-a",
        "updated row",
    );
}

// --- up --diff, deploy failure ----------------------------------------------

#[test]
fn up_fail_surfaces_the_error_without_color_directives() {
    let out = run("gcp-bootstrap", "up-fail.txt", "1").stdout;
    assert_has(&out, "❌ Failed", "title: failed");
    assert_has(
        &out,
        "**pulumi up failed** (exit 1) · 💥 1 errored",
        "failure line + errored count",
    );
    assert_has(&out, "error: update failed", "error surfaced");
    assert_lacks(&out, "<{%", "no leaked color directive");
}

// --- preview, program/type-check failure ------------------------------------

#[test]
fn preview_fail_surfaces_the_error_without_ansi() {
    let out = run("gcp-org", "preview-fail.txt", "1").stdout;
    assert_has(
        &out,
        "· pulumi preview · production · ❌ Failed",
        "title: preview failed",
    );
    assert_has(
        &out,
        "Error: random:index/randomPet:RandomPet is not assignable",
        "Error surfaced",
    );
    assert_lacks(&out, "\x1b[", "no leaked ANSI");
}

// --- row cap ----------------------------------------------------------------

#[test]
fn the_row_cap_drops_low_risk_rows_and_says_how_many() {
    let out = run_file(
        "gcp-org",
        &data("up-creates.txt"),
        "0",
        &[("PULUMI_SUMMARY_ROW_MAX", "2")],
    )
    .stdout;
    assert_eq!(resource_rows(&out), 2, "table capped to 2 rows\n{out}");
    assert_has(&out, "… and 3 more", "truncation note");
}

#[test]
fn destructive_rows_survive_the_row_cap() {
    let out = run_file(
        "gcp-org",
        &data("up-mixed.txt"),
        "0",
        &[("PULUMI_SUMMARY_ROW_MAX", "1")],
    )
    .stdout;
    assert_has(
        &out,
        "➖ **Deleted** | `random:index/randomString:RandomString` | **str-a**",
        "destructive survives the cap",
    );
    assert_eq!(resource_rows(&out), 1);
    assert_has(&out, "… and 3 more", "cap note present");
}

// --- size clamp -------------------------------------------------------------

#[test]
fn a_400_resource_apply_stays_under_the_comment_limit() {
    let mut log = String::from("Updating (production):\n  pulumi:pulumi:Stack: (same)\n");
    for i in 0..400 {
        log.push_str(&format!(
            "    + gcp:organizations/veryLongResourceTypeName:VeryLongResourceType{i:03}: (create)\n"
        ));
        log.push_str(&format!(
            "        [urn=urn:pulumi:production::proj::gcp:organizations/veryLongResourceTypeName:VeryLongResourceType{i:03}::a-really-quite-long-resource-name-number-{i:03}-with-lots-of-padding]\n"
        ));
    }
    log.push_str("Resources:\n    + 401 created\n");
    let t = TempDir::new();
    let big = t.join("big.txt");
    write(&big, &log);
    let out = run_file("gcp-networks", &big, "0", &[]).stdout;
    // The script measured `$(...)`, which drops the final newline.
    let bytes = out.trim_end_matches('\n').len();
    assert!(bytes <= 65536, "digest is {bytes} bytes (> 65536)");
    assert_has(&out, "… and 300 more", "row cap note present");
    assert_has(
        &out,
        " bytes (full log in the raw job output) …\n\n",
        "log truncated, from the end",
    );
}

#[test]
fn the_log_budget_is_what_the_head_leaves_under_the_limit() {
    // The head of the up-mixed digest, without its trailing newlines, is what
    // the script measured; the log gets limit - head - 200.
    let golden = read(data("up-mixed.digest.txt"));
    let head = golden.split("\n\n<details>").next().unwrap();
    let limit = head.len() + 200 + 100;
    let out = run_file(
        "gcp-org",
        &data("up-mixed.txt"),
        "0",
        &[("PULUMI_SUMMARY_COMMENT_LIMIT", &limit.to_string())],
    )
    .stdout;
    assert_has(
        &out,
        "… log truncated to last 100 bytes (full log in the raw job output) …\n\n",
        "budget",
    );
    let log = std::fs::read(data("up-mixed.txt")).unwrap();
    let tail = String::from_utf8_lossy(&log[log.len() - 100..]).into_owned();
    assert_has(
        &out,
        &format!("…\n\n{tail}\n```\n\n</details>\n"),
        "the LAST 100 bytes",
    );
    // No room at all: the log is omitted.
    let out = run_file(
        "gcp-org",
        &data("up-mixed.txt"),
        "0",
        &[("PULUMI_SUMMARY_COMMENT_LIMIT", "10")],
    )
    .stdout;
    assert_has(
        &out,
        "(log omitted — digest is at the comment size limit; see the raw job output)",
        "omitted",
    );
    // RAW_MAX caps it even when the limit would allow more.
    let out = run_file(
        "gcp-org",
        &data("up-mixed.txt"),
        "0",
        &[("PULUMI_SUMMARY_RAW_MAX", "50")],
    )
    .stdout;
    assert_has(&out, "… log truncated to last 50 bytes", "RAW_MAX");
}

// --- robustness: missing / empty output -------------------------------------

#[test]
fn an_empty_log_still_renders_a_digest() {
    let t = TempDir::new();
    let empty = t.join("empty.txt");
    write(&empty, "");
    let o = run_file("some-app", &empty, "0", &[]);
    assert_eq!(o.code, 0);
    assert_has(
        &o.stdout,
        "(no pulumi output captured)",
        "renders with no pulumi output",
    );
    assert_has(
        &o.stdout,
        "## 🏗️ some-app · pulumi · ✅ Succeeded\n",
        "still shows a title",
    );
}

#[test]
fn a_missing_log_is_the_same_as_an_empty_one() {
    let t = TempDir::new();
    let o = run_file("some-app", &t.join("nope.txt"), "1", &[]);
    assert_eq!(o.code, 0);
    assert_has(
        &o.stdout,
        "_No `error:` line was captured — see the full log below._",
        "no error line",
    );
    assert_has(&o.stdout, "(no pulumi output captured)", "no output");
}

#[test]
fn missing_or_empty_arguments_are_a_usage_error() {
    let t = TempDir::new();
    let f = t.join("f.txt");
    write(&f, "x\n");
    let fs = f.to_str().unwrap();
    for args in [
        vec![],
        vec!["l", fs],
        vec!["", fs, "0"],
        vec!["l", "", "0"],
        vec!["l", fs, ""],
    ] {
        let o = Run::new(&bin("BIN")).args(&args).go();
        assert_eq!(o.code, 2, "{args:?}: {o:?}");
        assert_has(&o.stderr, "usage: pulumi-summary", "usage");
        assert_eq!(o.stdout, "", "{args:?}");
    }
}

#[test]
fn only_plain_digits_are_an_exit_code() {
    for (code, title, shown) in [
        ("0", "✅ Succeeded", None),
        ("000", "✅ Succeeded", None),
        ("007", "❌ Failed", Some("(exit 007)")),
        ("-1", "❌ Failed", Some("(exit 1)")),
        ("+0", "❌ Failed", Some("(exit 1)")),
        ("abc", "❌ Failed", Some("(exit 1)")),
    ] {
        let out = run("gcp-org", "up-creates.txt", code).stdout;
        assert_has(&out, title, code);
        if let Some(s) = shown {
            assert_has(&out, s, code);
        }
    }
}

// --- GITHUB_OUTPUT counts: the deploy gates key off these -------------------

#[test]
fn a_destructive_plan_emits_every_count_key() {
    let got = outputs(
        "Previewing update (production):\n    -   gcp:projects/iAMMember:IAMMember some-binding delete\nResources:\n    - 1 to delete\n    46 unchanged\n",
        "0",
    );
    // Every output .github/actions/pulumi-summary/action.yml declares.
    assert_eq!(
        got,
        "created=0\nupdated=0\nreplaced=0\ndeleted=1\nunchanged=46\nerrored=0\ndestructive=1\n"
    );
}

#[test]
fn a_clean_plan_emits_zero_destructive() {
    let got = outputs(
        "Previewing update (production):\nResources:\n    47 unchanged\n",
        "0",
    );
    assert_eq!(
        got,
        "created=0\nupdated=0\nreplaced=0\ndeleted=0\nunchanged=47\nerrored=0\ndestructive=0\n"
    );
}

#[test]
fn destructive_is_deleted_plus_replaced() {
    let got = outputs("Updating (p):\nResources:\n    +-3 replaced\n    - 2 deleted\n    + 1 created\n    ~ 4 updated\n", "0");
    assert_eq!(
        got,
        "created=1\nupdated=4\nreplaced=3\ndeleted=2\nunchanged=0\nerrored=0\ndestructive=5\n"
    );
}

#[test]
fn outputs_are_appended_not_overwritten() {
    let t = TempDir::new();
    let gho = t.join("gho");
    write(&gho, "earlier=1\n");
    let o = run_file(
        "l",
        &data("up-mixed.txt"),
        "0",
        &[("GITHUB_OUTPUT", gho.to_str().unwrap())],
    );
    assert_eq!(o.code, 0);
    assert_eq!(
        read(&gho),
        "earlier=1\ncreated=1\nupdated=0\nreplaced=2\ndeleted=1\nunchanged=2\nerrored=0\ndestructive=3\n"
    );
}

#[test]
fn no_github_output_is_fine() {
    let o = run_file("gate-test", Path::new("/dev/null"), "0", &[]);
    assert_eq!(o.code, 0);
    assert_has(
        &o.stdout,
        "## 🏗️ gate-test",
        "works with no GITHUB_OUTPUT set",
    );
}

// --- parser details the script's sed/awk fixed -------------------------------

#[test]
fn only_the_last_section_counts() {
    let got = outputs(
        "Previewing update (s):\nResources:\n    - 9 to delete\n\nUpdating (s):\nResources:\n    + 1 created\n",
        "0",
    );
    assert_has(&got, "deleted=0\n", "the preview section is not counted");
    assert_has(&got, "created=1\n", "the update section is");
}

#[test]
fn a_count_needs_exactly_one_space_before_its_word() {
    // awk's /[0-9]+ (created|to create)/: `3  created` and `2 recreated` are
    // not counts; `4 created` is.
    let got = outputs(
        "Updating (s):\nResources:\n    + 3  created\n    + 2 recreated\n    4 created\n",
        "0",
    );
    assert_has(&got, "created=4\n", "leftmost single-space count");
}

#[test]
fn the_resources_block_ends_at_a_blank_or_duration_line() {
    let got = outputs(
        "Updating (s):\nResources:\n    + 1 created\n \t\n    - 5 deleted\n",
        "0",
    );
    assert_has(&got, "deleted=0\n", "after a blank line");
    let got = outputs(
        "Updating (s):\nResources:\n    + 1 created\nDuration: 3s\n    - 5 deleted\n",
        "0",
    );
    assert_has(&got, "deleted=0\n", "after Duration:");
}

#[test]
fn colour_directives_ansi_and_trailing_cr_are_stripped_like_sed() {
    let t = TempDir::new();
    let f = t.join("log.txt");
    write(
        &f,
        "Updating (st):\r\n\x1b[1;31mred\x1b[0m \x1b[?25lkept\r\r\n<{%fg 1%}>1 errored<{%reset%}>\r\nResources:\r\n    <{%fg 1%}>1 errored<{%reset%}>\r\n",
    );
    let out = run_file("l", &f, "1", &[]).stdout;
    assert_has(&out, "· 💥 1 errored", "errored read through the directive");
    // ESC[ digits/semicolons + letter goes; ESC[?25l is not that shape.
    assert_has(
        &out,
        "red \x1b[?25lkept\r\n",
        "only the last CR of a line goes",
    );
    assert_lacks(&out, "\x1b[1;31m", "SGR stripped");
    assert_lacks(&out, "<{%", "directives stripped");
}

#[test]
fn rows_take_the_type_after_markers_and_the_name_after_the_last_double_colon() {
    let t = TempDir::new();
    let f = t.join("log.txt");
    write(
        &f,
        "Updating (s):\n    + - aws:s3/bucket:Bucket: (create) \t\n        [urn=urn:pulumi:s::p::aws:s3/bucket:Bucket::my:name]\n  +-a|b:T: (replace)\n    [urn=urn:pulumi:s::p::a|b:T::x|y]\n",
    );
    let out = run_file("l", &f, "0", &[]).stdout;
    // blanks, markers, blanks once: ` + - ` leaves `- aws...`.
    assert_has(
        &out,
        "| ➕ Created | `- aws:s3/bucket:Bucket` | my:name |",
        "type and single-colon name",
    );
    assert_has(
        &out,
        "| ♻️ **Replaced** | `a\\|b:T` | **x\\|y** |",
        "pipes escaped",
    );
}

#[test]
fn error_lines_are_capped_at_twenty_and_cut_at_a_tab() {
    let t = TempDir::new();
    let f = t.join("log.txt");
    let mut log = String::from("error:\tbefore tab\n");
    for i in 0..25 {
        log.push_str(&format!("error: e{i}\n"));
    }
    write(&f, &log);
    let out = run_file("l", &f, "1", &[]).stdout;
    assert_has(&out, "```text\nerror:\nerror: e0\n", "tab ends the line");
    assert_has(&out, "error: e18\n```", "20 lines in all");
    assert_lacks(&out, "error: e19\n```", "the 21st is dropped");
}
