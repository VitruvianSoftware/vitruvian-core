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

//! LauncherTest (:hook_test): every launcher in the tree (hook.sh, and
//! proposed-hook.sh while it waits to replace it) in a throwaway git
//! checkout with an origin/main ref. It must run origin/main's guard, not a
//! local edit; fall back to the working copy when origin/main's is not there
//! or will not build or run; try each program it knows in turn; and find the
//! checkout from its own path whichever folder it is run from.
//!
//! Most cases use testlib's stand-ins (a stub python, or a stub rustc that
//! "builds" a stub guard), so they test the launcher and nothing else. The
//! Rust launcher is also run once with the Bazel toolchain's real rustc on
//! the real src/, end to end: compiled from origin/main, then answering.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::process::{Command, Stdio};
use std::time::Instant;

use agent_guard::paths::{exists, isfile, join};
use agent_guard::pyval::{loads, PyVal};

use crate::installer::{AGY_COMMAND, CLAUDE_COMMAND};
use crate::testlib::{
    self, agy, claude, clean_env, decision, git, launcher_text_of, launchers, read, runfile, write,
    Checkout, Flavor, BROKEN, EXITS_1,
};

/// Run co's launcher as Claude Code does (default) or as `command` from `cwd`:
/// (exit code, stdout trimmed, stderr).
fn run(
    co: &Checkout,
    payload: &PyVal,
    cwd: Option<&str>,
    command: Option<&str>,
) -> (i32, String, String) {
    let mut child = Command::new("/bin/sh")
        .arg("-c")
        .arg(command.unwrap_or(CLAUDE_COMMAND))
        .current_dir(cwd.unwrap_or(&co.out))
        .env_clear()
        .envs(clean_env())
        .env("HOME", &co.home)
        .env("CLAUDE_PROJECT_DIR", &co.root)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("sh runs");
    {
        use std::io::Write;
        let mut stdin = child.stdin.take().unwrap();
        stdin
            .write_all(agent_guard::pyval::dumps(payload, false).as_bytes())
            .unwrap();
    }
    let out = child.wait_with_output().unwrap();
    (
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stdout).trim().to_string(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

/// The copy the stub guard was told it is (AGENT_GUARD_SOURCE), last call first.
fn stub_source(err: &str) -> String {
    err.lines()
        .filter_map(|l| l.strip_prefix("stub guard: source="))
        .last()
        .unwrap_or_else(|| panic!("the stub guard did not run:\n{}", err))
        .to_string()
}

/// origin/main's id for the guard the launcher runs (a blob, or src/'s tree).
fn main_id(co: &Checkout) -> String {
    git(
        &co.root,
        &[
            "rev-parse",
            &format!("origin/main:{}", co.flavor.guard_on_main()),
        ],
    )
    .trim()
    .to_string()
}

fn cache(co: &Checkout) -> String {
    join(&co.home, ".local/state/agent-guard/cache")
}

/// What the launcher caches main's guard as.
fn cached_guard(co: &Checkout, id: &str) -> String {
    match co.flavor {
        Flavor::Python => join(&cache(co), &format!("guard-{}/agent_guard.py", id)),
        Flavor::Rust => join(&cache(co), &format!("guard-{}", id)),
    }
}

/// An executable stand-in that runs body as a shell script.
fn fake(dir: &str, name: &str, body: &str) -> String {
    let path = join(dir, name);
    write(&path, &format!("#!/bin/sh\n{}\n", body));
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    path
}

/// How many times the stub rustc ran.
fn rustc_calls(co: &Checkout) -> usize {
    let path = format!("{}.calls", co.stub);
    if exists(&path) {
        read(&path).lines().count()
    } else {
        0
    }
}

/// Each launcher in the tree, in its own fresh checkout.
fn each(f: impl Fn(&str, Checkout)) {
    let all = launchers();
    assert!(!all.is_empty(), "no launcher in the runfiles");
    for rel in all {
        f(&rel, Checkout::with_launcher(&rel, None, true));
    }
}

#[test]
fn both_launchers_are_tested_until_the_switch() {
    // hook.sh is always there; proposed-hook.sh only until James moves it
    // over hook.sh. Either way some launcher in the tree is the Rust one,
    // and after the move it is hook.sh itself.
    let all = launchers();
    assert_eq!(all[0], "tools/agent-guard/hook.sh");
    assert!(
        all.iter()
            .any(|rel| testlib::flavor_of(&read(&testlib::launcher_file(rel))) == Flavor::Rust),
        "no launcher here runs the Rust guard: {:?}",
        all
    );
}

#[test]
fn runs_origin_mains_guard_not_the_local_edit() {
    each(|rel, co| {
        // An agent breaks the working copy and switches every category off:
        // it governs nothing, because origin/main's copy is what runs.
        co.break_guard();
        co.set_policy(&[("git-stash", "off"), ("go", "off")], false);
        let (rc, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(
            (rc, decision(&out, false).as_str()),
            (0, "deny"),
            "{}: {}",
            rel,
            err
        );
        let (rc, out, err) = run(&co, &claude("git status", &co.root), None, None);
        assert_eq!((rc, out.as_str()), (0, ""), "{}: {}", rel, err);
        assert_eq!(
            stub_source(&err),
            format!("origin/main:{}", main_id(&co)),
            "{}",
            rel
        );
    });
}

#[test]
fn a_merged_change_takes_effect() {
    each(|rel, co| {
        co.set_policy(&[("git-stash", "off")], true);
        let (rc, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!((rc, out.as_str()), (0, ""), "{}: {}", rel, err);
    });
}

#[test]
fn caches_by_id_in_the_protected_state_folder() {
    each(|rel, co| {
        run(&co, &claude("git status", &co.root), None, None);
        let id = main_id(&co);
        let pid = git(
            &co.root,
            &["rev-parse", "origin/main:tools/agent-guard/policy.json"],
        );
        let guard = cached_guard(&co, &id);
        assert!(isfile(&guard), "{}: no {}", rel, guard);
        assert!(
            isfile(&join(&cache(&co), &format!("policy-{}.json", pid.trim()))),
            "{}",
            rel
        );
        let mode = fs::metadata(cache(&co)).unwrap().permissions().mode();
        assert_eq!(mode & 0o077, 0, "{}: cache mode {:o}", rel, mode);
        // The cache is what the guard protects: agents may not write there.
        assert!(agent_guard::tamper::guard_path(&guard, &co.home), "{}", rel);
        // A missing entry is rebuilt on the next call.
        let entry = join(&cache(&co), &format!("guard-{}", id));
        if co.flavor == Flavor::Python {
            fs::remove_dir_all(&entry).unwrap();
        } else {
            fs::remove_file(&entry).unwrap();
        }
        let (_, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(decision(&out, false), "deny", "{}: {}", rel, err);
        assert!(isfile(&guard), "{}", rel);
    });
}

#[test]
fn falls_back_to_the_working_copy_without_origin_main() {
    each(|rel, co| {
        co.set_policy(&[("git-stash", "off")], false);
        git(&co.root, &["update-ref", "-d", "refs/remotes/origin/main"]);
        let (rc, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        // The working copy's policy decided.
        assert_eq!((rc, out.as_str()), (0, ""), "{}: {}", rel, err);
        assert!(err.contains("not origin/main's copy"), "{}: {}", rel, err);
        assert!(
            stub_source(&err).starts_with("working-copy (no origin/main"),
            "{}: {}",
            rel,
            err
        );
    });
}

#[test]
fn falls_back_when_main_has_no_guard() {
    each(|rel, co| {
        git(
            &co.root,
            &["rm", "-rq", "--cached", co.flavor.guard_on_main()],
        );
        git(&co.root, &["commit", "-qm", "drop", "--no-gpg-sign"]);
        git(
            &co.root,
            &["update-ref", "refs/remotes/origin/main", "HEAD"],
        );
        let (_, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(decision(&out, false), "deny", "{}: {}", rel, err);
        assert!(
            stub_source(&err).starts_with("working-copy"),
            "{}: {}",
            rel,
            err
        );
    });
}

#[test]
fn falls_back_outside_git() {
    for rel in launchers() {
        let co = Checkout::with_launcher(&rel, None, false);
        let (rc, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(
            (rc, decision(&out, false).as_str()),
            (0, "deny"),
            "{}: {}",
            rel,
            err
        );
        assert!(
            stub_source(&err).starts_with("working-copy"),
            "{}: {}",
            rel,
            err
        );
    }
}

#[test]
fn a_main_copy_that_will_not_build_or_run_falls_back_to_the_working_copy() {
    each(|rel, co| {
        co.break_guard();
        co.commit_to_main("broken guard on main");
        for src in co.flavor.guard_sources() {
            co.write(src, "// the working copy, which works\n");
        }
        let (rc, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(
            (rc, decision(&out, false).as_str()),
            (0, "deny"),
            "{}: {}",
            rel,
            err
        );
        let want = match co.flavor {
            Flavor::Python => "origin/main's copy failed",
            Flavor::Rust => "origin/main's copy did not build",
        };
        assert!(stub_source(&err).contains(want), "{}: {}", rel, err);
    });
}

#[test]
fn a_main_build_that_exits_1_falls_back_to_the_working_copy() {
    each(|rel, co| {
        if co.flavor != Flavor::Rust {
            return; // the Python launcher has no build step
        }
        co.write("tools/agent-guard/src/main.rs", EXITS_1);
        co.commit_to_main("main's guard exits 1");
        co.write("tools/agent-guard/src/main.rs", "// the working copy\n");
        let (rc, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(
            (rc, decision(&out, false).as_str()),
            (0, "deny"),
            "{}: {}",
            rel,
            err
        );
        assert!(
            stub_source(&err).contains("origin/main's copy failed with exit 1"),
            "{}: {}",
            rel,
            err
        );
    });
}

#[test]
fn a_build_is_done_once_and_a_failed_one_is_not_retried() {
    each(|rel, co| {
        if co.flavor != Flavor::Rust {
            return;
        }
        // One build (lib.rs, then main.rs), then the cached binary.
        run(&co, &claude("git status", &co.root), None, None);
        assert_eq!(rustc_calls(&co), 2, "{}", rel);
        run(&co, &claude("git status", &co.root), None, None);
        assert_eq!(rustc_calls(&co), 2, "{}", rel);
        // main breaks: tried once, remembered, and the working copy answers.
        co.break_guard();
        co.commit_to_main("broken guard on main");
        for src in co.flavor.guard_sources() {
            co.write(src, "// the working copy, which works\n");
        }
        let (_, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(decision(&out, false), "deny", "{}: {}", rel, err);
        assert!(
            isfile(&format!("{}.failed", cached_guard(&co, &main_id(&co)))),
            "{}",
            rel
        );
        let after = rustc_calls(&co);
        let (_, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(decision(&out, false), "deny", "{}: {}", rel, err);
        assert_eq!(rustc_calls(&co), after, "{}: rebuilt a known failure", rel);
    });
}

#[test]
fn an_older_main_build_is_the_last_resort() {
    each(|rel, co| {
        if co.flavor != Flavor::Rust {
            return;
        }
        run(&co, &claude("git status", &co.root), None, None); // builds main's copy
        let old = main_id(&co);
        co.break_guard();
        co.commit_to_main("broken guard on main"); // and the working copy is broken too
        let (rc, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(
            (rc, decision(&out, false).as_str()),
            (0, "deny"),
            "{}: {}",
            rel,
            err
        );
        assert!(
            err.contains("running an older origin/main build"),
            "{}: {}",
            rel,
            err
        );
        assert!(
            stub_source(&err).starts_with(&format!("origin/main:{} (stale: ", old)),
            "{}: {}",
            rel,
            err
        );
    });
}

#[test]
fn tries_each_program_in_turn() {
    for rel in launchers() {
        let co = Checkout::new_for(&rel);
        let bin = join(&co.tmp, "bin");
        fs::create_dir_all(&bin).unwrap();
        let broken = fake(&bin, "broken", "exit 1");
        let chain = vec!["/nonexistent/stand-in".to_string(), broken, co.stub.clone()];
        co.write("tools/agent-guard/hook.sh", &launcher_text_of(&rel, &chain));
        let (rc, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(
            (rc, decision(&out, false).as_str()),
            (0, "deny"),
            "{}: {}",
            rel,
            err
        );
    }
}

#[test]
fn exits_1_only_when_nothing_works() {
    for rel in launchers() {
        let co = Checkout::new_for(&rel);
        let bin = join(&co.tmp, "bin");
        fs::create_dir_all(&bin).unwrap();
        let broken = fake(&bin, "broken", "exit 1");
        let chain = vec!["/nonexistent/stand-in".to_string(), broken.clone()];
        co.write("tools/agent-guard/hook.sh", &launcher_text_of(&rel, &chain));
        let (rc, out, err) = run(&co, &claude("git status", &co.root), None, None);
        assert_eq!((rc, out.as_str()), (1, ""), "{}: {}", rel, err);
        assert!(err.contains(co.flavor.nothing_ran()), "{}: {}", rel, err);
        assert!(err.contains(&broken), "{}: {}", rel, err);
    }
}

#[test]
fn agy_runs_it_from_dot_agents() {
    each(|rel, co| {
        let dot_agents = join(&co.root, ".agents");
        let (rc, out, err) = run(
            &co,
            &agy("go vet ./...", &co.root),
            Some(&dot_agents),
            Some(AGY_COMMAND),
        );
        assert_eq!(
            (rc, decision(&out, true).as_str()),
            (0, "deny"),
            "{}: {}",
            rel,
            err
        );
        let (rc, out, err) = run(
            &co,
            &agy("git status", &co.root),
            Some(&dot_agents),
            Some(AGY_COMMAND),
        );
        assert_eq!((rc, out.as_str()), (0, ""), "{}: {}", rel, err);
        assert!(
            stub_source(&err).starts_with("origin/main:"),
            "{}: {}",
            rel,
            err
        );
    });
}

#[test]
fn finds_the_checkout_from_its_own_path_not_the_cwd() {
    each(|rel, co| {
        // Claude Code runs it from wherever the agent is, even another checkout.
        let other = Checkout::new_for(rel);
        other.set_policy(&[("git-stash", "off")], true);
        let (_, out, err) = run(&co, &claude("git stash", &co.root), Some(&other.root), None);
        assert_eq!(decision(&out, false), "deny", "{}: {}", rel, err);
    });
}

#[test]
fn the_real_launchers_are_valid_sh_and_list_what_they_try() {
    for rel in launchers() {
        let path = testlib::launcher_file(&rel);
        let ok = Command::new("/bin/sh")
            .arg("-n")
            .arg(&path)
            .status()
            .unwrap();
        assert!(ok.success(), "{} is not valid sh", rel);
        let text = read(&path);
        let (begin, end) = match testlib::flavor_of(&text) {
            Flavor::Python => ("# --- pythons: begin", "# --- pythons: end ---\n"),
            Flavor::Rust => ("# --- rustcs: begin", "# --- rustcs: end ---\n"),
        };
        let a = text.find(begin).unwrap();
        let block = &text[a..a + text[a..].find(end).unwrap()];
        match testlib::flavor_of(&text) {
            Flavor::Python => {
                let r = Command::new("/bin/sh")
                    .arg("-c")
                    .arg(format!("{}\necho \"$pythons\"", block))
                    .output()
                    .unwrap();
                let listed = String::from_utf8_lossy(&r.stdout).into_owned();
                let chain: Vec<&str> = listed.split_whitespace().collect();
                assert_eq!(
                    chain[chain.len() - 2..],
                    [
                        "/Library/Developer/CommandLineTools/usr/bin/python3",
                        "/usr/bin/python3"
                    ],
                    "{}",
                    rel
                );
                let brew: Vec<u32> = chain[..chain.len() - 2]
                    .iter()
                    .filter(|p| p.starts_with("/opt/homebrew/"))
                    .map(|p| p.rsplit("python3.").next().unwrap().parse().unwrap())
                    .collect();
                let mut sorted = brew.clone();
                sorted.sort_by(|a, b| b.cmp(a));
                assert_eq!(brew, sorted, "{}", rel);
            }
            Flavor::Rust => {
                // rustcs lists only programs that exist, the PATH's last;
                // never rustup's proxy, which can stop to download.
                let home = testlib::tmpdir("agent-guard-rustcs-");
                let r = Command::new("/bin/sh")
                    .arg("-c")
                    .arg(format!("{}\nrustcs", block))
                    .env("HOME", &home)
                    .output()
                    .unwrap();
                let _ = fs::remove_dir_all(&home);
                assert!(r.status.success() || r.stdout.is_empty(), "{}", rel);
                for p in String::from_utf8_lossy(&r.stdout).lines() {
                    assert!(!p.ends_with("/.cargo/bin/rustc"), "{}: {}", rel, p);
                    assert!(exists(p), "{}: lists {}, which is not there", rel, p);
                }
                assert!(block.contains("command -v rustc"), "{}", rel);
            }
        }
    }
}

#[test]
fn latency() {
    each(|rel, co| {
        run(&co, &claude("git status", &co.root), None, None); // warm the cache
        let n = 10;
        let start = Instant::now();
        for _ in 0..n {
            run(&co, &claude("git status", &co.root), None, None);
        }
        let ms = start.elapsed().as_millis() / n;
        eprintln!("{}: {} ms a call (git status, warm cache)", rel, ms);
        // Generous: CI machines are slow and shared. Locally it is ~20-50 ms.
        assert!(ms < 3000, "{}: {} ms", rel, ms);
    });
}

/// The Bazel toolchain's rustc, from the test's runfiles (AGENT_GUARD_RUSTC).
fn toolchain_rustc() -> String {
    let rel = std::env::var("AGENT_GUARD_RUSTC")
        .expect("AGENT_GUARD_RUSTC (the BUILD file passes the toolchain's rustc)");
    // A rootpath: relative to the main repository's runfiles folder.
    let path = runfile(&rel);
    assert!(isfile(&path), "no rustc at {}", path);
    path
}

/// The real path, end to end: the real src/ on origin/main, built by the
/// Rust launcher with a real rustc, refuses `git stash` and allows `git
/// status` in both agents' formats, and logs that origin/main's copy decided.
#[test]
fn the_rust_launcher_builds_and_runs_the_real_guard() {
    let rustc = toolchain_rustc();
    let mut ran = 0;
    for rel in launchers() {
        let probe = Checkout::new_for(&rel);
        if probe.flavor != Flavor::Rust {
            continue;
        }
        drop(probe);
        let co = Checkout::with_launcher(&rel, Some(vec![rustc.clone()]), true);
        let src = join(&co.guard_dir, "src");
        fs::remove_dir_all(&src).unwrap();
        let real = runfile("tools/agent-guard/src/lib.rs");
        let real_dir = &real[..real.len() - "/lib.rs".len()];
        let mut copied = 0;
        for e in fs::read_dir(real_dir).unwrap().flatten() {
            let name = e.file_name().to_string_lossy().into_owned();
            if name.ends_with(".rs") {
                write(&join(&src, &name), &read(&e.path().to_string_lossy()));
                copied += 1;
            }
        }
        assert!(copied > 2, "{}: copied only {} files of src/", rel, copied);
        co.commit_to_main("the real guard");
        let id = main_id(&co);

        let (rc, out, err) = run(&co, &claude("git stash", &co.root), None, None);
        assert_eq!(
            (rc, decision(&out, false).as_str()),
            (0, "deny"),
            "{}: {}",
            rel,
            err
        );
        assert!(out.contains("Blocked by agent-guard"), "{}: {}", rel, out);
        assert!(
            isfile(&cached_guard(&co, &id)),
            "{}: built nothing\n{}",
            rel,
            err
        );
        let (rc, out, err) = run(&co, &claude("git status", &co.root), None, None);
        assert_eq!((rc, out.as_str()), (0, ""), "{}: {}", rel, err);
        let dot_agents = join(&co.root, ".agents");
        let (rc, out, err) = run(
            &co,
            &agy("git stash", &co.root),
            Some(&dot_agents),
            Some(AGY_COMMAND),
        );
        assert_eq!(
            (rc, decision(&out, true).as_str()),
            (0, "deny"),
            "{}: {}",
            rel,
            err
        );

        let log = read(&join(&co.home, ".local/state/agent-guard/log.jsonl"));
        let last = loads(log.lines().last().expect("a log line")).unwrap();
        assert_eq!(
            last.get("source").and_then(|v| v.as_str()),
            Some(format!("origin/main:{}", id).as_str()),
            "{}: {}",
            rel,
            log
        );
        assert_eq!(
            last.get("agent").and_then(|v| v.as_str()),
            Some("antigravity"),
            "{}",
            rel
        );
        ran += 1;
    }
    assert!(ran > 0, "no Rust launcher in the tree");
}

#[test]
fn stand_ins_fail_the_way_the_tests_assume() {
    // BROKEN and EXITS_1 are what the stubs key on: keep them in step.
    assert!(BROKEN.contains("does not compile"));
    assert!(EXITS_1.contains("then exits 1"));
}
