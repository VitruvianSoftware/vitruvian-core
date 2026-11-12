// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Runs a built binary with arguments as a Bazel test.

use std::process::Command;

pub fn run_cli(args: &[String]) -> i32 {
    if args.is_empty() {
        eprintln!("usage: run_binary <binary> [args...]");
        return 2;
    }
    let status = match Command::new(&args[0]).args(&args[1..]).status() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("failed to execute {}: {}", args[0], e);
            return 1;
        }
    };
    if let Some(code) = status.code() {
        code
    } else {
        #[cfg(unix)]
        {
            use std::os::unix::process::ExitStatusExt;
            if let Some(sig) = status.signal() {
                return 128 + sig;
            }
        }
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_run_binary_exit_codes() {
        assert_eq!(run_cli(&[]), 2);
        assert_eq!(
            run_cli(&[
                "/bin/sh".to_string(),
                "-c".to_string(),
                "exit 0".to_string()
            ]),
            0
        );
        assert_eq!(
            run_cli(&[
                "/bin/sh".to_string(),
                "-c".to_string(),
                "exit 7".to_string()
            ]),
            7
        );
    }
}
