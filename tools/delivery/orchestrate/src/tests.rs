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

//! main_test.go, ported. bazel is FAKED (a stub printing canned query output
//! over a canned bazel-bin); deploy-affected.sh is REAL, run over scratch git
//! repos built once per test binary.

use super::*;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

struct Scratch {
    dir: String,
    base: String,
}

struct Repos {
    script: String,
    declared: Scratch,
    undeclared: Scratch,
    excluded: Scratch,
    global_impact: Scratch,
    _root: TmpDir,
}

/// A test temp dir, removed on drop.
struct TmpDir(PathBuf);

impl TmpDir {
    fn new() -> TmpDir {
        static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let base = std::env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        let p = base.join(format!(
            "orch-rs-{}-{}",
            std::process::id(),
            N.fetch_add(1, std::sync::atomic::Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        TmpDir(p)
    }
    fn path(&self) -> String {
        self.0.to_string_lossy().into_owned()
    }
}

impl Drop for TmpDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn must_git(dir: &str, args: &[&str]) -> String {
    let out = Command::new("git")
        .args(args)
        .current_dir(dir)
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "git {:?}: {}",
        args,
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn must_write(dir: &str, rel: &str, content: &str) {
    let p = Path::new(dir).join(rel);
    fs::create_dir_all(p.parent().unwrap()).unwrap();
    fs::write(p, content).unwrap();
}

fn new_scratch(root: &str, name: &str, file: &str) -> Scratch {
    let dir = format!("{}/{}", root, name);
    fs::create_dir_all(&dir).unwrap();
    must_git(&dir, &["-c", "init.defaultBranch=main", "init"]);
    must_git(&dir, &["config", "user.email", "test@example.com"]);
    must_git(&dir, &["config", "user.name", "Test"]);
    must_write(&dir, "README.md", "init\n");
    must_git(&dir, &["add", "."]);
    must_git(&dir, &["commit", "-m", "test: initial commit"]);
    let base = must_git(&dir, &["rev-parse", "HEAD"]);
    must_write(&dir, file, "changed\n");
    must_git(&dir, &["add", "."]);
    must_git(&dir, &["commit", "-m", &format!("test: touch {}", file)]);
    Scratch { dir, base }
}

fn repos() -> &'static Repos {
    static R: OnceLock<Repos> = OnceLock::new();
    R.get_or_init(|| {
        let rel = std::env::var("DEPLOY_AFFECTED")
            .unwrap_or_else(|_| "../../ci/deploy-affected.sh".into());
        let script = fs::canonicalize(&rel)
            .unwrap_or_else(|e| panic!("the real decision engine is missing at {}: {}", rel, e))
            .to_string_lossy()
            .into_owned();
        let root = TmpDir::new();
        let r = root.path();
        Repos {
            script,
            declared: new_scratch(&r, "declared", "oauth-user-inspector/infra/app/main.go"),
            undeclared: new_scratch(&r, "undeclared", "docs/notes.md"),
            excluded: new_scratch(
                &r,
                "excluded",
                "oauth-user-inspector/infra/identity/main.go",
            ),
            global_impact: new_scratch(&r, "global-impact", "MODULE.bazel"),
            _root: root,
        }
    })
}

#[derive(Default)]
struct FakeBazel {
    labels: Vec<String>,
    bin_dir: String,
    fail_query: bool,
    fail_build: bool,
}

impl FakeBazel {
    fn install(&self, dir: &str) -> String {
        let mut query = "true".to_string();
        if !self.labels.is_empty() {
            query = "printf '%s\\n'".to_string();
            for l in &self.labels {
                query += &format!(" '{}'", l);
            }
        }
        if self.fail_query {
            query = "echo 'ERROR: package contains errors' >&2; exit 1".into();
        }
        let build = if self.fail_build {
            "echo 'ERROR: analysis of target failed' >&2; exit 1"
        } else {
            "true"
        };
        let script = format!(
            "#!/usr/bin/env bash\nset -uo pipefail\ncase \"${{1:-}}\" in\n  query) {} ;;\n  build) {} ;;\n  info)  echo '{}' ;;\n  *) echo \"fake bazel: unexpected invocation: $*\" >&2; exit 64 ;;\nesac\n",
            query, build, self.bin_dir
        );
        let p = format!("{}/fake-bazel", dir);
        fs::write(&p, script).unwrap();
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
        p
    }
}

fn decl(name: &str, over: serde_json::Value) -> serde_json::Value {
    let mut m = serde_json::json!({
        "schema": 1,
        "name": name,
        "kind": "cloud-run",
        "run": format!("//{}/infra/app:deploy", name),
        "build": "",
        "environments": ["development", "nonproduction", "production"],
        "github_environment": format!("{}-{{env}}", name),
        "promotion": format!("release:{}-v", name),
        "companions": [],
        "extra_paths": [],
        "exclude_paths": [],
        "preflight": "",
        "package": format!("{}/infra/app", name),
    });
    if let serde_json::Value::Object(o) = over {
        for (k, v) in o {
            m[k] = v;
        }
    }
    m
}

fn write_meta(bin: &str, meta: &serde_json::Value) -> String {
    let pkg = meta["package"].as_str().unwrap();
    let name = meta["name"].as_str().unwrap();
    let dir = format!("{}/{}", bin, pkg);
    fs::create_dir_all(&dir).unwrap();
    fs::write(
        format!("{}/{}.delivery.json", dir, name),
        serde_json::to_vec_pretty(meta).unwrap(),
    )
    .unwrap();
    format!("//{}:{}.delivery_unit", pkg, name)
}

struct Result_ {
    code: i32,
    stdout: String,
    man: serde_json::Value,
    man_raw: String,
    gh_output: String,
}

impl Result_ {
    fn outputs(&self) -> HashMap<String, String> {
        self.gh_output
            .split('\n')
            .filter_map(|l| l.split_once('='))
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }
    fn unit(&self, name: &str) -> &serde_json::Value {
        self.man["units"]
            .as_array()
            .unwrap()
            .iter()
            .find(|u| u["name"] == name)
            .unwrap_or_else(|| panic!("unit {} missing from manifest: {}", name, self.man_raw))
    }
    fn units(&self) -> usize {
        self.man["units"].as_array().unwrap().len()
    }
}

/// Holds the per-test temp dirs alive for the duration of a run.
struct Harness<'a> {
    repo: &'a Scratch,
    fake: FakeBazel,
    env: Vec<(&'a str, String)>,
    _keep: Vec<TmpDir>,
}

impl<'a> Harness<'a> {
    fn new(repo: &'a Scratch, fake: FakeBazel, keep: TmpDir) -> Harness<'a> {
        Harness {
            repo,
            fake,
            env: Vec::new(),
            _keep: vec![keep],
        }
    }
    fn env(mut self, k: &'a str, v: &str) -> Self {
        self.env.push((k, v.to_string()));
        self
    }
    fn run(self) -> Result_ {
        let work = TmpDir::new();
        let w = work.path();
        let gh_out = format!("{}/github_output", w);
        fs::write(&gh_out, b"").unwrap();
        let mut env: HashMap<String, String> = HashMap::new();
        env.insert("PATH".into(), std::env::var("PATH").unwrap_or_default());
        env.insert("HOME".into(), w.clone());
        env.insert(
            "GIT_CONFIG_GLOBAL".into(),
            format!("{}/nonexistent-gitconfig", w),
        );
        env.insert(
            "GIT_CONFIG_SYSTEM".into(),
            format!("{}/nonexistent-gitconfig", w),
        );
        env.insert("BEFORE_REV".into(), self.repo.base.clone());
        env.insert("GITHUB_OUTPUT".into(), gh_out.clone());
        for (k, v) in &self.env {
            if v.is_empty() {
                env.remove(*k);
            } else {
                env.insert(k.to_string(), v.clone());
            }
        }
        let mut out: Vec<u8> = Vec::new();
        let code = {
            let mut cfg = Config {
                repo_root: self.repo.dir.clone(),
                script: repos().script.clone(),
                bazel: self.fake.install(&w),
                out: format!("{}/delivery-manifest.json", w),
                env: Env(env
                    .into_iter()
                    .map(|(k, v)| (k, OsString::from(v)))
                    .collect()),
                stdout: &mut out,
            };
            orchestrate(&mut cfg)
        };
        let stdout = String::from_utf8_lossy(&out).into_owned();
        let man_raw = fs::read_to_string(format!("{}/delivery-manifest.json", w))
            .unwrap_or_else(|_| panic!("no manifest written (exit {}):\n{}", code, stdout));
        let man = serde_json::from_str(&man_raw).expect("manifest is valid JSON");
        let gh_output = fs::read_to_string(&gh_out).unwrap();
        Result_ {
            code,
            stdout,
            man,
            man_raw,
            gh_output,
        }
    }
}

fn one_unit(over: serde_json::Value) -> (FakeBazel, TmpDir) {
    let bin = TmpDir::new();
    let mut base = serde_json::json!({"extra_paths": ["oauth-user-inspector/", "tools/deploy/"]});
    if let serde_json::Value::Object(o) = over {
        for (k, v) in o {
            base[k] = v;
        }
    }
    let label = write_meta(&bin.path(), &decl("oauth-user-inspector", base));
    (
        FakeBazel {
            labels: vec![label],
            bin_dir: bin.path(),
            ..Default::default()
        },
        bin,
    )
}

fn two_units() -> (FakeBazel, TmpDir) {
    let bin = TmpDir::new();
    let hit = write_meta(
        &bin.path(),
        &decl(
            "oauth-user-inspector",
            serde_json::json!({"extra_paths": ["oauth-user-inspector/"]}),
        ),
    );
    let miss = write_meta(
        &bin.path(),
        &decl(
            "tabula-api",
            serde_json::json!({"extra_paths": ["tabula/api/"]}),
        ),
    );
    (
        FakeBazel {
            labels: vec![hit, miss],
            bin_dir: bin.path(),
            ..Default::default()
        },
        bin,
    )
}

fn h1<'a>(repo: &'a Scratch, over: serde_json::Value) -> Harness<'a> {
    let (f, k) = one_unit(over);
    Harness::new(repo, f, k)
}

fn assert_fail_open(r: &Result_, want_reason: &str) {
    assert_eq!(
        r.code, 0,
        "a detection problem must never redden CI\n{}",
        r.stdout
    );
    assert_eq!(r.man["computed_by"], COMPUTED_BY_FAIL_OPEN);
    let reason = r.man["reason"].as_str().unwrap_or("");
    assert!(
        !reason.is_empty(),
        "a fail-open that does not say why is a silent one"
    );
    assert!(
        reason.contains(want_reason),
        "reason {:?} lacks {:?}",
        reason,
        want_reason
    );
    for u in r.man["units"].as_array().unwrap() {
        assert_eq!(
            u["affected"], true,
            "unit {} must be affected under fail-open",
            u["name"]
        );
        assert_eq!(u["computed_by"], COMPUTED_BY_FAIL_OPEN);
    }
    assert!(
        r.stdout
            .contains("::warning title=delivery-orchestrator-fail-open::"),
        "{}",
        r.stdout
    );
}

// --- happy path -------------------------------------------------------------

#[test]
fn path_match_affected() {
    let rp = repos();
    let r = h1(&rp.declared, serde_json::json!({})).run();
    assert_eq!(r.code, 0, "{}", r.stdout);
    assert_eq!(r.man["computed_by"], COMPUTED_BY_PATHS);
    assert!(
        r.man.get("reason").is_none(),
        "reason must be omitted on a clean decision"
    );
    assert_eq!(r.man["schema"], SCHEMA_VERSION);
    assert_eq!(r.man["before"], rp.declared.base.as_str());
    assert_ne!(r.man["commit"], "");
    let u = r.unit("oauth-user-inspector");
    assert_eq!(u["affected"], true);
    assert_eq!(u["computed_by"], COMPUTED_BY_PATHS);
    assert!(
        u["reason"].as_str().unwrap().contains("path matched"),
        "{}",
        u["reason"]
    );
    assert_eq!(u["kind"], "cloud-run");
    assert_eq!(u["run"], "//oauth-user-inspector/infra/app:deploy");
    assert_eq!(
        u["environments"],
        serde_json::json!(["development", "nonproduction", "production"])
    );
    assert_eq!(u["github_environment"], "oauth-user-inspector-{env}");
    let out = r.outputs();
    assert_eq!(out["affected_oauth_user_inspector"], "true");
    let echoed: serde_json::Value = serde_json::from_str(&out["manifest"]).unwrap();
    assert_eq!(
        echoed, r.man,
        "GITHUB_OUTPUT manifest disagrees with the file"
    );
    assert!(r
        .stdout
        .contains("---- deploy-affected.sh: oauth-user-inspector (paths mode) ----"));
}

#[test]
fn no_path_match_not_affected() {
    let r = h1(&repos().undeclared, serde_json::json!({})).run();
    assert_eq!(r.code, 0);
    assert_eq!(r.man["computed_by"], COMPUTED_BY_PATHS);
    assert_eq!(r.unit("oauth-user-inspector")["affected"], false);
    assert_eq!(r.outputs()["affected_oauth_user_inspector"], "false");
}

#[test]
fn exclude_paths_respected() {
    let r = h1(
        &repos().excluded,
        serde_json::json!({"extra_paths": ["oauth-user-inspector/"], "exclude_paths": ["oauth-user-inspector/infra/identity/"]}),
    )
    .run();
    let u = r.unit("oauth-user-inspector");
    assert_eq!(
        u["affected"], false,
        "exclude_paths did not reach EXCLUDE_PATH_REGEX: {}",
        u["reason"]
    );
    assert_eq!(u["computed_by"], COMPUTED_BY_PATHS);
}

#[test]
fn graph_mode_exports_deploy_targets() {
    let r = h1(
        &repos().global_impact,
        serde_json::json!({"build": "//oauth-user-inspector:image", "extra_paths": ["oauth-user-inspector/"]}),
    )
    .run();
    let u = r.unit("oauth-user-inspector");
    assert_eq!(u["computed_by"], COMPUTED_BY_GRAPH);
    assert_eq!(u["affected"], true);
    assert!(
        u["reason"].as_str().unwrap().contains("global-impact"),
        "{}",
        u["reason"]
    );
    assert_eq!(r.man["computed_by"], COMPUTED_BY_GRAPH);
}

#[test]
fn graph_targets_export_deploy_targets() {
    let bin = TmpDir::new();
    let label = write_meta(
        &bin.path(),
        &decl(
            "tabula-api",
            serde_json::json!({
                "build": "", "shared_build": "tabula",
                "graph_targets": ["//tabula/api:image_push", "//tabula/extension:chrome_zip"],
                "extra_paths": ["tabula/infra/app/"],
            }),
        ),
    );
    let fake = FakeBazel {
        labels: vec![label],
        bin_dir: bin.path(),
        ..Default::default()
    };
    let r = Harness::new(&repos().global_impact, fake, bin).run();
    let u = r.unit("tabula-api");
    assert_eq!(u["computed_by"], COMPUTED_BY_GRAPH);
    assert_eq!(u["affected"], true);
    assert!(u["reason"].as_str().unwrap().contains("global-impact"));
}

#[test]
fn decide_exports_the_declared_graph_universe() {
    let dir = TmpDir::new();
    let stub = format!("{}/engine.sh", dir.path());
    fs::write(
        &stub,
        "#!/usr/bin/env bash\necho \"stub-engine: DEPLOY_TARGETS=[${DEPLOY_TARGETS-<unset>}]\"\necho \"deploy-affected: affected=false (stub)\"\necho \"affected=false\" >> \"$GITHUB_OUTPUT\"\n",
    )
    .unwrap();
    let v = |s: &[&str]| Some(s.iter().map(|x| x.to_string()).collect::<Vec<_>>());
    let cases = [
        (
            UnitMeta {
                name: "tabula-api".into(),
                run: "//tabula/infra/app:deploy".into(),
                graph_targets: v(&["//tabula/api:image_push", "//tabula/extension:chrome_zip"]),
                ..Default::default()
            },
            "DEPLOY_TARGETS=[//tabula/api:image_push //tabula/extension:chrome_zip]",
        ),
        (
            UnitMeta {
                name: "app".into(),
                run: "//app/infra:deploy".into(),
                build: "//app:image".into(),
                ..Default::default()
            },
            "DEPLOY_TARGETS=[//app:image //app/infra:deploy]",
        ),
        (
            UnitMeta {
                name: "app".into(),
                run: "//app/infra:deploy".into(),
                ..Default::default()
            },
            "DEPLOY_TARGETS=[<unset>]",
        ),
    ];
    for (meta, want) in cases {
        let mut out: Vec<u8> = Vec::new();
        let mut cfg = Config {
            repo_root: dir.path(),
            script: stub.clone(),
            bazel: String::new(),
            out: String::new(),
            env: Env::from_pairs(&[("PATH", &std::env::var("PATH").unwrap_or_default())]),
            stdout: &mut out,
        };
        let res = decide(&mut cfg, "HEAD~1", &meta);
        let text = String::from_utf8_lossy(&out).into_owned();
        assert!(res.is_ok(), "decide failed:\n{}", text);
        let v = res.ok().unwrap();
        assert_eq!(v.reason, "stub");
        assert!(text.contains(want), "want {:?} in\n{}", want, text);
    }
}

#[test]
fn two_units_independent_verdicts() {
    let (f, k) = two_units();
    let r = Harness::new(&repos().declared, f, k).run();
    assert_eq!(r.unit("oauth-user-inspector")["affected"], true);
    assert_eq!(r.unit("tabula-api")["affected"], false);
    let out = r.outputs();
    assert_eq!(out["affected_oauth_user_inspector"], "true");
    assert_eq!(out["affected_tabula_api"], "false");
}

#[test]
fn unit_filter_judges_only_the_named_units() {
    let (f, k) = two_units();
    let r = Harness::new(&repos().declared, f, k)
        .env("ORCHESTRATE_UNITS", "tabula-api")
        .run();
    assert_ne!(r.man["computed_by"], COMPUTED_BY_FAIL_OPEN, "{}", r.man_raw);
    assert_eq!(r.units(), 1);
    assert_eq!(r.unit("tabula-api")["affected"], false);
    let out = r.outputs();
    assert!(!out.contains_key("affected_oauth_user_inspector"));
    assert_eq!(out["affected_tabula_api"], "false");
}

#[test]
fn unit_filter_unknown_unit_fails_open() {
    let (f, k) = two_units();
    let r = Harness::new(&repos().declared, f, k)
        .env("ORCHESTRATE_UNITS", "tabula-api ghost")
        .run();
    assert_fail_open(&r, "ghost");
    r.unit("ghost");
    r.unit("tabula-api");
    assert_eq!(r.units(), 2);
}

#[test]
fn unit_filter_query_failure_lists_the_named_units() {
    let (mut f, k) = two_units();
    f.fail_query = true;
    let r = Harness::new(&repos().declared, f, k)
        .env("ORCHESTRATE_UNITS", "oauth-user-inspector tabula-api")
        .run();
    assert_fail_open(&r, "bazel query");
    r.unit("oauth-user-inspector");
    r.unit("tabula-api");
}

// --- spec §5 row 1: fail-open -------------------------------------------------

#[test]
fn unresolvable_before_rev_fails_open() {
    let r = h1(&repos().undeclared, serde_json::json!({}))
        .env("BEFORE_REV", "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
        .run();
    assert_fail_open(&r, "does not resolve to a commit");
    assert_eq!(r.outputs()["affected_oauth_user_inspector"], "true");
}

#[test]
fn no_base_at_all_fails_open() {
    let r = h1(&repos().undeclared, serde_json::json!({}))
        .env("BEFORE_REV", "")
        .env("BASE_REF", "")
        .run();
    assert_fail_open(&r, "neither BEFORE_REV nor BASE_REF");
}

#[test]
fn base_ref_fallback_decides() {
    let rp = repos();
    let r = h1(&rp.declared, serde_json::json!({}))
        .env("BEFORE_REV", "")
        .env("BASE_REF", &rp.declared.base)
        .run();
    assert_eq!(
        r.man["computed_by"], COMPUTED_BY_PATHS,
        "BASE_REF was ignored\n{}",
        r.stdout
    );
    assert_eq!(r.man["before"], rp.declared.base.as_str());
    assert_eq!(r.unit("oauth-user-inspector")["affected"], true);
}

#[test]
fn forced_push_fails_open() {
    let r = h1(&repos().undeclared, serde_json::json!({}))
        .env("FORCED_PUSH", "true")
        .run();
    assert_fail_open(&r, "forced push");
}

#[test]
fn bazel_query_fails_fails_open() {
    let (mut f, k) = one_unit(serde_json::json!({}));
    f.fail_query = true;
    let r = Harness::new(&repos().undeclared, f, k).run();
    assert_fail_open(&r, "bazel query");
    assert_eq!(r.units(), 0);
    assert!(
        r.man_raw.contains("ERROR: package contains errors"),
        "{}",
        r.man_raw
    );
}

#[test]
fn bazel_build_fails_fails_open() {
    let (mut f, k) = one_unit(serde_json::json!({}));
    f.fail_build = true;
    let r = Harness::new(&repos().undeclared, f, k).run();
    assert_fail_open(&r, "bazel build");
    assert_eq!(r.unit("oauth-user-inspector")["affected"], true);
    assert_eq!(r.outputs()["affected_oauth_user_inspector"], "true");
}

#[test]
fn metadata_unparsable_fails_open() {
    let bin = TmpDir::new();
    let label = write_meta(
        &bin.path(),
        &decl("oauth-user-inspector", serde_json::json!({})),
    );
    fs::write(
        format!(
            "{}/oauth-user-inspector/infra/app/oauth-user-inspector.delivery.json",
            bin.path()
        ),
        "{ this is not json",
    )
    .unwrap();
    let fake = FakeBazel {
        labels: vec![label],
        bin_dir: bin.path(),
        ..Default::default()
    };
    let r = Harness::new(&repos().undeclared, fake, bin).run();
    assert_fail_open(
        &r,
        "unreadable: invalid character 't' looking for beginning of object key string",
    );
    assert_eq!(r.unit("oauth-user-inspector")["affected"], true);
}

#[test]
fn metadata_missing_fails_open() {
    let bin = TmpDir::new();
    let fake = FakeBazel {
        labels: vec!["//some/pkg:ghost.delivery_unit".into()],
        bin_dir: bin.path(),
        ..Default::default()
    };
    let r = Harness::new(&repos().undeclared, fake, bin).run();
    assert_fail_open(&r, "unreadable");
    let u = r.unit("ghost");
    assert_eq!(u["affected"], true);
    assert_eq!(
        u["run"], "",
        "a placeholder must not present the filegroup label as a delivery target"
    );
    assert_eq!(u["environments"], serde_json::Value::Null);
    assert!(r.man["reason"]
        .as_str()
        .unwrap()
        .contains("//some/pkg:ghost.delivery_unit"));
    assert!(r.man["reason"]
        .as_str()
        .unwrap()
        .contains(": no such file or directory"));
}

#[test]
fn engine_non_zero_fails_open() {
    let bin = TmpDir::new();
    let fine = write_meta(
        &bin.path(),
        &decl(
            "tabula-api",
            serde_json::json!({"extra_paths": ["tabula/api/"]}),
        ),
    );
    let broken = write_meta(
        &bin.path(),
        &decl("no-signal", serde_json::json!({"extra_paths": []})),
    );
    let fake = FakeBazel {
        labels: vec![fine, broken],
        bin_dir: bin.path(),
        ..Default::default()
    };
    let r = Harness::new(&repos().undeclared, fake, bin).run();
    assert_fail_open(&r, "exited non-zero: exit status");
    assert_eq!(r.unit("tabula-api")["affected"], true);
    assert_eq!(r.unit("no-signal")["affected"], true);
}

#[test]
fn empty_universe_is_not_fail_open() {
    let bin = TmpDir::new();
    let fake = FakeBazel {
        bin_dir: bin.path(),
        ..Default::default()
    };
    let r = Harness::new(&repos().undeclared, fake, bin).run();
    assert_eq!(r.code, 0);
    assert_ne!(r.man["computed_by"], COMPUTED_BY_FAIL_OPEN);
    assert_eq!(r.units(), 0);
    assert!(r.man_raw.contains("\"units\": []"), "{}", r.man_raw);
}

#[test]
fn unwritable_out_exits_one() {
    let (f, k) = one_unit(serde_json::json!({}));
    let mut out: Vec<u8> = Vec::new();
    let code = {
        let mut cfg = Config {
            repo_root: repos().undeclared.dir.clone(),
            script: repos().script.clone(),
            bazel: f.install(&k.path()),
            out: "/nonexistent-dir/x/delivery-manifest.json".into(),
            env: Env::from_pairs(&[("PATH", &std::env::var("PATH").unwrap_or_default())]),
            stdout: &mut out,
        };
        orchestrate(&mut cfg)
    };
    assert_eq!(code, 1);
    let text = String::from_utf8_lossy(&out);
    assert!(
        text.contains("::error title=delivery-orchestrator::cannot write the manifest to /nonexistent-dir/x/delivery-manifest.json: open /nonexistent-dir/x/delivery-manifest.json: no such file or directory"),
        "{}",
        text
    );
}

// --- pure helpers ---------------------------------------------------------------

#[test]
fn metadata_rel_path_cases() {
    for (label, want) in [
        (
            "//oauth-user-inspector/infra/app:oauth-user-inspector.delivery_unit",
            "oauth-user-inspector/infra/app/oauth-user-inspector.delivery.json",
        ),
        ("@//a/b:c.delivery_unit", "a/b/c.delivery.json"),
        ("@@//a/b:c.delivery_unit", "a/b/c.delivery.json"),
        ("//a/b:weird", "a/b/weird.delivery.json"),
        ("//a/b", "a/b/b.delivery.json"),
    ] {
        assert_eq!(metadata_rel_path(label).unwrap(), want, "{}", label);
    }
    assert_eq!(
        metadata_rel_path("//").unwrap_err(),
        "label \"//\" is not a main-repo label"
    );
    assert_eq!(
        metadata_rel_path("//a:").unwrap_err(),
        "label \"//a:\" has an empty target name"
    );
}

#[test]
fn unit_name_from_label_cases() {
    assert_eq!(
        unit_name_from_label("//oauth-user-inspector/infra/app:oauth-user-inspector.delivery_unit"),
        "oauth-user-inspector"
    );
    assert_eq!(unit_name_from_label("//a/b:c.delivery_unit"), "c");
}

/// The same table as TestOutputVarName (and //tools/delivery/gen's copy).
#[test]
fn output_var_name_contract() {
    for (i, w) in [
        ("oauth-user-inspector", "oauth_user_inspector"),
        ("tabula-api", "tabula_api"),
        ("charts", "charts"),
        ("a.b/c", "a_b_c"),
    ] {
        assert_eq!(output_var_name(i), w);
    }
    assert_eq!(output_var_name("é-x"), "__x");
}

#[test]
fn engine_env_does_not_inherit_deploy_targets() {
    let env = Env::from_pairs(&[
        ("PATH", "/usr/bin"),
        ("DEPLOY_TARGETS", "//leaked:target"),
        ("SOME_OTHER_THING", "x"),
    ]);
    for (k, _) in engine_env(&env, &[("BEFORE_REV", "abc".into())]) {
        assert_ne!(k, "DEPLOY_TARGETS");
        assert_ne!(k, "SOME_OTHER_THING");
    }
}

#[test]
fn engine_reason_takes_the_first_verdict_line() {
    assert_eq!(
        engine_reason(
            "x\ndeploy-affected: affected=true (a (b))\ndeploy-affected: affected=false (c)\n"
        ),
        Some("a (b)".into())
    );
    assert_eq!(engine_reason("deploy-affected: affected=maybe (x)"), None);
}

// --- per-unit durable bases (#1842) -------------------------------------------

#[test]
fn per_unit_base_overrides_the_single_base() {
    let rp = repos();
    let head = must_git(&rp.declared.dir, &["rev-parse", "HEAD"]);
    let r = h1(&rp.declared, serde_json::json!({}))
        .env(
            "UNIT_BASES_JSON",
            &format!("{{\"oauth-user-inspector\":\"{}\"}}", head),
        )
        .run();
    let u = r.unit("oauth-user-inspector");
    assert_eq!(
        u["affected"], false,
        "the per-unit base did not reach the engine: {}",
        u["reason"]
    );
    assert_eq!(u["base"], head.as_str());
    assert_eq!(r.man["before"], rp.declared.base.as_str());
}

#[test]
fn per_unit_base_unresolvable_falls_back() {
    let rp = repos();
    let r = h1(&rp.declared, serde_json::json!({}))
        .env(
            "UNIT_BASES_JSON",
            "{\"oauth-user-inspector\":\"0000000000000000000000000000000000000000\"}",
        )
        .run();
    let u = r.unit("oauth-user-inspector");
    assert_eq!(u["affected"], true);
    assert_eq!(u["base"], rp.declared.base.as_str());
}

#[test]
fn per_unit_base_malformed_json_is_ignored() {
    let rp = repos();
    let r = h1(&rp.declared, serde_json::json!({}))
        .env("UNIT_BASES_JSON", "{not json")
        .run();
    let u = r.unit("oauth-user-inspector");
    assert_eq!(u["affected"], true);
    assert_eq!(u["base"], rp.declared.base.as_str());
}
