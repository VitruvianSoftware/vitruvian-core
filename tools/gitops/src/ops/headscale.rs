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

const SUBCMDS: &str = "raw|apikey-create|apikey-list|apikey-expire|user-create|user-list|user-destroy|node-list|node-register|node-delete|preauthkey-create|preauthkey-list";

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
        _ => return die(2, &sc::cat(&[b"ERROR: unknown subcmd '", &sub, b"'"])),
    };
    Ok(st)
}
