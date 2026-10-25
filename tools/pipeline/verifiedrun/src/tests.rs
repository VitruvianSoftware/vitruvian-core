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

//! The cases of main_test.go, record_test.go and shim_test.go.

use super::*;
use std::cell::RefCell;
use std::fs;
use std::io::{BufRead, BufReader, Read};
use std::net::TcpListener;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::{Arc, Mutex};

fn s(v: &[&str]) -> Vec<String> {
    v.iter().map(|x| x.to_string()).collect()
}

fn tmp(tag: &str) -> PathBuf {
    let base = std::env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let d = base.join(format!("vr-{tag}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&d);
    fs::create_dir_all(&d).unwrap();
    d
}

fn git_t(dir: &str, args: &[&str]) -> String {
    let out = std::process::Command::new("git")
        .args([
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.com",
            "-c",
            "commit.gpgsign=false",
        ])
        .args(args)
        .current_dir(dir)
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn new_repo(tag: &str) -> String {
    let d = tmp(tag);
    let d = d.to_str().unwrap().to_string();
    git_t(&d, &["init", "-q"]);
    fs::write(format!("{d}/a.txt"), "one\n").unwrap();
    git_t(&d, &["add", "a.txt"]);
    git_t(&d, &["commit", "-q", "-m", "first"]);
    d
}

#[test]
fn tree_hash_follows_files_not_commits() {
    let ctx = Ctx::background();
    let dir = new_repo("tree");
    let tree1 = tree_hash(&ctx, &dir).unwrap();
    assert_eq!(tree1, git_t(&dir, &["rev-parse", "HEAD^{tree}"]));
    let commit1 = git_t(&dir, &["rev-parse", "HEAD"]);
    git_t(
        &dir,
        &["commit", "-q", "--amend", "-m", "a different message"],
    );
    assert_ne!(git_t(&dir, &["rev-parse", "HEAD"]), commit1);
    assert_eq!(tree_hash(&ctx, &dir).unwrap(), tree1);
    fs::write(format!("{dir}/a.txt"), "two\n").unwrap();
    git_t(&dir, &["commit", "-q", "-am", "edit"]);
    assert_ne!(tree_hash(&ctx, &dir).unwrap(), tree1);
}

#[test]
fn require_clean_refuses_uncommitted_and_untracked_files() {
    let ctx = Ctx::background();
    let dir = new_repo("clean");
    require_clean(&ctx, &dir).unwrap();
    fs::write(format!("{dir}/new.txt"), "x").unwrap();
    let e = require_clean(&ctx, &dir).unwrap_err();
    assert_eq!(e, "the working tree has uncommitted or untracked files, so a pass would not describe HEAD. Commit or remove them first:\n?? new.txt");
    fs::remove_file(format!("{dir}/new.txt")).unwrap();
    fs::write(format!("{dir}/a.txt"), "changed\n").unwrap();
    assert!(require_clean(&ctx, &dir).is_err());
    let e = git(&ctx, "/no/such/dir", &["status"]).unwrap_err();
    assert_eq!(
        e,
        "git status: chdir /no/such/dir: no such file or directory: "
    );
}

#[test]
fn key_startup_cases() {
    let write = |dir: &str, c: &str| fs::write(format!("{dir}/user.bazelrc"), c).unwrap();
    const KEY: &str = "common --remote_header=x-buildbuddy-api-key=SECRET\n";
    let ws = tmp("ks-ws");
    let main = tmp("ks-main");
    let (ws, main) = (ws.to_str().unwrap(), main.to_str().unwrap());
    assert!(key_startup(ws, main)
        .unwrap_err()
        .contains("no BuildBuddy key"));
    write(main, KEY);
    assert_eq!(
        key_startup(ws, main).unwrap(),
        vec![format!("--bazelrc={main}/user.bazelrc")]
    );
    assert_eq!(key_startup(main, main).unwrap(), Vec::<String>::new());
    write(ws, KEY);
    assert_eq!(key_startup(ws, main).unwrap(), Vec::<String>::new());
}

fn unit(name: &str, runner: &str) -> Unit {
    Unit {
        name: name.into(),
        runner: runner.into(),
        ..Unit::default()
    }
}

#[test]
fn classify_mirrors_how_ci_runs_each_unit() {
    let mut units = HashMap::new();
    units.insert(
        "linux".into(),
        Unit {
            test_targets: s(&["//a:t"]),
            ..unit("linux", "ubuntu-26.04")
        },
    );
    units.insert("mac".into(), unit("mac", "xcode-27"));
    units.insert("macos".into(), unit("macos", "macos-15"));
    units.insert(
        "emulator".into(),
        Unit {
            needs_emulator: true,
            ..unit("emulator", "ubuntu-26.04")
        },
    );
    units.insert(
        "files".into(),
        Unit {
            artifacts: [("apk".to_string(), "x.apk".to_string())]
                .into_iter()
                .collect(),
            ..unit("files", "ubuntu-26.04")
        },
    );
    units.insert("linux2".into(), unit("linux2", "ubuntu-26.04"));
    let picked: Vec<PlanEntry> = ["mac", "linux2", "emulator", "linux", "files", "macos"]
        .iter()
        .map(|n| PlanEntry {
            name: n.to_string(),
            runner: String::new(),
        })
        .collect();
    let (covered, left) = classify(&picked, &units).unwrap();
    assert_eq!(
        covered.iter().map(|u| u.name.as_str()).collect::<Vec<_>>(),
        ["linux", "linux2"]
    );
    for n in ["mac", "macos", "emulator", "files"] {
        assert!(!left[n].is_empty(), "{n}");
    }
    let e = classify(
        &[PlanEntry {
            name: "ghost".into(),
            runner: String::new(),
        }],
        &units,
    )
    .unwrap_err();
    assert_eq!(
        e,
        "the planner picked unit \"ghost\", but no pipeline_unit by that name was found"
    );
}

#[derive(Default, Clone)]
struct Fake {
    plan: PlanResult,
    plan_err: Option<String>,
    build_test: i32,
    unit_rc: HashMap<String, i32>,
    invs: Vec<Invocation>,
    record_err: Option<String>,
}

struct Outcome {
    rc: i32,
    out: String,
    recorded: Vec<Record>,
    ran_units: Vec<String>,
}

#[derive(Clone)]
struct Buf(Rc<RefCell<Vec<u8>>>);

impl std::io::Write for Buf {
    fn write(&mut self, b: &[u8]) -> std::io::Result<usize> {
        self.0.borrow_mut().extend_from_slice(b);
        Ok(b.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn drive(f: &Fake, with_record: bool) -> Outcome {
    let buf = Buf(Rc::new(RefCell::new(Vec::new())));
    let recorded = Rc::new(RefCell::new(Vec::new()));
    let ran = Rc::new(RefCell::new(Vec::new()));
    let mut units = HashMap::new();
    units.insert(
        "api".into(),
        Unit {
            test_targets: s(&["//api:test"]),
            ..unit("api", "ubuntu-26.04")
        },
    );
    units.insert(
        "mac".into(),
        Unit {
            test_targets: s(&["//mac:test"]),
            ..unit("mac", "xcode-27")
        },
    );
    let rc = {
        let ran2 = ran.clone();
        let rec2 = recorded.clone();
        let mut v = Verifier {
            out: Box::new(buf.clone()),
            head: "a".repeat(40),
            tree: "b".repeat(40),
            base: "c".repeat(40),
            units,
            plan: Box::new(|| match &f.plan_err {
                Some(e) => Err(e.clone()),
                None => Ok(f.plan.clone()),
            }),
            run_build_test: Box::new(|| (f.build_test, None)),
            run_unit: Box::new(move |u: &Unit| {
                ran2.borrow_mut().push(u.name.clone());
                (*f.unit_rc.get(&u.name).unwrap_or(&0), None)
            }),
            invocations: Box::new(|| Ok(f.invs.clone())),
            record: None,
        };
        if with_record {
            v.record = Some(Box::new(move |r: &Record| {
                rec2.borrow_mut().push(r.clone());
                match &f.record_err {
                    Some(e) => Err(e.clone()),
                    None => Ok(()),
                }
            }));
        }
        v.run()
    };
    let out = String::from_utf8(buf.0.borrow().clone()).unwrap();
    let recorded = recorded.borrow().clone();
    let ran_units = ran.borrow().clone();
    Outcome {
        rc,
        out,
        recorded,
        ran_units,
    }
}

fn remote_inv(lane: &str, target: &str) -> Invocation {
    Invocation {
        lane: lane.into(),
        command: "test".into(),
        targets: Some(s(&[target])),
        url: format!("https://app.buildbuddy.io/invocation/{lane}"),
        saw_summary: true,
        processes: "3 remote, 4 internal".into(),
        ..Invocation::default()
    }
}

fn entries(names: &[&str]) -> Vec<PlanEntry> {
    names
        .iter()
        .map(|n| PlanEntry {
            name: n.to_string(),
            runner: String::new(),
        })
        .collect()
}

#[test]
fn run_records_a_pass_that_ran_remotely() {
    let f = Fake {
        plan: PlanResult {
            changed_files: s(&["api/x.go"]),
            matrix: entries(&["api", "mac"]),
            ..PlanResult::default()
        },
        invs: vec![
            remote_inv("build-test", "//api:lib_test"),
            remote_inv("unit:api", "//api:test"),
        ],
        ..Fake::default()
    };
    let o = drive(&f, true);
    assert_eq!(o.rc, EXIT_VERIFIED, "{}", o.out);
    assert_eq!(o.ran_units, s(&["api"]));
    assert_eq!(o.recorded.len(), 1);
    let r = &o.recorded[0];
    assert_eq!(
        (r.tree.clone(), r.head.clone(), r.base.clone()),
        ("b".repeat(40), "a".repeat(40), "c".repeat(40))
    );
    assert_eq!(r.lanes, s(&["build-test", "unit:api"]));
    let digest = plan_digest(&f.invs);
    assert_eq!(
        o.out,
        format!(
            "verified-run: commit aaaaaaaaaaaa, files (tree) {b}\nCompared with cccccccccccc, the merge base with origin/main.\n\n1 changed file(s). What runs here, and why:\n  - build-test: the affected targets, chosen by tools/ci/affected-targets.sh exactly as on a PR.\n  - unit api: picked by the planner; 1 target(s).\nLeft to CI (not covered by this record):\n  - unit mac: runs on a macOS runner; the remote machines are Linux\nAlso left to CI: the fast checks and every other CI job (macOS build, race tests, lint, ...).\n\n\nPASSED on the remote machines: 2 Bazel run(s), lanes build-test, unit:api.\nBuild results: https://app.buildbuddy.io/history/commit/{a}\nRecord: context \"verified-run\", tree={b} base=cccccccccccc plan={d}\nRecorded on commit aaaaaaaaaaaa.\n",
            a = "a".repeat(40),
            b = "b".repeat(40),
            d = &digest[..12]
        )
    );
}

#[test]
fn run_never_records_a_failure() {
    let api = || entries(&["api"]);
    let mut on_mac = remote_inv("build-test", "//x:t");
    on_mac.processes = "2 darwin-sandbox".into();
    let mut no_link = remote_inv("build-test", "//x:t");
    no_link.url = String::new();
    let mut failed = remote_inv("build-test", "//x:t");
    failed.exit = 1;
    let cases: Vec<(&str, Fake, &str)> = vec![
        ("build-test failed", Fake { plan: PlanResult { matrix: api(), ..Default::default() }, build_test: 3, invs: vec![remote_inv("build-test", "//x:t")], ..Default::default() }, "build-test did not pass (exit 3)."),
        ("a unit failed", Fake { plan: PlanResult { matrix: api(), ..Default::default() }, unit_rc: [("api".to_string(), 3)].into_iter().collect(), invs: vec![remote_inv("unit:api", "//api:test")], ..Default::default() }, "unit api did not pass (exit 3)."),
        ("the planner failed", Fake { plan_err: Some("query timed out".into()), ..Default::default() }, "the planner failed: query timed out"),
        ("the plan is degraded", Fake { plan: PlanResult { is_degraded: true, sweep_reason: "query failed".into(), ..Default::default() }, ..Default::default() }, "the planner could not work out what changed (query failed). CI would run everything; fix the cause first."),
        ("unknown unit", Fake { plan: PlanResult { matrix: entries(&["ghost"]), ..Default::default() }, ..Default::default() }, "the planner picked unit \"ghost\""),
        ("work ran on the Mac", Fake { invs: vec![on_mac], ..Default::default() }, "bazel test (build-test) ran 2 process(es) on this machine (\"darwin-sandbox\"), not on the remote machines."),
        ("no link", Fake { invs: vec![no_link], ..Default::default() }, "bazel test (build-test) has no BuildBuddy link, so there is no proof of where it ran."),
        ("a logged run failed", Fake { invs: vec![failed], ..Default::default() }, "bazel test (build-test) failed with exit code 1."),
    ];
    for (name, f, why) in cases {
        let o = drive(&f, true);
        assert_eq!(o.rc, EXIT_NOT_VERIFIED, "{name}: {}", o.out);
        assert!(o.recorded.is_empty(), "{name}");
        assert!(
            o.out.contains(&format!("\nNOT VERIFIED: {why}"))
                && o.out.ends_with("Nothing was recorded.\n"),
            "{name}: {}",
            o.out
        );
    }
}

#[test]
fn run_says_plainly_when_the_recorder_is_missing() {
    let f = Fake {
        invs: vec![remote_inv("build-test", "//x:t")],
        record_err: Some(record::err_no_recorder()),
        ..Default::default()
    };
    let o = drive(&f, true);
    assert_eq!(o.rc, EXIT_NOT_RECORDED);
    assert!(o.out.contains("The tests passed, but: not recorded: tools/pipeline/verifiedrun/recorder.tsv names no recorder"), "{}", o.out);
}

#[test]
fn run_with_no_record_and_nothing_to_run() {
    let f = Fake {
        invs: vec![remote_inv("build-test", "//x:t")],
        ..Default::default()
    };
    let o = drive(&f, false);
    assert!(
        o.rc == EXIT_VERIFIED && o.out.contains("Not recorded (--no-record)"),
        "{}",
        o.out
    );
    let o = drive(&Fake::default(), true);
    assert!(
        o.rc == EXIT_VERIFIED && o.recorded.is_empty() && o.out.contains("nothing to record"),
        "{}",
        o.out
    );
}

#[test]
fn strict_flags_tie_the_run_to_the_code() {
    let flags = strict_flags("HEADSHA", "TREESHA").join(" ");
    for want in [
        "--config=remote",
        "--spawn_strategy=remote",
        "--noremote_local_fallback",
        "--noremote_upload_local_results",
        "--disk_cache=",
        "--nocache_test_results",
        "--platforms=//tools/platforms:linux_x86_64",
        "--host_platform=//tools/platforms:linux_x86_64",
        "--extra_execution_platforms=//tools/platforms:linux_x86_64",
        "--build_metadata=COMMIT_SHA=HEADSHA",
        "--build_metadata=TREE_SHA=TREESHA",
        "--build_metadata=REPO_URL=https://github.com/VitruvianSoftware/vitruvian-core",
    ] {
        assert!(flags.contains(want), "missing {want}");
    }
}

#[test]
fn decode_plan_reads_like_go() {
    let p = decode_plan(br#"{"is_degraded":false,"changed_files":["a"],"matrix":[{"name":"x","runner":"r","extra":1}],"other":2}"#).unwrap();
    assert_eq!(
        p.matrix,
        vec![PlanEntry {
            name: "x".into(),
            runner: "r".into()
        }]
    );
    assert_eq!(
        decode_plan(br#"{"matrix":[{"name":5}]}"#).unwrap_err(),
        "json: cannot unmarshal number into Go struct field planEntry.matrix.name of type string"
    );
    assert_eq!(
        decode_plan(br#"{"matrix":["x"]}"#).unwrap_err(),
        "json: cannot unmarshal string into Go struct field planResult.matrix of type main.planEntry"
    );
    assert_eq!(
        decode_plan(b"").unwrap_err(),
        "unexpected end of JSON input"
    );
}

// ---- record_test.go ---------------------------------------------------------

fn inv_lt(lane: &str, targets: &[&str]) -> Invocation {
    Invocation {
        lane: lane.into(),
        targets: Some(s(targets)),
        ..Invocation::default()
    }
}

#[test]
fn plan_digest_ignores_order_but_not_content() {
    let a = vec![
        inv_lt("build-test", &["//a:t", "//b:t"]),
        inv_lt("unit:x", &["//x:t"]),
    ];
    let b = vec![
        inv_lt("unit:x", &["//x:t"]),
        inv_lt("build-test", &["//b:t", "//a:t"]),
        inv_lt("build-test", &["//a:t"]),
    ];
    assert_eq!(plan_digest(&a), plan_digest(&b));
    let c = vec![
        inv_lt("build-test", &["//a:t"]),
        inv_lt("unit:x", &["//x:t"]),
    ];
    assert_ne!(plan_digest(&a), plan_digest(&c));
    let d = vec![
        inv_lt("unit:y", &["//a:t", "//b:t"]),
        inv_lt("unit:x", &["//x:t"]),
    ];
    assert_ne!(plan_digest(&a), plan_digest(&d));
    // The digest is sha256 of the sorted "lane\ttarget" lines.
    assert_eq!(
        plan_digest(&[inv_lt("l", &["t"])]),
        "11407b3278c8f71b9f7e3247643d6c0805cdb9679e7c764de58e38a7750f6a9e"
    );
}

#[test]
fn record_description_fits_github_limit() {
    let mut i1 = Invocation {
        lane: "build-test".into(),
        url: "u1".into(),
        ..Default::default()
    };
    let i2 = Invocation {
        lane: "unit:x".into(),
        url: "u2".into(),
        ..Default::default()
    };
    let r = new_record(
        &"a".repeat(40),
        &"b".repeat(40),
        &"c".repeat(40),
        &[i1.clone(), i2],
    );
    let d = r.description();
    assert!(d.len() <= 140, "{d}");
    assert!(d.contains(&format!("tree={}", "b".repeat(40))));
    assert_eq!(
        r.target_url,
        format!(
            "https://app.buildbuddy.io/history/commit/{}",
            "a".repeat(40)
        )
    );
    i1.lane = String::new();
    let one = new_record("h", "t", "b", &[i1.clone(), i1]);
    assert_eq!(one.target_url, "u1");
}

const TEST_AGENTS: &str = "# agent\tapp\tinst\tbot\nscout\t4521103\t152054588\t314429511\nwren\t4521094\t152054411\t314429222\n";

fn write_files(tag: &str, recorder: &str) -> (String, String, String) {
    let d = tmp(tag);
    let (rp, ap, kd) = (d.join("recorder.tsv"), d.join("agents.tsv"), d.join("keys"));
    fs::write(&rp, recorder).unwrap();
    fs::write(&ap, TEST_AGENTS).unwrap();
    fs::create_dir_all(&kd).unwrap();
    (
        rp.to_str().unwrap().into(),
        ap.to_str().unwrap().into(),
        kd.to_str().unwrap().into(),
    )
}

#[test]
fn committed_recorder_is_scout() {
    let (_, ap, _) = write_files("scout", "");
    let rec = ["recorder.tsv", "tools/pipeline/verifiedrun/recorder.tsv"]
        .into_iter()
        .find(|p| std::path::Path::new(p).exists())
        .expect("recorder.tsv in the runfiles");
    let cfg = load_recorder(rec, &ap).unwrap();
    assert_eq!(
        cfg,
        RecorderConfig {
            agent: "scout".into(),
            app_id: "4521103".into(),
            installation_id: "152054588".into(),
            bot_user_id: "314429511".into()
        }
    );
}

#[test]
fn load_recorder_refusals() {
    for (i, (content, want)) in [
        ("# only comments\n", "names no recorder"),
        ("scout\t314429511\nwren\t314429222\n", "exactly one"),
        ("scout\n", "one line"),
        ("scout\tabc\n", "one line"),
        ("scout\t1\n", "agents.tsv says 314429511"),
        ("ghost\t314429511\n", "not in tools/agent-app/agents.tsv"),
        ("Scout\t314429511\n", "one line"),
    ]
    .iter()
    .enumerate()
    {
        let (rp, ap, _) = write_files(&format!("refuse{i}"), content);
        let e = load_recorder(&rp, &ap).unwrap_err();
        assert!(e.contains(want), "{content:?}: {e}");
    }
    let e = load_recorder("/no/such/recorder.tsv", "/x").unwrap_err();
    assert_eq!(e, "not recorded: cannot read tools/pipeline/verifiedrun/recorder.tsv: open /no/such/recorder.tsv: no such file or directory");
}

#[test]
fn record_refuses_without_the_key() {
    let (rp, ap, kd) = write_files("nokey", "scout\t314429511\n");
    let minted = std::cell::Cell::new(false);
    let rec = StatusRecorder {
        config_path: rp,
        agents_path: ap,
        key_dir: kd.clone(),
        mint: Box::new(|_, _| {
            minted.set(true);
            Ok("tok".into())
        }),
        api_base: String::new(),
    };
    let e = rec
        .record(&Record {
            head: "h".into(),
            ..Default::default()
        })
        .unwrap_err();
    assert!(
        e.contains(&format!("private key is not at {kd}/scout.pem")),
        "{e}"
    );
    assert!(!minted.get());
}

/// The request a test server saw: request line, headers, body.
type Seen = Arc<Mutex<Option<(String, Vec<String>, String)>>>;

/// A one-request HTTP server: answers with (status, body) and hands back
/// the request it saw (request line, headers, body).
fn serve_once(status: u16, body: &'static str) -> (String, Seen) {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = l.local_addr().unwrap();
    let seen = Arc::new(Mutex::new(None));
    let seen2 = seen.clone();
    std::thread::spawn(move || {
        let (mut sock, _) = l.accept().unwrap();
        let mut r = BufReader::new(sock.try_clone().unwrap());
        let mut line = String::new();
        r.read_line(&mut line).unwrap();
        let mut headers = Vec::new();
        let mut len = 0usize;
        loop {
            let mut h = String::new();
            r.read_line(&mut h).unwrap();
            let h = h.trim_end().to_string();
            if h.is_empty() {
                break;
            }
            if let Some(v) = h.to_ascii_lowercase().strip_prefix("content-length:") {
                len = v.trim().parse().unwrap();
            }
            headers.push(h);
        }
        let mut b = vec![0u8; len];
        r.read_exact(&mut b).unwrap();
        *seen2.lock().unwrap() = Some((
            line.trim_end().to_string(),
            headers,
            String::from_utf8(b).unwrap(),
        ));
        let resp = format!(
            "HTTP/1.1 {status} X\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        sock.write_all(resp.as_bytes()).unwrap();
    });
    (format!("http://{addr}"), seen)
}

fn recorder_against(tag: &str, api: String) -> (StatusRecorder<'static>, String) {
    let (rp, ap, kd) = write_files(tag, "scout\t314429511\n");
    fs::write(format!("{kd}/scout.pem"), "fake").unwrap();
    let want_key = format!("{kd}/scout.pem");
    (
        StatusRecorder {
            config_path: rp,
            agents_path: ap,
            key_dir: kd,
            mint: Box::new(move |cfg, key| {
                assert_eq!(key, want_key);
                assert_eq!(
                    (cfg.app_id.as_str(), cfg.installation_id.as_str()),
                    ("4521103", "152054588")
                );
                Ok("recorder-token".into())
            }),
            api_base: api,
        },
        String::new(),
    )
}

#[test]
fn record_posts_the_status_with_the_recorder_token_only() {
    let (api, seen) = serve_once(
        201,
        r#"{"state":"success","creator":{"login":"vitruvian-scout-agent[bot]","id":314429511}}"#,
    );
    let (rec, _) = recorder_against("post", api);
    let r = Record {
        head: "a".repeat(40),
        tree: "b".repeat(40),
        base: "c".repeat(40),
        plan: "d".repeat(64),
        target_url: "https://app.buildbuddy.io/invocation/x".into(),
        ..Default::default()
    };
    rec.record(&r).unwrap();
    let (line, headers, body) = seen.lock().unwrap().clone().unwrap();
    assert_eq!(
        line,
        format!(
            "POST /repos/VitruvianSoftware/vitruvian-core/statuses/{} HTTP/1.1",
            r.head
        )
    );
    assert!(
        headers.contains(&"Authorization: Bearer recorder-token".to_string()),
        "{headers:?}"
    );
    assert!(headers.contains(&"X-GitHub-Api-Version: 2022-11-28".to_string()));
    assert_eq!(
        body,
        format!(
            r#"{{"context":"verified-run","description":"{}","state":"success","target_url":"https://app.buildbuddy.io/invocation/x"}}"#,
            r.description()
        )
    );
}

#[test]
fn record_distrusts_a_status_set_by_someone_else() {
    let (api, _) = serve_once(201, r#"{"creator":{"login":"ipv1337","id":42}}"#);
    let (rec, _) = recorder_against("other", api);
    let e = rec
        .record(&Record {
            head: "h".into(),
            ..Default::default()
        })
        .unwrap_err();
    assert_eq!(e, "the status was written, but GitHub says it was set by \"ipv1337\" (id 42), not the recorder scout (id 314429511). Do not trust it");
}

#[test]
fn record_reports_github_refusal() {
    let (api, _) = serve_once(422, "{\"message\":\"No commit found for SHA\"}\n");
    let (rec, _) = recorder_against("refusal", api);
    let e = rec
        .record(&Record {
            head: "h".into(),
            ..Default::default()
        })
        .unwrap_err();
    assert_eq!(e, "not recorded: GitHub answered 422 (has this commit been pushed?): {\"message\":\"No commit found for SHA\"}");
}

#[test]
fn without_github_tokens_drops_only_tokens() {
    let got = without_github_tokens(s(&[
        "GH_TOKEN=a",
        "GITHUB_TOKEN=b",
        "PATH=/bin",
        "GH_TOKENISH=c",
        "GH_ENTERPRISE_TOKEN=d",
    ]));
    assert_eq!(got, s(&["PATH=/bin", "GH_TOKENISH=c"]));
}

// ---- shim_test.go -----------------------------------------------------------

#[test]
fn shim_args_put_strict_flags_last_and_drop_key_headers() {
    let (got, cmd, targets) = shim_args(
        &s(&[
            "test",
            "--config=remote",
            "--remote_header=x-buildbuddy-api-key=SECRET",
            "--bes_header=x-buildbuddy-api-key=SECRET",
            "--spawn_strategy=local",
            "//a:t",
            "//b/...",
        ]),
        &s(&["--bazelrc=/main/user.bazelrc"]),
        &s(&["--config=remote", "--spawn_strategy=remote"]),
    );
    assert_eq!(
        got,
        s(&[
            "--bazelrc=/main/user.bazelrc",
            "test",
            "--config=remote",
            "--spawn_strategy=local",
            "//a:t",
            "//b/...",
            "--spawn_strategy=remote"
        ])
    );
    assert_eq!(
        (cmd.as_str(), targets),
        ("test", Some(s(&["//a:t", "//b/..."])))
    );
}

#[test]
fn shim_args_other_shapes() {
    let (got, _, t) = shim_args(&s(&["test", "//a:t"]), &[], &s(&["--config=remote", "--S"]));
    assert_eq!(got, s(&["test", "//a:t", "--config=remote", "--S"]));
    assert_eq!(t, Some(s(&["//a:t"])));
    let (got, _, t) = shim_args(
        &s(&["build", "--keep_going", "--", "-//a:excluded", "//b:x"]),
        &[],
        &s(&["--S"]),
    );
    assert_eq!(
        got,
        s(&[
            "build",
            "--keep_going",
            "--S",
            "--",
            "-//a:excluded",
            "//b:x"
        ])
    );
    assert_eq!(t, Some(s(&["-//a:excluded", "//b:x"])));
    let (got, cmd, t) = shim_args(
        &s(&["query", "attr(tags, pipeline, //...)", "--output=label"]),
        &s(&["--bazelrc=x"]),
        &s(&["--S"]),
    );
    assert_eq!(
        (got, cmd.as_str(), t),
        (
            s(&[
                "--bazelrc=x",
                "query",
                "attr(tags, pipeline, //...)",
                "--output=label"
            ]),
            "query",
            None
        )
    );
    let (got, cmd, _) = shim_args(
        &s(&["--nohome_rc", "test", "//a:t"]),
        &s(&["--bazelrc=x"]),
        &s(&["--S"]),
    );
    assert_eq!(
        (got, cmd.as_str()),
        (
            s(&["--bazelrc=x", "--nohome_rc", "test", "//a:t", "--S"]),
            "test"
        )
    );
    let (got, cmd, t) = shim_args(&s(&["--version"]), &[], &s(&["--S"]));
    assert_eq!((got, cmd.as_str(), t), (s(&["--version"]), "", None));
    let (_, _, t) = shim_args(&s(&["test", "--x"]), &[], &[]);
    assert_eq!(t, None);
}

#[test]
fn scan_line_reads_link_and_summary() {
    let mut inv = Invocation::default();
    for l in [
        "INFO: Invocation ID: 5a8aa3be",
        "\x1b[32mINFO: \x1b[0mStreaming build results to: https://app.buildbuddy.io/invocation/5a8aa3be-9a5d\r",
        "INFO: 12 processes: 3 remote cache hit, 5 internal, 4 remote.",
    ] {
        scan_line(l, &mut inv);
    }
    assert_eq!(
        inv.url,
        "https://app.buildbuddy.io/invocation/5a8aa3be-9a5d"
    );
    assert!(inv.saw_summary);
    assert_eq!(inv.processes, "3 remote cache hit, 5 internal, 4 remote");
    let mut zero = Invocation::default();
    scan_line("INFO: 0 processes.", &mut zero);
    assert!(zero.saw_summary && zero.processes.is_empty());
    let mut one = Invocation::default();
    scan_line("INFO: 1 process: 1 internal.  ", &mut one);
    assert_eq!(one.processes, "1 internal");
    let mut none = Invocation::default();
    scan_line("INFO: 2 processes running", &mut none);
    scan_line("Streaming build results to: https:// x", &mut none);
    assert!(!none.saw_summary && none.url.is_empty());
}

#[test]
fn check_invocation_cases() {
    let ok = Invocation {
        lane: "build-test".into(),
        command: "test".into(),
        url: "https://app.buildbuddy.io/invocation/x".into(),
        saw_summary: true,
        ..Default::default()
    };
    type Mutate = Box<dyn Fn(&mut Invocation)>;
    let cases: Vec<(&str, Mutate, &str)> = vec![
        (
            "remote only",
            Box::new(|i| i.processes = "2 remote, 6 internal, 1 remote cache hit".into()),
            "",
        ),
        ("nothing ran", Box::new(|i| i.processes = String::new()), ""),
        (
            "action cache",
            Box::new(|i| i.processes = "4 action cache hit, 1 remote".into()),
            "",
        ),
        (
            "ran on the Mac",
            Box::new(|i| i.processes = "1 darwin-sandbox, 2 remote".into()),
            "on this machine",
        ),
        (
            "local",
            Box::new(|i| i.processes = "1 local".into()),
            "on this machine",
        ),
        (
            "worker",
            Box::new(|i| i.processes = "3 worker".into()),
            "on this machine",
        ),
        (
            "disk cache",
            Box::new(|i| i.processes = "1 disk cache hit".into()),
            "on this machine",
        ),
        (
            "unreadable",
            Box::new(|i| i.processes = "lots".into()),
            "could not read \"lots\"",
        ),
        (
            "failed",
            Box::new(|i| i.exit = 3),
            "failed with exit code 3",
        ),
        (
            "no link",
            Box::new(|i| i.url = String::new()),
            "no BuildBuddy link",
        ),
        (
            "no summary",
            Box::new(|i| i.saw_summary = false),
            "did not report",
        ),
        (
            "no test targets",
            Box::new(|i| {
                i.exit = 4;
                i.saw_summary = false;
            }),
            "",
        ),
        (
            "no lane",
            Box::new(|i| {
                i.lane = String::new();
                i.exit = 9;
            }),
            "bazel test (no lane) failed",
        ),
    ];
    for (name, m, want) in cases {
        let mut inv = ok.clone();
        m(&mut inv);
        let r = check_invocation(&inv);
        if want.is_empty() {
            assert!(r.is_ok(), "{name}: {r:?}");
        } else {
            assert!(
                r.as_ref().err().map(|e| e.contains(want)).unwrap_or(false),
                "{name}: {r:?}"
            );
        }
    }
}

#[test]
fn read_invocations_round_trip() {
    let d = tmp("log");
    let p = d.join("log.jsonl");
    let ps = p.to_str().unwrap();
    assert_eq!(read_invocations(ps).unwrap(), None);
    fs::write(&p, "{\"lane\":\"a\",\"command\":\"test\",\"targets\":[\"//x\"],\"exit\":0}\n{\"lane\":\"b\",\"command\":\"build\"}\n").unwrap();
    let invs = read_invocations(ps).unwrap().unwrap();
    assert_eq!(invs.len(), 2);
    assert_eq!(invs[0].targets, Some(s(&["//x"])));
    assert_eq!(invs[1].lane, "b");
    fs::write(&p, "{not json").unwrap();
    assert_eq!(read_invocations(ps).unwrap_err(), "the run log is unreadable: invalid character 'n' looking for beginning of object key string");
    fs::write(&p, "{\"lane\":\"a\"").unwrap();
    assert_eq!(
        read_invocations(ps).unwrap_err(),
        "the run log is unreadable: unexpected EOF"
    );
    // The shim's own line round-trips.
    let inv = remote_inv("unit:a<b>", "//x:t");
    let line = unitfile::gocompat::json::marshal(&inv);
    assert!(line.contains("unit:a\\u003cb\\u003e"), "{line}");
    fs::write(&p, line + "\n").unwrap();
    assert_eq!(read_invocations(ps).unwrap().unwrap(), vec![inv]);
}
