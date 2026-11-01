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

//! The hermetic half of main_test.go, ported: golden files, determinism, the
//! kill switch, grouping, pruning, discovery and every declaration the
//! renderer must refuse. (parity_test.go reads the COMMITTED workflows, which
//! do not depend on which generator wrote them; it stays a Go test.)

use std::collections::BTreeMap;

use crate::actionpins::Pins;
use crate::app::{self, PinSource};
use crate::gostd::Value;
use crate::render::{self, GenError};
use crate::unit::{self, Unit};

const FIXTURES: &[&str] = &[
    "charts",
    "esp32-s3",
    "gravastar-mouse-publish",
    "oauth-user-inspector-identity",
    "oauth-user-inspector",
    "tabula-api",
    "tabula-build-stack",
    "tabula-dev-latest",
    "tabula-identity",
    "tabula-web",
    "vitruvian",
    "zitadel-apps",
];
const WF: &str = "delivery-fixture.yaml";

type Mutation = Box<dyn Fn(&mut Unit)>;
type Edit = Box<dyn Fn(&mut Vec<Unit>)>;

/// The package's testdata directory, under `bazel test` (runfiles) or cargo.
fn testdata() -> String {
    for base in [
        std::env::var("TEST_SRCDIR")
            .ok()
            .map(|s| format!("{}/_main/tools/delivery/gen/testdata", s)),
        Some("tools/delivery/gen/testdata".to_string()),
        std::env::var("CARGO_MANIFEST_DIR")
            .ok()
            .map(|s| format!("{}/testdata", s)),
    ]
    .into_iter()
    .flatten()
    {
        if std::path::Path::new(&base).join("action-pins.yml").exists() {
            return base;
        }
    }
    panic!("cannot find tools/delivery/gen/testdata");
}

fn pins() -> Pins {
    Pins::load(&format!("{}/action-pins.yml", testdata())).unwrap()
}

fn fixture_paths() -> Vec<String> {
    FIXTURES
        .iter()
        .map(|n| format!("{}/units/{}.delivery.json", testdata(), n))
        .collect()
}

fn fixtures() -> Vec<Unit> {
    let u = unit::load_units(&fixture_paths()).unwrap();
    assert_eq!(u.len(), FIXTURES.len());
    u
}

fn must_render(units: &[Unit], phase: i64) -> String {
    render::render(units, phase, WF, &pins())
        .unwrap_or_else(|e| panic!("render(phase {}): {:?}", phase, e))
}

fn render_err(units: &[Unit], phase: i64) -> String {
    match render::render(units, phase, WF, &pins()) {
        Ok(_) => panic!("render succeeded; want an error"),
        Err(e) => e.text().to_string(),
    }
}

fn assert_golden(name: &str, got: &str) {
    let want = std::fs::read_to_string(format!("{}/{}", testdata(), name)).unwrap();
    if want != got {
        let (w, g): (Vec<&str>, Vec<&str>) = (want.lines().collect(), got.lines().collect());
        for i in 0..w.len().max(g.len()) {
            if w.get(i) != g.get(i) {
                panic!(
                    "{} differs at line {}:\n  want: {:?}\n  got:  {:?}",
                    name,
                    i + 1,
                    w.get(i),
                    g.get(i)
                );
            }
        }
        panic!("{} differs (trailing bytes)", name);
    }
}

#[test]
fn golden_phase0() {
    assert_golden("golden.delivery.yaml", &must_render(&fixtures(), 0));
}

#[test]
fn golden_phase1() {
    assert_golden("golden.phase1.delivery.yaml", &must_render(&fixtures(), 1));
}

#[test]
fn golden_phase2() {
    assert_golden("golden.phase2.delivery.yaml", &must_render(&fixtures(), 2));
}

#[test]
fn render_is_order_independent() {
    let forward = fixtures();
    let mut rev = fixture_paths();
    rev.reverse();
    let reversed = unit::load_units(&rev).unwrap();
    for phase in 0..=2 {
        assert_eq!(
            must_render(&forward, phase),
            must_render(&reversed, phase),
            "phase {}",
            phase
        );
    }
}

#[test]
fn kill_switch_gates_orchestrate() {
    let got = must_render(&fixtures(), 0);
    let want = format!("    if: {}", render::KILL_SWITCH_EXPR);
    let job = &got[got.find("  orchestrate:\n").unwrap()..];
    assert!(job.find(&want).unwrap() < job.find("    runs-on:").unwrap());
}

#[test]
fn phase0_renders_only_orchestrate() {
    let got = must_render(&fixtures(), 0);
    let body = &got[got.find("\njobs:\n").unwrap()..];
    let jobs: Vec<&str> = body
        .lines()
        .filter(|l| {
            l.starts_with("  ")
                && !l.starts_with("   ")
                && l.ends_with(':')
                && !l.trim_start().starts_with('#')
        })
        .collect();
    assert_eq!(jobs, vec!["  orchestrate:"]);
    assert!(!got.contains("\n    environment:"));
}

#[test]
fn output_var_name_is_the_orchestrator_contract() {
    for (i, w) in [
        ("oauth-user-inspector", "oauth_user_inspector"),
        ("tabula-api", "tabula_api"),
        ("charts", "charts"),
        ("a.b/c", "a_b_c"),
    ] {
        assert_eq!(render::output_var_name(i), w);
    }
}

#[test]
fn write_atomic_is_idempotent() {
    let dir = tempdir("atomic");
    let path = format!("{}/sub/delivery.yaml", dir);
    let content = must_render(&fixtures(), 0);
    assert!(app::write_atomic(&path, &content).unwrap());
    assert!(!app::write_atomic(&path, &content).unwrap());
    assert_eq!(std::fs::read_to_string(&path).unwrap(), content);
    for e in std::fs::read_dir(format!("{}/sub", dir)).unwrap() {
        assert!(!e
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".delivery-gen-"));
    }
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn load_units_rejects_duplicate_names() {
    let dir = tempdir("dup");
    let body = r#"{"schema":1,"name":"dup","kind":"pulumi","run":"//a:up","environments":["development"],"github_environment":"e-{env}"}"#;
    let paths: Vec<String> = (0..2)
        .map(|i| {
            let p = format!("{}/u{}.delivery.json", dir, i);
            std::fs::write(&p, body).unwrap();
            p
        })
        .collect();
    assert!(unit::load_units(&paths)
        .unwrap_err()
        .contains("duplicate delivery unit name"));
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn discover_uses_bazel_and_fails_closed() {
    let bin = "/tmp/bin".to_string();
    let fake = |query: &'static str| {
        let bin = bin.clone();
        move |args: &[String]| -> Result<Vec<u8>, String> {
            match args[0].as_str() {
                "query" => Ok(query.as_bytes().to_vec()),
                "build" => Ok(Vec::new()),
                "info" => Ok(format!("{}\n", bin).into_bytes()),
                _ => Err(format!("unexpected bazel {:?}", args)),
            }
        }
    };
    let mut f = fake(
        "//pkg/one:alpha.delivery_unit\n//pkg/two:beta.delivery_unit\n//pkg/two:beta.delivery\n",
    );
    let paths = app::discover(&mut f).unwrap();
    assert_eq!(
        paths,
        vec![
            "/tmp/bin/pkg/one/alpha.delivery.json",
            "/tmp/bin/pkg/two/beta.delivery.json"
        ]
    );
    let mut f = fake("\n");
    assert!(app::discover(&mut f).is_err());
}

fn cloud_run_base() -> Unit {
    let mut wi = BTreeMap::new();
    for (k, v) in [
        ("app-name", "app"),
        ("env-prefix", "APP"),
        ("pulumi-dir", "app/infra"),
        ("service-name", "app"),
    ] {
        wi.insert(k.to_string(), Value::Str(v.to_string()));
    }
    Unit {
        schema: 1,
        name: "app".into(),
        kind: "cloud-run".into(),
        run: "//app:deploy".into(),
        environments: vec!["development".into()],
        github_environment: "app-{env}".into(),
        build_context: "app/".into(),
        image_repository_path: "app/api".into(),
        workflow_inputs: wi,
        ..Default::default()
    }
}

fn companion() -> Unit {
    Unit {
        schema: 1,
        name: "zitadel-apps".into(),
        kind: "pulumi".into(),
        run: "//z:up".into(),
        environments: vec!["development".into()],
        github_environment: "app-{env}".into(),
        ..Default::default()
    }
}

#[test]
fn phase1_rejects_declarations_that_would_render_a_broken_workflow() {
    let mut cases: Vec<(Vec<Unit>, &str)> = Vec::new();
    let mut u = cloud_run_base();
    u.companions = vec!["nope".into()];
    cases.push((vec![u], "not a declared delivery() unit"));
    let mut u = cloud_run_base();
    u.companions = vec!["other".into()];
    let mut o = companion();
    o.name = "other".into();
    cases.push((vec![u, o], "no reusable workflow registered"));
    let mut u = cloud_run_base();
    u.companions = vec!["zitadel-apps".into()];
    let mut c = companion();
    c.environments = vec!["production".into()];
    cases.push((vec![u, c], "declares no \"development\" rung"));
    let mut u = cloud_run_base();
    u.build_context.clear();
    cases.push((vec![u], "needs build_context and image_repository_path"));
    let mut u = cloud_run_base();
    u.build = "//app:image_push".into();
    cases.push((vec![u], "renders the Docker path only"));
    let mut u = cloud_run_base();
    u.workflow_inputs.remove("pulumi-dir");
    cases.push((vec![u], "missing required workflow_inputs"));
    let mut u = cloud_run_base();
    u.workflow_inputs
        .insert("extra".into(), Value::Arr(vec![Value::Str("a".into())]));
    cases.push((vec![u], "value [a] ([]interface {}) is not a scalar"));
    let mut u = cloud_run_base();
    u.workflow_inputs.insert("extra".into(), Value::Null);
    cases.push((vec![u], "value is null"));
    for (mut units, want) in cases {
        units.sort_by(|a, b| a.name.cmp(&b.name));
        let err = render_err(&units, 1);
        assert!(err.contains(want), "want {:?}, got {:?}", want, err);
    }
}

#[test]
fn phase2_rejects_declarations_that_would_render_a_broken_ladder() {
    let base = || {
        let mut wi = BTreeMap::new();
        for (k, v) in [
            ("app-name", "tabula"),
            ("env-prefix", "TABULA"),
            ("pulumi-dir", "tabula/infra/app"),
            ("service-name", "tabula-api"),
        ] {
            wi.insert(k.to_string(), Value::Str(v.to_string()));
        }
        Unit {
            schema: 1,
            name: "tabula-api".into(),
            kind: "cloud-run".into(),
            run: "//tabula/infra/app:deploy".into(),
            environments: vec![
                "development".into(),
                "nonproduction".into(),
                "production".into(),
            ],
            github_environment: "tabula-{env}".into(),
            shared_build: "tabula".into(),
            image_digest_output: "image-digest".into(),
            promotion: "release:tabula-api-v".into(),
            soak: true,
            workflow_inputs: wi,
            ..Default::default()
        }
    };
    let muts: Vec<(Mutation, &str)> = vec![
        (
            Box::new(|u| u.shared_build = "nope".into()),
            "no registered build job",
        ),
        (
            Box::new(|u| u.image_digest_output = "web-digest".into()),
            "EMPTY STRING",
        ),
        (
            Box::new(|u| u.github_environment = "tabula-app-{env}".into()),
            "fails the whole run at startup",
        ),
        (
            Box::new(|u| {
                u.promotion.clear();
                u.soak = false;
            }),
            "would then deliver on a PUSH",
        ),
        (
            Box::new(|u| u.environments = vec!["development".into()]),
            "no promotion rung to hold back",
        ),
    ];
    for (m, want) in muts {
        let mut u = base();
        m(&mut u);
        let err = render_err(&[u], 2);
        assert!(err.contains(want), "want {:?}, got {:?}", want, err);
    }
}

#[test]
fn group_by_app_gives_every_app_its_own_workflow() {
    let groups = render::group_by_app(&fixtures()).unwrap();
    let got: Vec<(String, Vec<String>)> = groups
        .iter()
        .map(|g| {
            (
                g.app.clone(),
                g.units.iter().map(|u| u.name.clone()).collect(),
            )
        })
        .collect();
    let want: Vec<(String, Vec<String>)> = vec![
        ("charts", vec!["charts"]),
        ("esp32-s3", vec!["esp32-s3"]),
        ("gravastar-mouse", vec!["gravastar-mouse-publish"]),
        (
            "oauth-user-inspector",
            vec![
                "oauth-user-inspector",
                "oauth-user-inspector-identity",
                "zitadel-apps",
            ],
        ),
        (
            "tabula",
            vec![
                "tabula-api",
                "tabula-build-stack",
                "tabula-dev-latest",
                "tabula-identity",
                "tabula-web",
            ],
        ),
        ("vitruvian", vec!["vitruvian"]),
    ]
    .into_iter()
    .map(|(a, us)| (a.to_string(), us.into_iter().map(String::from).collect()))
    .collect();
    assert_eq!(got, want);
    for g in &groups {
        assert_eq!(g.file, format!("delivery-{}.yaml", g.app));
    }
}

#[test]
fn group_by_app_refuses_couplings_across_apps() {
    let edits: Vec<(Edit, &str)> = vec![
        (Box::new(|us| us[0].app.clear()), "declares no app"),
        (Box::new(|us| us[0].app = "Tabula_App".into()), "lowercase"),
        (
            Box::new(|us| {
                for u in us.iter_mut().filter(|u| u.name == "tabula-web") {
                    u.app = "tabula-web".into();
                }
            }),
            "shared build",
        ),
        (
            Box::new(|us| {
                for u in us.iter_mut().filter(|u| u.name == "zitadel-apps") {
                    u.app = "platform".into();
                }
            }),
            "companion",
        ),
    ];
    for (edit, want) in edits {
        let mut us = fixtures();
        edit(&mut us);
        let err = render::group_by_app(&us).unwrap_err();
        assert!(err.contains(want), "want {:?}, got {:?}", want, err);
    }
}

#[test]
fn write_apps_prunes_only_generated_workflows() {
    let dir = tempdir("prune");
    let write = |name: &str, body: &str| std::fs::write(format!("{}/{}", dir, name), body).unwrap();
    write(
        "delivery.yaml",
        &format!("{}\nname: delivery\n", render::GENERATED_BANNER),
    );
    write(
        "delivery-gone.yaml",
        &format!("{}\nname: delivery-gone\n", render::GENERATED_BANNER),
    );
    write("delivery-drift.yaml", "name: delivery-drift\n");
    write("ci.yaml", &format!("{}\n", render::GENERATED_BANNER));

    let groups = render::group_by_app(&fixtures()).unwrap();
    let mut p = PinSource::fixed(pins());
    let (written, removed) = app::write_apps(&dir, &groups, 2, &mut p).unwrap();
    assert_eq!(written.len(), groups.len());
    assert_eq!(removed, vec!["delivery-gone.yaml", "delivery.yaml"]);
    for kept in ["delivery-drift.yaml", "ci.yaml"] {
        assert!(std::path::Path::new(&format!("{}/{}", dir, kept)).exists());
    }
    let (written, removed) = app::write_apps(&dir, &groups, 2, &mut p).unwrap();
    assert!(written.is_empty() && removed.is_empty());

    let mut us = fixtures();
    for u in us.iter_mut().filter(|u| u.name == "charts") {
        u.app = "drift".into();
    }
    let groups = render::group_by_app(&us).unwrap();
    match app::write_apps(&dir, &groups, 2, &mut p) {
        Err(GenError::Msg(m)) => assert!(m.contains("not generated"), "{}", m),
        other => panic!("want a refusal, got {:?}", other),
    }
    assert_eq!(
        std::fs::read_to_string(format!("{}/delivery-drift.yaml", dir)).unwrap(),
        "name: delivery-drift\n"
    );
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn dispatch_never_defaults_to_production() {
    for g in render::group_by_app(&fixtures()).unwrap() {
        let envs = render::dispatch_environments(&g.units);
        if envs.is_empty() {
            continue;
        }
        assert_ne!(envs[0], "production", "app {}", g.app);
        if envs.iter().any(|e| e == "production") {
            assert_eq!(envs.last().unwrap(), "production", "app {}", g.app);
        }
    }
}

#[test]
fn unpinned_action_is_a_panic_not_an_error() {
    let empty = Pins::load(&format!("{}/action-pins.yml", testdata())).unwrap();
    // A manifest missing actions/checkout: render must report it as the panic
    // the Go generator dies with.
    let dir = tempdir("pins");
    let p = format!("{}/pins.yml", dir);
    std::fs::write(&p, "uses: x/y@3d3c42e5aac5ba805825da76410c181273ba90b1\n").unwrap();
    let only_xy = Pins::load(&p).unwrap();
    assert!(empty.len() > only_xy.len());
    match render::render(&fixtures(), 0, WF, &only_xy) {
        Err(GenError::Panic(m)) => {
            assert!(m.contains("unpinned action \"actions/checkout\""), "{}", m)
        }
        other => panic!("want a panic, got {:?}", other.map(|_| ())),
    }
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn flags_parse_like_the_go_flag_package() {
    let mut err = Vec::new();
    let f = app::parse_flags(
        "gen",
        &["--phase=0x1".into(), "-out-dir".into(), "x".into()],
        &mut err,
    )
    .unwrap();
    assert_eq!((f.phase, f.out_dir.as_str()), (1, "x"));
    let mut err = Vec::new();
    assert_eq!(
        app::parse_flags("gen", &["-phase=two".into()], &mut err).err(),
        Some(2)
    );
    let text = String::from_utf8(err).unwrap();
    assert!(
        text.starts_with("invalid value \"two\" for flag -phase: parse error\nUsage of gen:\n"),
        "{}",
        text
    );
    let mut err = Vec::new();
    assert_eq!(
        app::parse_flags("gen", &["-h".into()], &mut err).err(),
        Some(0)
    );
}

fn tempdir(tag: &str) -> String {
    let d = std::env::temp_dir().join(format!(
        "delivery-gen-{}-{}-{}",
        tag,
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&d).unwrap();
    d.to_string_lossy().into_owned()
}

// --- the soak step: a failed rustc build fails closed, ALLOW_UNSOAKED=true
// still overrides it (the retired shell script had no build to fail) --------

/// The `run: |` body of every `*-require-dev-soak` job, de-indented.
fn soak_scripts(yaml: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = yaml;
    while let Some(i) = rest.find("-require-dev-soak:\n") {
        let job = &rest[i..];
        let end = job.find("\n\n").unwrap_or(job.len());
        let job = &job[..end];
        let run = job
            .find("        run: |\n")
            .expect("soak job has a run block");
        let body: Vec<&str> = job[run..]
            .lines()
            .skip(1)
            .take_while(|l| l.starts_with("          "))
            .map(|l| &l[10..])
            .collect();
        out.push(body.join("\n") + "\n");
        rest = &rest[i + end..];
    }
    out
}

#[test]
fn soak_step_shape() {
    let scripts = soak_scripts(&must_render(&fixtures(), 2));
    assert_eq!(
        scripts.len(),
        3,
        "the phase-2 fixtures carry three soak jobs"
    );
    for s in &scripts {
        let order = [
            "if ! {\n",
            "rustc --edition 2021 --crate-type lib --crate-name shell_compat ",
            "rustc --edition 2021 tools/ci/src/require_dev_soak/main.rs ",
            "}; then\n",
            "  if [ \"${ALLOW_UNSOAKED:-}\" = \"true\" ]; then\n",
            "::warning title=dev-soak gate bypassed::",
            "    exit 0\n",
            "  fi\n",
            "::error title=dev-soak gate could not run::rustc failed",
            "  exit 1\n",
            "fi\n",
            "\"$RUNNER_TEMP/require-dev-soak\"\n",
        ];
        let mut at = 0;
        for want in order {
            match s[at..].find(want) {
                Some(i) => at += i + want.len(),
                None => panic!("soak step lacks {want:?} (in order):\n{s}"),
            }
        }
    }
}

/// Run a soak step under GitHub's `bash -eo pipefail` with a fake rustc.
/// `build_ok` false makes rustc fail; true makes it write a binary that
/// prints RAN and exits 7, standing in for the real gate.
fn run_soak_step(script: &str, build_ok: bool, allow: Option<&str>) -> (i32, String) {
    let base = std::env::var("TEST_TMPDIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let d = base.join(format!(
        "soak-{}-{}",
        std::process::id(),
        N.fetch_add(1, std::sync::atomic::Ordering::SeqCst)
    ));
    let bin = d.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    let fake = if build_ok {
        "#!/usr/bin/env bash\nwhile [ $# -gt 0 ]; do [ \"$1\" = -o ] && out=\"$2\"; shift; done\nprintf '#!/bin/sh\\necho RAN\\nexit 7\\n' >\"$out\"\nchmod +x \"$out\"\n"
    } else {
        "#!/usr/bin/env bash\necho 'error: could not compile' >&2\nexit 1\n"
    };
    let rustc = bin.join("rustc");
    std::fs::write(&rustc, fake).unwrap();
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&rustc, std::fs::Permissions::from_mode(0o755)).unwrap();
    let step = d.join("step.sh");
    std::fs::write(&step, script).unwrap();
    let mut c = std::process::Command::new("bash");
    c.args(["--noprofile", "--norc", "-eo", "pipefail"])
        .arg(&step)
        .current_dir(&d)
        .env_clear()
        .env("PATH", format!("{}:/usr/bin:/bin", bin.display()))
        .env("RUNNER_TEMP", &d);
    if let Some(v) = allow {
        c.env("ALLOW_UNSOAKED", v);
    }
    let o = c.output().unwrap();
    let text =
        String::from_utf8_lossy(&o.stdout).into_owned() + &String::from_utf8_lossy(&o.stderr);
    (o.status.code().unwrap_or(-1), text)
}

#[test]
fn soak_step_build_failure_fails_closed() {
    for s in soak_scripts(&must_render(&fixtures(), 2)) {
        for allow in [Some("false"), Some("TRUE"), Some("1"), Some(""), None] {
            let (rc, out) = run_soak_step(&s, false, allow);
            assert_eq!(
                rc, 1,
                "ALLOW_UNSOAKED={allow:?} must not pass a failed build:\n{out}"
            );
            assert!(
                out.contains("::error title=dev-soak gate could not run::"),
                "{out}"
            );
            assert!(!out.contains("bypassed"), "{out}");
        }
    }
}

#[test]
fn soak_step_build_failure_allow_unsoaked_true_overrides() {
    for s in soak_scripts(&must_render(&fixtures(), 2)) {
        let (rc, out) = run_soak_step(&s, false, Some("true"));
        assert_eq!(rc, 0, "the break-glass must survive a failed build:\n{out}");
        assert!(
            out.contains("::warning title=dev-soak gate bypassed::"),
            "{out}"
        );
        assert!(!out.contains("RAN"), "nothing was built to run:\n{out}");
    }
}

#[test]
fn soak_step_built_gate_decides() {
    for s in soak_scripts(&must_render(&fixtures(), 2)) {
        // A successful build runs the gate, whose own status is the step's,
        // even with the override set (the gate itself honours it).
        for allow in [Some("true"), Some("false")] {
            let (rc, out) = run_soak_step(&s, true, allow);
            assert_eq!((rc, out.contains("RAN")), (7, true), "{out}");
            assert!(
                !out.contains("::error title=dev-soak gate could not run"),
                "{out}"
            );
        }
    }
}
