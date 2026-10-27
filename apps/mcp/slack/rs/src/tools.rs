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

pub const HTTP_WITHHELD_WITHOUT_USER_TOKEN: &[&str] = &[
    "slack_set_channel_topic",
    "slack_invite_to_channel",
    "slack_mark_read",
    "slack_list_unread",
    "slack_add_reaction",
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
    vec![
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
            description: "Read the content of a text file shared in Slack. Binary files are refused; use slack_download_file for those.",
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
    ]
}

pub fn tools_for(config: &ServerConfig) -> Vec<ToolDefinition> {
    let tools = all_tools();
    if config.transport == TransportMode::Stdio {
        return tools;
    }
    let has_user_token = config.slack.user_token.is_some();
    tools
        .into_iter()
        .filter(|tool| {
            !HTTP_WITHHELD_ALWAYS.contains(&tool.name)
                && (has_user_token || !HTTP_WITHHELD_WITHOUT_USER_TOKEN.contains(&tool.name))
        })
        .collect()
}
