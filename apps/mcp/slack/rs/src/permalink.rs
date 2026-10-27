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

use std::fmt;

use crate::url::ParsedUrl;

/// Raised when a URL is not a Slack permalink or file link this can read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InvalidPermalinkError {
    pub input: String,
    pub reason: String,
    pub message: String,
}

impl InvalidPermalinkError {
    pub fn new(input: &str, reason: &str) -> Self {
        let message = format!(
            "Cannot parse \"{input}\" as a Slack link: {reason}. Expected the form https://<workspace>.slack.com/archives/<channel>/p<timestamp>."
        );
        Self {
            input: input.to_string(),
            reason: reason.to_string(),
            message,
        }
    }
}

impl fmt::Display for InvalidPermalinkError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for InvalidPermalinkError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MessageRef {
    pub channel_id: String,
    /// Slack message timestamp, `seconds.micros`.
    pub ts: String,
    /// Present only for a reply; the parent's timestamp.
    pub thread_ts: Option<String>,
}

fn is_channel_id(s: &str) -> bool {
    let mut chars = s.chars();
    match chars.next() {
        Some('C' | 'D' | 'G') => {}
        _ => return false,
    }
    let rest: Vec<char> = chars.collect();
    !rest.is_empty()
        && rest
            .iter()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit())
}

fn is_file_id(s: &str) -> bool {
    let mut chars = s.chars();
    if chars.next() != Some('F') {
        return false;
    }
    let rest: Vec<char> = chars.collect();
    !rest.is_empty()
        && rest
            .iter()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit())
}

fn is_slack_ts(s: &str) -> bool {
    let Some((secs, micros)) = s.split_once('.') else {
        return false;
    };
    !secs.is_empty()
        && secs.chars().all(|c| c.is_ascii_digit())
        && micros.len() == 6
        && micros.chars().all(|c| c.is_ascii_digit())
}

fn is_slack_host(hostname: &str) -> bool {
    hostname == "slack.com" || hostname.ends_with(".slack.com")
}

fn parse_url(input: &str) -> Result<ParsedUrl, InvalidPermalinkError> {
    let url =
        ParsedUrl::parse(input).map_err(|_| InvalidPermalinkError::new(input, "not a URL"))?;
    if url.protocol != "https:" {
        return Err(InvalidPermalinkError::new(input, "not an https URL"));
    }
    if !is_slack_host(&url.hostname) {
        return Err(InvalidPermalinkError::new(
            input,
            &format!("{} is not a Slack host", url.hostname),
        ));
    }
    Ok(url)
}

/// Reads channel and timestamp out of a message permalink.
pub fn parse_permalink(input: &str) -> Result<MessageRef, InvalidPermalinkError> {
    let url = parse_url(input)?;
    let trimmed_path = url.pathname.strip_suffix('/').unwrap_or(&url.pathname);
    let Some(rest) = trimmed_path.strip_prefix("/archives/") else {
        return Err(InvalidPermalinkError::new(
            input,
            "path is not /archives/<channel>/p<timestamp>",
        ));
    };
    let Some((channel_id, p_segment)) = rest.split_once('/') else {
        return Err(InvalidPermalinkError::new(
            input,
            "path is not /archives/<channel>/p<timestamp>",
        ));
    };
    if channel_id.is_empty() || p_segment.contains('/') {
        return Err(InvalidPermalinkError::new(
            input,
            "path is not /archives/<channel>/p<timestamp>",
        ));
    }
    let Some(digits) = p_segment.strip_prefix('p') else {
        return Err(InvalidPermalinkError::new(
            input,
            "path is not /archives/<channel>/p<timestamp>",
        ));
    };
    if digits.len() != 16 || !digits.chars().all(|c| c.is_ascii_digit()) {
        return Err(InvalidPermalinkError::new(
            input,
            "path is not /archives/<channel>/p<timestamp>",
        ));
    }
    if !is_channel_id(channel_id) {
        return Err(InvalidPermalinkError::new(
            input,
            &format!("{channel_id} is not a channel ID"),
        ));
    }

    let ts = format!("{}.{}", &digits[..10], &digits[10..]);
    let Some(thread_ts) = url.query_get("thread_ts") else {
        return Ok(MessageRef {
            channel_id: channel_id.to_string(),
            ts,
            thread_ts: None,
        });
    };
    if thread_ts == ts {
        return Ok(MessageRef {
            channel_id: channel_id.to_string(),
            ts,
            thread_ts: None,
        });
    }
    if !is_slack_ts(thread_ts) {
        return Err(InvalidPermalinkError::new(
            input,
            &format!("thread_ts={thread_ts} is not a Slack timestamp"),
        ));
    }
    Ok(MessageRef {
        channel_id: channel_id.to_string(),
        ts,
        thread_ts: Some(thread_ts.to_string()),
    })
}

/// Accepts either a bare file ID or a Slack file URL and returns the ID.
pub fn parse_file_reference(input: &str) -> Result<String, InvalidPermalinkError> {
    let trimmed = input.trim();
    if is_file_id(trimmed) {
        return Ok(trimmed.to_string());
    }
    if !trimmed.starts_with("https://") {
        return Err(InvalidPermalinkError::new(
            input,
            "not a file ID or file URL",
        ));
    }
    // parseUrl(trimmed): its refusals quote the trimmed input, as in TS.
    let url = parse_url(trimmed)?;
    let Some(rest) = url.pathname.strip_prefix("/files/") else {
        return Err(InvalidPermalinkError::new(
            input,
            "path is not /files/<user>/<file id>/…",
        ));
    };
    let mut parts = rest.split('/');
    let user = parts.next().unwrap_or("");
    let file_id = parts.next().unwrap_or("");
    if user.is_empty() || !is_file_id(file_id) {
        return Err(InvalidPermalinkError::new(
            input,
            "path is not /files/<user>/<file id>/…",
        ));
    }
    Ok(file_id.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_channel_and_timestamp_from_top_level_message_permalink() {
        assert_eq!(
            parse_permalink("https://acme.slack.com/archives/C0123ABCD/p1700000000123456").unwrap(),
            MessageRef {
                channel_id: "C0123ABCD".to_string(),
                ts: "1700000000.123456".to_string(),
                thread_ts: None,
            }
        );
    }

    #[test]
    fn reads_parent_thread_from_reply_permalink() {
        assert_eq!(
            parse_permalink(
                "https://acme.slack.com/archives/C0123ABCD/p1700000001000000?thread_ts=1700000000.123456&cid=C0123ABCD"
            )
            .unwrap(),
            MessageRef {
                channel_id: "C0123ABCD".to_string(),
                ts: "1700000001.000000".to_string(),
                thread_ts: Some("1700000000.123456".to_string()),
            }
        );
    }

    #[test]
    fn treats_thread_ts_equal_to_message_ts_as_top_level_message() {
        assert_eq!(
            parse_permalink(
                "https://acme.slack.com/archives/C0123ABCD/p1700000000123456?thread_ts=1700000000.123456"
            )
            .unwrap(),
            MessageRef {
                channel_id: "C0123ABCD".to_string(),
                ts: "1700000000.123456".to_string(),
                thread_ts: None,
            }
        );
    }

    #[test]
    fn accepts_group_and_dm_conversation_ids() {
        assert_eq!(
            parse_permalink("https://acme.slack.com/archives/G0PRIVATE1/p1700000000123456")
                .unwrap()
                .channel_id,
            "G0PRIVATE1"
        );
        assert_eq!(
            parse_permalink("https://acme.slack.com/archives/D0DM000001/p1700000000123456")
                .unwrap()
                .channel_id,
            "D0DM000001"
        );
    }

    #[test]
    fn accepts_enterprise_grid_hosts() {
        assert_eq!(
            parse_permalink(
                "https://acme.enterprise.slack.com/archives/C0123ABCD/p1700000000123456"
            )
            .unwrap()
            .channel_id,
            "C0123ABCD"
        );
    }

    #[test]
    fn rejects_invalid_permalinks() {
        let cases = [
            (
                "a non-Slack host",
                "https://evil.example.com/archives/C0123ABCD/p1700000000123456",
            ),
            (
                "a look-alike host",
                "https://slack.com.evil.example/archives/C0123ABCD/p1700000000123456",
            ),
            (
                "a non-archives path",
                "https://acme.slack.com/files/U1/F1/x.txt",
            ),
            (
                "a malformed timestamp",
                "https://acme.slack.com/archives/C0123ABCD/p17000",
            ),
            (
                "a lower-case channel id",
                "https://acme.slack.com/archives/c0123abcd/p1700000000123456",
            ),
            ("plain text", "not a url"),
            ("a bare channel id", "C0123ABCD"),
        ];
        for (label, input) in cases {
            assert!(
                parse_permalink(input).is_err(),
                "expected {label} ({input}) to be rejected"
            );
        }
    }

    #[test]
    fn rejects_thread_ts_that_is_not_slack_timestamp() {
        assert!(parse_permalink(
            "https://acme.slack.com/archives/C0123ABCD/p1700000000123456?thread_ts=abc"
        )
        .is_err());
    }

    #[test]
    fn passes_bare_file_id_through() {
        assert_eq!(parse_file_reference("F0123ABCD").unwrap(), "F0123ABCD");
    }

    #[test]
    fn reads_file_id_out_of_slack_file_url() {
        assert_eq!(
            parse_file_reference("https://acme.slack.com/files/U0USER/F0123ABCD/report.pdf")
                .unwrap(),
            "F0123ABCD"
        );
    }

    #[test]
    fn rejects_invalid_file_references() {
        let cases = [
            (
                "a non-Slack host",
                "https://evil.example.com/files/U0USER/F0123ABCD/x.pdf",
            ),
            (
                "a message permalink",
                "https://acme.slack.com/archives/C0123ABCD/p1700000000123456",
            ),
            ("an empty string", ""),
            ("a channel id", "C0123ABCD"),
        ];
        for (label, input) in cases {
            assert!(
                parse_file_reference(input).is_err(),
                "expected {label} ({input}) to be rejected"
            );
        }
    }

    #[test]
    fn file_reference_errors_quote_what_typescript_quoted() {
        // A URL refusal from parseUrl(trimmed) quotes the trimmed input...
        let err =
            parse_file_reference("  https://evil.example.com/files/U1/F0123ABCD/x  ").unwrap_err();
        assert!(err
            .message
            .starts_with("Cannot parse \"https://evil.example.com/files/U1/F0123ABCD/x\" as"));
        assert!(err.message.contains("evil.example.com is not a Slack host"));
        // ...while the other two refusals quote the input as given.
        let err = parse_file_reference(" nope ").unwrap_err();
        assert!(err.message.starts_with("Cannot parse \" nope \" as"));
        let err = parse_file_reference(" https://acme.slack.com/archives/C1/p1700000000123456 ")
            .unwrap_err();
        assert!(err.message.starts_with(
            "Cannot parse \" https://acme.slack.com/archives/C1/p1700000000123456 \""
        ));
        assert!(err.message.contains("path is not /files/"));
    }

    #[test]
    fn permalinks_with_surrounding_whitespace_parse_as_new_url_would() {
        assert_eq!(
            parse_permalink("https://acme.slack.com/archives/C0123ABCD/p1700000000123456\n")
                .unwrap()
                .channel_id,
            "C0123ABCD"
        );
    }
}
