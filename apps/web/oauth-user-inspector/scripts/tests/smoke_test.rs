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

//! `:smoke` end to end against stub `curl` and Chrome binaries. The expected
//! output is what `infra/app/smoke.sh` (the script this binary replaced, run
//! by //tools/deploy as `bash -c`) produced on the same stubs.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

static N: AtomicUsize = AtomicUsize::new(0);

const CHROMES: [&str; 3] = ["google-chrome-stable", "google-chrome", "chromium-browser"];
const NOT_MOUNTED: &str =
    "::error::App did NOT mount -- served only the static fallback (broken frontend bundle).\n";

fn stubs() -> PathBuf {
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let d = base.join(format!(
        "smoke-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = fs::remove_dir_all(&d);
    fs::create_dir_all(&d).unwrap();
    stub(
        &d.join("curl"),
        r#"echo "curl $*" >>"$CALLS"; exit ${CURL_RC:-0}"#,
    );
    for c in CHROMES {
        stub(
            &d.join(c),
            &format!(
                r#"echo "{c} $*" >>"$CALLS"; echo noise >&2; printf "%b" "${{DOM-<div>Select a provider</div>\n}}"; exit ${{CHROME_RC:-0}}"#
            ),
        );
    }
    d
}

fn stub(p: &Path, body: &str) {
    fs::write(p, format!("#!/bin/sh\n{body}\n")).unwrap();
    fs::set_permissions(p, fs::Permissions::from_mode(0o755)).unwrap();
}

fn smoke(bin: &Path, env: &[(&str, &str)]) -> (i32, Vec<u8>, String) {
    let calls = bin.join("calls");
    let mut c = Command::new(std::env::var("SMOKE_BIN").expect("SMOKE_BIN"));
    c.env_clear()
        .env("PATH", format!("{}:/usr/bin:/bin", bin.display()))
        .env("CALLS", &calls);
    for (k, v) in env {
        c.env(k, v);
    }
    let o = c.output().unwrap();
    (
        o.status.code().unwrap_or(-1),
        o.stdout,
        fs::read_to_string(calls).unwrap_or_default(),
    )
}

const URL: (&str, &str) = ("CAND", "https://cand.example");
const HEAD: &str = "Smoke-checking https://cand.example/\n";

#[test]
fn skips_without_a_candidate() {
    for env in [vec![], vec![("CAND", "")]] {
        let s = stubs();
        let (rc, out, calls) = smoke(&s, &env);
        assert_eq!(rc, 0);
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "Service is disabled or candidate URL is empty — skipping smoke check.\n"
        );
        assert_eq!(calls, "");
    }
}

#[test]
fn passes_when_the_app_mounts() {
    let s = stubs();
    let (rc, out, calls) = smoke(&s, &[URL]);
    assert_eq!(rc, 0);
    assert_eq!(
        String::from_utf8(out).unwrap(),
        format!("{HEAD}Smoke OK: React app mounted.\n")
    );
    assert_eq!(
        calls,
        "curl --fail --retry 10 --retry-delay 5 --retry-connrefused https://cand.example/\n\
         google-chrome-stable --headless=new --no-sandbox --disable-gpu --virtual-time-budget=10000 --dump-dom https://cand.example/\n"
    );
}

#[test]
fn curl_failing_does_not_decide_the_smoke() {
    // The script ran without errexit: the DOM check is the only gate.
    let s = stubs();
    let (rc, out, _) = smoke(&s, &[URL, ("CURL_RC", "22")]);
    assert_eq!(rc, 0);
    assert!(String::from_utf8(out)
        .unwrap()
        .ends_with("Smoke OK: React app mounted.\n"));
}

#[test]
fn fails_on_the_static_fallback_and_dumps_the_captured_dom() {
    let s = stubs();
    let (rc, out, _) = smoke(&s, &[URL, ("DOM", "<div id=\"root\"></div>\\n\\n\\n")]);
    assert_eq!(rc, 1);
    assert_eq!(
        out,
        format!("{HEAD}{NOT_MOUNTED}<div id=\"root\"></div>").into_bytes()
    );

    let long = "x".repeat(1000);
    let (rc, out, _) = smoke(&s, &[URL, ("DOM", &long)]);
    assert_eq!(rc, 1);
    assert_eq!(
        out,
        format!("{HEAD}{NOT_MOUNTED}{}", &long[..800]).into_bytes()
    );

    // A failing Chrome is judged by what it printed.
    let (rc, _, _) = smoke(&s, &[URL, ("CHROME_RC", "1")]);
    assert_eq!(rc, 0);
}

#[test]
fn finds_chrome_the_way_command_v_does() {
    let s = stubs();
    fs::remove_file(s.join("google-chrome-stable")).unwrap();
    fs::remove_file(s.join("google-chrome")).unwrap();
    let (rc, _, calls) = smoke(&s, &[URL]);
    assert_eq!(rc, 0);
    assert!(
        calls.contains("\nchromium-browser --headless=new"),
        "{calls}"
    );

    // A non-executable google-chrome-stable is still what `command -v` names
    // (no executable one exists), so the run fails rather than moving on.
    let s = stubs();
    fs::set_permissions(
        s.join("google-chrome-stable"),
        fs::Permissions::from_mode(0o644),
    )
    .unwrap();
    let (rc, out, _) = smoke(&s, &[URL]);
    assert_eq!(rc, 1);
    assert_eq!(out, format!("{HEAD}{NOT_MOUNTED}").into_bytes());

    let s = stubs();
    for c in CHROMES {
        fs::remove_file(s.join(c)).unwrap();
    }
    let (rc, out, _) = smoke(&s, &[URL]);
    assert_eq!(rc, 1);
    assert_eq!(
        String::from_utf8(out).unwrap(),
        format!("{HEAD}::error::no headless Chrome available -- cannot verify the app mounts\n")
    );
}
