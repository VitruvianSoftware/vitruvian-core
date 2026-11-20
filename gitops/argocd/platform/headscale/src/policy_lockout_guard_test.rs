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

//! Lockout guard test ensuring `policy.hujson` never removes James's all-access mesh rule.

use headscale_values::{check_policy_lockout_guard, yaml, PKG_DIR, POLICY_FILENAME};

#[test]
fn policy_hujson_keeps_full_mesh_access_for_both_james_identities() {
    let path = yaml::resolve_data_path(PKG_DIR, POLICY_FILENAME);
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
    check_policy_lockout_guard(&raw).unwrap_or_else(|e| panic!("{e}"));
}

#[test]
fn lockout_guard_rejects_missing_identity_restricted_dst_or_restricted_proto() {
    let base = yaml::resolve_data_path(PKG_DIR, POLICY_FILENAME);
    let raw = std::fs::read_to_string(&base).expect("read policy.hujson");
    check_policy_lockout_guard(&raw).unwrap();

    for broken in [
        raw.replace("\"james@\", ", ""),
        raw.replace(", \"james.nguyen@gmail.com\"", ""),
        raw.replace("\"*:*\"", "\"fedora:30265\""),
        raw.replace(
            "\"dst\": [\"*:*\"]",
            "\"proto\": \"tcp\", \"dst\": [\"*:*\"]",
        ),
        raw.replace("\"action\": \"accept\"", "\"action\": \"deny\""),
        "{ \"acls\": [] }\n".to_string(),
        r#"{
  "acls": [
    {"action": "accept", "src": ["james@"], "dst": ["*:*"]},
    {"action": "accept", "src": ["james.nguyen@gmail.com"], "dst": ["fedora:30265"]}
  ]
}"#
        .to_string(),
    ] {
        let err = check_policy_lockout_guard(&broken).unwrap_err();
        assert!(
            err.contains("lock James out of the mesh"),
            "unexpected error: {err}"
        );
    }
}
