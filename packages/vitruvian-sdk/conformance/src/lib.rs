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

//! Native Rust implementation of the Vitruvian SDK Conformance Validator
//! (`packages/vitruvian-sdk/conformance/conformance.py`).

pub mod cli;
pub mod json;
pub mod protocol;
pub mod pystr;
pub mod session;

pub use cli::{check, check_to, main_with_args, parse_args, resolve_folder, Options, ParseOutcome};
pub use protocol::{
    check_params, is_block, is_chips, is_choice, is_count, is_equivalent, is_flag, is_id,
    is_number, is_saved, is_since, is_state, is_text, is_tree, is_ui_text, is_whole, kind_of,
    misnamed, name_rule_broken, newer_than, Failure, MsgKind, ANSWER_SECONDS, EXIT_SECONDS,
    FEATURES, FIRST_ANSWER_SECONDS, HAS_HELP, INVALID_PARAMS, MAX_BLOCKS, MAX_CHOICE_OPTIONS,
    MAX_CHOICE_VALUE, MAX_LINE_BYTES, MAX_NAME, MAX_STATUS_AFTER_REFUSAL, MAX_TREE_BYTES,
    METHOD_NOT_FOUND, NEEDS_ID, NOT_IN_USES, STATES, UNAVAILABLE, VERSIONS,
};
pub use session::{an_older_app, Link, Run, TempDir, Transport};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::Value;
    use std::time::{Duration, Instant};

    #[test]
    fn test_pystr_repr_and_bytes() {
        assert_eq!(pystr::repr_str("hello"), "'hello'");
        assert_eq!(pystr::repr_str("it's"), "\"it's\"");
        assert_eq!(pystr::repr_str("caf\u{00e9}"), "'caf\u{00e9}'");
        assert_eq!(pystr::repr_bytes(b"starting up\n"), "b'starting up\\n'");
    }

    #[test]
    fn test_json_roundtrip_and_py_eq() {
        let a = json::loads(r#"{"b": 1, "a": [true, 1.0, "ok"]}"#).unwrap();
        let b = json::loads(r#"{"a": [1, true, "ok"], "b": 1.0}"#).unwrap();
        assert!(json::py_eq(&a, &b));
        assert_eq!(a.py_repr(), "{'b': 1, 'a': [True, 1.0, 'ok']}");
        assert_eq!(a.dumps_compact(), r#"{"b":1,"a":[true,1.0,"ok"]}"#);
    }

    #[test]
    fn test_name_rules_and_misnamed() {
        assert_eq!(
            name_rule_broken("").as_deref(),
            Some("at least one character")
        );
        assert_eq!(
            name_rule_broken("installHook:claudeCode").as_deref(),
            Some("ASCII letters, digits, '.', '-' and '_' only")
        );
        assert_eq!(
            name_rule_broken("caf\u{00e9}").as_deref(),
            Some("ASCII letters, digits, '.', '-' and '_' only")
        );
        assert_eq!(
            name_rule_broken(&"a".repeat(129)).as_deref(),
            Some("at most 128 characters")
        );
        assert_eq!(
            name_rule_broken(".hooks").as_deref(),
            Some("no '.' at either end")
        );
        assert_eq!(
            name_rule_broken("hooks.").as_deref(),
            Some("no '.' at either end")
        );
        assert_eq!(
            name_rule_broken("hooks..claude").as_deref(),
            Some("no two '.' together")
        );
        for valid in [&"a".repeat(128), "install-hook.claude_code", "x", "0.1-b_2"] {
            assert_eq!(name_rule_broken(valid), None);
        }

        let bad_block_tree = json::loads(
            r#"{"blocks": [{"type": "toggle", "id": "installHook:claudeCode", "title": "Hook", "value": false}]}"#,
        )
        .unwrap();
        assert_eq!(
            misnamed(&bad_block_tree, "counter").as_deref(),
            Some("the page of counter has block id 'installHook:claudeCode', which is not a valid name (ASCII letters, digits, '.', '-' and '_' only): Vitruvian refuses the whole page")
        );

        let missing_row_id_tree = json::loads(
            r#"{"blocks": [{"type": "list", "id": "hooks", "rows": [{"title": "Claude Code"}]}]}"#,
        )
        .unwrap();
        assert_eq!(
            misnamed(&missing_row_id_tree, "counter").as_deref(),
            Some("the page of counter has a row in list 'hooks' whose id is missing or not text: Vitruvian refuses the whole page")
        );
    }

    #[test]
    fn test_kind_of_and_check_params() {
        let req = json::loads(
            r#"{"jsonrpc": "2.0", "id": "a", "method": "notify/hud", "params": {"icon": "hand.wave", "message": "hi"}}"#,
        )
        .unwrap();
        assert_eq!(kind_of(&req).unwrap(), MsgKind::Request);
        assert!(check_params(&req).is_ok());

        let bad_req = json::loads(
            r#"{"jsonrpc": "2.0", "id": "a", "method": "notify/hud", "params": {"icon": "hand.wave", "message": 5}}"#,
        )
        .unwrap();
        assert_eq!(
            check_params(&bad_req).unwrap_err().0,
            "notify/hud with params that are not its own: {'icon': 'hand.wave', 'message': 5}"
        );

        let null_id_err = json::loads(
            r#"{"jsonrpc": "2.0", "id": null, "error": {"code": -32600, "message": "bad"}}"#,
        )
        .unwrap();
        assert_eq!(kind_of(&null_id_err).unwrap(), MsgKind::Failure);

        let missing_id_err =
            json::loads(r#"{"jsonrpc": "2.0", "error": {"code": -32600, "message": "bad"}}"#)
                .unwrap();
        assert!(kind_of(&missing_id_err).is_err());
    }

    #[test]
    fn test_the_hello() {
        struct Kept {
            sent: Vec<Value>,
        }
        impl Transport for Kept {
            fn send(&mut self, message: &Value) -> Result<(), Failure> {
                self.sent.push(message.clone());
                Ok(())
            }
            fn receive(
                &mut self,
                _deadline: Instant,
                _seconds: u64,
                _leaving: bool,
            ) -> Result<Option<Value>, Failure> {
                Ok(Some(
                    json::loads(
                        r#"{"jsonrpc": "2.0", "id": 1, "result": {"protocolVersion": "1", "toolVersion": "0"}}"#,
                    )
                    .unwrap(),
                ))
            }
        }

        let manifest = Value::Obj(Vec::new());
        let mut run_modern = Run::new(
            Kept { sent: Vec::new() },
            &manifest,
            "/tmp/data",
            Run::<Kept>::default_features(),
        );
        assert_eq!(run_modern.handshake().unwrap(), "version 1, tool 0");
        let sent_features = run_modern.link.sent[0]
            .get("params")
            .and_then(|p| p.get("features"))
            .and_then(|f| f.as_arr())
            .unwrap();
        let names: Vec<&str> = sent_features.iter().filter_map(|v| v.as_str()).collect();
        assert_eq!(names, FEATURES);

        let mut run_older = Run::new(Kept { sent: Vec::new() }, &manifest, "/tmp/data", None);
        assert_eq!(run_older.handshake().unwrap(), "version 1, tool 0");
        assert!(run_older.link.sent[0]
            .get("params")
            .unwrap()
            .get("features")
            .is_none());
    }

    #[test]
    fn test_a_line_always_waiting() {
        struct AlwaysWaiting {
            give_up: Instant,
        }
        impl Transport for AlwaysWaiting {
            fn send(&mut self, _message: &Value) -> Result<(), Failure> {
                Ok(())
            }
            fn receive(
                &mut self,
                _deadline: Instant,
                _seconds: u64,
                _leaving: bool,
            ) -> Result<Option<Value>, Failure> {
                if Instant::now() >= self.give_up {
                    return Err(Failure::new("read on past its limit"));
                }
                Ok(Some(
                    json::loads(
                        r#"{"jsonrpc": "2.0", "method": "log", "params": {"message": "still here"}}"#,
                    )
                    .unwrap(),
                ))
            }
        }

        let manifest = Value::Obj(Vec::new());
        let mut run = Run::new(
            AlwaysWaiting {
                give_up: Instant::now() + Duration::from_secs(2 * EXIT_SECONDS),
            },
            &manifest,
            "",
            Run::<AlwaysWaiting>::default_features(),
        );
        let started = Instant::now();
        let err = run.last_words().unwrap_err();
        let took = started.elapsed();
        assert_eq!(
            err.0,
            format!("still writing {} seconds after it exited", EXIT_SECONDS)
        );
        assert!(took < Duration::from_secs(EXIT_SECONDS + 1));
    }
}
