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

//! llvm_cache_key — derive the Actions cache key for the extracted LLVM
//! toolchain (the llvm-cache-restore composite). Prints the key to stdout.
//!
//! WHY /etc/os-release is part of the key. toolchains_llvm picks its LLVM
//! distribution in `_linux_dist()`, which does:
//!
//! ```text
//! for line in rctx.read("/etc/os-release").splitlines():
//! ```
//!
//! An `rctx.read()` of a path outside the repo is a RECORDED INPUT of the
//! `llvm_toolchain_llvm` repo rule. Bazel 9 re-reads every recorded input on
//! each build and REJECTS the cached repo contents when a digest moved -- so
//! the key has to move with that file or the cache goes to dead weight:
//!
//!   1. GitHub rolls a runner-image point release (24.04.4 -> 24.04.5, image
//!      20260831.293 -> 20260907.300). /etc/os-release changes.
//!   2. The key was keyed only on MODULE.bazel, so it still HITS. ~2.2GB of
//!      the old image's extraction is downloaded and unpacked (~28-38s).
//!   3. Bazel's recorded-inputs check rejects all of it and re-extracts LLVM
//!      anyway (98-264s, per the llvm-cache-restore header).
//!   4. actions/cache does not save on an exact primary-key hit ("Cache hit
//!      occurred on the primary key ..., not saving cache"), so the freshly
//!      extracted contents are NEVER persisted -- step 2-3 repeats on every
//!      run, on every lane, until MODULE.bazel happens to change.
//!
//! That is not a slow rot: it turns red the moment the new image reaches a
//! runner, because the llvm-cache-tripwire composite (correctly) fails a job
//! that restored a hit and re-extracted anyway. Observed 2026-09-08 on #2242.
//!
//! Keying on the file's digest makes the image roll a one-run cache MISS -- the
//! tripwire's benign "expected once" branch -- and the post step then saves an
//! entry that actually validates. Hash the WHOLE file, not a parsed field:
//! Bazel digests the whole file, so anything narrower would call two files
//! identical that Bazel calls different, which is the bug all over again.
//!
//! Deliberately NO restore-keys: a prefix match would restore an entry built
//! under a different /etc/os-release, which is exactly the rejected-contents
//! state this exists to avoid. A miss is correct and self-healing.
//!
//! Usage: llvm_cache_key <runner-os> <module-bazel-hash> [os-release-path]

use shell_compat::{capture, cat, err, out, which};

pub fn llvm_cache_key(runner_os: &[u8], module_hash: &[u8], os_release_path: &[u8]) -> i32 {
    let osrel;
    if shell_compat::is_readable(os_release_path) {
        let digest_raw;
        if which(b"sha256sum").is_some() {
            let r = capture(
                80,
                std::process::Command::new("sha256sum").arg(shell_compat::os(os_release_path)),
            );
            if r.ok() {
                digest_raw = shell_compat::subst(r.stdout);
            } else {
                digest_raw = Vec::new();
            }
        } else if which(b"shasum").is_some() {
            let r = capture(
                82,
                std::process::Command::new("shasum")
                    .arg("-a")
                    .arg("256")
                    .arg(shell_compat::os(os_release_path)),
            );
            if r.ok() {
                digest_raw = shell_compat::subst(r.stdout);
            } else {
                digest_raw = Vec::new();
            }
        } else {
            digest_raw = Vec::new();
        }
        if digest_raw.is_empty() {
            err(&cat(&[
                b"::error::llvm-cache-key: no sha256 tool (sha256sum/shasum) could digest ",
                os_release_path,
                b"; refusing to emit a key that would silently ignore it\n",
            ]));
            return 1;
        }
        osrel = digest_raw.get(..16).unwrap_or(&digest_raw).to_vec();
    } else {
        osrel = b"noosrelease".to_vec();
    }
    out(&cat(&[
        b"llvm-contents-v2-",
        runner_os,
        b"-",
        &osrel,
        b"-",
        module_hash,
    ]));
    0
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    if args.is_empty() {
        err(b"runner os required\n");
        return 2;
    }
    if args.len() < 2 {
        err(b"MODULE.bazel hash required\n");
        return 2;
    }
    let runner_os = &args[0];
    let module_hash = &args[1];
    let os_release_path = if args.len() > 2 {
        args[2].clone()
    } else {
        b"/etc/os-release".to_vec()
    };
    llvm_cache_key(runner_os, module_hash, &os_release_path)
}
