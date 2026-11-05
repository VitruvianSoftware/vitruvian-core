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

//! //tools/pulumi:pulumi-go-test, the runner behind every pulumi_go_test()
//! target. Cases 1-3 are ported 1:1 from the former pulumi_go_test_test.sh;
//! case 4 is new (what it actually runs, with a stub `go`).

mod common;
use common::*;

// 1. No arguments -> usage error.
#[test]
fn t1_no_args_is_an_error() {
    let o = run(cmd(&bin("PULUMI_GO_TEST_BIN"), "/usr/bin:/bin"));
    assert_ne!(code(&o), 0);
}

// 2. A directory that does not exist -> error.
#[test]
fn t2_missing_dir_is_an_error() {
    let d = tempdir("go-test");
    let mut c = cmd(&bin("PULUMI_GO_TEST_BIN"), "/usr/bin:/bin");
    c.arg(d.join("nope"));
    assert_ne!(code(&run(c)), 0);
}

// 3. No go toolchain on PATH -> error that names go.
#[test]
fn t3_missing_go_is_an_error() {
    let d = tempdir("go-test");
    let empty = d.join("empty-path");
    std::fs::create_dir_all(&empty).unwrap();
    std::fs::create_dir_all(d.join("project")).unwrap();
    let mut c = cmd(&bin("PULUMI_GO_TEST_BIN"), empty.to_str().unwrap());
    c.arg(d.join("project"));
    let o = run(c);
    assert_ne!(code(&o), 0);
    assert!(stderr(&o).to_lowercase().contains("go"), "{}", stderr(&o));
}

// 4. New: execs `go test ./...` in the project dir with GOWORK=off, and its
// exit code is the target's.
#[test]
fn t4_execs_go_test_in_project_with_gowork_off() {
    let d = tempdir("go-test");
    let stubs = d.join("stubs");
    write_exec(
        &stubs.join("go"),
        "#!/usr/bin/env bash\necho \"pwd=$PWD gowork=$GOWORK args=$*\" >\"$GO_LOG\"\nexit 7\n",
    );
    let project = d.join("project");
    std::fs::create_dir_all(&project).unwrap();
    let log = d.join("go.log");
    let mut c = cmd(
        &bin("PULUMI_GO_TEST_BIN"),
        &format!("{}:/usr/bin:/bin", stubs.display()),
    );
    c.env("GO_LOG", &log).arg(&project);
    let o = run(c);
    assert_eq!(code(&o), 7);
    let project = std::fs::canonicalize(&project).unwrap();
    let got = read(&log);
    assert!(
        got.contains(&format!("pwd={} ", project.display()))
            || got.contains(&format!("pwd={}/ ", project.display())),
        "{got}"
    );
    assert!(got.contains("gowork=off args=test ./..."), "{got}");
}

// 5. VITRUVIAN_GO_BIN (resolved relative to initial cwd before chdir) works
// even when no `go` is on PATH, setting GOROOT to the SDK root two levels up
// and GOTOOLCHAIN=local.
#[test]
fn t5_vitruvian_go_bin_runs_without_go_on_path() {
    let d = tempdir("go-test");
    let empty_path = d.join("empty-path");
    std::fs::create_dir_all(&empty_path).unwrap();
    let sdk_bin = d.join("sdk/bin");
    std::fs::create_dir_all(&sdk_bin).unwrap();
    write_exec(
        &sdk_bin.join("go"),
        "#!/bin/sh\necho \"pwd=$PWD goroot=$GOROOT gotoolchain=$GOTOOLCHAIN gowork=$GOWORK args=$*\" >\"$GO_LOG\"\nexit 0\n",
    );
    let project = d.join("project");
    std::fs::create_dir_all(&project).unwrap();
    let log = d.join("go.log");
    let mut c = cmd(&bin("PULUMI_GO_TEST_BIN"), empty_path.to_str().unwrap());
    c.current_dir(&d)
        .env("VITRUVIAN_GO_BIN", "sdk/bin/go")
        .env("GO_LOG", &log)
        .arg("project");
    let o = run(c);
    assert_eq!(code(&o), 0, "stderr: {}", stderr(&o));
    let d_canon = std::fs::canonicalize(&d).unwrap();
    let got = read(&log);
    assert!(
        got.contains(&format!("goroot={}", d_canon.join("sdk").display())),
        "{got}"
    );
    assert!(
        got.contains("gotoolchain=local gowork=off args=test ./..."),
        "{got}"
    );
}
