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

//! //tools/ci:go_test_with_retry_test. Runs the REAL binary over a scratch
//! tree of Go modules with a fake `go` and a fake `sleep` first on PATH. The
//! former go-test-with-retry_test.sh covered only the transient-error
//! classifier, whose cases live on in //tools/ci:transient_lib_test; this
//! suite covers what it never did: which modules run, that only a transport
//! failure is retried (10s then 20s), and the exit status of the module that
//! failed.

use ci_testkit::{bin, read, write, write_exe, Output, Run, TempDir};
use std::path::Path;

/// A fake `go`: logs `<module dir>` per call, then follows the script in
/// `$FAKE_GO_PLAN/<module basename>`: one line per attempt, `<rc> <message>`;
/// the last line repeats. No plan file means pass.
const FAKE_GO: &str = r#"#!/usr/bin/env bash
printf '%s\n' "$PWD" >> "$FAKE_LOG/go"
plan="$FAKE_GO_PLAN/$(basename "$PWD")"
[ -f "$plan" ] || { echo "ok  $(basename "$PWD")"; exit 0; }
n=$(grep -c . "$FAKE_LOG/go")
mine=$(grep -c "/$(basename "$PWD")\$" "$FAKE_LOG/go")
line=$(sed -n "${mine}p" "$plan"); [ -n "$line" ] || line=$(tail -n 1 "$plan")
rc=${line%% *}; msg=${line#* }
echo "$msg" >&2
exit "$rc"
"#;

struct Tree {
    dir: TempDir,
}

impl Tree {
    fn new() -> Tree {
        let dir = TempDir::new();
        write_exe(dir.join("fakes/go"), FAKE_GO);
        write_exe(
            dir.join("fakes/sleep"),
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$1\" >> \"$FAKE_LOG/sleep\"\n",
        );
        std::fs::create_dir_all(dir.join("log")).unwrap();
        std::fs::create_dir_all(dir.join("plan")).unwrap();
        Tree { dir }
    }
    fn root(&self) -> std::path::PathBuf {
        self.dir.join("root")
    }
    /// A module at `rel` (under the root), with or without a _test.go.
    fn module(&self, rel: &str, with_tests: bool) {
        write(self.root().join(rel).join("go.mod"), "module x\n");
        if with_tests {
            write(self.root().join(rel).join("x_test.go"), "package x\n");
        }
    }
    fn plan(&self, module: &str, lines: &str) {
        write(self.dir.join("plan").join(module), lines);
    }
    fn run(&self) -> Output {
        std::fs::create_dir_all(self.root()).unwrap();
        Run::new(&bin("BIN"))
            .cwd(self.root())
            .path_first(&self.dir.join("fakes"))
            .env("FAKE_LOG", self.dir.join("log"))
            .env("FAKE_GO_PLAN", self.dir.join("plan"))
            .go_within(std::time::Duration::from_secs(60))
            .expect("go-test-with-retry hung")
    }
    fn go_calls(&self) -> Vec<String> {
        let root = std::fs::canonicalize(self.root()).unwrap();
        read(self.dir.join("log/go"))
            .lines()
            .map(|l| {
                Path::new(l)
                    .strip_prefix(&root)
                    .unwrap_or(Path::new(l))
                    .display()
                    .to_string()
            })
            .collect()
    }
    fn sleeps(&self) -> String {
        read(self.dir.join("log/sleep"))
    }
}

const TRANSIENT: &str = "http2: stream error: stream ID 5; INTERNAL_ERROR";

#[test]
fn runs_only_modules_with_tests_in_sorted_order() {
    let t = Tree::new();
    t.module("infrastructure/pulumi/b", true);
    t.module("infrastructure/pulumi/a", true);
    t.module("infrastructure/pulumi/no-tests", false);
    t.module("infrastructure/pulumi/a/vendor/dep", true);
    t.module("app/infra", true);
    t.module(".hidden/infra", true);
    let o = t.run();
    assert_eq!(o.code, 0, "{}", o.all());
    assert_eq!(
        t.go_calls(),
        vec![
            "app/infra",
            "infrastructure/pulumi/a",
            "infrastructure/pulumi/b"
        ],
        "*/infra and infrastructure/pulumi, sorted; no vendor, no test-less module, no dot-dir"
    );
    assert!(o
        .stdout
        .contains("::group::go test infrastructure/pulumi/a\n"));
    assert!(
        o.stdout.ends_with("ran go test in 3 IaC module(s)\n"),
        "{}",
        o.stdout
    );
    assert_eq!(t.sleeps(), "");
}

#[test]
fn no_modules_is_a_pass() {
    let t = Tree::new();
    let o = t.run();
    assert_eq!(o.code, 0);
    assert_eq!(o.stdout, "ran go test in 0 IaC module(s)\n");
}

#[test]
fn a_real_failure_is_not_retried_and_keeps_gos_status() {
    let t = Tree::new();
    t.module("infrastructure/pulumi/a", true);
    t.plan("a", "3 --- FAIL: TestFoo (0.00s)\n");
    let o = t.run();
    assert_eq!(o.code, 3, "{}", o.all());
    assert_eq!(t.go_calls().len(), 1, "a deterministic failure runs once");
    assert_eq!(t.sleeps(), "");
    assert!(!o.stderr.contains("::warning::"));
}

#[test]
fn go_output_reaches_stdout_both_streams() {
    let t = Tree::new();
    t.module("infrastructure/pulumi/a", true);
    t.plan("a", "1 boom on stderr\n");
    let o = t.run();
    assert!(
        o.stdout.contains("boom on stderr"),
        "2>&1 | tee: {}",
        o.stdout
    );
}

#[test]
fn a_transient_failure_is_retried_after_10s() {
    let t = Tree::new();
    t.module("infrastructure/pulumi/a", true);
    t.plan("a", &format!("1 {TRANSIENT}\n0 ok\n"));
    let o = t.run();
    assert_eq!(o.code, 0, "{}", o.all());
    assert_eq!(t.go_calls().len(), 2);
    assert_eq!(t.sleeps(), "10\n");
    assert!(
        o.stderr.contains(
            "::warning::go test in infrastructure/pulumi/a hit a transient network error (attempt 1/3) -- retrying in 10s"
        ),
        "{}",
        o.stderr
    );
}

#[test]
fn three_transient_failures_give_up_with_the_last_status() {
    let t = Tree::new();
    t.module("infrastructure/pulumi/a", true);
    t.plan(
        "a",
        &format!("1 {TRANSIENT}\n1 {TRANSIENT}\n7 {TRANSIENT}\n"),
    );
    let o = t.run();
    assert_eq!(o.code, 7, "{}", o.all());
    assert_eq!(t.go_calls().len(), 3, "three attempts, no more");
    assert_eq!(t.sleeps(), "10\n20\n");
}

#[test]
fn a_transient_then_real_failure_stops_there() {
    let t = Tree::new();
    t.module("infrastructure/pulumi/a", true);
    t.plan(
        "a",
        &format!("1 {TRANSIENT}\n4 ./foo.go:10:2: undefined: bar\n"),
    );
    let o = t.run();
    assert_eq!(o.code, 4);
    assert_eq!(t.go_calls().len(), 2);
    assert_eq!(t.sleeps(), "10\n");
}

#[test]
fn the_first_failing_module_ends_the_run() {
    // set -e in the script: the failing module's status, and no later module.
    let t = Tree::new();
    t.module("infrastructure/pulumi/a", true);
    t.module("infrastructure/pulumi/b", true);
    t.plan("a", "2 FAIL\n");
    let o = t.run();
    assert_eq!(o.code, 2);
    assert_eq!(t.go_calls(), vec!["infrastructure/pulumi/a"]);
    assert!(!o.stdout.contains("ran go test in"));
}
