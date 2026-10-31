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

//! Black-box guard for the rdeps-map-ref binary (#2841): a real bare repository
//! stands in for GitHub, so save / fetch / prune run the same git commands they
//! run in CI. No network, no token. Each test builds its own repo pair; the
//! cases inside `fetch_returns_the_nearest_valid_map` run in order because each
//! builds on the refs the previous one stored.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn binary() -> PathBuf {
    let rel = std::env::var("RDEPS_MAP_REF_BIN").expect("set by Bazel");
    std::env::current_dir().unwrap().join(rel)
}

/// `jq` from the hermetic toolchain, put first on PATH (the binary shells out to it).
fn path_with_jq() -> String {
    let mut path = std::env::var("PATH").unwrap_or_default();
    if let Ok(jq) = std::env::var("JQ_BIN") {
        let jq = match jq.strip_prefix("external/") {
            Some(rest) => format!("../{rest}"),
            None => jq,
        };
        let abs = std::env::current_dir().unwrap().join(jq);
        path = format!("{}:{path}", abs.parent().unwrap().display());
    }
    path
}

fn git(dir: &Path, args: &[&str]) -> String {
    let o = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .output()
        .expect("git runs");
    assert!(
        o.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&o.stderr)
    );
    String::from_utf8_lossy(&o.stdout).trim().to_string()
}

struct Env {
    work: PathBuf,
    repo: PathBuf,
    remote: PathBuf,
    path: String,
    shas: Vec<String>,
}

impl Env {
    fn new() -> Env {
        let base = std::env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".into());
        use std::sync::atomic::{AtomicU32, Ordering};
        static N: AtomicU32 = AtomicU32::new(0);
        let work = Path::new(&base).join(format!(
            "rdeps-map-ref-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_dir_all(&work);
        std::fs::create_dir_all(&work).unwrap();
        let remote = work.join("remote.git");
        let repo = work.join("repo");
        assert!(Command::new("git")
            .args(["init", "-q", "--bare"])
            .arg(&remote)
            .status()
            .unwrap()
            .success());
        assert!(Command::new("git")
            .args(["init", "-q", "-b", "main"])
            .arg(&repo)
            .status()
            .unwrap()
            .success());
        git(&repo, &["config", "user.email", "test@example.com"]);
        git(&repo, &["config", "user.name", "test"]);
        git(&repo, &["config", "commit.gpgsign", "false"]);
        git(
            &repo,
            &["remote", "add", "origin", remote.to_str().unwrap()],
        );
        let mut shas = Vec::new();
        for i in 1..=6 {
            std::fs::write(repo.join("f"), format!("{i}\n")).unwrap();
            git(&repo, &["add", "f"]);
            git(&repo, &["commit", "-q", "-m", &format!("c{i}")]);
            shas.push(git(&repo, &["rev-parse", "HEAD"]));
        }
        git(&repo, &["push", "-q", "origin", "main"]);
        Env {
            work,
            repo,
            remote,
            path: path_with_jq(),
            shas,
        }
    }

    fn run(&self, args: &[&str], envs: &[(&str, &str)]) -> Output {
        let mut c = Command::new(binary());
        c.args(args)
            .current_dir(&self.repo)
            .env("PATH", &self.path)
            .env_remove("GH_TOKEN")
            .env_remove("GITHUB_OUTPUT")
            .env_remove("RDEPS_MAP_REMOTE")
            .env_remove("RDEPS_MAP_MAX_BEHIND")
            .env_remove("RDEPS_MAP_KEEP")
            .env("GIT_TERMINAL_PROMPT", "0");
        for (k, v) in envs {
            c.env(k, v);
        }
        c.output().expect("binary runs")
    }

    fn mkmap(&self, commit: &str) -> PathBuf {
        let p = self.work.join("map.json");
        std::fs::write(
            &p,
            format!("{{\"schema\":1,\"commit\":\"{commit}\",\"packages\":[\"a\"]}}"),
        )
        .unwrap();
        p
    }

    fn remote_has(&self, sha: &str) -> bool {
        Command::new("git")
            .arg("-C")
            .arg(&self.remote)
            .args([
                "show-ref",
                "--verify",
                "--quiet",
                &format!("refs/rdeps-map/{sha}"),
            ])
            .status()
            .unwrap()
            .success()
    }

    fn fetch(&self, out: &Path, base: &str, envs: &[(&str, &str)]) -> (String, String) {
        let o = self.run(&["fetch", out.to_str().unwrap(), base], envs);
        assert!(
            o.status.success(),
            "fetch must exit 0: {}",
            String::from_utf8_lossy(&o.stderr)
        );
        (
            String::from_utf8_lossy(&o.stdout).trim_end().to_string(),
            String::from_utf8_lossy(&o.stderr).to_string(),
        )
    }
}

impl Drop for Env {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.work);
    }
}

#[test]
fn save_stores_refuses_and_creates_no_branches() {
    let e = Env::new();
    let map = e.mkmap(&e.shas[1]);
    let o = e.run(&["save", map.to_str().unwrap(), &e.shas[1]], &[]);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    assert!(
        e.remote_has(&e.shas[1]),
        "map stored at refs/rdeps-map/<sha>"
    );

    let o = e.run(&["save", map.to_str().unwrap(), &e.shas[2]], &[]);
    assert!(
        !o.status.success(),
        "a map for another commit must be refused"
    );
    assert!(!e.remote_has(&e.shas[2]), "saved a mislabelled map");

    let o = e.run(&["save", map.to_str().unwrap(), "not-a-sha"], &[]);
    assert_eq!(
        o.status.code(),
        Some(2),
        "a ref name that is not a full sha"
    );

    let o = e.run(&["save"], &[]);
    assert_eq!(
        o.status.code(),
        Some(1),
        "missing arguments: {}",
        String::from_utf8_lossy(&o.stderr)
    );

    let refs = git(&e.remote, &["for-each-ref", "refs/heads", "refs/tags"]);
    assert!(
        refs.lines().all(|l| l.ends_with("refs/heads/main")),
        "created a branch or tag: {refs}"
    );
}

#[test]
fn an_unknown_command_is_a_usage_error() {
    let e = Env::new();
    assert_eq!(e.run(&[], &[]).status.code(), Some(2));
    assert_eq!(e.run(&["frobnicate"], &[]).status.code(), Some(2));
}

#[test]
fn fetch_returns_the_nearest_valid_map() {
    let e = Env::new();
    let map = e.mkmap(&e.shas[1]);
    assert!(e
        .run(&["save", map.to_str().unwrap(), &e.shas[1]], &[])
        .status
        .success());
    let out = e.work.join("out.json");

    // Exact base: the map comes back byte for byte.
    let (stdout, stderr) = e.fetch(&out, &e.shas[1], &[]);
    assert_eq!(stdout, format!("commit={}", e.shas[1]), "{stderr}");
    assert_eq!(std::fs::read(&out).unwrap(), std::fs::read(&map).unwrap());

    // A base without a map gets its nearest ancestor's.
    std::fs::remove_file(&out).unwrap();
    let (stdout, stderr) = e.fetch(&out, &e.shas[3], &[]);
    assert_eq!(stdout, format!("commit={}", e.shas[1]), "{stderr}");
    assert!(stderr.contains("2 commit(s) behind"), "{stderr}");

    // The nearer of two ancestors wins.
    let map2 = e.mkmap(&e.shas[2]);
    assert!(e
        .run(&["save", map2.to_str().unwrap(), &e.shas[2]], &[])
        .status
        .success());
    let (stdout, _) = e.fetch(&out, &e.shas[3], &[]);
    assert_eq!(stdout, format!("commit={}", e.shas[2]));

    // Nothing within the limit: no file, empty result, exit 0.
    std::fs::remove_file(&out).unwrap();
    let (stdout, _) = e.fetch(&out, &e.shas[5], &[("RDEPS_MAP_MAX_BEHIND", "1")]);
    assert_eq!(stdout, "commit=");
    assert!(!out.exists(), "no file when nothing is found");

    // A map for a LATER commit is never returned.
    let (stdout, _) = e.fetch(&out, &e.shas[0], &[]);
    assert_eq!(stdout, "commit=");

    // An unresolvable base is an empty result, not an error.
    let (stdout, _) = e.fetch(&out, "0000000000000000000000000000000000000000", &[]);
    assert_eq!(stdout, "commit=");

    // A mislabelled map on the remote is skipped and the next ancestor used.
    let bad = {
        let mut c = Command::new("git");
        c.arg("-C")
            .arg(&e.repo)
            .args(["hash-object", "-w", "--stdin"]);
        c.stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped());
        let mut child = c.spawn().unwrap();
        use std::io::Write;
        child
            .stdin
            .take()
            .unwrap()
            .write_all(format!("{{\"commit\":\"{}\"}}", e.shas[0]).as_bytes())
            .unwrap();
        String::from_utf8(child.wait_with_output().unwrap().stdout)
            .unwrap()
            .trim()
            .to_string()
    };
    git(
        &e.repo,
        &[
            "push",
            "-q",
            "origin",
            &format!("+{bad}:refs/rdeps-map/{}", e.shas[4]),
        ],
    );
    let (stdout, stderr) = e.fetch(&out, &e.shas[4], &[]);
    assert_eq!(stdout, format!("commit={}", e.shas[2]), "{stderr}");
    assert!(stderr.contains("unreadable or mislabelled"), "{stderr}");
}

#[test]
fn fetch_writes_commit_to_github_output() {
    let e = Env::new();
    let map = e.mkmap(&e.shas[2]);
    assert!(e
        .run(&["save", map.to_str().unwrap(), &e.shas[2]], &[])
        .status
        .success());
    let gho = e.work.join("gho");
    std::fs::write(&gho, "").unwrap();
    let out = e.work.join("out.json");
    let o = e.run(
        &["fetch", out.to_str().unwrap(), &e.shas[2]],
        &[("GITHUB_OUTPUT", gho.to_str().unwrap())],
    );
    assert!(o.status.success());
    let written = std::fs::read_to_string(&gho).unwrap();
    assert!(
        written
            .lines()
            .any(|l| l == format!("commit={}", e.shas[2])),
        "{written}"
    );
}

#[test]
fn prune_drops_old_maps_and_refuses_to_guess_on_thin_history() {
    let e = Env::new();
    for i in [1usize, 2, 4] {
        let map = e.mkmap(&e.shas[i]);
        assert!(e
            .run(&["save", map.to_str().unwrap(), &e.shas[i]], &[])
            .status
            .success());
    }
    // Keeps commits 3..6 (indexes 2..5).
    let o = e.run(&["prune"], &[("RDEPS_MAP_KEEP", "4")]);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    assert!(!e.remote_has(&e.shas[1]), "an old map must be dropped");
    assert!(
        e.remote_has(&e.shas[2]) && e.remote_has(&e.shas[4]),
        "recent maps must stay"
    );

    // With too little history to judge, prune nothing.
    let o = e.run(&["prune"], &[("RDEPS_MAP_KEEP", "1")]);
    assert!(o.status.success());
    assert!(String::from_utf8_lossy(&o.stderr).contains("pruning nothing"));
    assert!(e.remote_has(&e.shas[2]));

    let main = Command::new("git")
        .arg("-C")
        .arg(&e.remote)
        .args(["show-ref", "--verify", "--quiet", "refs/heads/main"])
        .status()
        .unwrap();
    assert!(main.success(), "main untouched");
}
