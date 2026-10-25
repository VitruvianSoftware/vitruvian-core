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

//! One binary, three commands, chosen by the name it is run as
//! (`inventory`, `check`, `setup` or `setup_publishers`, as a symlink would
//! be) or else by its first argument:
//!
//!     registry-trust-rs inventory [--json] [--all]
//!     registry-trust-rs check
//!     registry-trust-rs setup [--dry-run] [--only npm|pypi|crates]

use std::io::Write;

use crate::http::{self, Recorded};
use crate::json::Value;
use crate::{check, inventory, py, setup_publishers};

pub const USAGE: &str =
    "usage: registry-trust-rs inventory [--json] [--all] | check | setup [--dry-run] [--only npm|pypi|crates]";

fn command_of(name: &str) -> Option<&'static str> {
    match name {
        "inventory" => Some("inventory"),
        "check" => Some("check"),
        "setup" | "setup_publishers" => Some("setup"),
        _ => None,
    }
}

/// Runs one command with the process's environment and streams.
pub fn run(
    argv0: &str,
    args: &[String],
    env: &[(String, String)],
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    let invoked = py::basename(argv0);
    let invoked = invoked.strip_suffix(".py").unwrap_or(invoked);
    let (command, args) = match command_of(invoked) {
        Some(command) => (command, args),
        None => match args.first().and_then(|a| command_of(a)) {
            Some(command) => (command, &args[1..]),
            None => {
                let _ = writeln!(err, "registry-trust: {USAGE}");
                return 2;
            }
        },
    };
    let get = |key: &str| {
        env.iter()
            .rev()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
            .filter(|v| !v.is_empty())
    };
    let recorded = match get("REGISTRY_TRUST_RECORDED") {
        None => None,
        Some(_) if get("TEST_TMPDIR").is_none() => {
            let _ = writeln!(
                err,
                "registry-trust: REGISTRY_TRUST_RECORDED is honoured only under bazel test; a recording never stands in for a registry"
            );
            return 2;
        }
        Some(path) => match Recorded::load(path) {
            Ok(recorded) => Some(recorded),
            Err(error) => {
                let _ = writeln!(err, "registry-trust: {error}");
                return 2;
            }
        },
    };
    let root = inventory::root_folder(env);
    let mut fetch = |url: &str| match &recorded {
        Some(r) => r.fetch(url),
        None => http::http_fetch(url),
    };
    match command {
        "inventory" => inventory::main(args, &root, out, err),
        "check" => check::main(args, &root, &mut fetch, out, err),
        _ => {
            let mut send = |m: &str, u: &str, t: &str, b: Option<&Value>| match &recorded {
                Some(r) => Ok(r.send(m, u, t, b)),
                None => setup_publishers::crates_send(m, u, t, b),
            };
            let env: setup_publishers::Env = env.to_vec();
            setup_publishers::main(
                args,
                &root,
                &env,
                &mut fetch,
                &mut send,
                &mut setup_publishers::run_npm_setup,
                out,
                err,
            )
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_with(argv0: &str, args: &[&str], env: &[(&str, &str)]) -> (i32, String, String) {
        let args: Vec<String> = args.iter().map(|a| a.to_string()).collect();
        let env: Vec<(String, String)> = env
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        let (mut out, mut err) = (Vec::new(), Vec::new());
        let code = run(argv0, &args, &env, &mut out, &mut err);
        (
            code,
            String::from_utf8(out).unwrap(),
            String::from_utf8(err).unwrap(),
        )
    }

    #[test]
    fn no_command_is_a_usage_error() {
        let (code, _, err) = run_with("/x/registry-trust-rs", &[], &[]);
        assert_eq!(code, 2);
        assert!(err.contains("usage:"));
        assert_eq!(run_with("registry-trust-rs", &["publish"], &[]).0, 2);
    }

    #[test]
    fn the_name_it_is_run_as_chooses_the_command() {
        // `check` with an argument refuses it before reading anything.
        let (code, _, err) = run_with("/bin/check", &["--fix"], &[]);
        assert_eq!(
            (code, err.as_str()),
            (2, "registry-trust: unknown argument: --fix\n")
        );
        let (code, _, err) = run_with("registry-trust-rs", &["check", "--fix"], &[]);
        assert_eq!(
            (code, err.as_str()),
            (2, "registry-trust: unknown argument: --fix\n")
        );
        let (code, _, err) = run_with("setup_publishers.py", &["--force"], &[]);
        assert_eq!(code, 2);
        assert!(err.contains("unknown flag: --force"));
    }

    #[test]
    fn a_recording_is_refused_outside_a_test() {
        let (code, _, err) = run_with(
            "registry-trust-rs",
            &["check"],
            &[("REGISTRY_TRUST_RECORDED", "/x.json")],
        );
        assert_eq!(code, 2);
        assert!(err.contains("only under bazel test"));
    }
}
