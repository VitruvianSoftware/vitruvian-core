// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT
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

//! End-to-end behaviour of `:prepare` and `:inject-reference-fonts`, run as
//! `bazel run` runs them: started outside the checkout, finding it through
//! BUILD_WORKSPACE_DIRECTORY. The expectations are what the shell scripts
//! these binaries replaced (`.design-sync/{prepare,inject-reference-fonts}.sh`)
//! did on the same fixtures, recorded by a side-by-side run before deleting
//! them: exit codes, output, the tools called and the files written.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

static N: AtomicUsize = AtomicUsize::new(0);

fn bin(var: &str) -> PathBuf {
    let p = PathBuf::from(std::env::var(var).unwrap_or_else(|_| panic!("{var} unset")));
    fs::canonicalize(&p).unwrap_or(p)
}

fn fixture(name: &str) -> PathBuf {
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let d = base.join(format!(
        "ds-{name}-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = fs::remove_dir_all(&d);
    fs::create_dir_all(&d).unwrap();
    fs::canonicalize(&d).unwrap()
}

fn write(p: &Path, body: &str) {
    fs::create_dir_all(p.parent().unwrap()).unwrap();
    fs::write(p, body).unwrap();
}

fn stub(p: &Path, body: &str) {
    write(p, &format!("#!/bin/sh\n{body}\n"));
    fs::set_permissions(p, fs::Permissions::from_mode(0o755)).unwrap();
}

struct Out {
    rc: i32,
    stdout: String,
    stderr: String,
}

fn run(var: &str, root: &Path, env: &[(&str, &str)]) -> Out {
    let mut c = Command::new(bin(var));
    // Not the checkout, and not the runfiles tree: only the env var can lead
    // the binary to the fixture.
    c.current_dir(std::env::temp_dir())
        .env("BUILD_WORKSPACE_DIRECTORY", root)
        .env("CALLS", root.join(".calls"));
    for (k, v) in env {
        c.env(k, v);
    }
    let o = c.output().unwrap();
    Out {
        rc: o.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&o.stdout).replace(root.to_str().unwrap(), "ROOT"),
        stderr: String::from_utf8_lossy(&o.stderr).replace(root.to_str().unwrap(), "ROOT"),
    }
}

fn calls(root: &Path) -> String {
    fs::read_to_string(root.join(".calls"))
        .unwrap_or_default()
        .replace(root.to_str().unwrap(), "ROOT")
}

// ---------------------------------------------------------------- prepare

fn prepare_fixture(name: &str) -> PathBuf {
    let r = fixture(name);
    write(&r.join("packages/design-system/tsconfig.json"), "{}");
    write(
        &r.join(".design-sync/tailwind-entry.css"),
        "@import \"tailwindcss\";",
    );
    stub(
        &r.join("node_modules/.bin/tsc"),
        r#"echo "tsc cwd=${PWD##*/} args=$*" | tee -a "$CALLS"; exit ${TSC_RC:-0}"#,
    );
    stub(
        &r.join(".ds-sync/node_modules/.bin/tailwindcss"),
        r#"echo "tw cwd=${PWD##*/} args=$*" >> "$CALLS"; echo "tw out"
o=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && o="$2"; shift; done
mkdir -p "$(dirname "$o")"
[ -n "${TW_NOWRITE:-}" ] || printf "%s" "${TW_CSS:-:root{--color-surface:#111}}" > "$o"
exit ${TW_RC:-0}"#,
    );
    r
}

#[test]
fn prepare_builds_dist_then_stylesheet_from_the_package() {
    let r = prepare_fixture("ok");
    let o = run("PREPARE_BIN", &r, &[]);
    assert_eq!(o.rc, 0, "{}", o.stderr);
    assert_eq!(
        o.stdout,
        "tsc cwd=design-system args=-p tsconfig.json\ntw out\nprepare: dist/ + dist/vitruvian.built.css ready\n"
    );
    assert_eq!(o.stderr, "");
    assert_eq!(
        calls(&r),
        "tsc cwd=design-system args=-p tsconfig.json\n\
         tw cwd=design-system args=-i ROOT/.design-sync/tailwind-entry.css -o ROOT/packages/design-system/dist/vitruvian.built.css\n"
    );
    assert!(r
        .join("packages/design-system/dist/vitruvian.built.css")
        .is_file());
}

#[test]
fn prepare_fails_on_a_stock_tailwind_palette() {
    for css in [":root{--color-blue-500:#00f}", "x --color-slate-50: y"] {
        let r = prepare_fixture("leak");
        let o = run("PREPARE_BIN", &r, &[("TW_CSS", css)]);
        assert_eq!(o.rc, 1);
        assert_eq!(
            o.stderr,
            "prepare: stock Tailwind colours leaked into vitruvian.built.css\n"
        );
        assert!(!o.stdout.contains("ready"));
    }
    let r = prepare_fixture("noleak");
    let o = run(
        "PREPARE_BIN",
        &r,
        &[(
            "TW_CSS",
            "--color-blue-sky:1;--color-red-x:2;--color-reds-1:3",
        )],
    );
    assert_eq!(o.rc, 0, "{}", o.stderr);
}

#[test]
fn prepare_stops_with_the_failing_tools_status() {
    let r = prepare_fixture("tscfail");
    let o = run("PREPARE_BIN", &r, &[("TSC_RC", "7")]);
    assert_eq!(o.rc, 7);
    assert!(!calls(&r).contains("tw "), "tailwind ran after tsc failed");

    let r = prepare_fixture("twfail");
    let o = run("PREPARE_BIN", &r, &[("TW_RC", "3")]);
    assert_eq!(o.rc, 3);
    assert!(!o.stdout.contains("ready"));

    let r = prepare_fixture("tscmissing");
    fs::remove_file(r.join("node_modules/.bin/tsc")).unwrap();
    let o = run("PREPARE_BIN", &r, &[]);
    assert_eq!(o.rc, 127);
    assert_eq!(
        o.stderr,
        "ROOT/node_modules/.bin/tsc: No such file or directory\n"
    );

    let r = prepare_fixture("nopkg");
    fs::remove_dir_all(r.join("packages/design-system")).unwrap();
    let o = run("PREPARE_BIN", &r, &[]);
    assert_eq!(o.rc, 1);
    assert_eq!(
        o.stderr,
        "cd: ROOT/packages/design-system: No such file or directory\n"
    );
    assert_eq!(calls(&r), "");
}

#[test]
fn prepare_treats_an_unwritten_stylesheet_as_the_script_did() {
    // `if grep -qE ... missing-file` is false, not fatal: grep complains and
    // the script still said ready.
    let r = prepare_fixture("nowrite");
    let o = run("PREPARE_BIN", &r, &[("TW_NOWRITE", "1")]);
    assert_eq!(o.rc, 0);
    assert_eq!(
        o.stderr,
        "grep: ROOT/packages/design-system/dist/vitruvian.built.css: No such file or directory\n"
    );
    assert!(o.stdout.ends_with("ready\n"));
}

// ----------------------------------------------------- inject-reference-fonts

const IFRAME: &str = "<!doctype html><html><head><title>x</title></head><head></head></html>\n";
const LINKED: &str = "<!doctype html><html><head><link rel=\"stylesheet\" href=\"./ds-fonts/fonts.css\"><title>x</title></head><head></head></html>\n";

fn inject_fixture(name: &str) -> PathBuf {
    let r = fixture(name);
    write(&r.join(".design-sync/fonts/a.woff2"), "A");
    write(&r.join(".design-sync/fonts/b.woff2"), "B");
    write(
        &r.join(".design-sync/fonts.css"),
        "@font-face{src:url('./fonts/a.woff2')}\n@font-face{src:url('./fonts/b.woff2') format('woff2')}\n",
    );
    write(&r.join(".design-sync/sb-reference/iframe.html"), IFRAME);
    r
}

fn ds(r: &Path, rel: &str) -> PathBuf {
    r.join(".design-sync/sb-reference").join(rel)
}

#[test]
fn inject_copies_faces_rewrites_urls_and_links_once() {
    let r = inject_fixture("ok");
    let o = run("INJECT_BIN", &r, &[]);
    assert_eq!(
        (o.rc, o.stdout.as_str(), o.stderr.as_str()),
        (0, "injected into iframe.html\n", "")
    );
    assert_eq!(fs::read_to_string(ds(&r, "ds-fonts/a.woff2")).unwrap(), "A");
    assert_eq!(fs::read_to_string(ds(&r, "ds-fonts/b.woff2")).unwrap(), "B");
    assert_eq!(
        fs::read_to_string(ds(&r, "ds-fonts/fonts.css")).unwrap(),
        "@font-face{src:url('./a.woff2')}\n@font-face{src:url('./b.woff2') format('woff2')}\n"
    );
    assert_eq!(fs::read_to_string(ds(&r, "iframe.html")).unwrap(), LINKED);

    // Idempotent: the second run finds the link and leaves the page alone.
    let o = run("INJECT_BIN", &r, &[]);
    assert_eq!((o.rc, o.stdout.as_str()), (0, "already injected\n"));
    assert_eq!(fs::read_to_string(ds(&r, "iframe.html")).unwrap(), LINKED);
}

#[test]
fn inject_refuses_without_a_reference_build() {
    let r = inject_fixture("noiframe");
    fs::remove_file(ds(&r, "iframe.html")).unwrap();
    let o = run("INJECT_BIN", &r, &[]);
    assert_eq!(o.rc, 1);
    assert_eq!(o.stderr, "no sb-reference/iframe.html — build it first\n");
    assert!(!ds(&r, "ds-fonts").exists());
}

#[test]
fn inject_fails_on_a_face_the_stylesheet_names_but_nobody_ships() {
    let r = inject_fixture("missing");
    let css = r.join(".design-sync/fonts.css");
    let mut body = fs::read_to_string(&css).unwrap();
    body.push_str("x{src:url('./fonts/zz.woff2')}\nx{src:url('plain.woff2')}\n");
    fs::write(&css, body).unwrap();
    let o = run("INJECT_BIN", &r, &[]);
    assert_eq!(o.rc, 1);
    assert_eq!(
        o.stderr,
        "missing font face: ds-fonts/zz.woff2\nmissing font face: ds-fonts/url('plain.woff2\n"
    );
    assert_eq!(fs::read_to_string(ds(&r, "iframe.html")).unwrap(), IFRAME);
}

#[test]
fn inject_follows_the_scripts_glob_and_regex_rules() {
    // Dot-files are not in `*.woff2`; sed's `.` matches any character.
    let r = inject_fixture("glob");
    write(&r.join(".design-sync/fonts/.hidden.woff2"), "H");
    let css = r.join(".design-sync/fonts.css");
    let mut body = fs::read_to_string(&css).unwrap();
    body.push_str("x{src:url('Q/fonts/a.woff2'),url('./fonts/b.woff2')}\n");
    fs::write(&css, body).unwrap();
    let o = run("INJECT_BIN", &r, &[]);
    assert_eq!(o.rc, 0, "{}", o.stderr);
    assert!(!ds(&r, "ds-fonts/.hidden.woff2").exists());
    assert!(fs::read_to_string(ds(&r, "ds-fonts/fonts.css"))
        .unwrap()
        .ends_with("x{src:url('./a.woff2'),url('./b.woff2')}\n"));
}

#[test]
fn inject_reports_cp_and_head_failures_like_the_script() {
    let r = inject_fixture("nowoff2");
    fs::remove_file(r.join(".design-sync/fonts/a.woff2")).unwrap();
    fs::remove_file(r.join(".design-sync/fonts/b.woff2")).unwrap();
    let o = run("INJECT_BIN", &r, &[]);
    assert_ne!(o.rc, 0);
    assert!(
        o.stderr.contains("ROOT/.design-sync/fonts/*.woff2"),
        "{}",
        o.stderr
    );

    let r = inject_fixture("nohead");
    write(&ds(&r, "iframe.html"), "<html><body></body></html>\n");
    let o = run("INJECT_BIN", &r, &[]);
    assert_eq!((o.rc, o.stdout.as_str(), o.stderr.as_str()), (1, "", ""));

    let r = inject_fixture("nocss");
    fs::remove_file(r.join(".design-sync/fonts.css")).unwrap();
    let o = run("INJECT_BIN", &r, &[]);
    assert_eq!(o.rc, 1);
    assert_eq!(
        o.stderr,
        "sed: ROOT/.design-sync/fonts.css: No such file or directory\n"
    );
    assert_eq!(
        fs::read_to_string(ds(&r, "ds-fonts/fonts.css")).unwrap(),
        ""
    );
}
