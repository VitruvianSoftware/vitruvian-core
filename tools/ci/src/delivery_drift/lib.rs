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

//! delivery-drift.sh — report delivery units whose last successful delivery is
//! behind main.

use shell_compat::{capture, cat, env, env_or, env_or_empty, err, mktemp_dir, out, status, subst};
use std::collections::HashMap;
use std::process::Command;

fn log(msg: &[u8]) {
    err(&cat(&[b"delivery-drift: ", msg, b"\n"]));
}

const DELIVERY_QUERY: &[u8] =
    b"attr(tags, \"\\bdelivery\\b\", (//... except //apps/desktop/nexus-agent/macos/...))";

const RUNS_QUERY: &str = r#"query($id: ID!, $n: Int!, $after: String) {
  node(id: $id) { ... on Workflow { runs(first: $n, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { databaseId checkSuite { branch { name } commit { oid }
      checkRuns(first: 100, filterBy: {conclusions: [SUCCESS]}) { nodes { name } } } } } } } }"#;

struct PageCache {
    dir: Vec<u8>,
    wf_ids: HashMap<Vec<u8>, Vec<u8>>,
}

impl PageCache {
    fn new(dir: Vec<u8>) -> Self {
        Self {
            dir,
            wf_ids: HashMap::new(),
        }
    }

    fn page_path(&self, wf: &[u8], page: usize) -> std::path::PathBuf {
        let name = cat(&[wf, b".", page.to_string().as_bytes()]);
        let full = cat(&[&self.dir, b"/", &name]);
        shell_compat::path(&full).to_path_buf()
    }

    fn wf_id(&mut self, wf: &[u8], gh: &[u8], repo: &[u8]) -> Option<Vec<u8>> {
        if let Some(id) = self.wf_ids.get(wf) {
            return Some(id.clone());
        }
        let r = capture(
            178,
            Command::new(shell_compat::os(gh))
                .arg("api")
                .arg(shell_compat::os(&cat(&[
                    b"repos/",
                    repo,
                    b"/actions/workflows/",
                    wf,
                ])))
                .arg("--jq")
                .arg(".node_id"),
        );
        if !r.ok() {
            return None;
        }
        let id = subst(r.stdout);
        if id.is_empty() {
            return None;
        }
        self.wf_ids.insert(wf.to_vec(), id.clone());
        Some(id)
    }

    fn fetch_page(
        &mut self,
        wf: &[u8],
        page: usize,
        gh: &[u8],
        repo: &[u8],
        page_size: &[u8],
    ) -> bool {
        let p = self.page_path(wf, page);
        if p.exists() && std::fs::metadata(&p).map(|m| m.len() > 0).unwrap_or(false) {
            return true;
        }
        let node_id = match self.wf_id(wf, gh, repo) {
            Some(id) => id,
            None => return false,
        };
        let mut after = Vec::new();
        if page > 1 {
            let prev = self.page_path(wf, page - 1);
            if let Ok(content) = std::fs::read(&prev) {
                for line in content.split(|&c| c == b'\n') {
                    if line.starts_with(b"next\t") {
                        after = line[5..].to_vec();
                        break;
                    }
                }
            }
        }
        let mut args: Vec<Vec<u8>> = vec![
            b"api".to_vec(),
            b"graphql".to_vec(),
            b"-f".to_vec(),
            cat(&[b"query=", RUNS_QUERY.as_bytes()]),
            b"-f".to_vec(),
            cat(&[b"id=", &node_id]),
            b"-F".to_vec(),
            cat(&[b"n=", page_size]),
        ];
        if !after.is_empty() {
            args.push(b"-f".to_vec());
            args.push(cat(&[b"after=", &after]));
        }
        let mut cmd = Command::new(shell_compat::os(gh));
        for a in &args {
            cmd.arg(shell_compat::os(a));
        }
        let r = capture(186, &mut cmd);
        if !r.ok() {
            return false;
        }
        let raw = subst(r.stdout);

        let py_script = r#"
import json, sys
d = json.loads(sys.argv[1])
if d.get("errors"):
    sys.exit(1)
runs = d["data"]["node"]["runs"]
for r in runs["nodes"]:
    cs = r.get("checkSuite") or {}
    jobs = [c["name"] for c in ((cs.get("checkRuns") or {}).get("nodes") or [])]
    print("run\t%s\t%s\t%s\t%s" % (r["databaseId"], (cs.get("commit") or {}).get("oid") or "",
                                   (cs.get("branch") or {}).get("name") or "", "\037".join(jobs)))
print("next\t%s" % (runs["pageInfo"]["endCursor"] if runs["pageInfo"]["hasNextPage"] else ""))
"#;
        let r2 = capture(
            199,
            Command::new("python3")
                .arg("-c")
                .arg(py_script)
                .arg(shell_compat::os(&raw)),
        );
        if !r2.ok() {
            return false;
        }
        let parsed = subst(r2.stdout);
        let part = cat(&[p.to_string_lossy().as_bytes(), b".part"]);
        if shell_compat::write_file(&part, &parsed, 0o644).is_err() {
            return false;
        }
        std::fs::rename(shell_compat::path(&part), &p).is_ok()
    }
}

#[derive(Clone)]
struct LastDelivered {
    sha: Vec<u8>,
    state: Vec<u8>,
    runs: usize,
}

fn last_delivered(
    cache: &mut PageCache,
    wf: &[u8],
    prefix: &[u8],
    branch: &[u8],
    gh: &[u8],
    repo: &[u8],
    page_size: &[u8],
    run_scan_limit: usize,
) -> LastDelivered {
    let ps: usize = std::str::from_utf8(page_size)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(100);
    let max_pages = (run_scan_limit + ps - 1) / ps;
    let mut total_runs: usize = 0;

    for page in 1..=max_pages {
        if !cache.fetch_page(wf, page, gh, repo, page_size) {
            return LastDelivered {
                sha: Vec::new(),
                state: b"error".to_vec(),
                runs: total_runs,
            };
        }
        let p = cache.page_path(wf, page);
        let content = match std::fs::read(&p) {
            Ok(c) => c,
            Err(_) => {
                return LastDelivered {
                    sha: Vec::new(),
                    state: b"error".to_vec(),
                    runs: total_runs,
                };
            }
        };
        let mut page_runs = 0usize;
        let mut next_cursor = Vec::new();
        for line in content.split(|&c| c == b'\n') {
            if line.is_empty() {
                continue;
            }
            if line.starts_with(b"next\t") {
                next_cursor = line[5..].to_vec();
                continue;
            }
            if !line.starts_with(b"run\t") {
                continue;
            }
            page_runs += 1;
            // run<TAB>id<TAB>sha<TAB>branch<TAB>jobs(\x1f-separated)
            let fields: Vec<&[u8]> = line.splitn(5, |&c| c == b'\t').collect();
            if fields.len() < 5 {
                continue;
            }
            let run_branch = fields[3];
            if run_branch != branch {
                continue;
            }
            let sha = fields[2];
            let jobs_raw = fields[4];
            for job in jobs_raw.split(|&c| c == 0x1f) {
                if job.len() >= prefix.len() && &job[..prefix.len()] == prefix {
                    return LastDelivered {
                        sha: sha.to_vec(),
                        state: b"found".to_vec(),
                        runs: total_runs + page_runs,
                    };
                }
            }
        }
        total_runs += page_runs;
        if next_cursor.is_empty() {
            return LastDelivered {
                sha: Vec::new(),
                state: b"absent".to_vec(),
                runs: total_runs,
            };
        }
    }
    LastDelivered {
        sha: Vec::new(),
        state: b"capped".to_vec(),
        runs: total_runs,
    }
}

fn why_unknown(name: &[u8], env_name: &[u8], wf: &[u8], ld: &LastDelivered, run_scan_limit: usize) {
    match ld.state.as_slice() {
        b"error" => log(&cat(&[
            name,
            b": could not read the run history of ",
            wf,
            b" -- UNKNOWN (nothing inferred from a failed read)",
        ])),
        b"capped" => log(&cat(&[
            name,
            b": no successful ",
            env_name,
            b" delivery in the newest ",
            ld.runs.to_string().as_bytes(),
            b" runs of ",
            wf,
            b", and its history goes back further (RUN_SCAN_LIMIT=",
            run_scan_limit.to_string().as_bytes(),
            b") -- UNKNOWN",
        ])),
        _ => log(&cat(&[
            name,
            b": no successful ",
            env_name,
            b" delivery in the whole history of ",
            wf,
            b" (",
            ld.runs.to_string().as_bytes(),
            b" runs) -- UNKNOWN",
        ])),
    }
}

struct JudgedCommit {
    state: Vec<u8>,
    sha: Vec<u8>,
    why: Vec<u8>,
}

fn find_judged_commit(
    wf: &[u8],
    gh: &[u8],
    repo: &[u8],
    branch: &[u8],
    head_sha: &[u8],
    drift_recent_runs: &[u8],
    ignore_in_flight: bool,
) -> JudgedCommit {
    if ignore_in_flight {
        return JudgedCommit {
            state: b"judge".to_vec(),
            sha: head_sha.to_vec(),
            why: b"main's tip (DRIFT_IGNORE_IN_FLIGHT set)".to_vec(),
        };
    }
    let r = capture(
        333,
        Command::new(shell_compat::os(gh))
            .arg("run")
            .arg("list")
            .arg("--repo")
            .arg(shell_compat::os(repo))
            .arg("--workflow")
            .arg(shell_compat::os(wf))
            .arg("--branch")
            .arg(shell_compat::os(branch))
            .arg("--event")
            .arg("push")
            .arg("--limit")
            .arg(shell_compat::os(drift_recent_runs))
            .arg("--json")
            .arg("databaseId,status,headSha,conclusion")
            .arg("--jq")
            .arg(r#".[] | "\(.databaseId) \(.status) \(.headSha) \(.conclusion)"#),
    );
    if !r.ok() {
        return JudgedCommit {
            state: b"unknown".to_vec(),
            sha: b"-".to_vec(),
            why: cat(&[b"could not read the recent runs of `", wf, b"`"]),
        };
    }
    let raw = subst(r.stdout);

    // Check for waiting runs (approval gate)
    for line in shell_compat::lines(&raw) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&[u8]> = line.splitn(4, |&c| c == b' ').collect();
        if fields.len() < 3 {
            continue;
        }
        let id = fields[0];
        let run_status = fields[1];
        if run_status == b"waiting" {
            return JudgedCommit {
                state: b"skip".to_vec(),
                sha: b"-".to_vec(),
                why: cat(&[
                    b"run ",
                    id,
                    b" of `",
                    wf,
                    b"` is waiting on an approval (it will deliver once approved)",
                ]),
            };
        }
    }

    // Find newest finished, non-cancelled run
    let mut in_flight: u64 = 0;
    let mut passed_over: u64 = 0;
    let mut found_sha = Vec::new();
    let mut found_id = Vec::new();
    let mut found_conclusion = Vec::new();
    for line in shell_compat::lines(&raw) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&[u8]> = line.splitn(4, |&c| c == b' ').collect();
        if fields.len() < 3 {
            continue;
        }
        let id = fields[0];
        let run_status = fields[1];
        let sha = fields[2];
        let conclusion = if fields.len() > 3 { fields[3] } else { b"" };

        if run_status != b"completed" {
            in_flight += 1;
            continue;
        }
        match conclusion {
            b"cancelled" | b"skipped" | b"stale" => {
                passed_over += 1;
                continue;
            }
            _ => {
                found_sha = sha.to_vec();
                found_id = id.to_vec();
                found_conclusion = conclusion.to_vec();
                break;
            }
        }
    }

    if found_sha.is_empty() {
        return JudgedCommit {
            state: b"skip".to_vec(),
            sha: b"-".to_vec(),
            why: cat(&[
                b"no finished push run among the newest ",
                drift_recent_runs,
                b" of `",
                wf,
                b"` (",
                in_flight.to_string().as_bytes(),
                b" in flight, ",
                passed_over.to_string().as_bytes(),
                b" cancelled)",
            ]),
        };
    }

    let conc_display = if found_conclusion.is_empty() {
        b"no conclusion".to_vec()
    } else {
        found_conclusion.clone()
    };
    let mut why = cat(&[
        b"newest finished run of `",
        wf,
        b"` (",
        &found_id,
        b", ",
        &conc_display,
        b") at `",
        &found_sha[..std::cmp::min(8, found_sha.len())],
        b"`",
    ]);
    if in_flight > 0 {
        why = cat(&[
            &why,
            b"; ",
            in_flight.to_string().as_bytes(),
            b" newer still in flight",
        ]);
    }
    if passed_over > 0 {
        why = cat(&[
            &why,
            b"; ",
            passed_over.to_string().as_bytes(),
            b" newer cancelled",
        ]);
    }

    // Check if sha is in local checkout
    let rc = status(
        371,
        Command::new("git")
            .arg("rev-parse")
            .arg("--verify")
            .arg("--quiet")
            .arg(shell_compat::os(&cat(&[&found_sha, b"^{commit}"])))
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null()),
        true,
    );
    if rc != 0 {
        let r2 = capture(
            374,
            Command::new(shell_compat::os(gh))
                .arg("api")
                .arg(shell_compat::os(&cat(&[
                    b"repos/",
                    repo,
                    b"/compare/",
                    head_sha,
                    b"...",
                    &found_sha,
                ])))
                .arg("--jq")
                .arg(".status"),
        );
        let relation = if r2.ok() {
            subst(r2.stdout)
        } else {
            Vec::new()
        };
        return match relation.as_slice() {
            b"ahead" | b"identical" => JudgedCommit {
                state: b"judge".to_vec(),
                sha: head_sha.to_vec(),
                why: cat(&[&why, b", newer than this checkout: judged at the checkout"]),
            },
            _ => JudgedCommit {
                state: b"unknown".to_vec(),
                sha: b"-".to_vec(),
                why: cat(&[
                    &why,
                    b", which is not in this checkout (GitHub compare: ",
                    if relation.is_empty() {
                        b"no answer"
                    } else {
                        &relation
                    },
                    b")",
                ]),
            },
        };
    }

    JudgedCommit {
        state: b"judge".to_vec(),
        sha: found_sha,
        why,
    }
}

fn ask_engine(
    engine: &[u8],
    engine_is_binary: bool,
    extra: &[u8],
    exclude: &[u8],
    targets: &[u8],
    before: &[u8],
    after: &[u8],
) -> Vec<u8> {
    let mut cmd;
    if engine_is_binary {
        cmd = Command::new(shell_compat::os(engine));
    } else {
        cmd = Command::new("bash");
        cmd.arg(shell_compat::os(engine));
    }
    cmd.env("EXTRA_PATH_REGEX", shell_compat::os(extra))
        .env("EXCLUDE_PATH_REGEX", shell_compat::os(exclude))
        .env("DEPLOY_TARGETS", shell_compat::os(targets))
        .env("BEFORE_REV", shell_compat::os(before))
        .env("AFTER_REV", shell_compat::os(after))
        .env("GITHUB_OUTPUT", "/dev/null")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    match cmd.output() {
        Ok(o) => {
            let mut out = o.stdout;
            out.extend_from_slice(&o.stderr);
            subst(out)
        }
        Err(_) => Vec::new(),
    }
}

fn json_field_str(meta_path: &[u8], expr: &str) -> Vec<u8> {
    let r = capture(
        302,
        Command::new("python3")
            .arg("-c")
            .arg(expr)
            .arg(shell_compat::os(meta_path)),
    );
    if r.ok() {
        subst(r.stdout)
    } else {
        Vec::new()
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let repo = env_or("REPO", b"VitruvianSoftware/vitruvian-core");
    let workflow_file = env_or_empty("WORKFLOW_FILE");
    // LEGACY_WORKFLOW_FILE: default "delivery.yaml", empty disables
    let legacy_workflow_file = match env("LEGACY_WORKFLOW_FILE") {
        Some(v) => v,
        None => b"delivery.yaml".to_vec(),
    };
    let branch = env_or("BRANCH", b"main");
    let run_scan_limit: usize = std::str::from_utf8(&env_or("RUN_SCAN_LIMIT", b"5000"))
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(5000);
    let page_size = env_or("DRIFT_PAGE_SIZE", b"100");
    let bazel = env_or("BAZEL", b"bazel");
    let gh = env_or("GH", b"gh");
    let drift_recent_runs = env_or("DRIFT_RECENT_RUNS", b"50");
    let drift_result_file = env_or_empty("DRIFT_RESULT_FILE");
    let drift_summary_file = env_or_empty("DRIFT_SUMMARY_FILE");
    let ignore_in_flight = shell_compat::env_set_nonempty("DRIFT_IGNORE_IN_FLIGHT");

    let engine = match env("DEPLOY_AFFECTED_BIN") {
        Some(v) if !v.is_empty() => v,
        _ => b"tools/ci/deploy-affected.sh".to_vec(),
    };
    let engine_is_binary = !engine.ends_with(b".sh");

    if shell_compat::which(&gh).is_none() {
        log(b"gh not found on PATH");
        return 2;
    }

    // --- 1. discover delivery units ---
    let r = capture(
        136,
        Command::new(shell_compat::os(&bazel))
            .arg("query")
            .arg(shell_compat::os(DELIVERY_QUERY))
            .arg("--output=label")
            .stderr(std::process::Stdio::null()),
    );
    let labels_raw = subst(r.stdout);
    if labels_raw.is_empty() {
        log(b"no delivery units declared (or bazel query failed) -- nothing to check");
        return 2;
    }
    let labels: Vec<Vec<u8>> = shell_compat::lines(&labels_raw)
        .into_iter()
        .filter(|l| !l.is_empty())
        .collect();

    // Build metadata
    let mut build_cmd = Command::new(shell_compat::os(&bazel));
    build_cmd
        .arg("build")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    for l in &labels {
        build_cmd.arg(shell_compat::os(l));
    }
    let rc = status(142, &mut build_cmd, true);
    if rc != 0 {
        log(b"bazel build of delivery metadata failed");
        return 2;
    }

    let r = capture(
        146,
        Command::new(shell_compat::os(&bazel))
            .arg("info")
            .arg("bazel-bin")
            .stderr(std::process::Stdio::null()),
    );
    let bin_dir = subst(r.stdout);

    let page_dir = match mktemp_dir() {
        Ok(d) => d,
        Err(_) => {
            log(b"failed to create temp directory");
            return 2;
        }
    };
    let mut page_cache = PageCache::new(page_dir.clone());

    let head_r = capture(259, Command::new("git").arg("rev-parse").arg("HEAD"));
    let head_sha = subst(head_r.stdout);

    // Tracking
    let mut drift_found = false;
    let mut bad: u64 = 0;
    let mut checked: u64 = 0;
    let mut skipped: u64 = 0;
    let mut checked_md = Vec::new();
    let mut skipped_md = Vec::new();
    let mut skipped_names = Vec::new();

    // Per-unit data
    struct Unit {
        name: Vec<u8>,
        first_env: Vec<u8>,
        wf: Vec<u8>,
        meta: Vec<u8>,
    }
    let mut units: Vec<Unit> = Vec::new();

    for label in &labels {
        // //pkg/sub:x.delivery_unit -> pkg/sub/x.delivery.json
        let mut rel = label.clone();
        while rel.starts_with(b"@") {
            rel = rel[1..].to_vec();
        }
        if rel.starts_with(b"//") {
            rel = rel[2..].to_vec();
        }
        let (pkg, tgt) = if let Some(colon) = rel.iter().position(|&c| c == b':') {
            (rel[..colon].to_vec(), rel[colon + 1..].to_vec())
        } else {
            continue;
        };
        let tgt_base = if tgt.ends_with(b".delivery_unit") {
            &tgt[..tgt.len() - 14]
        } else {
            &tgt
        };
        let meta = cat(&[&bin_dir, b"/", &pkg, b"/", tgt_base, b".delivery.json"]);
        if !shell_compat::is_file(&meta) {
            log(&cat(&[
                b"metadata missing for ",
                label,
                b" -- cannot check, treating as UNKNOWN",
            ]));
            bad += 1;
            drift_found = true;
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                label,
                b"`: **UNKNOWN: its metadata is missing**\n",
            ]));
            continue;
        }

        let name = json_field_str(
            &meta,
            "import json,sys; print(json.load(open(sys.argv[1]))['name'])",
        );
        let first_env = json_field_str(
            &meta,
            "import json,sys; e=json.load(open(sys.argv[1])).get('environments') or ['']; print(e[0])",
        );
        let app = json_field_str(
            &meta,
            "import json,sys; print(json.load(open(sys.argv[1])).get('app') or '')",
        );
        if name.is_empty() {
            continue;
        }

        let wf = if !workflow_file.is_empty() {
            workflow_file.clone()
        } else if !app.is_empty() {
            cat(&[b"delivery-", &app, b".yaml"])
        } else {
            Vec::new()
        };
        if wf.is_empty() {
            log(&cat(&[
                &name,
                b": declares no app, so no workflow delivers it -- UNKNOWN",
            ]));
            bad += 1;
            drift_found = true;
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &name,
                b"`: **UNKNOWN: it declares no app, so no workflow delivers it**\n",
            ]));
            continue;
        }

        units.push(Unit {
            name,
            first_env,
            wf,
            meta,
        });
    }

    // --- judged commit cache per workflow ---
    let mut jc_cache: HashMap<Vec<u8>, JudgedCommit> = HashMap::new();

    // --- 4. per-unit check ---
    for unit in &units {
        let jc = jc_cache.entry(unit.wf.clone()).or_insert_with(|| {
            find_judged_commit(
                &unit.wf,
                &gh,
                &repo,
                &branch,
                &head_sha,
                &drift_recent_runs,
                ignore_in_flight,
            )
        });

        match jc.state.as_slice() {
            b"judge" => {}
            b"skip" => {
                log(&cat(&[&unit.name, b": ", &jc.why, b" -- not checked"]));
                skipped += 1;
                skipped_md.extend_from_slice(&cat(&[b"- `", &unit.name, b"`: ", &jc.why, b"\n"]));
                if !skipped_names.is_empty() {
                    skipped_names.extend_from_slice(b", ");
                }
                skipped_names.extend_from_slice(&unit.name);
                continue;
            }
            _ => {
                log(&cat(&[&unit.name, b": ", &jc.why, b" -- UNKNOWN"]));
                bad += 1;
                drift_found = true;
                checked += 1;
                checked_md.extend_from_slice(&cat(&[
                    b"- `",
                    &unit.name,
                    b"`: **UNKNOWN: ",
                    &jc.why,
                    b"**\n",
                ]));
                continue;
            }
        }

        let judge_sha = jc.sha.clone();
        let at = cat(&[
            b"judged at `",
            &judge_sha[..std::cmp::min(8, judge_sha.len())],
            b"`",
        ]);
        let job_prefix = cat(&[&unit.name, b"-", &unit.first_env]);

        let mut ld = last_delivered(
            &mut page_cache,
            &unit.wf,
            &job_prefix,
            &branch,
            &gh,
            &repo,
            &page_size,
            run_scan_limit,
        );

        if ld.state == b"absent"
            && !legacy_workflow_file.is_empty()
            && legacy_workflow_file != unit.wf
        {
            ld = last_delivered(
                &mut page_cache,
                &legacy_workflow_file,
                &job_prefix,
                &branch,
                &gh,
                &repo,
                &page_size,
                run_scan_limit,
            );
            if ld.state == b"found" {
                log(&cat(&[
                    &unit.name,
                    b": no delivery in the whole history of ",
                    &unit.wf,
                    b"; last delivered by ",
                    &legacy_workflow_file,
                ]));
            }
        }

        let wf_display = if ld.state != b"found"
            && !legacy_workflow_file.is_empty()
            && legacy_workflow_file != unit.wf
        {
            cat(&[&unit.wf, b" or ", &legacy_workflow_file])
        } else {
            unit.wf.clone()
        };

        if ld.state != b"found" {
            why_unknown(
                &unit.name,
                &unit.first_env,
                &wf_display,
                &ld,
                run_scan_limit,
            );
            bad += 1;
            drift_found = true;
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: **UNKNOWN: no delivery found in `",
                &wf_display,
                b"` (",
                &ld.state,
                b", ",
                ld.runs.to_string().as_bytes(),
                b" runs read)**\n",
            ]));
            continue;
        }

        let last_sha = ld.sha.clone();
        if last_sha == judge_sha {
            log(&cat(&[
                &unit.name,
                b": up to date (delivered ",
                &judge_sha[..std::cmp::min(8, judge_sha.len())],
                b") -- ",
                &jc.why,
            ]));
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: up to date (delivered `",
                &judge_sha[..std::cmp::min(8, judge_sha.len())],
                b"`)\n",
            ]));
            continue;
        }

        // Check if last_sha contains judge_sha
        let ls_rc = status(
            438,
            Command::new("git")
                .arg("rev-parse")
                .arg("--verify")
                .arg("--quiet")
                .arg(shell_compat::os(&cat(&[&last_sha, b"^{commit}"])))
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
            true,
        );
        if ls_rc != 0 {
            let r2 = capture(
                441,
                Command::new(shell_compat::os(&gh))
                    .arg("api")
                    .arg(shell_compat::os(&cat(&[
                        b"repos/",
                        &repo,
                        b"/compare/",
                        &judge_sha,
                        b"...",
                        &last_sha,
                    ])))
                    .arg("--jq")
                    .arg(".status"),
            );
            let relation = if r2.ok() {
                subst(r2.stdout)
            } else {
                Vec::new()
            };
            if relation == b"ahead" {
                log(&cat(&[
                    &unit.name,
                    b": up to date (delivered ",
                    &last_sha[..std::cmp::min(8, last_sha.len())],
                    b", newer than ",
                    &judge_sha[..std::cmp::min(8, judge_sha.len())],
                    b")",
                ]));
                checked += 1;
                checked_md.extend_from_slice(&cat(&[
                    b"- `",
                    &unit.name,
                    b"`: up to date (delivered `",
                    &last_sha[..std::cmp::min(8, last_sha.len())],
                    b"`, newer than the judged `",
                    &judge_sha[..std::cmp::min(8, judge_sha.len())],
                    b"`)\n",
                ]));
                continue;
            }
            log(&cat(&[
                &unit.name,
                b": last-delivered commit ",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b" not in this checkout, and GitHub's compare says '",
                if relation.is_empty() {
                    b"no answer"
                } else {
                    &relation
                },
                b"' -- UNKNOWN",
            ]));
            bad += 1;
            drift_found = true;
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: **UNKNOWN: delivered `",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"`, which is not in this checkout**\n",
            ]));
            continue;
        }

        let anc_rc = status(
            451,
            Command::new("git")
                .arg("merge-base")
                .arg("--is-ancestor")
                .arg(shell_compat::os(&judge_sha))
                .arg(shell_compat::os(&last_sha))
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
            true,
        );
        if anc_rc == 0 {
            log(&cat(&[
                &unit.name,
                b": up to date (delivered ",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b", which includes the judged ",
                &judge_sha[..std::cmp::min(8, judge_sha.len())],
                b")",
            ]));
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: up to date (delivered `",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"`, which includes the judged `",
                &judge_sha[..std::cmp::min(8, judge_sha.len())],
                b"`)\n",
            ]));
            continue;
        }

        // Read per-unit metadata for the engine
        let extra = json_field_str(
            &unit.meta,
            "import json,sys; print('|'.join(json.load(open(sys.argv[1])).get('extra_paths') or []))",
        );
        let exclude = json_field_str(
            &unit.meta,
            "import json,sys; print('|'.join(json.load(open(sys.argv[1])).get('exclude_paths') or []))",
        );
        let targets = json_field_str(
            &unit.meta,
            "import json,sys; print(' '.join(json.load(open(sys.argv[1])).get('graph_targets') or []))",
        );

        // PHASE 1 — range pre-filter
        let phase1 = ask_engine(
            &engine,
            engine_is_binary,
            &extra,
            &exclude,
            &targets,
            &last_sha,
            &judge_sha,
        );
        if shell_compat::contains(&phase1, b"deploy-gate-fallback")
            || shell_compat::contains(&phase1, b"gate degraded")
        {
            log(&cat(&[
                &unit.name,
                b": engine could not determine affectedness (gate degraded) -- NOT CHECKED",
            ]));
            skipped += 1;
            skipped_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: the affectedness engine could not tell (gate degraded)\n",
            ]));
            if !skipped_names.is_empty() {
                skipped_names.extend_from_slice(b", ");
            }
            skipped_names.extend_from_slice(&unit.name);
            continue;
        }
        if !shell_compat::contains(&phase1, b"affected=true") {
            let reason = extract_reason(&phase1, b"affected=false (");
            log(&cat(&[
                &unit.name,
                b": delivered ",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"; nothing since affects it (",
                &reason,
                b")",
            ]));
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: delivered `",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"`; nothing since affects it (",
                &at,
                b")\n",
            ]));
            continue;
        }

        // PHASE 2 — per-commit check
        let rev_r = capture(
            506,
            Command::new("git")
                .arg("rev-list")
                .arg("--reverse")
                .arg(shell_compat::os(&cat(&[&last_sha, b"..", &judge_sha]))),
        );
        let rev_list = subst(rev_r.stdout);
        let mut culprit = Vec::new();
        let mut culprit_why = Vec::new();
        for c in shell_compat::lines(&rev_list) {
            if c.is_empty() {
                continue;
            }
            let v = ask_engine(
                &engine,
                engine_is_binary,
                &extra,
                &exclude,
                &targets,
                &cat(&[&c, b"^"]),
                &c,
            );
            if shell_compat::contains(&v, b"deploy-gate-fallback")
                || shell_compat::contains(&v, b"gate degraded")
            {
                continue;
            }
            if shell_compat::contains(&v, b"affected=true") {
                culprit = c;
                culprit_why = extract_reason(&v, b"affected=true (");
                break;
            }
        }

        if culprit.is_empty() {
            log(&cat(&[
                &unit.name,
                b": delivered ",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"; only version-bump commits since (promote by tag, nothing to deploy)",
            ]));
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: delivered `",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"`; only version-bump commits since (",
                &at,
                b")\n",
            ]));
            continue;
        }

        // Get commit subject
        let subj_r = capture(
            523,
            Command::new("git")
                .arg("log")
                .arg("-1")
                .arg("--pretty=%s")
                .arg(shell_compat::os(&culprit)),
        );
        let subj = subst(subj_r.stdout);
        let subj_short = if subj.len() > 60 { &subj[..60] } else { &subj };

        log(&cat(&[
            b"DRIFT ",
            &unit.name,
            b": last delivered ",
            &last_sha[..std::cmp::min(8, last_sha.len())],
            b", but ",
            &culprit[..std::cmp::min(8, culprit.len())],
            b" ('",
            subj_short,
            b"') should have delivered and did not -- ",
            &culprit_why,
            b" -- judged at the ",
            &jc.why,
        ]));
        bad += 1;
        drift_found = true;
        checked += 1;
        checked_md.extend_from_slice(&cat(&[
            b"- `",
            &unit.name,
            b"`: **DRIFT: last delivered `",
            &last_sha[..std::cmp::min(8, last_sha.len())],
            b"`, but `",
            &culprit[..std::cmp::min(8, culprit.len())],
            b"` should have delivered and did not (",
            &at,
            b")**\n",
        ]));
    }

    // --- 5. verdict ---
    let total = checked + skipped;
    log(&cat(&[
        b"checked ",
        checked.to_string().as_bytes(),
        b" unit(s), not checked ",
        skipped.to_string().as_bytes(),
    ]));

    let (verdict, conclusion, title);
    if drift_found {
        verdict = b"DRIFT".to_vec();
        conclusion = b"failure".to_vec();
        title = cat(&[
            bad.to_string().as_bytes(),
            b" of ",
            total.to_string().as_bytes(),
            b" unit(s) behind main or unknown",
        ]);
    } else if checked == 0 {
        verdict = b"NOTHING_CHECKED".to_vec();
        conclusion = b"neutral".to_vec();
        title = cat(&[
            b"Nothing checked: all ",
            skipped.to_string().as_bytes(),
            b" unit(s) were skipped",
        ]);
    } else {
        verdict = b"OK".to_vec();
        conclusion = b"success".to_vec();
        title = if skipped == 0 {
            cat(&[checked.to_string().as_bytes(), b" unit(s) delivered"])
        } else {
            cat(&[
                checked.to_string().as_bytes(),
                b" unit(s) delivered; ",
                skipped.to_string().as_bytes(),
                b" not checked",
            ])
        };
    }

    if !skipped_names.is_empty() {
        log(&cat(&[b"NOT CHECKED: ", &skipped_names]));
    }

    if !drift_result_file.is_empty() {
        let data = cat(&[
            b"conclusion=",
            &conclusion,
            b"\ntitle=",
            &title,
            b"\nchecked=",
            checked.to_string().as_bytes(),
            b"\nskipped=",
            skipped.to_string().as_bytes(),
            b"\n",
        ]);
        let _ = std::fs::OpenOptions::new()
            .append(true)
            .create(true)
            .open(shell_compat::path(&drift_result_file))
            .and_then(|mut f| {
                use std::io::Write;
                f.write_all(&data)
            });
    }

    if !drift_summary_file.is_empty() {
        let mut summary = cat(&[
            b"**",
            &title,
            b"** (commit `",
            &head_sha[..std::cmp::min(8, head_sha.len())],
            b"`)\n\n",
        ]);
        if verdict == b"NOTHING_CHECKED" {
            summary.extend_from_slice(b"This is not a pass: no unit was judged. Every one was skipped, for the reason given below.\n\n");
        }
        if !checked_md.is_empty() {
            summary.extend_from_slice(&cat(&[
                b"### Checked (",
                checked.to_string().as_bytes(),
                b")\n",
            ]));
            summary.extend_from_slice(&checked_md);
            summary.push(b'\n');
        }
        if !skipped_md.is_empty() {
            summary.extend_from_slice(&cat(&[
                b"### Not checked (",
                skipped.to_string().as_bytes(),
                b")\n",
            ]));
            summary.extend_from_slice(&skipped_md);
            summary.push(b'\n');
        }
        if checked > 0 {
            summary.extend_from_slice(b"Each unit is judged at the newest finished delivery run of its app, not at main's tip: newer commits are still being delivered, and a later check judges them.\n");
        }
        let _ = shell_compat::write_file(&drift_summary_file, &summary, 0o644);
    }

    out(&cat(&[&verdict, b"\n"]));

    // Clean up temp dir
    let _ = std::fs::remove_dir_all(shell_compat::path(&page_dir));

    if verdict == b"DRIFT" {
        1
    } else {
        0
    }
}

fn extract_reason(text: &[u8], marker: &[u8]) -> Vec<u8> {
    if let Some(pos) = text.windows(marker.len()).position(|w| w == marker) {
        let rest = &text[pos..];
        if let Some(end) = rest.iter().position(|&c| c == b'\n') {
            return rest[..end].to_vec();
        }
        return rest.to_vec();
    }
    Vec::new()
}
