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

//! //tools/ci:image_sbom_scan_test. Runs the REAL binary against a fake
//! registry: a fake `curl` serving an image index, its attestation manifest and
//! the SPDX blob from fixtures, the hermetic jq, and a fake `osv-scanner`. The
//! lib tests cover the digest parsing and the APP_TREE decision table; this
//! covers the fetch-and-filter flow they cannot, including the jq filters
//! themselves. One of those (the attestation selector) shipped with its last
//! quote eaten by a Rust raw string, so jq refused to compile it and every
//! published image read as "carries no attestation manifests".

use ci_testkit::{bin, read, write, write_exe, Output, Run, TempDir};
use std::path::{Path, PathBuf};

const IMAGE: &str = "ghcr.io/vitruviansoftware/demo";
const INDEX: &str = "sha256:1111111111111111111111111111111111111111111111111111111111111111";
const PLATFORM: &str = "sha256:2222222222222222222222222222222222222222222222222222222222222222";
const ATT: &str = "sha256:3333333333333333333333333333333333333333333333333333333333333333";
const SBOM: &str = "sha256:4444444444444444444444444444444444444444444444444444444444444444";

/// `curl ... [-o FILE] URL`: the token endpoint prints a token, anything
/// under /manifests/ or /blobs/ is served from `$REG/<kind>/<digest>`.
/// `$CURL_FAIL` (a substring of the URL) makes that request exit 22.
const FAKE_CURL: &str = r#"#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REG/curl.log"
out=''; url=''
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; https://*) url="$1" ;; esac
  shift
done
if [ -n "${CURL_FAIL:-}" ] && [[ "$url" == *"$CURL_FAIL"* ]]; then
  echo "curl: (22) The requested URL returned error: 404" >&2; exit 22
fi
case "$url" in
  */token\?*) printf '{"token":"tok-123"}' ;;
  */manifests/*) src="$REG/manifests/${url##*/}" ;;
  */blobs/*) src="$REG/blobs/${url##*/}" ;;
esac
if [ -n "${src:-}" ]; then
  [ -f "$src" ] || { echo "curl: (22) no fixture for $url" >&2; exit 22; }
  if [ -n "$out" ]; then cp "$src" "$out"; else cat "$src"; fi
fi
"#;

/// `osv-scanner scan source --sbom=F --format table|markdown`: logs the
/// call; the table (blocking) arm exits `$OSV_RC`.
const FAKE_OSV: &str = r#"#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REG/osv.log"
case "$*" in
  *"--format table"*) echo "table for $3"; exit "${OSV_RC:-0}" ;;
  *) echo "No issues found" ;;
esac
"#;

fn index(with_attestation: bool) -> String {
    let att = if with_attestation {
        format!(
            r#",{{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"{ATT}","platform":{{"architecture":"unknown","os":"unknown"}},"annotations":{{"vnd.docker.reference.type":"attestation-manifest","vnd.docker.reference.digest":"{PLATFORM}"}}}}"#
        )
    } else {
        String::new()
    };
    format!(
        r#"{{"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"{PLATFORM}","platform":{{"architecture":"amd64","os":"linux"}}}}{att}]}}"#
    )
}

fn attestation(with_sbom: bool) -> String {
    let sbom = if with_sbom {
        format!(
            r#",{{"digest":"{SBOM}","annotations":{{"in-toto.io/predicate-type":"https://spdx.dev/Document"}}}}"#
        )
    } else {
        String::new()
    };
    format!(
        r#"{{"layers":[{{"digest":"sha256:5555","annotations":{{"in-toto.io/predicate-type":"https://slsa.dev/provenance/v0.2"}}}}{sbom}]}}"#
    )
}

/// An in-toto statement whose SPDX predicate lists `app` packages under
/// /app/node_modules and two system ones.
fn sbom_blob(app: usize) -> String {
    let mut pkgs: Vec<String> = (0..app)
        .map(|i| {
            format!(
                r#"{{"name":"a{i}","sourceInfo":"acquired package info from installed node module manifest file: /app/node_modules/a{i}/package.json"}}"#
            )
        })
        .collect();
    pkgs.push(r#"{"name":"libc","sourceInfo":"acquired package info from DPKG DB: /var/lib/dpkg/status"}"#.into());
    pkgs.push(r#"{"name":"tzdata"}"#.into());
    format!(
        r#"{{"_type":"https://in-toto.io/Statement/v0.1","predicate":{{"spdxVersion":"SPDX-2.3","packages":[{}],"relationships":[{{"x":1}}],"files":[{{"y":1}}]}}}}"#,
        pkgs.join(",")
    )
}

struct Reg {
    dir: TempDir,
}

impl Reg {
    fn new(index_json: &str, att_json: &str, blob: &str) -> Reg {
        let dir = TempDir::new();
        write_exe(dir.join("fakes/curl"), FAKE_CURL);
        write_exe(dir.join("fakes/osv-scanner"), FAKE_OSV);
        if let Some(jq) = jq() {
            std::os::unix::fs::symlink(jq, dir.join("fakes/jq")).unwrap();
        }
        write(dir.join(format!("manifests/{INDEX}")), index_json);
        write(dir.join(format!("manifests/{ATT}")), att_json);
        write(dir.join(format!("blobs/{SBOM}")), blob);
        Reg { dir }
    }
    fn standard(app: usize) -> Reg {
        Reg::new(&index(true), &attestation(true), &sbom_blob(app))
    }
    fn summary(&self) -> PathBuf {
        self.dir.join("summary.md")
    }
    fn run(&self, env: &[(&str, &str)]) -> Output {
        let mut r = Run::new(&bin("BIN"))
            .cwd(self.dir.path())
            .env(
                "PATH",
                format!("{}:/usr/bin:/bin", self.dir.join("fakes").display()),
            )
            .env("REG", self.dir.path())
            .env("IMAGE", IMAGE)
            .env("DIGEST", INDEX)
            .env("GITHUB_STEP_SUMMARY", self.summary());
        for (k, v) in env {
            r = r.env(k, v);
        }
        r.go_within(std::time::Duration::from_secs(60))
            .expect("image-sbom-scan hung")
    }
    fn osv(&self) -> Vec<String> {
        read(self.dir.join("osv.log"))
            .lines()
            .map(str::to_string)
            .collect()
    }
    fn curl(&self) -> String {
        read(self.dir.join("curl.log"))
    }
}

/// The hermetic jq from JQ_BIN ($(JQ_BIN) is an execroot path; in runfiles
/// an external repo sits beside _main). Unset: the ambient jq.
fn jq() -> Option<PathBuf> {
    let jq = std::env::var("JQ_BIN").ok()?;
    let p = match jq.find("external/") {
        Some(i) => Path::new("..").join(&jq[i + "external/".len()..]),
        None => PathBuf::from(&jq),
    };
    Some(std::fs::canonicalize(&p).unwrap_or_else(|e| panic!("JQ_BIN={jq}: {e}")))
}

#[test]
fn absent_tree_scans_the_whole_image_and_reports() {
    let r = Reg::standard(0);
    let o = r.run(&[("APP_TREE", "absent")]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert!(
        o.stdout
            .contains(&format!("==> attestation {ATT} (subject {PLATFORM})")),
        "{}",
        o.stdout
    );
    assert!(
        o.stdout
            .contains("    2 packages total, 0 under /app/node_modules"),
        "{}",
        o.stdout
    );
    assert!(o
        .stdout
        .contains("--> BLOCKING scan: skipped, APP_TREE=absent"));
    assert!(o.stdout.contains("==> 1 SBOM attestation(s) scanned"));
    let osv = r.osv();
    assert_eq!(osv.len(), 1, "only the reporting arm: {osv:?}");
    assert!(
        osv[0].ends_with(&format!("{}.spdx.json --format markdown", &PLATFORM[7..])),
        "{osv:?}"
    );
    let summary = read(r.summary());
    assert!(
        summary.starts_with(&format!("### Image SBOM \u{2014} `{PLATFORM}`\n")),
        "{summary}"
    );
    assert!(summary.contains("`2` packages, `0` under `/app/node_modules` (the blocking arm)."));
    assert!(summary.contains("No issues found"));
}

#[test]
fn present_tree_blocks_on_the_app_packages_only() {
    let r = Reg::standard(3);
    let o = r.run(&[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert!(
        o.stdout
            .contains("--> BLOCKING scan: /app/node_modules (3 packages)"),
        "{}",
        o.stdout
    );
    assert!(o
        .stdout
        .contains("no advisories in the application dependency tree"));
    let osv = r.osv();
    assert_eq!(osv.len(), 2, "{osv:?}");
    assert!(osv[0].contains(".app.spdx.json --format table"), "{osv:?}");
    assert!(
        osv[1].contains(".spdx.json --format markdown") && !osv[1].contains(".app."),
        "{osv:?}"
    );
    assert!(
        o.stdout
            .contains("    5 packages total, 3 under /app/node_modules"),
        "{}",
        o.stdout
    );
}

#[test]
fn advisories_in_the_app_tree_block() {
    let r = Reg::standard(2);
    let o = r.run(&[("OSV_RC", "1")]);
    assert_eq!(o.code, 1);
    assert!(
        o.stderr
            .contains("::error::advisories found under /app/node_modules"),
        "{}",
        o.stderr
    );
    assert!(
        read(r.summary()).contains("### Image SBOM"),
        "the report is still written"
    );
}

#[test]
fn zero_app_packages_with_present_refuses() {
    let r = Reg::standard(0);
    let o = r.run(&[("APP_TREE", "present")]);
    assert_eq!(o.code, 1);
    assert!(
        o.stderr.contains("the blocking arm would pass vacuously"),
        "{}",
        o.stderr
    );
}

#[test]
fn app_packages_with_absent_refuses() {
    let r = Reg::standard(1);
    let o = r.run(&[("APP_TREE", "absent")]);
    assert_eq!(o.code, 1);
    assert!(
        o.stderr
            .contains("APP_TREE=absent, but 1 packages sit under /app/node_modules"),
        "{}",
        o.stderr
    );
}

#[test]
fn an_index_without_attestations_refuses() {
    let r = Reg::new(&index(false), &attestation(true), &sbom_blob(0));
    let o = r.run(&[("APP_TREE", "absent")]);
    assert_eq!(o.code, 1);
    assert!(
        o.stderr.contains("carries no attestation manifests"),
        "{}",
        o.stderr
    );
}

#[test]
fn an_attestation_without_an_sbom_refuses() {
    let r = Reg::new(&index(true), &attestation(false), &sbom_blob(0));
    let o = r.run(&[("APP_TREE", "absent")]);
    assert_eq!(o.code, 1);
    assert!(
        o.stderr
            .contains("has no https://spdx.dev/Document predicate"),
        "{}",
        o.stderr
    );
}

#[test]
fn a_platform_digest_is_not_an_index() {
    let r = Reg::new(
        r#"{"mediaType":"application/vnd.oci.image.manifest.v1+json","layers":[]}"#,
        "",
        "",
    );
    let o = r.run(&[("APP_TREE", "absent")]);
    assert_eq!(o.code, 1);
    assert!(
        o.stderr.contains(
            "is not an image index (mediaType: application/vnd.oci.image.manifest.v1+json)"
        ),
        "{}",
        o.stderr
    );
}

#[test]
fn a_failed_token_fetch_exits_with_curls_status() {
    let r = Reg::standard(0);
    let o = r.run(&[("APP_TREE", "absent"), ("CURL_FAIL", "/token")]);
    assert_eq!(o.code, 22, "{}", o.all());
    assert!(
        o.stderr.contains("curl: (22)"),
        "curl's own error is shown: {}",
        o.stderr
    );
}

#[test]
fn a_failed_sbom_download_fails_closed() {
    let r = Reg::standard(0);
    let o = r.run(&[("APP_TREE", "absent"), ("CURL_FAIL", "/blobs/")]);
    assert_ne!(o.code, 0);
    assert!(o.stderr.contains("curl: (22)"), "{}", o.stderr);
    assert!(r.osv().is_empty(), "nothing scanned");
}

#[test]
fn every_registry_call_carries_the_token() {
    let r = Reg::standard(0);
    let o = r.run(&[("APP_TREE", "absent")]);
    assert_eq!(o.code, 0, "{}", o.all());
    let log = r.curl();
    let calls: Vec<&str> = log.lines().collect();
    assert!(
        calls[0].contains(
            "https://ghcr.io/token?scope=repository:vitruviansoftware/demo:pull&service=ghcr.io"
        ),
        "{log}"
    );
    for c in &calls[1..] {
        assert!(c.contains("-H Authorization: Bearer tok-123"), "{c}");
    }
    assert!(log.contains(&format!(
        "https://ghcr.io/v2/vitruviansoftware/demo/blobs/{SBOM}"
    )));
}

#[test]
fn without_a_step_summary_the_report_goes_to_stdout() {
    let r = Reg::standard(0);
    let o = r.run(&[("APP_TREE", "absent"), ("GITHUB_STEP_SUMMARY", "")]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert!(
        o.stdout
            .contains(&format!("### Image SBOM \u{2014} `{PLATFORM}`")),
        "{}",
        o.stdout
    );
}

#[test]
fn bad_inputs_are_refused() {
    let r = Reg::standard(0);
    assert_eq!(r.run(&[("DIGEST", "latest")]).code, 1);
    assert_eq!(r.run(&[("APP_TREE", "maybe")]).code, 1);
}
