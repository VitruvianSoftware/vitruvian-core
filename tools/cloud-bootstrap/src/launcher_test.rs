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

//! Tests for tools/cloud-bootstrap/cloud-bootstrap.sh, the launcher that
//! .claude/session-start.sh and the cloud environment's Setup script run before
//! Bazel exists. It runs against a copy of the tool's tree, on a PATH holding
//! only the coreutils it needs plus a fake `rustc` (which records each build
//! and drops in the Bazel-built binary) or a fake `bazel`. Pinned: one build,
//! then reuse; a changed source rebuilds and prunes the old build; arguments
//! and the exit code pass through; the checkout is the tool's workspace; a
//! failed build never blocks a session (`up`/`install`/`auth` exit 0) and
//! leaves no half-written binary; no rustc falls back to `bazel run`; and with
//! neither, the session still starts and says why. Whether the real sources
//! build with a real rustc is :cloud-bootstrap_rustc_test's job.

use std::fs;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

fn runfile(var: &str) -> PathBuf {
    let rel = std::env::var_os(var).unwrap_or_else(|| panic!("{var} is not set"));
    fs::canonicalize(&rel).unwrap_or_else(|e| panic!("{var}={rel:?}: {e}"))
}

fn write_exec(p: &Path, body: &str) {
    fs::write(p, body).unwrap();
    fs::set_permissions(p, fs::Permissions::from_mode(0o755)).unwrap();
}

static SEQ: AtomicUsize = AtomicUsize::new(0);

struct Tree {
    dir: PathBuf,
}

impl Drop for Tree {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

/// The launcher's tree (tools/cloud-bootstrap/{cloud-bootstrap.sh,profiles.tsv,
/// src/cloud_bootstrap/*.rs}), a bin dir of just the tools it uses, a cache dir.
impl Tree {
    fn new() -> Tree {
        let base = std::env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        let dir = base.join(format!(
            "launcher-{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&dir);
        let pkg = dir.join("repo/tools/cloud-bootstrap");
        fs::create_dir_all(pkg.join("src/cloud_bootstrap")).unwrap();
        fs::create_dir_all(dir.join("bin")).unwrap();
        fs::copy(runfile("LAUNCHER"), pkg.join("cloud-bootstrap.sh")).unwrap();
        fs::set_permissions(
            pkg.join("cloud-bootstrap.sh"),
            fs::Permissions::from_mode(0o755),
        )
        .unwrap();
        fs::write(
            pkg.join("profiles.tsv"),
            "# fixture\nlauncherprof gh - - - Read from the launcher's own checkout.\n",
        )
        .unwrap();
        let src_dir = runfile("MAIN_RS").parent().unwrap().to_path_buf();
        for e in fs::read_dir(src_dir).unwrap() {
            let p = e.unwrap().path();
            if p.extension().map_or(false, |x| x == "rs") {
                fs::copy(
                    &p,
                    pkg.join("src/cloud_bootstrap").join(p.file_name().unwrap()),
                )
                .unwrap();
            }
        }
        // Only what the launcher itself runs, so neither a real rustc nor a
        // real bazel on the host can leak in.
        let path = std::env::var_os("PATH").unwrap_or_default();
        for tool in [
            "bash", "cat", "cksum", "tr", "mkdir", "mv", "rm", "tail", "dirname", "cp", "env",
            "find", "chmod", "touch",
        ] {
            let found = std::env::split_paths(&path)
                .map(|d| d.join(tool))
                .find(|p| p.is_file())
                .unwrap_or_else(|| panic!("{tool} not found on PATH"));
            symlink(found, dir.join("bin").join(tool)).unwrap();
        }
        Tree { dir }
    }

    fn launcher(&self) -> PathBuf {
        self.dir
            .join("repo/tools/cloud-bootstrap/cloud-bootstrap.sh")
    }

    fn cache(&self) -> PathBuf {
        self.dir.join("cache")
    }

    fn log(&self, name: &str) -> String {
        fs::read_to_string(self.dir.join(name)).unwrap_or_default()
    }

    /// A fake rustc: `--version` answers, a build is logged and the real
    /// Bazel-built tool copied to `-o`, or (FAIL) a compile error.
    fn fake_rustc(&self, fail: bool) {
        let tool = runfile("BIN");
        let log = self.dir.join("rustc.log");
        write_exec(
            &self.dir.join("bin/rustc"),
            &format!(
                r#"#!/usr/bin/env bash
# Like rustup's proxy: RUSTUP_TOOLCHAIN, or a rust-toolchain(.toml) in the
# working directory or any parent, picks a different (here: planted) compiler.
d="$PWD"
while :; do
  if [ -f "$d/rust-toolchain.toml" ] || [ -f "$d/rust-toolchain" ]; then planted=1; fi
  [ "$d" = / ] && break
  d="$(dirname "$d")"
done
if [ -n "${{RUSTUP_TOOLCHAIN:-}}" ] || [ -n "${{planted:-}}" ]; then
  touch "{pwned}"; echo "planted compiler ran" >&2; exit 1
fi
printf 'cwd=%s\n' "$PWD" >>"{cwdlog}"
if [ "$1" = --version ]; then echo "rustc 1.75.0 (fake)"; exit 0; fi
printf '%s\n' "$*" >>"{log}"
if [ "{fail}" = true ]; then echo "error[E0425]: cannot find value" >&2; exit 1; fi
while [ "$#" -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
cp "{tool}" "$out"
"#,
                log = log.display(),
                tool = tool.display(),
                pwned = self.dir.join("PWNED").display(),
                cwdlog = self.dir.join("rustc.cwd").display()
            ),
        );
    }

    fn fake_bazel(&self) {
        let log = self.dir.join("bazel.log");
        write_exec(
            &self.dir.join("bin/bazel"),
            &format!(
                "#!/usr/bin/env bash\nprintf '%s | %s\\n' \"$PWD\" \"$*\" >>\"{}\"\nexit 7\n",
                log.display()
            ),
        );
    }

    fn remove(&self, tool: &str) {
        let _ = fs::remove_file(self.dir.join("bin").join(tool));
    }

    /// Run the launcher the way the hook does: a clean environment, HOME and
    /// the cache pinned, no CLAUDE_PROJECT_DIR. stdout+stderr as one stream.
    fn run(&self, args: &[&str]) -> (String, i32) {
        let (out, _, rc) = self.run_with(args, &[], &[], true);
        (out, rc)
    }

    /// `run` with extra env, env vars removed, and (unless `merged`) stdout
    /// alone in the first slot, stderr in the second. Runs from the checkout,
    /// as the hook does.
    fn run_with(
        &self,
        args: &[&str],
        env: &[(&str, &str)],
        remove: &[&str],
        merged: bool,
    ) -> (String, String, i32) {
        let out_path = self.dir.join("run.out");
        let err_path = self.dir.join("run.err");
        let out = fs::File::create(&out_path).unwrap();
        let err = if merged {
            out.try_clone().unwrap()
        } else {
            fs::File::create(&err_path).unwrap()
        };
        let mut c = Command::new(self.dir.join("bin/bash"));
        c.arg(self.launcher())
            .args(args)
            .current_dir(self.dir.join("repo"))
            .env_clear()
            .env("PATH", self.dir.join("bin"))
            .env("HOME", self.dir.join("home"))
            .env("CLOUD_BOOTSTRAP_BUILD_DIR", self.cache())
            .stdin(Stdio::null())
            .stdout(out)
            .stderr(err);
        for (k, v) in env {
            c.env(k, v);
        }
        for k in remove {
            c.env_remove(k);
        }
        let st = c.status().unwrap();
        (
            fs::read_to_string(&out_path).unwrap(),
            fs::read_to_string(&err_path).unwrap_or_default(),
            st.code().unwrap_or(-1),
        )
    }

    fn builds(&self) -> usize {
        self.log("rustc.log").lines().count()
    }

    fn cached_binaries(&self) -> Vec<String> {
        let mut v: Vec<String> = fs::read_dir(self.cache())
            .map(|rd| {
                rd.filter_map(|e| e.ok())
                    .map(|e| e.file_name().to_string_lossy().into_owned())
                    .filter(|n| n.starts_with("cloud-bootstrap-"))
                    .collect()
            })
            .unwrap_or_default();
        v.sort();
        v
    }
}

#[test]
fn builds_once_then_reuses_and_passes_arguments_through() {
    let t = Tree::new();
    t.fake_rustc(false);
    let (out, rc) = t.run(&["profiles"]);
    assert_eq!(rc, 0, "{out}");
    assert_contains(
        &out,
        "  launcherprof Read from the launcher's own checkout.",
    );
    assert_eq!(t.builds(), 1, "the first run must build");
    assert!(
        t.log("rustc.log").contains("--edition 2021"),
        "built without --edition 2021: {}",
        t.log("rustc.log")
    );
    assert!(
        t.log("rustc.log").contains("src/cloud_bootstrap/main.rs"),
        "did not build main.rs: {}",
        t.log("rustc.log")
    );

    let (_, rc) = t.run(&["profiles"]);
    assert_eq!(rc, 0);
    assert_eq!(t.builds(), 1, "a second run must reuse the build");

    // Arguments and the tool's exit code pass straight through.
    let (out, rc) = t.run(&["bogus"]);
    assert_eq!(rc, 2, "the tool's exit code was not passed through:\n{out}");
    assert_contains(&out, "unknown subcommand 'bogus'");
    // ...and so do flags after the subcommand (the Setup script's --force).
    let (out, rc) = t.run(&["whoami", "--help"]);
    assert_eq!(rc, 0, "{out}");
    assert_contains(&out, "Usage: bazel run //tools/cloud-bootstrap");
}

#[test]
fn no_arguments_means_up_as_the_hook_calls_it() {
    let t = Tree::new();
    t.fake_rustc(false);
    let (out, rc) = t.run(&[]);
    assert_eq!(rc, 0);
    // `up` outside a cloud session stops at its guard: proof it ran `up`.
    assert_contains(&out, "not a cloud session");
}

#[test]
fn a_changed_source_rebuilds_and_prunes_the_old_build() {
    let t = Tree::new();
    t.fake_rustc(false);
    t.run(&["profiles"]);
    let first = t.cached_binaries();
    assert_eq!(first.len(), 1, "{first:?}");

    let main = t
        .dir
        .join("repo/tools/cloud-bootstrap/src/cloud_bootstrap/main.rs");
    let mut src = fs::read_to_string(&main).unwrap();
    src.push_str("\n// changed\n");
    fs::write(&main, src).unwrap();
    t.run(&["profiles"]);
    assert_eq!(t.builds(), 2, "a changed source must rebuild");
    let second = t.cached_binaries();
    assert_eq!(second.len(), 1, "the old build was not pruned: {second:?}");
    assert_ne!(first, second, "the rebuild reused the old cache key");
}

#[test]
fn a_failed_build_never_blocks_a_session() {
    let t = Tree::new();
    t.fake_rustc(true);
    for sub in ["up", "install", "auth"] {
        let (out, rc) = t.run(&[sub]);
        assert_eq!(
            rc, 0,
            "{sub} must exit 0 when the tool cannot be built:\n{out}"
        );
        assert_contains(&out, "rustc could not build");
        assert_contains(&out, "error[E0425]");
    }
    // The hook's stdout is what the agent sees, so the notice is there too.
    let (stdout, _, rc) = t.run_with(&["up"], &[], &[], false);
    assert_eq!(rc, 0);
    assert_contains(&stdout, "nothing bootstrapped");
    let (_, rc) = t.run(&["whoami"]);
    assert_eq!(
        rc, 1,
        "whoami is a gate: a tool that cannot be built must fail it"
    );
    assert!(
        t.cached_binaries().is_empty(),
        "a failed build left a binary behind: {:?}",
        t.cached_binaries()
    );
}

#[test]
fn without_rustc_it_falls_back_to_bazel_run_from_the_checkout() {
    let t = Tree::new();
    t.remove("rustc");
    t.fake_bazel();
    let (_, rc) = t.run(&["whoami", "--profile", "x"]);
    assert_eq!(rc, 7, "bazel's exit code was not passed through");
    let (_, _) = t.run(&[]);
    let (out, rc) = t.run(&["bogus"]);
    assert_eq!(rc, 2, "an unknown subcommand must exit 2:\n{out}");
    let log = t.log("bazel.log");
    let repo = fs::canonicalize(t.dir.join("repo")).unwrap();
    let lines: Vec<&str> = log.lines().collect();
    assert_eq!(lines.len(), 2, "{log}");
    assert_eq!(
        lines[0],
        format!(
            "{} | run --noshow_progress //tools/cloud-bootstrap:whoami -- --profile x",
            repo.display()
        )
    );
    assert_eq!(
        lines[1],
        format!(
            "{} | run --noshow_progress //tools/cloud-bootstrap:cloud-bootstrap --",
            repo.display()
        )
    );
}

#[test]
fn with_neither_the_session_still_starts_and_says_why() {
    let t = Tree::new();
    t.remove("rustc");
    let (out, rc) = t.run(&["up"]);
    assert_eq!(rc, 0, "up must not block the session:\n{out}");
    assert_contains(&out, "neither rustc nor bazel is installed");
    let (_, rc) = t.run(&["whoami"]);
    assert_eq!(rc, 1);
}

#[track_caller]
fn assert_contains(hay: &str, needle: &str) {
    assert!(hay.contains(needle), "{needle:?} not found in:\n{hay}");
}

#[test]
fn a_planted_rust_toolchain_or_rustup_toolchain_cannot_pick_the_compiler() {
    // rustup picks the compiler from a rust-toolchain(.toml) in the working
    // directory or any parent, or from RUSTUP_TOOLCHAIN. Session start runs
    // from the checkout, so a file in a branch could otherwise choose the
    // compiler that builds a binary which then holds the session's credentials.
    let t = Tree::new();
    t.fake_rustc(false);
    fs::write(
        t.dir.join("repo/rust-toolchain.toml"),
        "[toolchain]\nchannel = \"planted\"\n",
    )
    .unwrap();
    fs::write(
        t.dir.join("repo/tools/cloud-bootstrap/rust-toolchain"),
        "planted\n",
    )
    .unwrap();
    let (out, _, rc) = t.run_with(&["profiles"], &[("RUSTUP_TOOLCHAIN", "planted")], &[], true);
    assert_eq!(rc, 0, "{out}");
    assert!(
        !t.dir.join("PWNED").exists(),
        "the planted compiler ran:\n{out}"
    );
    assert_contains(&out, "launcherprof");
    let cwds = t.log("rustc.cwd");
    assert_eq!(
        cwds.lines().count(),
        2,
        "both rustc calls (--version and the build) must be seen: {cwds}"
    );
    assert!(
        cwds.lines().all(|l| l == "cwd=/"),
        "rustc ran outside /: {cwds}"
    );
}

#[test]
fn a_cached_binary_others_can_write_is_rebuilt_not_run() {
    let t = Tree::new();
    t.fake_rustc(false);
    t.run(&["profiles"]);
    let bin = t.cache().join(&t.cached_binaries()[0]);
    // Someone with group write swaps in their own binary. (Made writable
    // first: the fake copies Bazel's read-only output; rustc's would not be.)
    fs::set_permissions(&bin, fs::Permissions::from_mode(0o755)).unwrap();
    fs::write(&bin, "#!/bin/sh\necho PLANTED-BINARY-RAN\n").unwrap();
    fs::set_permissions(&bin, fs::Permissions::from_mode(0o775)).unwrap();
    let (out, rc) = t.run(&["profiles"]);
    assert_eq!(rc, 0, "{out}");
    assert!(
        !out.contains("PLANTED-BINARY-RAN"),
        "a group-writable cached binary was run:\n{out}"
    );
    assert_eq!(t.builds(), 2, "it must be rebuilt");
    assert_eq!(fs::metadata(&bin).unwrap().permissions().mode() & 0o022, 0);
}

#[test]
fn the_cache_dir_is_private() {
    let t = Tree::new();
    t.fake_rustc(false);
    t.run(&["profiles"]);
    assert_eq!(
        fs::metadata(t.cache()).unwrap().permissions().mode() & 0o777,
        0o700
    );
    // A cache dir others could write is made private before it is trusted.
    fs::set_permissions(t.cache(), fs::Permissions::from_mode(0o777)).unwrap();
    let (out, rc) = t.run(&["profiles"]);
    assert_eq!(rc, 0, "{out}");
    assert_eq!(
        fs::metadata(t.cache()).unwrap().permissions().mode() & 0o777,
        0o700
    );
}

#[test]
fn without_home_it_refuses_rather_than_using_a_shared_dir() {
    let t = Tree::new();
    t.fake_rustc(false);
    let unset = ["HOME", "CLOUD_BOOTSTRAP_BUILD_DIR"];
    let (out, _, rc) = t.run_with(&["up"], &[], &unset, true);
    assert_eq!(rc, 0, "up must not block the session:\n{out}");
    assert_contains(&out, "HOME is not set");
    assert_eq!(t.builds(), 0, "it built somewhere anyway");
    let (_, _, rc) = t.run_with(&["whoami"], &[], &unset, true);
    assert_eq!(rc, 1);
    // A relative cache path is refused too (it would resolve against the cwd).
    let (out, _, _) = t.run_with(
        &["up"],
        &[("CLOUD_BOOTSTRAP_BUILD_DIR", "rel/cache")],
        &[],
        true,
    );
    assert_contains(&out, "must be an absolute path");
}
