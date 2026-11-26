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

//! Black-box tests for //tools/ci:foundation_leaf_guard, run the way the
//! deploy workflows run it (from the checkout root, inputs as arguments), plus
//! structural checks that both deploy workflows actually put it in front of
//! everything else (#4279).

use ci_testkit::{bin, workflow_job_text, workflow_jobs, write, Output, Run, TempDir};

const PROJ: &str = "infrastructure/pulumi/foundation/gcp-projects";
const APP: &str = "infrastructure/pulumi/foundation/gcp-app-infra";

/// A checkout with the two stages' real leaf layout: gcp-projects has a
/// `shared` leaf per business unit, gcp-app-infra does not.
fn checkout() -> TempDir {
    let d = TempDir::new();
    for bu in ["business_unit_1", "business_unit_2"] {
        for env in ["shared", "development", "nonproduction", "production"] {
            write(
                d.join(format!("{PROJ}/{bu}/{env}/Pulumi.yaml")),
                "name: x\n",
            );
        }
        for env in ["development", "nonproduction", "production"] {
            write(d.join(format!("{APP}/{bu}/{env}/Pulumi.yaml")), "name: x\n");
        }
    }
    // A directory that looks like a leaf but is not a Pulumi project.
    write(
        d.join(format!("{PROJ}/modules/development/main.go")),
        "package x\n",
    );
    write(
        d.join(format!("{PROJ}/business_unit_3/README.md")),
        "no leaves\n",
    );
    d
}

fn guard(root: &TempDir, args: [&str; 4]) -> Output {
    Run::new(&bin("BIN")).cwd(root.path()).args(args).go()
}

fn refused(o: &Output, why: &str) {
    assert_eq!(o.code, 1, "{o:?}");
    assert_eq!(
        o.stdout,
        format!("::error::foundation leaf guard: refusing this deploy: {why}. Only the stage's own leaves can be deployed from this workflow (#4279).\n")
    );
}

#[test]
fn every_real_leaf_passes() {
    let c = checkout();
    for bu in ["business_unit_1", "business_unit_2"] {
        for env in ["shared", "development", "nonproduction", "production"] {
            let o = guard(&c, ["gcp-projects", PROJ, bu, env]);
            assert_eq!(o.code, 0, "{bu}/{env}: {o:?}");
            assert_eq!(
                o.stdout,
                format!("foundation leaf guard: OK ({PROJ}/{bu}/{env})\n")
            );
        }
        for env in ["development", "nonproduction", "production"] {
            let o = guard(&c, ["gcp-app-infra", APP, bu, env]);
            assert_eq!(o.code, 0, "{bu}/{env}: {o:?}");
        }
    }
}

#[test]
fn another_working_directory_is_refused() {
    let c = checkout();
    for wd in [
        APP,
        "infrastructure/pulumi/foundation/gcp-org/envs/shared",
        "infrastructure/pulumi/platform/repo-config",
        "infrastructure/pulumi/foundation/gcp-projects/",
        "./infrastructure/pulumi/foundation/gcp-projects",
        "infrastructure/pulumi/foundation/gcp-projects/../gcp-app-infra",
        "",
    ] {
        let o = guard(&c, ["gcp-projects", wd, "business_unit_1", "development"]);
        refused(&o, &format!("working-directory must be {PROJ}, got '{wd}'"));
    }
    // And the other way round: the app stage only takes its own root.
    let o = guard(
        &c,
        ["gcp-app-infra", PROJ, "business_unit_1", "development"],
    );
    refused(
        &o,
        &format!("working-directory must be {APP}, got '{PROJ}'"),
    );
}

#[test]
fn a_business_unit_that_is_not_business_unit_n_is_refused() {
    let c = checkout();
    for bu in [
        "../business_unit_1",
        "business_unit_1/..",
        "business_unit_1/development/..",
        "modules",
        "business_unit_01",
        "business_unit_",
        "",
    ] {
        let o = guard(&c, ["gcp-projects", PROJ, bu, "development"]);
        refused(
            &o,
            &format!("business-unit must be business_unit_<n>, got '{bu}'"),
        );
    }
}

#[test]
fn an_unknown_environment_is_refused() {
    // A workflow_call takes `environment` as a free string.
    let c = checkout();
    for env in ["dev", "../shared", "production/..", "Production", ""] {
        let o = guard(&c, ["gcp-projects", PROJ, "business_unit_1", env]);
        refused(
            &o,
            &format!("environment must be one of shared, development, nonproduction, production, got '{env}'"),
        );
    }
}

#[test]
fn a_leaf_that_does_not_exist_is_refused() {
    let c = checkout();
    // business_unit_3 has no leaves; gcp-app-infra has no `shared` leaf.
    let o = guard(&c, ["gcp-projects", PROJ, "business_unit_3", "development"]);
    refused(
        &o,
        &format!("no Pulumi project at {PROJ}/business_unit_3/development/Pulumi.yaml"),
    );
    let o = guard(&c, ["gcp-app-infra", APP, "business_unit_1", "shared"]);
    refused(
        &o,
        &format!("no Pulumi project at {APP}/business_unit_1/shared/Pulumi.yaml"),
    );
}

#[test]
fn a_symlinked_pulumi_yaml_is_refused() {
    let c = checkout();
    let leaf = c.join(format!("{PROJ}/business_unit_2/development"));
    std::fs::remove_file(leaf.join("Pulumi.yaml")).unwrap();
    std::os::unix::fs::symlink("/etc/hostname", leaf.join("Pulumi.yaml")).unwrap();
    let o = guard(&c, ["gcp-projects", PROJ, "business_unit_2", "development"]);
    refused(
        &o,
        &format!("no Pulumi project at {PROJ}/business_unit_2/development/Pulumi.yaml"),
    );
}

#[test]
fn an_unknown_stage_or_wrong_arguments_are_refused() {
    let c = checkout();
    let o = guard(&c, ["gcp-org", PROJ, "business_unit_1", "development"]);
    refused(
        &o,
        "unknown stage 'gcp-org' (known: gcp-projects, gcp-app-infra)",
    );
    let o = Run::new(&bin("BIN"))
        .cwd(c.path())
        .args(["gcp-projects", PROJ, "business_unit_1"])
        .go();
    assert_eq!(o.code, 1, "{o:?}");
    assert!(
        o.stdout
            .starts_with("::error::foundation-leaf-guard: usage:"),
        "{o:?}"
    );
}

// --- the workflows run it, first, ungated --------------------------------------

/// The workflow files, from the runfiles root (//:workflow_files).
fn workflow(name: &str) -> String {
    let p = std::env::current_dir()
        .unwrap()
        .join(".github/workflows")
        .join(name);
    std::fs::read_to_string(&p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))
}

/// Every job in `yaml` other than `leaf-guard` waits for it, directly or
/// through a job that does.
fn assert_every_job_waits_for_the_guard(name: &str, yaml: &str) {
    let jobs = workflow_jobs(yaml);
    assert!(
        jobs.iter().any(|j| j.id == "leaf-guard"),
        "{name}: no leaf-guard job"
    );
    let needs = |id: &str| -> Vec<String> {
        let line = jobs
            .iter()
            .find(|j| j.id == id)
            .map(|j| j.needs.clone())
            .unwrap_or_default();
        let list = line.trim_start().trim_start_matches("needs:").trim();
        list.trim_matches(|c| c == '[' || c == ']')
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect()
    };
    for job in jobs.iter().filter(|j| j.id != "leaf-guard") {
        let mut seen = vec![job.id.clone()];
        let mut todo = needs(&job.id);
        let mut found = false;
        while let Some(n) = todo.pop() {
            if n == "leaf-guard" {
                found = true;
                break;
            }
            if !seen.contains(&n) {
                seen.push(n.clone());
                todo.extend(needs(&n));
            }
        }
        assert!(
            found,
            "{name}: job '{}' does not wait for leaf-guard",
            job.id
        );
    }
}

fn assert_guard_job(name: &str, yaml: &str, stage: &str) {
    let job = workflow_job_text(yaml, "leaf-guard");
    // Ungated and keyless: no Environment, no cloud identity, no secrets.
    for banned in ["environment:", "id-token", "secrets.", "gcp-auth"] {
        assert!(
            !job.contains(banned),
            "{name}: leaf-guard job has {banned}:\n{job}"
        );
    }
    assert!(
        job.contains("tool: foundation_leaf_guard"),
        "{name}:\n{job}"
    );
    // The inputs reach the guard through env, never spliced into the shell,
    // and they are the same `a || b` values every other job runs with.
    let run = format!(
        "run: '\"$LEAF_GUARD_BIN\" {stage} \"$WORKING_DIRECTORY\" \"$BUSINESS_UNIT\" \"$LEAF_ENVIRONMENT\"'"
    );
    assert!(
        job.contains(&run),
        "{name}: guard step is not\n  {run}\n{job}"
    );
    for env in [
        "WORKING_DIRECTORY: ${{ inputs['working-directory'] || inputs.working_directory }}",
        "BUSINESS_UNIT: ${{ inputs['business-unit'] || inputs.business_unit }}",
        "LEAF_ENVIRONMENT: ${{ inputs.environment }}",
    ] {
        assert!(job.contains(env), "{name}: missing `{env}`:\n{job}");
    }
}

#[test]
fn the_projects_deploy_guards_its_inputs_before_anything_else() {
    let name = "foundation-proj-deploy.yaml";
    let yaml = workflow(name);
    assert_guard_job(name, &yaml, "gcp-projects");
    assert_every_job_waits_for_the_guard(name, &yaml);
}

#[test]
fn the_app_infra_deploy_guards_its_inputs_before_anything_else() {
    let name = "foundation-app-deploy.yaml";
    let yaml = workflow(name);
    assert_guard_job(name, &yaml, "gcp-app-infra");
    assert_every_job_waits_for_the_guard(name, &yaml);
}
