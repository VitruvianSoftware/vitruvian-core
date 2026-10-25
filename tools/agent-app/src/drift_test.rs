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

//! permission_drift_test.py's cases, on the port: a fake GitHub that
//! answers by path, and an unknown path is a 404.

use crate::drift::{self, Agent, Declared, LoadFail};
use crate::github::{Api, ReadFail};
use crate::json::{loads, Value};

const BASE: &str = r#"{"checks": "read", "contents": "write", "metadata": "read", "pull_requests": "write", "workflows": "write"}"#;

fn base() -> Value {
    loads(BASE).unwrap()
}

fn with(v: &Value, key: &str, val: &str) -> Value {
    let mut items = match v {
        Value::Obj(i) => i.clone(),
        _ => unreachable!(),
    };
    items.retain(|(k, _)| k != key);
    items.push((key.into(), Value::Str(val.into())));
    Value::Obj(items)
}

fn without(v: &Value, key: &str) -> Value {
    match v {
        Value::Obj(i) => Value::Obj(i.iter().filter(|(k, _)| k != key).cloned().collect()),
        _ => unreachable!(),
    }
}

fn agents() -> Vec<Agent> {
    vec![
        Agent::new("beacon", 101, 1001),
        Agent::new("wren", 104, 1004),
    ]
}

fn perms(v: &Value) -> drift::Perms {
    match v {
        Value::Obj(items) => items.iter().map(|(k, v)| (k.clone(), v.py_str())).collect(),
        _ => unreachable!(),
    }
}

fn declared(beacon: Option<Value>) -> Declared {
    vec![
        ("beacon".into(), perms(&beacon.unwrap_or_else(base))),
        ("wren".into(), perms(&with(&base(), "actions", "write"))),
    ]
}

fn installation(name: &str, app_id: i64, inst_id: i64, perms: Value, slug: Option<&str>) -> Value {
    let slug = slug
        .map(String::from)
        .unwrap_or(format!("vitruvian-{}-agent", name));
    Value::Obj(vec![
        ("id".into(), Value::Int(inst_id.to_string())),
        ("app_id".into(), Value::Int(app_id.to_string())),
        ("app_slug".into(), Value::Str(slug)),
        ("permissions".into(), perms),
    ])
}

fn live(beacon: Option<Value>, wren: Option<Value>, extra: Vec<Value>) -> Vec<Value> {
    let mut out = vec![
        installation("beacon", 101, 1001, beacon.unwrap_or_else(base), None),
        installation(
            "wren",
            104,
            1004,
            wren.unwrap_or_else(|| with(&base(), "actions", "write")),
            None,
        ),
        installation(
            "sonarqubecloud",
            9,
            9,
            loads(r#"{"checks": "write"}"#).unwrap(),
            Some("sonarqubecloud"),
        ),
    ];
    out.extend(extra);
    out
}

fn set(v: &mut Value, key: &str, val: Value) {
    if let Value::Obj(items) = v {
        items.retain(|(k, _)| k != key);
        items.push((key.into(), val));
    }
}

#[derive(Default)]
struct Fake {
    installations: Vec<Value>,
    requested: Vec<(String, Value)>,
    errors: Vec<(String, ReadFail)>,
    /// Answers for /apps/ name a different App.
    wrong_id: bool,
    /// total_count says one more than the page holds.
    short: bool,
}

impl Fake {
    fn new(installations: Vec<Value>) -> Fake {
        Fake {
            installations,
            ..Default::default()
        }
    }
}

impl Api for Fake {
    fn get(&mut self, path: &str) -> Result<(Value, Option<String>), ReadFail> {
        for (prefix, err) in &self.errors {
            if path.starts_with(prefix.as_str()) {
                return Err(match err {
                    ReadFail::Read(m) => ReadFail::Read(m.clone()),
                    ReadFail::Crash(c) => ReadFail::Crash(c.clone()),
                });
            }
        }
        if path.starts_with("/orgs/VitruvianSoftware/installations") {
            let n = self.installations.len() + usize::from(self.short);
            return Ok((
                Value::Obj(vec![
                    ("total_count".into(), Value::Int(n.to_string())),
                    (
                        "installations".into(),
                        Value::Arr(self.installations.clone()),
                    ),
                ]),
                None,
            ));
        }
        if let Some(slug) = path.strip_prefix("/apps/") {
            for inst in &self.installations {
                if inst.get("app_slug") == Some(&Value::Str(slug.into())) {
                    let perms = self
                        .requested
                        .iter()
                        .find(|(s, _)| s == slug)
                        .map(|(_, p)| p.clone())
                        .unwrap_or_else(|| inst.get("permissions").unwrap().clone());
                    let id = if self.wrong_id {
                        Value::Int("1".into())
                    } else {
                        inst.get("app_id").unwrap().clone()
                    };
                    return Ok((
                        Value::Obj(vec![
                            ("id".into(), id),
                            ("slug".into(), Value::Str(slug.into())),
                            ("permissions".into(), perms),
                        ]),
                        None,
                    ));
                }
            }
        }
        Err(ReadFail::Read(format!("GET {}: HTTP 404 Not Found", path)))
    }
}

fn run(fake: &mut Fake, decl: Option<Declared>) -> (i32, String) {
    let (code, lines) = drift::check(
        &agents(),
        &decl.unwrap_or_else(|| declared(None)),
        fake,
        "VitruvianSoftware",
    )
    .unwrap();
    (code, lines.join("\n"))
}

fn line_for(report: &str, name: &str) -> String {
    report
        .lines()
        .find(|l| format!("{} ", l).contains(&format!(" {} ", name)))
        .unwrap_or_else(|| panic!("no line for {} in\n{}", name, report))
        .to_string()
}

#[test]
fn match_passes() {
    let (code, report) = run(&mut Fake::new(live(None, None, vec![])), None);
    assert_eq!(code, 0, "{}", report);
    assert!(report.contains("2 Apps: 2 ok."), "{}", report);
    assert!(line_for(&report, "wren").contains("actions=write"));
}

#[test]
fn extra_permission_on_github_fails_naming_app_and_permission() {
    let (code, report) = run(
        &mut Fake::new(live(Some(with(&base(), "actions", "write")), None, vec![])),
        None,
    );
    assert_eq!(code, 1, "{}", report);
    assert!(line_for(&report, "beacon").contains("DRIFT"));
    assert!(report.contains("GitHub grants actions=write; permissions.tsv does not"));
    assert!(line_for(&report, "wren").trim_start().starts_with("ok"));
}

#[test]
fn missing_permission_fails() {
    let (code, report) = run(
        &mut Fake::new(live(Some(without(&base(), "workflows")), None, vec![])),
        None,
    );
    assert_eq!(code, 1, "{}", report);
    assert!(line_for(&report, "beacon").contains("DRIFT"));
    assert!(report.contains("permissions.tsv declares workflows=write; GitHub does not"));
}

#[test]
fn different_level_fails() {
    let (code, report) = run(
        &mut Fake::new(live(None, Some(with(&base(), "actions", "read")), vec![])),
        None,
    );
    assert_eq!(code, 1, "{}", report);
    assert!(line_for(&report, "wren").contains("DRIFT"));
    assert!(report.contains("actions: permissions.tsv declares write, GitHub grants read"));
}

#[test]
fn pending_request_the_code_already_declares_is_pending() {
    let mut fake = Fake::new(live(None, None, vec![]));
    fake.requested = vec![(
        "vitruvian-beacon-agent".into(),
        with(&base(), "actions", "write"),
    )];
    let (code, report) = run(
        &mut fake,
        Some(declared(Some(with(&base(), "actions", "write")))),
    );
    assert_eq!(code, 1, "{}", report);
    assert!(line_for(&report, "beacon").contains("PENDING"));
    assert!(!report.contains("DRIFT"));
    assert!(report.contains("settings/installations/1001"));
    assert!(report.contains("the App's settings ask for actions=write; GitHub does not"));
}

#[test]
fn pending_request_the_code_does_not_declare_is_drift() {
    let mut fake = Fake::new(live(None, None, vec![]));
    fake.requested = vec![(
        "vitruvian-beacon-agent".into(),
        with(&base(), "issues", "write"),
    )];
    let (code, report) = run(&mut fake, None);
    assert_eq!(code, 1, "{}", report);
    assert!(line_for(&report, "beacon").contains("DRIFT"));
    assert!(report.contains("the App's settings ask for issues=write"));
    assert!(report.contains("org has not accepted"));
}

#[test]
fn app_listed_in_code_but_not_installed_fails() {
    let installs: Vec<Value> = live(None, None, vec![])
        .into_iter()
        .filter(|i| i.get("app_slug") != Some(&Value::Str("vitruvian-wren-agent".into())))
        .collect();
    let (code, report) = run(&mut Fake::new(installs), None);
    assert_eq!(code, 1, "{}", report);
    assert!(line_for(&report, "wren").contains("MISSING"));
    assert!(report.contains("installation 1004 is not on VitruvianSoftware"));
}

#[test]
fn no_installations_at_all_is_not_a_pass() {
    let (code, report) = run(&mut Fake::new(vec![]), None);
    assert_eq!(code, 1, "{}", report);
    assert!(report.contains("2 MISSING"));
}

#[test]
fn installation_id_of_another_app_fails() {
    let mut installs = live(None, None, vec![]);
    set(&mut installs[1], "app_id", Value::Int("999".into()));
    let (code, report) = run(&mut Fake::new(installs), None);
    assert_eq!(code, 1, "{}", report);
    assert!(report.contains("belongs to App 999"));
}

#[test]
fn suspended_installation_fails() {
    let mut installs = live(None, None, vec![]);
    set(
        &mut installs[0],
        "suspended_at",
        Value::Str("2026-10-01T00:00:00Z".into()),
    );
    let (code, report) = run(&mut Fake::new(installs), None);
    assert_eq!(code, 1, "{}", report);
    assert!(line_for(&report, "beacon").contains("suspended"));
}

#[test]
fn agent_app_installed_but_not_listed_fails() {
    let extra = vec![installation("newbie", 200, 2000, base(), None)];
    let (code, report) = run(&mut Fake::new(live(None, None, extra)), None);
    assert_eq!(code, 1, "{}", report);
    assert!(line_for(&report, "vitruvian-newbie-agent").contains("UNLISTED"));
}

#[test]
fn other_apps_on_the_org_are_ignored() {
    let (code, report) = run(&mut Fake::new(live(None, None, vec![])), None);
    assert_eq!(code, 0, "{}", report);
    assert!(!report.contains("sonarqubecloud"));
}

#[test]
fn ids_compare_as_python_numbers() {
    // GitHub sending 1001.0 or a float app id still names the same App.
    let mut installs = live(None, None, vec![]);
    set(&mut installs[0], "id", Value::Float(1001.0));
    set(&mut installs[0], "app_id", Value::Float(101.0));
    let (code, report) = run(&mut Fake::new(installs), None);
    assert_eq!(code, 0, "{}", report);
}

#[test]
fn a_403_on_installations_is_not_checked_for_every_app() {
    let mut fake = Fake::new(live(None, None, vec![]));
    fake.errors = vec![(
        "/orgs/".into(),
        ReadFail::Read(
            "GET /orgs/VitruvianSoftware/installations: HTTP 403 Resource not accessible by integration".into(),
        ),
    )];
    let (code, report) = run(&mut fake, None);
    assert_eq!(code, 2, "{}", report);
    assert!(!report.contains(" ok "));
    assert!(report.contains("2 NOT CHECKED"));
    assert!(report.contains("NOT a pass"));
    assert!(report.contains("org Administration read"));
}

#[test]
fn unreadable_app_settings_is_not_checked_even_if_the_grant_matches() {
    let mut fake = Fake::new(live(None, None, vec![]));
    fake.errors = vec![(
        "/apps/vitruvian-wren-agent".into(),
        ReadFail::Read("GET /apps/vitruvian-wren-agent: HTTP 500".into()),
    )];
    let (code, report) = run(&mut fake, None);
    assert_eq!(code, 2, "{}", report);
    assert!(line_for(&report, "wren").contains("NOT CHECKED"));
}

#[test]
fn apps_answer_for_a_different_app_is_not_trusted() {
    let mut fake = Fake::new(live(None, None, vec![]));
    fake.wrong_id = true;
    assert_eq!(run(&mut fake, None).0, 2);
}

#[test]
fn a_page_not_followed_is_not_checked() {
    let mut fake = Fake::new(live(None, None, vec![]));
    fake.short = true;
    let (code, report) = run(&mut fake, None);
    assert_eq!(code, 2, "{}", report);
    assert!(report.contains("counts 4 installations but 3 were read"));
}

#[test]
fn an_installation_that_is_not_a_dict_crashes_as_python_does() {
    let mut installs = live(None, None, vec![]);
    installs.push(Value::Str("x".into()));
    let err = drift::check(
        &agents(),
        &declared(None),
        &mut Fake::new(installs),
        "VitruvianSoftware",
    )
    .unwrap_err();
    assert_eq!(err.class, "AttributeError");
    assert_eq!(err.msg, "'str' object has no attribute 'get'");
}

// --- the committed files -------------------------------------------------

fn write(text: &[u8]) -> (std::path::PathBuf, String) {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static N: AtomicUsize = AtomicUsize::new(0);
    let dir = std::env::temp_dir().join(format!(
        "permission-drift-test-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("f.tsv");
    std::fs::write(&path, text).unwrap();
    let s = path.to_string_lossy().into_owned();
    (dir, s)
}

fn file_error(r: Result<Declared, LoadFail>) -> String {
    match r {
        Err(LoadFail::File(m)) => m,
        other => panic!("{:?}", other),
    }
}

#[test]
fn the_committed_files_are_consistent() {
    // Under bazel test the data files sit beside the test in its runfiles.
    let dir = std::env::var("TEST_SRCDIR")
        .map(|d| format!("{}/_main/tools/agent-app", d))
        .unwrap_or_else(|_| "tools/agent-app".to_string());
    let agents = drift::load_agents(&format!("{}/agents.tsv", dir)).unwrap();
    let decl = drift::load_declared(&format!("{}/permissions.tsv", dir), &agents).unwrap();
    assert_eq!(agents.len(), decl.len());
    for (name, perms) in &decl {
        assert!(
            perms.iter().any(|(p, l)| p == "metadata" && l == "read"),
            "{} lacks metadata=read, which GitHub always grants",
            name
        );
    }
}

#[test]
fn bad_level_is_rejected() {
    let (_d, p) = write(b"beacon\tcontents\twirte\nwren\tcontents\twrite\n");
    assert!(file_error(drift::load_declared(&p, &agents())).contains("wirte"));
}

#[test]
fn duplicate_permission_is_rejected() {
    let (_d, p) =
        write(b"beacon\tcontents\twrite\nbeacon\tcontents\tread\nwren\tcontents\twrite\n");
    assert!(file_error(drift::load_declared(&p, &agents())).contains("twice"));
}

#[test]
fn agent_with_no_rows_is_rejected() {
    let (_d, p) = write(b"beacon\tcontents\twrite\n");
    assert!(file_error(drift::load_declared(&p, &agents()))
        .contains("no permissions declared for wren"));
}

#[test]
fn row_for_unknown_agent_is_rejected() {
    let (_d, p) =
        write(b"beacon\tcontents\twrite\nwren\tcontents\twrite\nghost\tcontents\twrite\n");
    assert!(
        file_error(drift::load_declared(&p, &agents())).contains("'ghost' is not in agents.tsv")
    );
}

#[test]
fn agents_file_rules() {
    let (_d, p) = write(b"# c\n\n  \nbeacon\t0101\t\xd9\xa1\xd9\xa2\n");
    let a = drift::load_agents(&p).unwrap();
    assert_eq!(
        a,
        vec![Agent {
            name: "beacon".into(),
            app_id: "101".into(),
            inst_id: "12".into()
        }]
    );
    let (_d, p) = write(b"beacon\t\xc2\xb2\t1\n");
    match drift::load_agents(&p) {
        Err(LoadFail::Crash(c)) => assert_eq!(c.class, "ValueError"),
        other => panic!("{:?}", other),
    }
    let (_d, p) = write(b"beacon\tx\t1\n");
    assert!(
        matches!(drift::load_agents(&p), Err(LoadFail::File(m)) if m.ends_with(":1: app_id and installation_id must be numbers"))
    );
    let (_d, p) = write(b"beacon\t1\n");
    assert!(
        matches!(drift::load_agents(&p), Err(LoadFail::File(m)) if m.ends_with(":1: want agent, app_id, installation_id"))
    );
    let (_d, p) = write(b"# only\n");
    assert!(
        matches!(drift::load_agents(&p), Err(LoadFail::File(m)) if m.ends_with(": no agents listed"))
    );
    let (_d, p) = write(b"\xff");
    assert!(
        matches!(drift::load_agents(&p), Err(LoadFail::Crash(c)) if c.class == "UnicodeDecodeError")
    );
    assert!(
        matches!(drift::load_agents("/no/such/file"), Err(LoadFail::File(m)) if m == "cannot read /no/such/file: [Errno 2] No such file or directory: '/no/such/file'")
    );
}
