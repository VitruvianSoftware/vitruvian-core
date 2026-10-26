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

//! sealed_secrets_keys.sh and argocd-secret.sh: back up, restore and verify
//! a cluster secret as a Bitwarden attachment. bw's JSON (and the key list
//! kubectl prints) is read with serde_json where the scripts piped it
//! through jq, so neither port needs jq. argocd-secret still runs python3
//! for the one YAML edit (stripping server-managed metadata with PyYAML),
//! with the script's own program.

use std::process::Stdio;

use shell_compat as sc;

use super::common::*;
use super::jq::{self, J};

/// `bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo unknown`.
fn bw_status() -> Vec<u8> {
    let (st, out) = output(0, cmd("bw", &[b"status"]), true);
    let (mut text, ok) = jq::field_r(&out, "status");
    if st != 0 || !ok {
        text.extend_from_slice(b"unknown\n");
    }
    sc::subst(text)
}

/// The unlock both scripts fold in: an unlocked session as it is, else
/// $BW_PASSWORD, else a prompt on a terminal. `check_empty`: whether an empty
/// session is refused (sealed_secrets_keys.sh does; argocd-secret.sh asks
/// `bw status` twice and does not).
fn ensure_session(twice: bool, check_empty: bool, l: (u32, u32)) -> Res<()> {
    let st = bw_status();
    if st == b"unlocked" {
        return Ok(());
    }
    let st = if twice { bw_status() } else { st };
    if st == b"unauthenticated" {
        return die(
            1,
            "ERROR: not logged in to Bitwarden \u{2014} run 'bw login' once, then re-run."
                .as_bytes(),
        );
    }
    let session = if sc::env_set_nonempty("BW_PASSWORD") {
        let (s, v) = capture(
            l.0,
            cmd(
                "bw",
                &[b"unlock", b"--passwordenv", b"BW_PASSWORD", b"--raw"],
            ),
        );
        if s != 0 {
            return die(1, b"ERROR: 'bw unlock' failed (BW_PASSWORD).");
        }
        v
    } else if sc::stdin_is_tty() {
        warn("Unlocking Bitwarden \u{2014} enter your master password:".as_bytes());
        let (s, v) = capture(l.1, cmd("bw", &[b"unlock", b"--raw"]));
        if s != 0 {
            return die(1, b"ERROR: 'bw unlock' failed.");
        }
        v
    } else {
        warn(b"ERROR: Bitwarden is locked and there's no TTY to prompt. Either:");
        warn(b"    export BW_SESSION=$(bw unlock --raw)   # then re-run, or");
        warn(b"    export BW_PASSWORD=...                  # for non-interactive unlock");
        return Err(1);
    };
    if check_empty && session.is_empty() {
        return die(1, b"ERROR: 'bw unlock' returned an empty session.");
    }
    std::env::set_var("BW_SESSION", sc::os(&session));
    Ok(())
}

/// `bw sync >/dev/null 2>&1 || true`.
fn bw_sync() {
    run_quiet(0, cmd("bw", &[b"sync"]));
}

/// `bw get item "$ITEM" 2>/dev/null | jq -r '.id // empty' 2>/dev/null`: the
/// id and the pipeline's status.
fn item_id(item: &[u8]) -> (i32, Vec<u8>) {
    let (st, out) = output(0, cmd("bw", &[b"get", b"item", item]), true);
    let (id, ok) = jq::field_or_empty_r(&out, "id");
    let status = if !ok { 5 } else { st };
    (status, sc::subst(id))
}

/// `jq -n --arg n "$ITEM" '{type:2,secureNote:{type:0},name:$n,notes:"..."}'`.
fn new_item_json(item: &[u8], notes: &str) -> String {
    format!(
        "{{\n  \"type\": 2,\n  \"secureNote\": {{\n    \"type\": 0\n  }},\n  \"name\": {},\n  \"notes\": {}\n}}\n",
        jq::string_literal(&String::from_utf8_lossy(item)),
        jq::string_literal(notes)
    )
}

/// `... | bw encode | bw create item | jq -r FILTER`: the id printed (or
/// None when the pipeline fails).
fn create_item(item: &[u8], notes: &str, or_empty: bool) -> (i32, Vec<u8>) {
    let json = new_item_json(item, notes);
    let mut encode = cmd("bw", &[b"encode"]);
    encode.stdin(Stdio::piped()).stdout(Stdio::piped());
    // bw encode | bw create item, then the jq filter over what create printed.
    let (st1, encoded) = {
        let mut ch = match encode.spawn() {
            Ok(c) => c,
            Err(e) => {
                sc::err(&sc::spawn_diag(0, &encode, &e));
                return (sc::spawn_failure_status(&e), Vec::new());
            }
        };
        if let Some(mut sin) = ch.stdin.take() {
            use std::io::Write;
            let _ = sin.write_all(json.as_bytes());
        }
        match ch.wait_with_output() {
            Ok(o) => (sc::status_code(o.status), o.stdout),
            Err(_) => (1, Vec::new()),
        }
    };
    let mut create = cmd("bw", &[b"create", b"item"]);
    create.stdin(Stdio::piped()).stdout(Stdio::piped());
    let (st2, created) = match create.spawn() {
        Ok(mut ch) => {
            if let Some(mut sin) = ch.stdin.take() {
                use std::io::Write;
                let _ = sin.write_all(&encoded);
            }
            match ch.wait_with_output() {
                Ok(o) => (sc::status_code(o.status), o.stdout),
                Err(_) => (1, Vec::new()),
            }
        }
        Err(e) => {
            sc::err(&sc::spawn_diag(0, &create, &e));
            (sc::spawn_failure_status(&e), Vec::new())
        }
    };
    let (id, ok) = if or_empty {
        jq::field_or_empty_r(&created, "id")
    } else {
        jq::field_r(&created, "id")
    };
    let mut status = 0;
    for s in [st1, st2, if ok { 0 } else { 5 }] {
        if s != 0 {
            status = s;
        }
    }
    (status, sc::subst(id))
}

/// `for att in $(bw get item "$id" [2>/dev/null] | jq -r --arg f FILE
/// '...'); do bw delete attachment "$att" --itemid "$id" >/dev/null 2>&1 ||
/// true; done`.
fn delete_old_attachments(id: &[u8], file: &str, quiet: bool) {
    let (_, out) = output(0, cmd("bw", &[b"get", b"item", id]), quiet);
    let (ids, ok) = jq::attachment_ids(&out, file);
    if !ok && !quiet {
        sc::err(b"jq: error: cannot select the attachments of this item\n");
    }
    for att in sc::ifs_split(&ids) {
        run_quiet(
            0,
            cmd("bw", &[b"delete", b"attachment", &att, b"--itemid", id]),
        );
    }
}

/// `bw get attachment FILE --itemid ID --output F >/dev/null [2>&1]`.
fn get_attachment(file: &str, id: &[u8], dest: &[u8], quiet: bool) -> i32 {
    let mut c = cmd(
        "bw",
        &[
            b"get",
            b"attachment",
            file.as_bytes(),
            b"--itemid",
            id,
            b"--output",
            dest,
        ],
    );
    c.stdout(Stdio::null());
    if quiet {
        c.stderr(Stdio::null());
    }
    run(0, &mut c, quiet)
}

/// Removes the private temp dir (holding the plaintext key) however the run
/// ends: the script's `trap 'rm -rf "$tmpd"' EXIT ...`.
struct TempDir(Vec<u8>);

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(sc::path(&self.0));
    }
}

fn finish(r: Res<i32>) -> i32 {
    let c = match r {
        Ok(c) | Err(c) => c,
    };
    match sc::caught_signal() {
        Some(s) => 128 + s,
        None => c,
    }
}

// ---------------------------------------------------------------------------
// sealed_secrets_keys.sh
// ---------------------------------------------------------------------------

pub fn sealed_secrets_keys(args: &[Vec<u8>]) -> i32 {
    finish(sealed_run(args))
}

/// `key_count F`: `jq '[.items[]? | select(.kind == "Secret")] | length' F
/// 2>/dev/null || echo 0`.
fn key_count(f: &[u8]) -> Vec<u8> {
    match std::fs::read(sc::path(f)) {
        Ok(data) => match jq::count_secrets(&data) {
            Some(ns) => sc::subst(
                ns.iter()
                    .fold(String::new(), |mut s, n| {
                        s.push_str(&n.to_string());
                        s.push('\n');
                        s
                    })
                    .into_bytes(),
            ),
            None => b"0".to_vec(),
        },
        Err(_) => b"0".to_vec(),
    }
}

/// The jq that strips server-managed metadata from the captured key list.
fn strip_key_list(input: &[u8]) -> Result<String, (i32, String)> {
    let vals = jq::parse_stream(input).map_err(|_| {
        (
            2,
            "jq: error (at <stdin>:0): Cannot parse input".to_string(),
        )
    })?;
    let mut out = String::new();
    for mut v in vals {
        if let Some(md) = v.get_mut("metadata") {
            md.del("resourceVersion");
        }
        match v.get_mut("items") {
            Some(J::Arr(items)) => {
                for it in items.iter_mut() {
                    if let Some(md) = it.get_mut("metadata") {
                        for k in [
                            "resourceVersion",
                            "uid",
                            "creationTimestamp",
                            "generation",
                            "managedFields",
                        ] {
                            md.del(k);
                        }
                        if let Some(ann) = md.get_mut("annotations") {
                            ann.del("kubectl.kubernetes.io/last-applied-configuration");
                        }
                    }
                }
            }
            Some(J::Null) | None => {
                return Err((
                    5,
                    "jq: error (at <stdin>:0): Cannot iterate over null".into(),
                ))
            }
            Some(_) => {
                return Err((
                    5,
                    "jq: error (at <stdin>:0): Cannot iterate over this value".into(),
                ))
            }
        }
        out.push_str(&jq::pretty(&v));
    }
    Ok(out)
}

const SS_NOTES: &str = "Sealed-secrets controller private keys for dev-local \u{2014} the ONLY thing that decrypts the SealedSecrets in git. Restore: bazel run //tools/gitops:sealed-secrets-restore";

fn sealed_run(args: &[Vec<u8>]) -> Res<i32> {
    let sub = param(
        args,
        1,
        32,
        "usage: sealed-secrets-backup | sealed-secrets-restore | sealed-secrets-verify",
    )?;
    default_kubeconfig(35)?;
    let k = kctx();
    let ns = sc::env_or("SS_NAMESPACE", b"sealed-secrets");
    let label: &[u8] = b"sealedsecrets.bitnami.com/sealed-secrets-key";
    let controller = sc::env_or("SS_CONTROLLER", b"sealed-secrets-controller");
    let item = sc::env_or("SS_BW_ITEM", b"dev-local sealed-secrets controller keys");
    let file = "sealed-secrets-keys.json";

    // jq is no longer needed: bw's JSON is read with serde_json.
    need_tools(&["kubectl", "bw"], true)?;
    ensure_session(false, true, (59, 63))?;

    sc::umask(0o077);
    let tmpd = match mktemp_dir_named("sskeys") {
        Ok(d) => TempDir(d),
        Err(e) => {
            sc::err(format!("mktemp: {}\n", sc::strerror(&e)).as_bytes());
            return Err(1);
        }
    };
    sc::record_exit_signals();
    let f = sc::cat(&[&tmpd.0, b"/", file.as_bytes()]);
    let ns_s = String::from_utf8_lossy(&ns).into_owned();
    let item_s = String::from_utf8_lossy(&item).into_owned();

    match sub.as_slice() {
        b"backup" => {
            let (st, json) = output(
                93,
                kubectl(
                    &k,
                    &[b"-n", &ns, b"get", b"secret", b"-l", label, b"-o", b"json"],
                ),
                false,
            );
            let stripped = strip_key_list(&json);
            let text = match &stripped {
                Ok(t) => t.clone(),
                Err(_) => String::new(),
            };
            sc::write_file(&f, text.as_bytes(), 0o600).map_err(|e| {
                sc::redirect_error(99, &f, &e);
                1
            })?;
            // pipefail: jq's failure (rightmost) wins over kubectl's.
            if let Err((code, m)) = stripped {
                sc::err(format!("{}\n", m).as_bytes());
                return Err(code);
            }
            if st != 0 {
                return Err(st);
            }
            let n = key_count(&f);
            if !test_ge_1(104, &n) {
                return die(
                    1,
                    format!(
                        "ERROR: no sealed-secrets keys (label {}) found in ns '{}'.",
                        String::from_utf8_lossy(label),
                        ns_s
                    )
                    .as_bytes(),
                );
            }
            bw_sync();
            let (_, mut id) = item_id(&item);
            if id.is_empty() {
                let (_, new_id) = create_item(&item, SS_NOTES, true);
                id = new_id;
                if id.is_empty() {
                    return die(1, b"ERROR: 'bw create item' failed or returned no id.");
                }
                say(&sc::cat(&[b"Created Bitwarden item: ", &item]));
            }
            delete_old_attachments(&id, file, true);
            let mut up = cmd(
                "bw",
                &[b"create", b"attachment", b"--file", &f, b"--itemid", &id],
            );
            up.stdout(Stdio::null());
            if run(124, &mut up, false) != 0 {
                return die(
                    1,
                    b"ERROR: failed to upload the key attachment to Bitwarden.",
                );
            }
            bw_sync();
            // `bw get item "$id" | jq -e ... >/dev/null 2>&1`: bw's stderr is not silenced.
            let (st, got) = output(0, cmd("bw", &[b"get", b"item", &id]), false);
            if st != 0 || !jq::has_attachment(&got, file) {
                return die(
                    1,
                    format!("ERROR: item created but attachment '{}' did not persist \u{2014} Bitwarden file attachments require a paid plan (Premium/Families/Org).", file).as_bytes(),
                );
            }
            say(&sc::cat(&[
                "\u{2713} Backed up ".as_bytes(),
                &n,
                format!(
                    " sealed-secrets key secret(s) to Bitwarden item '{}' (attachment: {}).",
                    item_s, file
                )
                .as_bytes(),
            ]));
            Ok(0)
        }
        b"restore" => {
            bw_sync();
            let (_, id) = item_id(&item);
            if id.is_empty() {
                return die(
                    1,
                    format!(
                        "ERROR: Bitwarden item '{}' not found (nothing to restore).",
                        item_s
                    )
                    .as_bytes(),
                );
            }
            if get_attachment(file, &id, &f, true) != 0 {
                return die(
                    1,
                    format!("ERROR: Bitwarden attachment '{}' not found on item '{}' (backup incomplete?).", file, item_s).as_bytes(),
                );
            }
            let n = key_count(&f);
            if !test_ge_1(136, &n) {
                return die(
                    1,
                    format!(
                        "ERROR: Bitwarden attachment '{}' is missing or invalid.",
                        file
                    )
                    .as_bytes(),
                );
            }
            say(&sc::cat(&[
                b"Applying ",
                &n,
                format!(" sealed-secrets key(s) to ns '{}' and restarting '", ns_s).as_bytes(),
                &controller,
                b"'...",
            ]));
            for step in [
                kubectl(&k, &[b"-n", &ns, b"apply", b"-f", &f]),
                kubectl(
                    &k,
                    &[
                        b"-n",
                        &ns,
                        b"rollout",
                        b"restart",
                        b"deployment",
                        &controller,
                    ],
                ),
                kubectl(
                    &k,
                    &[
                        b"-n",
                        &ns,
                        b"rollout",
                        b"status",
                        b"deployment",
                        &controller,
                        b"--timeout=120s",
                    ],
                ),
            ] {
                let mut step = step;
                let st = run(140, &mut step, false);
                if st != 0 {
                    return Err(st);
                }
                if let Some(s) = sc::caught_signal() {
                    return Err(128 + s);
                }
            }
            say(&sc::cat(&[
                "\u{2713} Restored ".as_bytes(),
                &n,
                b" sealed-secrets key(s); controller is up. Existing SealedSecrets will decrypt with the restored key.",
            ]));
            Ok(0)
        }
        b"verify" => {
            bw_sync();
            let (_, id) = item_id(&item);
            if id.is_empty() {
                return die(
                    1,
                    format!(
                        "\u{2717} No Bitwarden item '{}' found \u{2014} nothing is backed up.",
                        item_s
                    )
                    .as_bytes(),
                );
            }
            if get_attachment(file, &id, &f, true) != 0 {
                return die(
                    1,
                    format!("\u{2717} Item '{}' exists but has NO '{}' attachment \u{2014} the key is NOT backed up (re-run backup).", item_s, file).as_bytes(),
                );
            }
            let n = key_count(&f);
            if !test_ge_1(153, &n) {
                return die(
                    1,
                    format!("\u{2717} Attachment '{}' is present but contains no Secret \u{2014} backup is invalid.", file).as_bytes(),
                );
            }
            say(&sc::cat(&[
                format!("\u{2713} Backup OK: item '{}' holds '{}' with ", item_s, file).as_bytes(),
                &n,
                b" sealed-secrets key secret(s) \xe2\x80\x94 restorable via 'bazel run //tools/gitops:sealed-secrets-restore'.",
            ]));
            Ok(0)
        }
        _ => die(
            2,
            &sc::cat(&[
                b"ERROR: unknown subcommand '",
                &sub,
                b"' (backup|restore|verify)",
            ]),
        ),
    }
}

// ---------------------------------------------------------------------------
// argocd-secret.sh
// ---------------------------------------------------------------------------

/// The script's strip_metadata, run by the same python3 (PyYAML).
const STRIP_METADATA_PY: &str = r#"import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
m = d.get("metadata", {})
for k in ("resourceVersion", "uid", "creationTimestamp", "managedFields",
          "ownerReferences", "generation", "selfLink"):
    m.pop(k, None)
ann = m.get("annotations", {})
ann.pop("kubectl.kubernetes.io/last-applied-configuration", None)
if ann == {}:
    m.pop("annotations", None)
d.pop("status", None)
yaml.safe_dump(d, open(sys.argv[1], "w"), default_flow_style=False)
"#;

const ARGOCD_NOTES: &str = "ArgoCD argocd-secret (server.secretkey + accounts.mcp.tokens) for dev-local. Restore after a cluster reinstall so the existing MCP token keeps validating: bazel run //tools/gitops:argocd-secret-restore";

pub fn argocd_secret(args: &[Vec<u8>]) -> i32 {
    finish(argocd_run(args))
}

/// `id="$(item_id)"` without the sibling script's `|| true`: a missing item
/// fails the pipeline and `set -e` ends the run there, silently.
fn argocd_item_id(item: &[u8]) -> Res<Vec<u8>> {
    let (st, id) = item_id(item);
    if st != 0 {
        return Err(st);
    }
    Ok(id)
}

fn argocd_run(args: &[Vec<u8>]) -> Res<i32> {
    let sub = param(
        args,
        1,
        37,
        "usage: argocd-secret-backup | argocd-secret-restore | argocd-secret-verify",
    )?;
    default_kubeconfig(40)?;
    let k = kctx();
    let ns = sc::env_or("ARGOCD_NAMESPACE", b"argocd");
    let secret: &[u8] = b"argocd-secret";
    let server = sc::env_or("ARGOCD_SERVER_DEPLOY", b"argocd-server");
    let item = sc::env_or(
        "ARGOCD_BW_ITEM",
        b"dev-local argocd-secret (server.secretkey + mcp token)",
    );
    let file = "argocd-secret.yaml";

    // jq is no longer needed; python3 still is, for the YAML edit.
    need_tools(&["kubectl", "bw", "python3"], true)?;
    ensure_session(true, false, (62, 66))?;

    let tmpd = match mktemp_dir_named("argocdsec") {
        Ok(d) => TempDir(d),
        Err(e) => {
            sc::err(format!("mktemp: {}\n", sc::strerror(&e)).as_bytes());
            return Err(1);
        }
    };
    let f = sc::cat(&[&tmpd.0, b"/", file.as_bytes()]);
    let ns_s = String::from_utf8_lossy(&ns).into_owned();
    let item_s = String::from_utf8_lossy(&item).into_owned();
    let read_f = || std::fs::read(sc::path(&f)).unwrap_or_default();

    match sub.as_slice() {
        b"backup" => {
            let o = std::fs::OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open(sc::path(&f))
                .map_err(|e| {
                    sc::redirect_error(104, &f, &e);
                    1
                })?;
            let mut get = kubectl(&k, &[b"-n", &ns, b"get", b"secret", secret, b"-o", b"yaml"]);
            get.stdout(o);
            let st = run(104, &mut get, false);
            if st != 0 {
                return Err(st);
            }
            if !grep_dot(&read_f(), b"kind: Secret") {
                return die(
                    1,
                    format!("ERROR: argocd-secret not found in ns '{}'.", ns_s).as_bytes(),
                );
            }
            if !grep_dot(&read_f(), b"server.secretkey") {
                return die(1, b"ERROR: argocd-secret has no server.secretkey.");
            }
            let st = feed(
                85,
                cmd("python3", &[b"-", &f]),
                STRIP_METADATA_PY.as_bytes(),
                None,
            );
            if st != 0 {
                return Err(st);
            }
            bw_sync();
            let mut id = argocd_item_id(&item)?;
            if id.is_empty() {
                let (st, new_id) = create_item(&item, ARGOCD_NOTES, false);
                if st != 0 {
                    return Err(st);
                }
                id = new_id;
                say(&sc::cat(&[b"Created Bitwarden item: ", &item]));
            }
            delete_old_attachments(&id, file, false);
            let mut up = cmd(
                "bw",
                &[b"create", b"attachment", b"--file", &f, b"--itemid", &id],
            );
            up.stdout(Stdio::null());
            let st = run(117, &mut up, false);
            if st != 0 {
                return Err(st);
            }
            bw_sync();
            say(format!(
                "\u{2713} Backed up argocd-secret to Bitwarden item '{}' (attachment: {}).",
                item_s, file
            )
            .as_bytes());
            Ok(0)
        }
        b"restore" => {
            let id = argocd_item_id(&item)?;
            if id.is_empty() {
                return die(
                    1,
                    format!(
                        "ERROR: Bitwarden item '{}' not found (nothing to restore).",
                        item_s
                    )
                    .as_bytes(),
                );
            }
            bw_sync();
            let st = get_attachment(file, &id, &f, false);
            if st != 0 {
                return Err(st);
            }
            if !grep_dot(&read_f(), b"server.secretkey") {
                return die(
                    1,
                    format!("ERROR: attachment '{}' is missing or invalid.", file).as_bytes(),
                );
            }
            say(&sc::cat(&[
                format!("Applying argocd-secret to ns '{}' and restarting '", ns_s).as_bytes(),
                &server,
                b"'...",
            ]));
            for step in [
                kubectl(&k, &[b"-n", &ns, b"apply", b"-f", &f]),
                kubectl(
                    &k,
                    &[b"-n", &ns, b"rollout", b"restart", b"deployment", &server],
                ),
            ] {
                let mut step = step;
                let st = run(129, &mut step, false);
                if st != 0 {
                    return Err(st);
                }
            }
            say(&sc::cat(&[
                "\u{2713} Restored argocd-secret + restarted ".as_bytes(),
                &server,
                b". The existing MCP JWT will validate.",
            ]));
            Ok(0)
        }
        b"verify" => {
            bw_sync();
            let id = argocd_item_id(&item)?;
            if id.is_empty() {
                return die(
                    1,
                    format!(
                        "\u{2717} No Bitwarden item '{}' found \u{2014} nothing is backed up.",
                        item_s
                    )
                    .as_bytes(),
                );
            }
            if get_attachment(file, &id, &f, true) != 0 {
                return die(
                    1,
                    format!(
                        "\u{2717} Item '{}' exists but has NO '{}' attachment (re-run backup).",
                        item_s, file
                    )
                    .as_bytes(),
                );
            }
            let text = read_f();
            if grep_dot(&text, b"server.secretkey") && grep_dot(&text, b"accounts.mcp.tokens") {
                say(format!("\u{2713} Backup OK: item '{}' holds '{}' with server.secretkey + accounts.mcp.tokens \u{2014} restorable via 'bazel run //tools/gitops:argocd-secret-restore'.", item_s, file).as_bytes());
                Ok(0)
            } else {
                die(
                    1,
                    format!("\u{2717} Attachment '{}' present but missing server.secretkey and/or accounts.mcp.tokens.", file).as_bytes(),
                )
            }
        }
        _ => die(
            2,
            &sc::cat(&[
                b"ERROR: unknown subcommand '",
                &sub,
                b"' (backup|restore|verify)",
            ]),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_item_is_jq_pretty() {
        assert_eq!(
            new_item_json(b"x \"y\"", "n"),
            "{\n  \"type\": 2,\n  \"secureNote\": {\n    \"type\": 0\n  },\n  \"name\": \"x \\\"y\\\"\",\n  \"notes\": \"n\"\n}\n"
        );
    }

    #[test]
    fn strips_server_managed_metadata() {
        let input = br#"{"apiVersion":"v1","items":[{"kind":"Secret","metadata":{"name":"k","resourceVersion":"1","uid":"u","annotations":{"kubectl.kubernetes.io/last-applied-configuration":"x","keep":"y"}}}],"kind":"List","metadata":{"resourceVersion":""}}"#;
        let out = strip_key_list(input).unwrap();
        assert!(!out.contains("resourceVersion"));
        assert!(!out.contains("\"uid\""));
        assert!(!out.contains("last-applied"));
        assert!(out.contains("\"keep\": \"y\""));
        assert!(out.contains("\"metadata\": {}"));
        assert!(strip_key_list(br#"{"kind":"List"}"#).is_err());
    }
}
