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

//! llvm-cache-key.sh — derive the Actions cache key for the extracted LLVM
//! toolchain. Prints the key to stdout.

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
