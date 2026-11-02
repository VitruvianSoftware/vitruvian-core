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

//! //tools/ci:go_test_with_retry — `go test ./...` over every IaC Go module that
//! actually carries tests, retrying a module ONLY on a recognizable transient
//! module-proxy/network signature.
//!
//! With no arguments it searches the IaC set (`infrastructure/pulumi` and
//! `apps/*/*/infra`; the go-test-infra job). `--root <dir>` (repeatable)
//! searches only the given trees instead: example-build passes
//! `--root packages/pulumi/examples`, whose tests had never run anywhere
//! (#4205). A named root that is missing, or holds no module with tests, is an
//! error: asking for a tree and testing nothing must not read as green.

use shell_compat::{cat, err, out, status_code, subst};
use std::io::Read;
use std::process::Command;

fn has_test_files(dir: &[u8]) -> bool {
    let r = shell_compat::capture(
        0,
        Command::new("find")
            .arg(shell_compat::os(dir))
            .arg("-name")
            .arg("*_test.go")
            .arg("-print")
            .arg("-quit"),
    );
    !subst(r.stdout).is_empty()
}

/// The names of the non-dot subdirectories of `dir` (a shell `dir/*/` glob:
/// dot-directories are skipped, as the glob skips them).
fn subdir_names(dir: &[u8]) -> Vec<Vec<u8>> {
    let mut found = Vec::new();
    if let Ok(entries) = std::fs::read_dir(shell_compat::path(dir)) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_bytes = std::os::unix::ffi::OsStrExt::as_bytes(name.as_os_str());
            if name_bytes.first() == Some(&b'.') {
                continue;
            }
            if shell_compat::is_dir(&cat(&[dir, b"/", name_bytes])) {
                found.push(name_bytes.to_vec());
            }
        }
    }
    found
}

/// The IaC roots go-test-infra tests (this tool with no arguments), relative
/// to `base`: `infrastructure/pulumi` and every `apps/*/*/infra` (the app
/// layout, `apps/<category>/<app>/infra`). The old `*/infra` glob predates
/// that layout and matched nothing once apps moved (#4178), so it is gone.
///
/// Public so //tools/ci:go_test_lanes judges coverage by the same roots this
/// tool searches, not a second hand-kept list.
pub fn iac_roots_in(base: &[u8]) -> Vec<Vec<u8>> {
    let under = |rel: &[u8]| -> Vec<u8> {
        if base == b"." {
            rel.to_vec()
        } else {
            cat(&[base, b"/", rel])
        }
    };
    let mut roots: Vec<Vec<u8>> = vec![b"infrastructure/pulumi".to_vec()];
    for category in subdir_names(&under(b"apps")) {
        let category_rel = cat(&[b"apps/", &category]);
        for app in subdir_names(&under(&category_rel)) {
            let infra = cat(&[&category_rel, b"/", &app, b"/infra"]);
            if shell_compat::is_dir(&under(&infra)) {
                roots.push(infra);
            }
        }
    }
    roots
}

fn iac_search_paths() -> Vec<Vec<u8>> {
    iac_roots_in(b".")
}

/// Every go.mod under `search_paths`, sorted, skipping vendored copies (and
/// node_modules, which an npm workspace such as ts-foundation may carry).
fn find_go_mods(search_paths: &[Vec<u8>]) -> Vec<Vec<u8>> {
    let mut cmd = Command::new("find");
    for p in search_paths {
        cmd.arg(shell_compat::os(p));
    }
    cmd.arg("-name")
        .arg("go.mod")
        .arg("-not")
        .arg("-path")
        .arg("*/vendor/*")
        .arg("-not")
        .arg("-path")
        .arg("*/node_modules/*");
    cmd.stderr(std::process::Stdio::null());

    let r = shell_compat::capture(0, &mut cmd);
    let raw = subst(r.stdout);
    if raw.is_empty() {
        return Vec::new();
    }
    let mut mods: Vec<Vec<u8>> = shell_compat::lines(&raw);
    mods.sort();
    mods
}

fn go_test_with_retry(dir: &[u8]) -> i32 {
    let dir_str = String::from_utf8_lossy(dir);
    let mut last_status: i32 = 0;

    for attempt in 1..=3 {
        let shell_cmd = format!(
            "cd '{}' && go test ./... 2>&1",
            dir_str.replace('\'', "'\\''")
        );
        let mut child = match Command::new("bash")
            .arg("-c")
            .arg(&shell_cmd)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                err(&cat(&[
                    b"go-test-with-retry: could not start bash: ",
                    e.to_string().as_bytes(),
                    b"\n",
                ]));
                return 1;
            }
        };

        let mut captured = Vec::new();
        if let Some(mut stdout) = child.stdout.take() {
            let mut buf = [0u8; 8192];
            loop {
                match stdout.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        out(&buf[..n]);
                        captured.extend_from_slice(&buf[..n]);
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(_) => break,
                }
            }
        }

        let status = match child.wait() {
            Ok(st) => status_code(st),
            Err(_) => 1,
        };

        if status == 0 {
            return 0;
        }
        last_status = status;

        if attempt < 3 && transient_lib::is_transient_network_error(&captured) {
            let delay = attempt * 10;
            err(&cat(&[
                b"::warning::go test in ",
                dir,
                b" hit a transient network error (attempt ",
                attempt.to_string().as_bytes(),
                b"/3) -- retrying in ",
                delay.to_string().as_bytes(),
                b"s\n",
            ]));
            // `sleep N`, the command, as the script ran it (a test stubs it).
            let slept = Command::new("sleep").arg(delay.to_string()).status();
            if slept.is_err() {
                std::thread::sleep(std::time::Duration::from_secs(delay as u64));
            }
            continue;
        }
        return last_status;
    }
    last_status
}

const USAGE: &[u8] = b"usage: go_test_with_retry [--root <dir>]...\n";

pub fn run(args: &[Vec<u8>]) -> i32 {
    let rc = shell_compat::enter_bazel_run_cwd("go_test_with_retry");
    if rc != 0 {
        return rc;
    }

    let mut roots: Vec<Vec<u8>> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_slice() {
            b"--root" if i + 1 < args.len() => {
                roots.push(args[i + 1].clone());
                i += 2;
            }
            b"-h" | b"--help" => {
                out(USAGE);
                return 0;
            }
            _ => {
                err(USAGE);
                return 2;
            }
        }
    }
    for r in &roots {
        if !shell_compat::is_dir(r) {
            err(&cat(&[
                b"::error::go_test_with_retry: --root ",
                r,
                b" is not a directory\n",
            ]));
            return 1;
        }
    }
    let explicit = !roots.is_empty();
    let search_paths = if explicit { roots } else { iac_search_paths() };
    let mods = find_go_mods(&search_paths);
    let mut ran: u32 = 0;

    for mod_path in &mods {
        let dir = shell_compat::dirname(mod_path);
        if !has_test_files(&dir) {
            continue;
        }
        ran += 1;
        out(&cat(&[b"::group::go test ", &dir, b"\n"]));
        let rc = go_test_with_retry(&dir);
        out(b"::endgroup::\n");
        if rc != 0 {
            return rc;
        }
    }

    if explicit && ran == 0 {
        err(b"::error::go_test_with_retry: no Go module with tests under the given --root -- refusing to report green on an empty run\n");
        return 1;
    }

    out(&cat(&[
        b"ran go test in ",
        ran.to_string().as_bytes(),
        if explicit {
            b" module(s)\n" as &[u8]
        } else {
            b" IaC module(s)\n"
        },
    ]));
    0
}
