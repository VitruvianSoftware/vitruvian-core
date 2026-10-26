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

//! gitops-cmd.sh: kubectl (and helm, kubeseal) against the dev-local
//! cluster, run from the workspace root. The subcommand is `$1`, baked in by
//! each `bazel run` target; the rest goes to the tool.

use std::os::unix::process::CommandExt;
use std::process::Command;

use shell_compat as sc;

use super::common::*;

const SUBCMDS: &str = "apply|delete|diff|get|patch|status|helm|kubeseal";

/// `exec CMD`: replace this process; bash's message and 126/127 when it
/// cannot.
fn exec(line: u32, mut c: Command) -> i32 {
    let e = c.exec();
    let what = if e.kind() == std::io::ErrorKind::NotFound {
        "not found".to_string()
    } else {
        sc::strerror(&e)
    };
    diag(
        line,
        &sc::cat(&[
            b"exec: ",
            sc::path_bytes(std::path::Path::new(c.get_program())).as_slice(),
            b": ",
            what.as_bytes(),
        ]),
    );
    sc::spawn_failure_status(&e)
}

pub fn main(args: &[Vec<u8>]) -> i32 {
    match run_main(args) {
        Ok(c) | Err(c) => c,
    }
}

fn run_main(args: &[Vec<u8>]) -> Res<i32> {
    let sub = param(
        args,
        1,
        28,
        &format!("gitops subcommand required ({})", SUBCMDS),
    )?;
    let rest: Vec<&[u8]> = args.iter().skip(1).map(|a| a.as_slice()).collect();
    default_kubeconfig(31)?;
    let k = kctx();
    if !have("kubectl") {
        return die(1, b"ERROR: kubectl not found on PATH.");
    }
    cd_workspace(40)?;
    let plain = |verb: &[u8]| {
        let mut c = kubectl(&k, &[verb]);
        for a in &rest {
            c.arg(sc::os(a));
        }
        c
    };
    Ok(match sub.as_slice() {
        b"apply" | b"delete" | b"diff" | b"get" | b"patch" => exec(43, plain(&sub)),
        b"status" => {
            say(b"=== ArgoCD projects / appsets / applications (sync \xc2\xb7 health) ===");
            let mut c = kubectl(
                &k,
                &[
                    b"get",
                    b"appprojects,applicationsets,applications",
                    b"-n",
                    b"argocd",
                    b"-o",
                    b"wide",
                ],
            );
            for a in &rest {
                c.arg(sc::os(a));
            }
            exec(52, c)
        }
        b"helm" => {
            if !have("helm") {
                return die(1, b"ERROR: helm not found on PATH.");
            }
            let mut c = cmd("helm", &[b"--kube-context", &k]);
            for a in &rest {
                c.arg(sc::os(a));
            }
            exec(58, c)
        }
        b"kubeseal" => {
            if !have("kubeseal") {
                return die(1, b"ERROR: kubeseal not found on PATH.");
            }
            exec(66, kubeseal(&k, &rest))
        }
        _ => {
            return die(
                2,
                &sc::cat(&[
                    b"ERROR: unknown gitops subcommand '",
                    &sub,
                    format!("' ({})", SUBCMDS).as_bytes(),
                ]),
            )
        }
    })
}
