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

//! foundation-app-digest-guard — export per-app image digests for the
//! Pulumi program, and FAIL CLOSED if any workload enabled in
//! Pulumi.production.yaml has no digest supplied.

use shell_compat::{cat, err, out};

const KEY: &[u8] = b"_workload_enabled:";

/// Pure function: returns space-separated list of app names that are
/// `_workload_enabled: "true"` in `pulumi_file_contents` but have no
/// matching entry in `app_image_digests`.
///
/// Line for line the script's `grep -E '_workload_enabled: *"true"'` and
/// `sed -E 's/.*:([a-z0-9-]+)_workload_enabled:.*/\1/'`. When the sed does not
/// match (no `ns:` prefix, or a name outside `[a-z0-9-]`), the app "name" is
/// the WHOLE line, which no digest pair ever matches: the line is reported
/// missing and the guard fails closed.
pub fn missing_digest_apps(pulumi_file_contents: &[u8], app_image_digests: &[u8]) -> Vec<u8> {
    let mut missing = Vec::new();
    let haystack = cat(&[b",", app_image_digests, b","]);
    for line in pulumi_file_contents.split(|&c| c == b'\n') {
        if !enabled_true(line) {
            continue;
        }
        let app = app_name(line);
        if app.is_empty() {
            continue;
        }
        // `app=` with nothing after it is no digest: it renders the same
        // EMPTY image as a missing pair, so it counts as missing.
        let needle = cat(&[b",", app, b"="]);
        let has_digest = haystack.windows(needle.len()).enumerate().any(|(i, w)| {
            w == needle.as_slice() && !matches!(haystack.get(i + needle.len()), None | Some(b','))
        });
        if has_digest {
            continue;
        }
        if !missing.is_empty() {
            missing.push(b' ');
        }
        missing.extend_from_slice(app);
    }
    missing
}

/// `_workload_enabled: *"true"` anywhere on the line: the key, any number of
/// spaces, then `"true"` straight after. `"false" # "true"` is not enabled.
fn enabled_true(line: &[u8]) -> bool {
    (0..line.len()).any(|q| {
        line[q..].starts_with(KEY) && {
            let rest = &line[q + KEY.len()..];
            let spaces = rest.iter().take_while(|&&c| c == b' ').count();
            rest[spaces..].starts_with(b"\"true\"")
        }
    })
}

/// `s/.*:([a-z0-9-]+)_workload_enabled:.*/\1/`: greedy `.*:` takes the LAST
/// colon that is followed by one or more `[a-z0-9-]` and then the key. No such
/// colon: sed leaves the line as it is.
fn app_name(line: &[u8]) -> &[u8] {
    let ok = |c: u8| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-';
    for c in (0..line.len()).rev() {
        if line[c] != b':' {
            continue;
        }
        let run = line[c + 1..].iter().take_while(|&&b| ok(b)).count();
        if run > 0 && line[c + 1 + run..].starts_with(KEY) {
            return &line[c + 1..c + 1 + run];
        }
    }
    line
}

fn find_subslice(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    hay.windows(needle.len()).position(|w| w == needle)
}

fn append(file: &[u8], data: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    std::fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(shell_compat::path(file))?
        .write_all(data)
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let app_image_digests = args.first().cloned().unwrap_or_default();
    // `${2:?pulumi file required}`: missing OR empty stops before anything is
    // exported.
    let pulumi_file = match args.get(1) {
        Some(p) if !p.is_empty() => p.clone(),
        _ => {
            err(b"foundation-app-digest-guard: pulumi file required\n");
            return 1;
        }
    };

    if !app_image_digests.is_empty() {
        let github_env = shell_compat::env_or_empty("GITHUB_ENV");
        // `IFS=',' read -ra pairs <<< "$digests"` reads the first line only.
        let first_line = app_image_digests
            .split(|&c| c == b'\n')
            .next()
            .unwrap_or_default();
        for pair in first_line.split(|&c| c == b',') {
            // `${pair%%=*}` / `${pair#*=}`: with no `=` both are the pair.
            let (app, digest) = match pair.iter().position(|&c| c == b'=') {
                Some(p) => (&pair[..p], &pair[p + 1..]),
                None => (pair, pair),
            };
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
            // The script ran under `set -eu`: an unset GITHUB_ENV, or one it
            // cannot append to, stopped it with exit 1. A digest that never
            // reaches the program would render the EMPTY image this guard
            // exists to prevent, so this fails the same way.
            if github_env.is_empty() {
                err(b"foundation-app-digest-guard: GITHUB_ENV is not set; cannot export the image digests\n");
                return 1;
            }
            if let Err(e) = append(&github_env, &cat(&[&var_line, b"=", digest, b"\n"])) {
                err(&cat(&[
                    b"foundation-app-digest-guard: cannot write GITHUB_ENV: ",
                    e.to_string().as_bytes(),
                    b"\n",
                ]));
                return 1;
            }
            out(&cat(&[b"exporting ", &var_line, b"\n"]));
        }
    }

    // Deliberately STRICTER than the script, which read the file with a bare
    // `$(cat ...)`: a missing file read as "no workloads enabled" and the
    // guard printed OK. A deploy guard that cannot read its input must not
    // pass.
    let contents = match std::fs::read(shell_compat::path(&pulumi_file)) {
        Ok(c) => c,
        Err(e) => {
            out(&cat(&[
                b"::error::digest guard: cannot read ",
                &pulumi_file,
                b": ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            return 1;
        }
    };

    let missing = missing_digest_apps(&contents, &app_image_digests);
    if !missing.is_empty() {
        // stdout, like the script's echo: the runner reads ::error:: there.
        out(&cat(&[
            b"::error::workload enabled but no image digest supplied for:",
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

    #[test]
    fn a_name_the_sed_cannot_read_is_reported_whole() {
        // No `ns:` prefix, and a name outside [a-z0-9-]: the script's sed
        // leaves the line as is, so it is missing and the guard fails closed.
        let got = missing_digest_apps(b"  b_workload_enabled: \"true\"\n", b"b=1");
        assert_eq!(got, b"  b_workload_enabled: \"true\"");
        let got = missing_digest_apps(b"  ns:My_App_workload_enabled: \"true\"\n", b"My_App=1");
        assert_eq!(got, b"  ns:My_App_workload_enabled: \"true\"");
    }

    #[test]
    fn an_empty_digest_counts_as_missing() {
        let pf = b"  ns:oauth-user-inspector_workload_enabled: \"true\"\n";
        assert_eq!(
            missing_digest_apps(pf, b"oauth-user-inspector="),
            b"oauth-user-inspector"
        );
        assert_eq!(
            missing_digest_apps(pf, b"oauth-user-inspector=,x=1"),
            b"oauth-user-inspector"
        );
        assert_eq!(
            missing_digest_apps(pf, b"oauth-user-inspector=sha256:ab"),
            b""
        );
    }

    #[test]
    fn true_must_follow_the_key() {
        let pf = b"  ns:x_workload_enabled: \"false\" # \"true\"\n  ns:y_workload_enabled:\"true\"\n  ns:z_workload_enabled:   \"true\"\r\n";
        assert_eq!(missing_digest_apps(pf, b""), b"y z");
    }
}
