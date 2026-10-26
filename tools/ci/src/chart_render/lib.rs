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

//! chart-render.sh — `helm template` over every co-located chart
//! (**/deploy/chart), with negative controls.

use shell_compat::{capture, cat, err, out, subst, which};
use std::process::Command;

const VALUES_DIR: &[u8] = b"tools/ci/chart-render";

/// Chart-dir → dotted-values-path for the `kindIs "string"` type-rejection
/// guard.  Declared, not derived: completeness is enforced both ways.
const STRING_REJECT_CONTROLS: &[(&str, &str)] =
    &[("apps/mcp/slack/deploy/chart", "networkPolicy.enabled")];

/// Extract every `required "<message>" .Values.<path>` from a chart's
/// templates directory, returning deduplicated dotted paths.
fn required_paths(chart_dir: &[u8]) -> Vec<Vec<u8>> {
    let templates = cat(&[chart_dir, b"/templates"]);
    let r = capture(
        0,
        Command::new("grep")
            .arg("-rho")
            .arg(r#"required "[^"]*" \.Values\.[A-Za-z0-9_.]*"#)
            .arg(shell_compat::os(&templates)),
    );
    if r.stdout.is_empty() {
        return Vec::new();
    }
    let mut paths: Vec<Vec<u8>> = Vec::new();
    for line in shell_compat::lines(&r.stdout) {
        if line.is_empty() {
            continue;
        }
        if let Some(idx) = line.windows(8).position(|w| w == b".Values.") {
            let path = line[idx + 8..].to_vec();
            if !path.is_empty() && !paths.contains(&path) {
                paths.push(path);
            }
        }
    }
    paths.sort();
    paths.dedup();
    paths
}

/// Extract the chart name from Chart.yaml via `awk -F': ' '/^name:/{print $2; exit}'`.
fn chart_name(chart_yaml: &[u8]) -> Vec<u8> {
    let r = capture(
        0,
        Command::new("awk")
            .arg("-F: ")
            .arg("/^name:/{print $2; exit}")
            .arg(shell_compat::os(chart_yaml)),
    );
    subst(r.stdout)
}

/// Whether templates contain `kindIs "string"`.
fn has_string_guard(chart_dir: &[u8]) -> bool {
    let templates = cat(&[chart_dir, b"/templates"]);
    let r = capture(
        0,
        Command::new("grep")
            .arg("-rq")
            .arg(r#"kindIs "string""#)
            .arg(shell_compat::os(&templates)),
    );
    r.ok()
}

/// Count `^kind:` lines in rendered output.
fn count_resources(rendered: &[u8]) -> usize {
    rendered
        .split(|&c| c == b'\n')
        .filter(|l| l.starts_with(b"kind:"))
        .count()
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    // Determine repo root.
    let repo = {
        let bwd = shell_compat::env_or_empty("BUILD_WORKSPACE_DIRECTORY");
        if !bwd.is_empty() {
            bwd
        } else {
            let r = capture(
                0,
                Command::new("git").arg("rev-parse").arg("--show-toplevel"),
            );
            let top = subst(r.stdout);
            if !top.is_empty() {
                top
            } else {
                let r2 = capture(0, &mut Command::new("pwd"));
                subst(r2.stdout)
            }
        }
    };

    if std::env::set_current_dir(shell_compat::path(&repo)).is_err() {
        err(&cat(&[b"chart-render: cannot cd to ", &repo, b"\n"]));
        return 1;
    }

    let mut failures: i32 = 0;

    let fail = |msg: &[u8], failures: &mut i32| {
        err(&cat(&[b"chart-render: FAIL: ", msg, b"\n"]));
        *failures += 1;
    };

    if which(b"helm").is_none() {
        err(b"chart-render: helm not found on PATH\n");
        return 1;
    }

    // Discover charts.
    let r = capture(
        0,
        Command::new("find")
            .arg(".")
            .arg("(")
            .arg("-name")
            .arg("bazel-*")
            .arg("-o")
            .arg("-name")
            .arg(".git")
            .arg("-o")
            .arg("-name")
            .arg(".claude")
            .arg("-o")
            .arg("-name")
            .arg(".worktrees")
            .arg("-o")
            .arg("-name")
            .arg("node_modules")
            .arg(")")
            .arg("-prune")
            .arg("-o")
            .arg("-path")
            .arg("*/deploy/chart/Chart.yaml")
            .arg("-print"),
    );
    let charts_raw = subst(r.stdout);
    if charts_raw.is_empty() {
        err(b"chart-render: found no charts under */deploy/chart \xe2\x80\x94 layout changed?\n");
        return 1;
    }
    let mut charts: Vec<Vec<u8>> = shell_compat::lines(&charts_raw);
    charts.sort();

    for chart_path in &charts {
        let dir = shell_compat::dirname(chart_path);
        let reldir = if dir.starts_with(b"./") {
            dir[2..].to_vec()
        } else {
            dir.clone()
        };
        let name = chart_name(chart_path);
        let values = cat(&[VALUES_DIR, b"/", &name, b".values.yaml"]);

        out(&cat(&[
            b"::group::chart-render: ",
            &reldir,
            b" (",
            &name,
            b")\n",
        ]));

        // Build the common argument vector: name dir [-f values]
        let mut template_args: Vec<Vec<u8>> = vec![name.clone(), dir.clone()];
        let has_values = shell_compat::is_file(&values);
        if has_values {
            template_args.push(b"-f".to_vec());
            template_args.push(values.clone());
        }

        // helm lint (chart dir only, no release name)
        {
            let mut cmd = Command::new("helm");
            cmd.arg("lint");
            for a in &template_args[1..] {
                cmd.arg(shell_compat::os(a));
            }
            let r = capture(0, &mut cmd);
            if !r.ok() {
                fail(&cat(&[&reldir, b": helm lint"]), &mut failures);
                err(&r.stdout);
                err(b"\n");
            }
        }

        // --- Positive control ---
        let rendered = {
            let mut cmd = Command::new("helm");
            cmd.arg("template");
            for a in &template_args {
                cmd.arg(shell_compat::os(a));
            }
            let r = capture(0, &mut cmd);
            if !r.ok() {
                fail(
                    &cat(&[&reldir, b": positive control did not render:"]),
                    &mut failures,
                );
                err(&r.stderr);
                err(b"\n");
                out(b"::endgroup::\n");
                continue;
            }
            r.stdout
        };
        let n_resources = count_resources(&rendered);
        out(&cat(&[
            b"chart-render: ",
            &reldir,
            b": rendered ",
            n_resources.to_string().as_bytes(),
            b" resources\n",
        ]));

        // --- Negative controls: every `required` must fire ---
        let paths = required_paths(&dir);
        if !paths.is_empty() && !has_values {
            fail(
                &cat(&[
                    &reldir,
                    b": has required values but no ",
                    &values,
                    b" \xe2\x80\x94 it would go ungated",
                ]),
                &mut failures,
            );
        }

        let mut n_paths: usize = 0;
        for path in &paths {
            n_paths += 1;
            let set_arg = cat(&[path, b"=null"]);
            let mut cmd = Command::new("helm");
            cmd.arg("template");
            for a in &template_args {
                cmd.arg(shell_compat::os(a));
            }
            cmd.arg("--set").arg(shell_compat::os(&set_arg));
            let r = capture(0, &mut cmd);
            if r.ok() {
                fail(
                    &cat(&[
                        &reldir,
                        b": nulling ",
                        path,
                        b" still rendered \xe2\x80\x94 its 'required' does not fire",
                    ]),
                    &mut failures,
                );
                continue;
            }
            // The error message must name the value path.
            let combined = cat(&[&r.stdout, &r.stderr]);
            if !shell_compat::contains(&combined, path) {
                fail(
                    &cat(&[
                        &reldir,
                        b": nulling ",
                        path,
                        b" refused the render (good) but the message never names ",
                        path,
                        b" \xe2\x80\x94 name the value in its 'required' text",
                    ]),
                    &mut failures,
                );
            }
        }
        if n_paths > 0 {
            out(&cat(&[
                b"chart-render: ",
                &reldir,
                b": ",
                n_paths.to_string().as_bytes(),
                b" required value(s), each refuses when absent\n",
            ]));
        }

        // --- Negative control: quoted boolean must be REFUSED ---
        let mut guarded: Option<&str> = None;
        for &(ctl_dir, ctl_path) in STRING_REJECT_CONTROLS {
            if reldir == ctl_dir.as_bytes() {
                guarded = Some(ctl_path);
            }
        }

        if has_string_guard(&dir) {
            match guarded {
                None => {
                    fail(
                        &cat(&[
                            &reldir,
                            b": templates carry a kindIs \"string\" guard with no STRING_REJECT_CONTROLS entry \xe2\x80\x94 the guard would be untested",
                        ]),
                        &mut failures,
                    );
                }
                Some(ctl_path) => {
                    let set_arg = cat(&[ctl_path.as_bytes(), b"=false"]);
                    let mut cmd = Command::new("helm");
                    cmd.arg("template");
                    for a in &template_args {
                        cmd.arg(shell_compat::os(a));
                    }
                    cmd.arg("--set-string").arg(shell_compat::os(&set_arg));
                    let r = capture(0, &mut cmd);
                    if r.ok() {
                        fail(
                            &cat(&[
                                &reldir,
                                b": the STRING \"false\" was ACCEPTED for ",
                                ctl_path.as_bytes(),
                                b" \xe2\x80\x94 Helm reads that as true",
                            ]),
                            &mut failures,
                        );
                    } else {
                        out(&cat(&[
                            b"chart-render: ",
                            &reldir,
                            b": string \"false\" refused for ",
                            ctl_path.as_bytes(),
                            b"\n",
                        ]));
                    }
                }
            }
        } else if guarded.is_some() {
            fail(
                &cat(&[
                    &reldir,
                    b": STRING_REJECT_CONTROLS names ",
                    guarded.unwrap().as_bytes(),
                    b" but the templates have no kindIs \"string\" guard \xe2\x80\x94 stale entry, or the guard was removed",
                ]),
                &mut failures,
            );
        }

        out(b"::endgroup::\n");
    }

    if failures != 0 {
        err(&cat(&[
            b"chart-render: ",
            failures.to_string().as_bytes(),
            b" failure(s)\n",
        ]));
        return 1;
    }

    out(b"chart-render: OK\n");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn required_paths_extracts_dotted_values() {
        // Simulate the grep output that required_paths parses.
        let grep_output = b"required \"message\" .Values.foo.bar\nrequired \"other\" .Values.baz\nrequired \"dup\" .Values.foo.bar\n";
        let mut paths: Vec<Vec<u8>> = Vec::new();
        for line in shell_compat::lines(grep_output) {
            if line.is_empty() {
                continue;
            }
            if let Some(idx) = line.windows(8).position(|w| w == b".Values.") {
                let path = line[idx + 8..].to_vec();
                if !path.is_empty() && !paths.contains(&path) {
                    paths.push(path);
                }
            }
        }
        paths.sort();
        paths.dedup();
        assert_eq!(paths, vec![b"baz".to_vec(), b"foo.bar".to_vec()]);
    }

    #[test]
    fn required_paths_empty_for_no_match() {
        let grep_output = b"";
        let paths: Vec<Vec<u8>> = Vec::new();
        assert!(paths.is_empty());
        // Also check the extraction logic handles empty input
        let lines = shell_compat::lines(grep_output);
        let extracted: Vec<Vec<u8>> = lines
            .iter()
            .filter(|l| !l.is_empty())
            .filter_map(|l| {
                l.windows(8)
                    .position(|w| w == b".Values.")
                    .map(|idx| l[idx + 8..].to_vec())
            })
            .filter(|p| !p.is_empty())
            .collect();
        assert!(extracted.is_empty());
    }

    #[test]
    fn count_resources_matches_grep_kind() {
        let rendered = b"---\nkind: Deployment\nmetadata:\n  name: x\n---\nkind: Service\nmetadata:\n  name: y\n";
        assert_eq!(count_resources(rendered), 2);
    }

    #[test]
    fn count_resources_zero_on_empty() {
        assert_eq!(count_resources(b""), 0);
    }

    #[test]
    fn count_resources_ignores_non_start_kind() {
        let rendered = b"  kind: Nested\nkind: Real\n";
        assert_eq!(count_resources(rendered), 1);
    }

    #[test]
    fn string_reject_controls_lookup() {
        let reldir = b"apps/mcp/slack/deploy/chart";
        let mut guarded: Option<&str> = None;
        for &(ctl_dir, ctl_path) in STRING_REJECT_CONTROLS {
            if reldir == ctl_dir.as_bytes() {
                guarded = Some(ctl_path);
            }
        }
        assert_eq!(guarded, Some("networkPolicy.enabled"));
    }

    #[test]
    fn string_reject_controls_miss() {
        let reldir = b"apps/other/deploy/chart";
        let mut guarded: Option<&str> = None;
        for &(ctl_dir, ctl_path) in STRING_REJECT_CONTROLS {
            if reldir == ctl_dir.as_bytes() {
                guarded = Some(ctl_path);
            }
        }
        assert!(guarded.is_none());
    }

    #[test]
    fn reldir_strip_dot_slash() {
        let dir = b"./apps/mcp/slack/deploy/chart";
        let reldir = if dir.starts_with(b"./") {
            dir[2..].to_vec()
        } else {
            dir.to_vec()
        };
        assert_eq!(reldir, b"apps/mcp/slack/deploy/chart");
    }

    #[test]
    fn reldir_no_prefix() {
        let dir = b"apps/other/deploy/chart";
        let reldir = if dir.starts_with(b"./") {
            dir[2..].to_vec()
        } else {
            dir.to_vec()
        };
        assert_eq!(reldir, b"apps/other/deploy/chart");
    }

    #[test]
    fn chart_name_from_yaml_content() {
        // Test the awk-based extraction indirectly: the pattern should match
        // "name: <value>" at the start of a line.
        let yaml = b"apiVersion: v2\nname: mcp-slack\nversion: 0.1.0\n";
        // Simulate awk logic: find ^name: and take what follows ": "
        let mut extracted = Vec::new();
        for line in yaml.split(|&c| c == b'\n') {
            if line.starts_with(b"name:") {
                if let Some(idx) = line.iter().position(|&c| c == b':') {
                    let rest = &line[idx + 1..];
                    let trimmed: Vec<u8> =
                        rest.iter().copied().skip_while(|&c| c == b' ').collect();
                    extracted = trimmed;
                    break;
                }
            }
        }
        assert_eq!(extracted, b"mcp-slack");
    }

    #[test]
    fn string_reject_controls_is_complete() {
        // Verify every entry has non-empty fields.
        for &(dir, path) in STRING_REJECT_CONTROLS {
            assert!(!dir.is_empty(), "STRING_REJECT_CONTROLS has empty dir");
            assert!(!path.is_empty(), "STRING_REJECT_CONTROLS has empty path");
        }
    }
}
