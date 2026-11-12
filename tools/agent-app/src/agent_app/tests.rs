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
    assert!(workflow_args("u", &v(&["--ref=main", "-fn=1", "--raw-field", "a=b"])).is_ok());
    for bad in [
        &["-F", "n=1"][..],
        &["-Fn=1"],
        &["--field", "n=@secret.txt"],
        &["--field=n=1"],
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
fn allowlist_entries_declare_their_input_keys() {
    let list = b"# c\ncatalog-bump.yaml id tag # inputs\n  delivery-drift.yaml  # x\n  # indented\nfoundation-proj-deploy.yaml environment business-unit allow-destructive\n";
    assert_eq!(
        allowlist(list),
        b"catalog-bump.yaml\ndelivery-drift.yaml\nfoundation-proj-deploy.yaml"
    );
    assert_eq!(
        allowlist_entry(list, b"catalog-bump.yaml"),
        Some(v(&["id", "tag"]))
    );
    assert_eq!(allowlist_entry(list, b"delivery-drift.yaml"), Some(vec![]));
    assert_eq!(allowlist_entry(list, b"catalog-bump"), None);
    assert_eq!(allowlist_entry(list, b"#"), None);
}

/// The committed list, read the way workflow-run reads it.
fn committed_list() -> Vec<u8> {
    let p = std::env::var("WORKFLOW_ALLOWLIST_TXT").expect("WORKFLOW_ALLOWLIST_TXT (set by BUILD)");
    std::fs::read(p).expect("read workflow-allowlist.txt")
}

fn inputs(wf: &str, args: &[&str]) -> Result<(), Refusal> {
    let list = committed_list();
    let declared = allowlist_entry(&list, wf.as_bytes()).expect("listed");
    workflow_inputs_ok(wf.as_bytes(), &declared, &v(args))
}

fn proj() -> Vec<Vec<u8>> {
    v(&["environment", "business-unit", "allow-destructive"])
}

#[test]
fn committed_allowlist_pins_the_foundation_entries() {
    let list = committed_list();
    assert_eq!(
        allowlist_entry(&list, b"foundation-proj-deploy.yaml"),
        Some(proj())
    );
    assert_eq!(
        allowlist_entry(&list, b"foundation-app-deploy.yaml"),
        Some(v(&["environment", "business-unit", "app-image-digests"]))
    );
    assert_eq!(
        allowlist_entry(&list, b"catalog-bump.yaml"),
        Some(v(&["id", "tag"]))
    );
    assert_eq!(allowlist_entry(&list, b"delivery-drift.yaml"), Some(vec![]));
    assert_eq!(
        allowlist_entry(&list, b"agent-app-permissions.yaml"),
        Some(vec![])
    );
    assert_eq!(
        allowlist_entry(&list, b"delivery-stripe.yaml"),
        Some(v(&["unit", "environment"]))
    );
}

#[test]
fn foundation_rerun_accepted() {
    let good: &[&[&str]] = &[
        &[
            "-f",
            "environment=development",
            "-f",
            "business-unit=business_unit_1",
            "-f",
            "allow-destructive=true",
            "--ref",
            "main",
        ],
        &[
            "-fenvironment=production",
            "--raw-field=business-unit=business_unit_2",
            "-f",
            "allow-destructive=false",
        ],
        &["-f", "environment=shared"],
    ];
    for g in good {
        assert_eq!(inputs("foundation-proj-deploy.yaml", g), Ok(()), "{:?}", g);
        assert!(workflow_args("u", &v(g)).is_ok(), "{:?}", g);
    }
    assert_eq!(
        inputs(
            "foundation-app-deploy.yaml",
            &[
                "-f",
                "environment=nonproduction",
                "-f",
                "business-unit=business_unit_2",
                "-f",
                "app-image-digests=tabula=ghcr.io/x@sha256:ab"
            ]
        ),
        Ok(())
    );
    assert_eq!(
        inputs(
            "catalog-bump.yaml",
            &[
                "-f",
                "id=dev.vitruvian.speaker",
                "-f",
                "tag=vitruvian-speaker-v1.20.0"
            ]
        ),
        Ok(())
    );
    assert_eq!(inputs("delivery-drift.yaml", &["--ref", "main"]), Ok(()));
}

#[test]
fn undeclared_input_key_refused() {
    for (wf, a) in [
        ("foundation-proj-deploy.yaml", "-fapp-image-digests=x=y"),
        ("foundation-proj-deploy.yaml", "-fEnvironment=production"),
        ("foundation-app-deploy.yaml", "-fextra=1"),
        ("catalog-bump.yaml", "-ftool=github"),
        ("delivery-drift.yaml", "-fid=x"),
        ("agent-app-permissions.yaml", "-fx=y"),
    ] {
        let m = msg(inputs(wf, &[a]).unwrap_err());
        assert!(m.contains("not declared"), "{} {}: {}", wf, a, m);
    }
}

#[test]
fn allow_destructive_only_for_foundation_proj_deploy() {
    // Refused on every other workflow even when its list line is edited to
    // declare the key: the rule does not trust the file.
    for wf in [
        "foundation-app-deploy.yaml",
        "catalog-bump.yaml",
        "delivery-drift.yaml",
        "other.yaml",
    ] {
        for key in [
            "allow-destructive",
            "allow_destructive",
            "Allow-Destructive",
        ] {
            let declared = v(&[key, "environment"]);
            let kv = format!("{}=true", key);
            let r = workflow_inputs_ok(wf.as_bytes(), &declared, &v(&["-f", &kv]));
            let m = msg(r.unwrap_err());
            assert!(
                m.contains("only foundation-proj-deploy.yaml"),
                "{} {}: {}",
                wf,
                key,
                m
            );
        }
    }
    // And against the committed list: app-deploy has no such input.
    let m = msg(inputs(
        "foundation-app-deploy.yaml",
        &["-f", "allow-destructive=true"],
    )
    .unwrap_err());
    assert!(m.contains("only foundation-proj-deploy.yaml"), "{}", m);
}

#[test]
fn allow_destructive_value_must_be_true_or_false() {
    for bad in ["1", "TRUE", "yes", "", "true ", "on"] {
        let kv = format!("allow-destructive={}", bad);
        let m = msg(inputs("foundation-proj-deploy.yaml", &["-f", &kv]).unwrap_err());
        assert!(m.contains("not an accepted value"), "{:?}: {}", bad, m);
    }
}

#[test]
fn working_directory_refused_for_foundation_workflows() {
    for wf in ["foundation-proj-deploy.yaml", "foundation-app-deploy.yaml"] {
        for key in [
            "working-directory",
            "working_directory",
            "Working-Directory",
        ] {
            let mut declared = proj();
            declared.push(key.as_bytes().to_vec());
            let kv = format!("{}=infrastructure/pulumi/foundation/gcp-org", key);
            let m =
                msg(workflow_inputs_ok(wf.as_bytes(), &declared, &v(&["-f", &kv])).unwrap_err());
            assert!(
                m.contains("chooses which Pulumi project"),
                "{} {}: {}",
                wf,
                key,
                m
            );
        }
        assert!(inputs(wf, &["-f", "working-directory=x"]).is_err());
    }
}

#[test]
fn foundation_leaf_values_must_name_a_real_leaf() {
    for bad in [
        "business-unit=../../gcp-org/production",
        "business-unit=business_unit_1/../../x",
        "business-unit=business_unit_",
        "business-unit=business_unit_01",
        "business-unit=",
        "environment=staging",
        "environment=../shared",
    ] {
        let m = msg(inputs("foundation-proj-deploy.yaml", &["-f", bad]).unwrap_err());
        assert!(m.contains("not an accepted value"), "{}: {}", bad, m);
    }
    assert!(business_unit_name(b"business_unit_12"));
}

#[test]
fn raw_field_inputs_are_checked_in_both_forms() {
    for (wf, a) in [
        (
            "foundation-proj-deploy.yaml",
            &["--raw-field", "working-directory=x"][..],
        ),
        (
            "foundation-proj-deploy.yaml",
            &["--raw-field=working-directory=x"],
        ),
        (
            "foundation-app-deploy.yaml",
            &["--raw-field", "allow-destructive=true"],
        ),
        (
            "foundation-app-deploy.yaml",
            &["--raw-field=allow_destructive=true"],
        ),
        (
            "foundation-proj-deploy.yaml",
            &["--raw-field", "business-unit=../x"],
        ),
        (
            "foundation-proj-deploy.yaml",
            &["--raw-field=business-unit=../x"],
        ),
    ] {
        assert!(workflow_args("u", &v(a)).is_ok(), "{:?}", a);
        assert!(inputs(wf, a).is_err(), "{} {:?}", wf, a);
    }
}

#[test]
fn foundation_app_deploy_values_must_name_a_real_leaf() {
    for bad in [
        "business-unit=../x",
        "business-unit=../../gcp-projects/business_unit_1",
        "environment=staging",
        "environment=shared",
    ] {
        let m = msg(inputs("foundation-app-deploy.yaml", &["-f", bad]).unwrap_err());
        assert!(m.contains("not an accepted value"), "{}: {}", bad, m);
    }
    for env in ["development", "nonproduction", "production"] {
        let kv = format!("environment={}", env);
        assert_eq!(
            inputs("foundation-app-deploy.yaml", &["-f", &kv]),
            Ok(()),
            "{}",
            env
        );
    }
    // The projects stage does have a shared leaf.
    assert_eq!(
        inputs("foundation-proj-deploy.yaml", &["-f", "environment=shared"]),
        Ok(())
    );
}

#[test]
fn input_given_twice_or_without_value_refused() {
    let r = inputs(
        "foundation-proj-deploy.yaml",
        &[
            "-f",
            "environment=development",
            "-f",
            "environment=production",
        ],
    );
    assert!(msg(r.unwrap_err()).contains("given twice"));
    let r = inputs("foundation-proj-deploy.yaml", &["-f", "environment"]);
    assert!(msg(r.unwrap_err()).contains("key=value"));
}

#[test]
fn non_main_ref_still_refused_with_good_inputs() {
    let ok = [
        "-f",
        "environment=development",
        "-f",
        "allow-destructive=true",
    ];
    for r in [
        &["--ref", "feature"][..],
        &["-rfeature"],
        &["--ref=refs/heads/main"],
    ] {
        let mut a: Vec<&str> = ok.to_vec();
        a.extend_from_slice(r);
        assert!(workflow_args("u", &v(&a)).is_err(), "{:?}", a);
    }
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
    assert!(USAGE.contains("pr-update-branch [--agent <agent>] <pr> [--rebase]"));
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

// --- branch-delete's landed gate --------------------------------------------

fn gate_scratch(name: &str) -> std::path::PathBuf {
    let d = std::path::PathBuf::from(std::env::var("TEST_TMPDIR").unwrap()).join(name);
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn put(p: &std::path::Path, mode: u32) {
    use std::os::unix::fs::PermissionsExt;
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::write(p, b"#!/bin/sh\n").unwrap();
    std::fs::set_permissions(p, std::fs::Permissions::from_mode(mode)).unwrap();
}

fn b(p: &std::path::Path) -> Vec<u8> {
    p.as_os_str().as_bytes().to_vec()
}

#[test]
fn landed_is_found_beside_the_program_not_in_the_checkout() {
    let d = gate_scratch("landed-sibling");
    let here = d.join("bin/tools/agent-app");
    std::fs::create_dir_all(&here).unwrap();
    let argv0 = here.join("agent-app");
    // A checkout-shaped landed.sh must never be what is picked.
    put(&d.join("checkout/tools/landed/landed.sh"), 0o755);
    assert_eq!(
        find_landed(&landed_candidates(&b(&here), &b(&argv0), b"")),
        None
    );

    // Not executable: not a gate.
    let sib = d.join("bin/tools/landed/landed");
    put(&sib, 0o644);
    assert_eq!(
        find_landed(&landed_candidates(&b(&here), &b(&argv0), b"")),
        None
    );
    put(&sib, 0o755);
    let got = find_landed(&landed_candidates(&b(&here), &b(&argv0), b"")).unwrap();
    assert_eq!(
        std::fs::canonicalize(sh::path(&got)).unwrap(),
        std::fs::canonicalize(&sib).unwrap()
    );
}

#[test]
fn landed_falls_back_to_runfiles() {
    let d = gate_scratch("landed-runfiles");
    let here = d.join("elsewhere");
    let argv0 = d.join("bin/agent-app");
    let rf = d.join("rf");
    put(&rf.join("_main/tools/landed/landed"), 0o755);
    assert_eq!(
        find_landed(&landed_candidates(&b(&here), &b(&argv0), &b(&rf))),
        Some(b(&rf.join("_main/tools/landed/landed")))
    );
    let own = d.join("bin/agent-app.runfiles/_main/tools/landed/landed");
    put(&own, 0o755);
    assert_eq!(
        find_landed(&landed_candidates(&b(&here), &b(&argv0), b"")),
        Some(b(&own))
    );
}

/// The gate is the Rust binary: it must be run directly. `bash <binary>`
/// answers "cannot execute binary file" for every branch.
#[test]
fn landed_gate_runs_the_binary_itself() {
    let bin = std::env::current_dir()
        .unwrap()
        .join(std::env::var("LANDED_BIN").expect("LANDED_BIN is set by the BUILD rule"));
    let d = gate_scratch("landed-run");
    let mut c = landed_gate(&b(&bin), b"no-such-branch-for-a-test", b"");
    c.current_dir(&d)
        .env_remove("BUILD_WORKSPACE_DIRECTORY")
        .env_remove("BUILD_WORKING_DIRECTORY")
        .env("GIT_CEILING_DIRECTORIES", &d);
    let o = c.output().expect("landed starts");
    let all = format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    );
    assert!(!all.contains("cannot execute"), "{all}");
    assert_ne!(o.status.code(), Some(126), "{all}");
    // Outside a repository it cannot prove anything, so it says no.
    assert_ne!(o.status.code(), Some(0), "{all}");
}

#[test]
fn read_args_allows_reads() {
    for ok in [
        &["pr", "view", "4446", "--json", "state"][..],
        &["pr", "checks", "4446"],
        &["run", "list", "--workflow", "ci.yaml", "--limit", "5"],
        &["run", "view", "123", "--log-failed"],
        &["workflow", "list"],
        &["issue", "view", "3418"],
        &["search", "prs", "relay"],
        &["status"],
        &["api", "repos/VitruvianSoftware/vitruvian-core/rulesets"],
        &["api", "-X", "GET", "search/issues", "-f", "q=repo:x"],
        &["api", "--method=HEAD", "repos/o/r"],
        &["api", "graphql", "-f", "query={ viewer { login } }"],
    ] {
        assert!(read_args(&v(ok)).is_ok(), "{:?}", ok);
    }
}

#[test]
fn read_args_refuses_writes() {
    for bad in [
        &[][..],
        &["--repo", "x"],
        &["pr", "merge", "1"],
        &["pr", "create"],
        &["pr"],
        &["run", "rerun", "1"],
        &["workflow", "run", "x.yaml"],
        &["issue", "create", "--title", "x"],
        &["secret", "set", "X"],
        &["auth", "login"],
        &["repo", "delete", "o/r"],
        &["api", "-X", "POST", "repos/o/r/issues"],
        &["api", "--method", "delete", "repos/o/r"],
        &["api", "repos/o/r/issues", "-f", "title=x"],
        &["api", "repos/o/r", "--input", "body.json"],
        &["api", "graphql", "-f", "query=mutation { x }"],
        &["api", "graphql", "-f", "query=Mutation{x}"],
        &["api", "graphql"],
    ] {
        assert!(read_args(&v(bad)).is_err(), "{:?}", bad);
    }
}

#[test]
fn parse_alert_dismiss_validates_alert_number_kind_and_comment() {
    let valid_sec: &[&[u8]] = &[b"false_positive", b"wont_fix", b"revoked", b"used_in_tests"];
    let (n, r, c) = parse_alert_dismiss(
        "U",
        &v(&[
            "6",
            "--resolution",
            "false_positive",
            "--comment",
            "public web key",
        ]),
        b"--resolution",
        valid_sec,
    )
    .unwrap();
    assert_eq!(
        (&n[..], &r[..], &c[..]),
        (&b"6"[..], &b"false_positive"[..], &b"public web key"[..])
    );

    let (n2, r2, c2) = parse_alert_dismiss(
        "U",
        &v(&["1455", "--reason=tolerable_risk", "--comment=build only"]),
        b"--reason",
        &[b"tolerable_risk", b"not_used"],
    )
    .unwrap();
    assert_eq!(
        (&n2[..], &r2[..], &c2[..]),
        (&b"1455"[..], &b"tolerable_risk"[..], &b"build only"[..])
    );

    for bad in [
        &[][..],
        &["0", "--resolution", "false_positive", "--comment", "x"],
        &["abc", "--resolution", "false_positive", "--comment", "x"],
        &["6", "--resolution", "invalid", "--comment", "x"],
        &["6", "--resolution", "false_positive"],
        &["6", "--resolution", "false_positive", "--comment", "   "],
        &["6", "--comment", "x"],
        &[
            "6",
            "--resolution",
            "false_positive",
            "--comment",
            "x",
            "--extra",
        ],
    ] {
        assert!(
            parse_alert_dismiss("U", &v(bad), b"--resolution", valid_sec).is_err(),
            "{:?}",
            bad
        );
    }
}
