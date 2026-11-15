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

//! headscale_ops.sh: the headscale CLI inside its pod, behind one target
//! per operation. Each runs `kubectl exec -c headscale POD -- headscale ...`
//! and exits with its status.

use shell_compat as sc;

use super::common::*;

const SUBCMDS: &str = "raw|apikey-create|apikey-list|apikey-expire|user-create|user-list|user-destroy|node-list|node-register|node-delete|preauthkey-create|preauthkey-list|policy-check|policy-set";

pub fn main(args: &[Vec<u8>]) -> i32 {
    match run_ops(args) {
        Ok(c) | Err(c) => c,
    }
}

fn run_ops(args: &[Vec<u8>]) -> Res<i32> {
    let sub = param(
        args,
        1,
        41,
        &format!("usage: headscale-SUBCMD ({})", SUBCMDS),
    )?;
    let a: Vec<&[u8]> = args[1..].iter().map(|x| x.as_slice()).collect();
    default_kubeconfig(44)?;
    let k = kctx();
    if !have("kubectl") {
        return die(1, b"ERROR: kubectl not found on PATH.");
    }
    let (_, pod) = capture_quiet(
        0,
        kubectl(
            &k,
            &[
                b"-n",
                b"headscale",
                b"get",
                b"pods",
                b"-l",
                b"app.kubernetes.io/name=headscale",
                b"-o",
                b"jsonpath={.items[0].metadata.name}",
            ],
        ),
    );
    if pod.is_empty() {
        return die(
            1,
            b"ERROR: no running headscale pod found in namespace 'headscale' (kubectl get pods -n headscale -l app.kubernetes.io/name=headscale). Is the headscale Application synced?",
        );
    }
    let kexec = |words: &[&[u8]], rest: &[&[u8]]| -> i32 {
        let mut c = kubectl(
            &k,
            &[
                b"-n",
                b"headscale",
                b"exec",
                b"-c",
                b"headscale",
                &pod,
                b"--",
                b"headscale",
            ],
        );
        for w in words.iter().chain(rest.iter()) {
            c.arg(sc::os(w));
        }
        run(0, &mut c, false)
    };
    let st = match sub.as_slice() {
        b"raw" => kexec(&[], &a),
        b"apikey-create" => kexec(&[b"apikeys", b"create"], &a),
        b"apikey-list" => kexec(&[b"apikeys", b"list"], &a),
        b"apikey-expire" => kexec(&[b"apikeys", b"expire"], &a),
        b"user-create" => {
            let user = param(&args[1..], 1, 75, "usage: headscale-user-create USERNAME")?;
            assign_exported("USER", &user);
            kexec(&[b"users", b"create", &user], &[])
        }
        b"user-list" => kexec(&[b"users", b"list"], &a),
        b"user-destroy" => {
            // "$@" still holds USERNAME (the script never shifts it off), so
            // headscale gets it twice: `users destroy NAME NAME ...`.
            let user = param(&args[1..], 1, 82, "usage: headscale-user-destroy USERNAME")?;
            assign_exported("USER", &user);
            kexec(&[b"users", b"destroy", &user], &a)
        }
        b"node-list" => kexec(&[b"nodes", b"list"], &a),
        b"node-register" => kexec(&[b"nodes", b"register"], &a),
        b"node-delete" => {
            let node = param(&args[1..], 1, 92, "usage: headscale-node-delete NODE_ID")?;
            kexec(&[b"nodes", b"delete", b"--identifier", &node], &[])
        }
        b"preauthkey-create" => kexec(&[b"preauthkeys", b"create"], &a),
        b"preauthkey-list" => kexec(&[b"preauthkeys", b"list"], &a),
        b"policy-check" => {
            let policy = read_policy(&a)?;
            policy_exec(&k, &pod, b"check", &policy)?
        }
        b"policy-set" => {
            // Read once, so the bytes `set` sends are the bytes `check` passed
            // even if the file changes in between.
            let policy = read_policy(&a)?;
            let st = policy_exec(&k, &pod, b"check", &policy)?;
            if st != 0 {
                return die(
                    st,
                    b"ERROR: policy check did not pass (see the output above); the live policy was not changed.",
                );
            }
            policy_exec(&k, &pod, b"set", &policy)?
        }
        _ => return die(2, &sc::cat(&[b"ERROR: unknown subcmd '", &sub, b"'"])),
    };
    Ok(st)
}

/// The policy file in git that `policy-check`/`policy-set` send by default.
const POLICY_FILE: &str = "gitops/argocd/platform/headscale/policy.hujson";

/// The policy file's contents: $1 (relative to the workspace) or
/// [`POLICY_FILE`]. An unreadable file is its own error, never reported as a
/// failed policy check.
fn read_policy(rest: &[&[u8]]) -> Res<Vec<u8>> {
    cd_workspace(120)?;
    let path: Vec<u8> = rest
        .first()
        .map(|p| p.to_vec())
        .unwrap_or_else(|| POLICY_FILE.as_bytes().to_vec());
    match std::fs::read(sc::path(&path)) {
        Ok(b) => Ok(b),
        Err(e) => die(
            1,
            &sc::cat(&[
                b"ERROR: cannot read ",
                &path,
                b": ",
                sc::strerror(&e).as_bytes(),
            ]),
        ),
    }
}

/// `headscale policy {check,set} -f /dev/stdin` with `policy` written to the
/// command's stdin over `kubectl exec -i`, so nothing has to be copied into
/// the pod.
fn policy_exec(k: &[u8], pod: &[u8], verb: &[u8], policy: &[u8]) -> Res<i32> {
    use std::io::Write;
    use std::process::Stdio;
    let mut c = kubectl(
        k,
        &[
            b"-n",
            b"headscale",
            b"exec",
            b"-i",
            b"-c",
            b"headscale",
            pod,
            b"--",
            b"headscale",
            b"policy",
            verb,
            b"-f",
            b"/dev/stdin",
        ],
    );
    c.stdin(Stdio::piped());
    let mut child = match c.spawn() {
        Ok(ch) => ch,
        Err(e) => {
            return die(
                1,
                &sc::cat(&[b"ERROR: kubectl: ", sc::strerror(&e).as_bytes()]),
            )
        }
    };
    {
        let mut sin = child.stdin.take().expect("piped stdin");
        if let Err(e) = sin.write_all(policy) {
            // kubectl may have exited before reading (bad context, no pod);
            // its own status and message say why, so report that first.
            drop(sin);
            if let Ok(st) = child.wait() {
                let code = sc::status_code(st);
                if code != 0 {
                    return Ok(code);
                }
            }
            return die(
                1,
                &sc::cat(&[
                    b"ERROR: writing the policy to kubectl: ",
                    sc::strerror(&e).as_bytes(),
                ]),
            );
        }
        // Dropping stdin closes it, so headscale sees EOF.
    }
    match child.wait() {
        Ok(st) => Ok(sc::status_code(st)),
        Err(e) => die(
            1,
            &sc::cat(&[b"ERROR: kubectl: ", sc::strerror(&e).as_bytes()]),
        ),
    }
}
