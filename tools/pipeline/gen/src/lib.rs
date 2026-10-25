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

//! //tools/pipeline/gen in Rust: reads pipeline_unit() declarations (or
//! `.pipeline.json` files with --units-dir) and writes the presubmit
//! workflow, the dynamic matrix, the units as JSON, or their dependency
//! order. Output, messages and exit codes match the Go tool (`:gen-go`)
//! byte for byte; the parity test holds it to that.

pub mod actionpins;
pub mod dag;
pub mod flags;
pub mod gojson;
pub mod gostr;
pub mod matrix;
pub mod render;
pub mod unit;
pub mod unitfile;

use std::io::Write;

use unit::{Unit, SCHEMA_VERSION};

/// Go's `unitOf`: a BUILD-file declaration as a generator unit.
pub fn unit_of(u: unitfile::Unit) -> Unit {
    Unit {
        schema: SCHEMA_VERSION,
        concurrency_group: format!("pipeline-{}", u.name),
        name: u.name,
        package: u.package,
        test_targets: Some(u.test_targets),
        tier: u.tier,
        runner: u.runner,
        persona: u.persona,
        timeout_minutes: u.timeout_minutes,
        depends_on: u.depends_on,
        needs_emulator: u.needs_emulator,
        artifacts: u.artifacts,
        env: u.env,
        build_flags: u.build_flags,
        tags: Vec::new(),
    }
}

/// Go's `parseUnitsFromBuildContent`.
pub fn parse_units_from_build_content(content: &str, pkg: &str) -> Result<Vec<Unit>, Vec<u8>> {
    Ok(unitfile::parse(content.as_bytes(), pkg)?
        .into_iter()
        .map(unit_of)
        .collect())
}

/// How a run ends: the exit code after everything has been written.
struct Out<'a> {
    stdout: &'a mut dyn Write,
    stderr: &'a mut dyn Write,
}

impl Out<'_> {
    fn fail(&mut self, m: &[u8]) -> i32 {
        let _ = self.stderr.write_all(m);
        let _ = self.stderr.write_all(b"\n");
        1
    }
    /// What the Go runtime printed for an unrecovered panic; exit 2.
    fn panic(&mut self, m: &str) -> i32 {
        let _ = write!(
            self.stderr,
            "panic: {m}\n\ngoroutine 1 [running]:\nmain.main()\n"
        );
        2
    }
}

fn units_from_dir(units_dir: &str) -> Result<Vec<Unit>, String> {
    let mut files = unit::find_unit_files(units_dir);
    if files.is_empty() {
        // Try reading JSON files directly in dir.
        if let Some(names) = gostr::read_dir_names(units_dir) {
            for n in names {
                if n.ends_with(".json") {
                    files.push(gostr::join(units_dir, &n));
                }
            }
        }
    }
    unit::load_units(&files).map_err(|e| format!("failed to load units from {units_dir}: {e}"))
}

/// The whole program. `argv0` is only used in the usage text.
pub fn run(argv0: &str, args: &[String], stdout: &mut dyn Write, stderr: &mut dyn Write) -> i32 {
    let mut o = Out { stdout, stderr };
    let f = match flags::parse(args) {
        Ok(f) => f,
        Err(flags::FlagError::Help) => {
            let _ = o.stderr.write_all(flags::usage(argv0).as_bytes());
            return 0;
        }
        Err(flags::FlagError::Bad(m)) => {
            let _ = writeln!(o.stderr, "{m}");
            let _ = o.stderr.write_all(flags::usage(argv0).as_bytes());
            return 2;
        }
    };

    let mut repo_root = f.repo_root.clone();
    if repo_root.is_empty() {
        match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
            Ok(ws) if !ws.is_empty() => repo_root = ws,
            _ => match gostr::getwd() {
                Ok(wd) => repo_root = wd,
                Err(e) => {
                    return o.fail(
                        format!(
                            "failed to get current working directory: {}",
                            gostr::errno_text(&e)
                        )
                        .as_bytes(),
                    )
                }
            },
        }
    }

    let units = if !f.units_dir.is_empty() {
        let mut d = f.units_dir.clone();
        if !gostr::is_abs(&d) {
            d = gostr::join(&repo_root, &d);
        }
        match units_from_dir(&d) {
            Ok(u) => u,
            Err(e) => return o.fail(e.as_bytes()),
        }
    } else {
        match unitfile::discover(&repo_root) {
            Ok(u) => u.into_iter().map(unit_of).collect(),
            Err(e) => {
                let mut m =
                    format!("failed to discover units in workspace {repo_root}: ").into_bytes();
                m.extend_from_slice(&e);
                return o.fail(&m);
            }
        }
    };

    let dag = match dag::build_dag(&units) {
        Ok(d) => d,
        Err(e) => return o.fail(format!("DAG validation failed: {e}").as_bytes()),
    };

    let mut format = f.format.as_str();
    if format == "matrix"
        && !f.output_file.is_empty()
        && (f.output_file.ends_with(".yaml") || f.output_file.ends_with(".yml"))
    {
        format = "workflow";
    }

    let generated = match format {
        "workflow" => {
            match render::render_presubmit_workflow(&units, &mut actionpins::load_default) {
                Ok(s) => s,
                Err(render::RenderError::Dag(e)) => {
                    return o.fail(format!("failed to render workflow: {e}").as_bytes())
                }
                Err(render::RenderError::Panic(m)) => return o.panic(&m),
            }
        }
        "json" => unit::marshal_indent(&units) + "\n",
        "dag" => match dag.topological_order() {
            Ok(ordered) => {
                let names: Vec<&str> = ordered.iter().map(|u| u.name.as_str()).collect();
                names.join("\n") + "\n"
            }
            Err(e) => return o.fail(format!("topological sort failed: {e}").as_bytes()),
        },
        _ => matrix::render_matrix_json(&matrix::compile_matrix(&units, &f.tier, &f.persona)),
    };

    let mut out_path = f.output_file.clone();
    if !out_path.is_empty() && !gostr::is_abs(&out_path) {
        out_path = gostr::join(&repo_root, &out_path);
    }

    if f.check {
        if out_path.is_empty() {
            return o.fail(b"--check requires --output-file");
        }
        let existing = match gostr::read_file(&out_path) {
            Ok(b) => b,
            Err(e) => {
                return o.fail(format!("failed to read output file {out_path}: {e}").as_bytes())
            }
        };
        if existing != generated.as_bytes() {
            return o.fail(
                format!(
                    "ERROR: {} is out of date with pipeline_unit() declarations. Run 'bazel run //tools/pipeline:gen' to update.",
                    f.output_file
                )
                .as_bytes(),
            );
        }
        let _ = writeln!(
            o.stdout,
            "✓ {} matches generated output cleanly",
            f.output_file
        );
        return 0;
    }

    if !out_path.is_empty() {
        if let Err(e) = gostr::mkdir_all(&gostr::dir(&out_path)) {
            return o.fail(format!("failed to create directory for {out_path}: {e}").as_bytes());
        }
        if let Err(e) = gostr::write_file(&out_path, generated.as_bytes()) {
            return o.fail(format!("failed to write output file: {e}").as_bytes());
        }
    } else {
        let _ = o.stdout.write_all(generated.as_bytes());
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pins() -> Result<actionpins::Pins, String> {
        static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("gen-rs-pins-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("action.yml");
        let sha = "0123456789abcdef0123456789abcdef01234567";
        let body: String = [
            "actions/checkout",
            "actions/setup-go",
            "actions/cache/restore",
            "actions/cache/save",
            "actions/upload-artifact",
        ]
        .iter()
        .map(|a| format!("    - uses: {a}@{sha} # v1\n"))
        .collect();
        std::fs::write(&p, body).unwrap();
        actionpins::load(p.to_str().unwrap())
    }

    fn render(units: &[Unit]) -> String {
        render::render_presubmit_workflow(units, &mut pins).unwrap()
    }

    fn unit(name: &str) -> Unit {
        Unit {
            schema: 1,
            name: name.into(),
            package: "a".into(),
            test_targets: Some(vec![format!("//{name}:t")]),
            tier: "L1".into(),
            runner: "ubuntu-26.04".into(),
            persona: "all".into(),
            timeout_minutes: 10,
            ..Default::default()
        }
    }

    #[test]
    fn jobs_are_gated_on_the_plan_and_fail_open() {
        let mut beta = unit("beta");
        beta.depends_on = vec!["alpha".into()];
        let got = render(&[unit("alpha"), beta]);
        assert!(got.contains("  plan:\n"));
        assert!(got.contains("ALL_UNITS: '[\"alpha\",\"beta\"]'"));
        assert!(got.contains("    needs: [plan, unit-alpha]\n"));
        assert!(got.contains("contains(fromJSON(needs.plan.outputs.units || '[]'), 'beta')"));
        assert!(got.contains("    needs: [plan, unit-alpha, unit-beta]\n"));
        assert!(got.contains("set +e -u -o pipefail"));
    }

    #[test]
    fn emulator_artifacts_flags_and_env_render() {
        let mut u = unit("with");
        u.needs_emulator = true;
        u.artifacts.insert("zebra".into(), "z.txt".into());
        u.artifacts.insert("alpha".into(), "app.apk".into());
        u.build_flags = vec!["--fat_apk_cpu=arm64-v8a,x86_64".into()];
        u.env.insert(
            "ANDROID_NDK_HOME".into(),
            "${{ env.ANDROID_NDK_ROOT }}".into(),
        );
        let got = render(&[u]);
        assert!(got.contains("uses: ./.github/actions/android-emulator"));
        assert!(got.contains("--test_env=ANDROID_SERIAL"));
        assert!(got.contains("extra_flags+=(\"--fat_apk_cpu=arm64-v8a,x86_64\")"));
        assert!(got.contains("      ANDROID_NDK_HOME: \"${{ env.ANDROID_NDK_ROOT }}\"\n"));
        assert!(got.contains("cp -L \"$bin/app.apk\" .pipeline-artifacts/alpha/"));
        assert!(got.find("name: alpha").unwrap() < got.find("name: zebra").unwrap());
        assert!(got.contains("--config=remotecache-ci"));
    }

    #[test]
    fn mac_runners() {
        for (r, want) in [
            ("xcode-27", true),
            ("macos-latest", true),
            ("macos-26", true),
            ("ubuntu-26.04", false),
            ("ubuntu-latest", false),
        ] {
            assert_eq!(render::is_mac_runner(r), want, "{r}");
        }
        let mut u = unit("mac");
        u.runner = "xcode-27".into();
        let got = render(&[u]);
        assert!(got.contains("extra_flags=(--config=macos-app)"));
        assert!(got.contains("Select the pinned Xcode"));
    }

    #[test]
    fn missing_pin_is_a_panic() {
        let err = render::render_presubmit_workflow(&[unit("a")], &mut || {
            Err("actionpins: failed to find pin manifest: x".into())
        });
        assert_eq!(
            err,
            Err(render::RenderError::Panic(
                "actionpins: failed to find pin manifest: x [recovered, repanicked]".into()
            ))
        );
    }

    #[test]
    fn build_content_units() {
        let units = parse_units_from_build_content(
            "pipeline_unit(\n    name = \"plain\",\n    test_targets = [\":lib\"],\n    tier = \"L1\",\n)\n",
            "pkg",
        )
        .unwrap();
        assert_eq!(units.len(), 1);
        assert!(units[0].artifacts.is_empty());
        assert_eq!(units[0].test_targets, Some(vec!["//pkg:lib".to_string()]));
        assert_eq!(units[0].timeout_minutes, 20);
    }
}
