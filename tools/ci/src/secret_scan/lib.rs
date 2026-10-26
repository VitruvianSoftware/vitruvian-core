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

//! secret-scan.sh — gitleaks gate over the commits a change INTRODUCES.

use shell_compat::{capture, cat, env_or_empty, err, out, status, subst};
use std::process::Command;

const GITLEAKS_VERSION: &str = "8.30.1";
const GITLEAKS_SHA256: &str = "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb";

pub fn run(_args: &[Vec<u8>]) -> i32 {
    // cd to git root
    let root_r = capture(
        49,
        Command::new("git").arg("rev-parse").arg("--show-toplevel"),
    );
    let root = subst(root_r.stdout);
    if root.is_empty() || root_r.status != 0 {
        err(b"secret-scan: could not determine git root\n");
        return 1;
    }
    if std::env::set_current_dir(shell_compat::path(&root)).is_err() {
        err(b"secret-scan: could not cd to git root\n");
        return 1;
    }

    // Resolve scan range.
    let base_rev = env_or_empty("BASE_REV");
    let base_ref = env_or_empty("BASE_REF");
    let mut range: Vec<u8> = Vec::new();

    if !base_rev.is_empty() {
        let r = capture(
            59,
            Command::new("git")
                .arg("rev-parse")
                .arg("--verify")
                .arg("--quiet")
                .arg(shell_compat::os(&cat(&[&base_rev, b"^{commit}"])))
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
        );
        if r.status == 0 {
            range = cat(&[&base_rev, b"..HEAD"]);
        }
    } else if !base_ref.is_empty() {
        let r = capture(
            62,
            Command::new("git")
                .arg("merge-base")
                .arg(shell_compat::os(&cat(&[b"origin/", &base_ref])))
                .arg("HEAD")
                .stderr(std::process::Stdio::null()),
        );
        if r.status == 0 {
            let base = subst(r.stdout);
            if !base.is_empty() {
                range = cat(&[&base, b"..HEAD"]);
            }
        }
    }

    // Install gitleaks.
    let bin_dir = match shell_compat::mktemp_dir() {
        Ok(d) => d,
        Err(e) => {
            err(&cat(&[
                b"secret-scan: mktemp failed: ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            return 1;
        }
    };

    let use_system = env_or_empty("USE_SYSTEM_GITLEAKS");
    let gitleaks: Vec<u8>;

    if use_system == b"1" {
        if let Some(sys) = shell_compat::which(b"gitleaks") {
            let sys_bytes = shell_compat::path_bytes(&sys);
            // Check version.
            let ver_r = capture(
                80,
                Command::new(shell_compat::os(&sys_bytes))
                    .arg("version")
                    .stderr(std::process::Stdio::null()),
            );
            let system_version = shell_compat::strip_cr_lf(&subst(ver_r.stdout));
            if system_version != GITLEAKS_VERSION.as_bytes() {
                let ver_display = if system_version.is_empty() {
                    b"<no version>".to_vec()
                } else {
                    system_version.clone()
                };
                err(&cat(&[
                    b"::error::secret-scan: USE_SYSTEM_GITLEAKS=1 but ",
                    &sys_bytes,
                    b" reports\n'",
                    &ver_display,
                    b"', not the pinned v",
                    GITLEAKS_VERSION.as_bytes(),
                    b". A scan by\na different gitleaks is not the scan CI runs -- its rules and detectors differ --\nso its result must not be reported as this gate's.\n  * Install v",
                    GITLEAKS_VERSION.as_bytes(),
                    b", or unset USE_SYSTEM_GITLEAKS to use the pinned,\n    checksum-verified download (Linux only -- see the exec-failure note below).\n",
                ]));
                let _ = std::fs::remove_dir_all(shell_compat::path(&bin_dir));
                return 1;
            }
            gitleaks = sys_bytes;
        } else {
            // gitleaks not on PATH, fall through to download
            gitleaks = download_gitleaks(&bin_dir);
            if gitleaks.is_empty() {
                let _ = std::fs::remove_dir_all(shell_compat::path(&bin_dir));
                return 1;
            }
        }
    } else {
        gitleaks = download_gitleaks(&bin_dir);
        if gitleaks.is_empty() {
            let _ = std::fs::remove_dir_all(shell_compat::path(&bin_dir));
            return 1;
        }
    }

    // Scan.
    let rc = if !range.is_empty() {
        out(&cat(&[b"secret-scan: scanning commits in ", &range, b"\n"]));
        status(
            111,
            Command::new(shell_compat::os(&gitleaks))
                .arg("git")
                .arg("--no-banner")
                .arg("--redact")
                .arg("--config")
                .arg(".gitleaks.toml")
                .arg(shell_compat::os(&cat(&[b"--log-opts=", &range])))
                .arg("."),
            false,
        )
    } else {
        out(b"secret-scan: no diff base resolved \xe2\x80\x94 scanning the working tree (fail-safe).\n");
        status(
            116,
            Command::new(shell_compat::os(&gitleaks))
                .arg("dir")
                .arg("--no-banner")
                .arg("--redact")
                .arg("--config")
                .arg(".gitleaks.toml")
                .arg("."),
            false,
        )
    };

    let _ = std::fs::remove_dir_all(shell_compat::path(&bin_dir));

    if rc == 126 || rc == 127 {
        err(&cat(&[
            b"::error::secret-scan: gitleaks did not run (exit ",
            rc.to_string().as_bytes(),
            b") -- this is an exec\nfailure, NOT a secret finding. The fetched binary is Linux-only; on macOS (or\nany non-Linux host) it cannot execute.\n  * Install gitleaks locally (e.g. `brew install gitleaks`) and re-run with\n    USE_SYSTEM_GITLEAKS=1, or run this script on Linux/in CI.\n",
        ]));
        return rc;
    }

    if rc != 0 {
        err(b"::error::secret-scan: gitleaks found a candidate secret in the commits this change adds.\n  * If it IS a secret: remove it, then ROTATE it -- it is in the branch history\n    and rewriting that history does not un-share it.\n  * If it is a false positive that is safe BY CONSTRUCTION (e.g. ciphertext),\n    add a scoped allowlist entry to .gitleaks.toml explaining why.\n  * For a genuine one-off, put a `gitleaks:allow` comment on that line.\n");
        return rc;
    }

    out(b"secret-scan: no secrets found in the added commits.\n");
    0
}

fn download_gitleaks(bin_dir: &[u8]) -> Vec<u8> {
    let tarball = cat(&[bin_dir, b"/gitleaks.tar.gz"]);
    let url = cat(&[
        b"https://github.com/gitleaks/gitleaks/releases/download/v",
        GITLEAKS_VERSION.as_bytes(),
        b"/gitleaks_",
        GITLEAKS_VERSION.as_bytes(),
        b"_linux_x64.tar.gz",
    ]);
    out(&cat(&[
        b"secret-scan: fetching gitleaks v",
        GITLEAKS_VERSION.as_bytes(),
        b"...\n",
    ]));
    let rc = status(
        96,
        Command::new("curl")
            .arg("-fsSL")
            .arg("--retry")
            .arg("5")
            .arg("--retry-delay")
            .arg("2")
            .arg("--retry-all-errors")
            .arg("--max-time")
            .arg("120")
            .arg("-o")
            .arg(shell_compat::os(&tarball))
            .arg(shell_compat::os(&url)),
        false,
    );
    if rc != 0 {
        err(b"secret-scan: failed to download gitleaks\n");
        return Vec::new();
    }

    // Checksum verify: sha256sum <tarball> | awk '{print $1}'
    let sha_r = capture(
        97,
        Command::new("sha256sum").arg(shell_compat::os(&tarball)),
    );
    let actual = {
        let out = subst(sha_r.stdout);
        let first = shell_compat::first_line(&out);
        match first.iter().position(|&c| c == b' ') {
            Some(i) => first[..i].to_vec(),
            None => first,
        }
    };
    if actual != GITLEAKS_SHA256.as_bytes() {
        err(&cat(&[
            b"::error::gitleaks checksum mismatch \xe2\x80\x94 expected ",
            GITLEAKS_SHA256.as_bytes(),
            b", got ",
            &actual,
            b"\n",
        ]));
        return Vec::new();
    }

    // Extract
    let rc = status(
        102,
        Command::new("tar")
            .arg("-xzf")
            .arg(shell_compat::os(&tarball))
            .arg("-C")
            .arg(shell_compat::os(bin_dir))
            .arg("gitleaks"),
        false,
    );
    if rc != 0 {
        err(b"secret-scan: failed to extract gitleaks\n");
        return Vec::new();
    }

    cat(&[bin_dir, b"/gitleaks"])
}
