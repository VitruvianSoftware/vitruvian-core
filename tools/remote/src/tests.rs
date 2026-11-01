// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Hermetic tests for //tools/remote:setup, driving the real binary.
//!
//! The headline case is a real bug: header lines written under BOTH
//! common:remote and common:remotecache COMMA-JOINED into "KEY,KEY" when a
//! dev ran the documented `--config=remote` on a machine with the remotecache
//! local default (--remote_header repeats are joined, not deduped). The
//! invariant: across every scope, the auth header expands EXACTLY ONCE for
//! any config combination (t1).
//!
//! t1..t5 are the shell suite (setup_test.sh) ported. The `parity_*` tests
//! run the former shell implementation (setup.sh, still on disk because
//! cloud-bootstrap runs it at session start) as an oracle over a matrix of
//! scenarios and require the same stdout, stderr, exit code and files.

use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

static N: AtomicUsize = AtomicUsize::new(0);

fn abs(var: &str) -> PathBuf {
    let p = std::env::var(var).unwrap_or_else(|_| panic!("{var} not set"));
    fs::canonicalize(&p).unwrap_or_else(|e| panic!("{var}={p}: {e}"))
}

fn bin() -> PathBuf {
    abs("BIN")
}

fn shell() -> PathBuf {
    abs("SETUP_SH")
}

/// A fresh directory: `<tmp>/<n>/` with `ws/` (the workspace) and `home/`.
fn scratch() -> PathBuf {
    let base =
        std::env::var("TEST_TMPDIR").unwrap_or_else(|_| std::env::temp_dir().display().to_string());
    let d = PathBuf::from(base).join(format!(
        "setup-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = fs::remove_dir_all(&d);
    fs::create_dir_all(d.join("ws")).unwrap();
    fs::create_dir_all(d.join("home")).unwrap();
    fs::create_dir_all(d.join("fakebin")).unwrap();
    fs::canonicalize(d).unwrap()
}

struct Out {
    code: i32,
    stdout: String,
    stderr: String,
}

/// Run `prog` (the binary, or `bash setup.sh` when `sh`) against `root/ws`.
fn run(root: &Path, sh: bool, args: &[&str], env: &[(&str, &str)], stdin: &str) -> Out {
    let mut c = if sh {
        let mut c = Command::new("bash");
        c.arg(shell());
        c
    } else {
        Command::new(bin())
    };
    let path = format!(
        "{}:{}",
        root.join("fakebin").display(),
        std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".into())
    );
    c.args(args)
        .env_clear()
        .env("PATH", path)
        .env("HOME", root.join("home"))
        .env("BUILD_WORKSPACE_DIRECTORY", root.join("ws"))
        .current_dir(root)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for (k, v) in env {
        if v.is_empty() && *k == "BUILD_WORKSPACE_DIRECTORY" {
            c.env_remove(k);
        } else {
            c.env(k, v);
        }
    }
    let mut child = c.spawn().expect("spawn");
    child.stdin.take().unwrap().write_all(stdin.as_bytes()).ok();
    let o = child.wait_with_output().unwrap();
    let norm = |b: &[u8]| String::from_utf8_lossy(b).replace(&root.display().to_string(), "<ROOT>");
    Out {
        code: o.status.code().unwrap_or(-1),
        stdout: norm(&o.stdout),
        stderr: norm(&o.stderr),
    }
}

fn read(p: PathBuf) -> String {
    fs::read_to_string(&p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))
}

/// Total header lines that could apply to ANY invocation: unscoped `common`
/// plus any config-scoped variant. The doubling bug shows up as >1.
fn header_expansions(ws: &Path) -> usize {
    read(ws.join("user.bazelrc"))
        .lines()
        .filter(|l| {
            let Some(rest) = l.strip_prefix("common") else {
                return false;
            };
            let rest = match rest.strip_prefix(':') {
                Some(r) => match r.find(' ') {
                    Some(i) if r[..i].chars().all(|c| c.is_ascii_lowercase() || c == '-') => {
                        &r[i..]
                    }
                    _ => return false,
                },
                None => rest,
            };
            rest.starts_with(" --remote_header=x-buildbuddy-api-key=")
        })
        .count()
}

const BB: &[&str] = &[
    "--cache",
    "buildbuddy",
    "--provider",
    "buildbuddy",
    "--no-ci",
    "--yes",
];

fn bb(root: &Path, key: &str, extra: &[&str]) -> Out {
    let mut a: Vec<&str> = BB.to_vec();
    a.extend_from_slice(&["--key", key]);
    a.extend_from_slice(extra);
    let o = run(root, false, &a, &[], "");
    assert_eq!(o.code, 0, "setup failed: {}{}", o.stdout, o.stderr);
    o
}

// --- the shell suite, ported ---------------------------------------------

#[test]
fn t1_fresh_setup_writes_exactly_one_unscoped_header() {
    let r = scratch();
    let ws = r.join("ws");
    bb(&r, "TESTKEY", &[]);
    assert_eq!(
        header_expansions(&ws),
        1,
        "the auth header must expand exactly once:\n{}",
        read(ws.join("user.bazelrc"))
    );
    let rc = read(ws.join("user.bazelrc"));
    assert!(
        rc.lines()
            .any(|l| l == "common --remote_header=x-buildbuddy-api-key=TESTKEY"),
        "header line must be UNSCOPED (plain 'common'):\n{rc}"
    );
    assert!(
        rc.lines().any(|l| l == "common --config=remotecache"),
        "local default line missing:\n{rc}"
    );
}

#[test]
fn t2_rerun_rotates_the_key_without_duplicating() {
    let r = scratch();
    let ws = r.join("ws");
    bb(&r, "TESTKEY", &[]);
    bb(&r, "ROTATED", &[]);
    let rc = read(ws.join("user.bazelrc"));
    assert_eq!(
        header_expansions(&ws),
        1,
        "re-run duplicated header lines:\n{rc}"
    );
    assert!(rc.contains("ROTATED"), "rotated key not written");
    assert!(!rc.contains("TESTKEY"), "old key survived rotation:\n{rc}");
    assert_eq!(
        rc.matches(">>> build cache").count(),
        1,
        "managed block duplicated:\n{rc}"
    );
}

#[test]
fn t3_legacy_scoped_headers_are_cleaned_up() {
    let r = scratch();
    let ws = r.join("ws");
    bb(&r, "TESTKEY", &[]);
    let mut f = fs::OpenOptions::new()
        .append(true)
        .open(ws.join("user.bazelrc"))
        .unwrap();
    f.write_all(
        b"common:remote --remote_header=x-buildbuddy-api-key=LEGACY\ncommon:remotecache --remote_header=x-buildbuddy-api-key=LEGACY\n",
    )
    .unwrap();
    bb(&r, "TESTKEY", &[]);
    assert_eq!(
        header_expansions(&ws),
        1,
        "legacy scoped headers not cleaned:\n{}",
        read(ws.join("user.bazelrc"))
    );
    assert!(!read(ws.join("user.bazelrc")).contains("LEGACY"));
}

#[test]
fn t4_no_local_default_omits_the_default_and_keeps_one_header() {
    let r = scratch();
    let ws = r.join("ws");
    bb(&r, "TESTKEY", &[]);
    let o = bb(&r, "TESTKEY", &["--no-local-default"]);
    let rc = read(ws.join("user.bazelrc"));
    assert!(
        !rc.lines().any(|l| l == "common --config=remotecache"),
        "--no-local-default still wrote the default line:\n{rc}"
    );
    assert_eq!(
        header_expansions(&ws),
        1,
        "no-local-default broke header count"
    );
    assert!(o
        .stdout
        .contains("Local default skipped (--no-local-default)"));
}

#[test]
fn t5_no_clobber_guard_leaves_a_committed_remote_bazelrc_alone() {
    let r = scratch();
    let ws = r.join("ws");
    fs::create_dir_all(ws.join("tools")).unwrap();
    fs::write(
        ws.join("tools/remote.bazelrc"),
        "SENTINEL\ncommon:remote --remote_executor=grpcs://remote.buildbuddy.io\n",
    )
    .unwrap();
    let o = bb(&r, "TESTKEY", &[]);
    assert!(
        read(ws.join("tools/remote.bazelrc")).starts_with("SENTINEL\n"),
        "setup clobbered a committed remote.bazelrc with the same endpoint"
    );
    assert!(o.stdout.contains(
        "✓ tools/remote.bazelrc already targets grpcs://remote.buildbuddy.io (left untouched)."
    ));
}

// --- beyond the shell suite ----------------------------------------------

#[test]
fn a_run_never_rewrites_this_repos_committed_remote_bazelrc() {
    // The committed file has grown past the template (remotecache-ci and its
    // notes), so a rewrite would silently downgrade CI's RBE config. The
    // no-clobber guard must recognise the real file, byte for byte.
    let committed = read(abs("COMMITTED_REMOTE_BAZELRC"));
    let r = scratch();
    fs::create_dir_all(r.join("ws/tools")).unwrap();
    fs::write(r.join("ws/tools/remote.bazelrc"), &committed).unwrap();
    let o = bb(&r, "TESTKEY", &[]);
    assert_eq!(read(r.join("ws/tools/remote.bazelrc")), committed);
    assert!(o.stdout.contains("(left untouched)"), "{}", o.stdout);
}

#[test]
fn the_key_comes_from_the_environment_when_not_given() {
    let r = scratch();
    let o = run(
        &r,
        false,
        &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--no-ci",
        ],
        &[("BUILDBUDDY_API_KEY", "ENVKEY")],
        "",
    );
    assert_eq!(o.code, 0, "{}", o.stderr);
    assert!(read(r.join("ws/user.bazelrc"))
        .contains("common --remote_header=x-buildbuddy-api-key=ENVKEY\n"));
}

#[test]
fn no_key_at_all_exits_2() {
    let r = scratch();
    let o = run(
        &r,
        false,
        &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--no-ci",
        ],
        &[],
        "",
    );
    assert_eq!(o.code, 2);
    assert_eq!(o.stderr, "No API key provided.\n");
}

#[test]
fn unknown_argument_exits_2_with_usage() {
    let r = scratch();
    let o = run(&r, false, &["--bogus"], &[], "");
    assert_eq!(o.code, 2);
    assert_eq!(o.stderr, "unknown argument: --bogus\n");
    assert!(o
        .stdout
        .starts_with("Usage: bazel run //tools/remote:setup -- [flags]\n"));
}

#[test]
fn a_flag_without_its_value_exits_1() {
    let r = scratch();
    let o = run(&r, false, &["--cache"], &[], "");
    assert_eq!(o.code, 1);
    assert!(
        o.stderr.contains("2: parameter null or not set"),
        "{}",
        o.stderr
    );
}

#[test]
fn cache_none_removes_the_managed_block_only() {
    let r = scratch();
    let ws = r.join("ws");
    fs::write(ws.join("user.bazelrc"), "common --jobs=8\n").unwrap();
    bb(&r, "TESTKEY", &[]);
    let o = run(&r, false, &["--cache", "none"], &[], "");
    assert_eq!(o.code, 0);
    let rc = read(ws.join("user.bazelrc"));
    assert!(!rc.contains("build cache"), "{rc}");
    assert!(rc.contains("common --jobs=8"), "{rc}");
    // The header lines live inside the block, so the key goes with it.
    assert!(!rc.contains("TESTKEY"), "{rc}");
}

#[test]
fn cache_local_writes_a_disk_cache_under_home() {
    let r = scratch();
    let ws = r.join("ws");
    fs::write(ws.join(".gitignore"), "bazel-*\n").unwrap();
    let o = run(&r, false, &["--cache", "local"], &[], "");
    assert_eq!(o.code, 0, "{}", o.stderr);
    let dir = r.join("home/.cache/ws-bazel-disk");
    assert!(dir.is_dir());
    assert!(
        read(ws.join("user.bazelrc")).contains(&format!("common --disk_cache={}\n", dir.display()))
    );
    assert_eq!(read(ws.join(".gitignore")), "bazel-*\nuser.bazelrc\n");
    assert!(o.stdout.contains("✓ Added user.bazelrc to .gitignore."));
}

#[test]
fn cache_shared_is_read_only_with_an_optional_header() {
    let r = scratch();
    let ws = r.join("ws");
    let o = run(
        &r,
        false,
        &[
            "--cache",
            "shared",
            "--url",
            "grpcs://c.example",
            "--key",
            "K",
        ],
        &[],
        "",
    );
    assert_eq!(o.code, 0, "{}", o.stderr);
    let rc = read(ws.join("user.bazelrc"));
    assert!(rc.contains("common --remote_cache=grpcs://c.example\ncommon --remote_upload_local_results=false\ncommon --remote_header=x-api-key=K\n"), "{rc}");
    // Blank key on the prompt: no header at all.
    let o = run(
        &r,
        false,
        &["--cache", "shared", "--url", "grpcs://c.example"],
        &[],
        "\n",
    );
    assert_eq!(o.code, 0);
    assert!(!read(ws.join("user.bazelrc")).contains("remote_header"));
    // No URL and nothing on stdin: `read` fails under set -e.
    let o = run(&r, false, &["--cache", "shared"], &[], "");
    assert_eq!(o.code, 1);
}

#[test]
fn the_ci_secret_travels_on_stdin_never_argv() {
    let r = scratch();
    let log = r.join("gh.log");
    fake_gh(&r, true, true);
    let o = run(
        &r,
        false,
        &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--key",
            "SEKRETKEY",
        ],
        &[],
        "",
    );
    assert_eq!(o.code, 0, "{}", o.stderr);
    let l = read(log);
    assert!(l.contains("argv: secret set BUILDBUDDY_API_KEY\n"), "{l}");
    assert!(l.contains("stdin: SEKRETKEY\n"), "{l}");
    assert!(
        !l.contains("argv: secret set BUILDBUDDY_API_KEY SEKRETKEY"),
        "{l}"
    );
    assert!(o
        .stdout
        .contains("✓ Set the GitHub Actions secret BUILDBUDDY_API_KEY on this repo."));
    assert!(
        !o.stdout.contains("SEKRETKEY"),
        "the key was printed:\n{}",
        o.stdout
    );
}

#[test]
fn the_git_toplevel_is_used_without_build_workspace_directory() {
    if Command::new("git").arg("--version").output().is_err() {
        eprintln!("SKIP: no git");
        return;
    }
    let r = scratch();
    let ws = r.join("ws");
    assert!(Command::new("git")
        .args(["init", "-q"])
        .current_dir(&ws)
        .status()
        .unwrap()
        .success());
    fs::create_dir_all(ws.join("sub/dir")).unwrap();
    let mut c = Command::new(bin());
    c.args(BB)
        .args(["--key", "K"])
        .env_remove("BUILD_WORKSPACE_DIRECTORY")
        .env("HOME", r.join("home"))
        .current_dir(ws.join("sub/dir"))
        .stdin(Stdio::null())
        .stdout(Stdio::null());
    assert!(c.status().unwrap().success());
    assert!(ws.join("user.bazelrc").is_file());
    assert!(!ws.join("sub/dir/user.bazelrc").exists());
}

// --- parity with the shell implementation --------------------------------

/// `gh` that logs argv and stdin; `auth status` and `secret set` succeed or
/// fail as told.
fn fake_gh(r: &Path, authed: bool, set_ok: bool) {
    let p = r.join("fakebin/gh");
    fs::write(
        &p,
        format!(
            "#!/bin/sh\nlog='{}'\nif [ \"$1\" = auth ]; then exit {}; fi\nprintf 'argv: %s\\n' \"$*\" >>\"$log\"\nprintf 'stdin: %s\\n' \"$(cat)\" >>\"$log\"\nexit {}\n",
            r.join("gh.log").display(),
            if authed { 0 } else { 1 },
            if set_ok { 0 } else { 1 }
        ),
    )
    .unwrap();
    fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
}

struct Case {
    name: &'static str,
    args: &'static [&'static str],
    env: &'static [(&'static str, &'static str)],
    stdin: &'static str,
    /// Prepare the scratch tree (identically for both runs).
    prep: fn(&Path),
}

fn nothing(_: &Path) {}

fn prior_state(r: &Path) {
    let ws = r.join("ws");
    // An old managed block, legacy scoped headers, unrelated lines, a header
    // for another name, and no final newline.
    fs::write(
        ws.join("user.bazelrc"),
        "common --jobs=8\n# >>> build cache (managed by tools/remote:setup) — do not edit by hand\ncommon --disk_cache=/x\n# <<< build cache (managed by tools/remote:setup)\ncommon:remote --remote_header=x-buildbuddy-api-key=OLD\ncommon:remotecache --bes_header=x-buildbuddy-api-key=OLD\ncommon --remote_header=other=keep\nbuild --config=mine",
    )
    .unwrap();
    fs::write(ws.join(".gitignore"), "bazel-*").unwrap();
}

fn unterminated_block(r: &Path) {
    fs::write(
        r.join("ws/user.bazelrc"),
        "a\n# >>> build cache (managed by tools/remote:setup) — do not edit by hand\nb\nc\n",
    )
    .unwrap();
}

fn committed_other_endpoint(r: &Path) {
    fs::create_dir_all(r.join("ws/tools")).unwrap();
    fs::write(
        r.join("ws/tools/remote.bazelrc"),
        "common:remote --remote_executor=grpcs://elsewhere\n",
    )
    .unwrap();
}

fn committed_same_endpoint(r: &Path) {
    fs::create_dir_all(r.join("ws/tools")).unwrap();
    fs::write(
        r.join("ws/tools/remote.bazelrc"),
        "X\ncommon:remote --remote_executor=grpcs://rbe.example\n",
    )
    .unwrap();
}

fn ci_gh_ok(r: &Path) {
    fake_gh(r, true, true);
    workflows(r);
}
fn ci_gh_set_fails(r: &Path) {
    fake_gh(r, true, false);
    workflows(r);
}
fn ci_gh_unauthed(r: &Path) {
    fake_gh(r, false, true);
}
fn workflows(r: &Path) {
    let w = r.join("ws/.github/workflows");
    fs::create_dir_all(w.join("nested")).unwrap();
    fs::write(w.join("ci.yaml"), "run: bazel test //...\n").unwrap();
    fs::write(w.join("nested/x.yaml"), "run: bazel build //x\n").unwrap();
    fs::write(w.join("other.yaml"), "run: echo hi\n").unwrap();
}

const CASES: &[Case] = &[
    Case {
        name: "buildbuddy fresh",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--key",
            "K1",
            "--no-ci",
            "--yes",
        ],
        env: &[],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "buildbuddy over prior state",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--key",
            "K1",
            "--no-ci",
        ],
        env: &[],
        stdin: "",
        prep: prior_state,
    },
    Case {
        name: "no local default",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--key",
            "K1",
            "--no-ci",
            "--no-local-default",
        ],
        env: &[],
        stdin: "",
        prep: prior_state,
    },
    Case {
        name: "provider implies buildbuddy",
        args: &["--provider", "buildbuddy", "--key", "K1", "--no-ci"],
        env: &[],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "endpoint implies buildbuddy, custom via prompt",
        args: &[
            "--endpoint",
            "grpcs://rbe.example",
            "--key",
            "K1",
            "--no-ci",
        ],
        env: &[],
        stdin: "custom\nhdr-name\n",
        prep: nothing,
    },
    Case {
        name: "custom provider by flags",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "custom",
            "--endpoint",
            "grpcs://rbe.example",
            "--header-name",
            "x-k",
            "--key",
            "K1",
            "--no-ci",
        ],
        env: &[],
        stdin: "",
        prep: committed_other_endpoint,
    },
    Case {
        name: "custom provider, committed same endpoint",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "custom",
            "--endpoint",
            "grpcs://rbe.example",
            "--header-name",
            "x-k",
            "--key",
            "K1",
            "--no-ci",
        ],
        env: &[],
        stdin: "",
        prep: committed_same_endpoint,
    },
    Case {
        name: "custom provider, prompts",
        args: &["--cache", "buildbuddy", "--provider", "custom", "--no-ci"],
        env: &[],
        stdin: "  grpcs://rbe.example  \nx-k\nPROMPTKEY\n",
        prep: nothing,
    },
    Case {
        name: "custom provider, endpoint EOF",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "custom",
            "--key",
            "K",
        ],
        env: &[],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "custom provider, header EOF",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "custom",
            "--key",
            "K",
        ],
        env: &[],
        stdin: "grpcs://e\n",
        prep: nothing,
    },
    Case {
        name: "custom provider, blank endpoint",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "custom",
            "--key",
            "K",
        ],
        env: &[],
        stdin: "\nh\n",
        prep: nothing,
    },
    Case {
        name: "unknown provider",
        args: &["--provider", "nope", "--key", "K"],
        env: &[],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "key from env",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--no-ci",
        ],
        env: &[("BUILDBUDDY_API_KEY", "ENVKEY")],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "key from prompt",
        args: &["--cache", "buildbuddy", "--no-ci"],
        env: &[],
        stdin: "\nTYPEDKEY\n",
        prep: nothing,
    },
    Case {
        name: "no key",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--no-ci",
        ],
        env: &[],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "menu none (EOF)",
        args: &[],
        env: &[],
        stdin: "",
        prep: prior_state,
    },
    Case {
        name: "menu local",
        args: &[],
        env: &[],
        stdin: "2\n",
        prep: prior_state,
    },
    Case {
        name: "menu shared",
        args: &[],
        env: &[],
        stdin: "3\ngrpcs://c.example\nAUTH\n",
        prep: nothing,
    },
    Case {
        name: "menu buildbuddy",
        args: &["--no-ci"],
        env: &[("BUILDBUDDY_API_KEY", "ENVKEY")],
        stdin: "4\n\n",
        prep: nothing,
    },
    Case {
        name: "menu invalid",
        args: &[],
        env: &[],
        stdin: "9\n",
        prep: nothing,
    },
    Case {
        name: "cache none",
        args: &["--cache", "none"],
        env: &[],
        stdin: "",
        prep: prior_state,
    },
    Case {
        name: "cache none, unterminated block",
        args: &["--cache", "none"],
        env: &[],
        stdin: "",
        prep: unterminated_block,
    },
    Case {
        name: "cache none, no user.bazelrc",
        args: &["--cache", "none"],
        env: &[],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "cache local",
        args: &["--cache", "local"],
        env: &[],
        stdin: "",
        prep: prior_state,
    },
    Case {
        name: "cache shared with key",
        args: &[
            "--cache",
            "shared",
            "--url",
            "grpcs://c.example",
            "--key",
            "K",
            "--header-name",
            "h",
        ],
        env: &[],
        stdin: "",
        prep: prior_state,
    },
    Case {
        name: "cache shared, prompts",
        args: &["--cache", "shared"],
        env: &[],
        stdin: "grpcs://c.example\n\n",
        prep: nothing,
    },
    Case {
        name: "cache shared, URL EOF",
        args: &["--cache", "shared"],
        env: &[],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "cache shared, blank URL",
        args: &["--cache", "shared"],
        env: &[],
        stdin: "\n",
        prep: nothing,
    },
    Case {
        name: "unknown cache",
        args: &["--cache", "nope"],
        env: &[],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "unknown argument",
        args: &["--cache", "none", "--what"],
        env: &[],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "help",
        args: &["-h"],
        env: &[],
        stdin: "",
        prep: nothing,
    },
    Case {
        name: "CI, gh sets the secret",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--key",
            "K1",
        ],
        env: &[],
        stdin: "",
        prep: ci_gh_ok,
    },
    Case {
        name: "CI, gh refuses",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--key",
            "K1",
        ],
        env: &[],
        stdin: "",
        prep: ci_gh_set_fails,
    },
    Case {
        name: "CI, gh not authenticated",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--key",
            "K1",
        ],
        env: &[],
        stdin: "",
        prep: ci_gh_unauthed,
    },
    Case {
        name: "CI, no gh",
        args: &[
            "--cache",
            "buildbuddy",
            "--provider",
            "buildbuddy",
            "--key",
            "K1",
        ],
        env: &[],
        stdin: "",
        prep: nothing,
    },
];

/// Every file under `ws` (and the gh log), as `path: content`.
fn tree(r: &Path) -> Vec<String> {
    fn walk(base: &Path, d: &Path, out: &mut Vec<String>) {
        let Ok(rd) = fs::read_dir(d) else { return };
        for e in rd.flatten() {
            let p = e.path();
            if p.is_dir() {
                out.push(format!("{}/", p.strip_prefix(base).unwrap().display()));
                walk(base, &p, out);
            } else {
                out.push(format!(
                    "{}: {:?}",
                    p.strip_prefix(base).unwrap().display(),
                    String::from_utf8_lossy(&fs::read(&p).unwrap())
                ));
            }
        }
    }
    let mut v = Vec::new();
    walk(r, &r.join("ws"), &mut v);
    walk(r, &r.join("home"), &mut v);
    if let Ok(l) = fs::read_to_string(r.join("gh.log")) {
        v.push(format!("gh.log: {l:?}"));
    }
    v.sort();
    v.into_iter()
        .map(|s| s.replace(&r.display().to_string(), "<ROOT>"))
        .collect()
}

#[test]
fn parity_with_setup_sh() {
    let mut bad = Vec::new();
    for c in CASES {
        let rs = scratch();
        let sh = scratch();
        (c.prep)(&rs);
        (c.prep)(&sh);
        let a = run(&rs, false, c.args, c.env, c.stdin);
        let b = run(&sh, true, c.args, c.env, c.stdin);
        let (ta, tb) = (tree(&rs), tree(&sh));
        if a.code != b.code || a.stdout != b.stdout || a.stderr != b.stderr || ta != tb {
            bad.push(format!(
                "case '{}':\n  exit rust={} sh={}\n  --- rust stdout\n{}\n  --- sh stdout\n{}\n  --- rust stderr\n{}\n  --- sh stderr\n{}\n  --- rust files\n{}\n  --- sh files\n{}",
                c.name, a.code, b.code, a.stdout, b.stdout, a.stderr, b.stderr, ta.join("\n"), tb.join("\n")
            ));
        }
    }
    assert!(
        bad.is_empty(),
        "{} case(s) differ from setup.sh:\n\n{}",
        bad.len(),
        bad.join("\n\n")
    );
}
