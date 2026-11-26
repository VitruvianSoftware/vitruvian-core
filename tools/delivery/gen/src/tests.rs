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
    "gravastar-mouse-publish",
    "oauth-user-inspector-identity",
    "oauth-user-inspector",
    "pagerduty",
    "stripe",
    "vitruvian-atrium",
    "vitruvian-deck",
    "vitruvian-tabs-api",
    "vitruvian-tabs-build-stack",
    "vitruvian-tabs-dev-latest",
    "vitruvian-tabs-identity",
    "vitruvian-tabs-web",
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
        ("vitruvian-tabs-api", "vitruvian_tabs_api"),
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
            ("pulumi-dir", "apps/suites/vitruvian-tabs/infra/app"),
            ("service-name", "tabula-api"),
        ] {
            wi.insert(k.to_string(), Value::Str(v.to_string()));
        }
        Unit {
            schema: 1,
            name: "vitruvian-tabs-api".into(),
            kind: "cloud-run".into(),
            run: "//apps/suites/vitruvian-tabs/infra/app:deploy".into(),
            environments: vec![
                "development".into(),
                "nonproduction".into(),
                "production".into(),
            ],
            github_environment: "tabula-{env}".into(),
            shared_build: "vitruvian-tabs".into(),
            image_digest_output: "image-digest".into(),
            promotion: "release:vitruvian-tabs-api-v".into(),
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
            Box::new(|u| u.github_environment = "vitruvian-tabs-app-{env}".into()),
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
        ("gravastar-mouse", vec!["gravastar-mouse-publish"]),
        (
            "oauth-user-inspector",
            vec![
                "oauth-user-inspector",
                "oauth-user-inspector-identity",
                "zitadel-apps",
            ],
        ),
        ("pagerduty", vec!["pagerduty"]),
        ("stripe", vec!["stripe"]),
        ("vitruvian-atrium", vec!["vitruvian-atrium"]),
        ("vitruvian-deck", vec!["vitruvian-deck"]),
        (
            "vitruvian-tabs",
            vec![
                "vitruvian-tabs-api",
                "vitruvian-tabs-build-stack",
                "vitruvian-tabs-dev-latest",
                "vitruvian-tabs-identity",
                "vitruvian-tabs-web",
            ],
        ),
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
        (
            Box::new(|us| us[0].app = "Vitruvian_Tabs".into()),
            "lowercase",
        ),
        (
            Box::new(|us| {
                for u in us.iter_mut().filter(|u| u.name == "vitruvian-tabs-web") {
                    u.app = "vitruvian-tabs-web".into();
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

// PagerDuty's only environment is production, so there is no sandbox rung to default to.
const PRODUCTION_ONLY_APPS: &[&str] = &["pagerduty"];

#[test]
fn dispatch_never_defaults_to_production() {
    for g in render::group_by_app(&fixtures()).unwrap() {
        let envs = render::dispatch_environments(&g.units);
        if envs.is_empty() {
            continue;
        }
        if !(envs.len() == 1 && PRODUCTION_ONLY_APPS.contains(&g.app.as_str())) {
            assert_ne!(envs[0], "production", "app {}", g.app);
        }
        if envs.iter().any(|e| e == "production") {
            assert_eq!(envs.last().unwrap(), "production", "app {}", g.app);
        }
    }
}

/// A hand-started run of a branch must never reach a job: every dispatch arm
/// the generator writes also requires the run to come from main. Checks every
/// app's real rendered workflow, not one fixture, so a new arm that forgets
/// the gate fails here.
#[test]
fn every_dispatch_arm_requires_main() {
    let arm = "github.event_name == 'workflow_dispatch'";
    let gated = format!("{} && {}", arm, render::DISPATCH_FROM_MAIN);
    let mut arms = 0;
    for g in render::group_by_app(&fixtures()).unwrap() {
        let yaml = must_render(&g.units, 2);
        for line in yaml.lines().filter(|l| l.trim_start().starts_with("if:")) {
            let n = line.matches(arm).count();
            arms += n;
            assert_eq!(
                line.matches(gated.as_str()).count(),
                n,
                "app {}: a dispatch arm without the main gate: {}",
                g.app,
                line.trim()
            );
        }
    }
    assert!(
        arms > 0,
        "no dispatch arm rendered; the test checks nothing"
    );
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

// --- the promotion rung's companion waits on the soak gate (#4176) ---------

/// The body of job `name` in a rendered workflow, up to the next blank line.
fn job_block<'a>(yaml: &'a str, name: &str) -> &'a str {
    let head = format!("\n  {name}:\n");
    let i = yaml.find(&head).unwrap_or_else(|| panic!("no job {name}"));
    let job = &yaml[i + 1..];
    &job[..job.find("\n\n").unwrap_or(job.len())]
}

#[test]
fn promotion_companion_needs_the_soak_verdict() {
    let yaml = must_render(&fixtures(), 2);
    let soak = "oauth-user-inspector-require-dev-soak";
    let job = job_block(&yaml, "zitadel-apps-nonproduction");
    assert!(
        job.contains(&format!("    needs: [{soak}]\n")),
        "the nonproduction expand must wait for the soak gate:\n{job}"
    );
    let cond = job
        .lines()
        .find(|l| l.starts_with("    if: "))
        .expect("companion has an if:");
    assert!(
        cond.contains(&format!("needs.{soak}.result == 'success'")),
        "and check its verdict explicitly (an if: replaces success()):\n{cond}"
    );
    // The development rung has no soak gate to wait for, and production
    // already follows the nonproduction deploy.
    for other in ["zitadel-apps-development", "zitadel-apps-production"] {
        assert!(
            !job_block(&yaml, other).contains(soak),
            "{other} must not depend on the soak gate"
        );
    }
}

#[test]
fn soak_job_outlives_the_gates_wait() {
    let yaml = must_render(&fixtures(), 2);
    let job = job_block(&yaml, "oauth-user-inspector-require-dev-soak");
    // require_dev_soak waits up to WAIT_SECONDS (2400 s = 40 min) for a
    // development deploy still running; a shorter job timeout would kill it
    // mid-wait with no verdict.
    assert!(job.contains("    timeout-minutes: 50\n"), "{job}");
}

/// Each Stripe rung takes only its own mode's key: sandbox test, production
/// live. These are the lines that make it so; a regeneration that loses one of
/// them would let a rung apply the other mode's key, apply before the key-mode
/// check runs, or walk a push into production without a sandbox apply.
#[test]
fn stripe_rungs_accept_only_their_own_key_mode() {
    let us: Vec<Unit> = fixtures()
        .into_iter()
        .filter(|u| u.name == "stripe")
        .collect();
    let got = must_render(&us, 2);
    let after_sandbox = got
        .split("\n  stripe-sandbox:\n")
        .nth(1)
        .expect("no stripe-sandbox job rendered");
    let (sandbox, production) = after_sandbox
        .split_once("\n  stripe-production:\n")
        .expect("no stripe-production job rendered after stripe-sandbox");

    for (job, env, mode, accept, refuse) in [
        (sandbox, "sandbox", "test", "sk_test_*|rk_test_*", "live"),
        (
            production,
            "production",
            "live",
            "sk_live_*|rk_live_*",
            "test",
        ),
    ] {
        for want in [
            format!("    environment: stripe-{}\n", env),
            format!("            {}) ;;\n", accept),
            format!("            *) echo \"::error::STRIPE_API_KEY in the stripe-{} environment is not a {}-mode secret key", env, mode),
            format!("          if [ \"$mode\" != \"{}\" ]; then\n", mode),
            format!("          stack: {}\n", env),
            "          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}\n".to_string(),
            "          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}\n".to_string(),
        ] {
            assert!(job.contains(&want), "stripe-{} job lacks {:?}", env, want);
        }
        // The only accepted keys are this rung's mode: no case arm admits the other.
        assert!(
            !job.contains(&format!("sk_{}_*", refuse))
                && !job.contains(&format!("rk_{}_*", refuse)),
            "stripe-{} accepts a {}-mode key",
            env,
            refuse
        );
        // The guard runs before Pulumi, and every Pulumi step waits on it.
        let guard = job.find("id: key").unwrap();
        let up = job
            .find("uses: ./.github/actions/pulumi-run-captured")
            .unwrap();
        assert!(
            guard < up,
            "stripe-{}: the key check must run before pulumi up",
            env
        );
        assert_eq!(
            job.matches("if: steps.key.outputs.present == 'true'\n")
                .count(),
            4,
            "stripe-{}: Go, Pulumi, pulumi up and the applied marker must each wait on the key check",
            env
        );
        // A Stripe key, never a cloud identity.
        assert!(!job.contains("id-token: write"));
        assert!(
            !job.lines()
                .any(|l| !l.trim_start().starts_with('#') && l.contains("--show-secrets")),
            "nothing in the stripe-{} job may print secret outputs",
            env
        );
    }

    // Production starts on a push only after the sandbox REALLY applied in the
    // same run: a sandbox rung that skipped for want of a key succeeds, so
    // result == 'success' alone would walk the push into production.
    assert!(
        sandbox.contains("    outputs:\n      applied: ${{ steps.applied.outputs.applied }}\n"),
        "stripe-sandbox must export whether it applied"
    );
    assert!(production.contains("    needs: [orchestrate, stripe-sandbox]\n"));
    let cond = production
        .lines()
        .find(|l| l.starts_with("    if: "))
        .expect("stripe-production has no if:");
    assert!(
        cond.contains("needs.stripe-sandbox.result == 'success' && needs.stripe-sandbox.outputs.applied == 'true'"),
        "stripe-production's push arm must wait on the sandbox having applied: {}",
        cond
    );
    // The applied marker is only written once pulumi up exited 0.
    let marker = sandbox.find("id: applied").unwrap();
    assert!(sandbox.find("id: pulumi").unwrap() < marker);
}

#[test]
fn pagerduty_rung_checks_token_and_rejects_unknown_env() {
    let mut pd: Vec<Unit> = fixtures()
        .into_iter()
        .filter(|u| u.name == "pagerduty")
        .collect();
    assert_eq!(pd.len(), 1);
    let got = must_render(&pd, 2);
    let job = got
        .split("\n  pagerduty-production:\n")
        .nth(1)
        .expect("no pagerduty-production job rendered");

    for want in [
        "    timeout-minutes: 20\n",
        "    permissions:\n      contents: read\n",
        "    environment: pagerduty-production\n",
        "    env:\n      GOWORK: off\n",
        "echo \"::notice::No PAGERDUTY_TOKEN in the pagerduty-production environment yet, so nothing was applied. See infrastructure/pulumi/platform/pagerduty/README.md.\"",
        "          go-version-file: infrastructure/pulumi/platform/pagerduty/go.mod\n",
        "          cache-dependency-path: infrastructure/pulumi/platform/pagerduty/go.sum\n",
        "          working-directory: infrastructure/pulumi/platform/pagerduty\n",
        "          stack: production\n",
        "          pulumi-access-token: ${{ secrets.PULUMI_ACCESS_TOKEN }}\n",
    ] {
        assert!(job.contains(want), "pagerduty-production lacks {want:?}:\n{job}");
    }

    let guard = job.find("id: key").expect("token presence check");
    let up = job
        .find("uses: ./.github/actions/pulumi-run-captured")
        .expect("pulumi-run-captured step");
    assert!(guard < up, "token check must precede pulumi up");
    assert_eq!(
        job.matches("if: steps.key.outputs.present == 'true'\n")
            .count(),
        3,
        "Go setup, Pulumi install, and pulumi up must wait on the token check"
    );
    assert!(!job.contains("id-token: write"));
    assert!(
        !job.lines()
            .any(|l| !l.trim_start().starts_with('#') && l.contains("--show-secrets")),
        "nothing in pagerduty-production may print secret outputs"
    );

    pd[0].environments = vec!["sandbox".into()];
    let err = render_err(&pd, 2);
    assert!(
        err.contains("render_pagerduty_steps knows only production"),
        "unexpected error: {err}"
    );
}

#[test]
fn path_only_workflows_use_no_bazel_fast_path_and_fall_through() {
    // Single-unit path-only group (stripe): uses filter: blob:none + build-ci-tool
    // fast path and gates setup-bazel + manifest + upload on fast != 'false'.
    let stripe: Vec<Unit> = fixtures()
        .into_iter()
        .filter(|u| u.name == "stripe")
        .collect();
    let got = must_render(&stripe, 2);
    let orch = got
        .split_once("\n  stripe-sandbox:\n")
        .expect("stripe-sandbox job follows orchestrate")
        .0;
    for want in [
        "          filter: blob:none\n",
        "      affected_stripe: ${{ steps.manifest.outputs.affected_stripe || steps.fast_stripe.outputs.affected }}\n",
        "        tool: resolve_deploy_base\n",
        "        tool: resolve_unit_bases\n",
        "        tool: deploy_affected\n",
        "      - name: Fast path check (stripe)\n",
        "        id: fast_stripe\n",
        "          EXTRA_PATH_REGEX: 'infrastructure/pulumi/platform/stripe/'\n",
        "      - if: steps.fast_stripe.outputs.affected != 'false'\n        uses: ./.github/actions/setup-bazel\n",
        "      - name: Compute the delivery manifest\n        id: manifest\n        if: steps.fast_stripe.outputs.affected != 'false'\n",
        "      - name: Upload the delivery manifest\n        if: steps.fast_stripe.outputs.affected != 'false'\n",
    ] {
        assert!(orch.contains(want), "single-unit path-only orchestrate lacks {want:?}:\n{orch}");
    }
    assert!(
        !orch.contains("continue-on-error:"),
        "durable-base conformance forbids continue-on-error in delivery workflows"
    );

    // Multi-unit path-only group (oauth-user-inspector + identity + zitadel-apps).
    let oauth: Vec<Unit> = fixtures()
        .into_iter()
        .filter(|u| u.app == "oauth-user-inspector")
        .collect();
    assert_eq!(oauth.len(), 3);
    let got_oauth = must_render(&oauth, 2);
    let orch_oauth = got_oauth
        .split_once("\n  # ======== unit:")
        .expect("fan-out follows orchestrate")
        .0;
    let want_if = "steps.fast_oauth_user_inspector.outputs.affected != 'false' || steps.fast_oauth_user_inspector_identity.outputs.affected != 'false' || steps.fast_zitadel_apps.outputs.affected != 'false'";
    assert!(
        orch_oauth.contains(&format!(
            "      - if: {want_if}\n        uses: ./.github/actions/setup-bazel\n"
        )),
        "multi-unit setup-bazel must fall through if any unit != 'false':\n{orch_oauth}"
    );
    assert!(
        orch_oauth.contains("affected_oauth_user_inspector: ${{ steps.manifest.outputs.affected_oauth_user_inspector || steps.fast_oauth_user_inspector.outputs.affected }}\n")
            && orch_oauth.contains("affected_zitadel_apps: ${{ steps.manifest.outputs.affected_zitadel_apps || steps.fast_zitadel_apps.outputs.affected }}\n")
    );

    // Removing extra_paths from one unit drops back to full Bazel mode (no blob:none).
    let mut no_paths = stripe;
    no_paths[0].extra_paths.clear();
    let fallback = must_render(&no_paths, 2);
    assert!(!fallback.contains("filter: blob:none"));
    assert!(!fallback.contains("build-ci-tool"));
}
