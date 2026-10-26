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

//! neon-branch: neon-branch.sh in Rust. Creates, deletes and reads Neon
//! copy-on-write branches through the Neon API with `curl`, exactly as the
//! script does -- same curl argv, same output, same exit codes. The jq the
//! script pipes every response through is [`crate::jq`].
//!
//! The script's control flow has two bash subtleties the port keeps:
//! - Its helpers run inside `$(...)`, where bash clears `set -e`. So a curl
//!   failure inside `find_branch_by_name`, `resolve_parent_branch_id` or
//!   `get_branch_endpoint` is NOT fatal there (curl's message still shows; the
//!   empty response reads as "nothing found"), while the same failure in a
//!   direct `x="$(api_request ...)"` in an action ends the run with curl's
//!   status.
//! - A helper's status is its last pipeline's (`pipefail`), so a jq error in
//!   one ends the run with jq's 5.

use crate::common::{captured, discarded, echo, prog_name, unbound};
use crate::jq::{self, each, one, Produced, J};
use shell_compat::{cat, err, out, subst};
use std::process::Command;

const USAGE: &str = "Usage: {PROG} <create|delete|get> [options]

Actions:
  create    Create a new branch and compute endpoint; print connection info
  delete    Delete an existing branch (idempotent)
  get       Fetch connection info for an existing branch

Options:
  --project-id <id>     Neon Project ID [REQUIRED]
  --api-key <key>       Neon API Key [REQUIRED]
  --branch-name <name>  Branch name [REQUIRED]
  --parent-id <id>      Parent branch name or ID (default: main)
  --api-url <url>       Neon API base URL (default: https://console.neon.tech/api/v2)
  --format <json|url>   Output format (default: json)
  --dry-run             Show planned actions without calling the API
  -h, --help            Show this help message
";

fn usage(code: i32) -> i32 {
    let mut parts = USAGE.splitn(2, "{PROG}");
    let head = parts.next().unwrap_or("");
    let tail = parts.next().unwrap_or("");
    out(&cat(&[head.as_bytes(), &prog_name(), tail.as_bytes()]));
    code
}

struct Opts {
    api_url: Vec<u8>,
    project_id: Vec<u8>,
    api_key: Vec<u8>,
    branch_name: Vec<u8>,
    parent_id: Vec<u8>,
    format: Vec<u8>,
    dry_run: bool,
}

type R<T> = Result<T, i32>;

/// Exit with `st` when it is a failure: `set -e` on a direct command.
fn check(st: i32) -> R<()> {
    if st == 0 {
        Ok(())
    } else {
        Err(st)
    }
}

impl Opts {
    fn curl(&self, method: &[u8], path: &[u8], data: Option<&[u8]>) -> Command {
        let base = self.api_url.strip_suffix(b"/").unwrap_or(&self.api_url);
        let p = path.strip_prefix(b"/").unwrap_or(path);
        let url = cat(&[base, b"/", p]);
        let mut c = Command::new("curl");
        c.args(["-sS", "-f", "-X"])
            .arg(shell_compat::os(method))
            .arg("-H")
            .arg(shell_compat::os(&cat(&[
                b"Authorization: Bearer ",
                &self.api_key,
            ])))
            .args(["-H", "Content-Type: application/json"]);
        if let Some(d) = data.filter(|d| !d.is_empty()) {
            c.arg("-d").arg(shell_compat::os(d));
        }
        c.arg(shell_compat::os(&url));
        c
    }

    /// `x="$(api_request ...)"`: (status, captured).
    fn api(&self, method: &[u8], path: &[u8], data: Option<&[u8]>) -> (i32, Vec<u8>) {
        let line = if data.map_or(false, |d| !d.is_empty()) {
            91
        } else {
            93
        };
        let (st, o) = captured(line, &mut self.curl(method, path, data));
        (st, subst(o))
    }

    fn branches_path(&self) -> Vec<u8> {
        cat(&[b"projects/", &self.project_id, b"/branches"])
    }

    /// `find_branch_by_name` as `$(...)` sees it: (status, output).
    fn find_branch_by_name(&self, name: &[u8]) -> (i32, Vec<u8>) {
        let (_, json) = self.api(b"GET", &self.branches_path(), None);
        let f = |v: &J| -> Produced {
            each(
                v.index("branches").and_then(|b| b.iterate()),
                &|b: &J| match b.index("name") {
                    Ok(n) if n.is_str(name) => (vec![b.clone()], None),
                    Ok(_) => (vec![], None),
                    Err(e) => (vec![], Some(e)),
                },
            )
        };
        let r = jq::run(&echo(&json), true, &f);
        err(&r.stderr);
        (r.status, subst(r.stdout))
    }

    /// `resolve_parent_branch_id` as `$(...)` sees it.
    fn resolve_parent_branch_id(&self) -> (i32, Vec<u8>) {
        let (_, json) = self.api(b"GET", &self.branches_path(), None);
        let p = &self.parent_id;
        let f = |v: &J| -> Produced {
            each(v.index("branches").and_then(|b| b.iterate()), &|b: &J| {
                let hit = match b.index("id") {
                    Ok(id) if id.is_str(p) => true,
                    Ok(_) => match b.index("name") {
                        Ok(n) => n.is_str(p),
                        Err(e) => return (vec![], Some(e)),
                    },
                    Err(e) => return (vec![], Some(e)),
                };
                if hit {
                    one(b.index("id"))
                } else {
                    (vec![], None)
                }
            })
        };
        let r = jq::run(&echo(&json), true, &f);
        err(&r.stderr);
        let id = subst(jq::head1(&r.stdout));
        if id.is_empty() || id == b"null" {
            err(&cat(&[
                b"ERROR: Parent branch '",
                &self.parent_id,
                b"' not found in project '",
                &self.project_id,
                b"'\n",
            ]));
            return (1, Vec::new());
        }
        (0, subst(echo(&id)))
    }

    /// `get_branch_endpoint` as `$(...)` sees it.
    fn get_branch_endpoint(&self, branch_id: &[u8]) -> (i32, Vec<u8>) {
        let path = cat(&[b"projects/", &self.project_id, b"/endpoints"]);
        let (_, json) = self.api(b"GET", &path, None);
        let f = |v: &J| -> Produced {
            each(
                v.index("endpoints").and_then(|b| b.iterate()),
                &|e: &J| match e.index("branch_id") {
                    Ok(b) if b.is_str(branch_id) => one(e.index("host")),
                    Ok(_) => (vec![], None),
                    Err(x) => (vec![], Some(x)),
                },
            )
        };
        let r = jq::run(&echo(&json), true, &f);
        err(&r.stderr);
        (r.status, subst(jq::head1(&r.stdout)))
    }

    fn connection_uri_path(&self, branch_id: &[u8]) -> Vec<u8> {
        cat(&[
            b"projects/",
            &self.project_id,
            b"/connection_uri?branch_id=",
            branch_id,
            b"&database_name=neondb&role_name=neondb_owner",
        ])
    }
}

/// `x="$(echo "$v" | jq -r <filter>)"` in a `set -e` context.
fn jq_assign(v: &[u8], f: &dyn Fn(&J) -> Produced) -> R<Vec<u8>> {
    let r = jq::run(&echo(v), true, f);
    err(&r.stderr);
    check(r.status)?;
    Ok(subst(r.stdout))
}

fn id_of(v: &J) -> Produced {
    one(v.index("id"))
}

fn uri_or_empty(v: &J) -> Produced {
    match v.index("uri") {
        Ok(u) if u.truthy() => (vec![u], None),
        Ok(_) => (vec![], None),
        Err(e) => (vec![], Some(e)),
    }
}

fn connection_json(o: &Opts, branch_id: &[u8], host: &[u8], db_url: &[u8], ready: bool) {
    let mut m = vec![
        ("project_id".to_string(), jq::arg(&o.project_id)),
        ("branch_id".to_string(), jq::arg(branch_id)),
        ("branch_name".to_string(), jq::arg(&o.branch_name)),
        ("host".to_string(), jq::arg(host)),
        ("database_url".to_string(), jq::arg(db_url)),
    ];
    if ready {
        m.push(("status".to_string(), J::str("ready")));
    }
    out(&cat(&[jq::pretty(&J::Obj(m)).as_bytes(), b"\n"]));
}

fn or_default<'a>(v: &'a [u8], d: &'a [u8]) -> &'a [u8] {
    if v.is_empty() {
        d
    } else {
        v
    }
}

fn do_create(o: &Opts) -> R<()> {
    if o.dry_run {
        out(&cat(&[
            b"{\n  \"dry_run\": true,\n  \"action\": \"create\",\n  \"project_id\": \"",
            or_default(&o.project_id, b"dry-run-project"),
            b"\",\n  \"branch_name\": \"",
            or_default(&o.branch_name, b"dry-run-branch"),
            b"\",\n  \"parent_id\": \"",
            &o.parent_id,
            b"\",\n  \"database_url\": \"postgresql://neondb_owner:mock_password@ep-dry-run-123456.us-central-1.aws.neon.tech/neondb?sslmode=require\"\n}\n",
        ]));
        return Ok(());
    }
    let (st, existing) = o.find_branch_by_name(&o.branch_name);
    check(st)?;
    let branch_id = if !existing.is_empty() && existing != b"null" {
        jq_assign(&existing, &id_of)?
    } else {
        let (st, parent) = o.resolve_parent_branch_id();
        check(st)?;
        let payload = jq::pretty(&J::Obj(vec![
            (
                "branch".to_string(),
                J::Obj(vec![
                    ("name".to_string(), jq::arg(&o.branch_name)),
                    ("parent_id".to_string(), jq::arg(&parent)),
                ]),
            ),
            (
                "endpoints".to_string(),
                J::Arr(vec![J::Obj(vec![(
                    "type".to_string(),
                    J::str("read_write"),
                )])]),
            ),
        ]));
        let (st, resp) = o.api(b"POST", &o.branches_path(), Some(payload.as_bytes()));
        check(st)?;
        jq_assign(&resp, &|v: &J| {
            one(v.index("branch").and_then(|b| b.index("id")))
        })?
    };
    let (st, host) = o.get_branch_endpoint(&branch_id);
    check(st)?;
    let (st, uri_resp) = o.api(b"GET", &o.connection_uri_path(&branch_id), None);
    check(st)?;
    let mut db_url = jq_assign(&uri_resp, &uri_or_empty)?;
    if db_url.is_empty() {
        db_url = cat(&[
            b"postgresql://neondb_owner@",
            &host,
            b"/neondb?sslmode=require",
        ]);
    }
    if o.format == b"url" {
        out(&echo(&db_url));
    } else {
        connection_json(o, &branch_id, &host, &db_url, true);
    }
    Ok(())
}

fn do_delete(o: &Opts) -> R<()> {
    if o.dry_run {
        out(&cat(&[
            b"{\"dry_run\": true, \"action\": \"delete\", \"branch_name\": \"",
            or_default(&o.branch_name, b"dry-run-branch"),
            b"\"}\n",
        ]));
        return Ok(());
    }
    let (st, existing) = o.find_branch_by_name(&o.branch_name);
    check(st)?;
    if existing.is_empty() || existing == b"null" {
        out(&cat(&[
            b"{\"status\": \"not_found\", \"branch_name\": \"",
            &o.branch_name,
            b"\", \"message\": \"Branch does not exist, nothing to delete\"}\n",
        ]));
        return Ok(());
    }
    let branch_id = jq_assign(&existing, &id_of)?;
    let path = cat(&[b"projects/", &o.project_id, b"/branches/", &branch_id]);
    check(discarded(93, &mut o.curl(b"DELETE", &path, None)))?;
    out(&cat(&[
        b"{\"status\": \"deleted\", \"branch_id\": \"",
        &branch_id,
        b"\", \"branch_name\": \"",
        &o.branch_name,
        b"\"}\n",
    ]));
    Ok(())
}

fn do_get(o: &Opts) -> R<()> {
    if o.dry_run {
        out(&cat(&[
            b"{\"dry_run\": true, \"action\": \"get\", \"branch_name\": \"",
            or_default(&o.branch_name, b"dry-run-branch"),
            b"\"}\n",
        ]));
        return Ok(());
    }
    let (st, existing) = o.find_branch_by_name(&o.branch_name);
    check(st)?;
    if existing.is_empty() || existing == b"null" {
        err(&cat(&[
            b"ERROR: Branch '",
            &o.branch_name,
            b"' not found\n",
        ]));
        return Err(1);
    }
    let branch_id = jq_assign(&existing, &id_of)?;
    let (st, host) = o.get_branch_endpoint(&branch_id);
    check(st)?;
    let (st, uri_resp) = o.api(b"GET", &o.connection_uri_path(&branch_id), None);
    check(st)?;
    let db_url = jq_assign(&uri_resp, &uri_or_empty)?;
    if o.format == b"url" {
        out(&echo(&db_url));
    } else {
        connection_json(o, &branch_id, &host, &db_url, false);
    }
    Ok(())
}

/// neon-branch.sh's command line; the exit status.
pub fn run(args: &[Vec<u8>]) -> i32 {
    match main(args) {
        Ok(()) => 0,
        Err(c) => c,
    }
}

fn main(args: &[Vec<u8>]) -> R<()> {
    let env = shell_compat::env_or_empty;
    let mut o = Opts {
        api_url: shell_compat::env_or("NEON_API_URL", b"https://console.neon.tech/api/v2"),
        project_id: env("NEON_PROJECT_ID"),
        api_key: env("NEON_API_KEY"),
        branch_name: env("NEON_BRANCH_NAME"),
        parent_id: shell_compat::env_or("NEON_PARENT_ID", b"main"),
        format: b"json".to_vec(),
        dry_run: false,
    };
    let mut action: Vec<u8> = Vec::new();
    let mut i = 0;
    if let Some(a) = args.first() {
        if a == b"create" || a == b"delete" || a == b"get" {
            action = a.clone();
            i = 1;
        }
    }
    while i < args.len() {
        let a = args[i].as_slice();
        let (slot, line): (&mut Vec<u8>, u32) = match a {
            b"--project-id" => (&mut o.project_id, 48),
            b"--api-key" => (&mut o.api_key, 49),
            b"--branch-name" => (&mut o.branch_name, 50),
            b"--parent-id" => (&mut o.parent_id, 51),
            b"--api-url" => (&mut o.api_url, 52),
            b"--format" => (&mut o.format, 53),
            b"--dry-run" => {
                o.dry_run = true;
                i += 1;
                continue;
            }
            b"-h" | b"--help" => return Err(usage(0)),
            _ => {
                err(&cat(&[b"ERROR: Unknown option: ", a, b"\n"]));
                return Err(usage(1));
            }
        };
        match args.get(i + 1) {
            Some(v) => *slot = v.clone(),
            None => return Err(unbound(line)),
        }
        i += 2;
    }
    if action.is_empty() {
        err(b"ERROR: Missing action (create, delete, get)\n");
        return Err(usage(1));
    }
    if !o.dry_run {
        if o.project_id.is_empty() {
            err(b"ERROR: --project-id or NEON_PROJECT_ID is required\n");
            return Err(1);
        }
        if o.api_key.is_empty() {
            err(b"ERROR: --api-key or NEON_API_KEY is required\n");
            return Err(1);
        }
        if o.branch_name.is_empty() {
            err(b"ERROR: --branch-name or NEON_BRANCH_NAME is required\n");
            return Err(1);
        }
    }
    match action.as_slice() {
        b"create" => do_create(&o),
        b"delete" => do_delete(&o),
        _ => do_get(&o),
    }
}
