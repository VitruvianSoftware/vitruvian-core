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

//! foundation-app-digest-guard.sh — export per-app image digests for the
//! Pulumi program, and FAIL CLOSED if any workload enabled in
//! Pulumi.production.yaml has no digest supplied.

use shell_compat::{cat, err, out};

/// Pure function: returns space-separated list of app names that are
/// `_workload_enabled: "true"` in `pulumi_file_contents` but have no
/// matching entry in `app_image_digests`.
pub fn missing_digest_apps(pulumi_file_contents: &[u8], app_image_digests: &[u8]) -> Vec<u8> {
    let mut missing = Vec::new();
    let haystack = cat(&[b",", app_image_digests, b","]);
    for line in pulumi_file_contents.split(|&c| c == b'\n') {
        let Some(we_pos) = find_subslice(line, b"_workload_enabled:") else {
            continue;
        };
        let after_key = &line[we_pos + b"_workload_enabled:".len()..];
        if !contains_enabled_true(after_key) {
            continue;
        }
        let before = &line[..we_pos];
        let colon_pos = match before.iter().rposition(|&c| c == b':') {
            Some(p) => p,
            None => continue,
        };
        let app = &before[colon_pos + 1..];
        if app.is_empty() {
            continue;
        }
        let needle = cat(&[b",", app, b"="]);
        if find_subslice(&haystack, &needle).is_some() {
            continue;
        }
        if !missing.is_empty() {
            missing.push(b' ');
        }
        missing.extend_from_slice(app);
    }
    missing
}

fn find_subslice(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    hay.windows(needle.len()).position(|w| w == needle)
}

fn contains_enabled_true(after_key: &[u8]) -> bool {
    let trimmed = after_key
        .iter()
        .skip_while(|&&c| c == b' ')
        .copied()
        .collect::<Vec<u8>>();
    find_subslice(&trimmed, b"\"true\"").is_some()
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let app_image_digests = if !args.is_empty() {
        args[0].clone()
    } else {
        Vec::new()
    };
    let pulumi_file = if args.len() >= 2 {
        args[1].clone()
    } else {
        err(b"pulumi file required\n");
        return 2;
    };

    let github_env = shell_compat::env_or_empty("GITHUB_ENV");

    if !app_image_digests.is_empty() {
        for pair in app_image_digests.split(|&c| c == b',') {
            if pair.is_empty() {
                continue;
            }
            let eq_pos = match pair.iter().position(|&c| c == b'=') {
                Some(p) => p,
                None => continue,
            };
            let app = &pair[..eq_pos];
            let digest = &pair[eq_pos + 1..];
            if app.is_empty() || digest.is_empty() {
                continue;
            }
            let var: Vec<u8> = app
                .iter()
                .map(|&c| {
                    if c == b'-' {
                        b'_'
                    } else {
                        c.to_ascii_uppercase()
                    }
                })
                .collect();
            let var_line = cat(&[&var, b"_IMAGE_DIGEST"]);
            if !github_env.is_empty() {
                let entry = cat(&[&var_line, b"=", digest, b"\n"]);
                let _ = std::fs::OpenOptions::new()
                    .append(true)
                    .create(true)
                    .open(shell_compat::path(&github_env))
                    .and_then(|mut f| {
                        use std::io::Write;
                        f.write_all(&entry)
                    });
            }
            out(&cat(&[b"exporting ", &var_line, b"\n"]));
        }
    }

    let contents = match std::fs::read(shell_compat::path(&pulumi_file)) {
        Ok(c) => c,
        Err(e) => {
            err(&cat(&[
                b"could not read pulumi file: ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            return 2;
        }
    };

    let missing = missing_digest_apps(&contents, &app_image_digests);
    if !missing.is_empty() {
        err(&cat(&[
            b"::error::workload enabled but no image digest supplied for: ",
            &missing,
            b" \xe2\x80\x94 deploying would render an EMPTY image and strip it off the live service. Pass app_image_digests as '<app>=<ref>'.\n",
        ]));
        return 1;
    }
    out(b"digest guard: OK\n");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_digests_present() {
        let pf = b"config:\n  gcp-app-infra:oauth-user-inspector_workload_enabled: \"true\"\n  gcp-app-infra:zitadel-apps_workload_enabled: \"false\"\n  gcp-app-infra:mcp-slack_workload_enabled: \"true\"\n";
        let got = missing_digest_apps(pf, b"oauth-user-inspector=sha256:aaa,mcp-slack=sha256:bbb");
        assert_eq!(got, b"");
    }

    #[test]
    fn one_missing() {
        let pf = b"config:\n  gcp-app-infra:oauth-user-inspector_workload_enabled: \"true\"\n  gcp-app-infra:zitadel-apps_workload_enabled: \"false\"\n  gcp-app-infra:mcp-slack_workload_enabled: \"true\"\n";
        let got = missing_digest_apps(pf, b"oauth-user-inspector=sha256:aaa");
        assert_eq!(got, b"mcp-slack");
    }

    #[test]
    fn no_digests_at_all() {
        let pf = b"config:\n  gcp-app-infra:oauth-user-inspector_workload_enabled: \"true\"\n  gcp-app-infra:zitadel-apps_workload_enabled: \"false\"\n  gcp-app-infra:mcp-slack_workload_enabled: \"true\"\n";
        let got = missing_digest_apps(pf, b"");
        assert_eq!(got, b"oauth-user-inspector mcp-slack");
    }

    #[test]
    fn disabled_workload_digest_doesnt_excuse_enabled() {
        let pf = b"config:\n  gcp-app-infra:oauth-user-inspector_workload_enabled: \"true\"\n  gcp-app-infra:zitadel-apps_workload_enabled: \"false\"\n  gcp-app-infra:mcp-slack_workload_enabled: \"true\"\n";
        let got = missing_digest_apps(pf, b"mcp-slack=sha256:bbb,zitadel-apps=sha256:ccc");
        assert_eq!(got, b"oauth-user-inspector");
    }

    #[test]
    fn no_workloads_enabled() {
        let pf = b"config:\n  gcp-app-infra:zitadel-apps_workload_enabled: \"false\"\n";
        let got = missing_digest_apps(pf, b"");
        assert_eq!(got, b"");
    }

    #[test]
    fn extra_digest_is_harmless() {
        let pf = b"config:\n  gcp-app-infra:oauth-user-inspector_workload_enabled: \"true\"\n  gcp-app-infra:zitadel-apps_workload_enabled: \"false\"\n  gcp-app-infra:mcp-slack_workload_enabled: \"true\"\n";
        let got = missing_digest_apps(
            pf,
            b"oauth-user-inspector=sha256:aaa,mcp-slack=sha256:bbb,unrelated-app=sha256:zzz",
        );
        assert_eq!(got, b"");
    }
}
