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

//! `bazel run //tools/cloud-bootstrap:configure-tailscale` writes
//! `.claude/tailscale-up.sh`, the SessionStart hook that joins a Claude Code
//! cloud sandbox to the tailnet: the self-hosted Headscale control plane
//! (`https://headscale.ipv1337.dev`) and subnet-routed homelab access
//! (`--accept-routes=true`).
//!
//! Usage:
//!   bazel run //tools/cloud-bootstrap:configure-tailscale
//!   bazel run //tools/cloud-bootstrap:configure-tailscale -- --check
//!   bazel run //tools/cloud-bootstrap:configure-tailscale -- --file <path>
//!
//! `--check` exits 1 (printing a unified diff) when the file differs from what
//! this tool would write. Exit 2 is a usage error. Ported from
//! configure-tailscale.sh with the same output, exit codes and messages.
//!
//! The hook itself is NOT edited here by hand: `.claude/*.sh` changes need
//! James's approval, so change [`HOOK`] and the file together in one reviewed
//! PR. `:configure-tailscale_test` fails when they differ.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The exact contents written to `.claude/tailscale-up.sh`.
pub const HOOK: &str = r##"#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Join this Claude Code *cloud* sandbox to the tailnet so a web/mobile session
# can reach tailnet-only devices (homelab boxes, internal services).
#
# Best-effort by design: a Tailscale hiccup must never block the Claude session,
# so every failure path exits 0 (mirrors devx-tailscale-up.service).
#
# Why a SessionStart hook and not the cloud "Setup script": the cloud
# environment cache snapshots files, not running processes, so a daemon started
# in the Setup script would not be running on cached/resumed sessions. The
# BINARY is installed by //tools/cloud-bootstrap, which .claude/session-start.sh
# runs to completion before this, for any profile whose `tools` column lists
# tailscale; this hook (re)starts the daemon each session.
#
# Why userspace networking: the sandbox has no TUN device and all egress is
# forced through an HTTP/HTTPS proxy, so raw WireGuard cannot leave. tailscaled
# dials control + DERP through $HTTPS_PROXY and exposes a local SOCKS5/HTTP proxy
# on :1055 for reaching peers. Connectivity is DERP-relayed, not direct.
#
# Reach peers once up:  curl --proxy socks5h://localhost:1055 http://<peer>/
set -uo pipefail

# Cloud sessions only — no-op on a local checkout.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

# Pick up anything //tools/cloud-bootstrap resolved for this session's profile.
# Hooks are separate processes, so a TS_AUTHKEY it fetched from Secret Manager is
# NOT in this one's environment — without this, the `homelab` profile's whole
# point (rotate the auth key in one place, no cloud-environment edit) would not
# reach tailscaled. A TS_AUTHKEY set directly on the environment still works
# unchanged; cloud-bootstrap leaves those alone.
_session_env="$HOME/.config/vitruvian-core/cloud/session.env"
# shellcheck disable=SC1090 # path is fixed; the file is 0600 and machine-written
[ -f "$_session_env" ] && . "$_session_env"

if ! command -v tailscale >/dev/null 2>&1; then
	echo "tailscale-up: binary missing — this session's \$VITRUVIAN_PROFILE does not list" >&2
	echo "  tailscale (see tools/cloud-bootstrap/profiles.tsv); add it, or use a profile that does" >&2
	exit 0
fi

# Use sudo for privileged commands only when we are not already root.
priv=()
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
	priv=(sudo)
fi

# Already connected (e.g. a resumed session reusing the same VM)? Nothing to do.
if "${priv[@]}" tailscale status >/dev/null 2>&1; then
	echo "tailscale-up: already connected"
	exit 0
fi

if [ -z "${TS_AUTHKEY:-}" ]; then
	echo "tailscale-up: TS_AUTHKEY not set — add it to the cloud environment variables" >&2
	exit 0
fi

# Userspace networking + dial out via the sandbox proxy; expose SOCKS5/HTTP on :1055.
tailscaled_args=(
	--tun=userspace-networking
	--socks5-server=localhost:1055
	--outbound-http-proxy-listen=localhost:1055
	--statedir=/var/lib/tailscale
)
"${priv[@]}" tailscaled "${tailscaled_args[@]}" >/tmp/tailscaled.log 2>&1 &

# tailscaled reports ready a beat after its socket appears; poll briefly.
for _ in $(seq 1 20); do
	"${priv[@]}" tailscale status >/dev/null 2>&1 && break
	sleep 0.5
done

# --accept-routes=true: allow userspace SOCKS5 (:1055) to reach homelab LAN
# routes (192.168.86.0/24, including k8s-api.lab.ipv1337.dev -> 192.168.86.64)
# advertised by homelab-subnet-router. The node joins untagged (a personal
# device) so it inherits the owner's access to their own devices.
# TS_AUTHKEY must be reusable and permit untagged device registration.
up_args=(
	--authkey="${TS_AUTHKEY}"
	--hostname="claude-cloud-$(hostname -s 2>/dev/null || echo sandbox)"
	--accept-routes=true
	--timeout=30s
)
if [ -n "${TS_LOGIN_SERVER:-}" ]; then
	up_args+=(--login-server="${TS_LOGIN_SERVER}")
elif [[ "${TS_AUTHKEY}" != tskey-* ]]; then
	up_args+=(--login-server="https://headscale.ipv1337.dev")
fi
if ! "${priv[@]}" tailscale up "${up_args[@]}"; then
	echo "tailscale-up: 'tailscale up' failed — see /tmp/tailscaled.log" >&2
	exit 0
fi

echo "tailscale-up: connected as $("${priv[@]}" tailscale ip -4 2>/dev/null | head -n1)"
echo "tailscale-up: reach peers via  curl --proxy socks5h://localhost:1055 http://<peer>/"
exit 0
"##;

const NAME: &str = "configure-tailscale";

enum Mode {
    Write,
    Check,
}

fn usage_error(msg: &str) -> i32 {
    eprintln!("{NAME}: {msg}");
    2
}

/// Runs the tool; returns the process exit code.
pub fn run(args: &[String]) -> i32 {
    let mut mode = Mode::Write;
    let mut target: Option<PathBuf> = None;
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--check" => mode = Mode::Check,
            "--file" => match it.next() {
                Some(p) => target = Some(PathBuf::from(p)),
                // The script died on `$2: unbound variable` (exit 1) here.
                None => {
                    eprintln!("{NAME}: --file needs a path");
                    return 1;
                }
            },
            other => return usage_error(&format!("unknown argument: {other}")),
        }
    }

    let target = match target {
        Some(t) => t,
        None => match workspace_root() {
            Ok(root) => root.join(".claude/tailscale-up.sh"),
            Err(code) => return code,
        },
    };

    if !target.is_file() {
        eprintln!("{NAME}: target file not found: {}", target.display());
        return 1;
    }

    match mode {
        Mode::Check => check(&target),
        Mode::Write => write(&target),
    }
}

/// `$BUILD_WORKSPACE_DIRECTORY` (set by `bazel run`), else the git toplevel.
fn workspace_root() -> Result<PathBuf, i32> {
    if let Some(d) = std::env::var_os("BUILD_WORKSPACE_DIRECTORY").filter(|d| !d.is_empty()) {
        return Ok(PathBuf::from(d));
    }
    match Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        Ok(o) if o.status.success() => {
            let s = String::from_utf8_lossy(&o.stdout);
            Ok(PathBuf::from(s.trim_end_matches('\n')))
        }
        Ok(o) => {
            let _ = std::io::stderr().write_all(&o.stderr);
            Err(o.status.code().unwrap_or(1))
        }
        Err(e) => {
            eprintln!("{NAME}: git: {e}");
            Err(127)
        }
    }
}

fn check(target: &Path) -> i32 {
    let current = match std::fs::read(target) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("{NAME}: read {}: {e}", target.display());
            return 1;
        }
    };
    if current != HOOK.as_bytes() {
        show_diff(target);
        eprintln!(
            "{NAME}: {} is out of sync; run 'bazel run //tools/cloud-bootstrap:configure-tailscale'",
            target.display()
        );
        return 1;
    }
    println!("{NAME}: {} is up to date", target.display());
    0
}

/// Print `diff -u <target> <expected>` to stdout, as the script did. Best
/// effort: the verdict is the byte comparison above, not diff's exit code.
///
/// The expected text goes to diff on its stdin (`-`), never through a file
/// in the shared temp directory: a file there at a guessable name, written
/// with a plain create-or-truncate, lets another local user plant a symlink
/// at that name and have this overwrite whatever it points at.
fn show_diff(target: &Path) {
    let child = Command::new("diff")
        .arg("-u")
        .arg(target)
        .arg("-")
        .stdin(std::process::Stdio::piped())
        .spawn();
    let Ok(mut child) = child else { return };
    if let Some(mut stdin) = child.stdin.take() {
        // The hook is a few KiB, well under a pipe's buffer, so this cannot
        // block on diff's output; dropping stdin then closes it.
        let _ = stdin.write_all(HOOK.as_bytes());
    }
    let _ = child.wait();
}

fn write(target: &Path) -> i32 {
    if let Err(e) = std::fs::write(target, HOOK) {
        eprintln!("{NAME}: write {}: {e}", target.display());
        return 1;
    }
    if let Err(e) = make_executable(target) {
        eprintln!("{NAME}: chmod +x {}: {e}", target.display());
        return 1;
    }
    println!("{NAME}: updated {}", target.display());
    0
}

fn make_executable(target: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mut perm = std::fs::metadata(target)?.permissions();
    perm.set_mode(perm.mode() | 0o111);
    std::fs::set_permissions(target, perm)
}
