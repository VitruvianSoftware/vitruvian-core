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

//! CLI installers. Every installer is idempotent and skips a tool already on
//! PATH, so after the first session (which the cloud environment snapshots)
//! the cost is a few `command -v` lookups. Only what has to exist BEFORE bazel
//! can run is installed here: bazelisk honours .bazelversion, and the repo's
//! own toolchains (//tools:bazel_env) own everything else.
//!
//! Pinned so a session is reproducible and a surprise major cannot land in the
//! middle of an incident; override per session with the matching env var.
//! bazelisk and direnv are deliberately taken from their version-less "latest"
//! assets: bazelisk is a launcher whose only job is to honour .bazelversion,
//! and direnv only execs .envrc.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::sh::{self, has};
use crate::{note, warn, Ctx};

const GH_VERSION: &str = "2.96.0";
const GCLOUD_VERSION: &str = "577.0.0";
const PULUMI_VERSION: &str = "3.254.0";
const TAILSCALE_VERSION: &str = "1.98.9";

fn is_arm() -> bool {
    matches!(std::env::consts::ARCH, "aarch64" | "arm")
}

fn arch_deb() -> &'static str {
    if is_arm() {
        "arm64"
    } else {
        "amd64"
    }
}

/// Google publishes the Cloud CLI as `linux-x86_64` and `linux-arm` (there is
/// no `linux-arm64`, which the shell version asked for and got a 404).
fn arch_gcloud() -> &'static str {
    gcloud_arch(std::env::consts::ARCH)
}

fn gcloud_arch(arch: &str) -> &'static str {
    if matches!(arch, "aarch64" | "arm") {
        "arm"
    } else {
        "x86_64"
    }
}

/// `${TMPDIR:-/tmp}/<name>.$$<suffix>`.
fn tmp(name: &str, suffix: &str) -> PathBuf {
    let dir = sh::env_or("TMPDIR", "/tmp");
    let mut p = sh::lossy(&dir);
    p.push('/');
    p.push_str(&format!("{name}.{}{suffix}", std::process::id()));
    PathBuf::from(p)
}

pub struct Installer<'a> {
    ctx: &'a Ctx,
    /// `sudo` when not root and sudo exists, computed once on first use.
    sudo: bool,
}

impl<'a> Installer<'a> {
    pub fn new(ctx: &'a Ctx) -> Self {
        let uid = sh::capture(Command::new("id").arg("-u"));
        let root = uid.ok && sh::subst(uid.stdout) == b"0";
        let sudo = uid.ok && !root && has("sudo");
        Installer { ctx, sudo }
    }

    /// A command run with the privilege prefix ("${priv[@]}").
    fn privileged(&self, prog: &str) -> Command {
        if self.sudo {
            let mut c = Command::new("sudo");
            c.arg(prog);
            c
        } else {
            Command::new(prog)
        }
    }

    fn dest(&self, name: &str) -> PathBuf {
        self.ctx.install_dir.join(name)
    }

    /// fetch_to: download, or fail with the URL named.
    fn fetch_to(&self, url: &str, dest: &Path) -> bool {
        let ok = sh::run(
            Command::new("curl")
                .args(["-fsSL", "--retry", "3", "--retry-delay", "2", "-o"])
                .arg(dest)
                .arg(url),
        );
        if !ok {
            warn(&format!("download failed: {url}"));
        }
        ok
    }

    /// install_bin: chmod +x, then move into the install dir.
    fn install_bin(&self, src: &Path, name: &str) -> bool {
        let made_exec = match fs::metadata(src) {
            Ok(m) => {
                let mode = m.permissions().mode() | 0o111;
                fs::set_permissions(src, fs::Permissions::from_mode(mode)).is_ok()
            }
            Err(_) => false,
        };
        made_exec && sh::run(self.privileged("mv").arg(src).arg(self.dest(name)))
    }

    fn untar(&self, archive: &Path, dir: &Path) -> bool {
        fs::create_dir_all(dir).is_ok()
            && sh::run(
                Command::new("tar")
                    .arg("-xzf")
                    .arg(archive)
                    .arg("-C")
                    .arg(dir)
                    .arg("--strip-components=1"),
            )
    }

    fn install_mode(&self, src: &Path, name: &str) -> bool {
        sh::run(
            self.privileged("install")
                .args(["-m", "0755"])
                .arg(src)
                .arg(self.dest(name)),
        )
    }

    fn link(&self, target: &Path, name: &str) -> bool {
        sh::run(
            self.privileged("ln")
                .arg("-sf")
                .arg(target)
                .arg(self.dest(name)),
        )
    }

    fn bazel(&self) -> bool {
        if has("bazel") {
            return true;
        }
        let t = tmp("bazelisk", "");
        let url = format!(
            "https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-{}",
            arch_deb()
        );
        // Installed under BOTH names: `bazelisk` is what it is, `bazel` is what
        // every doc in this repo types. bazelisk then reads .bazelversion.
        self.fetch_to(&url, &t)
            && self.install_bin(&t, "bazelisk")
            && self.link(&self.dest("bazelisk"), "bazel")
    }

    fn direnv(&self) -> bool {
        if has("direnv") {
            return true;
        }
        let t = tmp("direnv", "");
        let url = format!(
            "https://github.com/direnv/direnv/releases/latest/download/direnv.linux-{}",
            arch_deb()
        );
        if !(self.fetch_to(&url, &t) && self.install_bin(&t, "direnv")) {
            return false;
        }
        // .envrc puts the //tools:bazel_env bin tree on PATH; without the shell
        // hook it never fires and every tool it exports looks "missing".
        if !sh::file_contains(&self.ctx.bashrc, b"direnv hook bash") {
            return sh::append(&self.ctx.bashrc, b"\neval \"$(direnv hook bash)\"\n").is_ok();
        }
        true
    }

    fn gh(&self) -> bool {
        if has("gh") {
            return true;
        }
        let v = sh::env_str("GH_VERSION", GH_VERSION);
        let (t, dir) = (tmp("gh", ".tar.gz"), tmp("gh", ".d"));
        let url = format!(
            "https://github.com/cli/cli/releases/download/v{v}/gh_{v}_linux_{}.tar.gz",
            arch_deb()
        );
        if !(self.fetch_to(&url, &t)
            && self.untar(&t, &dir)
            && self.install_mode(&dir.join("bin/gh"), "gh"))
        {
            return false;
        }
        let _ = fs::remove_file(&t);
        let _ = fs::remove_dir_all(&dir);
        true
    }

    fn gcloud(&self) -> bool {
        if has("gcloud") {
            return true;
        }
        let v = sh::env_str("GCLOUD_VERSION", GCLOUD_VERSION);
        let t = tmp("gcloud", ".tar.gz");
        let root = sh::path(&sh::env_or("CLOUD_BOOTSTRAP_GCLOUD_ROOT", "/usr/local"));
        let url = format!(
            "https://storage.googleapis.com/cloud-sdk-release/google-cloud-cli-{v}-linux-{}.tar.gz",
            arch_gcloud()
        );
        if !(self.fetch_to(&url, &t)
            && sh::run(
                self.privileged("tar")
                    .arg("-xzf")
                    .arg(&t)
                    .arg("-C")
                    .arg(&root),
            ))
        {
            return false;
        }
        let _ = fs::remove_file(&t);
        let bin = root.join("google-cloud-sdk/bin");
        // The status is the last link's, as the shell function's was.
        let _ = self.link(&bin.join("gcloud"), "gcloud");
        self.link(&bin.join("gsutil"), "gsutil")
    }

    fn pulumi(&self) -> bool {
        if has("pulumi") {
            return true;
        }
        let v = sh::env_str("PULUMI_VERSION", PULUMI_VERSION);
        let a = if is_arm() { "arm64" } else { "x64" };
        let (t, dir) = (tmp("pulumi", ".tar.gz"), tmp("pulumi", ".d"));
        let url = format!("https://get.pulumi.com/releases/sdk/pulumi-v{v}-linux-{a}.tar.gz");
        if !(self.fetch_to(&url, &t) && self.untar(&t, &dir)) {
            return false;
        }
        // install -m 0755 "$dir"/pulumi* "$INSTALL_DIR/" 2>/dev/null
        let mut bins: Vec<PathBuf> = fs::read_dir(&dir)
            .map(|rd| {
                rd.filter_map(|e| e.ok())
                    .filter(|e| e.file_name().to_string_lossy().starts_with("pulumi"))
                    .map(|e| e.path())
                    .collect()
            })
            .unwrap_or_default();
        bins.sort();
        if !bins.is_empty() {
            let _ = sh::quiet(
                self.privileged("install")
                    .args(["-m", "0755"])
                    .args(&bins)
                    .arg(format!("{}/", sh::path_str(&self.ctx.install_dir))),
            );
        }
        let _ = fs::remove_file(&t);
        let _ = fs::remove_dir_all(&dir);
        has("pulumi")
    }

    fn tailscale(&self) -> bool {
        // Both binaries or nothing: tailscale-up.sh runs `tailscaled` (the
        // daemon) and then `tailscale` (the client), so a half-install is worse
        // than none.
        if has("tailscale") && has("tailscaled") {
            return true;
        }
        let v = sh::env_str("TAILSCALE_VERSION", TAILSCALE_VERSION);
        let (t, dir) = (tmp("tailscale", ".tgz"), tmp("tailscale", ".d"));
        // The pinned static tarball, not install.sh: that detects the distro and
        // shells out to apt, which this sandbox does not need.
        let url = format!(
            "https://pkgs.tailscale.com/stable/tailscale_{v}_{}.tgz",
            arch_deb()
        );
        if !(self.fetch_to(&url, &t)
            && self.untar(&t, &dir)
            && self.install_mode(&dir.join("tailscale"), "tailscale")
            && self.install_mode(&dir.join("tailscaled"), "tailscaled"))
        {
            return false;
        }
        let _ = fs::remove_file(&t);
        let _ = fs::remove_dir_all(&dir);
        true
    }

    fn kubectl(&self) -> bool {
        // kube-setup.sh already installs kubectl for the homelab path; this is
        // here so a profile that wants kubectl without the tailnet hooks gets it.
        if has("kubectl") {
            return true;
        }
        let mut ver = sh::lossy(&sh::env_or_empty("KUBECTL_VERSION"));
        if ver.is_empty() {
            let r = sh::capture(
                Command::new("curl")
                    .arg("-fsSL")
                    .arg("https://dl.k8s.io/release/stable.txt"),
            );
            ver = sh::lossy(&sh::subst(r.stdout));
        }
        if ver.is_empty() {
            warn("could not resolve the stable kubectl version");
            return false;
        }
        let t = tmp("kubectl", "");
        let url = format!(
            "https://dl.k8s.io/release/{ver}/bin/linux/{}/kubectl",
            arch_deb()
        );
        self.fetch_to(&url, &t) && self.install_bin(&t, "kubectl")
    }

    /// install_tools: install every key of the list; best-effort, always Ok.
    pub fn install_all(&self, tools: &[String]) {
        if tools.is_empty() {
            return;
        }
        let mut ok = 0;
        let mut failed: Vec<&str> = Vec::new();
        for key in tools {
            let done = match key.as_str() {
                "bazel" => self.bazel(),
                "direnv" => self.direnv(),
                "gh" => self.gh(),
                "gcloud" => self.gcloud(),
                "pulumi" => self.pulumi(),
                "kubectl" => self.kubectl(),
                "tailscale" => self.tailscale(),
                other => {
                    warn(&format!(
                        "unknown tool key '{other}' in profiles.tsv — ignoring"
                    ));
                    continue;
                }
            };
            if done {
                ok += 1;
            } else {
                failed.push(key);
            }
        }
        if !failed.is_empty() {
            warn(&format!(
                "install failed for: {} (the session continues without them)",
                failed.join(" ")
            ));
        }
        note(&format!("installed/verified {ok} tool(s)"));
    }
}

#[cfg(test)]
mod tests {
    use super::gcloud_arch;

    #[test]
    fn gcloud_asset_names_are_the_published_ones() {
        // google-cloud-cli-<v>-linux-{x86_64,arm}.tar.gz; `linux-arm64` is a 404.
        assert_eq!(gcloud_arch("x86_64"), "x86_64");
        assert_eq!(gcloud_arch("aarch64"), "arm");
    }
}
