// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Zitadel's protected-resource metadata for an MCP endpoint.

use serde_json::{json, Value};

/// The scope that puts a Zitadel project's id in a token's audience.
pub fn audience_scope_for(project_id: &str) -> String {
    format!("urn:zitadel:iam:org:project:id:{project_id}:aud")
}

/// Every scope a client should ask for to reach a server on this project.
pub fn full_scope_string(project_id: &str) -> String {
    format!("openid offline_access {}", audience_scope_for(project_id))
}

/// The RFC 9728 document served at `/.well-known/oauth-protected-resource`:
/// which resource this is, who issues tokens for it, and the scopes to ask for.
pub fn protected_resource_metadata(resource: &str, issuer: &str, project_id: &str) -> Value {
    json!({
        "resource": resource,
        "authorization_servers": [issuer],
        "scopes_supported": [
            "openid",
            "offline_access",
            audience_scope_for(project_id),
        ],
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prm_lists_project_audience_scope() {
        let doc = protected_resource_metadata(
            "https://relay.example.test/mcp",
            "https://auth.example.test",
            "123456789",
        );
        assert_eq!(doc["resource"], "https://relay.example.test/mcp");
        assert_eq!(
            doc["authorization_servers"],
            serde_json::json!(["https://auth.example.test"])
        );
        assert_eq!(
            doc["scopes_supported"],
            serde_json::json!([
                "openid",
                "offline_access",
                "urn:zitadel:iam:org:project:id:123456789:aud"
            ])
        );
    }
}
