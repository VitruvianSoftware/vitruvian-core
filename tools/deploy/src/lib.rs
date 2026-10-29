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

//! cloud-run: the blue-green Cloud Run deploy sequencer (candidate -> smoke
//! -> promote), ported from cloud-run.sh and held to it byte for byte by
//! cloud_run_rs_parity_test.py: the same output, exit codes, pulumi/gcloud/
//! curl calls and the same <PREFIX>_ variables handed to them.
//!
//! What the script does that is easy to get wrong in a port, and is kept:
//! - `pulumi up` goes through `bash <ws>/tools/pulumi/pulumi-cmd.sh`, so
//!   identity and backend resolve as for `bazel run //<app>:up`.
//! - per-invocation state reaches Pulumi as exported <PREFIX>_IMAGE_DIGEST
//!   (or _IMAGE_TAG), <PREFIX>_STABLE_REVISION and <PREFIX>_PROMOTE (#499).
//! - the smoke step never falls back to the stable URL on a non-first deploy
//!   (#808); the candidate URL is read from `gcloud ... --format=json`, which
//!   the script filtered with jq and this port parses with serde_json.
//! - the stable revision is the one carrying traffic in `gcloud ... describe
//!   --format=json` (largest percent > 0), never `status.traffic[0]`: a
//!   failed 0% candidate can be listed first.
//! - a gcloud failure reading the stable revision that is not a NOT_FOUND,
//!   or a service where nothing carries traffic, fails the deploy (exit 1)
//!   instead of carrying on as a first deploy.

use serde_json::Value;
use shell_compat::{cat, err, out, subst};
use std::process::{Command, Stdio};

const USAGE: &str = "Usage: bazel run //tools/deploy:cloud-run -- \\
  --pulumi-dir <dir> --service <name> --env <stack> --env-prefix <PREFIX> \\
  --project <gcp-project> --region <region> \\
  (--image-digest <ref@sha256:..> | --image-tag <tag>) \\
  [--smoke-path /health] [--custom-smoke-script '<sh>'] [--refresh] \\
  [--stable-revision <rev>] [--phase all|candidate|smoke|promote] [--dry-run]
";

/// How the script stops early: the exit status it leaves with.
type Exit = Result<(), i32>;

fn usage() -> i32 {
    err(USAGE.as_bytes());
    2
}

/// The script's own name as bash puts it in front of its diagnostics.
fn prog() -> Vec<u8> {
    use std::os::unix::ffi::OsStringExt;
    std::env::args_os()
        .next()
        .map(|a| a.into_vec())
        .unwrap_or_default()
}

/// `<script>: line <n>: <what>` on stderr, as bash reports its own errors.
fn diag(line: u32, what: &[u8]) {
    err(&cat(&[
        &prog(),
        format!(": line {}: ", line).as_bytes(),
        what,
        b"\n",
    ]));
}

// ---------------------------------------------------------------------------
// pure pieces (unit-tested below, and in the script by cloud-run_test.sh)
// ---------------------------------------------------------------------------

/// bash's builtin `echo "$x"`: a lone argument made only of n/e/E option
/// letters (`-n`, `-e`, `-neE`, ...) is taken as options, not printed.
pub fn bash_echo(arg: &[u8]) -> Vec<u8> {
    let is_opts = arg.len() >= 2
        && arg[0] == b'-'
        && arg[1..].iter().all(|c| matches!(c, b'n' | b'e' | b'E'));
    if is_opts {
        if arg.contains(&b'n') {
            Vec::new()
        } else {
            b"\n".to_vec()
        }
    } else {
        cat(&[arg, b"\n"])
    }
}

/// resolve_smoke_url (#808): the URL to smoke, as `$(resolve_smoke_url ...)`
/// captures it. A resolved candidate always wins; no service URL means no
/// smoke (empty); a first deploy smokes the live URL; otherwise refuse.
pub fn resolve_smoke_url(
    cand: &[u8],
    first_deploy: &[u8],
    service_url: &[u8],
) -> Result<Vec<u8>, Vec<u8>> {
    if !cand.is_empty() && cand != b"null" {
        return Ok(subst(bash_echo(cand)));
    }
    if service_url.is_empty() || service_url == b"null" {
        return Ok(Vec::new());
    }
    if first_deploy == b"true" {
        return Ok(subst(bash_echo(service_url)));
    }
    Err(b"cloud-run: could not resolve the candidate revision URL on a non-first deploy. Refusing to smoke the stable revision (that would false-green and promote an untested revision, #808). Failing.\n".to_vec())
}

/// `grep -qiE "not_found|not found|cannot find|404|does not exist|may not exist"`
/// over `echo "$text"`.
pub fn looks_not_found(text: &[u8]) -> bool {
    let lower: Vec<u8> = bash_echo(text)
        .iter()
        .map(|c| c.to_ascii_lowercase())
        .collect();
    [
        &b"not_found"[..],
        b"not found",
        b"cannot find",
        b"404",
        b"does not exist",
        b"may not exist",
    ]
    .iter()
    .any(|n| shell_compat::contains(&lower, n))
}

/// serving_revision: the revision actually serving, from `gcloud run
/// services describe --format=json`. Only `status.traffic` entries with a
/// revisionName and a percent above 0 count (Cloud Run omits `percent` when
/// it is 0); shares naming the same revision add up, and the largest total
/// wins. On a tie the revision listed first wins. None when nothing carries
/// traffic or the JSON is not a service.
///
/// The order of `status.traffic` is not a contract: a failed candidate at 0%
/// behind the `candidate` tag can be listed first, and taking
/// `status.traffic[0]` then promoted a revision that never started.
pub fn serving_revision(describe_json: &[u8]) -> Option<Vec<u8>> {
    let v: Value = serde_json::from_slice(describe_json).ok()?;
    let mut shares: Vec<(&str, f64)> = Vec::new();
    for t in v.pointer("/status/traffic")?.as_array()? {
        let name = match t.get("revisionName").and_then(Value::as_str) {
            Some(n) if !n.is_empty() => n,
            _ => continue,
        };
        let pct = t.get("percent").and_then(Value::as_f64).unwrap_or(0.0);
        if pct <= 0.0 {
            continue;
        }
        match shares.iter_mut().find(|(n, _)| *n == name) {
            Some(s) => s.1 += pct,
            None => shares.push((name, pct)),
        }
    }
    let mut best: Option<(&str, f64)> = None;
    for (n, p) in shares {
        if best.map_or(true, |(_, bp)| p > bp) {
            best = Some((n, p));
        }
    }
    best.map(|(n, _)| n.as_bytes().to_vec())
}

/// resolve_stable_revision: the currently-serving revision from a `gcloud
/// run services describe --format=json` (status, stderr, stdout). Ok is the
/// revision (empty for a confirmed first deploy); Err is what to print on
/// stderr before failing closed. A service that exists but where no revision
/// carries traffic is an error, never a first deploy.
pub fn resolve_stable_revision(
    rc: i32,
    stderr_content: &[u8],
    stdout_value: &[u8],
    svc: &[u8],
) -> Result<Vec<u8>, Vec<u8>> {
    if rc == 0 {
        return serving_revision(stdout_value).ok_or_else(|| {
            cat(&[
                b"cloud-run: ",
                svc,
                b" exists but no revision carries traffic (no status.traffic entry with a revisionName and percent > 0).\n",
                b"cloud-run: refusing to guess -- treating this as a first deploy would route 100% of traffic to an unsmoked revision. Failing closed.\n",
            ])
        });
    }
    if looks_not_found(stderr_content) {
        return Ok(Vec::new());
    }
    Err(cat(&[
        b"cloud-run: could not read the live/stable revision for ",
        svc,
        b":\n",
        &shell_compat::indent(&bash_echo(stderr_content)),
        format!(
            "cloud-run: refusing to guess -- treating this as a first deploy would skip the blue-green rollout and route 100% of traffic to an unsmoked revision. Failing closed (rc={}).\n",
            rc
        )
        .as_bytes(),
    ]))
}

/// image_env_kv: the <PREFIX>_IMAGE_* assignment (digest wins), as echoed.
pub fn image_env_kv(prefix: &[u8], digest: &[u8], tag: &[u8]) -> Vec<u8> {
    if !digest.is_empty() {
        cat(&[prefix, b"_IMAGE_DIGEST=", digest, b"\n"])
    } else {
        cat(&[prefix, b"_IMAGE_TAG=", tag, b"\n"])
    }
}

/// `sed 's/=/ = /'`: the first `=` on every line spaced out.
pub fn sed_spaced_eq(text: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(text.len() + 4);
    let mut done = false;
    for &c in text {
        if c == b'\n' {
            done = false;
            v.push(c);
        } else if c == b'=' && !done {
            v.extend_from_slice(b" = ");
            done = true;
        } else {
            v.push(c);
        }
    }
    v
}

/// What `jq -r '.status.traffic[]? | select(.tag=="candidate") | .url'`
/// prints for `input` (a stream of JSON documents): one line per candidate
/// URL, strings raw. Like jq, an error (invalid JSON, indexing a non-object)
/// stops it, keeping what was printed before.
pub fn jq_candidate_urls(input: &[u8]) -> Vec<u8> {
    fn field<'a>(v: &'a Value, k: &str) -> Result<&'a Value, ()> {
        static NULL: Value = Value::Null;
        match v {
            Value::Object(m) => Ok(m.get(k).unwrap_or(&NULL)),
            Value::Null => Ok(&NULL),
            _ => Err(()),
        }
    }
    fn emit(o: &mut Vec<u8>, v: &Value) {
        match v {
            Value::String(s) => o.extend_from_slice(s.as_bytes()),
            Value::Array(_) | Value::Object(_) => o.extend_from_slice(
                serde_json::to_string_pretty(v)
                    .unwrap_or_default()
                    .as_bytes(),
            ),
            _ => o.extend_from_slice(v.to_string().as_bytes()),
        }
        o.push(b'\n');
    }
    let mut o = Vec::new();
    for doc in serde_json::Deserializer::from_slice(input).into_iter::<Value>() {
        let Ok(doc) = doc else { break };
        let step = (|| -> Result<(), ()> {
            let traffic = field(field(&doc, "status")?, "traffic")?;
            let items: Vec<&Value> = match traffic {
                Value::Array(a) => a.iter().collect(),
                Value::Object(m) => m.values().collect(),
                _ => Vec::new(),
            };
            for e in items {
                if field(e, "tag")? == "candidate" {
                    emit(&mut o, field(e, "url")?);
                }
            }
            Ok(())
        })();
        if step.is_err() {
            break;
        }
    }
    o
}

/// `export "NAME=VALUE"`: the name and value, or None when NAME is not a
/// shell identifier (bash refuses it).
pub fn export_name(assignment: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    let eq = assignment.iter().position(|&c| c == b'=')?;
    let (name, value) = (&assignment[..eq], &assignment[eq + 1..]);
    let valid = !name.is_empty()
        && (name[0].is_ascii_alphabetic() || name[0] == b'_')
        && name.iter().all(|c| c.is_ascii_alphanumeric() || *c == b'_');
    if valid {
        Some((name.to_vec(), value.to_vec()))
    } else {
        None
    }
}

// ---------------------------------------------------------------------------
// the sequencer
// ---------------------------------------------------------------------------

#[derive(Default)]
struct Cfg {
    pulumi_dir: Vec<u8>,
    service: Vec<u8>,
    env: Vec<u8>,
    prefix: Vec<u8>,
    project: Vec<u8>,
    region: Vec<u8>,
    image_digest: Vec<u8>,
    image_tag: Vec<u8>,
    smoke_path: Vec<u8>,
    custom_smoke: Vec<u8>,
    refresh: bool,
    stable_override: Vec<u8>,
    phase: Vec<u8>,
    dry_run: bool,
    // derived
    svc: Vec<u8>,
    stable: Vec<u8>,
    first_deploy: bool,
}

/// Where pulumi_wrap's output goes.
enum Wrap {
    /// `>/dev/null 2>&1`
    Silent,
    /// straight through
    Inherit,
    /// `$(... 2>/dev/null)`
    Capture,
}

fn os(b: &[u8]) -> &std::ffi::OsStr {
    shell_compat::os(b)
}

impl Cfg {
    fn image_kv(&self) -> Vec<u8> {
        image_env_kv(&self.prefix, &self.image_digest, &self.image_tag)
    }

    /// pulumi_wrap: `bash <ws>/tools/pulumi/pulumi-cmd.sh <dir> <args>`, or
    /// the DRYRUN line. Ok carries (status, captured stdout); Err is the
    /// script exiting.
    fn pulumi_wrap(&self, args: &[&[u8]], how: Wrap) -> Result<(i32, Vec<u8>), i32> {
        if self.dry_run {
            let joined: Vec<u8> = args.join(&b' ');
            let line = cat(&[
                b"DRYRUN pulumi: (dir=",
                &self.pulumi_dir,
                b") pulumi ",
                &joined,
                b"\n",
            ]);
            return match how {
                Wrap::Inherit => {
                    out(&line);
                    Ok((0, Vec::new()))
                }
                Wrap::Silent => Ok((0, Vec::new())),
                Wrap::Capture => Ok((0, line)),
            };
        }
        if !shell_compat::env_set_nonempty("BUILD_WORKSPACE_DIRECTORY") {
            // ${BUILD_WORKSPACE_DIRECTORY:?...}: the shell exits 1; its
            // message follows the call's stderr (silenced unless Inherit).
            if let Wrap::Inherit = how {
                diag(
                    105,
                    b"BUILD_WORKSPACE_DIRECTORY: cloud-run must be invoked via 'bazel run'",
                );
            }
            return Err(1);
        }
        let wrap = cat(&[
            &shell_compat::env_or_empty("BUILD_WORKSPACE_DIRECTORY"),
            b"/tools/pulumi/pulumi-cmd.sh",
        ]);
        let mut cmd = Command::new("bash");
        cmd.arg(os(&wrap)).arg(os(&self.pulumi_dir));
        for a in args {
            cmd.arg(os(a));
        }
        match how {
            Wrap::Silent => {
                cmd.stdout(Stdio::null()).stderr(Stdio::null());
                Ok((shell_compat::status(106, &mut cmd, true), Vec::new()))
            }
            Wrap::Inherit => Ok((shell_compat::status(106, &mut cmd, false), Vec::new())),
            Wrap::Capture => {
                cmd.stdin(Stdio::inherit())
                    .stderr(Stdio::null())
                    .stdout(Stdio::piped());
                match cmd.output() {
                    Ok(o) => Ok((shell_compat::status_code(o.status), o.stdout)),
                    Err(e) => Ok((shell_compat::spawn_failure_status(&e), Vec::new())),
                }
            }
        }
    }

    /// `$(pulumi_wrap stack output serviceUrl --stack "$ENV" 2>/dev/null || true)`
    fn service_url(&self) -> Result<Vec<u8>, i32> {
        let (_, o) = self.pulumi_wrap(
            &[b"stack", b"output", b"serviceUrl", b"--stack", &self.env],
            Wrap::Capture,
        )?;
        Ok(subst(o))
    }

    fn ensure_stack(&self) -> Exit {
        if self.dry_run {
            out(&cat(&[
                b"DRYRUN pulumi: (dir=",
                &self.pulumi_dir,
                b") ensure stack '",
                &self.env,
                b"' exists (stack select -c)\n",
            ]));
            return Ok(());
        }
        let (st, _) = self.pulumi_wrap(&[b"stack", b"select", &self.env], Wrap::Silent)?;
        if st != 0 {
            self.pulumi_wrap(&[b"stack", b"select", &self.env, b"-c"], Wrap::Silent)?;
        }
        Ok(())
    }

    fn export(&self, line: u32, assignment: &[u8]) -> Exit {
        match export_name(assignment) {
            Some((n, v)) => {
                std::env::set_var(os(&n), os(&v));
                Ok(())
            }
            None => {
                diag(
                    line,
                    &cat(&[b"export: `", assignment, b"': not a valid identifier"]),
                );
                Err(1)
            }
        }
    }

    fn deploy_phase(&self, promote: bool) -> Exit {
        let mut refresh = false;
        if !promote {
            refresh = self.refresh || self.first_deploy;
        }
        let promote_s: &[u8] = if promote { b"true" } else { b"false" };
        self.export(145, &subst(self.image_kv()))?;
        self.export(
            146,
            &cat(&[&self.prefix, b"_STABLE_REVISION=", &self.stable]),
        )?;
        self.export(147, &cat(&[&self.prefix, b"_PROMOTE=", promote_s]))?;
        let stable_shown: &[u8] = if self.stable.is_empty() {
            b"<empty>"
        } else {
            &self.stable
        };
        err(&cat(&[
            b"cloud-run: [",
            if promote { b"promote" } else { b"candidate" },
            b"] ",
            &self.prefix,
            b"_PROMOTE=",
            promote_s,
            b" ",
            &self.prefix,
            b"_STABLE_REVISION=",
            stable_shown,
            b"\n",
        ]));
        let mut args: Vec<&[u8]> = vec![b"up", b"--stack", &self.env, b"--yes"];
        if refresh {
            args.push(b"--refresh");
        }
        let (st, _) = self.pulumi_wrap(&args, Wrap::Inherit)?;
        if st != 0 {
            return Err(st);
        }
        Ok(())
    }

    fn smoke_phase(&self) -> Exit {
        if self.dry_run {
            err(&cat(&[
                b"DRYRUN smoke: resolve candidate URL for ",
                &self.svc,
                b", then GET <url>",
                &self.smoke_path,
                b" (first_deploy=",
                if self.first_deploy { b"true" } else { b"false" },
                b")\n",
            ]));
            return Ok(());
        }
        let described = Command::new("gcloud")
            .args(["run", "services", "describe"])
            .arg(os(&self.svc))
            .arg("--project")
            .arg(os(&self.project))
            .arg("--region")
            .arg(os(&self.region))
            .arg("--format=json")
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .map(|o| o.stdout)
            .unwrap_or_default();
        let cand = subst(shell_compat::first_line(&jq_candidate_urls(&described)));
        let service_url = self.service_url()?;
        let first: &[u8] = if self.first_deploy { b"true" } else { b"false" };
        let url = match resolve_smoke_url(&cand, first, &service_url) {
            Ok(u) => u,
            Err(msg) => {
                err(&msg);
                return Err(1);
            }
        };
        if url.is_empty() {
            err(b"cloud-run: stack exported no service URL (workload disabled or non-serving); skipping smoke test.\n");
            return Ok(());
        }
        let st = if !self.custom_smoke.is_empty() {
            err(&cat(&[
                b"cloud-run: running custom smoke against ",
                &url,
                b"\n",
            ]));
            let mut cmd = Command::new("bash");
            cmd.env("CAND", os(&url))
                .arg("-c")
                .arg(os(&self.custom_smoke));
            shell_compat::status(169, &mut cmd, false)
        } else {
            err(&cat(&[
                b"cloud-run: smoke GET ",
                &url,
                &self.smoke_path,
                b"\n",
            ]));
            let mut cmd = Command::new("curl");
            cmd.args([
                "--fail",
                "--retry",
                "10",
                "--retry-delay",
                "5",
                "--retry-connrefused",
            ])
            .arg(os(&cat(&[&url, &self.smoke_path])));
            shell_compat::status(172, &mut cmd, false)
        };
        if st != 0 {
            return Err(st);
        }
        Ok(())
    }

    /// The live stable revision: `gcloud run services describe` as JSON, its
    /// stdout and stderr captured apart. Read-only.
    fn lookup_stable(&self) -> Result<Vec<u8>, i32> {
        let mut cmd = Command::new("gcloud");
        cmd.args(["run", "services", "describe"])
            .arg(os(&self.svc))
            .arg("--project")
            .arg(os(&self.project))
            .arg("--region")
            .arg(os(&self.region))
            .arg("--format=json");
        let ran = shell_compat::capture(234, &mut cmd);
        let raw = subst(ran.stdout);
        let err_text = subst(ran.stderr);
        // Fail closed (the script's original `|| exit 1`). #2053 turned this
        // into `|| STABLE=""`, so an unreadable stable revision quietly
        // became a first deploy.
        resolve_stable_revision(ran.status, &err_text, &raw, &self.svc).map_err(|msg| {
            err(&msg);
            1
        })
    }
}

/// `CUSTOM_SMOKE="$(cat "${BUILD_WORKSPACE_DIRECTORY:?...}/$2")"`
fn read_smoke_file(rel: &[u8]) -> Result<Vec<u8>, i32> {
    if !shell_compat::env_set_nonempty("BUILD_WORKSPACE_DIRECTORY") {
        diag(
            198,
            b"BUILD_WORKSPACE_DIRECTORY: --custom-smoke-script-file needs bazel run",
        );
        return Err(1);
    }
    let p = cat(&[
        &shell_compat::env_or_empty("BUILD_WORKSPACE_DIRECTORY"),
        b"/",
        rel,
    ]);
    let mut cmd = Command::new("cat");
    cmd.arg(os(&p));
    let ran = shell_compat::capture_stdout(198, &mut cmd);
    if ran.status != 0 {
        return Err(ran.status);
    }
    Ok(subst(ran.stdout))
}

fn parse(args: &[Vec<u8>]) -> Result<Cfg, i32> {
    let mut c = Cfg {
        smoke_path: b"/".to_vec(),
        phase: b"all".to_vec(),
        ..Default::default()
    };
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_slice();
        let next = args.get(i + 1).cloned().unwrap_or_default();
        // `shift 2` past the end fails, and set -e ends the script (1).
        let two = |i: usize| {
            if i + 2 > args.len() {
                Err(1)
            } else {
                Ok(i + 2)
            }
        };
        i = match a {
            b"--pulumi-dir" => {
                c.pulumi_dir = next;
                two(i)?
            }
            b"--service" => {
                c.service = next;
                two(i)?
            }
            b"--env" => {
                c.env = next;
                two(i)?
            }
            b"--env-prefix" => {
                c.prefix = next;
                two(i)?
            }
            b"--project" => {
                c.project = next;
                two(i)?
            }
            b"--region" => {
                c.region = next;
                two(i)?
            }
            b"--image-digest" => {
                c.image_digest = next;
                two(i)?
            }
            b"--image-tag" => {
                c.image_tag = next;
                two(i)?
            }
            b"--smoke-path" => {
                c.smoke_path = next;
                two(i)?
            }
            b"--custom-smoke-script" => {
                c.custom_smoke = next;
                two(i)?
            }
            b"--custom-smoke-script-file" => {
                c.custom_smoke = read_smoke_file(&next)?;
                two(i)?
            }
            b"--refresh" => {
                c.refresh = true;
                i + 1
            }
            b"--stable-revision" => {
                c.stable_override = next;
                two(i)?
            }
            b"--phase" => {
                c.phase = next;
                two(i)?
            }
            b"--dry-run" => {
                c.dry_run = true;
                i + 1
            }
            b"-h" | b"--help" => return Err(usage()),
            _ => {
                err(&cat(&[b"cloud-run: unknown argument '", a, b"'\n"]));
                return Err(usage());
            }
        };
    }
    for (v, flag) in [
        (&c.pulumi_dir, "--pulumi-dir"),
        (&c.service, "--service"),
        (&c.env, "--env"),
        (&c.prefix, "--env-prefix"),
        (&c.project, "--project"),
        (&c.region, "--region"),
    ] {
        if v.is_empty() {
            err(format!("cloud-run: missing required {}\n", flag).as_bytes());
            return Err(usage());
        }
    }
    if !matches!(
        c.phase.as_slice(),
        b"all" | b"candidate" | b"smoke" | b"promote"
    ) {
        err(b"cloud-run: --phase must be all|candidate|smoke|promote\n");
        return Err(usage());
    }
    if c.image_digest.is_empty() && c.image_tag.is_empty() {
        err(b"cloud-run: need --image-digest or --image-tag\n");
        return Err(usage());
    }
    Ok(c)
}

fn main_inner(args: &[Vec<u8>]) -> Exit {
    let mut c = parse(args)?;
    c.svc = cat(&[&c.service, b"-", &c.env]);
    c.ensure_stack()?;

    if !c.stable_override.is_empty() {
        c.stable = c.stable_override.clone();
    } else if !c.dry_run {
        c.stable = c.lookup_stable()?;
    }
    c.first_deploy = c.stable.is_empty();
    let first: &[u8] = if c.first_deploy { b"true" } else { b"false" };

    err(&cat(&[
        b"cloud-run: service=",
        &c.svc,
        b" env=",
        &c.env,
        b" prefix=",
        &c.prefix,
        b" phase=",
        &c.phase,
        b" ",
        &subst(sed_spaced_eq(&c.image_kv())),
        b"\n",
    ]));
    let stable_shown: &[u8] = if c.stable.is_empty() {
        b"<none, first deploy>"
    } else {
        &c.stable
    };
    err(&cat(&[
        b"cloud-run: stable_revision=",
        stable_shown,
        b" first_deploy=",
        first,
        b"\n",
    ]));

    let done = cat(&[
        b"cloud-run: phase '",
        &c.phase,
        b"' complete for ",
        &c.svc,
        b".\n",
    ]);
    match c.phase.as_slice() {
        b"candidate" => c.deploy_phase(false)?,
        b"smoke" => c.smoke_phase()?,
        b"promote" => c.deploy_phase(true)?,
        _ => {
            c.deploy_phase(false)?;
            c.smoke_phase()?;
            if !c.dry_run {
                let srv = c.service_url()?;
                if srv.is_empty() || srv == b"null" {
                    err(b"cloud-run: stack exported no service URL (workload disabled or non-serving); skipping promote phase.\n");
                    err(&done);
                    return Ok(());
                }
            }
            c.deploy_phase(true)?;
        }
    }
    err(&done);
    Ok(())
}

/// The script's `main "$@"`: the exit status.
pub fn run(args: &[Vec<u8>]) -> i32 {
    match main_inner(args) {
        Ok(()) => 0,
        Err(code) => code,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn smoke(c: &str, f: &str, s: &str) -> Result<String, ()> {
        resolve_smoke_url(c.as_bytes(), f.as_bytes(), s.as_bytes())
            .map(|v| String::from_utf8(v).unwrap())
            .map_err(|_| ())
    }

    #[test]
    fn smoke_url_cases_from_cloud_run_test() {
        assert_eq!(
            smoke("https://cand.example", "false", "https://live.example"),
            Ok("https://cand.example".into())
        );
        assert_eq!(
            smoke("", "true", "https://live.example"),
            Ok("https://live.example".into())
        );
        assert!(smoke("", "false", "https://live.example").is_err());
        assert_eq!(
            smoke("null", "true", "https://live.example"),
            Ok("https://live.example".into())
        );
        for f in ["true", "false"] {
            assert_eq!(smoke("", f, ""), Ok(String::new()));
            assert_eq!(smoke("", f, "null"), Ok(String::new()));
        }
        // bash's echo eats a lone option-like argument.
        assert_eq!(smoke("-n", "false", "x"), Ok(String::new()));
    }

    fn stable(rc: i32, e: &str, o: &str) -> Result<String, String> {
        resolve_stable_revision(rc, e.as_bytes(), o.as_bytes(), b"svc")
            .map(|v| String::from_utf8(v).unwrap())
            .map_err(|v| String::from_utf8(v).unwrap())
    }

    #[test]
    fn stable_revision_cases_from_cloud_run_test() {
        assert_eq!(
            stable(
                0,
                "",
                r#"{"status":{"traffic":[{"revisionName":"tabula-api-development-abc123","percent":100}]}}"#
            ),
            Ok("tabula-api-development-abc123".into())
        );
        for e in [
            "ERROR: (gcloud.run.services.describe) NOT_FOUND: Requested entity was not found.",
            "ERROR: (gcloud.run.services.describe) Cannot find service [x]",
            "ERROR: (gcloud.run.services.describe) Resource 'namespaces/p/services/s' was not found",
            "ERROR: PERMISSION_DENIED: denied on resource (or resource may not exist).",
            "HTTP 404",
            "the service Does Not Exist",
        ] {
            assert_eq!(stable(1, e, ""), Ok(String::new()), "{}", e);
        }
        let msg = stable(
            1,
            "ERROR: PERMISSION_DENIED: caller lacks permission\nline two",
            "",
        )
        .unwrap_err();
        assert!(msg.starts_with("cloud-run: could not read the live/stable revision for svc:\n  ERROR: PERMISSION_DENIED"));
        assert!(msg.contains("\n  line two\n"));
        assert!(msg.ends_with("Failing closed (rc=1).\n"));
        assert!(stable(
            1,
            "There was a problem refreshing your current auth tokens",
            ""
        )
        .is_err());
        // empty stderr: echo gives "\n", sed indents it.
        assert!(stable(2, "", "")
            .unwrap_err()
            .contains("for svc:\n  \ncloud-run: refusing"));
    }

    fn serving(traffic: &str) -> Option<String> {
        let j = format!(r#"{{"status":{{"traffic":{}}}}}"#, traffic);
        serving_revision(j.as_bytes()).map(|v| String::from_utf8(v).unwrap())
    }

    /// The production failure (run 40817981512 onwards): a failed candidate
    /// published at 0% behind the `candidate` tag is listed FIRST. The
    /// stable revision is the one carrying the traffic, not the first entry.
    #[test]
    fn stable_is_the_revision_carrying_traffic_not_the_first_entry() {
        assert_eq!(
            serving(
                r#"[{"tag":"candidate","revisionName":"B","percent":0},{"revisionName":"A","percent":100}]"#
            ),
            Some("A".into())
        );
        // Cloud Run omits `percent` when it is 0.
        assert_eq!(
            serving(
                r#"[{"tag":"candidate","revisionName":"B","url":"https://c"},{"revisionName":"A","percent":100,"latestRevision":false}]"#
            ),
            Some("A".into())
        );
    }

    #[test]
    fn stable_revision_from_traffic_split() {
        // normal: stable first, candidate at 0%
        assert_eq!(
            serving(
                r#"[{"revisionName":"A","percent":100},{"tag":"candidate","revisionName":"B","percent":0}]"#
            ),
            Some("A".into())
        );
        // split: the largest share wins, wherever it is listed
        assert_eq!(
            serving(r#"[{"revisionName":"A","percent":90},{"revisionName":"B","percent":10}]"#),
            Some("A".into())
        );
        assert_eq!(
            serving(r#"[{"revisionName":"B","percent":10},{"revisionName":"A","percent":90}]"#),
            Some("A".into())
        );
        // one revision named by two entries: its shares add up
        assert_eq!(
            serving(
                r#"[{"revisionName":"B","percent":40},{"revisionName":"A","percent":30},{"revisionName":"A","percent":30}]"#
            ),
            Some("A".into())
        );
        // tie: the revision listed first wins
        assert_eq!(
            serving(r#"[{"revisionName":"A","percent":50},{"revisionName":"B","percent":50}]"#),
            Some("A".into())
        );
        // an entry with traffic but no revision name is never chosen
        assert_eq!(
            serving(r#"[{"latestRevision":true,"percent":100},{"revisionName":"A","percent":0}]"#),
            None
        );
        // nothing carries traffic
        assert_eq!(
            serving(r#"[{"tag":"candidate","revisionName":"B","percent":0}]"#),
            None
        );
        assert_eq!(serving(r#"[{"tag":"candidate","revisionName":"B"}]"#), None);
        assert_eq!(serving("[]"), None);
        assert_eq!(serving_revision(br#"{"status":{}}"#), None);
        assert_eq!(serving_revision(b""), None);
        assert_eq!(serving_revision(b"not json"), None);
    }

    #[test]
    fn existing_service_with_no_serving_revision_fails_closed() {
        for o in [
            r#"{"status":{"traffic":[]}}"#,
            r#"{"status":{"traffic":[{"tag":"candidate","revisionName":"B","percent":0}]}}"#,
            "",
            "tabula-api-development-abc123",
        ] {
            let msg = stable(0, "", o).unwrap_err();
            assert!(
                msg.starts_with("cloud-run: svc exists but no revision carries traffic"),
                "{}",
                msg
            );
            assert!(msg.ends_with("Failing closed.\n"), "{}", msg);
        }
        // gcloud can exit 0 with an ERROR on stderr and nothing on stdout.
        assert!(stable(0, "ERROR: Reauthentication failed.", "").is_err());
        assert_eq!(
            stable(
                0,
                "",
                r#"{"status":{"traffic":[{"tag":"candidate","revisionName":"B","percent":0},{"revisionName":"A","percent":100}]}}"#
            ),
            Ok("A".into())
        );
    }

    #[test]
    fn echo_options() {
        assert_eq!(bash_echo(b"-n"), b"");
        assert_eq!(bash_echo(b"-e"), b"\n");
        assert_eq!(bash_echo(b"-neE"), b"");
        assert_eq!(bash_echo(b"-nx"), b"-nx\n");
        assert_eq!(bash_echo(b"-"), b"-\n");
    }

    #[test]
    fn jq_filter() {
        let j = br#"{"status":{"traffic":[{"revisionName":"a","percent":100},{"tag":"candidate","url":"https://c.example"},{"tag":"candidate","url":"https://d"}]}}"#;
        assert_eq!(jq_candidate_urls(j), b"https://c.example\nhttps://d\n");
        assert_eq!(jq_candidate_urls(b""), b"");
        assert_eq!(jq_candidate_urls(b"not json"), b"");
        assert_eq!(jq_candidate_urls(br#"{"status":null}"#), b"");
        assert_eq!(jq_candidate_urls(br#"{"status":{"traffic":5}}"#), b"");
        assert_eq!(
            jq_candidate_urls(br#"{"status":{"traffic":[{"tag":"candidate"}]}}"#),
            b"null\n"
        );
        // an error mid-stream keeps what came before
        assert_eq!(
            jq_candidate_urls(br#"{"status":{"traffic":[{"tag":"candidate","url":"u"},7,{"tag":"candidate","url":"v"}]}}"#),
            b"u\n"
        );
        assert_eq!(jq_candidate_urls(br#"{"status":"x"}"#), b"");
        assert_eq!(
            jq_candidate_urls(br#"{"status":{"traffic":[{"tag":"candidate","url":"a"}]}} {"status":{"traffic":[{"tag":"candidate","url":"b"}]}}"#),
            b"a\nb\n"
        );
    }

    #[test]
    fn kv_and_sed() {
        assert_eq!(
            image_env_kv(b"T", b"r@sha256:x", b"v"),
            b"T_IMAGE_DIGEST=r@sha256:x\n"
        );
        assert_eq!(image_env_kv(b"T", b"", b"v"), b"T_IMAGE_TAG=v\n");
        assert_eq!(sed_spaced_eq(b"A=b=c\nD=e\n"), b"A = b=c\nD = e\n");
    }

    #[test]
    fn export_names() {
        assert_eq!(
            export_name(b"A_B=1"),
            Some((b"A_B".to_vec(), b"1".to_vec()))
        );
        assert_eq!(
            export_name(b"A=B_X=1"),
            Some((b"A".to_vec(), b"B_X=1".to_vec()))
        );
        assert_eq!(export_name(b"a-b_X=1"), None);
        assert_eq!(export_name(b"1A=1"), None);
    }
}
