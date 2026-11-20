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

const SUBCMDS: &str = "raw|apikey-create|apikey-list|apikey-expire|user-create|user-list|user-destroy|node-list|node-register|node-delete|preauthkey-create|preauthkey-list|policy-check|policy-set|policy-sync-pause|policy-sync-resume";

const PAUSE_CONFIGMAP_NAME: &[u8] = b"headscale-policy-sync-pause";
const PAUSE_CONFIGMAP_YAML: &[u8] = b"\
apiVersion: v1
kind: ConfigMap
metadata:
  name: headscale-policy-sync-pause
  namespace: headscale
data:
  paused: \"true\"
";

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
    match sub.as_slice() {
        b"policy-sync-pause" => {
            if !a.is_empty() {
                return die(2, b"usage: headscale-policy-sync-pause");
            }
            return Ok(feed(
                0,
                kubectl(&k, &[b"-n", b"headscale", b"apply", b"-f", b"-"]),
                PAUSE_CONFIGMAP_YAML,
                None,
            ));
        }
        b"policy-sync-resume" => {
            if !a.is_empty() {
                return die(2, b"usage: headscale-policy-sync-resume");
            }
            return Ok(run(
                0,
                &mut kubectl(
                    &k,
                    &[
                        b"-n",
                        b"headscale",
                        b"delete",
                        b"configmap",
                        PAUSE_CONFIGMAP_NAME,
                        b"--ignore-not-found",
                    ],
                ),
                false,
            ));
        }
        _ => {}
    }
    let pod = headscale_pod(&k)?;
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

/// The running headscale pod's name, or the "is it synced?" error.
pub fn headscale_pod(k: &[u8]) -> Res<Vec<u8>> {
    let (_, pod) = capture_quiet(
        0,
        kubectl(
            k,
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
    Ok(pod)
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    struct EnvRestore {
        saved: Vec<(&'static str, Option<std::ffi::OsString>)>,
        dir: std::path::PathBuf,
    }

    impl EnvRestore {
        fn new(dir: std::path::PathBuf, vars: &[(&'static str, &str)]) -> Self {
            let mut saved = Vec::with_capacity(vars.len());
            for (k, v) in vars {
                saved.push((*k, std::env::var_os(k)));
                std::env::set_var(k, v);
            }
            Self { saved, dir }
        }
    }

    impl Drop for EnvRestore {
        fn drop(&mut self) {
            for (k, old) in self.saved.drain(..) {
                match old {
                    Some(v) => std::env::set_var(k, v),
                    None => std::env::remove_var(k),
                }
            }
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    #[test]
    fn subcmds_and_pause_manifest_cover_pause_and_resume() {
        assert!(SUBCMDS.split('|').any(|s| s == "policy-sync-pause"));
        assert!(SUBCMDS.split('|').any(|s| s == "policy-sync-resume"));
        let yaml = std::str::from_utf8(PAUSE_CONFIGMAP_YAML).unwrap();
        assert!(yaml.contains("kind: ConfigMap"));
        assert!(yaml.contains("name: headscale-policy-sync-pause"));
        assert!(yaml.contains("namespace: headscale"));
        assert!(yaml.contains("paused: \"true\""));
    }

    #[test]
    fn policy_sync_pause_and_resume_invoke_expected_kubectl_commands() {
        let dir =
            std::env::temp_dir().join(format!("gitops-headscale-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let bin_dir = dir.join("bin");
        std::fs::create_dir_all(&bin_dir).unwrap();
        let log_file = dir.join("kubectl.log");
        let stdin_file = dir.join("kubectl.stdin");
        let fake_kubectl = bin_dir.join("kubectl");
        std::fs::write(
            &fake_kubectl,
            format!(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{}'\ncat > '{}'\n",
                log_file.display(),
                stdin_file.display()
            ),
        )
        .unwrap();
        let mut perms = std::fs::metadata(&fake_kubectl).unwrap().permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&fake_kubectl, perms).unwrap();

        let orig_path = std::env::var("PATH").unwrap_or_default();
        let new_path = format!("{}:{orig_path}", bin_dir.display());
        let kubeconfig = dir.join("kube.yaml");
        std::fs::write(&kubeconfig, "apiVersion: v1\n").unwrap();
        let _guard = EnvRestore::new(
            dir.clone(),
            &[
                ("PATH", &new_path),
                ("KUBECONFIG", kubeconfig.to_str().unwrap()),
                ("KUBE_CONTEXT", "test-ctx"),
            ],
        );

        assert_eq!(main(&[b"policy-sync-pause".to_vec()]), 0);
        assert_eq!(std::fs::read(&stdin_file).unwrap(), PAUSE_CONFIGMAP_YAML);

        assert_eq!(main(&[b"policy-sync-resume".to_vec()]), 0);

        let calls = std::fs::read_to_string(&log_file).unwrap();
        let lines: Vec<&str> = calls.lines().collect();
        assert_eq!(
            lines,
            vec![
                "--context test-ctx -n headscale apply -f -",
                "--context test-ctx -n headscale delete configmap headscale-policy-sync-pause --ignore-not-found",
            ]
        );

        assert_eq!(
            main(&[b"policy-sync-pause".to_vec(), b"--unexpected".to_vec()]),
            2
        );
        assert_eq!(
            main(&[b"policy-sync-resume".to_vec(), b"--unexpected".to_vec()]),
            2
        );
    }
}
