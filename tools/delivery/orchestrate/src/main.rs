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

//! `bazel run //tools/delivery/orchestrate -- --out delivery-manifest.json`

use orchestrate::{flags, gostd, Config, Env, DEFAULT_MANIFEST_NAME, ENGINE_RLOCATION};
use std::io::Write;
use std::os::unix::ffi::OsStrExt;

fn main() {
    let env = Env::from_process();
    let args: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|a| orchestrate::json::go_string(a.as_bytes()))
        .collect();

    // ORCHESTRATE_BAZEL lets a caller point at a specific bazel; --bazel wins.
    let bazel_default = orchestrate::first_non_empty(&[&env.get("ORCHESTRATE_BAZEL"), "bazel"]);
    let flags = match flags::parse(&args, &bazel_default, DEFAULT_MANIFEST_NAME) {
        flags::Outcome::Run(f) => f,
        flags::Outcome::Exit(msg, code) => {
            let _ = std::io::stderr().write_all(msg.as_bytes());
            std::process::exit(code);
        }
    };

    // `bazel run` sets BUILD_WORKSPACE_DIRECTORY; its cwd is the runfiles tree.
    let mut root = env.get("BUILD_WORKSPACE_DIRECTORY");
    if root.is_empty() {
        root = match gostd::getwd() {
            Ok(wd) => wd,
            Err(e) => {
                eprintln!("orchestrate: cannot determine the workspace root: {}", e);
                std::process::exit(1);
            }
        };
    }
    let manifest_path = if flags.out.starts_with('/') {
        flags.out.clone()
    } else {
        gostd::join(&[&root, &flags.out])
    };

    // The decision engine: DEPLOY_AFFECTED_BIN when set, else the
    // deploy_affected binary in our runfiles.
    let script = match env.get("DEPLOY_AFFECTED_BIN") {
        s if !s.is_empty() => s,
        _ => match runfiles::Runfiles::create()
            .ok()
            .and_then(|r| runfiles::rlocation!(r, ENGINE_RLOCATION))
        {
            Some(p) => p.to_string_lossy().into_owned(),
            None => {
                eprintln!(
                    "orchestrate: cannot find the deploy-affected engine ({}) in the runfiles; run it as: bazel run //tools/delivery/orchestrate",
                    ENGINE_RLOCATION
                );
                std::process::exit(1);
            }
        },
    };

    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    let mut cfg = Config {
        script,
        repo_root: root,
        bazel: flags.bazel,
        out: manifest_path,
        env,
        stdout: &mut lock,
    };
    let code = orchestrate::orchestrate(&mut cfg);
    let _ = lock.flush();
    std::process::exit(code);
}
