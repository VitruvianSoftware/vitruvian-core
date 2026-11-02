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

//! //tools/ci:install_pinned_tool_test. Runs the REAL binary with a fake
//! `curl` first on PATH (it copies fixtures, no network) and the real `tar`,
//! `install` and `sha256sum`, so both install paths and the checksum check
//! run for real. Each world writes its own tools.lock.json, in the real
//! lock's format, pinning the fixtures' true hashes.
//!
//! The expected hash comes only from the lock (#4183): a version the lock does
//! not pin is refused before anything is downloaded, and a download whose
//! hash differs from the lock's is not installed. The last test runs every
//! install-pinned-tool step in .github/ against the real tools/tools.lock.json.

use ci_testkit::{bin, read, write, write_exe, Output, Run, TempDir};
use std::path::{Path, PathBuf};
use std::process::Command;

const URL: &str = "https://example.invalid/download";
const RAW: &str = "mytool_linux_amd64";
const TGZ: &str = "mytool_linux_amd64.tar.gz";
const PROM: &str = "prometheus-2.45.0.linux-amd64.tar.gz";
const PROM_MEMBER: &str = "prometheus-2.45.0.linux-amd64/promtool";

/// The fake curl: `curl ... -O <url>` copies `$FIXTURES_DIR/<basename>` into
/// the working directory, as real curl's -O names the file.
const FAKE_CURL: &str = r#"#!/usr/bin/env bash
if [ -n "${FAKE_CURL_ARGS_LOG:-}" ]; then printf '%s\n' "$*" >> "${FAKE_CURL_ARGS_LOG}"; fi
if [ -n "${FAKE_CURL_RC:-}" ] && [ "${FAKE_CURL_RC}" != "0" ]; then
  echo "curl: fake transport failure" >&2
  exit "${FAKE_CURL_RC}"
fi
url="${@: -1}"
base="${url##*/}"
if [ ! -f "${FIXTURES_DIR}/${base}" ]; then
  echo "curl: no fixture for '${base}'" >&2
  exit 22
fi
cp "${FIXTURES_DIR}/${base}" "./${base}"
"#;

struct World {
    dir: TempDir,
}

/// One lock entry: (tool, kind, file-in-archive, asset, sha256).
struct Pin<'a> {
    tool: &'a str,
    kind: &'a str,
    file: Option<&'a str>,
    asset: &'a str,
    sha256: String,
}

impl World {
    fn new() -> World {
        let dir = TempDir::new();
        write_exe(dir.join("bin/curl"), FAKE_CURL);
        let fx = dir.join("fixtures");
        // --raw: the asset IS the binary.
        write(fx.join(RAW), "fake-binary-bytes-for-mytool\n");
        // --tar: a top-level member named after the tool.
        let stage = dir.join("stage");
        write_exe(stage.join("mytool"), "#!/bin/sh\necho fake-tar-tool\n");
        tar_into(&stage, &["mytool"], &fx.join(TGZ));
        // --tar with the binary in a directory, as prometheus ships promtool.
        let nested = dir.join("nested");
        write_exe(nested.join(PROM_MEMBER), "#!/bin/sh\necho fake-promtool\n");
        write(
            nested.join("prometheus-2.45.0.linux-amd64/prometheus"),
            "server\n",
        );
        tar_into(&nested, &["prometheus-2.45.0.linux-amd64"], &fx.join(PROM));
        let w = World { dir };
        w.write_lock(&w.true_pins());
        w
    }

    fn fixtures(&self) -> PathBuf {
        self.dir.join("fixtures")
    }

    fn lock(&self) -> PathBuf {
        self.dir.join("tools.lock.json")
    }

    /// The fixtures pinned at their real hashes.
    fn true_pins(&self) -> Vec<Pin<'static>> {
        let fx = self.fixtures();
        vec![
            Pin {
                tool: "mytool",
                kind: "file",
                file: None,
                asset: RAW,
                sha256: sha256_of(&fx.join(RAW)),
            },
            Pin {
                tool: "mytool",
                kind: "archive",
                file: Some("mytool"),
                asset: TGZ,
                sha256: sha256_of(&fx.join(TGZ)),
            },
            Pin {
                tool: "promtool",
                kind: "archive",
                file: Some(PROM_MEMBER),
                asset: PROM,
                sha256: sha256_of(&fx.join(PROM)),
            },
        ]
    }

    /// Write the pins as tools/tools.lock.json lays them out.
    fn write_lock(&self, pins: &[Pin]) {
        let mut tools: Vec<&str> = pins.iter().map(|p| p.tool).collect();
        tools.dedup();
        let mut s = String::from("{\n  \"$schema\": \"https://raw.githubusercontent.com/theoremlp/rules_multitool/main/lockfile.schema.json\"");
        for t in tools {
            s.push_str(&format!(",\n  \"{t}\": {{\n    \"binaries\": [\n"));
            let entries: Vec<String> = pins
                .iter()
                .filter(|p| p.tool == t)
                .map(|p| {
                    let file = p
                        .file
                        .map(|f| format!("        \"file\": \"{f}\",\n"))
                        .unwrap_or_default();
                    format!(
                        "      {{\n        \"kind\": \"{}\",\n{file}        \"os\": \"linux\",\n        \"cpu\": \"x86_64\",\n        \"url\": \"{URL}/{}\",\n        \"sha256\": \"{}\"\n      }}",
                        p.kind, p.asset, p.sha256
                    )
                })
                .collect();
            s.push_str(&entries.join(",\n"));
            s.push_str("\n    ]\n  }");
        }
        s.push_str("\n}\n");
        write(self.lock(), s);
    }
}

/// `$PATH` for the binary: the fake curl first, then the system tools
/// (/sbin carries sha256sum on macOS).
fn path_for(fakes: &Path) -> String {
    format!(
        "{}:{}:/sbin:/usr/sbin",
        fakes.display(),
        std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".into())
    )
}

fn sha256_of(file: &Path) -> String {
    let o = Command::new("sha256sum")
        .arg(file)
        .env("PATH", path_for(Path::new("/nonexistent")))
        .output()
        .expect("sha256sum");
    assert!(o.status.success());
    String::from_utf8(o.stdout).unwrap()[..64].to_string()
}

fn tar_into(dir: &Path, members: &[&str], out: &Path) {
    let st = Command::new("tar")
        .arg("-czf")
        .arg(out)
        .args(members)
        .current_dir(dir)
        .status()
        .expect("tar");
    assert!(st.success());
}

/// One run in a fresh scratch dir: HOME and GITHUB_PATH inside it.
struct Ran {
    out: Output,
    scratch: TempDir,
}

impl Ran {
    fn home_bin(&self, name: &str) -> PathBuf {
        self.scratch.join("home/.local/bin").join(name)
    }
    fn github_path(&self) -> String {
        read(self.scratch.join("github_path"))
    }
    fn assert_installed_nothing(&self) {
        let bin = self.scratch.join("home/.local/bin");
        let n = std::fs::read_dir(&bin).map(|d| d.count()).unwrap_or(0);
        assert_eq!(n, 0, "nothing installed in {}", bin.display());
        assert_eq!(self.github_path(), "", "nothing put on PATH");
    }
}

fn run_with(w: &World, args: &[&str], tweak: impl FnOnce(Run, &Path) -> Run) -> Ran {
    let scratch = TempDir::new();
    std::fs::create_dir_all(scratch.join("home")).unwrap();
    write(scratch.join("github_path"), "");
    let r = Run::new(&bin("BIN"))
        .cwd(scratch.path())
        .env("PATH", path_for(&w.dir.join("bin")))
        .env("HOME", scratch.join("home"))
        .env("GITHUB_PATH", scratch.join("github_path"))
        .env("FIXTURES_DIR", w.fixtures())
        .args(args);
    let r = tweak(r, scratch.path());
    let out = r
        .go_within(std::time::Duration::from_secs(60))
        .expect("install-pinned-tool hung");
    Ran { out, scratch }
}

fn run(w: &World, args: &[&str]) -> Ran {
    run_with(w, args, |r, _| r)
}

fn lock_arg(w: &World) -> String {
    w.lock().display().to_string()
}

fn raw_args(w: &World) -> Vec<String> {
    vec![
        lock_arg(w),
        URL.into(),
        RAW.into(),
        "mytool".into(),
        "--raw".into(),
    ]
}

fn tar_args(w: &World) -> Vec<String> {
    vec![
        lock_arg(w),
        URL.into(),
        TGZ.into(),
        "mytool".into(),
        "--tar".into(),
    ]
}

fn strs(v: &[String]) -> Vec<&str> {
    v.iter().map(|s| s.as_str()).collect()
}

fn is_exec(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

// --- the happy paths ----------------------------------------------------------

#[test]
fn raw_happy_path() {
    let w = World::new();
    let r = run(&w, &strs(&raw_args(&w)));
    assert_eq!(r.out.code, 0, "{}", r.out.all());
    assert!(
        is_exec(&r.home_bin("mytool")),
        "--raw: binary installed and executable"
    );
    assert_eq!(read(r.home_bin("mytool")), "fake-binary-bytes-for-mytool\n");
    let want = format!("{}\n", r.scratch.join("home/.local/bin").display());
    assert_eq!(
        r.github_path(),
        want,
        "GITHUB_PATH gains ~/.local/bin, once"
    );
    assert_eq!(
        r.out.stdout,
        format!(
            "{RAW}: OK (sha256 pinned in {})\ninstall-pinned-tool: installed mytool from {URL}/{RAW}\n",
            w.lock().display()
        ),
        "the lock's verdict, then the install line"
    );
}

#[test]
fn tar_happy_path() {
    let w = World::new();
    let r = run(&w, &strs(&tar_args(&w)));
    assert_eq!(r.out.code, 0, "{}", r.out.all());
    assert!(is_exec(&r.home_bin("mytool")));
    assert!(read(r.home_bin("mytool")).contains("fake-tar-tool"));
}

#[test]
fn nested_member_lands_as_bin_name() {
    let w = World::new();
    let l = lock_arg(&w);
    let r = run(&w, &[&l, URL, PROM, "promtool", "--tar", PROM_MEMBER]);
    assert_eq!(r.out.code, 0, "{}", r.out.all());
    assert!(read(r.home_bin("promtool")).contains("fake-promtool"));
    assert!(
        !r.home_bin("prometheus").exists(),
        "only the named member is extracted"
    );
}

#[test]
fn empty_member_path_means_bin_name() {
    let w = World::new();
    let mut a = tar_args(&w);
    a.push(String::new());
    let r = run(&w, &strs(&a));
    assert_eq!(r.out.code, 0, "{}", r.out.all());
    assert!(read(r.home_bin("mytool")).contains("fake-tar-tool"));
}

// --- the lock is the only source of the expected hash -------------------------

#[test]
fn checksum_mismatch_with_the_lock_fails_closed_and_installs_nothing() {
    let w = World::new();
    let mut pins = w.true_pins();
    pins[0].sha256 = "0".repeat(64);
    w.write_lock(&pins);
    let r = run(&w, &strs(&raw_args(&w)));
    assert_eq!(
        r.out.code,
        1,
        "a checksum mismatch must fail: {}",
        r.out.all()
    );
    assert!(
        r.out.stderr.contains("checksum mismatch")
            && r.out.stderr.contains(&"0".repeat(64))
            && r.out.stderr.contains(&w.true_pins()[0].sha256),
        "names the pinned and the downloaded hash: {}",
        r.out.stderr
    );
    r.assert_installed_nothing();
}

#[test]
fn a_tampered_download_is_refused() {
    // The release swaps the binary (and would swap its checksum file too):
    // the lock still pins the old bytes, so nothing installs.
    let w = World::new();
    write(w.fixtures().join(RAW), "attacker-controlled-bytes\n");
    let r = run(&w, &strs(&raw_args(&w)));
    assert_eq!(r.out.code, 1, "{}", r.out.all());
    assert!(
        r.out.stderr.contains("checksum mismatch"),
        "{}",
        r.out.stderr
    );
    r.assert_installed_nothing();
}

#[test]
fn a_version_not_in_the_lock_is_refused_before_downloading() {
    let w = World::new();
    let log = w.dir.join("curl-args.log");
    let base = "https://example.invalid/download/v9.9.9";
    let l = lock_arg(&w);
    let r = run_with(&w, &[&l, base, RAW, "mytool", "--raw"], |r, _| {
        r.env("FAKE_CURL_ARGS_LOG", &log)
    });
    assert_eq!(r.out.code, 1, "{}", r.out.all());
    assert!(
        r.out
            .stderr
            .contains(&format!("{base}/{RAW} is not pinned in {l} under 'mytool'")),
        "{}",
        r.out.stderr
    );
    assert!(
        r.out.stderr.contains(&format!("pinned: {URL}/{RAW}")),
        "lists what is pinned: {}",
        r.out.stderr
    );
    assert!(!log.exists(), "curl never ran");
    r.assert_installed_nothing();
}

#[test]
fn a_tool_not_in_the_lock_is_refused() {
    let w = World::new();
    let l = lock_arg(&w);
    let r = run(&w, &[&l, URL, RAW, "othertool", "--raw"]);
    assert_eq!(r.out.code, 1, "{}", r.out.all());
    assert!(
        r.out.stderr.contains("pins no tool named 'othertool'"),
        "{}",
        r.out.stderr
    );
    r.assert_installed_nothing();
}

#[test]
fn a_pinned_url_under_another_tool_is_refused() {
    // promtool's tarball is pinned, but for promtool, not mytool.
    let w = World::new();
    let l = lock_arg(&w);
    let r = run(&w, &[&l, URL, PROM, "mytool", "--tar", PROM_MEMBER]);
    assert_eq!(r.out.code, 1, "{}", r.out.all());
    assert!(r.out.stderr.contains("is not pinned"), "{}", r.out.stderr);
    r.assert_installed_nothing();
}

#[test]
fn mode_must_match_the_locks_kind() {
    let w = World::new();
    let l = lock_arg(&w);
    let r = run(&w, &[&l, URL, RAW, "mytool", "--tar"]);
    assert_eq!(r.out.code, 1, "{}", r.out.all());
    assert!(
        r.out
            .stderr
            .contains("as kind 'file', but --tar installs kind 'archive'"),
        "{}",
        r.out.stderr
    );
    r.assert_installed_nothing();
}

#[test]
fn member_path_must_match_the_locks_file() {
    let w = World::new();
    let l = lock_arg(&w);
    let r = run(&w, &[&l, URL, PROM, "promtool", "--tar"]);
    assert_eq!(r.out.code, 1, "{}", r.out.all());
    assert!(
        r.out.stderr.contains(&format!(
            "is '{PROM_MEMBER}', but this step extracts 'promtool'"
        )),
        "{}",
        r.out.stderr
    );
    r.assert_installed_nothing();
}

#[test]
fn a_malformed_pinned_hash_is_refused() {
    let w = World::new();
    let mut pins = w.true_pins();
    pins[0].sha256 = pins[0].sha256.to_uppercase();
    w.write_lock(&pins);
    let r = run(&w, &strs(&raw_args(&w)));
    assert_eq!(r.out.code, 1, "{}", r.out.all());
    assert!(
        r.out.stderr.contains("not 64 lowercase hex"),
        "{}",
        r.out.stderr
    );
    r.assert_installed_nothing();
}

#[test]
fn a_missing_or_broken_lock_is_refused() {
    let w = World::new();
    let mut a = raw_args(&w);
    a[0] = w.dir.join("no-such.json").display().to_string();
    let r = run(&w, &strs(&a));
    assert_eq!(r.out.code, 1);
    assert!(r.out.stderr.contains("cannot read"), "{}", r.out.stderr);
    r.assert_installed_nothing();

    write(w.lock(), "{\"mytool\": {\"binaries\": [\n");
    let r = run(&w, &strs(&raw_args(&w)));
    assert_eq!(r.out.code, 1);
    assert!(
        r.out.stderr.contains("is not valid JSON"),
        "{}",
        r.out.stderr
    );
    r.assert_installed_nothing();
}

// --- transport, arguments and the environment ---------------------------------

#[test]
fn transport_failure_propagates_curls_status() {
    let w = World::new();
    let r = run_with(&w, &strs(&raw_args(&w)), |r, _| r.env("FAKE_CURL_RC", "22"));
    assert_eq!(r.out.code, 22, "exits with curl's own status");
    r.assert_installed_nothing();
}

#[test]
fn retry_policy_is_backoff_under_a_cap_and_only_the_asset_is_fetched() {
    // A fixed --retry-delay turns off curl's exponential backoff; it gave up
    // after ~6s of GitHub-releases 500s on 2026-09-25 and failed the queue.
    // No checksum file is fetched: the lock is the only source of the hash.
    let w = World::new();
    let log = w.dir.join("curl-args.log");
    let r = run_with(&w, &strs(&raw_args(&w)), |r, _| {
        r.env("FAKE_CURL_ARGS_LOG", &log)
    });
    assert_eq!(r.out.code, 0, "{}", r.out.all());
    let calls = read(&log);
    let lines: Vec<&str> = calls.lines().collect();
    assert_eq!(
        lines,
        vec![format!(
            "-fsSL --retry 6 --retry-all-errors --retry-max-time 180 --max-time 120 -O {URL}/{RAW}"
        )],
    );
}

#[test]
fn wrong_arg_count_exits_2() {
    let w = World::new();
    assert_eq!(run(&w, &["only", "one", "arg"]).out.code, 2);
    let mut seven = raw_args(&w);
    seven.push("member".into());
    seven.push("extra".into());
    let r = run(&w, &strs(&seven));
    assert_eq!(r.out.code, 2);
    assert!(
        r.out
            .stderr
            .starts_with("usage: install-pinned-tool <lock-file>"),
        "{}",
        r.out.stderr
    );
}

#[test]
fn bad_mode_exits_2() {
    let w = World::new();
    let l = lock_arg(&w);
    let r = run(&w, &[&l, URL, "asset", "name", "--bogus-mode"]);
    assert_eq!(r.out.code, 2);
    assert!(r
        .out
        .stderr
        .contains("mode must be --tar or --raw, got '--bogus-mode'"));
}

#[test]
fn missing_github_path_fails() {
    let w = World::new();
    let r = run_with(&w, &strs(&raw_args(&w)), |r, _| r.env_remove("GITHUB_PATH"));
    assert_eq!(r.out.code, 1);
    assert!(
        r.out.stderr.contains("GITHUB_PATH must be set"),
        "{}",
        r.out.stderr
    );
    assert!(!r.home_bin("mytool").exists());
}

#[test]
fn empty_github_path_fails_like_unset() {
    let w = World::new();
    let r = run_with(&w, &strs(&raw_args(&w)), |r, _| r.env("GITHUB_PATH", ""));
    assert_eq!(r.out.code, 1);
    assert!(r.out.stderr.contains("GITHUB_PATH must be set"));
}

#[test]
fn unwritable_github_path_fails() {
    let w = World::new();
    let r = run_with(&w, &strs(&raw_args(&w)), |r, scratch| {
        let d = scratch.join("github_path_dir");
        std::fs::create_dir_all(&d).unwrap();
        r.env("GITHUB_PATH", d)
    });
    assert_ne!(
        r.out.code,
        0,
        "a tool later steps cannot find on PATH is not installed: {}",
        r.out.all()
    );
}

#[test]
fn uncreatable_install_dir_fails() {
    let w = World::new();
    let r = run_with(&w, &strs(&raw_args(&w)), |r, scratch| {
        let home = scratch.join("home-is-a-file");
        write(&home, "not a directory\n");
        r.env("HOME", home)
    });
    assert_ne!(r.out.code, 0, "{}", r.out.all());
    assert_eq!(r.github_path(), "");
}

#[test]
fn downloads_stay_out_of_the_working_directory() {
    let w = World::new();
    let r = run(&w, &strs(&raw_args(&w)));
    assert_eq!(r.out.code, 0);
    assert!(
        !r.scratch.join(RAW).exists(),
        "the asset is fetched into a private temp dir"
    );
}

// --- the real workflows against the real lock ---------------------------------

/// One `uses: ./.github/actions/install-pinned-tool` step: its file and its
/// `with:` inputs, `${{ env.X }}` resolved from the same file.
struct Usage {
    file: String,
    with: Vec<(String, String)>,
}

impl Usage {
    fn get(&self, k: &str) -> &str {
        self.with
            .iter()
            .find(|(key, _)| key == k)
            .map(|(_, v)| v.as_str())
            .unwrap_or("")
    }
}

fn unquote(v: &str) -> String {
    let v = v.trim();
    for q in ['"', '\''] {
        if v.len() >= 2 && v.starts_with(q) && v.ends_with(q) {
            return v[1..v.len() - 1].to_string();
        }
    }
    v.to_string()
}

fn resolve_env(file: &str, text: &str, v: &str) -> String {
    let mut out = v.to_string();
    while let Some(a) = out.find("${{ env.") {
        let b = out[a..]
            .find("}}")
            .map(|b| a + b + 2)
            .expect("unclosed ${{");
        let name = out[a + "${{ env.".len()..b - 2].trim().to_string();
        let defs: Vec<String> = text
            .lines()
            .filter_map(|l| l.trim().strip_prefix(&format!("{name}: ")).map(unquote))
            .collect();
        assert!(
            defs.len() == 1,
            "{file}: env.{name} must be defined exactly once to check it against the lock, found {defs:?}"
        );
        out.replace_range(a..b, &defs[0]);
    }
    assert!(
        !out.contains("${{"),
        "{file}: cannot resolve '{v}' statically"
    );
    out
}

fn usages() -> Vec<Usage> {
    let files: Vec<String> = ["WORKFLOW_FILES", "COMPOSITE_ACTIONS"]
        .iter()
        .flat_map(|v| {
            std::env::var(v)
                .unwrap_or_else(|_| panic!("{v} is set by BUILD"))
                .split_whitespace()
                .map(String::from)
                .collect::<Vec<_>>()
        })
        .collect();
    let mut found = Vec::new();
    let mut expected = 0;
    for f in &files {
        let text = read(f);
        let lines: Vec<&str> = text.lines().collect();
        for (i, l) in lines.iter().enumerate() {
            let t = l.trim().trim_start_matches("- ");
            if !t.starts_with("uses: ./.github/actions/install-pinned-tool") {
                continue;
            }
            expected += 1;
            let step_indent = l.len() - l.trim_start().len();
            let mut with = Vec::new();
            let mut j = i + 1;
            // The rest of this step: deeper than its first key, or a `- ` at it.
            while j < lines.len() {
                let m = lines[j];
                let ind = m.len() - m.trim_start().len();
                if !m.trim().is_empty()
                    && (ind < step_indent
                        || (ind == step_indent && m.trim_start().starts_with("- ")))
                {
                    break;
                }
                if m.trim() == "with:" {
                    let wi = ind;
                    j += 1;
                    while j < lines.len() {
                        let n = lines[j];
                        let ni = n.len() - n.trim_start().len();
                        if n.trim().is_empty() || ni <= wi {
                            break;
                        }
                        if let Some((k, v)) = n.trim().split_once(':') {
                            with.push((k.trim().to_string(), resolve_env(f, &text, &unquote(v))));
                        }
                        j += 1;
                    }
                    break;
                }
                j += 1;
            }
            found.push(Usage {
                file: f.clone(),
                with,
            });
        }
    }
    assert_eq!(found.len(), expected);
    found
}

#[test]
fn every_workflow_install_is_pinned_in_tools_lock_json() {
    // Runs the real lookup: curl is a stub that exits 99, so 99 means the lock
    // pinned the step's URL (kind and member included) and the binary moved on
    // to download it; anything else is the refusal it printed.
    // Absolute: each run's working directory is its own scratch dir.
    let lock = std::fs::canonicalize(std::env::var("LOCK").expect("LOCK is set by BUILD"))
        .unwrap()
        .display()
        .to_string();
    let all = usages();
    assert!(
        all.len() >= 5,
        "found only {} install-pinned-tool steps; the scan is broken",
        all.len()
    );
    let w = World::new();
    let mut seen = Vec::new();
    for u in &all {
        let base = u.get("base-url");
        let asset = u.get("asset");
        let bin_name = u.get("bin-name");
        let mode = format!("--{}", u.get("mode"));
        let member = u.get("member-path");
        assert!(
            !base.is_empty() && !asset.is_empty() && !bin_name.is_empty(),
            "{}: incomplete step {:?}",
            u.file,
            u.with
        );
        for gone in ["checksum-file", "checksum-pattern"] {
            assert!(
                u.with.iter().all(|(k, _)| k != gone),
                "{}: '{gone}' is no longer an input; the hash comes from the lock",
                u.file
            );
        }
        let mut args = vec![lock.as_str(), base, asset, bin_name, mode.as_str()];
        if !member.is_empty() {
            args.push(member);
        }
        let r = run_with(&w, &args, |r, _| r.env("FAKE_CURL_RC", "99"));
        assert_eq!(
            r.out.code, 99,
            "{}: {base}/{asset} as {bin_name}: {}",
            u.file, r.out.stderr
        );
        seen.push(format!("{bin_name} {base}/{asset}"));
    }
    eprintln!("checked against the lock:\n  {}", seen.join("\n  "));
}
