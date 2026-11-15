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
    ChannelHistoryOptions, CreateUserGroupInput, ListScheduledMessagesOptions, PostMessageOptions,
    ReplyToThreadOptions, ScheduleMessageOptions, SearchOptions, SlackClient, SlackClientError,
    ThreadRepliesOptions, UpdateUserGroupFields, UploadFileInput,
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

/// The number exactly as sent. dispatch.ts handed it to the client
/// unchanged, so Slack received `-1`, `0` or `0.5` as written; converting to
/// an integer here would clamp negatives to 0 and truncate fractions.
fn opt_num(args: &JsonValue, name: &str) -> Result<Option<f64>, SlackClientError> {
    match args.get(name) {
        None | Some(JsonValue::Null) => Ok(None),
        Some(JsonValue::Number(n)) if n.is_finite() => Ok(Some(*n)),
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

fn message_ref(client: &SlackClient, args: &JsonValue) -> Result<MessageRef, SlackClientError> {
    if let Some(permalink) = opt_str(args, "permalink")? {
        if !permalink.is_empty() {
            return parse_permalink(&permalink).map_err(SlackClientError::InvalidPermalink);
        }
    }
    let channel_id = opt_str(args, "channel_id")?;
    let ts = opt_str(args, "timestamp")?;
    let (raw_channel_id, ts) = match (channel_id, ts) {
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
    let channel_id = client.resolve_channel_id(&raw_channel_id)?;
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

fn channel_arg(
    client: &SlackClient,
    args: &JsonValue,
    name: &str,
) -> Result<String, SlackClientError> {
    let raw = str_arg(args, name)?;
    client.resolve_channel_id(&raw)
}

fn opt_channel_arg(
    client: &SlackClient,
    args: &JsonValue,
    name: &str,
) -> Result<Option<String>, SlackClientError> {
    match opt_str(args, name)? {
        None => Ok(None),
        Some(s) if s.is_empty() => Ok(Some(s)),
        Some(s) => Ok(Some(client.resolve_channel_id(&s)?)),
    }
}

fn resolve_channel_list(
    client: &SlackClient,
    raw: Option<Vec<String>>,
) -> Result<Option<Vec<String>>, SlackClientError> {
    match raw {
        None => Ok(None),
        Some(items) => {
            let mut out = Vec::with_capacity(items.len());
            for item in items {
                if item.is_empty() {
                    out.push(item);
                } else {
                    out.push(client.resolve_channel_id(&item)?);
                }
            }
            Ok(Some(out))
        }
    }
}

fn resolve_users(
    client: &SlackClient,
    raw_users: &[String],
) -> Result<Vec<String>, SlackClientError> {
    let mut out = Vec::with_capacity(raw_users.len());
    for u in raw_users {
        out.push(client.resolve_user_id(u)?);
    }
    Ok(out)
}

fn post_at_arg(args: &JsonValue, name: &str) -> Result<String, SlackClientError> {
    match args.get(name) {
        Some(JsonValue::String(s)) if !s.is_empty() => Ok(s.clone()),
        Some(JsonValue::Number(n)) if n.is_finite() && n.fract() == 0.0 => {
            if *n >= (i64::MIN as f64) && *n < 9_223_372_036_854_775_808.0 {
                Ok((*n as i64).to_string())
            } else {
                Err(SlackClientError::Message(format!(
                    "Invalid post_at value {n}: Unix timestamp out of 64-bit integer range."
                )))
            }
        }
        _ => Err(SlackClientError::Message(format!(
            "Argument {name} is required and must be a Unix timestamp (seconds) or ISO 8601 date-time with timezone offset."
        ))),
    }
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
    "slack_whoami",
    "slack_search_messages",
    "slack_search_files",
    "slack_post_message",
    "slack_reply_to_thread",
    "slack_update_message",
    "slack_add_reaction",
    "slack_remove_reaction",
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
    "slack_open_dm",
    "slack_schedule_message",
    "slack_list_scheduled_messages",
    "slack_delete_scheduled_message",
];

pub fn handler_names() -> Vec<&'static str> {
    HANDLER_NAMES.to_vec()
}

pub fn dispatch(
    client: &SlackClient,
    name: &str,
    args: &JsonValue,
) -> Result<JsonValue, SlackClientError> {
    let _ = opt_bool(args, "compact")?;
    match name {
        // Channels
        "slack_list_channels" => {
            client.list_channels_num(opt_num(args, "limit")?, opt_str(args, "cursor")?.as_deref())
        }
        "slack_get_channel_info" => {
            client.get_channel_info(&channel_arg(client, args, "channel_id")?)
        }
        "slack_get_channel_history" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let opts = ChannelHistoryOptions {
                limit: opt_num(args, "limit")?,
                oldest: opt_str(args, "oldest")?,
                latest: opt_str(args, "latest")?,
                since: opt_str(args, "since")?,
                cursor: opt_str(args, "cursor")?,
                include_activity: opt_bool(args, "include_activity")?,
            };
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.get_channel_history_with_options(&cid, opts)
        }
        "slack_get_thread_replies" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let thread_ts = str_arg(args, "thread_ts")?;
            let opts = ThreadRepliesOptions {
                limit: opt_num(args, "limit")?,
                cursor: opt_str(args, "cursor")?,
                oldest: opt_str(args, "oldest")?,
                latest: opt_str(args, "latest")?,
            };
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.get_thread_replies_with_options(&cid, &thread_ts, opts)
        }
        "slack_set_channel_topic" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let topic = str_arg(args, "topic")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.set_channel_topic(&cid, &topic)
        }
        "slack_get_message" => {
            let r = message_ref(client, args)?;
            client.get_message(&r.channel_id, &r.ts, r.thread_ts.as_deref())
        }
        "slack_get_permalink" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let ts = str_arg(args, "timestamp")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.get_permalink(&cid, &ts)
        }

        // Channel membership
        "slack_join_channel" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let as_tok = token_choice(args, "as")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.join_channel(&cid, as_tok)
        }
        "slack_leave_channel" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let as_tok = token_choice(args, "as")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.leave_channel(&cid, as_tok)
        }
        "slack_list_channel_members" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let limit = opt_num(args, "limit")?;
            let cursor = opt_str(args, "cursor")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.list_channel_members_num(&cid, limit, cursor.as_deref())
        }
        "slack_invite_to_channel" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let raw_uids = str_array(args, "user_ids")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            let uids = resolve_users(client, &raw_uids)?;
            client.invite_to_channel(&cid, &uids)
        }
        "slack_list_unread" => client.list_unread_num(opt_num(args, "max_per_conversation")?),
        "slack_mark_read" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let ts = str_arg(args, "timestamp")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.mark_read(&cid, &ts)
        }

        // Users
        "slack_get_users" => {
            client.get_users_num(opt_num(args, "limit")?, opt_str(args, "cursor")?.as_deref())
        }
        "slack_get_user_profile" => {
            let raw_uid = str_arg(args, "user_id")?;
            let uid = client.resolve_user_id(&raw_uid)?;
            client.get_user_profile(&uid)
        }
        "slack_whoami" => client.whoami(),

        // Search
        "slack_search_messages" => client.search_messages_with_options(
            &str_arg(args, "query")?,
            SearchOptions {
                count: opt_num(args, "count")?,
                sort: opt_str(args, "sort")?,
                sort_dir: opt_str(args, "sort_dir")?,
                page: opt_num(args, "page")?,
            },
        ),
        "slack_search_files" => client.search_files_with_options(
            &str_arg(args, "query")?,
            SearchOptions {
                count: opt_num(args, "count")?,
                sort: opt_str(args, "sort")?,
                sort_dir: opt_str(args, "sort_dir")?,
                page: opt_num(args, "page")?,
            },
        ),

        // Messaging
        "slack_post_message" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let text = str_arg(args, "text")?;
            let opts = PostMessageOptions {
                thread_ts: opt_str(args, "thread_ts")?,
                reply_broadcast: opt_bool(args, "reply_broadcast")?,
                unfurl_links: opt_bool(args, "unfurl_links")?,
            };
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.post_message_with_options(&cid, &text, opts)
        }
        "slack_reply_to_thread" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let thread_ts = str_arg(args, "thread_ts")?;
            let text = str_arg(args, "text")?;
            let opts = ReplyToThreadOptions {
                reply_broadcast: opt_bool(args, "reply_broadcast")?,
                unfurl_links: opt_bool(args, "unfurl_links")?,
            };
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.reply_to_thread_with_options(&cid, &thread_ts, &text, opts)
        }
        "slack_update_message" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let ts = str_arg(args, "timestamp")?;
            let text = str_arg(args, "text")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.update_message(&cid, &ts, &text)
        }
        "slack_add_reaction" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let ts = str_arg(args, "timestamp")?;
            let reaction = str_arg(args, "reaction")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.add_reaction(&cid, &ts, &reaction)
        }
        "slack_remove_reaction" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let ts = str_arg(args, "timestamp")?;
            let emoji = str_arg(args, "emoji")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.remove_reaction(&cid, &ts, &emoji)
        }

        // Pins
        "slack_list_pins" => client.list_pins(&channel_arg(client, args, "channel_id")?),
        "slack_pin_message" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let ts = str_arg(args, "timestamp")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.pin_message(&cid, &ts)
        }
        "slack_unpin_message" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let ts = str_arg(args, "timestamp")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.unpin_message(&cid, &ts)
        }

        // Bookmarks
        "slack_list_bookmarks" => client.list_bookmarks(&channel_arg(client, args, "channel_id")?),
        "slack_add_bookmark" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let title = str_arg(args, "title")?;
            let link = str_arg(args, "link")?;
            let emoji = opt_str(args, "emoji")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.add_bookmark(&cid, &title, &link, emoji.as_deref())
        }

        // Canvases
        "slack_create_canvas" => {
            let title = opt_str(args, "title")?;
            let markdown = opt_str(args, "markdown")?;
            let cid = opt_channel_arg(client, args, "channel_id")?;
            client.create_canvas(title.as_deref(), markdown.as_deref(), cid.as_deref())
        }
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
        "slack_read_file" => client.read_file_num(&file_id(args)?, opt_num(args, "max_bytes")?),
        "slack_upload_file" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let filename = str_arg(args, "filename")?;
            let content = opt_str(args, "content")?;
            let content_base64 = opt_str(args, "content_base64")?;
            let title = opt_str(args, "title")?;
            let initial_comment = opt_str(args, "initial_comment")?;
            let thread_ts = opt_str(args, "thread_ts")?;
            let channel_id = client.resolve_channel_id(&raw_cid)?;
            client.upload_file(UploadFileInput {
                channel_id,
                filename,
                content,
                content_base64,
                title,
                initial_comment,
                thread_ts,
            })
        }
        "slack_download_file" => {
            client.download_file(&file_id(args)?, &str_arg(args, "output_path")?)
        }

        // User groups
        "slack_list_user_groups" => client.list_user_groups(opt_bool(args, "include_disabled")?),
        "slack_list_user_group_members" => {
            client.list_user_group_members(&str_arg(args, "usergroup_id")?)
        }
        "slack_create_user_group" => {
            let name_arg = str_arg(args, "name")?;
            let handle = str_arg(args, "handle")?;
            let description = opt_str(args, "description")?;
            let raw_cids = opt_str_array(args, "channel_ids")?;
            let channel_ids = resolve_channel_list(client, raw_cids)?;
            client.create_user_group(CreateUserGroupInput {
                name: name_arg,
                handle,
                description,
                channel_ids,
            })
        }
        "slack_update_user_group" => client.update_user_group(
            &str_arg(args, "usergroup_id")?,
            UpdateUserGroupFields {
                name: opt_str(args, "name")?,
                handle: opt_str(args, "handle")?,
                description: opt_str(args, "description")?,
            },
        ),
        "slack_set_user_group_members" => {
            let ug_id = str_arg(args, "usergroup_id")?;
            let raw_uids = str_array(args, "user_ids")?;
            let uids = resolve_users(client, &raw_uids)?;
            client.set_user_group_members(&ug_id, &uids)
        }
        "slack_set_user_group_enabled" => {
            let enabled = opt_bool(args, "enabled")?.ok_or_else(|| {
                SlackClientError::Message("Argument enabled is required.".to_string())
            })?;
            client.set_user_group_enabled(&str_arg(args, "usergroup_id")?, enabled)
        }

        // Direct messages & scheduled messages
        "slack_open_dm" => {
            let raw_users = str_array(args, "users")?;
            if raw_users.len() > 8 {
                return Err(SlackClientError::Message(format!(
                    "Argument users must contain between 1 and 8 user IDs or @handles (got {}).",
                    raw_users.len()
                )));
            }
            let resolved = resolve_users(client, &raw_users)?;
            client.open_dm(&resolved)
        }
        "slack_schedule_message" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let text = str_arg(args, "text")?;
            let post_at = post_at_arg(args, "post_at")?;
            let opts = ScheduleMessageOptions {
                thread_ts: opt_str(args, "thread_ts")?,
                reply_broadcast: opt_bool(args, "reply_broadcast")?,
            };
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.schedule_message(&cid, &text, &post_at, opts)
        }
        "slack_list_scheduled_messages" => {
            let raw_cid = opt_str(args, "channel_id")?;
            let cursor = opt_str(args, "cursor")?;
            let limit = opt_num(args, "limit")?;
            let channel_id = match raw_cid {
                None => None,
                Some(s) if s.is_empty() => Some(s),
                Some(s) => Some(client.resolve_channel_id(&s)?),
            };
            client.list_scheduled_messages(ListScheduledMessagesOptions {
                channel_id,
                cursor,
                limit,
            })
        }
        "slack_delete_scheduled_message" => {
            let raw_cid = str_arg(args, "channel_id")?;
            let scheduled_message_id = str_arg(args, "scheduled_message_id")?;
            let cid = client.resolve_channel_id(&raw_cid)?;
            client.delete_scheduled_message(&cid, &scheduled_message_id)
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

    #[test]
    fn numeric_arguments_reach_slack_as_javascript_wrote_them() {
        let urls: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
        let urls_ref = urls.clone();
        let _guard = set_mock_fetch(move |req| {
            urls_ref.lock().unwrap().push(req.url.clone());
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(r#"{"ok":true,"channels":[{"id":"C1"}],"channel":{"last_read":"1.0"},"messages":[{"ts":"2.0"}]}"#)
                    .unwrap(),
            ))
        });
        let client = client_for(&stdio_env());
        let query_of = |tool: &str, args: &str, key: &str| -> String {
            urls.lock().unwrap().clear();
            dispatch(&client, tool, &JsonValue::parse(args).unwrap()).unwrap();
            let recorded = urls.lock().unwrap();
            let url = recorded.last().unwrap();
            crate::url::ParsedUrl::parse(url)
                .unwrap()
                .query_get(key)
                .unwrap()
                .to_string()
        };
        // Passed through as String(n): negatives, zero and fractions intact.
        let hist = "slack_get_channel_history";
        assert_eq!(
            query_of(hist, r#"{"channel_id":"C1","limit":-1}"#, "limit"),
            "-1"
        );
        assert_eq!(
            query_of(hist, r#"{"channel_id":"C1","limit":0.5}"#, "limit"),
            "0.5"
        );
        assert_eq!(
            query_of(hist, r#"{"channel_id":"C1","limit":0}"#, "limit"),
            "0"
        );
        assert_eq!(
            query_of(hist, r#"{"channel_id":"C1","limit":1e21}"#, "limit"),
            "1e+21"
        );
        assert_eq!(query_of(hist, r#"{"channel_id":"C1"}"#, "limit"), "10");
        // Math.min(limit, 200) where the client bounds it.
        let list = "slack_list_channels";
        assert_eq!(query_of(list, r#"{"limit":-5}"#, "limit"), "-5");
        assert_eq!(query_of(list, r#"{"limit":2.5}"#, "limit"), "2.5");
        assert_eq!(query_of(list, r#"{"limit":500}"#, "limit"), "200");
        assert_eq!(query_of("slack_get_users", r#"{"limit":-0}"#, "limit"), "0");
        assert_eq!(
            query_of(
                "slack_search_messages",
                r#"{"query":"q","count":7.25}"#,
                "count"
            ),
            "7.25"
        );
        assert_eq!(
            query_of(
                "slack_search_files",
                r#"{"query":"q","count":101}"#,
                "count"
            ),
            "100"
        );
        assert_eq!(
            query_of(
                "slack_list_channel_members",
                r#"{"channel_id":"C1","limit":-3}"#,
                "limit"
            ),
            "-3"
        );
        // Math.min(Math.max(1, n), 200) for the unread page size.
        let unread = "slack_list_unread";
        assert_eq!(
            query_of(unread, r#"{"max_per_conversation":0.5}"#, "limit"),
            "1"
        );
        assert_eq!(
            query_of(unread, r#"{"max_per_conversation":1.5}"#, "limit"),
            "1.5"
        );
        assert_eq!(
            query_of(unread, r#"{"max_per_conversation":900}"#, "limit"),
            "200"
        );
        // Non-numbers are still refused before any call.
        let err = dispatch(
            &client,
            hist,
            &JsonValue::parse(r#"{"channel_id":"C1","limit":"5"}"#).unwrap(),
        )
        .unwrap_err();
        assert!(err.to_string().contains("must be a number"));
    }

    #[test]
    fn channel_history_paging_since_and_opt_in_activity_filtering() {
        let urls: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
        let urls_ref = urls.clone();
        let _guard = set_mock_fetch(move |req| {
            urls_ref.lock().unwrap().push(req.url.clone());
            let cursor = if req.url.contains("cursor=page2") {
                ""
            } else {
                "cursor_next_123"
            };
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(&format!(
                    r#"{{"ok":true,"messages":[{{"ts":"1.0","text":"hello"}},{{"ts":"2.0","subtype":"channel_join","text":"joined"}},{{"ts":"3.0","subtype":"channel_leave","text":"left"}},{{"ts":"4.0","subtype":"group_join","text":"gjoined"}},{{"ts":"5.0","subtype":"group_leave","text":"gleft"}},{{"ts":"6.0","subtype":"bot_message","text":"alert"}}],"response_metadata":{{"next_cursor":"{cursor}"}}}}"#
                ))
                .unwrap(),
            ))
        });

        let client = client_for(&stdio_env());

        // Default: include_activity is true (all 6 messages kept), Slack's response_metadata kept without top-level next_cursor.
        let default_res = dispatch(
            &client,
            "slack_get_channel_history",
            &JsonValue::parse(r#"{"channel_id":"C1"}"#).unwrap(),
        )
        .unwrap();
        assert_eq!(
            default_res
                .get("messages")
                .and_then(|v| v.as_array())
                .unwrap()
                .len(),
            6
        );
        assert!(!default_res.contains_key("next_cursor"));
        assert_eq!(
            default_res
                .get("response_metadata")
                .and_then(|m| m.get("next_cursor"))
                .and_then(|v| v.as_str()),
            Some("cursor_next_123")
        );

        // include_activity: false drops join/leave subtypes while keeping regular + bot messages.
        urls.lock().unwrap().clear();
        let filtered_res = dispatch(
            &client,
            "slack_get_channel_history",
            &JsonValue::parse(
                r#"{"channel_id":"C1","include_activity":false,"oldest":"100.0","latest":"200.0","since":"not-parsed-when-oldest-set","cursor":"page2"}"#,
            )
            .unwrap(),
        )
        .unwrap();
        let kept = filtered_res
            .get("messages")
            .and_then(|v| v.as_array())
            .unwrap();
        assert_eq!(kept.len(), 2);
        assert_eq!(kept[0].get("ts").and_then(|v| v.as_str()), Some("1.0"));
        assert_eq!(kept[1].get("ts").and_then(|v| v.as_str()), Some("6.0"));
        // Empty response_metadata.next_cursor does not emit top-level next_cursor.
        assert!(!filtered_res.contains_key("next_cursor"));
        {
            let recorded = urls.lock().unwrap();
            let parsed = crate::url::ParsedUrl::parse(&recorded[0]).unwrap();
            assert_eq!(parsed.query_get("oldest"), Some("100.0"));
            assert_eq!(parsed.query_get("latest"), Some("200.0"));
            assert_eq!(parsed.query_get("cursor"), Some("page2"));
        }

        // since converts to oldest when oldest is omitted.
        urls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_get_channel_history",
            &JsonValue::parse(r#"{"channel_id":"C1","since":"24h"}"#).unwrap(),
        )
        .unwrap();
        {
            let recorded = urls.lock().unwrap();
            let parsed = crate::url::ParsedUrl::parse(&recorded[0]).unwrap();
            let oldest_val: f64 = parsed.query_get("oldest").unwrap().parse().unwrap();
            assert!(oldest_val > 1_000_000_000.0);
        }

        // Invalid since fails before calling Slack.
        urls.lock().unwrap().clear();
        let err = dispatch(
            &client,
            "slack_get_channel_history",
            &JsonValue::parse(r#"{"channel_id":"C1","since":"yesterday"}"#).unwrap(),
        )
        .unwrap_err();
        assert!(err.to_string().contains("Invalid since value"));
        assert!(urls.lock().unwrap().is_empty());
    }

    #[test]
    fn thread_replies_sends_limit_only_when_passed_without_top_level_next_cursor() {
        let urls: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
        let urls_ref = urls.clone();
        let _guard = set_mock_fetch(move |req| {
            urls_ref.lock().unwrap().push(req.url.clone());
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(
                    r#"{"ok":true,"messages":[{"ts":"1.0"}],"response_metadata":{"next_cursor":"thread_cur"}}"#,
                )
                .unwrap(),
            ))
        });

        let client = client_for(&stdio_env());

        // Without limit: no limit query param sent to Slack, and no top-level next_cursor added.
        let res = dispatch(
            &client,
            "slack_get_thread_replies",
            &JsonValue::parse(r#"{"channel_id":"C1","thread_ts":"1.0"}"#).unwrap(),
        )
        .unwrap();
        assert!(!res.contains_key("next_cursor"));
        assert_eq!(
            res.get("response_metadata")
                .and_then(|m| m.get("next_cursor"))
                .and_then(|v| v.as_str()),
            Some("thread_cur")
        );
        {
            let parsed = crate::url::ParsedUrl::parse(&urls.lock().unwrap()[0]).unwrap();
            assert_eq!(parsed.query_get("limit"), None);
            assert_eq!(parsed.query_get("cursor"), None);
        }

        // With limit > 200 and paging bounds: clamped to 200 and forwarded.
        urls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_get_thread_replies",
            &JsonValue::parse(
                r#"{"channel_id":"C1","thread_ts":"1.0","limit":500,"cursor":"c2","oldest":"1.1","latest":"9.9"}"#,
            )
            .unwrap(),
        )
        .unwrap();
        {
            let parsed = crate::url::ParsedUrl::parse(&urls.lock().unwrap()[0]).unwrap();
            assert_eq!(parsed.query_get("limit"), Some("200"));
            assert_eq!(parsed.query_get("cursor"), Some("c2"));
            assert_eq!(parsed.query_get("oldest"), Some("1.1"));
            assert_eq!(parsed.query_get("latest"), Some("9.9"));
        }
    }

    #[test]
    fn search_tools_forward_page_and_sort_dir_and_validate_inputs() {
        let urls: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
        let urls_ref = urls.clone();
        let _guard = set_mock_fetch(move |req| {
            urls_ref.lock().unwrap().push(req.url.clone());
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(r#"{"ok":true,"messages":{"matches":[]},"files":{"matches":[]}}"#)
                    .unwrap(),
            ))
        });

        let client = client_for(&stdio_env());

        for tool in ["slack_search_messages", "slack_search_files"] {
            urls.lock().unwrap().clear();
            dispatch(
                &client,
                tool,
                &JsonValue::parse(
                    r#"{"query":"incident","page":3,"sort":"timestamp","sort_dir":"asc"}"#,
                )
                .unwrap(),
            )
            .unwrap();
            let parsed = crate::url::ParsedUrl::parse(&urls.lock().unwrap()[0]).unwrap();
            assert_eq!(parsed.query_get("page"), Some("3"));
            assert_eq!(parsed.query_get("sort_dir"), Some("asc"));

            urls.lock().unwrap().clear();
            assert!(dispatch(
                &client,
                tool,
                &JsonValue::parse(r#"{"query":"incident","page":0}"#).unwrap(),
            )
            .is_err());
            assert!(dispatch(
                &client,
                tool,
                &JsonValue::parse(r#"{"query":"incident","sort_dir":"sideways"}"#).unwrap(),
            )
            .is_err());
            assert!(urls.lock().unwrap().is_empty());
        }
    }

    #[test]
    fn whoami_remove_reaction_and_messaging_options_dispatch_correctly() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(r#"{"ok":true,"user_id":"U1","team_id":"T123"}"#).unwrap(),
            ))
        });

        let client = client_for(&stdio_env());

        // D1: slack_whoami calls auth.test for bot + user when user token is configured.
        let who = dispatch(&client, "slack_whoami", &JsonValue::empty_object()).unwrap();
        assert_eq!(
            who.get("bot")
                .and_then(|b| b.get("user_id"))
                .and_then(|v| v.as_str()),
            Some("U1")
        );
        assert_eq!(
            who.get("user")
                .and_then(|u| u.get("team_id"))
                .and_then(|v| v.as_str()),
            Some("T123")
        );
        assert_eq!(calls.lock().unwrap().len(), 2);

        // D2: slack_remove_reaction sends channel, timestamp, and name=emoji to reactions.remove.
        calls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_remove_reaction",
            &JsonValue::parse(
                r#"{"channel_id":"C1","timestamp":"1700000000.000100","emoji":"thumbsup"}"#,
            )
            .unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert_eq!(recorded.len(), 1);
            assert!(recorded[0].url.contains("/api/reactions.remove"));
            let body = JsonValue::parse(recorded[0].body.as_ref().unwrap()).unwrap();
            assert_eq!(body.get("channel").and_then(|v| v.as_str()), Some("C1"));
            assert_eq!(
                body.get("timestamp").and_then(|v| v.as_str()),
                Some("1700000000.000100")
            );
            assert_eq!(body.get("name").and_then(|v| v.as_str()), Some("thumbsup"));
        }

        // D3: slack_post_message default sends only channel + text; optional thread_ts,
        // reply_broadcast, unfurl_links forwarded when provided.
        calls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_post_message",
            &JsonValue::parse(r#"{"channel_id":"C1","text":"plain"}"#).unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            let body = JsonValue::parse(recorded[0].body.as_ref().unwrap()).unwrap();
            assert_eq!(body.as_object().unwrap().len(), 2);
        }

        calls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_post_message",
            &JsonValue::parse(
                r#"{"channel_id":"C1","text":"broadcast","thread_ts":"1.23","reply_broadcast":true,"unfurl_links":false}"#,
            )
            .unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            let body = JsonValue::parse(recorded[0].body.as_ref().unwrap()).unwrap();
            assert_eq!(body.get("thread_ts").and_then(|v| v.as_str()), Some("1.23"));
            assert_eq!(
                body.get("reply_broadcast").and_then(|v| v.as_bool()),
                Some(true)
            );
            assert_eq!(
                body.get("unfurl_links").and_then(|v| v.as_bool()),
                Some(false)
            );
        }

        // D3: slack_reply_to_thread forwards optional reply_broadcast and unfurl_links.
        calls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_reply_to_thread",
            &JsonValue::parse(
                r#"{"channel_id":"C1","thread_ts":"1.23","text":"reply","reply_broadcast":true,"unfurl_links":false}"#,
            )
            .unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            let body = JsonValue::parse(recorded[0].body.as_ref().unwrap()).unwrap();
            assert_eq!(
                body.get("reply_broadcast").and_then(|v| v.as_bool()),
                Some(true)
            );
            assert_eq!(
                body.get("unfurl_links").and_then(|v| v.as_bool()),
                Some(false)
            );
        }
    }

    #[test]
    fn bare_ids_do_not_trigger_conversations_list_or_users_list() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(
                    r#"{"ok":true,"channel":{"id":"D0DM123"},"messages":[{"ts":"1700000000.123456"}],"scheduled_messages":[]}"#,
                )
                .unwrap(),
            ))
        });

        let client = client_for(&stdio_env());
        let future_unix = (std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs()
            + 3600)
            .to_string();

        dispatch(
            &client,
            "slack_get_channel_history",
            &JsonValue::parse(r#"{"channel_id":"C0123ABCD"}"#).unwrap(),
        )
        .unwrap();
        dispatch(
            &client,
            "slack_post_message",
            &JsonValue::parse(r#"{"channel_id":"G0123PRIV","text":"hi"}"#).unwrap(),
        )
        .unwrap();
        dispatch(
            &client,
            "slack_mark_read",
            &JsonValue::parse(r#"{"channel_id":"D0123DM","timestamp":"1700000000.123456"}"#)
                .unwrap(),
        )
        .unwrap();
        dispatch(
            &client,
            "slack_get_user_profile",
            &JsonValue::parse(r#"{"user_id":"U0123USER"}"#).unwrap(),
        )
        .unwrap();
        dispatch(
            &client,
            "slack_invite_to_channel",
            &JsonValue::parse(r#"{"channel_id":"C0123ABCD","user_ids":["U0123USER","W0456GRID"]}"#)
                .unwrap(),
        )
        .unwrap();
        dispatch(
            &client,
            "slack_open_dm",
            &JsonValue::parse(r#"{"users":["U0123USER"]}"#).unwrap(),
        )
        .unwrap();
        dispatch(
            &client,
            "slack_schedule_message",
            &JsonValue::object(vec![
                ("channel_id", "C0123ABCD".into()),
                ("text", "later".into()),
                ("post_at", future_unix.as_str().into()),
            ]),
        )
        .unwrap();
        dispatch(
            &client,
            "slack_delete_scheduled_message",
            &JsonValue::parse(r#"{"channel_id":"C0123ABCD","scheduled_message_id":"Q1234ABCD"}"#)
                .unwrap(),
        )
        .unwrap();

        let recorded = calls.lock().unwrap();
        let listing_calls: Vec<&str> = recorded
            .iter()
            .map(|c| c.url.as_str())
            .filter(|u| {
                u.contains("conversations.list")
                    || u.contains("conversations.info")
                    || u.contains("users.list")
            })
            .collect();
        assert_eq!(
            listing_calls.len(),
            0,
            "Bare IDs must never trigger lookup calls, got: {listing_calls:?}"
        );
    }

    #[test]
    fn channel_name_resolves_caches_and_enforces_allowlist_without_leaking_existence() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            if req.url.contains("conversations.list") {
                if req.url.contains("cursor=cur_page2") {
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::parse(
                            r#"{"ok":true,"channels":[{"id":"G_OPS","name":"ops-private","is_private":true}],"response_metadata":{"next_cursor":""}}"#,
                        )
                        .unwrap(),
                    ));
                }
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{"ok":true,"channels":[{"id":"C_GEN","name":"general","is_private":false},{"id":"C_RAND","name":"random","is_private":false}],"response_metadata":{"next_cursor":"cur_page2"}}"#,
                    )
                    .unwrap(),
                ));
            }
            if req.url.contains("conversations.info") {
                if req.url.contains("channel=C0ALLOWED1") {
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::parse(
                            r#"{"ok":true,"channel":{"id":"C0ALLOWED1","name":"allowed-room","is_private":false}}"#,
                        )
                        .unwrap(),
                    ));
                }
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(r#"{"ok":false,"error":"channel_not_found"}"#).unwrap(),
                ));
            }
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(r#"{"ok":true,"messages":[{"ts":"1700000000.123456"}]}"#).unwrap(),
            ))
        });

        // 1. Unrestricted: #General (case-insensitive) stops at page 1 and caches.
        let unrestricted = client_for(&stdio_env());
        dispatch(
            &unrestricted,
            "slack_get_channel_history",
            &JsonValue::parse(r##"{"channel_id":"#General"}"##).unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            let list_calls: Vec<_> = recorded
                .iter()
                .filter(|c| c.url.contains("conversations.list"))
                .collect();
            assert_eq!(list_calls.len(), 1, "must stop paging once found on page 1");
            assert!(recorded.last().unwrap().url.contains("channel=C_GEN"));
        }

        // Cached hit: 0 conversations.list calls on #general and #random.
        calls.lock().unwrap().clear();
        dispatch(
            &unrestricted,
            "slack_post_message",
            &JsonValue::parse(r##"{"channel_id":"#general","text":"cached"}"##).unwrap(),
        )
        .unwrap();
        dispatch(
            &unrestricted,
            "slack_get_message",
            &JsonValue::parse(r##"{"channel_id":"#random","timestamp":"1700000000.123456"}"##)
                .unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert!(recorded
                .iter()
                .all(|c| !c.url.contains("conversations.list")));
        }

        // Page 2 channel (#OPS-PRIVATE) resolves by paging further.
        calls.lock().unwrap().clear();
        dispatch(
            &unrestricted,
            "slack_set_channel_topic",
            &JsonValue::parse(r##"{"channel_id":"#OPS-PRIVATE","topic":"oncall"}"##).unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            let body = JsonValue::parse(recorded.last().unwrap().body.as_ref().unwrap()).unwrap();
            assert_eq!(body.get("channel").and_then(|v| v.as_str()), Some("G_OPS"));
        }

        // Unrestricted miss returns `channel_not_found: #name` after re-listing once.
        calls.lock().unwrap().clear();
        let miss_err = dispatch(
            &unrestricted,
            "slack_get_channel_info",
            &JsonValue::parse(r##"{"channel_id":"#no-such-room"}"##).unwrap(),
        )
        .unwrap_err();
        assert_eq!(miss_err.to_string(), "channel_not_found: #no-such-room");
        {
            let recorded = calls.lock().unwrap();
            let list_count = recorded
                .iter()
                .filter(|c| c.url.contains("conversations.list"))
                .count();
            assert_eq!(list_count, 2, "a miss re-lists the 2-page workspace once");
        }

        // 2. Restricted guard: resolves ONLY via conversations.info on allowed IDs (never conversations.list),
        // caches the allowed channel name, and refuses non-allowed #names with the exact ID refusal text.
        calls.lock().unwrap().clear();
        let restricted = client_for(&http_env());
        dispatch(
            &restricted,
            "slack_get_channel_history",
            &JsonValue::parse(r##"{"channel_id":"#Allowed-Room"}"##).unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert!(
                recorded
                    .iter()
                    .all(|c| !c.url.contains("conversations.list")),
                "restricted guard must never call conversations.list"
            );
            assert_eq!(
                recorded
                    .iter()
                    .filter(|c| c.url.contains("conversations.info"))
                    .count(),
                1
            );
            assert!(recorded.last().unwrap().url.contains("channel=C0ALLOWED1"));
        }

        // Cached restricted hit: 0 conversations.info calls on second lookup.
        calls.lock().unwrap().clear();
        dispatch(
            &restricted,
            "slack_get_channel_history",
            &JsonValue::parse(r##"{"channel_id":"#allowed-room"}"##).unwrap(),
        )
        .unwrap();
        assert_eq!(
            calls
                .lock()
                .unwrap()
                .iter()
                .filter(|c| c.url.contains("conversations.info"))
                .count(),
            0
        );

        // Disallowed/unknown #name under restricted guard returns identical refusal text as disallowed IDs.
        calls.lock().unwrap().clear();
        let disallowed_existing_err = dispatch(
            &restricted,
            "slack_get_channel_history",
            &JsonValue::parse(r##"{"channel_id":"#general"}"##).unwrap(),
        )
        .unwrap_err();
        let disallowed_nonexistent_err = dispatch(
            &restricted,
            "slack_get_channel_history",
            &JsonValue::parse(r##"{"channel_id":"#totally-fake"}"##).unwrap(),
        )
        .unwrap_err();
        let expected_general = ChannelAllowlistError::ChannelNotAllowed {
            channel_id: "#general".to_string(),
        }
        .message();
        let expected_fake = ChannelAllowlistError::ChannelNotAllowed {
            channel_id: "#totally-fake".to_string(),
        }
        .message();
        assert_eq!(disallowed_existing_err.to_string(), expected_general);
        assert_eq!(disallowed_nonexistent_err.to_string(), expected_fake);
        assert!(calls
            .lock()
            .unwrap()
            .iter()
            .all(|c| !c.url.contains("conversations.list")));
    }

    #[test]
    fn user_handle_resolves_by_priority_caches_and_errors_on_ambiguity() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            if req.url.contains("users.list") {
                if req.url.contains("cursor=users_p2") {
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::parse(
                            r#"{
                                "ok": true,
                                "members": [
                                    {"id": "U_CAROL", "name": "cjones", "profile": {"display_name": "", "real_name": "Carol Jones"}},
                                    {"id": "U_AMB1", "name": "sam_one", "profile": {"display_name": "Sam", "real_name": "Sam One"}},
                                    {"id": "U_AMB2", "name": "sam_two", "profile": {"display_name": "sam", "real_name": "Sam Two"}}
                                ],
                                "response_metadata": {"next_cursor": ""}
                            }"#,
                        )
                        .unwrap(),
                    ));
                }
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{
                            "ok": true,
                            "members": [
                                {"id": "U_ALICE", "name": "alice", "profile": {"display_name": "Alice W", "real_name": "Alice Wonderland"}},
                                {"id": "U_SHADOW", "name": "shadow", "profile": {"display_name": "alice", "real_name": "Shadow User"}},
                                {"id": "U_BOB", "name": "robert99", "profile": {"display_name": "Bobby", "real_name": "Bob Builder"}}
                            ],
                            "response_metadata": {"next_cursor": "users_p2"}
                        }"#,
                    )
                    .unwrap(),
                ));
            }
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(r#"{"ok":true,"profile":{}}"#).unwrap(),
            ))
        });

        let client = client_for(&stdio_env());

        // 1. Exact `name` match wins over another user's `profile.display_name`.
        dispatch(
            &client,
            "slack_get_user_profile",
            &JsonValue::parse(r#"{"user_id":"@ALICE"}"#).unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert_eq!(
                recorded
                    .iter()
                    .filter(|c| c.url.contains("users.list"))
                    .count(),
                2
            );
            assert!(recorded.last().unwrap().url.contains("user=U_ALICE"));
        }

        // 2. Cached lookup matches `profile.display_name` and `profile.real_name` with 0 extra users.list calls.
        calls.lock().unwrap().clear();
        dispatch(
            &client,
            "slack_get_user_profile",
            &JsonValue::parse(r#"{"user_id":"@bobby"}"#).unwrap(),
        )
        .unwrap();
        assert!(calls
            .lock()
            .unwrap()
            .last()
            .unwrap()
            .url
            .contains("user=U_BOB"));

        dispatch(
            &client,
            "slack_invite_to_channel",
            &JsonValue::parse(r#"{"channel_id":"C1","user_ids":["@Carol Jones","@alice"]}"#)
                .unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert_eq!(
                recorded
                    .iter()
                    .filter(|c| c.url.contains("users.list"))
                    .count(),
                0
            );
            let body = JsonValue::parse(recorded.last().unwrap().body.as_ref().unwrap()).unwrap();
            assert_eq!(
                body.get("users").and_then(|v| v.as_str()),
                Some("U_CAROL,U_ALICE")
            );
        }

        // 3. Ambiguous handle errors listing matching IDs; never guesses.
        calls.lock().unwrap().clear();
        let amb_err = dispatch(
            &client,
            "slack_get_user_profile",
            &JsonValue::parse(r#"{"user_id":"@sam"}"#).unwrap(),
        )
        .unwrap_err()
        .to_string();
        assert!(
            amb_err.contains("U_AMB1") && amb_err.contains("U_AMB2"),
            "Ambiguous error must list matching IDs, got: {amb_err}"
        );
        assert!(calls.lock().unwrap().is_empty());

        // 4. Restricted channel allow-list does not block @handle user resolution.
        let restricted = client_for(&http_env());
        dispatch(
            &restricted,
            "slack_get_user_profile",
            &JsonValue::parse(r#"{"user_id":"@alice"}"#).unwrap(),
        )
        .unwrap();
    }

    #[test]
    fn open_dm_opens_conversation_resolves_handles_and_hides_disallowed_dm_id() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            if req.url.contains("users.list") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{"ok":true,"members":[{"id":"U_ALICE","name":"alice","profile":{}}],"response_metadata":{"next_cursor":""}}"#,
                    )
                    .unwrap(),
                ));
            }
            if req.url.contains("conversations.info") && req.url.contains("channel=D0ALLOWED9") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{"ok":true,"channel":{"id":"D0ALLOWED9","is_im":true,"user":"U_ALLOWED_PEER"}}"#,
                    )
                    .unwrap(),
                ));
            }
            if req.url.contains("conversations.open") {
                let body = req.body_str().unwrap_or_default();
                let dm_id = if body.contains("U_ALLOWED_PEER") {
                    "D0ALLOWED9"
                } else {
                    "D0SECRET99"
                };
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", true.into()),
                        ("channel", JsonValue::object(vec![("id", dm_id.into())])),
                    ]),
                ));
            }
            Ok(HttpResponse::json(
                200,
                JsonValue::object(vec![("ok", true.into())]),
            ))
        });

        // 1. Unrestricted: resolves @alice, calls conversations.open, returns channel_id.
        let unrestricted = client_for(&stdio_env());
        let ok_res = dispatch(
            &unrestricted,
            "slack_open_dm",
            &JsonValue::parse(r#"{"users":["@alice","U_BOB"]}"#).unwrap(),
        )
        .unwrap();
        assert_eq!(
            ok_res.get("channel_id").and_then(|v| v.as_str()),
            Some("D0SECRET99")
        );
        {
            let recorded = calls.lock().unwrap();
            let open_call = recorded
                .iter()
                .find(|c| c.url.contains("conversations.open"))
                .unwrap();
            let body = JsonValue::parse(open_call.body.as_ref().unwrap()).unwrap();
            assert_eq!(
                body.get("users").and_then(|v| v.as_str()),
                Some("U_ALICE,U_BOB")
            );
        }

        // Rejects >8 users before calling Slack.
        calls.lock().unwrap().clear();
        let too_many = dispatch(
            &unrestricted,
            "slack_open_dm",
            &JsonValue::parse(r#"{"users":["U1","U2","U3","U4","U5","U6","U7","U8","U9"]}"#)
                .unwrap(),
        )
        .unwrap_err();
        assert!(too_many.to_string().contains("8"));
        assert!(calls.lock().unwrap().is_empty());

        // 2. Restricted and DM NOT allowed -> standard refusal, NO DM ID leaked!
        let mut restricted_env = http_env();
        restricted_env.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        restricted_env.insert(
            "SLACK_CHANNEL_IDS".to_string(),
            "C0ALLOWED1,D0ALLOWED9".to_string(),
        );
        let restricted = client_for(&restricted_env);

        let err = dispatch(
            &restricted,
            "slack_open_dm",
            &JsonValue::parse(r#"{"users":["U_STRANGER"]}"#).unwrap(),
        )
        .unwrap_err();
        assert!(
            matches!(
                err,
                SlackClientError::ChannelAllowlist(ChannelAllowlistError::ChannelNotAllowed { .. })
            ),
            "expected ChannelNotAllowed refusal, got: {err:?}"
        );
        let msg = err.to_string();
        assert!(
            !msg.contains("D0SECRET99"),
            "refusal must NOT leak disallowed DM channel ID: {msg}"
        );
        assert!(msg.contains("is not in this server's allow-list"));

        // 3. Restricted and DM IS on allow-list -> returns the DM channel ID.
        let allowed_dm = dispatch(
            &restricted,
            "slack_open_dm",
            &JsonValue::parse(r#"{"users":["U_ALLOWED_PEER"]}"#).unwrap(),
        )
        .unwrap();
        assert_eq!(
            allowed_dm.get("channel_id").and_then(|v| v.as_str()),
            Some("D0ALLOWED9")
        );
    }

    #[test]
    fn open_dm_under_restriction_never_calls_conversations_open_for_im_mpim_or_refusal() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            if req.url.contains("users.list") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{
                            "ok": true,
                            "members": [
                                {"id": "U_ALICE", "name": "alice", "profile": {}},
                                {"id": "U_BOB", "name": "bob", "profile": {}},
                                {"id": "U_STRANGER", "name": "stranger", "profile": {}}
                            ],
                            "response_metadata": {"next_cursor": ""}
                        }"#,
                    )
                    .unwrap(),
                ));
            }
            if req.url.ends_with("/api/auth.test") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(r#"{"ok":true,"user_id":"U_CALLER","team_id":"T123"}"#)
                        .unwrap(),
                ));
            }
            if req.url.contains("conversations.info") {
                if req.url.contains("channel=D0ALLOWED_IM") {
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::parse(
                            r#"{"ok":true,"channel":{"id":"D0ALLOWED_IM","is_im":true,"user":"U_ALICE"}}"#,
                        )
                        .unwrap(),
                    ));
                }
                if req.url.contains("channel=G0ALLOWED_MPIM") {
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::parse(
                            r#"{"ok":true,"channel":{"id":"G0ALLOWED_MPIM","is_mpim":true,"is_private":true}}"#,
                        )
                        .unwrap(),
                    ));
                }
                if req.url.contains("channel=G0PRIV_CHAN") {
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::parse(
                            r#"{"ok":true,"channel":{"id":"G0PRIV_CHAN","name":"ops-priv","is_mpim":false,"is_private":true}}"#,
                        )
                        .unwrap(),
                    ));
                }
                if req.url.contains("channel=C0ALLOWED1") {
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::parse(
                            r#"{"ok":true,"channel":{"id":"C0ALLOWED1","name":"general","is_private":false}}"#,
                        )
                        .unwrap(),
                    ));
                }
            }
            if req.url.contains("conversations.members")
                && req.url.contains("channel=G0ALLOWED_MPIM")
            {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{"ok":true,"members":["U_CALLER","U_ALICE","U_BOB"],"response_metadata":{"next_cursor":""}}"#,
                    )
                    .unwrap(),
                ));
            }
            if req.url.contains("conversations.open") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(r#"{"ok":true,"channel":{"id":"D0UNWANTED_CREATED"}}"#)
                        .unwrap(),
                ));
            }
            Ok(HttpResponse::json(
                200,
                JsonValue::object(vec![("ok", true.into())]),
            ))
        });

        let mut restricted_env = http_env();
        restricted_env.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        restricted_env.insert(
            "SLACK_CHANNEL_IDS".to_string(),
            "C0ALLOWED1,D0ALLOWED_IM".to_string(),
        );
        restricted_env.insert(
            "SLACK_PRIVATE_CHANNEL_IDS".to_string(),
            "G0ALLOWED_MPIM,G0PRIV_CHAN".to_string(),
        );
        let restricted = client_for(&restricted_env);

        // 1. Refused case: stranger DM not in allow-list -> zero conversations.open calls.
        let refused_im = dispatch(
            &restricted,
            "slack_open_dm",
            &JsonValue::parse(r#"{"users":["@stranger"]}"#).unwrap(),
        )
        .unwrap_err();
        let open_calls_after_refusal = calls
            .lock()
            .unwrap()
            .iter()
            .filter(|c| c.url.contains("conversations.open"))
            .count();
        assert_eq!(
            open_calls_after_refusal, 0,
            "restricted slack_open_dm must NEVER call conversations.open on refusal"
        );
        assert_eq!(
            refused_im,
            SlackClientError::ChannelAllowlist(ChannelAllowlistError::ChannelNotAllowed {
                channel_id: "dm:U_STRANGER".to_string(),
            })
        );
        assert!(!refused_im.to_string().contains("D0UNWANTED_CREATED"));

        // 2. Allowed 1:1 IM match -> returns D0ALLOWED_IM with zero conversations.open calls and zero extra info calls (cached).
        calls.lock().unwrap().clear();
        let ok_im = dispatch(
            &restricted,
            "slack_open_dm",
            &JsonValue::parse(r#"{"users":["@alice"]}"#).unwrap(),
        )
        .unwrap();
        assert_eq!(
            ok_im.get("channel_id").and_then(|v| v.as_str()),
            Some("D0ALLOWED_IM")
        );
        assert_eq!(
            calls
                .lock()
                .unwrap()
                .iter()
                .filter(|c| c.url.contains("conversations.open"))
                .count(),
            0,
            "restricted slack_open_dm must NEVER call conversations.open on allowed IM match"
        );
        assert_eq!(
            calls
                .lock()
                .unwrap()
                .iter()
                .filter(|c| c.url.contains("conversations.info"))
                .count(),
            0,
            "second restricted open_dm reuses cached allowed D/G map"
        );

        // 3. Allowed MPIM match (exact member set = caller + requested users) -> returns G0ALLOWED_MPIM, zero conversations.open calls.
        calls.lock().unwrap().clear();
        let ok_mpim = dispatch(
            &restricted,
            "slack_open_dm",
            &JsonValue::parse(r#"{"users":["U_BOB","@alice"]}"#).unwrap(),
        )
        .unwrap();
        assert_eq!(
            ok_mpim.get("channel_id").and_then(|v| v.as_str()),
            Some("G0ALLOWED_MPIM")
        );
        assert_eq!(
            calls
                .lock()
                .unwrap()
                .iter()
                .filter(|c| c.url.contains("conversations.open"))
                .count(),
            0,
            "restricted slack_open_dm must NEVER call conversations.open on allowed MPIM match"
        );

        // 4. MPIM non-exact member sets (subset/superset/wrong peer) -> standard refusal, zero conversations.open calls.
        calls.lock().unwrap().clear();
        let refused_superset = dispatch(
            &restricted,
            "slack_open_dm",
            &JsonValue::parse(r#"{"users":["U_ALICE","U_BOB","U_STRANGER"]}"#).unwrap(),
        )
        .unwrap_err();
        assert_eq!(
            refused_superset,
            SlackClientError::ChannelAllowlist(ChannelAllowlistError::ChannelNotAllowed {
                channel_id: "dm:U_ALICE,U_BOB,U_STRANGER".to_string(),
            })
        );
        assert!(calls.lock().unwrap().is_empty());
    }

    #[test]
    fn schedule_message_accepts_unix_and_iso_and_rejects_past_or_over_120_days() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(
                    r#"{"ok":true,"channel":"C1","scheduled_message_id":"Q123","post_at":1800000000}"#,
                )
                .unwrap(),
            ))
        });

        let client = client_for(&stdio_env());
        let now_secs = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        // 1. Rejects past Unix and past ISO before calling Slack.
        let past_unix = (now_secs - 60).to_string();
        let err_past_unix = dispatch(
            &client,
            "slack_schedule_message",
            &JsonValue::object(vec![
                ("channel_id", "C1".into()),
                ("text", "too late".into()),
                ("post_at", past_unix.as_str().into()),
            ]),
        )
        .unwrap_err();
        assert!(err_past_unix.to_string().contains("past"));

        let err_past_iso = dispatch(
            &client,
            "slack_schedule_message",
            &JsonValue::parse(
                r#"{"channel_id":"C1","text":"too late","post_at":"2020-01-01T00:00:00Z"}"#,
            )
            .unwrap(),
        )
        .unwrap_err();
        assert!(err_past_iso.to_string().contains("past"));

        // 2. Rejects >120 days out before calling Slack.
        let too_far_unix = (now_secs + 121 * 86_400).to_string();
        let err_far = dispatch(
            &client,
            "slack_schedule_message",
            &JsonValue::object(vec![
                ("channel_id", "C1".into()),
                ("text", "too far".into()),
                ("post_at", too_far_unix.as_str().into()),
            ]),
        )
        .unwrap_err();
        assert!(err_far.to_string().contains("120 days"));

        // Rejects ISO without timezone offset before calling Slack.
        assert!(dispatch(
            &client,
            "slack_schedule_message",
            &JsonValue::parse(
                r#"{"channel_id":"C1","text":"no offset","post_at":"2026-12-01T09:00:00"}"#,
            )
            .unwrap(),
        )
        .is_err());
        assert!(calls.lock().unwrap().is_empty());

        // 3. Accepts Unix timestamp (string and number) and forwards thread_ts + reply_broadcast.
        let target_unix = now_secs + 7200;
        let target_unix_str = target_unix.to_string();
        dispatch(
            &client,
            "slack_schedule_message",
            &JsonValue::object(vec![
                ("channel_id", "C1".into()),
                ("text", "reminder".into()),
                ("post_at", target_unix_str.as_str().into()),
                ("thread_ts", "1700000000.000100".into()),
                ("reply_broadcast", true.into()),
            ]),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert_eq!(recorded.len(), 1);
            assert!(recorded[0].url.contains("/api/chat.scheduleMessage"));
            let body = JsonValue::parse(recorded[0].body.as_ref().unwrap()).unwrap();
            assert_eq!(body.get("channel").and_then(|v| v.as_str()), Some("C1"));
            assert_eq!(body.get("text").and_then(|v| v.as_str()), Some("reminder"));
            assert_eq!(
                body.get("post_at").and_then(|v| v.as_i64()),
                Some(target_unix)
            );
            assert_eq!(
                body.get("thread_ts").and_then(|v| v.as_str()),
                Some("1700000000.000100")
            );
            assert_eq!(
                body.get("reply_broadcast").and_then(|v| v.as_bool()),
                Some(true)
            );
        }

        // 4. Accepts ISO 8601 date-time with offset (2026-11-20T17:30:00-08:00 == 2026-11-21T01:30:00Z == 1795224600).
        // Compute a dynamic ISO timestamp 2 days from now so this test never rots with wall-clock date!
        calls.lock().unwrap().clear();
        let two_days_later = now_secs + 2 * 86_400;
        // Format `two_days_later` at +02:00 offset: local = two_days_later + 7200.
        let local_secs = two_days_later + 7200;
        let days = local_secs.div_euclid(86_400);
        let sod = local_secs.rem_euclid(86_400);
        let z = days + 719_468;
        let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
        let doe = (z - era * 146_097) as u32;
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
        let mut y = yoe as i64 + era * 400;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let d = doy - (153 * mp + 2) / 5 + 1;
        let m = if mp < 10 { mp + 3 } else { mp - 9 };
        if m <= 2 {
            y += 1;
        }
        let hh = sod / 3600;
        let mm = (sod % 3600) / 60;
        let ss = sod % 60;
        let iso_with_offset = format!("{y:04}-{m:02}-{d:02}T{hh:02}:{mm:02}:{ss:02}+02:00");

        dispatch(
            &client,
            "slack_schedule_message",
            &JsonValue::object(vec![
                ("channel_id", "C1".into()),
                ("text", "iso".into()),
                ("post_at", iso_with_offset.as_str().into()),
            ]),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            let body = JsonValue::parse(recorded[0].body.as_ref().unwrap()).unwrap();
            assert_eq!(
                body.get("post_at").and_then(|v| v.as_i64()),
                Some(two_days_later)
            );
        }
    }

    #[test]
    fn schedule_message_accepts_numeric_json_post_at_and_rejects_past_or_invalid_numbers() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(
                    r#"{"ok":true,"channel":"C1","scheduled_message_id":"Q_NUM","post_at":1800000000}"#,
                )
                .unwrap(),
            ))
        });

        let client = client_for(&stdio_env());
        let now_secs = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        // 1. Valid future JSON number is accepted and sent to chat.scheduleMessage.
        let future_num = now_secs + 3600;
        let ok_payload = JsonValue::parse(&format!(
            r#"{{"channel_id":"C1","text":"numeric","post_at":{future_num}}}"#
        ))
        .unwrap();
        assert!(matches!(
            ok_payload.get("post_at"),
            Some(JsonValue::Number(_))
        ));
        dispatch(&client, "slack_schedule_message", &ok_payload).unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert_eq!(recorded.len(), 1);
            assert!(recorded[0].url.contains("/api/chat.scheduleMessage"));
            let body = JsonValue::parse(recorded[0].body.as_ref().unwrap()).unwrap();
            assert_eq!(
                body.get("post_at").and_then(|v| v.as_i64()),
                Some(future_num)
            );
        }

        // 2. Past JSON number is rejected before calling Slack.
        calls.lock().unwrap().clear();
        let past_num = now_secs - 60;
        let past_payload = JsonValue::parse(&format!(
            r#"{{"channel_id":"C1","text":"too late","post_at":{past_num}}}"#
        ))
        .unwrap();
        let err_past = dispatch(&client, "slack_schedule_message", &past_payload).unwrap_err();
        assert!(err_past.to_string().contains("past"));
        assert!(calls.lock().unwrap().is_empty());

        // 3. Fractional JSON number is rejected.
        let frac_payload = JsonValue::parse(&format!(
            r#"{{"channel_id":"C1","text":"frac","post_at":{future_num}.5}}"#
        ))
        .unwrap();
        assert!(dispatch(&client, "slack_schedule_message", &frac_payload).is_err());
        assert!(calls.lock().unwrap().is_empty());

        // 4. Out-of-64-bit-range JSON number is rejected as out of range rather than saturating to i64::MAX.
        let overflow_payload =
            JsonValue::parse(r#"{"channel_id":"C1","text":"overflow","post_at":1e25}"#).unwrap();
        let err_overflow =
            dispatch(&client, "slack_schedule_message", &overflow_payload).unwrap_err();
        assert!(
            err_overflow
                .to_string()
                .contains("out of 64-bit integer range"),
            "expected out-of-range error, got: {err_overflow}"
        );
        assert!(calls.lock().unwrap().is_empty());
    }

    #[test]
    fn list_and_delete_scheduled_messages_filter_and_guard_channels() {
        let calls: Arc<Mutex<Vec<CapturedCall>>> = Arc::new(Mutex::new(Vec::new()));
        let calls_ref = calls.clone();
        let _guard = set_mock_fetch(move |req| {
            calls_ref.lock().unwrap().push(CapturedCall {
                url: req.url.clone(),
                body: req.body_str(),
            });
            if req.url.contains("chat.scheduledMessages.list") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{
                            "ok": true,
                            "scheduled_messages": [
                                {"id": "Q_ALLOW", "channel_id": "C0ALLOWED1", "post_at": 1800000100, "text": "allowed"},
                                {"id": "Q_DROP1", "channel_id": "C_SECRET", "post_at": 1800000200, "text": "secret 1"},
                                {"id": "Q_DROP2", "channel_id": "G_SECRET", "post_at": 1800000300, "text": "secret 2"}
                            ],
                            "response_metadata": {"next_cursor": "sched_next_cur"}
                        }"#,
                    )
                    .unwrap(),
                ));
            }
            Ok(HttpResponse::json(
                200,
                JsonValue::object(vec![("ok", true.into())]),
            ))
        });

        // 1. Restricted: drops disallowed entries, sets filtered_out, keeps response_metadata.next_cursor.
        let mut restricted_env = http_env();
        restricted_env.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        let restricted = client_for(&restricted_env);

        let res = dispatch(
            &restricted,
            "slack_list_scheduled_messages",
            &JsonValue::empty_object(),
        )
        .unwrap();
        let kept = res
            .get("scheduled_messages")
            .and_then(|v| v.as_array())
            .unwrap();
        assert_eq!(kept.len(), 1);
        assert_eq!(kept[0].get("id").and_then(|v| v.as_str()), Some("Q_ALLOW"));
        assert_eq!(res.get("filtered_out").and_then(|v| v.as_u64()), Some(2));
        assert_eq!(
            res.get("response_metadata")
                .and_then(|m| m.get("next_cursor"))
                .and_then(|v| v.as_str()),
            Some("sched_next_cur")
        );

        // Guarded when explicit disallowed channel_id is passed to list or delete.
        calls.lock().unwrap().clear();
        assert!(matches!(
            dispatch(
                &restricted,
                "slack_list_scheduled_messages",
                &JsonValue::parse(r#"{"channel_id":"G_SECRET"}"#).unwrap(),
            ),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::ChannelNotAllowed { .. }
            ))
        ));
        assert!(matches!(
            dispatch(
                &restricted,
                "slack_delete_scheduled_message",
                &JsonValue::parse(r#"{"channel_id":"G_SECRET","scheduled_message_id":"Q_DROP2"}"#,)
                    .unwrap(),
            ),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::ChannelNotAllowed { .. }
            ))
        ));
        assert!(calls.lock().unwrap().is_empty());

        // Allowed delete forwards channel + scheduled_message_id to chat.deleteScheduledMessage.
        dispatch(
            &restricted,
            "slack_delete_scheduled_message",
            &JsonValue::parse(r#"{"channel_id":"C0ALLOWED1","scheduled_message_id":"Q_ALLOW"}"#)
                .unwrap(),
        )
        .unwrap();
        {
            let recorded = calls.lock().unwrap();
            assert_eq!(recorded.len(), 1);
            assert!(recorded[0].url.contains("/api/chat.deleteScheduledMessage"));
            let body = JsonValue::parse(recorded[0].body.as_ref().unwrap()).unwrap();
            assert_eq!(
                body.get("channel").and_then(|v| v.as_str()),
                Some("C0ALLOWED1")
            );
            assert_eq!(
                body.get("scheduled_message_id").and_then(|v| v.as_str()),
                Some("Q_ALLOW")
            );
        }

        // 2. Unrestricted: keeps all 3 scheduled messages and omits filtered_out.
        let unrestricted = client_for(&stdio_env());
        let unres = dispatch(
            &unrestricted,
            "slack_list_scheduled_messages",
            &JsonValue::parse(r#"{"cursor":"c1","limit":25}"#).unwrap(),
        )
        .unwrap();
        assert_eq!(
            unres
                .get("scheduled_messages")
                .and_then(|v| v.as_array())
                .unwrap()
                .len(),
            3
        );
        assert!(!unres.contains_key("filtered_out"));
    }
}
