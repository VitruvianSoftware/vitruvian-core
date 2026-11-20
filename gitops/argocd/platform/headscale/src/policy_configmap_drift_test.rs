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

//! Drift tests verifying `configmap-policy.yaml` embeds `policy.hujson` byte-for-byte.

use headscale_values::{
    check_policy_configmap_drift, render_policy_configmap, yaml, PKG_DIR,
    POLICY_CONFIGMAP_FILENAME, POLICY_FILENAME,
};

#[test]
fn committed_configmap_embeds_policy_hujson_byte_for_byte() {
    let policy_path = yaml::resolve_data_path(PKG_DIR, POLICY_FILENAME);
    let cm_path = yaml::resolve_data_path(PKG_DIR, POLICY_CONFIGMAP_FILENAME);
    let raw_policy = std::fs::read_to_string(&policy_path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", policy_path.display()));
    let committed_cm = std::fs::read_to_string(&cm_path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", cm_path.display()));
    check_policy_configmap_drift(&raw_policy, &committed_cm).unwrap();
}

#[test]
fn drift_check_rejects_single_byte_or_header_mismatch() {
    let sample = "// comment\n{\n  \"acls\": []\n}\n";
    let cm = render_policy_configmap(sample);
    check_policy_configmap_drift(sample, &cm).unwrap();

    let changed_byte = "// comment\n{\n  \"acls\": [ ]\n}\n";
    let err = check_policy_configmap_drift(changed_byte, &cm).unwrap_err();
    assert!(err.contains("policy-configmap"), "{err}");

    let no_trailing_nl = "// comment\n{\n  \"acls\": []\n}";
    assert!(check_policy_configmap_drift(no_trailing_nl, &cm).is_err());

    let edited_cm = cm.replacen("Do not edit by hand", "Edited by hand", 1);
    assert!(check_policy_configmap_drift(sample, &edited_cm).is_err());

    // Round-trip special cases: leading spaces, internal blank lines, no trailing newline, empty.
    for edge in [
        "  {\n  \"acls\": []\n}\n",
        "// header\n\n{\n  \"acls\": []\n}\n",
        "{\n  \"acls\": []\n}",
        "",
    ] {
        let edge_cm = render_policy_configmap(edge);
        check_policy_configmap_drift(edge, &edge_cm).unwrap();
    }
}
