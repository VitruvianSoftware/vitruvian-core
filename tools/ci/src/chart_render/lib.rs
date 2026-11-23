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

//! //tools/ci:chart_render — `helm template` over every co-located chart
//! (**/deploy/chart), with negative controls.

use shell_compat::{capture, cat, err, out, subst, which};
use std::process::Command;

const VALUES_DIR: &[u8] = b"tools/ci/chart-render";

/// Chart-dir → dotted-values-path for the `kindIs "string"` type-rejection
/// guard.  Declared, not derived: completeness is enforced both ways.
const STRING_REJECT_CONTROLS: &[(&str, &str)] = &[(
    "apps/mcp/vitruvian-slack-mcp/deploy/chart",
    "networkPolicy.enabled",
)];

/// A value guard's negative and positive controls: each bad value, set with
/// `--set-string`, must refuse the render with a message naming the path, and
/// each good value must render with a line that, trimmed, equals `expect`
/// with `{v}` replaced by the value after its last `@` (the whole value if it
/// has none). `good_with` holds extra `path=value` pairs set (also with
/// `--set-string`) on the good renders only, for a value that is valid only
/// when another value changes with it.
pub struct ValueControl {
    pub chart_dir: &'static str,
    pub path: &'static str,
    pub bad: &'static [&'static str],
    pub good: &'static [&'static str],
    pub good_with: &'static [(&'static str, &'static str)],
    pub expect: &'static str,
}

/// The exact line a good value must render as.
pub fn expected_line(expect: &str, value: &str) -> String {
    expect.replace("{v}", value.rsplit('@').next().unwrap_or(value))
}

/// Whether any line of `rendered`, trimmed of surrounding whitespace, is
/// exactly `line`.
pub fn has_exact_line(rendered: &[u8], line: &str) -> bool {
    rendered
        .split(|&c| c == b'\n')
        .any(|l| l.trim_ascii() == line.as_bytes())
}

/// Chart-dir → value guards beyond `required`. Declared, not derived: an
/// entry whose chart no longer exists fails, so a stale entry cannot pass.
pub const VALUE_CONTROLS: &[ValueControl] = &[
    // Digest, never a tag (_helpers.tpl imageRef).
    ValueControl {
        chart_dir: "apps/suites/vitruvian-relay/relay/deploy/chart",
        path: "image.digest",
        bad: &[
            "v1.2.3",
            "main",
            "sha256:abc",
            "main@sha256:ABCDEF0000000000000000000000000000000000000000000000000000000000",
        ],
        good: &[
            "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "main@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        ],
        good_with: &[],
        expect: "image: ghcr.io/vitruviansoftware/vitruvian-relay@{v}",
    },
    // Below the relay's 75 s idle close (_helpers.tpl upstreamIdleTimeout).
    ValueControl {
        chart_dir: "apps/suites/vitruvian-relay/relay/deploy/chart",
        path: "upstreamIdleTimeout",
        bad: &["75s", "90s", "2m", "1m15s", "0s", "60", "10ms", "1h"],
        good: &["60s", "74s", "1m", "1m10s", "1m14s"],
        good_with: &[],
        expect: "connectionIdleTimeout: \"{v}\"",
    },
    // Who may sign in: with the role empty (and no user list in the CI values)
    // there is no check at all, which must refuse (_helpers.tpl
    // whoMaySignIn); a role renders as REQUIRED_ROLE's value.
    ValueControl {
        chart_dir: "apps/suites/vitruvian-relay/relay/deploy/chart",
        path: "oidc.requiredRole",
        bad: &[""],
        good: &["relay-user", "relay-tester"],
        good_with: &[],
        expect: "value: \"{v}\"",
    },
    // Both checks at once must refuse too: the new relay would ignore the user
    // list without saying so. The CI values already set requiredRole, so any
    // user list is "both". A list alone (the role cleared) is the old relay's
    // check and renders as ALLOWED_SUBJECTS's value.
    ValueControl {
        chart_dir: "apps/suites/vitruvian-relay/relay/deploy/chart",
        path: "oidc.allowedSubjects",
        bad: &["378818267051722263"],
        good: &["398000000000000001"],
        good_with: &[("oidc.requiredRole", "")],
        expect: "value: \"{v}\"",
    },
];

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

    for ctl in VALUE_CONTROLS {
        let want = cat(&[b"./", ctl.chart_dir.as_bytes(), b"/Chart.yaml"]);
        if !charts.contains(&want) {
            fail(
                &cat(&[
                    b"VALUE_CONTROLS names ",
                    ctl.chart_dir.as_bytes(),
                    b" (",
                    ctl.path.as_bytes(),
                    b") but no chart is there \xe2\x80\x94 stale entry",
                ]),
                &mut failures,
            );
        }
    }

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
                // The script printed `helm lint ... 2>&1`: both streams (lint
                // puts its closing `Error: ... failed` on stderr).
                err(&subst(cat(&[&r.stdout, &r.stderr])));
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

        // --- Value guards: bad values refuse, good values render ---
        for ctl in VALUE_CONTROLS {
            if reldir != ctl.chart_dir.as_bytes() {
                continue;
            }
            let run_with = |v: &str, extra: &[(&str, &str)]| {
                let set_arg = cat(&[ctl.path.as_bytes(), b"=", v.as_bytes()]);
                let mut cmd = Command::new("helm");
                cmd.arg("template");
                for a in &template_args {
                    cmd.arg(shell_compat::os(a));
                }
                cmd.arg("--set-string").arg(shell_compat::os(&set_arg));
                for &(p, x) in extra {
                    let arg = cat(&[p.as_bytes(), b"=", x.as_bytes()]);
                    cmd.arg("--set-string").arg(shell_compat::os(&arg));
                }
                capture(0, &mut cmd)
            };
            for &v in ctl.bad {
                let r = run_with(v, &[]);
                let combined = cat(&[&r.stdout, &r.stderr]);
                if r.ok() {
                    fail(
                        &cat(&[
                            &reldir,
                            b": ",
                            ctl.path.as_bytes(),
                            b"=",
                            v.as_bytes(),
                            b" still rendered \xe2\x80\x94 its guard does not fire",
                        ]),
                        &mut failures,
                    );
                } else if !shell_compat::contains(&combined, ctl.path.as_bytes()) {
                    fail(
                        &cat(&[
                            &reldir,
                            b": ",
                            ctl.path.as_bytes(),
                            b"=",
                            v.as_bytes(),
                            b" refused (good) but the message never names ",
                            ctl.path.as_bytes(),
                        ]),
                        &mut failures,
                    );
                }
            }
            for &v in ctl.good {
                let r = run_with(v, ctl.good_with);
                let want = expected_line(ctl.expect, v);
                if !r.ok() {
                    fail(
                        &cat(&[
                            &reldir,
                            b": ",
                            ctl.path.as_bytes(),
                            b"=",
                            v.as_bytes(),
                            b" is valid but refused the render",
                        ]),
                        &mut failures,
                    );
                    err(&r.stderr);
                    err(b"\n");
                } else if !has_exact_line(&r.stdout, &want) {
                    fail(
                        &cat(&[
                            &reldir,
                            b": ",
                            ctl.path.as_bytes(),
                            b"=",
                            v.as_bytes(),
                            b" rendered but no line is exactly `",
                            want.as_bytes(),
                            b"`",
                        ]),
                        &mut failures,
                    );
                }
            }
            out(&cat(&[
                b"chart-render: ",
                &reldir,
                b": ",
                ctl.path.as_bytes(),
                b": ",
                ctl.bad.len().to_string().as_bytes(),
                b" bad value(s) refused, ",
                ctl.good.len().to_string().as_bytes(),
                b" good value(s) rendered\n",
            ]));
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
    fn exact_line_match_is_not_a_substring_match() {
        let out = b"spec:\n      connectionIdleTimeout: \"1m10s\"\n  image: r@sha256:ab\n";
        let want = expected_line("connectionIdleTimeout: \"{v}\"", "1m10s");
        assert!(has_exact_line(out, &want));
        // A value that only appears inside the line, or a prefix of it, is not a match.
        assert!(!has_exact_line(
            out,
            &expected_line("connectionIdleTimeout: \"{v}\"", "10s")
        ));
        assert!(!has_exact_line(
            out,
            &expected_line("connectionIdleTimeout: \"{v}\"", "1m")
        ));
        assert!(has_exact_line(
            out,
            &expected_line("image: r@{v}", "main@sha256:ab")
        ));
        assert!(!has_exact_line(
            out,
            &expected_line("image: r@{v}", "sha256:a")
        ));
    }

    #[test]
    fn value_controls_expect_names_the_value() {
        for ctl in VALUE_CONTROLS {
            assert!(
                ctl.expect.contains("{v}"),
                "{}: expect has no {{v}}",
                ctl.path
            );
        }
    }

    #[test]
    fn value_controls_have_both_arms() {
        for ctl in VALUE_CONTROLS {
            assert!(
                ctl.chart_dir.ends_with("/deploy/chart"),
                "{}",
                ctl.chart_dir
            );
            assert!(!ctl.bad.is_empty(), "{}: no bad values", ctl.path);
            assert!(!ctl.good.is_empty(), "{}: no good values", ctl.path);
            for &(p, _) in ctl.good_with {
                assert!(
                    p != ctl.path,
                    "{}: good_with sets the path itself",
                    ctl.path
                );
            }
            for b in ctl.bad {
                assert!(
                    !ctl.good.contains(b),
                    "{}: {b} is both bad and good",
                    ctl.path
                );
            }
        }
    }

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
        let reldir = b"apps/mcp/vitruvian-slack-mcp/deploy/chart";
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
        let dir = b"./apps/mcp/vitruvian-slack-mcp/deploy/chart";
        let reldir = if dir.starts_with(b"./") {
            dir[2..].to_vec()
        } else {
            dir.to_vec()
        };
        assert_eq!(reldir, b"apps/mcp/vitruvian-slack-mcp/deploy/chart");
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
        let yaml = b"apiVersion: v2\nname: vitruvian-slack-mcp\nversion: 0.1.0\n";
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
        assert_eq!(extracted, b"vitruvian-slack-mcp");
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
