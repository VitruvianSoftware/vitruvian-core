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

//! bootstrap.sh in Rust: give a never-published package its FIRST publish,
//! from the MIRROR checkout, then hand off to setup so trusted publishing
//! governs it from then on. See bootstrap.sh for the why.
//!
//! The hand-off. The script runs `exec bash "$setup"` with the first of
//! `$SETUP_SH`, `$(dirname "$0")/setup.sh` and
//! `$ROOT/tools/npm-trusted-publisher/setup.sh` that is a file. This port
//! honours `$SETUP_SH` the same way (exec'ing bash on it); otherwise it runs
//! the Rust setup in-process, which IS the setup.sh the other two candidates
//! name. So the script's "published, but setup.sh was not found" exit cannot
//! happen here. As with `exec`, the cloned mirror is not removed on hand-off
//! (bash runs no EXIT trap across exec).

use crate::manifest;
use crate::sh::{self, errln, outln};
use std::process::{Command, Stdio};

const P: &str = "npm-trusted-publisher-bootstrap";
const SCRIPT: &str = "\
# Usage:
#   bazel run //tools/npm-trusted-publisher:bootstrap
#   bazel run //tools/npm-trusted-publisher:bootstrap -- --dry-run
#   bazel run //tools/npm-trusted-publisher:bootstrap -- --no-login
#
#   MIRROR_REPO=VitruvianSoftware/vitruvian-orchestrator-opencode \\
#     bazel run //tools/npm-trusted-publisher:bootstrap
#
# The mirror is a workspace (ts/packages/*) or one package at its top.
# Env: NPM, MIRROR_REPO (default VitruvianSoftware/pulumi-library), MIRROR_DIR
#      (use an existing checkout instead of cloning), SETUP_SH
# Exit: 0 nothing to do or all published · 1 a publish failed · 2 precondition
";

/// `sed -n '/^# Usage:/,/^# Exit:/p' "$0"`.
pub fn usage() -> String {
    let mut out = String::new();
    let mut on = false;
    for line in SCRIPT.split_inclusive('\n') {
        if on {
            out.push_str(line);
            if line.starts_with("# Exit:") {
                on = false;
            }
        } else if line.starts_with("# Usage:") {
            out.push_str(line);
            on = true;
        }
    }
    out
}

enum End {
    Exit(i32),
    /// Exec bash on this file.
    ExecBash(String),
    /// Run the Rust setup in-process.
    Setup,
}

fn lossy(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

fn quiet_ok(npm: &str, args: &[&str]) -> bool {
    let mut c = Command::new(npm);
    c.args(args).stdin(Stdio::inherit());
    sh::run_quiet(&mut c) == 0
}

/// bootstrap.sh. Returns the exit code (or does not return, on an exec).
pub fn main(args: &[String]) -> i32 {
    // The mirror to delete on exit: the script's `trap ... EXIT`, which is
    // only installed AFTER a successful clone.
    let mut cleanup: Option<String> = None;
    let end = run(args, &mut cleanup);
    match end {
        End::Exit(code) => {
            if let Some(dir) = cleanup {
                let _ = std::fs::remove_dir_all(dir);
            }
            code
        }
        End::ExecBash(file) => {
            sh::flush();
            use std::os::unix::process::CommandExt;
            let e = Command::new("bash").arg(&file).exec();
            errln(&format!("{}: exec: bash: {}", P, sh::strerror(&e)));
            127
        }
        End::Setup => crate::setup::main(&[]),
    }
}

fn run(args: &[String], cleanup: &mut Option<String>) -> End {
    if sh::cd_workspace(P).is_err() {
        return End::Exit(1);
    }
    let npm = sh::env_or("NPM", "npm");
    let mirror_repo = sh::env_or("MIRROR_REPO", "VitruvianSoftware/pulumi-library");
    let otp_wait = sh::env_or("OTP_WAIT_SECONDS", "900");
    let otp_poll = sh::env_or("OTP_POLL_SECONDS", "5");
    let (mut dry_run, mut no_login) = (false, false);
    for a in args {
        match a.as_str() {
            "--dry-run" => dry_run = true,
            "--no-login" => no_login = true,
            "-h" | "--help" => {
                sh::out(usage().as_bytes());
                return End::Exit(0);
            }
            _ => {
                errln(&format!("{}: unknown argument {}", P, a));
                return End::Exit(2);
            }
        }
    }

    let mut mirror = std::env::var("MIRROR_DIR").unwrap_or_default();
    if mirror.is_empty() {
        mirror = match sh::mktemp_d() {
            Ok(d) => d,
            Err(rc) => return End::Exit(rc),
        };
        outln(&format!(
            "{}: cloning {} (the publish origin)...",
            P, mirror_repo
        ));
        let url = format!("https://github.com/{}.git", mirror_repo);
        let rc = sh::run_inherit(
            Command::new("git").args(["clone", "--depth", "1", "--quiet", &url, &mirror]),
        );
        if rc != 0 {
            // Exits before the trap is set, so the empty clone dir stays.
            errln(&format!("  could not clone {}", mirror_repo));
            return End::Exit(2);
        }
        *cleanup = Some(mirror.clone());
    }

    let lay = match layout(&mirror) {
        Ok(l) => l,
        Err(m) => {
            errln(&format!("{}: {}", P, m));
            return End::Exit(2);
        }
    };

    let mut missing: Vec<String> = Vec::new();
    for mf in &lay.manifests {
        let line = match manifest::load_dict(mf) {
            Ok(d) => manifest::name_private_line(&d),
            Err(e) => {
                errln(&e);
                Vec::new()
            }
        };
        let f = sh::read_fields(&line, 2);
        let name = lossy(&f[0]);
        if name.is_empty() || f[1] != b"false" {
            continue;
        }
        if quiet_ok(&npm, &["view", &name, "version"]) {
            continue;
        }
        missing.push(mf.clone());
    }
    // `missing="$missing $mf"` and then `for mf in $missing`: split again.
    let missing: Vec<String> = sh::words(&missing.join(" "));

    if missing.is_empty() {
        outln("npm-trusted-publisher-bootstrap: every publishable package is already on");
        outln("  the registry; nothing to bootstrap.");
        return End::Exit(0);
    }

    outln("npm-trusted-publisher-bootstrap: these packages have never been published:");
    let mut bad_any = false;
    for mf in &missing {
        // The script reads the file again here; a file that no longer parses
        // fails the `name=$(...)` assignment, which `set -e` turns into exit 1.
        let d = match manifest::load_dict(mf) {
            Ok(d) => d,
            Err(e) => {
                errln(&e);
                return End::Exit(1);
            }
        };
        let name = manifest::name_of(&d);
        let bad = match manifest::unresolvable_deps(&d) {
            Ok(b) => b,
            Err(e) => {
                errln(&e);
                return End::Exit(1);
            }
        };
        // `bad="$(...)"` keeps interior lines, drops trailing newlines.
        let bad = lossy(&sh::subst(bad.join("\n").into_bytes()));
        if !bad.is_empty() {
            outln(&format!(
                "  ✗ {} — dependencies a consumer cannot resolve:",
                name
            ));
            for l in bad.split('\n') {
                outln(&format!("      {}", l));
            }
            bad_any = true;
        } else {
            outln(&format!("  {}", name));
        }
    }
    if bad_any {
        errln("npm-trusted-publisher-bootstrap: refusing to publish. These specs are");
        errln("  pnpm-internal or path-based and would be unusable for every consumer.");
        errln("  Copybara rewrites them on export (_LIBRARY_CATALOG_VERSIONS in");
        errln("  tools/copybara/copy.bara.sky); if they survived, that rewrite regressed.");
        return End::Exit(2);
    }

    if dry_run {
        outln("  DRY_RUN: no build, no publish, no trust configuration.");
        return End::Exit(0);
    }

    // ensure_login
    if !quiet_ok(&npm, &["whoami"]) {
        if no_login {
            errln("npm-trusted-publisher-bootstrap: not logged in and --no-login given.");
            return End::Exit(2);
        }
        // `[ -r /dev/tty ] && : >/dev/tty`: access(2), then an open for writing.
        let tty_ok = sh::can_access("/dev/tty", sh::R_OK)
            && std::fs::OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open("/dev/tty")
                .is_ok();
        if !sh::env_set("NPM_TP_TTY_OK") && !tty_ok {
            errln("npm-trusted-publisher-bootstrap: not logged in, and there is no");
            errln("  terminal to authenticate on. Run this from an interactive shell.");
            return End::Exit(2);
        }
        outln("npm-trusted-publisher-bootstrap: not logged in; starting npm login.");
        if sh::run_inherit(Command::new(&npm).arg("login")) != 0 {
            errln("  npm login failed.");
            return End::Exit(2);
        }
        if !quiet_ok(&npm, &["whoami"]) {
            errln("  npm login reported success but no session exists.");
            return End::Exit(2);
        }
    }
    let (_, who) = sh::capture(
        Command::new(&npm).arg("whoami").stdin(Stdio::inherit()),
        false,
    );
    outln(&format!("{}: authenticated as {}", P, lossy(&who)));

    if let Some(build_dir) = &lay.build_dir {
        outln(&format!("{}: building {}...", P, build_dir));
        // `( cd "$build_dir" && npm install && npm run build )`
        let built = (|| {
            let mut c = Command::new(&npm);
            c.arg("install");
            if let Err(m) = sh::in_dir(&mut c, build_dir) {
                errln(&format!("{}: {}", P, m));
                return false;
            }
            if sh::run_inherit(&mut c) != 0 {
                return false;
            }
            let mut c = Command::new(&npm);
            c.args(["run", "build"]);
            if sh::in_dir(&mut c, build_dir).is_err() {
                return false;
            }
            sh::run_inherit(&mut c) == 0
        })();
        if !built {
            errln("npm-trusted-publisher-bootstrap: the build failed; not publishing.");
            return End::Exit(2);
        }
    } else {
        outln(&format!(
            "{}: the package has no build script; publishing it as it is.",
            P
        ));
    }

    let (mut published, mut failed) = (0u64, 0u64);
    for mf in &missing {
        let dir = sh::dirname(mf);
        let name = match manifest::load_dict(mf) {
            Ok(d) => manifest::name_of(&d),
            Err(e) => {
                errln(&e);
                return End::Exit(1);
            }
        };
        if publish_with_otp_wait(&npm, &dir, &otp_wait, &otp_poll) {
            outln(&format!("  + published {}", name));
            published += 1;
        } else {
            errln(&format!("  ✗ {} failed to publish", name));
            failed += 1;
        }
    }

    outln(&format!(
        "{}: {} published, {} failed.",
        P, published, failed
    ));
    if failed != 0 {
        return End::Exit(1);
    }

    let setup = std::env::var("SETUP_SH").unwrap_or_default();
    outln("npm-trusted-publisher-bootstrap: attaching trusted publishers...");
    if !setup.is_empty() && std::path::Path::new(&setup).is_file() {
        End::ExecBash(setup)
    } else {
        End::Setup
    }
}

/// Where a mirror checkout keeps its packages, and what to build first.
#[derive(Debug, PartialEq)]
struct Layout {
    /// The package.json files to consider, in order.
    manifests: Vec<String>,
    /// The folder to `npm install && npm run build` in, if any.
    build_dir: Option<String>,
}

/// The two mirror layouts there are:
///   * a workspace, `ts/packages/*` built from `ts` (the Pulumi library);
///   * one package at the top (`package.json` at the root, as the
///     vitruvian-orchestrator-opencode mirror has it), built only if its
///     package.json has a `build` script.
fn layout(mirror: &str) -> Result<Layout, String> {
    let packages = format!("{}/ts/packages", mirror);
    if std::path::Path::new(&packages).is_dir() {
        // `for mf in $(find ... | sort)`: word-split, so a path with a blank in
        // it splits exactly as it does in the script.
        let found = sh::find_manifests(&[packages]).join("\n");
        return Ok(Layout {
            manifests: sh::words(&found),
            build_dir: Some(format!("{}/ts", mirror)),
        });
    }
    let root = format!("{}/package.json", mirror);
    if std::path::Path::new(&root).is_file() {
        let d = manifest::load_dict(&root)?;
        let has_build = matches!(
            d.get("scripts").and_then(|s| s.get("build")),
            Some(v) if v.truthy()
        );
        return Ok(Layout {
            manifests: vec![root],
            build_dir: has_build.then(|| mirror.to_string()),
        });
    }
    Err(format!(
        "{} has neither ts/packages/ nor a package.json at its top; the mirror layout moved.",
        mirror
    ))
}

/// The first publish runs on a person's machine, where npm cannot make a
/// provenance statement (it needs a CI identity). A package whose
/// `publishConfig` asks for provenance would fail with "Automatic provenance
/// generation not supported for provider: null", so this turns it off for
/// this one publish. Every later version comes from the mirror's CI, which
/// still attaches provenance.
const PUBLISH_ARGS: [&str; 4] = ["publish", "--access", "public", "--provenance=false"];

/// `publish_with_otp_wait`: retry the SAME publish through an EOTP until the
/// browser authentication lands or the budget runs out, never swallowing
/// npm's output (its URL is the only way forward).
fn publish_with_otp_wait(npm: &str, dir: &str, otp_wait: &str, otp_poll: &str) -> bool {
    let mut waited: i64 = 0;
    let mut shown = false;
    loop {
        let mut c = Command::new(npm);
        c.args(PUBLISH_ARGS)
            .stdin(Stdio::inherit());
        let (rc, out) = match sh::in_dir(&mut c, dir) {
            Ok(()) => sh::capture_merged(&mut c),
            Err(m) => (1, format!("{}: {}", P, m).into_bytes()),
        };
        if rc == 0 {
            sh::out(&out);
            sh::out(b"\n");
            return true;
        }
        if !sh::grep_fixed(&out, "EOTP") || !sh::test_lt(P, &waited.to_string(), otp_wait) {
            sh::err(&out);
            sh::err(b"\n");
            return false;
        }
        if !shown {
            shown = true;
            outln("");
            outln("npm-trusted-publisher-bootstrap: npm needs a one-time authentication");
            outln("  before it will accept a publish. Open the URL below, authenticate,");
            outln("  and CHOOSE \"skip for the next 5 minutes\" -- that covers every");
            outln("  package in this run.");
            sh::out(&out);
            sh::out(b"\n");
            outln(&format!(
                "  waiting for that authentication to complete (up to {}s)...",
                otp_wait
            ));
        }
        sh::sleep(otp_poll);
        waited += sh::parse_int(otp_poll).unwrap_or(0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn usage_is_the_scripts_block() {
        let u = usage();
        assert!(u.starts_with("# Usage:\n"));
        assert!(u.trim_end().ends_with("2 precondition"));
        assert!(u.contains("--dry-run"));
    }
    fn tmp(tag: &str) -> String {
        let d = std::env::temp_dir().join(format!("ntp-layout-{}-{}", tag, sh::unique()));
        std::fs::create_dir_all(&d).unwrap();
        d.to_string_lossy().into_owned()
    }

    #[test]
    fn layout_workspace() {
        let m = tmp("ws");
        std::fs::create_dir_all(format!("{}/ts/packages/a", m)).unwrap();
        std::fs::write(format!("{}/ts/packages/a/package.json", m), "{}").unwrap();
        let l = layout(&m).unwrap();
        assert_eq!(
            l.manifests,
            vec![format!("{}/ts/packages/a/package.json", m)]
        );
        assert_eq!(l.build_dir, Some(format!("{}/ts", m)));
    }

    #[test]
    fn layout_single_package_without_build() {
        let m = tmp("one");
        std::fs::write(
            format!("{}/package.json", m),
            r#"{"name":"x","scripts":{"test":"t"}}"#,
        )
        .unwrap();
        let l = layout(&m).unwrap();
        assert_eq!(l.manifests, vec![format!("{}/package.json", m)]);
        assert_eq!(l.build_dir, None);
    }

    #[test]
    fn layout_single_package_with_build() {
        let m = tmp("onebuild");
        std::fs::write(
            format!("{}/package.json", m),
            r#"{"name":"x","scripts":{"build":"tsc"}}"#,
        )
        .unwrap();
        assert_eq!(layout(&m).unwrap().build_dir, Some(m.clone()));
    }

    #[test]
    fn layout_unknown() {
        let m = tmp("none");
        assert!(layout(&m).unwrap_err().contains("layout moved"));
        std::fs::write(format!("{}/package.json", m), "[]").unwrap();
        assert!(layout(&m).is_err());
    }

    #[test]
    fn first_publish_turns_provenance_off() {
        assert_eq!(PUBLISH_ARGS[0], "publish");
        assert!(PUBLISH_ARGS.contains(&"--access"));
        assert!(PUBLISH_ARGS.contains(&"public"));
        assert!(PUBLISH_ARGS.contains(&"--provenance=false"));
    }
}
