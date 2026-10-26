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

//! gitops-validate.sh — schema + syntax validation for the ArgoCD GitOps tree
//! before it reaches main. Runs appset-render (goTemplate simulation), then
//! kubeconform over every manifest under gitops/argocd, including `.disabled`
//! manifests with their suffix stripped.

use shell_compat::{
    capture, cat, env_or, err, is_dir, is_file, mktemp_dir, os, out, status, subst, which,
};
use std::process::Command;

const SCHEMA_CONE: &[u8] = b"master-standalone-strict";

fn parse_count(summary: &[u8], key: &[u8]) -> Option<i64> {
    for line in summary.split(|&c| c == b'\n') {
        if let Some(pos) = line.windows(key.len()).position(|w| w == key) {
            let after = &line[pos + key.len()..];
            let num_bytes: Vec<u8> = after
                .iter()
                .copied()
                .skip_while(|&c| c == b' ')
                .take_while(|c| c.is_ascii_digit())
                .collect();
            if let Ok(s) = std::str::from_utf8(&num_bytes) {
                return s.parse().ok();
            }
        }
    }
    None
}

fn extract_valid(summary: &[u8]) -> Option<i64> {
    parse_count(summary, b"Valid:")
}

fn extract_skipped(summary: &[u8]) -> Option<i64> {
    parse_count(summary, b"Skipped:")
}

fn clone_shallow(url: &[u8], dest: &[u8], cone: &[u8]) -> bool {
    for attempt in 1..=3 {
        let _ = std::fs::remove_dir_all(shell_compat::path(dest));
        let ok = if !cone.is_empty() {
            let rc = status(
                106,
                Command::new("git")
                    .arg("clone")
                    .arg("--depth")
                    .arg("1")
                    .arg("--filter=blob:none")
                    .arg("--sparse")
                    .arg(os(url))
                    .arg(os(dest)),
                false,
            );
            if rc == 0 {
                status(
                    107,
                    Command::new("git")
                        .arg("-C")
                        .arg(os(dest))
                        .arg("sparse-checkout")
                        .arg("set")
                        .arg(os(cone)),
                    false,
                ) == 0
            } else {
                false
            }
        } else {
            status(
                110,
                Command::new("git")
                    .arg("clone")
                    .arg("--depth")
                    .arg("1")
                    .arg(os(url))
                    .arg(os(dest)),
                false,
            ) == 0
        };
        if ok {
            return true;
        }
        err(&cat(&[
            b"gitops-validate: clone of ",
            url,
            b" failed (attempt ",
            attempt.to_string().as_bytes(),
            b"/3), retrying...\n",
        ]));
        std::thread::sleep(std::time::Duration::from_secs(5));
    }
    err(&cat(&[
        b"gitops-validate: giving up cloning ",
        url,
        b" after 3 attempts\n",
    ]));
    false
}

fn find_yaml_files(dir: &[u8], exclude_values: bool) -> Vec<Vec<u8>> {
    let mut cmd = Command::new("find");
    cmd.arg(os(dir)).arg("-name").arg("*.yaml");
    if exclude_values {
        cmd.arg("-not").arg("-name").arg("values.yaml");
    } else {
        cmd.arg("-not").arg("-name").arg("values.yaml");
    }
    let r = capture(188, &mut cmd);
    let out_bytes = subst(r.stdout);
    if out_bytes.is_empty() {
        return Vec::new();
    }
    shell_compat::lines(&out_bytes)
}

fn find_disabled_files(dir: &[u8]) -> Vec<Vec<u8>> {
    let r = capture(
        229,
        Command::new("find")
            .arg(os(dir))
            .arg("-name")
            .arg("*.yaml.disabled"),
    );
    let out_bytes = subst(r.stdout);
    if out_bytes.is_empty() {
        return Vec::new();
    }
    let mut files = shell_compat::lines(&out_bytes);
    files.sort();
    files
}

fn run_kubeconform(files: &[Vec<u8>], schema_dir: &[u8], crd_catalog_dir: &[u8]) -> (i32, Vec<u8>) {
    if files.is_empty() {
        return (0, Vec::new());
    }
    let schema_loc1 = cat(&[
        schema_dir,
        b"/",
        SCHEMA_CONE,
        b"/{{.ResourceKind}}{{.KindSuffix}}.json",
    ]);
    let schema_loc2 = cat(&[
        crd_catalog_dir,
        b"/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json",
    ]);
    let mut cmd = Command::new("kubeconform");
    cmd.arg("-strict")
        .arg("-ignore-missing-schemas")
        .arg("-skip")
        .arg("ImageUpdater")
        .arg("-schema-location")
        .arg(os(&schema_loc1))
        .arg("-schema-location")
        .arg(os(&schema_loc2))
        .arg("-summary");
    for f in files {
        cmd.arg(os(f));
    }
    let r = capture(193, &mut cmd);
    let combined = cat(&[&r.stdout, &r.stderr]);
    (r.status, combined)
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let repo = if let Some(v) = shell_compat::env("BUILD_WORKSPACE_DIRECTORY") {
        if !v.is_empty() {
            v
        } else {
            let r = capture(
                41,
                Command::new("git").arg("rev-parse").arg("--show-toplevel"),
            );
            if r.ok() {
                subst(r.stdout)
            } else {
                let r2 = capture(41, &mut Command::new("pwd"));
                subst(r2.stdout)
            }
        }
    } else {
        let r = capture(
            41,
            Command::new("git").arg("rev-parse").arg("--show-toplevel"),
        );
        if r.ok() {
            subst(r.stdout)
        } else {
            let r2 = capture(41, &mut Command::new("pwd"));
            subst(r2.stdout)
        }
    };
    if std::env::set_current_dir(shell_compat::path(&repo)).is_err() {
        err(&cat(&[b"gitops-validate: cannot cd to ", &repo, b"\n"]));
        return 1;
    }

    // --- 1. goTemplate render simulation ---
    out(b"gitops-validate: simulating ApplicationSet goTemplate rendering ...\n");
    let rc = status(
        68,
        Command::new("go")
            .arg("run")
            .arg("./tools/gitops/appset-render")
            .arg("-root")
            .arg("gitops/argocd")
            .env("GOWORK", "off"),
        false,
    );
    if rc != 0 {
        return 1;
    }

    // --- 2. Schema validation ---
    if which(b"kubeconform").is_none() {
        err(b"gitops-validate: kubeconform not found on PATH\n");
        return 1;
    }

    let schema_dir = env_or("SCHEMA_DIR", b"/tmp/k8s-json-schema");
    let crd_catalog_dir = env_or("CRD_CATALOG_DIR", b"/tmp/crd-catalog");

    let schema_cone_dir = cat(&[&schema_dir, b"/", SCHEMA_CONE]);
    if !is_dir(&schema_cone_dir) {
        out(&cat(&[
            b"gitops-validate: cloning kubernetes-json-schema (sparse: ",
            SCHEMA_CONE,
            b")...\n",
        ]));
        if !clone_shallow(
            b"https://github.com/yannh/kubernetes-json-schema.git",
            &schema_dir,
            SCHEMA_CONE,
        ) {
            return 1;
        }
    }

    if !is_dir(&crd_catalog_dir) {
        out(b"gitops-validate: cloning CRDs-catalog...\n");
        if !clone_shallow(
            b"https://github.com/datreeio/CRDs-catalog.git",
            &crd_catalog_dir,
            b"",
        ) {
            return 1;
        }
    }

    // --- Guard: probe known schemas ---
    let probe1 = cat(&[&schema_dir, b"/", SCHEMA_CONE, b"/deployment-apps-v1.json"]);
    let probe2 = cat(&[&crd_catalog_dir, b"/argoproj.io/application_v1alpha1.json"]);
    for probe in [&probe1, &probe2] {
        if !is_file(probe) {
            err(&cat(&[
                b"gitops-validate: schema tree incomplete -- ",
                probe,
                b" is missing.\n",
            ]));
            err(b"gitops-validate: refusing to run, as -ignore-missing-schemas would\n");
            err(b"gitops-validate: turn the missing schemas into a silent pass.\n");
            return 1;
        }
    }

    out(b"gitops-validate: kubeconform over gitops/argocd ...\n");

    let files = find_yaml_files(b"gitops/argocd", true);
    let (rc, summary) = run_kubeconform(&files, &schema_dir, &crd_catalog_dir);
    if rc != 0 {
        out(&summary);
        out(b"\n");
        return 1;
    }
    out(&summary);
    out(b"\n");

    let valid = extract_valid(&summary);
    if valid.is_none() || valid == Some(0) {
        err(b"gitops-validate: no resource validated against a schema -- treating as\n");
        err(b"gitops-validate: a failure, not a pass. Check the -schema-location paths.\n");
        return 1;
    }

    // --- 3. The .disabled manifests ---
    let disabled = find_disabled_files(b"gitops/argocd");
    if !disabled.is_empty() {
        out(b"gitops-validate: kubeconform over .disabled manifests ...\n");
        let disabled_tmp = match mktemp_dir() {
            Ok(d) => d,
            Err(e) => {
                err(&cat(&[
                    b"gitops-validate: mktemp failed: ",
                    e.to_string().as_bytes(),
                    b"\n",
                ]));
                return 1;
            }
        };

        for f in &disabled {
            let rel = if f.starts_with(b"gitops/argocd/") {
                &f[b"gitops/argocd/".len()..]
            } else {
                f.as_slice()
            };
            let mut dest = rel.to_vec();
            if dest.ends_with(b".disabled") {
                dest.truncate(dest.len() - b".disabled".len());
            }
            let full_dest = cat(&[&disabled_tmp, b"/", &dest]);
            let dest_dir = shell_compat::dirname(&full_dest);
            let _ = shell_compat::mkdir_p(&dest_dir);
            let _ = std::fs::copy(shell_compat::path(f), shell_compat::path(&full_dest));
        }

        let disabled_files = find_yaml_files(&disabled_tmp, true);
        let (rc2, disabled_summary) =
            run_kubeconform(&disabled_files, &schema_dir, &crd_catalog_dir);
        if rc2 != 0 {
            out(&disabled_summary);
            out(b"\n");
            let _ = std::fs::remove_dir_all(shell_compat::path(&disabled_tmp));
            return 1;
        }
        out(&disabled_summary);
        out(b"\n");

        let disabled_count = disabled.len();
        let disabled_valid = extract_valid(&disabled_summary);
        let disabled_skipped = extract_skipped(&disabled_summary);

        if disabled_valid.is_none() || disabled_valid == Some(0) {
            err(&cat(&[
                b"gitops-validate: found ",
                disabled_count.to_string().as_bytes(),
                b" .disabled manifest(s) but validated\n",
            ]));
            err(b"gitops-validate: none of them -- treating as a failure, not a pass.\n");
            let _ = std::fs::remove_dir_all(shell_compat::path(&disabled_tmp));
            return 1;
        }
        if disabled_skipped.is_none() || disabled_skipped != Some(0) {
            let skip_s = disabled_skipped
                .map(|n| n.to_string())
                .unwrap_or_else(|| "?".to_string());
            err(&cat(&[
                b"gitops-validate: ",
                skip_s.as_bytes(),
                b" .disabled manifest(s) were SKIPPED rather than\n",
            ]));
            err(b"gitops-validate: validated. A skip exits 0 under -ignore-missing-schemas, so this\n");
            err(b"gitops-validate: would otherwise be a green check that checked less than it appears.\n");
            err(b"gitops-validate: Either a CRD is missing from the catalog, or a file stopped parsing.\n");
            let _ = std::fs::remove_dir_all(shell_compat::path(&disabled_tmp));
            return 1;
        }

        let _ = std::fs::remove_dir_all(shell_compat::path(&disabled_tmp));
    }

    out(b"gitops-validate: OK\n");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_valid_from_summary() {
        let summary = b"Summary: 102 resources found in 48 files - Valid: 101, Invalid: 0, Errors: 0, Skipped: 1\n";
        assert_eq!(extract_valid(summary), Some(101));
    }

    #[test]
    fn extract_valid_zero() {
        let summary = b"Summary: 0 resources found - Valid: 0, Invalid: 0, Errors: 0, Skipped: 0\n";
        assert_eq!(extract_valid(summary), Some(0));
    }

    #[test]
    fn extract_valid_missing() {
        let summary = b"no valid line here at all\n";
        assert_eq!(extract_valid(summary), None);
    }

    #[test]
    fn extract_skipped_from_summary() {
        let summary = b"Summary: 9 resources found - Valid: 9, Invalid: 0, Errors: 0, Skipped: 0\n";
        assert_eq!(extract_skipped(summary), Some(0));
    }

    #[test]
    fn extract_skipped_nonzero() {
        let summary = b"Summary: 10 resources - Valid: 8, Invalid: 0, Errors: 0, Skipped: 2\n";
        assert_eq!(extract_skipped(summary), Some(2));
    }

    #[test]
    fn extract_skipped_missing() {
        let summary = b"nothing here\n";
        assert_eq!(extract_skipped(summary), None);
    }

    #[test]
    fn extract_valid_multiline() {
        let summary = b"some preamble\nValid: 42, Invalid: 0\nSkipped: 3\n";
        assert_eq!(extract_valid(summary), Some(42));
        assert_eq!(extract_skipped(summary), Some(3));
    }

    #[test]
    fn parse_count_leading_spaces() {
        let summary = b"  Valid:  15, Skipped:   0\n";
        assert_eq!(extract_valid(summary), Some(15));
        assert_eq!(extract_skipped(summary), Some(0));
    }

    #[test]
    fn schema_cone_is_correct() {
        assert_eq!(SCHEMA_CONE, b"master-standalone-strict");
    }

    #[test]
    fn clone_shallow_retries_on_bad_url() {
        // A non-existent path should fail all 3 attempts and return false.
        // Using a file:// URL to a path that does not exist avoids any network.
        let dest = cat(&[&shell_compat::tmpdir(), b"/gitops-validate-test-clone"]);
        let result = clone_shallow(b"file:///nonexistent/repo.git", &dest, b"");
        assert!(!result);
        let _ = std::fs::remove_dir_all(shell_compat::path(&dest));
    }

    #[test]
    fn disabled_suffix_strip() {
        let f = b"gitops/argocd/platform/foo/bar.yaml.disabled";
        let rel = &f[b"gitops/argocd/".len()..];
        let mut dest = rel.to_vec();
        if dest.ends_with(b".disabled") {
            dest.truncate(dest.len() - b".disabled".len());
        }
        assert_eq!(dest, b"platform/foo/bar.yaml");
    }

    #[test]
    fn disabled_suffix_strip_no_prefix() {
        let f = b"something/else.yaml.disabled";
        let mut dest = f.to_vec();
        if dest.ends_with(b".disabled") {
            dest.truncate(dest.len() - b".disabled".len());
        }
        assert_eq!(dest, b"something/else.yaml");
    }
}
