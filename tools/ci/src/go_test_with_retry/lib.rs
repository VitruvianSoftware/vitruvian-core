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

//! go-test-with-retry.sh — `go test ./...` over every IaC Go module that
//! actually carries tests, retrying a module ONLY on a recognizable transient
//! module-proxy/network signature.

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

fn find_go_mods() -> Vec<Vec<u8>> {
    let mut search_paths: Vec<Vec<u8>> = vec![b"infrastructure/pulumi".to_vec()];
    if let Ok(entries) = std::fs::read_dir(".") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_bytes = std::os::unix::ffi::OsStrExt::as_bytes(name.as_os_str());
            let infra = cat(&[name_bytes, b"/infra"]);
            if shell_compat::is_dir(&infra) {
                search_paths.push(infra);
            }
        }
    }

    let mut cmd = Command::new("find");
    for p in &search_paths {
        cmd.arg(shell_compat::os(p));
    }
    cmd.arg("-name")
        .arg("go.mod")
        .arg("-not")
        .arg("-path")
        .arg("*/vendor/*");
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
            std::thread::sleep(std::time::Duration::from_secs(delay as u64));
            continue;
        }
        return last_status;
    }
    last_status
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let mods = find_go_mods();
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

    out(&cat(&[
        b"ran go test in ",
        ran.to_string().as_bytes(),
        b" IaC module(s)\n",
    ]));
    0
}
