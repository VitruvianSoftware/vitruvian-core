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

use crate::config::{ServerConfig, TransportMode};
use crate::json::JsonValue;

#[derive(Debug, Clone, PartialEq)]
pub struct ToolDefinition {
    pub name: &'static str,
    pub description: &'static str,
    pub input_schema: JsonValue,
}

impl ToolDefinition {
    pub fn to_json(&self) -> JsonValue {
        JsonValue::object(vec![
            ("name", self.name.into()),
            ("description", self.description.into()),
            ("inputSchema", self.input_schema.clone()),
        ])
    }
}

pub const HTTP_WITHHELD_ALWAYS: &[&str] = &["slack_download_file"];

pub const HTTP_WITHHELD_DESTRUCTIVE: &[&str] = &[
    "slack_delete_canvas",
    "slack_set_user_group_enabled",
    "slack_set_user_group_members",
];

pub const HTTP_WITHHELD_WITHOUT_USER_TOKEN: &[&str] = &[
    "slack_set_channel_topic",
    "slack_invite_to_channel",
    "slack_mark_read",
    "slack_list_unread",
    "slack_add_reaction",
    "slack_remove_reaction",
    "slack_pin_message",
    "slack_unpin_message",
    "slack_add_bookmark",
    "slack_get_users",
    "slack_search_messages",
    "slack_search_files",
    "slack_create_canvas",
    "slack_edit_canvas",
    "slack_lookup_canvas_sections",
    "slack_delete_canvas",
    "slack_list_user_group_members",
    "slack_create_user_group",
    "slack_update_user_group",
    "slack_set_user_group_members",
    "slack_set_user_group_enabled",
];

pub const HTTP_WITHHELD_TOOLS: &[&str] = HTTP_WITHHELD_WITHOUT_USER_TOKEN;

fn schema(props: Vec<(&str, JsonValue)>, required: &[&str]) -> JsonValue {
    let mut entries = vec![
        ("type", "object".into()),
        ("properties", JsonValue::object(props)),
    ];
    if !required.is_empty() {
        entries.push((
            "required",
            JsonValue::Array(required.iter().map(|s| (*s).into()).collect()),
        ));
    }
    JsonValue::object(entries)
}

fn str_prop(desc: &str) -> JsonValue {
    JsonValue::object(vec![
        ("type", "string".into()),
        ("description", desc.into()),
    ])
}

fn num_prop(desc: &str, default: Option<i64>) -> JsonValue {
    let mut v = vec![("type", "number".into()), ("description", desc.into())];
    if let Some(d) = default {
        v.push(("default", d.into()));
    }
    JsonValue::object(v)
}

fn bool_prop(desc: &str, default: Option<bool>) -> JsonValue {
    let mut v = vec![("type", "boolean".into()), ("description", desc.into())];
    if let Some(d) = default {
        v.push(("default", d.into()));
    }
    JsonValue::object(v)
}

fn str_array_prop(desc: &str) -> JsonValue {
    JsonValue::object(vec![
        ("type", "array".into()),
        ("items", JsonValue::object(vec![("type", "string".into())])),
        ("description", desc.into()),
    ])
}

pub fn all_tools() -> Vec<ToolDefinition> {
    all_tools_with_compact_default(false)
}

pub fn all_tools_with_compact_default(compact_default: bool) -> Vec<ToolDefinition> {
    let mut tools = vec![
        // Channels
        ToolDefinition {
            name: "slack_list_channels",
            description: "List public channels in the workspace (or a pre-defined subset via SLACK_CHANNEL_IDS)",
            input_schema: schema(
                vec![
                    ("limit", num_prop("Maximum number of channels to return (default 100, max 200)", Some(100))),
                    ("cursor", str_prop("Pagination cursor for the next page of results")),
                ],
                &[],
            ),
        },
        ToolDefinition {
            name: "slack_get_channel_info",
            description: "Get detailed information about a channel including topic, purpose, member count, and associated canvas ID",
            input_schema: schema(
                vec![("channel_id", str_prop("The ID of the channel"))],
                &["channel_id"],
            ),
        },
        ToolDefinition {
            name: "slack_get_channel_history",
            description: "Get recent messages from a channel",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel")),
                    ("limit", num_prop("Number of messages to retrieve (default 10)", Some(10))),
                    ("oldest", str_prop("Only messages after this Slack timestamp (e.g. '1234567890.123456')")),
                    ("latest", str_prop("Only messages before this Slack timestamp (e.g. '1234567890.123456')")),
                    ("since", str_prop("Relative lookback window such as '30m', '24h', or '7d' (converted to oldest; ignored if oldest is provided)")),
                    ("cursor", str_prop("Pagination cursor from response_metadata.next_cursor")),
                    ("include_activity", bool_prop("Include channel/group join and leave notices (default true)", Some(true))),
                ],
                &["channel_id"],
            ),
        },
        ToolDefinition {
            name: "slack_get_thread_replies",
            description: "Get all replies in a message thread",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel containing the thread")),
                    ("thread_ts", str_prop("The timestamp of the parent message (format: '1234567890.123456')")),
                    ("limit", num_prop("Maximum number of replies to return (max 200)", None)),
                    ("cursor", str_prop("Pagination cursor from response_metadata.next_cursor")),
                    ("oldest", str_prop("Only replies after this Slack timestamp")),
                    ("latest", str_prop("Only replies before this Slack timestamp")),
                ],
                &["channel_id", "thread_ts"],
            ),
        },
        ToolDefinition {
            name: "slack_set_channel_topic",
            description: "Set the topic of a channel",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel")),
                    ("topic", str_prop("The new topic text")),
                ],
                &["channel_id", "topic"],
            ),
        },
        ToolDefinition {
            name: "slack_get_message",
            description: "Fetch a single message, either from a Slack permalink (https://<workspace>.slack.com/archives/<channel>/p<timestamp>) or from a channel ID and timestamp. Returns the message with its thread_ts if it belongs to a thread.",
            input_schema: schema(
                vec![
                    ("permalink", str_prop("A Slack message permalink. When given, channel_id and timestamp are ignored.")),
                    ("channel_id", str_prop("The ID of the channel containing the message")),
                    ("timestamp", str_prop("The timestamp of the message (format: '1234567890.123456')")),
                    ("thread_ts", str_prop("For a thread reply, the parent message's timestamp. Not needed for top-level messages.")),
                ],
                &[],
            ),
        },
        ToolDefinition {
            name: "slack_get_permalink",
            description: "Get a shareable permalink URL for a message",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel containing the message")),
                    ("timestamp", str_prop("The timestamp of the message")),
                ],
                &["channel_id", "timestamp"],
            ),
        },
        // Channel membership
        ToolDefinition {
            name: "slack_join_channel",
            description: "Join a public channel. By default the bot joins (so it can read the channel afterwards); set as='user' to join as the authenticated user.",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel to join")),
                    ("as", JsonValue::object(vec![
                        ("type", "string".into()),
                        ("description", "Which identity joins: 'bot' (default) or 'user'".into()),
                        ("enum", JsonValue::Array(vec!["bot".into(), "user".into()])),
                        ("default", "bot".into()),
                    ])),
                ],
                &["channel_id"],
            ),
        },
        ToolDefinition {
            name: "slack_leave_channel",
            description: "Leave a channel. By default the bot leaves; set as='user' to leave as the authenticated user.",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel to leave")),
                    ("as", JsonValue::object(vec![
                        ("type", "string".into()),
                        ("description", "Which identity leaves: 'bot' (default) or 'user'".into()),
                        ("enum", JsonValue::Array(vec!["bot".into(), "user".into()])),
                        ("default", "bot".into()),
                    ])),
                ],
                &["channel_id"],
            ),
        },
        ToolDefinition {
            name: "slack_list_channel_members",
            description: "List the user IDs of a channel's members",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel")),
                    ("limit", num_prop("Maximum number of members to return (default 100, max 200)", Some(100))),
                    ("cursor", str_prop("Pagination cursor for the next page of results")),
                ],
                &["channel_id"],
            ),
        },
        ToolDefinition {
            name: "slack_invite_to_channel",
            description: "Invite users to a channel as the authenticated user",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel")),
                    ("user_ids", str_array_prop("User IDs to invite (up to 1000)")),
                ],
                &["channel_id", "user_ids"],
            ),
        },
        ToolDefinition {
            name: "slack_list_unread",
            description: "List the conversations the authenticated user has unread messages in, newest first, with an unread count and the latest_ts to hand to slack_mark_read. Slow: Slack has no single call for this, so it checks each conversation in turn (two API calls each). Conversation types the token cannot enumerate are named under 'skipped' and per-conversation failures under 'errors' rather than failing the listing; DMs and group DMs need the im:read and mpim:read user scopes. Counts top-level messages only, not thread replies, and ignores join/leave notices.",
            input_schema: schema(
                vec![(
                    "max_per_conversation",
                    num_prop("Stop counting a conversation's unread messages at this many (default 100, max 200)", Some(100)),
                )],
                &[],
            ),
        },
        ToolDefinition {
            name: "slack_mark_read",
            description: "Mark a conversation as read up to a message, as the authenticated user. Clears the unread badge for everything at or before that message; pass the timestamp of the newest message you have handled. Works for channels and private channels; DMs and group DMs need the im:write and mpim:write user scopes.",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel, private channel or DM")),
                    ("timestamp", str_prop("Timestamp (ts) of the newest message to mark as read, e.g. 1712345678.123456")),
                ],
                &["channel_id", "timestamp"],
            ),
        },
        // Custom emoji
        ToolDefinition {
            name: "slack_list_emoji",
            description: "List the workspace's custom emoji, optionally filtered by a substring of the name. Values are image URLs, or 'alias:<name>' for aliases.",
            input_schema: schema(
                vec![
                    ("query", str_prop("Case-insensitive substring to match against emoji names")),
                    ("include_aliases", bool_prop("Include alias entries (default true)", Some(true))),
                ],
                &[],
            ),
        },
        // Users
        ToolDefinition {
            name: "slack_get_users",
            description: "Get a list of all users in the workspace with basic profile information",
            input_schema: schema(
                vec![
                    ("cursor", str_prop("Pagination cursor for the next page of results")),
                    ("limit", num_prop("Maximum number of users to return (default 100, max 200)", Some(100))),
                ],
                &[],
            ),
        },
        ToolDefinition {
            name: "slack_get_user_profile",
            description: "Get detailed profile information for a specific user",
            input_schema: schema(
                vec![("user_id", str_prop("The ID of the user"))],
                &["user_id"],
            ),
        },
        ToolDefinition {
            name: "slack_whoami",
            description: "Identify the Slack bot and (when configured) user accounts backing this server via auth.test",
            input_schema: schema(vec![], &[]),
        },
        // Search
        ToolDefinition {
            name: "slack_search_messages",
            description: "Search for messages across the workspace. Supports Slack search modifiers like 'in:#channel', 'from:@user', 'before:2025-01-01', etc.",
            input_schema: schema(
                vec![
                    ("query", str_prop("The search query (supports Slack search modifiers)")),
                    ("count", num_prop("Number of results to return (default 20, max 100)", Some(20))),
                    ("sort", JsonValue::object(vec![
                        ("type", "string".into()),
                        ("description", "Sort order: 'score' (relevance) or 'timestamp'".into()),
                        ("default", "score".into()),
                    ])),
                    ("sort_dir", JsonValue::object(vec![
                        ("type", "string".into()),
                        ("description", "Sort direction: 'asc' or 'desc'".into()),
                        ("enum", JsonValue::Array(vec!["asc".into(), "desc".into()])),
                    ])),
                    ("page", num_prop("Page number of results to return (1-based)", None)),
                ],
                &["query"],
            ),
        },
        ToolDefinition {
            name: "slack_search_files",
            description: "Search for files across the workspace. Supports Slack search modifiers like 'in:#channel', 'from:@user', 'type:pdf', etc.",
            input_schema: schema(
                vec![
                    ("query", str_prop("The search query (supports Slack search modifiers)")),
                    ("count", num_prop("Number of results to return (default 20, max 100)", Some(20))),
                    ("sort", JsonValue::object(vec![
                        ("type", "string".into()),
                        ("description", "Sort order: 'score' (relevance) or 'timestamp'".into()),
                        ("default", "score".into()),
                    ])),
                    ("sort_dir", JsonValue::object(vec![
                        ("type", "string".into()),
                        ("description", "Sort direction: 'asc' or 'desc'".into()),
                        ("enum", JsonValue::Array(vec!["asc".into(), "desc".into()])),
                    ])),
                    ("page", num_prop("Page number of results to return (1-based)", None)),
                ],
                &["query"],
            ),
        },
        // Messaging
        ToolDefinition {
            name: "slack_post_message",
            description: "Post a new message to a Slack channel as the authenticated user (not as a bot)",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel to post to")),
                    ("text", str_prop("The message text to post (supports Slack mrkdwn)")),
                    ("thread_ts", str_prop("Optional parent message timestamp to post as a thread reply")),
                    ("reply_broadcast", bool_prop("When replying to a thread, also post the reply to the channel", None)),
                    ("unfurl_links", bool_prop("Enable or disable link unfurling for URLs in the message", None)),
                ],
                &["channel_id", "text"],
            ),
        },
        ToolDefinition {
            name: "slack_reply_to_thread",
            description: "Reply to a specific message thread as the authenticated user",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel containing the thread")),
                    ("thread_ts", str_prop("The timestamp of the parent message (format: '1234567890.123456')")),
                    ("text", str_prop("The reply text (supports Slack mrkdwn)")),
                    ("reply_broadcast", bool_prop("Also post the reply to the channel", None)),
                    ("unfurl_links", bool_prop("Enable or disable link unfurling for URLs in the reply", None)),
                ],
                &["channel_id", "thread_ts", "text"],
            ),
        },
        ToolDefinition {
            name: "slack_update_message",
            description: "Edit a previously sent message",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel containing the message")),
                    ("timestamp", str_prop("The timestamp of the message to edit")),
                    ("text", str_prop("The new message text (supports Slack mrkdwn)")),
                ],
                &["channel_id", "timestamp", "text"],
            ),
        },
        ToolDefinition {
            name: "slack_add_reaction",
            description: "Add a reaction emoji to a message",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel containing the message")),
                    ("timestamp", str_prop("The timestamp of the message to react to")),
                    ("reaction", str_prop("The emoji name without colons (e.g. 'thumbsup')")),
                ],
                &["channel_id", "timestamp", "reaction"],
            ),
        },
        ToolDefinition {
            name: "slack_remove_reaction",
            description: "Remove a reaction emoji from a message",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel containing the message")),
                    ("timestamp", str_prop("The timestamp of the message to remove the reaction from")),
                    ("emoji", str_prop("The emoji name without colons (e.g. 'thumbsup')")),
                ],
                &["channel_id", "timestamp", "emoji"],
            ),
        },
        // Pins
        ToolDefinition {
            name: "slack_list_pins",
            description: "List items pinned to a channel",
            input_schema: schema(
                vec![("channel_id", str_prop("The ID of the channel"))],
                &["channel_id"],
            ),
        },
        ToolDefinition {
            name: "slack_pin_message",
            description: "Pin a message to a channel",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel containing the message")),
                    ("timestamp", str_prop("The timestamp of the message to pin")),
                ],
                &["channel_id", "timestamp"],
            ),
        },
        ToolDefinition {
            name: "slack_unpin_message",
            description: "Unpin a message from a channel",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel containing the message")),
                    ("timestamp", str_prop("The timestamp of the message to unpin")),
                ],
                &["channel_id", "timestamp"],
            ),
        },
        // Bookmarks
        ToolDefinition {
            name: "slack_list_bookmarks",
            description: "List bookmarks for a channel",
            input_schema: schema(
                vec![("channel_id", str_prop("The ID of the channel"))],
                &["channel_id"],
            ),
        },
        ToolDefinition {
            name: "slack_add_bookmark",
            description: "Add a bookmark (link) to a channel",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel")),
                    ("title", str_prop("Title of the bookmark")),
                    ("link", str_prop("URL for the bookmark")),
                    ("emoji", str_prop("Emoji icon for the bookmark (e.g. ':link:')")),
                ],
                &["channel_id", "title", "link"],
            ),
        },
        // Canvases
        ToolDefinition {
            name: "slack_create_canvas",
            description: "Create a new Slack canvas. Content uses markdown format. Optionally attach to a channel.",
            input_schema: schema(
                vec![
                    ("title", str_prop("Title of the canvas")),
                    ("markdown", str_prop("Markdown content for the canvas body. Supports headings, lists, checklists, code blocks, bold, italic, links, tables, and @mentions.")),
                    ("channel_id", str_prop("Optional channel ID to automatically tab the canvas into")),
                ],
                &[],
            ),
        },
        ToolDefinition {
            name: "slack_edit_canvas",
            description: "Edit an existing Slack canvas. Supports insert, replace, delete, and rename operations.",
            input_schema: schema(
                vec![
                    ("canvas_id", str_prop("The ID of the canvas to edit (e.g. F1234ABCD)")),
                    ("operation", JsonValue::object(vec![
                        ("type", "string".into()),
                        ("description", "The edit operation: 'insert_at_start', 'insert_at_end', 'insert_before', 'insert_after', 'replace', 'delete', or 'rename'".into()),
                        ("enum", JsonValue::Array(vec![
                            "insert_at_start".into(),
                            "insert_at_end".into(),
                            "insert_before".into(),
                            "insert_after".into(),
                            "replace".into(),
                            "delete".into(),
                            "rename".into(),
                        ])),
                    ])),
                    ("markdown", str_prop("Markdown content for the operation (not used for delete)")),
                    ("section_id", str_prop("Section ID for relative operations (insert_before, insert_after, replace, delete). Use slack_lookup_canvas_sections to find section IDs.")),
                ],
                &["canvas_id", "operation"],
            ),
        },
        ToolDefinition {
            name: "slack_lookup_canvas_sections",
            description: "Find sections within a canvas by heading type and/or text content. Returns section IDs that can be used with slack_edit_canvas.",
            input_schema: schema(
                vec![
                    ("canvas_id", str_prop("The ID of the canvas")),
                    ("section_types", str_array_prop("Filter by section type: 'h1', 'h2', 'h3', or 'any_header'")),
                    ("contains_text", str_prop("Filter sections containing this text")),
                ],
                &["canvas_id"],
            ),
        },
        ToolDefinition {
            name: "slack_delete_canvas",
            description: "Permanently delete a canvas. This action cannot be undone.",
            input_schema: schema(
                vec![("canvas_id", str_prop("The ID of the canvas to delete"))],
                &["canvas_id"],
            ),
        },
        // Files
        ToolDefinition {
            name: "slack_get_file_info",
            description: "Get metadata for a file (name, type, size, who shared it, where it is shared) by file ID or Slack file URL. Private download URLs are not returned.",
            input_schema: schema(
                vec![("file", str_prop("The file ID (e.g. F1234ABCD) or a Slack file URL (https://<workspace>.slack.com/files/<user>/<file>/<name>)"))],
                &["file"],
            ),
        },
        ToolDefinition {
            name: "slack_read_file",
            description: "Read the content of a text file or Slack canvas shared in Slack. Binary files are refused; use slack_download_file for those.",
            input_schema: schema(
                vec![
                    ("file", str_prop("The file ID or a Slack file URL")),
                    ("max_bytes", num_prop("Refuse files larger than this many bytes (default 1048576)", Some(1_048_576))),
                ],
                &["file"],
            ),
        },
        ToolDefinition {
            name: "slack_upload_file",
            description: "Upload a file and share it into a channel, optionally in a thread. Provide the content as text, or base64 for binary data.",
            input_schema: schema(
                vec![
                    ("channel_id", str_prop("The ID of the channel to share the file into")),
                    ("filename", str_prop("File name including extension (e.g. report.csv)")),
                    ("content", str_prop("Text content of the file. Mutually exclusive with content_base64.")),
                    ("content_base64", str_prop("Base64-encoded binary content. Mutually exclusive with content.")),
                    ("title", str_prop("Title shown in Slack (defaults to the filename)")),
                    ("initial_comment", str_prop("Message text posted alongside the file")),
                    ("thread_ts", str_prop("Share into this thread instead of the channel top level")),
                ],
                &["channel_id", "filename"],
            ),
        },
        ToolDefinition {
            name: "slack_download_file",
            description: "Download a file from Slack to a path on the local machine. Refuses to overwrite an existing file. Available on the local (stdio) transport only.",
            input_schema: schema(
                vec![
                    ("file", str_prop("The file ID or a Slack file URL")),
                    ("output_path", str_prop("Absolute path to write the file to")),
                ],
                &["file", "output_path"],
            ),
        },
        // User groups
        ToolDefinition {
            name: "slack_list_user_groups",
            description: "List the workspace's user groups (@handles) with their IDs, names and member counts",
            input_schema: schema(
                vec![("include_disabled", bool_prop("Include disabled groups (default false)", Some(false)))],
                &[],
            ),
        },
        ToolDefinition {
            name: "slack_list_user_group_members",
            description: "List the user IDs that belong to a user group",
            input_schema: schema(
                vec![("usergroup_id", str_prop("The ID of the user group (e.g. S1234ABCD)"))],
                &["usergroup_id"],
            ),
        },
        ToolDefinition {
            name: "slack_create_user_group",
            description: "Create a user group as the authenticated user",
            input_schema: schema(
                vec![
                    ("name", str_prop("Display name of the group")),
                    ("handle", str_prop("Mention handle without the @ (e.g. 'platform')")),
                    ("description", str_prop("Short description of the group")),
                    ("channel_ids", str_array_prop("Default channels members are added to")),
                ],
                &["name", "handle"],
            ),
        },
        ToolDefinition {
            name: "slack_update_user_group",
            description: "Update a user group's name, handle or description as the authenticated user",
            input_schema: schema(
                vec![
                    ("usergroup_id", str_prop("The ID of the user group")),
                    ("name", str_prop("New display name")),
                    ("handle", str_prop("New mention handle")),
                    ("description", str_prop("New description")),
                ],
                &["usergroup_id"],
            ),
        },
        ToolDefinition {
            name: "slack_set_user_group_members",
            description: "Replace the full member list of a user group as the authenticated user. Slack has no add/remove primitive: read the current members first, then send the complete new list. A group cannot be emptied; disable it instead.",
            input_schema: schema(
                vec![
                    ("usergroup_id", str_prop("The ID of the user group")),
                    ("user_ids", str_array_prop("The complete list of user IDs the group should contain")),
                ],
                &["usergroup_id", "user_ids"],
            ),
        },
        ToolDefinition {
            name: "slack_set_user_group_enabled",
            description: "Enable or disable a user group as the authenticated user",
            input_schema: schema(
                vec![
                    ("usergroup_id", str_prop("The ID of the user group")),
                    ("enabled", bool_prop("true to enable, false to disable", None)),
                ],
                &["usergroup_id", "enabled"],
            ),
        },
    ];
    for tool in &mut tools {
        if let Some(entries) = tool.input_schema.as_object_mut() {
            if let Some((_, props)) = entries.iter_mut().find(|(k, _)| k == "properties") {
                props.insert(
                    "compact",
                    bool_prop(
                        "Return compact JSON with Slack UI and profile avatar noise stripped",
                        Some(compact_default),
                    ),
                );
            }
        }
    }
    tools
}

pub fn tools_for(config: &ServerConfig) -> Vec<ToolDefinition> {
    let tools = all_tools_with_compact_default(config.compact_output);
    if config.transport == TransportMode::Stdio {
        return tools;
    }
    let has_user_token = config.slack.user_token.is_some();
    let allow_destructive = config.http_allow_destructive;
    tools
        .into_iter()
        .filter(|tool| {
            !HTTP_WITHHELD_ALWAYS.contains(&tool.name)
                && (has_user_token || !HTTP_WITHHELD_WITHOUT_USER_TOKEN.contains(&tool.name))
                && (allow_destructive || !HTTP_WITHHELD_DESTRUCTIVE.contains(&tool.name))
        })
        .collect()
}

/// Strips Slack UI and avatar noise for opt-in `compact: true` output (spec C2).
pub fn strip_slack_noise(value: &JsonValue) -> JsonValue {
    match value {
        JsonValue::Array(items) => JsonValue::Array(items.iter().map(strip_slack_noise).collect()),
        JsonValue::Object(entries) => {
            let has_non_empty_text = entries
                .iter()
                .any(|(k, v)| k == "text" && v.as_str().is_some_and(|s| !s.is_empty()));
            let mut out = Vec::with_capacity(entries.len());
            for (k, v) in entries {
                if k == "blocks" && has_non_empty_text {
                    continue;
                }
                if matches!(
                    k.as_str(),
                    "team"
                        | "user_team"
                        | "source_team"
                        | "client_msg_id"
                        | "user_profile"
                        | "bot_profile"
                        | "icons"
                ) {
                    continue;
                }
                if k == "emoji" {
                    out.push((k.clone(), v.clone()));
                } else if k == "profile" {
                    out.push((k.clone(), strip_profile_noise(v)));
                } else {
                    out.push((k.clone(), strip_slack_noise(v)));
                }
            }
            JsonValue::Object(out)
        }
        other => other.clone(),
    }
}

fn strip_profile_noise(value: &JsonValue) -> JsonValue {
    match value {
        JsonValue::Object(entries) => {
            let mut out = Vec::with_capacity(entries.len());
            for (k, v) in entries {
                if k == "avatar_hash" || k.starts_with("image_") {
                    continue;
                }
                out.push((k.clone(), strip_slack_noise(v)));
            }
            JsonValue::Object(out)
        }
        other => strip_slack_noise(other),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::resolve_config;
    use std::collections::BTreeMap;

    fn live_http_env_without_destructive_flag() -> BTreeMap<String, String> {
        let mut m = BTreeMap::new();
        m.insert("MCP_TRANSPORT".to_string(), "http".to_string());
        m.insert("SLACK_BOT_TOKEN".to_string(), "xoxb-test".to_string());
        m.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        m.insert("SLACK_TEAM_ID".to_string(), "T123".to_string());
        m.insert("SLACK_CHANNEL_IDS".to_string(), "".to_string());
        m.insert("SLACK_WRITE_MODE".to_string(), "user".to_string());
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

    #[test]
    fn tool_count_is_43_and_every_tool_declares_compact_param() {
        let default_tools = all_tools();
        assert_eq!(default_tools.len(), 43);
        let names: Vec<&str> = default_tools.iter().map(|t| t.name).collect();
        assert!(names.contains(&"slack_whoami"));
        assert!(names.contains(&"slack_remove_reaction"));

        for tool in &default_tools {
            let compact = tool
                .input_schema
                .get("properties")
                .and_then(|p| p.get("compact"))
                .expect("every tool must expose optional compact");
            assert_eq!(
                compact.get("type").and_then(|v| v.as_str()),
                Some("boolean")
            );
            assert_eq!(
                compact.get("default").and_then(|v| v.as_bool()),
                Some(false)
            );
        }

        for tool in all_tools_with_compact_default(true) {
            let compact = tool
                .input_schema
                .get("properties")
                .and_then(|p| p.get("compact"))
                .unwrap();
            assert_eq!(compact.get("default").and_then(|v| v.as_bool()), Some(true));
        }
    }

    #[test]
    fn http_tool_list_matches_live_config_and_withholds_destructive_when_unset() {
        // Prior 40 HTTP impersonation tools on main (41 minus stdio-only slack_download_file)
        // plus slack_whoami and slack_remove_reaction.
        let mut expected_live: Vec<&str> = vec![
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
            "slack_list_emoji",
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
            "slack_get_file_info",
            "slack_read_file",
            "slack_upload_file",
            "slack_list_user_groups",
            "slack_list_user_group_members",
            "slack_create_user_group",
            "slack_update_user_group",
            "slack_set_user_group_members",
            "slack_set_user_group_enabled",
        ];

        // Live deployment config sets SLACK_HTTP_ALLOW_DESTRUCTIVE=true in gitops values.yaml:
        // preserves all destructive tools alongside slack_whoami and slack_remove_reaction.
        let mut live_env = live_http_env_without_destructive_flag();
        live_env.insert(
            "SLACK_HTTP_ALLOW_DESTRUCTIVE".to_string(),
            "true".to_string(),
        );
        let live_cfg = resolve_config(&live_env).unwrap();
        let mut live_names: Vec<&str> = tools_for(&live_cfg).iter().map(|t| t.name).collect();
        assert_eq!(live_names.len(), 42);
        assert!(live_names.contains(&"slack_whoami"));
        assert!(live_names.contains(&"slack_remove_reaction"));
        assert!(live_names.contains(&"slack_delete_canvas"));
        assert!(live_names.contains(&"slack_set_user_group_enabled"));
        assert!(live_names.contains(&"slack_set_user_group_members"));
        assert!(!live_names.contains(&"slack_download_file"));
        live_names.sort_unstable();
        expected_live.sort_unstable();
        assert_eq!(live_names, expected_live);

        // When SLACK_HTTP_ALLOW_DESTRUCTIVE is unset (new-install chart default),
        // the 3 destructive tools are excluded while slack_whoami and slack_remove_reaction remain.
        let unset_env = live_http_env_without_destructive_flag();
        let unset_cfg = resolve_config(&unset_env).unwrap();
        let unset_names: Vec<&str> = tools_for(&unset_cfg).iter().map(|t| t.name).collect();
        assert_eq!(unset_names.len(), 39);
        assert!(unset_names.contains(&"slack_whoami"));
        assert!(unset_names.contains(&"slack_remove_reaction"));
        for withheld in HTTP_WITHHELD_DESTRUCTIVE {
            assert!(
                !unset_names.contains(withheld),
                "{withheld} must be excluded when SLACK_HTTP_ALLOW_DESTRUCTIVE is unset"
            );
        }

        // Bot-only HTTP still offers slack_whoami, while withholding slack_remove_reaction.
        let mut bot_http = live_http_env_without_destructive_flag();
        bot_http.remove("SLACK_USER_TOKEN");
        bot_http.remove("SLACK_WRITE_MODE");
        bot_http.insert("SLACK_CHANNEL_IDS".to_string(), "C1".to_string());
        let bot_names: Vec<&str> = tools_for(&resolve_config(&bot_http).unwrap())
            .iter()
            .map(|t| t.name)
            .collect();
        assert!(bot_names.contains(&"slack_whoami"));
        assert!(!bot_names.contains(&"slack_remove_reaction"));
    }

    #[test]
    fn strip_slack_noise_strips_ui_and_avatar_fields_recursively_while_keeping_content() {
        let input = JsonValue::parse(
            r#"{
                "ok": true,
                "messages": [
                    {
                        "text": "ship it",
                        "ts": "1700000000.000100",
                        "user": "U1",
                        "thread_ts": "1700000000.000001",
                        "reply_count": 2,
                        "reactions": [{"name": "rocket", "count": 1}],
                        "files": [{"id": "F1"}],
                        "attachments": [{"fallback": "f"}],
                        "edited": {"user": "U1", "ts": "1700000001.000000"},
                        "subtype": "thread_broadcast",
                        "blocks": [{"type": "rich_text"}],
                        "team": "T1",
                        "user_team": "T1",
                        "source_team": "T1",
                        "client_msg_id": "uuid-1",
                        "user_profile": {"real_name": "Alice"},
                        "bot_profile": {"name": "DeployBot"},
                        "icons": {"emoji": ":robot_face:"}
                    },
                    {
                        "text": "",
                        "ts": "1700000002.000100",
                        "blocks": [{"type": "section", "text": {"type": "mrkdwn", "text": "blocks-only"}}]
                    }
                ],
                "members": [
                    {
                        "id": "U1",
                        "team_id": "T1",
                        "profile": {
                            "real_name": "Alice",
                            "display_name": "alice",
                            "avatar_hash": "deadbeef",
                            "image_24": "https://img/24.png",
                            "image_72": "https://img/72.png",
                            "image_original": "https://img/orig.png"
                        }
                    }
                ],
                "emoji": {
                    "team": "https://emoji/team.png",
                    "icons": "https://emoji/icons.png"
                }
            }"#,
        )
        .unwrap();

        let stripped = strip_slack_noise(&input);
        let msgs = stripped.get("messages").and_then(|v| v.as_array()).unwrap();

        // Message 0 had non-empty text: blocks and noise keys gone; content fields preserved.
        let m0 = &msgs[0];
        for dropped in [
            "blocks",
            "team",
            "user_team",
            "source_team",
            "client_msg_id",
            "user_profile",
            "bot_profile",
            "icons",
        ] {
            assert!(!m0.contains_key(dropped), "{dropped} must be stripped");
        }
        for kept in [
            "text",
            "ts",
            "user",
            "thread_ts",
            "reply_count",
            "reactions",
            "files",
            "attachments",
            "edited",
            "subtype",
        ] {
            assert!(m0.contains_key(kept), "{kept} must be kept");
        }

        // Message 1 had empty text: blocks must be kept!
        let m1 = &msgs[1];
        assert!(m1.contains_key("blocks"));

        // Profile stripped avatar_hash and image_* while keeping real_name and display_name.
        let prof = stripped.get("members").and_then(|v| v.as_array()).unwrap()[0]
            .get("profile")
            .unwrap();
        assert_eq!(
            prof.get("real_name").and_then(|v| v.as_str()),
            Some("Alice")
        );
        assert_eq!(
            prof.get("display_name").and_then(|v| v.as_str()),
            Some("alice")
        );
        assert!(!prof.contains_key("avatar_hash"));
        assert!(!prof.contains_key("image_24"));
        assert!(!prof.contains_key("image_72"));
        assert!(!prof.contains_key("image_original"));

        // Custom emoji dictionary preserves entries named "team" or "icons".
        let emoji = stripped.get("emoji").unwrap();
        assert!(emoji.contains_key("team"));
        assert!(emoji.contains_key("icons"));
    }
}
