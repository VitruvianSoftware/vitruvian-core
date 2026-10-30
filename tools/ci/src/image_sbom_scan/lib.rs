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

//! image-sbom-scan.sh — scan a published image's SBOM attestation for known
//! advisories. Two arms: BLOCKING (APP_PREFIX packages via osv-scanner) and
//! REPORTING (whole image). Fails closed on missing attestation, missing SBOM,
//! zero app packages, or missing osv-scanner. APP_TREE=absent declares an image
//! with no package-managed application tree; it then refuses if one appears.

use shell_compat::{
    capture, cat, env, env_or, err, mktemp_dir, os, out, path, status, subst, write_file,
};
use std::process::Command;

fn parse_image(image: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    let s = image;
    for i in 0..s.len() {
        if s[i] == b'/' {
            let registry = s[..i].to_vec();
            let repository = s[i + 1..].to_vec();
            if !registry.is_empty() && !repository.is_empty() {
                return Some((registry, repository));
            }
            return None;
        }
    }
    None
}

fn valid_digest(digest: &[u8]) -> bool {
    digest.len() > 7 && &digest[..7] == b"sha256:"
}

fn fetch(
    registry: &[u8],
    repository: &[u8],
    token: &[u8],
    digest_or_ref: &[u8],
    accept: &[u8],
    out_path: &[u8],
) -> bool {
    let url = cat(&[
        b"https://",
        registry,
        b"/v2/",
        repository,
        b"/manifests/",
        digest_or_ref,
    ]);
    let auth = cat(&[b"Bearer ", token]);
    let rc = status(
        0,
        Command::new("curl")
            .arg("-fsSL")
            .arg("--retry")
            .arg("3")
            .arg("--retry-delay")
            .arg("2")
            .arg("--retry-all-errors")
            .arg("--max-time")
            .arg("120")
            .arg("-H")
            .arg(os(&cat(&[b"Authorization: ", &auth])))
            .arg("-H")
            .arg(os(&cat(&[b"Accept: ", accept])))
            .arg(os(&url))
            .arg("-o")
            .arg(os(out_path)),
        false,
    );
    rc == 0
}

fn fetch_blob(
    registry: &[u8],
    repository: &[u8],
    token: &[u8],
    digest: &[u8],
    out_path: &[u8],
) -> bool {
    let url = cat(&[
        b"https://",
        registry,
        b"/v2/",
        repository,
        b"/blobs/",
        digest,
    ]);
    let auth = cat(&[b"Bearer ", token]);
    let r = capture(
        0,
        Command::new("bash").arg("-c").arg(os(&cat(&[
            b"curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors --max-time 300 -H 'Authorization: ",
            &auth,
            b"' '",
            &url,
            b"' | jq '.predicate'",
        ]))),
    );
    if !r.ok() {
        return false;
    }
    write_file(out_path, &r.stdout, 0o644).is_ok()
}

/// What the blocking arm does, given APP_TREE and the package count under
/// APP_PREFIX. APP_TREE=absent is for an image whose application carries no
/// package-managed dependency tree at all (mcp-slack since #3985: a Rust
/// binary built `--locked` from a lockfile osv-scan covers). There the blocking arm has
/// nothing to cover, so it asserts the tree is still absent instead: a tree
/// that reappears refuses rather than going unscanned.
#[derive(Debug, PartialEq)]
enum AppArm {
    Scan,
    SkipAbsent,
    RefuseVacuous,
    RefuseUnexpected,
    RefuseUnknown,
}

fn app_arm(app_tree: &[u8], app_count: &[u8]) -> Option<AppArm> {
    let zero = app_count == b"0";
    let unknown = app_count.is_empty();
    match app_tree {
        b"present" => Some(if zero || unknown {
            AppArm::RefuseVacuous
        } else {
            AppArm::Scan
        }),
        b"absent" => Some(if unknown {
            AppArm::RefuseUnknown
        } else if zero {
            AppArm::SkipAbsent
        } else {
            AppArm::RefuseUnexpected
        }),
        _ => None,
    }
}

fn jq_r(file: &[u8], filter: &[u8]) -> Vec<u8> {
    let r = capture(
        0,
        Command::new("jq").arg("-r").arg(os(filter)).arg(os(file)),
    );
    subst(r.stdout)
}

fn jq_r_arg(file: &[u8], filter: &[u8], arg_name: &[u8], arg_val: &[u8]) -> Vec<u8> {
    let r = capture(
        0,
        Command::new("jq")
            .arg("-r")
            .arg("--arg")
            .arg(os(arg_name))
            .arg(os(arg_val))
            .arg(os(filter))
            .arg(os(file)),
    );
    subst(r.stdout)
}

fn jq_write(
    in_file: &[u8],
    filter: &[u8],
    arg_name: &[u8],
    arg_val: &[u8],
    out_file: &[u8],
) -> bool {
    let r = capture(
        0,
        Command::new("jq")
            .arg("--arg")
            .arg(os(arg_name))
            .arg(os(arg_val))
            .arg(os(filter))
            .arg(os(in_file)),
    );
    if !r.ok() {
        return false;
    }
    write_file(out_file, &r.stdout, 0o644).is_ok()
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let image = match env("IMAGE") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"::error::IMAGE is required (e.g. ghcr.io/vitruviansoftware/mcp-slack)\n");
            return 1;
        }
    };
    let digest = match env("DIGEST") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"::error::DIGEST is required (the INDEX digest, sha256:...)\n");
            return 1;
        }
    };
    let app_prefix = env_or("APP_PREFIX", b"/app/node_modules");
    let app_tree = env_or("APP_TREE", b"present");
    if app_arm(&app_tree, b"0").is_none() {
        err(&cat(&[
            b"::error::APP_TREE must be 'present' or 'absent', got '",
            &app_tree,
            b"'\n",
        ]));
        return 1;
    }

    if !valid_digest(&digest) {
        err(&cat(&[
            b"::error::DIGEST must be a sha256:... reference, got '",
            &digest,
            b"'\n",
        ]));
        return 1;
    }

    for bin in &[b"curl" as &[u8], b"jq", b"osv-scanner"] {
        if shell_compat::which(bin).is_none() {
            err(&cat(&[b"::error::", bin, b" not found on PATH.\n"]));
            if *bin == b"osv-scanner" {
                err(b"Locally: go install github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.6.0\n");
            }
            return 1;
        }
    }

    let (registry, repository) = match parse_image(&image) {
        Some(pair) => pair,
        None => {
            err(&cat(&[
                b"::error::IMAGE '",
                &image,
                b"' must be in registry/repository format\n",
            ]));
            return 1;
        }
    };

    let work = match mktemp_dir() {
        Ok(d) => d,
        Err(e) => {
            err(&cat(&[
                b"::error::mktemp failed: ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            return 1;
        }
    };

    out(&cat(&[
        b"==> anonymous pull token for ",
        &repository,
        b" on ",
        &registry,
        b"\n",
    ]));
    let token_url = cat(&[
        b"https://",
        &registry,
        b"/token?scope=repository:",
        &repository,
        b":pull&service=",
        &registry,
    ]);
    let r = capture(
        0,
        Command::new("curl")
            .arg("-fsSL")
            .arg("--retry")
            .arg("3")
            .arg("--retry-delay")
            .arg("2")
            .arg("--retry-all-errors")
            .arg("--max-time")
            .arg("60")
            .arg(os(&token_url)),
    );
    let token_json = r.stdout;
    let token = {
        let tmp = cat(&[&work, b"/token.json"]);
        let _ = write_file(&tmp, &token_json, 0o644);
        jq_r(&tmp, b".token // empty")
    };
    if token.is_empty() {
        err(&cat(&[
            b"::error::no anonymous pull token for ",
            &image,
            b" -- is the package public?\n",
        ]));
        return 1;
    }

    out(&cat(&[b"==> index ", &digest, b"\n"]));
    let index_path = cat(&[&work, b"/index.json"]);
    let accept =
        b"application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json";
    if !fetch(&registry, &repository, &token, &digest, accept, &index_path) {
        err(&cat(&[b"::error::failed to fetch index ", &digest, b"\n"]));
        return 1;
    }

    let manifest_count = jq_r(&index_path, b".manifests | length? // 0");
    if manifest_count == b"0" || manifest_count.is_empty() {
        let media_type = jq_r(&index_path, b".mediaType // \"unknown\"");
        err(&cat(&[
            b"::error::",
            &digest,
            b" is not an image index (mediaType: ",
            &media_type,
            b").\n",
        ]));
        err(b"::error::Pass the INDEX digest -- attestations hang off the index, and the chart pins the index.\n");
        return 1;
    }

    let att_path = cat(&[&work, b"/attestations.txt"]);
    let att_filter = br#".manifests[]? | select(.annotations["vnd.docker.reference.type"] == "attestation-manifest") | "\(.digest) \(.annotations["vnd.docker.reference.digest"])"#;
    let att_text = jq_r(&index_path, att_filter);
    let _ = write_file(&att_path, &att_text, 0o644);

    if att_text.is_empty() {
        err(&cat(&[
            b"::error::",
            &image,
            b"@",
            &digest,
            b" carries no attestation manifests.\n",
        ]));
        err(b"::error::Is this an index digest? A platform manifest has none.\n");
        return 1;
    }

    let mut blocking_rc: i32 = 0;
    let mut sboms_found: i32 = 0;
    let summary_path = cat(&[&work, b"/summary.md"]);
    let _ = write_file(&summary_path, b"", 0o644);

    let att_lines = shell_compat::lines(&att_text);
    for line in &att_lines {
        if line.is_empty() {
            continue;
        }
        let parts: Vec<&[u8]> = line.splitn(2, |&b| b == b' ').collect();
        if parts.len() < 2 {
            continue;
        }
        let att_digest = parts[0];
        let subject = parts[1];
        if att_digest.is_empty() {
            continue;
        }

        out(&cat(&[
            b"==> attestation ",
            att_digest,
            b" (subject ",
            subject,
            b")\n",
        ]));

        let att_json_path = cat(&[&work, b"/att.json"]);
        if !fetch(
            &registry,
            &repository,
            &token,
            att_digest,
            b"application/vnd.oci.image.manifest.v1+json",
            &att_json_path,
        ) {
            err(&cat(&[
                b"::error::failed to fetch attestation ",
                att_digest,
                b"\n",
            ]));
            return 1;
        }

        let spdx_layer = {
            let filter = br#".layers[]? | select(.annotations["in-toto.io/predicate-type"] == "https://spdx.dev/Document") | .digest"#;
            let all = jq_r(&att_json_path, filter);
            shell_compat::first_line(&all)
        };

        if spdx_layer.is_empty() {
            err(&cat(&[
                b"::error::attestation ",
                att_digest,
                b" has no https://spdx.dev/Document predicate\n",
            ]));
            err(b"::error::(provenance alone is not an SBOM -- has --sbom=true been dropped from the build?)\n");
            return 1;
        }
        sboms_found += 1;

        let subject_hash = if subject.len() > 7 && &subject[..7] == b"sha256:" {
            &subject[7..]
        } else {
            subject
        };
        let full_path = cat(&[&work, b"/", subject_hash, b".spdx.json"]);
        if !fetch_blob(&registry, &repository, &token, &spdx_layer, &full_path) {
            err(&cat(&[
                b"::error::failed to fetch SBOM blob ",
                &spdx_layer,
                b"\n",
            ]));
            return 1;
        }

        let total = jq_r(&full_path, b".packages | length");

        let app_path = cat(&[&work, b"/", subject_hash, b".app.spdx.json"]);
        let app_filter = cat(&[
            b".packages = [.packages[] | select((.sourceInfo // \"\") | contains($p))] | .relationships = [] | .files = []",
        ]);
        if !jq_write(&full_path, &app_filter, b"p", &app_prefix, &app_path) {
            err(b"::error::failed to filter app packages from SBOM\n");
            return 1;
        }

        let app_count = jq_r(&app_path, b".packages | length");

        out(&cat(&[
            b"    ",
            &total,
            b" packages total, ",
            &app_count,
            b" under ",
            &app_prefix,
            b"\n",
        ]));

        let arm = app_arm(&app_tree, &app_count).unwrap_or(AppArm::RefuseUnknown);
        match arm {
            AppArm::RefuseVacuous => {
                err(&cat(&[
                    b"::error::zero packages under ",
                    &app_prefix,
                    b" in ",
                    subject,
                    b" -- the blocking arm would pass vacuously.\n",
                ]));
                err(b"::error::Either the image layout changed or the filter is wrong. Refusing rather than reporting clean.\n");
                err(b"::error::If the application no longer installs a dependency tree at all, set APP_TREE=absent.\n");
                return 1;
            }
            AppArm::RefuseUnexpected => {
                err(&cat(&[
                    b"::error::APP_TREE=absent, but ",
                    &app_count,
                    b" packages sit under ",
                    &app_prefix,
                    b" in ",
                    subject,
                    b".\n",
                ]));
                err(b"::error::The application has a dependency tree again: drop APP_TREE=absent so the blocking arm scans it.\n");
                return 1;
            }
            AppArm::RefuseUnknown => {
                err(&cat(&[
                    b"::error::could not count packages under ",
                    &app_prefix,
                    b" in ",
                    subject,
                    b". Refusing rather than reporting clean.\n",
                ]));
                return 1;
            }
            AppArm::SkipAbsent | AppArm::Scan => {}
        }

        if arm == AppArm::SkipAbsent {
            out(&cat(&[
                b"--> BLOCKING scan: skipped, APP_TREE=absent and none under ",
                &app_prefix,
                b" (as declared)\n",
            ]));
        } else {
            out(&cat(&[
                b"--> BLOCKING scan: ",
                &app_prefix,
                b" (",
                &app_count,
                b" packages)\n",
            ]));
            let scan_rc = status(
                0,
                Command::new("osv-scanner")
                    .arg("scan")
                    .arg("source")
                    .arg(os(&cat(&[b"--sbom=", &app_path])))
                    .arg("--format")
                    .arg("table"),
                false,
            );
            if scan_rc == 0 {
                out(b"    no advisories in the application dependency tree\n");
            } else {
                err(&cat(&[
                    b"::error::advisories found under ",
                    &app_prefix,
                    b" for ",
                    subject,
                    b".\n",
                ]));
                err(b"::error::At the default prefix this is the application's OWN dependency tree -- the one\n");
                err(b"::error::osv-scan cannot see, because the image does not install from the committed lockfile.\n");
                blocking_rc = 1;
            }
        }

        out(&cat(&[
            b"--> REPORTING scan: whole image (",
            &total,
            b" packages)\n",
        ]));
        let report_path = cat(&[&work, b"/report.md"]);
        let _ = status(
            0,
            Command::new("osv-scanner")
                .arg("scan")
                .arg("source")
                .arg(os(&cat(&[b"--sbom=", &full_path])))
                .arg("--format")
                .arg("markdown")
                .stdout(
                    std::fs::File::create(path(&report_path))
                        .map(std::process::Stdio::from)
                        .unwrap_or(std::process::Stdio::null()),
                )
                .stderr(std::process::Stdio::null()),
            true,
        );

        let report_content = std::fs::read(path(&report_path)).unwrap_or_default();
        let section = cat(&[
            b"### Image SBOM \xe2\x80\x94 `",
            subject,
            b"`\n\n`",
            &total,
            b"` packages, `",
            &app_count,
            b"` under `",
            &app_prefix,
            b"` (the blocking arm).\n\n<details><summary>Full advisory report (reporting only \xe2\x80\x94 does not block)</summary>\n\n",
            &report_content,
            b"\n</details>\n\n",
        ]);
        let existing = std::fs::read(path(&summary_path)).unwrap_or_default();
        let _ = write_file(&summary_path, &cat(&[&existing, &section]), 0o644);
    }

    out(&cat(&[
        b"==> ",
        sboms_found.to_string().as_bytes(),
        b" SBOM attestation(s) scanned\n",
    ]));

    let summary_content = std::fs::read(path(&summary_path)).unwrap_or_default();
    if let Some(gss) = env("GITHUB_STEP_SUMMARY") {
        if !gss.is_empty() {
            let _ = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(path(&gss))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(&summary_content)
                });
        }
    } else {
        out(&summary_content);
    }

    blocking_rc
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_digest() {
        assert!(valid_digest(b"sha256:63912eeeabcdef1234567890"));
        assert!(valid_digest(b"sha256:a"));
        assert!(!valid_digest(b"sha512:abc"));
        assert!(!valid_digest(b"abc123"));
        assert!(!valid_digest(b"sha256"));
        assert!(!valid_digest(b"sha256:"));
        assert!(!valid_digest(b""));
    }

    #[test]
    fn test_parse_image() {
        let (reg, repo) = parse_image(b"ghcr.io/vitruviansoftware/mcp-slack").unwrap();
        assert_eq!(reg, b"ghcr.io");
        assert_eq!(repo, b"vitruviansoftware/mcp-slack");

        let (reg, repo) = parse_image(b"docker.io/library/nginx").unwrap();
        assert_eq!(reg, b"docker.io");
        assert_eq!(repo, b"library/nginx");

        assert!(parse_image(b"no-slash-here").is_none());
        assert!(parse_image(b"/leading-slash").is_none());
        assert!(parse_image(b"trailing/").is_none());
        assert!(parse_image(b"").is_none());
    }

    #[test]
    fn test_parse_image_single_segment_repo() {
        let (reg, repo) = parse_image(b"registry.example.com/myimage").unwrap();
        assert_eq!(reg, b"registry.example.com");
        assert_eq!(repo, b"myimage");
    }

    #[test]
    fn test_app_arm_present() {
        assert_eq!(app_arm(b"present", b"93"), Some(AppArm::Scan));
        assert_eq!(app_arm(b"present", b"0"), Some(AppArm::RefuseVacuous));
        assert_eq!(app_arm(b"present", b""), Some(AppArm::RefuseVacuous));
    }

    #[test]
    fn test_app_arm_absent() {
        assert_eq!(app_arm(b"absent", b"0"), Some(AppArm::SkipAbsent));
        // A tree that comes back must be scanned, not waved through.
        assert_eq!(app_arm(b"absent", b"12"), Some(AppArm::RefuseUnexpected));
        assert_eq!(app_arm(b"absent", b""), Some(AppArm::RefuseUnknown));
    }

    #[test]
    fn test_app_arm_rejects_other_values() {
        assert_eq!(app_arm(b"", b"0"), None);
        assert_eq!(app_arm(b"Absent", b"0"), None);
        assert_eq!(app_arm(b"none", b"0"), None);
    }

    #[test]
    fn test_valid_digest_boundary() {
        assert!(valid_digest(b"sha256:0"));
        assert!(!valid_digest(b"sha256"));
        assert!(!valid_digest(b"sha25:x"));
    }
}
