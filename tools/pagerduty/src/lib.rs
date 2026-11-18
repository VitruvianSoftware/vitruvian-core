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

//! A read-only window on the PagerDuty REST API, for checking what the
//! `infrastructure/pulumi/platform/pagerduty` stack did to the live account.
//!
//! It only ever sends GET to https://api.pagerduty.com, and it masks contact
//! addresses (phone numbers, emails) in what it prints, so its output is safe
//! to show in a chat or a PR. Changes belong to the Pulumi stack, not here.

use serde_json::Value;

/// The only host this tool talks to.
pub const API_BASE: &str = "https://api.pagerduty.com";

/// Checks an API path such as `/users/PABC123/contact_methods` and returns
/// the full URL. The path must start with `/` and use only characters that
/// cannot change the host, scheme or method.
pub fn url_for(path: &str) -> Result<String, String> {
    if !path.starts_with('/') || path.starts_with("//") {
        return Err(format!("path {path:?} must start with a single /"));
    }
    if let Some(c) = path
        .chars()
        .find(|c| !(c.is_ascii_alphanumeric() || "/_-.?=&,[]%:+".contains(*c)))
    {
        return Err(format!(
            "path {path:?} has a character this tool does not send: {c:?}"
        ));
    }
    Ok(format!("{API_BASE}{path}"))
}

/// Keys whose string values are personal contact details.
const MASKED_KEYS: &[&str] = &["address", "email", "phone_number"];

/// Masks every contact detail in `v`, keeping the last two characters so two
/// entries can still be told apart.
pub fn mask(v: &mut Value) {
    match v {
        Value::Object(map) => {
            for (k, val) in map.iter_mut() {
                match val {
                    Value::String(s) if MASKED_KEYS.contains(&k.as_str()) => {
                        let tail: String = s
                            .chars()
                            .rev()
                            .take(2)
                            .collect::<Vec<_>>()
                            .into_iter()
                            .rev()
                            .collect();
                        *s = format!("***{tail}");
                    }
                    _ => mask(val),
                }
            }
        }
        Value::Array(items) => items.iter_mut().for_each(mask),
        _ => {}
    }
}

/// A PagerDuty object id, such as an incident id `Q3TYP5OP5GR0HZ`: upper-case
/// letters and digits only, so it cannot change the request path.
pub fn is_object_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 32
        && id
            .chars()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit())
}

/// The PUT /incidents/{id} body that resolves one incident.
pub fn resolve_body() -> String {
    r#"{"incident":{"type":"incident_reference","status":"resolved"}}"#.to_string()
}

/// A bare email address for PagerDuty's required `From` header: one `@`, a
/// dot in the domain, and no characters that could break the header line.
pub fn is_from_email(email: &str) -> bool {
    let Some((user, domain)) = email.split_once('@') else {
        return false;
    };
    !user.is_empty()
        && domain.contains('.')
        && !domain.starts_with('.')
        && !domain.ends_with('.')
        && email.matches('@').count() == 1
        && domain
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-')
        && user
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "._+-".contains(c))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn accepts_api_paths() {
        assert_eq!(
            url_for("/users/PABC/notification_rules?include[]=contact_methods").unwrap(),
            "https://api.pagerduty.com/users/PABC/notification_rules?include[]=contact_methods"
        );
    }

    #[test]
    fn accepts_timestamps_in_queries() {
        assert!(url_for("/incidents?since=2026-11-10T00:00:00Z&urgencies[]=low").is_ok());
    }

    #[test]
    fn refuses_paths_that_could_leave_the_api() {
        for bad in [
            "users",
            "//evil.example/x",
            "/x@evil.example",
            "/a b",
            "/x#y",
            "/x\\y",
        ] {
            assert!(url_for(bad).is_err(), "{bad} should be refused");
        }
    }

    #[test]
    fn masks_contact_details_everywhere() {
        let mut v = json!({"contact_methods": [
            {"type": "phone_contact_method", "address": "4155550123", "label": "Mobile"},
            {"type": "email_contact_method", "address": "a@b.dev"}
        ], "user": {"email": "a@b.dev", "name": "James"}});
        mask(&mut v);
        assert_eq!(v["contact_methods"][0]["address"], "***23");
        assert_eq!(v["contact_methods"][0]["label"], "Mobile");
        assert_eq!(v["contact_methods"][1]["address"], "***ev");
        assert_eq!(v["user"]["email"], "***ev");
        assert_eq!(v["user"]["name"], "James");
    }

    #[test]
    fn object_ids_are_upper_alphanumeric_only() {
        assert!(is_object_id("Q3TYP5OP5GR0HZ"));
        assert!(!is_object_id(""));
        assert!(!is_object_id("q3typ"));
        assert!(!is_object_id("Q3/../users"));
        assert!(!is_object_id("Q3?x=1"));
    }

    #[test]
    fn resolve_body_sets_status_resolved() {
        let v: Value = serde_json::from_str(&resolve_body()).unwrap();
        assert_eq!(v["incident"]["status"], "resolved");
        assert_eq!(v["incident"]["type"], "incident_reference");
    }

    #[test]
    fn from_email_must_be_a_bare_address() {
        assert!(is_from_email("james@vitruviansoftware.dev"));
        assert!(!is_from_email("james"));
        assert!(!is_from_email("James <james@vitruviansoftware.dev>"));
        assert!(!is_from_email("a@b.dev\nX-Evil: 1"));
        assert!(!is_from_email("a@nodot"));
    }
}
