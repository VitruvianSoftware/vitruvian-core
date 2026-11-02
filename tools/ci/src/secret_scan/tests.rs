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

//! //tools/ci:secret_scan_test. Runs the REAL binary in throwaway git repos
//! with a stub `gitleaks` (and, for the download path, a fake `curl`) first on
//! PATH. Ported case for case from the former secret-scan_test.sh, which pinned
//! the decision logic: an exec failure is not a finding, a finding is, and a
//! system gitleaks off the pin is refused. Added: which range is scanned for
//! each BASE_REV/BASE_REF combination, the download path failing closed, exit
//! codes the script's `set -e` produced, and the pin held level with
//! tools/tools.lock.json (which //tools/secret-scan uses locally).

use ci_testkit::{bin, commit_file, git, git_init, read, write_exe, Output, Run, TempDir};
use std::path::{Path, PathBuf};

/// The pin, read from the source rather than copied: a literal here would
/// keep passing after a bump while asserting the old pin.
fn pin(name: &str) -> String {
    let src = read(std::env::var("SRC").expect("SRC: the rust_test must pass the lib's path"));
    let key = format!("const {name}: &str = \"");
    let start = src
        .find(&key)
        .unwrap_or_else(|| panic!("no {name} in the secret_scan source"))
        + key.len();
    src[start..start + src[start..].find('"').unwrap()].to_string()
}

struct Repo {
    _dir: TempDir,
    root: PathBuf,
    fakes: PathBuf,
    log: PathBuf,
}

/// A repo with a base commit, plus a stub gitleaks reporting `version` and
/// exiting `scan_rc` for any scan. The stub logs `<pwd>|<args>` per scan.
fn repo(version: &str, scan_rc: i32) -> Repo {
    let dir = TempDir::new();
    let root = dir.join("repo");
    git_init(&root);
    commit_file(&root, ".gitleaks.toml", "", "rules");
    commit_file(&root, "file.txt", "hello\n", "base");
    let fakes = dir.join("fakes");
    let log = dir.join("gitleaks.log");
    write_exe(
        fakes.join("gitleaks"),
        format!(
            "#!/usr/bin/env bash\nif [ \"${{1:-}}\" = version ]; then printf '%s\\n' '{version}'; exit 0; fi\nprintf '%s|%s\\n' \"$PWD\" \"$*\" >> '{}'\nexit {scan_rc}\n",
            log.display()
        ),
    );
    Repo {
        _dir: dir,
        root,
        fakes,
        log,
    }
}

fn scan(r: &Repo, env: &[(&str, &str)]) -> Output {
    scan_in(r, &r.root, env)
}

fn scan_in(r: &Repo, cwd: &Path, env: &[(&str, &str)]) -> Output {
    let mut run = Run::new(&bin("BIN"))
        .cwd(cwd)
        .path_first(&r.fakes)
        .env("USE_SYSTEM_GITLEAKS", "1")
        .env("BASE_REV", "")
        .env("BASE_REF", "");
    for (k, v) in env {
        run = run.env(k, v);
    }
    run.go_within(std::time::Duration::from_secs(60))
        .expect("secret-scan hung")
}

fn scans(r: &Repo) -> Vec<String> {
    read(&r.log).lines().map(str::to_string).collect()
}

// --- the shell suite, case for case ------------------------------------------

#[test]
fn exec_failure_126_is_not_a_finding() {
    let r = repo(&pin("GITLEAKS_VERSION"), 126);
    let o = scan(&r, &[]);
    assert_eq!(o.code, 126);
    assert!(o.all().contains("gitleaks did not run"), "{}", o.all());
    assert!(!o.all().contains("found a candidate secret"));
}

#[test]
fn exec_failure_127_is_not_a_finding() {
    let r = repo(&pin("GITLEAKS_VERSION"), 127);
    let o = scan(&r, &[]);
    assert_eq!(o.code, 127);
    assert!(o.all().contains("gitleaks did not run"), "{}", o.all());
}

#[test]
fn a_real_finding_is_reported_as_a_finding() {
    let r = repo(&pin("GITLEAKS_VERSION"), 1);
    let o = scan(&r, &[]);
    assert_eq!(o.code, 1);
    assert!(
        o.stderr
            .contains("::error::secret-scan: gitleaks found a candidate secret"),
        "{}",
        o.all()
    );
}

#[test]
fn a_system_gitleaks_off_the_pin_is_refused() {
    let r = repo("8.29.0", 0);
    let o = scan(&r, &[]);
    assert_eq!(o.code, 1);
    let pinned = pin("GITLEAKS_VERSION");
    assert!(
        o.stderr.contains(&format!("not the pinned v{pinned}")),
        "{}",
        o.all()
    );
    assert!(
        o.stderr.contains("'8.29.0'"),
        "names the version it found: {}",
        o.all()
    );
    assert!(scans(&r).is_empty(), "refused before scanning");
    assert!(!o.all().contains("no secrets found"));
}

#[test]
fn a_system_gitleaks_on_the_pin_is_accepted_and_scans() {
    let r = repo(&pin("GITLEAKS_VERSION"), 0);
    let o = scan(&r, &[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert!(o
        .stdout
        .contains("secret-scan: no secrets found in the added commits."));
}

// --- the range each base resolves to -------------------------------------------

#[test]
fn no_base_scans_the_working_tree() {
    let r = repo(&pin("GITLEAKS_VERSION"), 0);
    let o = scan(&r, &[]);
    assert!(o.stdout.contains("no diff base resolved"), "{}", o.stdout);
    assert_eq!(
        scans(&r),
        vec![format!(
            "{}|dir --no-banner --redact --config .gitleaks.toml .",
            r.root.display()
        )]
    );
}

#[test]
fn base_rev_scans_base_rev_to_head() {
    let r = repo(&pin("GITLEAKS_VERSION"), 0);
    let base = git(&r.root, &["rev-parse", "HEAD~1"]);
    let o = scan(&r, &[("BASE_REV", &base)]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert!(o
        .stdout
        .contains(&format!("scanning commits in {base}..HEAD")));
    assert_eq!(
        scans(&r),
        vec![format!(
            "{}|git --no-banner --redact --config .gitleaks.toml --log-opts={base}..HEAD .",
            r.root.display()
        )]
    );
}

#[test]
fn base_ref_scans_from_the_merge_base() {
    let r = repo(&pin("GITLEAKS_VERSION"), 0);
    let base = git(&r.root, &["rev-parse", "HEAD"]);
    git(&r.root, &["update-ref", "refs/remotes/origin/main", &base]);
    commit_file(&r.root, "new.txt", "added\n", "the change");
    let o = scan(&r, &[("BASE_REF", "main")]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert!(
        scans(&r)[0].ends_with(&format!("--log-opts={base}..HEAD .")),
        "{:?}",
        scans(&r)
    );
}

#[test]
fn unresolvable_base_rev_falls_through_to_base_ref() {
    // A push's `before` is all zeros on a new branch. The script's
    // `if BASE_REV && it resolves ... elif BASE_REF` then used BASE_REF.
    let r = repo(&pin("GITLEAKS_VERSION"), 0);
    let base = git(&r.root, &["rev-parse", "HEAD"]);
    git(&r.root, &["update-ref", "refs/remotes/origin/main", &base]);
    commit_file(&r.root, "new.txt", "added\n", "the change");
    let o = scan(
        &r,
        &[
            ("BASE_REV", "0000000000000000000000000000000000000000"),
            ("BASE_REF", "main"),
        ],
    );
    assert_eq!(o.code, 0, "{}", o.all());
    assert!(
        scans(&r)[0].contains(&format!("--log-opts={base}..HEAD")),
        "{:?}",
        scans(&r)
    );
}

#[test]
fn unresolvable_bases_fail_safe_to_the_working_tree() {
    let r = repo(&pin("GITLEAKS_VERSION"), 0);
    let o = scan(
        &r,
        &[("BASE_REV", "deadbeef"), ("BASE_REF", "no-such-branch")],
    );
    assert_eq!(o.code, 0, "{}", o.all());
    assert!(scans(&r)[0].contains("|dir "), "{:?}", scans(&r));
}

#[test]
fn scans_from_the_repo_root_whatever_the_cwd() {
    let r = repo(&pin("GITLEAKS_VERSION"), 0);
    std::fs::create_dir_all(r.root.join("sub/dir")).unwrap();
    let o = scan_in(&r, &r.root.join("sub/dir"), &[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert!(scans(&r)[0].starts_with(&format!("{}|", r.root.display())));
}

// --- parity with the retired script ------------------------------------------

#[test]
fn version_whitespace_is_ignored_like_tr_d_space() {
    let r = repo(&format!(" {}\t ", pin("GITLEAKS_VERSION")), 0);
    let o = scan(&r, &[]);
    assert_eq!(
        o.code,
        0,
        "tr -d '[:space:]' strips every blank: {}",
        o.all()
    );
}

#[test]
fn outside_a_git_repo_exits_with_gits_status() {
    let r = repo(&pin("GITLEAKS_VERSION"), 0);
    let not_repo = r._dir.join("not-a-repo");
    std::fs::create_dir_all(&not_repo).unwrap();
    let o = Run::new(&bin("BIN"))
        .cwd(&not_repo)
        .path_first(&r.fakes)
        .env("GIT_CEILING_DIRECTORIES", r._dir.path())
        .env("USE_SYSTEM_GITLEAKS", "1")
        .go_within(std::time::Duration::from_secs(60))
        .unwrap();
    assert_eq!(
        o.code,
        128,
        "set -e on `git rev-parse --show-toplevel`: {}",
        o.all()
    );
    assert!(
        o.stderr.contains("not a git repository"),
        "git's own message: {}",
        o.stderr
    );
    assert!(scans(&r).is_empty());
}

/// The download path: no system gitleaks requested, a fake curl serving
/// `body` (or failing with `curl_rc`). The stub gitleaks on PATH must never run.
fn download(body: &str, curl_rc: i32) -> (Output, Repo, PathBuf) {
    let r = repo(&pin("GITLEAKS_VERSION"), 0);
    let curl_log = r._dir.join("curl.log");
    write_exe(
        r.fakes.join("curl"),
        format!(
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> '{log}'\n[ {curl_rc} -eq 0 ] || exit {curl_rc}\nout=''\nwhile [ $# -gt 0 ]; do [ \"$1\" = -o ] && out=\"$2\"; shift; done\nprintf '%s' '{body}' > \"$out\"\n",
            log = curl_log.display()
        ),
    );
    let o = Run::new(&bin("BIN"))
        .cwd(&r.root)
        .env(
            "PATH",
            format!(
                "{}:{}:/sbin:/usr/sbin",
                r.fakes.display(),
                std::env::var("PATH").unwrap_or_default()
            ),
        )
        .env_remove("USE_SYSTEM_GITLEAKS")
        .env("BASE_REV", "")
        .env("BASE_REF", "")
        .go_within(std::time::Duration::from_secs(60))
        .unwrap();
    (o, r, curl_log)
}

#[test]
fn a_download_that_fails_its_checksum_is_refused() {
    let (o, r, curl_log) = download("not the gitleaks tarball", 0);
    let log = read(&curl_log);
    assert_eq!(o.code, 1, "{}", o.all());
    assert!(
        o.stderr.contains(&format!(
            "::error::gitleaks checksum mismatch \u{2014} expected {}",
            pin("GITLEAKS_SHA256")
        )),
        "{}",
        o.stderr
    );
    assert!(
        scans(&r).is_empty(),
        "nothing scans with an unverified binary"
    );
    assert!(!o.all().contains("no secrets found"));
    let v = pin("GITLEAKS_VERSION");
    assert_eq!(
        log.trim_end(),
        format!(
            "-fsSL --retry 5 --retry-delay 2 --retry-all-errors --max-time 120 -o {}/gitleaks.tar.gz \
             https://github.com/gitleaks/gitleaks/releases/download/v{v}/gitleaks_{v}_linux_x64.tar.gz",
            curl_args_dir(&log)
        ),
        "the pinned linux_x64 release, fetched with the script's curl flags"
    );
}

/// The temp dir curl was told to write into (random per run).
fn curl_args_dir(log: &str) -> String {
    let after = log.split(" -o ").nth(1).expect("curl -o <file>");
    let file = after.split(' ').next().unwrap();
    file.trim_end_matches("/gitleaks.tar.gz").to_string()
}

#[test]
fn a_failed_download_exits_with_curls_status() {
    let (o, r, _) = download("", 22);
    assert_eq!(o.code, 22, "set -e on curl: {}", o.all());
    assert!(scans(&r).is_empty());
}

#[test]
fn use_system_gitleaks_without_one_on_path_downloads() {
    // The escape hatch needs a gitleaks on PATH; without one the script took
    // the pinned download, which then must verify.
    let r = repo(&pin("GITLEAKS_VERSION"), 0);
    std::fs::remove_file(r.fakes.join("gitleaks")).unwrap();
    write_exe(r.fakes.join("curl"), "#!/usr/bin/env bash\nexit 7\n");
    let o = Run::new(&bin("BIN"))
        .cwd(&r.root)
        .env("PATH", format!("{}:/usr/bin:/bin", r.fakes.display()))
        .env("USE_SYSTEM_GITLEAKS", "1")
        .go_within(std::time::Duration::from_secs(60))
        .unwrap();
    assert!(o.stdout.contains("fetching gitleaks"), "{}", o.all());
    assert_eq!(o.code, 7);
}

#[test]
fn the_pin_matches_tools_lock_json() {
    // //tools/secret-scan (local scans, //tools/git:commit) runs the
    // @multitool gitleaks from tools/tools.lock.json; CI downloads this pin.
    // The two must be the same binary.
    let lock = read(std::env::var("LOCK").expect("LOCK"));
    let v = pin("GITLEAKS_VERSION");
    let url = format!(
        "\"url\": \"https://github.com/gitleaks/gitleaks/releases/download/v{v}/gitleaks_{v}_linux_x64.tar.gz\""
    );
    let at = lock
        .find(&url)
        .unwrap_or_else(|| panic!("tools/tools.lock.json has no gitleaks v{v} linux_x64 entry"));
    let sha_line = lock[at..].lines().nth(1).unwrap_or("");
    assert_eq!(
        sha_line.trim(),
        format!("\"sha256\": \"{}\"", pin("GITLEAKS_SHA256")),
        "the lock's checksum for that tarball"
    );
}
