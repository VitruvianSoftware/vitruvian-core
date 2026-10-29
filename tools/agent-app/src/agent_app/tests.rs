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

//! Unit tests for agent_app: the argument rules, the encodings and the jq
//! programs.

use super::jq::{self, Prog, J};
use super::*;

fn v(args: &[&str]) -> Vec<Vec<u8>> {
    args.iter().map(|a| a.as_bytes().to_vec()).collect()
}

fn msg(r: Refusal) -> String {
    String::from_utf8(r.0).unwrap()
}

#[test]
fn b64url_is_unpadded_url_safe_base64() {
    assert_eq!(b64url(b""), b"");
    assert_eq!(b64url(b"f"), b"Zg");
    assert_eq!(b64url(b"fo"), b"Zm8");
    assert_eq!(b64url(b"foo"), b"Zm9v");
    assert_eq!(b64url(&[0xfb, 0xff, 0xbf]), b"-_-_");
    assert_eq!(
        b64url(br#"{"alg":"RS256","typ":"JWT"}"#),
        b"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9"
    );
}

#[test]
fn take_agent_reads_a_leading_agent_flag_only() {
    let a = v(&["--agent", "beacon", "12"]);
    let (who, rest) = take_agent(&a).unwrap();
    assert_eq!(who, b"beacon");
    assert_eq!(rest, &a[2..]);
    assert!(take_agent(&v(&["--agent"])).is_none());
    assert!(take_agent(&v(&["--agent", ""])).is_none());
    let a = v(&["12", "--agent", "beacon"]);
    assert_eq!(take_agent(&a).unwrap().1, &a[..]);
}

#[test]
fn need_target_refuses_missing_and_flag_shaped() {
    assert!(need_target("pr", "u", b"12").is_ok());
    assert_eq!(
        msg(need_target("pr", "u", b"").unwrap_err()),
        "usage: u   (missing <pr>)"
    );
    assert!(need_target("pr", "u", b"--title").is_err());
}

#[test]
fn fast_lane_label_is_detected_in_every_spelling() {
    for given in [
        &["--label", "agent-fast-lane"][..],
        &["--label=agent-fast-lane"],
        &["-l", "agent-fast-lane"],
        &["-lagent-fast-lane"],
        &["--label", "ci, agent-fast-lane"],
    ] {
        assert!(has_fast_lane(&v(given)), "{:?}", given);
    }
    for given in [
        &["--label", "ci"][..],
        &["--title", "agent-fast-lane"],
        &["--label", "agent-fast-lane-x"],
        &["agent-fast-lane"],
    ] {
        assert!(!has_fast_lane(&v(given)), "{:?}", given);
    }
}

#[test]
fn has_body_spellings() {
    for a in [
        "--body",
        "--body=",
        "-b",
        "-bx",
        "--body-file",
        "--body-file=f",
        "-F",
        "-Ff",
    ] {
        assert!(has_body(&v(&[a])), "{}", a);
    }
    for a in ["--bodyx", "--body-filex", "b", "-x"] {
        assert!(!has_body(&v(&[a])), "{}", a);
    }
}

#[test]
fn review_rules() {
    let u = "U";
    assert!(review_args(u, &v(&["--approve"])).is_ok());
    assert!(review_args(u, &v(&["-ab", "LGTM"])).is_ok());
    assert!(review_args(u, &v(&["--body", "--approve", "--comment"])).is_ok());
    assert!(msg(review_args(u, &v(&[])).unwrap_err()).contains("pass one of"));
    assert!(msg(review_args(u, &v(&["-ac", "-b", "x"])).unwrap_err()).contains("pass one of"));
    assert!(msg(review_args(u, &v(&["-r"])).unwrap_err()).contains("give the body"));
    assert_eq!(
        msg(review_args(u, &v(&["--approve", "--body"])).unwrap_err()),
        "usage: U"
    );
    assert!(msg(review_args(u, &v(&["-aw"])).unwrap_err())
        .starts_with("refusing -aw: it opens a browser"));
    assert!(review_args(u, &v(&["--approve", "-R", "o/r"])).is_ok());
}

#[test]
fn enqueue_rules() {
    assert_eq!(enqueue_args(&v(&["12"])).unwrap(), Enqueue::default());
    let e = enqueue_args(&v(&["12", "-sd"])).unwrap();
    assert!(e.method && !e.auto);
    let e = enqueue_args(&v(&["12", "--subject", "-m"])).unwrap();
    assert!(!e.method);
    let e = enqueue_args(&v(&["12", "-Ro/r", "--auto"])).unwrap();
    assert_eq!(e.repo, Some(b"o/r".to_vec()));
    assert!(e.auto);
    let e = enqueue_args(&v(&["12", "--repo", "a/b", "--repo=c/d"])).unwrap();
    assert_eq!(e.repo, Some(b"c/d".to_vec()));
    for bad in [
        "--admin",
        "--admin=true",
        "--rebase",
        "-m",
        "-sm",
        "-dr",
        "--disable-auto",
        "--merge=x",
    ] {
        assert!(enqueue_args(&v(&["12", bad])).is_err(), "{}", bad);
    }
    assert!(msg(enqueue_args(&v(&["--admin"])).unwrap_err()).contains("break-glass"));
    // -t ends the cluster: its value is -r, not a rebase.
    assert!(enqueue_args(&v(&["12", "-t", "-r"])).is_ok());
}

#[test]
fn hold_args_rules() {
    let h = hold_args("u", true, &v(&["--reason", "r", "-R", "o/r"])).unwrap();
    assert_eq!(h.reason, b"r");
    assert_eq!(h.repo, Some(b"o/r".to_vec()));
    assert_eq!(
        hold_args("u", true, &v(&["--reason=x"])).unwrap().reason,
        b"x"
    );
    assert_eq!(
        msg(hold_args("u", true, &v(&["--reason"])).unwrap_err()),
        "usage: u"
    );
    assert_eq!(
        msg(hold_args("u", false, &v(&["--reason", "r"])).unwrap_err()),
        "usage: u   (unexpected '--reason')"
    );
    assert!(hold_args("u", true, &v(&["--label", "x"])).is_err());
}

#[test]
fn issue_and_workflow_rules() {
    assert!(issue_args_ok("u", &v(&["-Rother/repo"])).is_err());
    assert!(issue_args_ok("u", &v(&["--web"])).is_err());
    assert!(issue_args_ok("u", &v(&["--title", "t"])).is_ok());
    assert!(workflow_args("u", &v(&["-f", "tool=github", "--ref", "main"])).is_ok());
    assert!(workflow_args("u", &v(&["--ref=main", "-Fn=1"])).is_ok());
    for bad in [
        &["--ref", "feature"][..],
        &["-rfeature"],
        &["--ref", "refs/heads/main"],
        &["-Ro/r"],
        &["--repo=o/r"],
        &["--json"],
        &["-f"],
    ] {
        assert!(workflow_args("u", &v(bad)).is_err(), "{:?}", bad);
    }
}

#[test]
fn allowlist_matches_whole_names() {
    let a = allowlist(b"# c\n\ncatalog-bump.yaml\n  delivery-drift.yaml  # x\n");
    assert_eq!(a, b"catalog-bump.yaml\ndelivery-drift.yaml");
    assert!(allowed_has(&a, b"catalog-bump.yaml"));
    assert!(!allowed_has(&a, b"catalog-bump"));
    assert!(!allowed_has(&a, b"catalog-bump.yaml.bak"));
}

#[test]
fn branch_names_and_queue_branches() {
    for ok in ["old/done", "a.b_c-d", "x"] {
        assert!(plain_branch_name(ok.as_bytes()), "{}", ok);
    }
    for bad in ["", "-x", "/x", "refs/heads/x", "a..b", "x y", "é"] {
        assert!(!plain_branch_name(bad.as_bytes()), "{}", bad);
    }
    assert_eq!(
        queue_pr(b"gh-readonly-queue/main/pr-1264-ed8e62380b5893f43aa4f6696991e116f1366e42"),
        Some(b"1264".to_vec())
    );
    assert_eq!(queue_pr(b"gh-readonly-queue//pr-1-x"), None);
    assert_eq!(queue_pr(b"gh-readonly-queue/main/pr-x-1"), None);
    assert_eq!(queue_pr(b"gh-readonly-queue/main/pr-12"), None);
}

#[test]
fn awk_v_processes_escapes() {
    assert_eq!(awk_v(br"a\tb"), b"a\tb");
    assert_eq!(awk_v(br"a\\b"), br"a\b");
    assert_eq!(awk_v(br"\101"), b"A");
    assert_eq!(awk_v(br"x\q"), br"x\q");
    assert_eq!(awk_v(b"trail\\"), b"trail\\");
}

#[test]
fn arith_and_test_lt() {
    assert_eq!(arith(b"5"), 5);
    assert_eq!(arith(b"010"), 8);
    assert_eq!(arith(b"0x10"), 16);
    assert_eq!(arith(b"abc"), 0);
    assert!(test_lt(1, b"2"));
    assert!(!test_lt(2, b"2"));
    assert!(!test_lt(1, b"x"));
}

#[test]
fn constants_match_the_gates() {
    assert_eq!(HOLD_LABEL, "do-not-automerge");
    assert_eq!(RELEASE_HOLD_LABEL, "dev-deploy-red");
    assert_eq!(BETA_GATE_LABEL, "beta-not-built");
    assert!(hold_jq().contains("index(\"do-not-automerge\")"));
    assert!(USAGE.starts_with("agent-app — the API half"));
    assert!(USAGE.ends_with("for why per-agent Apps at all.\n\n"));
}

fn jq_out(p: &Prog, input: &str, e: bool) -> (String, String, i32) {
    let r = jq::run(p, input.as_bytes(), e);
    (
        String::from_utf8(r.stdout).unwrap(),
        String::from_utf8(r.stderr).unwrap(),
        r.status,
    )
}

#[test]
fn jq_field_with_exit_status() {
    assert_eq!(
        jq_out(&Prog::Field("token"), r#"{"token":"ghs_x"}"#, true),
        ("ghs_x\n".into(), "".into(), 0)
    );
    assert_eq!(
        jq_out(&Prog::Field("token"), r#"{"message":"Bad"}"#, true),
        ("null\n".into(), "".into(), 1)
    );
    assert_eq!(
        jq_out(&Prog::Field("token"), "", true),
        ("".into(), "".into(), 4)
    );
    assert_eq!(
        jq_out(&Prog::Field("token"), r#"{"token":false}"#, true).2,
        1
    );
    let (o, e, st) = jq_out(&Prog::Field("token"), "[1]", true);
    assert_eq!((o.as_str(), st), ("", 5));
    assert_eq!(
        e,
        "jq: error (at <stdin>:0): Cannot index array with string (\"token\")\n"
    );
    assert_eq!(
        jq_out(
            &Prog::Field("token"),
            "{\"token\":{\"b\":1,\"a\":[]}}",
            true
        )
        .0,
        "{\n  \"b\": 1,\n  \"a\": []\n}\n"
    );
    assert_eq!(
        jq_out(&Prog::Field("pem"), "{\"pem\":\"A\\nB\"}", true).0,
        "A\nB\n"
    );
}

#[test]
fn jq_programs() {
    let (o, _, st) = jq_out(
        &Prog::Convert("k.pem"),
        r#"{"id":7,"slug":"s","owner":{"login":"o"}}"#,
        false,
    );
    assert_eq!(
        (o.as_str(), st),
        ("app_id=7\nslug=s\nowner=o\nkey=k.pem\n", 0)
    );
    let (o, _, _) = jq_out(&Prog::Convert("k"), r#"{"owner":null}"#, false);
    assert_eq!(o, "app_id=null\nslug=null\nowner=null\nkey=k\n");
    let (o, _, _) = jq_out(
        &Prog::Installations,
        r#"[{"id":1,"account":{"login":"V"},"repository_selection":"all"},{"id":2}]"#,
        false,
    );
    assert_eq!(o, "installation_id=1\taccount=V\tselection=all\ninstallation_id=2\taccount=null\tselection=null\n");
    let (o, e, st) = jq_out(&Prog::Installations, "[{\"id\":1},5]", false);
    assert_eq!(o, "installation_id=1\taccount=null\tselection=null\n");
    // The last interpolation is evaluated first, as jq does.
    assert!(e.contains("Cannot index number with string (\"repository_selection\")"));
    assert_eq!(st, 5);
    let (o, _, _) = jq_out(
        &Prog::Repos,
        r#"{"repositories":[{"full_name":"a/b"},{"full_name":"c/d"}]}"#,
        false,
    );
    assert_eq!(o, "a/b\nc/d\n");
    let (_, e, st) = jq_out(&Prog::Repos, "{}", false);
    assert_eq!(
        (e.as_str(), st),
        (
            "jq: error (at <stdin>:0): Cannot iterate over null (null)\n",
            5
        )
    );
}

#[test]
fn jq_keeps_document_order_and_escapes() {
    let v: J = serde_json::from_str(r#"{"z":1,"a":"\u0001é\"","z":2}"#).unwrap();
    assert_eq!(v.compact(), "{\"z\":2,\"a\":\"\\u0001é\\\"\"}");
    let v: J = serde_json::from_str("\"aaaaaaaaaaaaaaaaaaaaaaaaaaa\"").unwrap();
    assert_eq!(
        v.iterate().unwrap_err(),
        "Cannot iterate over string (\"aaaaaaaaaaaaaaaaaaaaaaaaaaa\")"
    );
    let v: J = serde_json::from_str("\"aaaaaaaaaaaaaaaaaaaaaaaaaaaa\"").unwrap();
    assert_eq!(
        v.iterate().unwrap_err(),
        "Cannot iterate over string (\"aaaaaaaaaaaaaaaaaaaaaaaa...)"
    );
}

#[test]
fn jq_line_numbers_and_parse_errors() {
    // Values counted through the character after them, as jq 1.8 does.
    let (_, e, _) = jq_out(&Prog::Field("a"), "[1]\n\n", false);
    assert_eq!(
        e,
        "jq: error (at <stdin>:1): Cannot index array with string (\"a\")\n"
    );
    let (o, e, _) = jq_out(&Prog::Field("a"), "{\"a\":1}\n\n\n[1]\n", false);
    assert_eq!(o, "1\n");
    assert!(e.starts_with("jq: error (at <stdin>:4)"));
    for (inp, want) in [
        ("{\"a\":", "Unfinished JSON term at EOF at line 1, column 5"),
        (
            "{\"a\":1} x",
            "Invalid numeric literal at EOF at line 1, column 9",
        ),
        ("nul", "Invalid literal at EOF at line 1, column 3"),
        (
            "{\"a\":1}\n\n{",
            "Unfinished JSON term at EOF at line 3, column 1",
        ),
        ("\"abc", "Unfinished string at EOF at line 1, column 4"),
    ] {
        let (_, e, st) = jq_out(&Prog::Field("token"), inp, true);
        assert_eq!(e, format!("jq: parse error: {}\n", want), "{:?}", inp);
        assert_eq!(st, 5);
    }
}
