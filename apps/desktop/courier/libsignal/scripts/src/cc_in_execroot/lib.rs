// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Rust port of `apps/desktop/courier/libsignal/cc_in_execroot.sh`.
//!
//! Runs the toolchain's `$CC` from `$COURIER_BAZEL_EXECROOT` so execroot-relative
//! compiler flags resolve while `cc-rs` passes absolute paths for everything else.

use std::env;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CcInvocation {
    pub execroot: PathBuf,
    pub cc: String,
    pub args: Vec<String>,
}

pub fn resolve_invocation(
    execroot: Option<&str>,
    cc: Option<&str>,
    argv: &[String],
) -> Result<CcInvocation, String> {
    let execroot_str = execroot
        .filter(|s| !s.is_empty())
        .ok_or_else(|| "COURIER_BAZEL_EXECROOT: parameter not set or empty".to_string())?;
    let cc_str = cc
        .filter(|s| !s.is_empty())
        .ok_or_else(|| "CC: parameter not set or empty".to_string())?;
    let forwarded = if argv.len() > 1 {
        argv[1..].to_vec()
    } else {
        Vec::new()
    };
    Ok(CcInvocation {
        execroot: PathBuf::from(execroot_str),
        cc: cc_str.to_string(),
        args: forwarded,
    })
}

pub fn run(argv: &[String]) -> i32 {
    let execroot = env::var("COURIER_BAZEL_EXECROOT").ok();
    let cc = env::var("CC").ok();
    let inv = match resolve_invocation(execroot.as_deref(), cc.as_deref(), argv) {
        Ok(i) => i,
        Err(msg) => {
            eprintln!("{msg}");
            return 1;
        }
    };
    if let Err(err) = env::set_current_dir(&inv.execroot) {
        eprintln!("cd {}: {err}", inv.execroot.display());
        return 1;
    }
    let err = Command::new(&inv.cc).args(&inv.args).exec();
    eprintln!("exec {}: {err}", inv.cc);
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn resolve_invocation_validates_required_vars() {
        let args = vec![
            "cc_in_execroot".to_string(),
            "-c".to_string(),
            "foo.c".to_string(),
        ];
        assert!(resolve_invocation(None, Some("/usr/bin/clang"), &args).is_err());
        assert!(resolve_invocation(Some(""), Some("/usr/bin/clang"), &args).is_err());
        assert!(resolve_invocation(Some("/tmp/execroot"), None, &args).is_err());
        assert!(resolve_invocation(Some("/tmp/execroot"), Some(""), &args).is_err());

        let inv = resolve_invocation(Some("/tmp/execroot"), Some("/usr/bin/clang"), &args).unwrap();
        assert_eq!(inv.execroot, PathBuf::from("/tmp/execroot"));
        assert_eq!(inv.cc, "/usr/bin/clang");
        assert_eq!(inv.args, vec!["-c".to_string(), "foo.c".to_string()]);
    }

    #[test]
    fn subprocess_execution_changes_into_execroot_and_forwards_args() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let scratch = env::temp_dir().join(format!("cc-in-execroot-test-{nanos}"));
        let execroot = scratch.join("execroot");
        fs::create_dir_all(&execroot).unwrap();

        let fake_cc = scratch.join("fake-cc.sh");
        fs::write(&fake_cc, "#!/bin/sh\npwd\nprintf '%s\\n' \"$@\"\n").unwrap();
        fs::set_permissions(&fake_cc, fs::Permissions::from_mode(0o755)).unwrap();

        let inv = resolve_invocation(
            Some(&execroot.to_string_lossy()),
            Some(&fake_cc.to_string_lossy()),
            &[
                "cc_in_execroot".to_string(),
                "-O2".to_string(),
                "-Iinclude".to_string(),
            ],
        )
        .unwrap();

        let out = Command::new(&inv.cc)
            .current_dir(&inv.execroot)
            .args(&inv.args)
            .output()
            .unwrap();
        assert!(out.status.success());
        let stdout = String::from_utf8_lossy(&out.stdout);
        let lines: Vec<&str> = stdout.lines().collect();
        let expected_dir = fs::canonicalize(&execroot).unwrap();
        let actual_dir = fs::canonicalize(lines[0]).unwrap();
        assert_eq!(actual_dir, expected_dir);
        assert_eq!(&lines[1..], &["-O2", "-Iinclude"]);

        let _ = fs::remove_dir_all(&scratch);
    }
}
