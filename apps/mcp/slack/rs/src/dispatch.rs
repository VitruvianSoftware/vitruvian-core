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

use crate::config::WriteTokenPreference;
use crate::json::JsonValue;
use crate::permalink::{parse_file_reference, parse_permalink, MessageRef};
use crate::slack_client::{
    CreateUserGroupInput, SlackClient, SlackClientError, UpdateUserGroupFields, UploadFileInput,
};

fn str_arg(args: &JsonValue, name: &str) -> Result<String, SlackClientError> {
    match args.get(name).and_then(|v| v.as_str()) {
        Some(s) if !s.is_empty() => Ok(s.to_string()),
        _ => Err(SlackClientError::Message(format!(
            "Argument {name} is required and must be a non-empty string."
        ))),
    }
}

fn opt_str(args: &JsonValue, name: &str) -> Result<Option<String>, SlackClientError> {
    match args.get(name) {
        None | Some(JsonValue::Null) => Ok(None),
        Some(JsonValue::String(s)) => Ok(Some(s.clone())),
        _ => Err(SlackClientError::Message(format!(
            "Argument {name} must be a string when present."
        ))),
    }
}

fn opt_num(args: &JsonValue, name: &str) -> Result<Option<usize>, SlackClientError> {
    match args.get(name) {
        None | Some(JsonValue::Null) => Ok(None),
        Some(JsonValue::Number(n)) if n.is_finite() => Ok(Some(*n as usize)),
        _ => Err(SlackClientError::Message(format!(
            "Argument {name} must be a number when present."
        ))),
    }
}

fn opt_bool(args: &JsonValue, name: &str) -> Result<Option<bool>, SlackClientError> {
    match args.get(name) {
        None | Some(JsonValue::Null) => Ok(None),
        Some(JsonValue::Bool(b)) => Ok(Some(*b)),
        _ => Err(SlackClientError::Message(format!(
            "Argument {name} must be a boolean when present."
        ))),
    }
}

fn str_array(args: &JsonValue, name: &str) -> Result<Vec<String>, SlackClientError> {
    match args.get(name).and_then(|v| v.as_array()) {
        Some(arr) if !arr.is_empty() => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                match item.as_str() {
                    Some(s) if !s.is_empty() => out.push(s.to_string()),
                    _ => {
                        return Err(SlackClientError::Message(format!(
                            "Argument {name} is required and must be a non-empty array of strings."
                        )))
                    }
                }
            }
            Ok(out)
        }
        _ => Err(SlackClientError::Message(format!(
            "Argument {name} is required and must be a non-empty array of strings."
        ))),
    }
}

fn opt_str_array(args: &JsonValue, name: &str) -> Result<Option<Vec<String>>, SlackClientError> {
    match args.get(name) {
        None | Some(JsonValue::Null) => Ok(None),
        Some(JsonValue::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                match item.as_str() {
                    Some(s) => out.push(s.to_string()),
                    None => {
                        return Err(SlackClientError::Message(format!(
                            "Argument {name} must be an array of strings when present."
                        )))
                    }
                }
            }
            Ok(Some(out))
        }
        _ => Err(SlackClientError::Message(format!(
            "Argument {name} must be an array of strings when present."
        ))),
    }
}

fn token_choice(args: &JsonValue, name: &str) -> Result<WriteTokenPreference, SlackClientError> {
    let val = opt_str(args, name)?.unwrap_or_else(|| "bot".to_string());
    match val.as_str() {
        "bot" => Ok(WriteTokenPreference::Bot),
        "user" => Ok(WriteTokenPreference::User),
        _ => Err(SlackClientError::Message(format!(
            "Argument {name} must be \"bot\" or \"user\"."
        ))),
    }
}

fn message_ref(args: &JsonValue) -> Result<MessageRef, SlackClientError> {
    if let Some(permalink) = opt_str(args, "permalink")? {
        if !permalink.is_empty() {
            return parse_permalink(&permalink).map_err(SlackClientError::InvalidPermalink);
        }
    }
    let channel_id = opt_str(args, "channel_id")?;
    let ts = opt_str(args, "timestamp")?;
    let (channel_id, ts) = match (channel_id, ts) {
        (Some(c), Some(t)) if !c.is_empty() && !t.is_empty() => (c, t),
        _ => {
            return Err(SlackClientError::Message(
                "Provide either permalink, or both channel_id and timestamp.".to_string(),
            ))
        }
    };
    let thread_ts = opt_str(args, "thread_ts")?;
    let thread_ts = match thread_ts {
        Some(ref tt) if !tt.is_empty() && tt != &ts => Some(tt.clone()),
        _ => None,
    };
    Ok(MessageRef {
        channel_id,
        ts,
        thread_ts,
    })
}

fn file_id(args: &JsonValue) -> Result<String, SlackClientError> {
    let raw = str_arg(args, "file")?;
    parse_file_reference(&raw).map_err(SlackClientError::InvalidPermalink)
}

pub const HANDLER_NAMES: &[&str] = &[
    "slack_list_channels",
    "slack_get_channel_info",
    "slack_get_channel_history",
    "slack_get_thread_replies",
    "slack_set_channel_topic",
    "slack_get_message",
    "slack_get_permalink",
    "slack_join_channel",
    "slack_leave_channel",
    "slack_list_channel_members",
    "slack_invite_to_channel",
    "slack_list_unread",
    "slack_mark_read",
    "slack_get_users",
    "slack_get_user_profile",
    "slack_search_messages",
    "slack_search_files",
    "slack_post_message",
    "slack_reply_to_thread",
    "slack_update_message",
    "slack_add_reaction",
    "slack_list_pins",
    "slack_pin_message",
    "slack_unpin_message",
    "slack_list_bookmarks",
    "slack_add_bookmark",
    "slack_create_canvas",
    "slack_edit_canvas",
    "slack_lookup_canvas_sections",
    "slack_delete_canvas",
    "slack_list_emoji",
    "slack_get_file_info",
    "slack_read_file",
    "slack_upload_file",
    "slack_download_file",
    "slack_list_user_groups",
    "slack_list_user_group_members",
    "slack_create_user_group",
    "slack_update_user_group",
    "slack_set_user_group_members",
    "slack_set_user_group_enabled",
];

pub fn handler_names() -> Vec<&'static str> {
    HANDLER_NAMES.to_vec()
}

pub fn dispatch(
    client: &SlackClient,
    name: &str,
    args: &JsonValue,
) -> Result<JsonValue, SlackClientError> {
    match name {
        // Channels
        "slack_list_channels" => {
            client.list_channels(opt_num(args, "limit")?, opt_str(args, "cursor")?.as_deref())
        }
        "slack_get_channel_info" => client.get_channel_info(&str_arg(args, "channel_id")?),
        "slack_get_channel_history" => {
            client.get_channel_history(&str_arg(args, "channel_id")?, opt_num(args, "limit")?)
        }
        "slack_get_thread_replies" => {
            client.get_thread_replies(&str_arg(args, "channel_id")?, &str_arg(args, "thread_ts")?)
        }
        "slack_set_channel_topic" => {
            client.set_channel_topic(&str_arg(args, "channel_id")?, &str_arg(args, "topic")?)
        }
        "slack_get_message" => {
            let r = message_ref(args)?;
            client.get_message(&r.channel_id, &r.ts, r.thread_ts.as_deref())
        }
        "slack_get_permalink" => {
            client.get_permalink(&str_arg(args, "channel_id")?, &str_arg(args, "timestamp")?)
        }

        // Channel membership
        "slack_join_channel" => {
            client.join_channel(&str_arg(args, "channel_id")?, token_choice(args, "as")?)
        }
        "slack_leave_channel" => {
            client.leave_channel(&str_arg(args, "channel_id")?, token_choice(args, "as")?)
        }
        "slack_list_channel_members" => client.list_channel_members(
            &str_arg(args, "channel_id")?,
            opt_num(args, "limit")?,
            opt_str(args, "cursor")?.as_deref(),
        ),
        "slack_invite_to_channel" => {
            client.invite_to_channel(&str_arg(args, "channel_id")?, &str_array(args, "user_ids")?)
        }
        "slack_list_unread" => client.list_unread(opt_num(args, "max_per_conversation")?),
        "slack_mark_read" => {
            client.mark_read(&str_arg(args, "channel_id")?, &str_arg(args, "timestamp")?)
        }

        // Users
        "slack_get_users" => {
            client.get_users(opt_num(args, "limit")?, opt_str(args, "cursor")?.as_deref())
        }
        "slack_get_user_profile" => client.get_user_profile(&str_arg(args, "user_id")?),

        // Search
        "slack_search_messages" => client.search_messages(
            &str_arg(args, "query")?,
            opt_num(args, "count")?,
            opt_str(args, "sort")?.as_deref(),
        ),
        "slack_search_files" => client.search_files(
            &str_arg(args, "query")?,
            opt_num(args, "count")?,
            opt_str(args, "sort")?.as_deref(),
        ),

        // Messaging
        "slack_post_message" => {
            client.post_message(&str_arg(args, "channel_id")?, &str_arg(args, "text")?)
        }
        "slack_reply_to_thread" => client.reply_to_thread(
            &str_arg(args, "channel_id")?,
            &str_arg(args, "thread_ts")?,
            &str_arg(args, "text")?,
        ),
        "slack_update_message" => client.update_message(
            &str_arg(args, "channel_id")?,
            &str_arg(args, "timestamp")?,
            &str_arg(args, "text")?,
        ),
        "slack_add_reaction" => client.add_reaction(
            &str_arg(args, "channel_id")?,
            &str_arg(args, "timestamp")?,
            &str_arg(args, "reaction")?,
        ),

        // Pins
        "slack_list_pins" => client.list_pins(&str_arg(args, "channel_id")?),
        "slack_pin_message" => {
            client.pin_message(&str_arg(args, "channel_id")?, &str_arg(args, "timestamp")?)
        }
        "slack_unpin_message" => {
            client.unpin_message(&str_arg(args, "channel_id")?, &str_arg(args, "timestamp")?)
        }

        // Bookmarks
        "slack_list_bookmarks" => client.list_bookmarks(&str_arg(args, "channel_id")?),
        "slack_add_bookmark" => client.add_bookmark(
            &str_arg(args, "channel_id")?,
            &str_arg(args, "title")?,
            &str_arg(args, "link")?,
            opt_str(args, "emoji")?.as_deref(),
        ),

        // Canvases
        "slack_create_canvas" => client.create_canvas(
            opt_str(args, "title")?.as_deref(),
            opt_str(args, "markdown")?.as_deref(),
            opt_str(args, "channel_id")?.as_deref(),
        ),
        "slack_edit_canvas" => client.edit_canvas(
            &str_arg(args, "canvas_id")?,
            &str_arg(args, "operation")?,
            opt_str(args, "markdown")?.as_deref(),
            opt_str(args, "section_id")?.as_deref(),
        ),
        "slack_lookup_canvas_sections" => client.lookup_canvas_sections(
            &str_arg(args, "canvas_id")?,
            opt_str_array(args, "section_types")?.as_deref(),
            opt_str(args, "contains_text")?.as_deref(),
        ),
        "slack_delete_canvas" => client.delete_canvas(&str_arg(args, "canvas_id")?),

        // Emoji
        "slack_list_emoji" => client.list_emoji(
            opt_str(args, "query")?.as_deref(),
            opt_bool(args, "include_aliases")?,
        ),

        // Files
        "slack_get_file_info" => client.get_file_info(&file_id(args)?),
        "slack_read_file" => client.read_file(&file_id(args)?, opt_num(args, "max_bytes")?),
        "slack_upload_file" => client.upload_file(UploadFileInput {
            channel_id: str_arg(args, "channel_id")?,
            filename: str_arg(args, "filename")?,
            content: opt_str(args, "content")?,
            content_base64: opt_str(args, "content_base64")?,
            title: opt_str(args, "title")?,
            initial_comment: opt_str(args, "initial_comment")?,
            thread_ts: opt_str(args, "thread_ts")?,
        }),
        "slack_download_file" => {
            client.download_file(&file_id(args)?, &str_arg(args, "output_path")?)
        }

        // User groups
        "slack_list_user_groups" => client.list_user_groups(opt_bool(args, "include_disabled")?),
        "slack_list_user_group_members" => {
            client.list_user_group_members(&str_arg(args, "usergroup_id")?)
        }
        "slack_create_user_group" => client.create_user_group(CreateUserGroupInput {
            name: str_arg(args, "name")?,
            handle: str_arg(args, "handle")?,
            description: opt_str(args, "description")?,
            channel_ids: opt_str_array(args, "channel_ids")?,
        }),
        "slack_update_user_group" => client.update_user_group(
            &str_arg(args, "usergroup_id")?,
            UpdateUserGroupFields {
                name: opt_str(args, "name")?,
                handle: opt_str(args, "handle")?,
                description: opt_str(args, "description")?,
            },
        ),
        "slack_set_user_group_members" => client.set_user_group_members(
            &str_arg(args, "usergroup_id")?,
            &str_array(args, "user_ids")?,
        ),
        "slack_set_user_group_enabled" => {
            let enabled = opt_bool(args, "enabled")?.ok_or_else(|| {
                SlackClientError::Message("Argument enabled is required.".to_string())
            })?;
            client.set_user_group_enabled(&str_arg(args, "usergroup_id")?, enabled)
        }

        _ => Err(SlackClientError::Message(format!("Unknown tool: {name}"))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::channel_allowlist::ChannelAllowlistError;
    use crate::config::resolve_config;
    use crate::slack_client::{set_mock_fetch, HttpResponse};
    use crate::tools::all_tools;
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex};

    fn stdio_env() -> HashMap<String, String> {
        let mut m = HashMap::new();
        m.insert("SLACK_BOT_TOKEN".to_string(), "xoxb-test".to_string());
        m.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        m.insert("SLACK_TEAM_ID".to_string(), "T123".to_string());
        m
    }

    fn http_env() -> HashMap<String, String> {
        let mut m = HashMap::new();
        m.insert("MCP_TRANSPORT".to_string(), "http".to_string());
        m.insert("SLACK_BOT_TOKEN".to_string(), "xoxb-test".to_string());
        m.insert("SLACK_TEAM_ID".to_string(), "T123".to_string());
        m.insert("SLACK_CHANNEL_IDS".to_string(), "C0ALLOWED1".to_string());
        m.insert(
            "OIDC_ISSUER".to_string(),
            "https://auth.example.test".to_string(),
        );
        m.insert("OIDC_PROJECT_ID".to_string(), "999".to_string());
        m.insert(
            "OIDC_ALLOWED_SUBJECTS".to_string(),
            "379361013981513322".to_string(),
        );
        m.insert(
            "OIDC_ALLOWED_CLIENT_ID".to_string(),
            "111222333".to_string(),
        );
        m
    }

    fn client_for(env: &HashMap<String, String>) -> SlackClient {
        let config = resolve_config(env).unwrap();
        SlackClient::new(config.slack, config.channel_guard, config.write_token)
    }

    #[derive(Clone, Debug)]
    struct CapturedCall {
        url: String,
        body: Option<String>,
    }

    #[test]
    fn every_advertised_tool_has_a_handler_and_vice_versa() {
        let mut tool_names: Vec<String> = all_tools()
            .into_iter()
            .map(|t| t.name.to_string())
            .collect();
        tool_names.sort();
        let mut h_names: Vec<String> = handler_names().into_iter().map(|s| s.to_string()).collect();
        h_names.sort();

        let missing: Vec<_> = tool_names.iter().filter(|n| !h_names.contains(n)).collect();
        assert!(missing.is_empty(), "Missing handlers: {missing:?}");

        let orphaned: Vec<_> = h_names.iter().filter(|n| !tool_names.contains(n)).collect();
        assert!(orphaned.is_empty(), "Orphaned handlers: {orphaned:?}");

        let err = dispatch(
            &client_for(&stdio_env()),
            "slack_no_such_tool",
            &JsonValue::object(vec![]),
        )
        .unwrap_err();
        assert!(err.to_string().contains("Unknown tool"));
    }

    #[test]
    fn handlers_pass_arguments_through_in_the_clients_shape() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(r#"{"ok":true}"#).unwrap(),
            ))
        });

        let client = client_for(&stdio_env());

        // 1. slack_mark_read
        dispatch(
            &client,
            "slack_mark_read",
            &JsonValue::parse(r#"{"channel_id":"C1","timestamp":"1712345678.123456"}"#).unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert!(recorded[0].url.contains("conversations.mark"));
            let body = JsonValue::parse(recorded[0].body.as_ref().unwrap()).unwrap();
            assert_eq!(body.get("channel").and_then(|v| v.as_str()), Some("C1"));
            assert_eq!(
                body.get("ts").and_then(|v| v.as_str()),
                Some("1712345678.123456")
            );
        }

        // 2. slack_get_channel_history
        calls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_get_channel_history",
            &JsonValue::parse(r#"{"channel_id":"C1","limit":3}"#).unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert!(recorded[0].url.contains("conversations.history"));
            assert!(recorded[0].url.contains("channel=C1"));
            assert!(recorded[0].url.contains("limit=3"));
        }

        // 3. slack_reply_to_thread
        calls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_reply_to_thread",
            &JsonValue::parse(r#"{"channel_id":"C1","thread_ts":"1.000001","text":"hi"}"#).unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert!(recorded[0].url.contains("chat.postMessage"));
            let body = JsonValue::parse(recorded[0].body.as_ref().unwrap()).unwrap();
            assert_eq!(body.get("channel").and_then(|v| v.as_str()), Some("C1"));
            assert_eq!(
                body.get("thread_ts").and_then(|v| v.as_str()),
                Some("1.000001")
            );
            assert_eq!(body.get("text").and_then(|v| v.as_str()), Some("hi"));
        }

        // 4. Rejects missing required string before calling Slack
        calls.lock().unwrap().clear();
        let err = dispatch(
            &client,
            "slack_get_channel_history",
            &JsonValue::object(vec![]),
        )
        .unwrap_err();
        assert!(err.to_string().contains("channel_id"));
        assert!(calls.lock().unwrap().is_empty());
    }

    #[test]
    fn permalinks_are_resolved_to_a_channel_before_the_guard_runs() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(r#"{"ok":true,"messages":[]}"#).unwrap(),
            ))
        });

        let client = client_for(&http_env());

        // 1. Refuses permalink into a channel outside the allow-list
        let err = dispatch(
            &client,
            "slack_get_message",
            &JsonValue::parse(
                r#"{"permalink":"https://acme.slack.com/archives/G0PRIVATE1/p1700000000123456"}"#,
            )
            .unwrap(),
        )
        .unwrap_err();
        assert!(matches!(
            err,
            SlackClientError::ChannelAllowlist(ChannelAllowlistError::ChannelNotAllowed { .. })
        ));
        assert!(calls.lock().unwrap().is_empty());

        // 2. Fetches a top-level message by its permalink
        dispatch(
            &client,
            "slack_get_message",
            &JsonValue::parse(
                r#"{"permalink":"https://acme.slack.com/archives/C0ALLOWED1/p1700000000123456"}"#,
            )
            .unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert_eq!(recorded.len(), 1);
            let url = &recorded[0].url;
            assert!(url.contains("conversations.history"));
            assert!(url.contains("channel=C0ALLOWED1"));
            assert!(url.contains("latest=1700000000.123456"));
            assert!(url.contains("oldest=1700000000.123456"));
            assert!(url.contains("inclusive=true"));
        }

        // 3. Fetches a reply through its parent thread
        calls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_get_message",
            &JsonValue::parse(
                r#"{"permalink":"https://acme.slack.com/archives/C0ALLOWED1/p1700000001000000?thread_ts=1700000000.123456"}"#,
            )
            .unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            let url = &recorded[0].url;
            assert!(url.contains("conversations.replies"));
            assert!(url.contains("ts=1700000000.123456"));
        }

        // 4. Accepts channel_id and timestamp instead of a permalink
        calls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_get_message",
            &JsonValue::parse(r#"{"channel_id":"C0ALLOWED1","timestamp":"1700000000.123456"}"#)
                .unwrap(),
        )
        .unwrap();
        assert!(calls.lock().unwrap()[0]
            .url
            .contains("conversations.history"));

        // 5. Rejects a malformed permalink without calling Slack
        calls.lock().unwrap().clear();
        let err = dispatch(
            &client,
            "slack_get_message",
            &JsonValue::parse(
                r#"{"permalink":"https://evil.example/archives/C0ALLOWED1/p1700000000123456"}"#,
            )
            .unwrap(),
        )
        .unwrap_err();
        assert!(matches!(err, SlackClientError::InvalidPermalink(_)));
        assert!(calls.lock().unwrap().is_empty());

        // 6. Requires either a permalink or channel_id plus timestamp
        let err = dispatch(&client, "slack_get_message", &JsonValue::object(vec![])).unwrap_err();
        assert!(err.to_string().contains("permalink"));
        assert!(calls.lock().unwrap().is_empty());
    }
}
