/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// ---------------------------------------------------------------------------
// Tool definitions and per-transport visibility
// ---------------------------------------------------------------------------
//
// Split out of index.ts so the advertised set is reachable from tests without
// importing the entrypoint, which starts a server as a side effect.

import type { ServerConfig } from "./config.js";

export const tools = [
  // ── Channels ────────────────────────────────────────────────────────
  {
    name: "slack_list_channels",
    description:
      "List public channels in the workspace (or a pre-defined subset via SLACK_CHANNEL_IDS)",
    inputSchema: {
      type: "object" as const,
      properties: {
        limit: {
          type: "number",
          description:
            "Maximum number of channels to return (default 100, max 200)",
          default: 100,
        },
        cursor: {
          type: "string",
          description: "Pagination cursor for the next page of results",
        },
      },
    },
  },
  {
    name: "slack_get_channel_info",
    description:
      "Get detailed information about a channel including topic, purpose, member count, and associated canvas ID",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel",
        },
      },
      required: ["channel_id"],
    },
  },
  {
    name: "slack_get_channel_history",
    description: "Get recent messages from a channel",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel",
        },
        limit: {
          type: "number",
          description: "Number of messages to retrieve (default 10)",
          default: 10,
        },
      },
      required: ["channel_id"],
    },
  },
  {
    name: "slack_get_thread_replies",
    description: "Get all replies in a message thread",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel containing the thread",
        },
        thread_ts: {
          type: "string",
          description:
            "The timestamp of the parent message (format: '1234567890.123456')",
        },
      },
      required: ["channel_id", "thread_ts"],
    },
  },
  {
    name: "slack_set_channel_topic",
    description: "Set the topic of a channel",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel",
        },
        topic: {
          type: "string",
          description: "The new topic text",
        },
      },
      required: ["channel_id", "topic"],
    },
  },

  {
    name: "slack_get_message",
    description:
      "Fetch a single message, either from a Slack permalink (https://<workspace>.slack.com/archives/<channel>/p<timestamp>) or from a channel ID and timestamp. Returns the message with its thread_ts if it belongs to a thread.",
    inputSchema: {
      type: "object" as const,
      properties: {
        permalink: {
          type: "string",
          description:
            "A Slack message permalink. When given, channel_id and timestamp are ignored.",
        },
        channel_id: {
          type: "string",
          description: "The ID of the channel containing the message",
        },
        timestamp: {
          type: "string",
          description:
            "The timestamp of the message (format: '1234567890.123456')",
        },
        thread_ts: {
          type: "string",
          description:
            "For a thread reply, the parent message's timestamp. Not needed for top-level messages.",
        },
      },
    },
  },
  {
    name: "slack_get_permalink",
    description: "Get a shareable permalink URL for a message",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel containing the message",
        },
        timestamp: {
          type: "string",
          description: "The timestamp of the message",
        },
      },
      required: ["channel_id", "timestamp"],
    },
  },

  // ── Channel membership ──────────────────────────────────────────────
  {
    name: "slack_join_channel",
    description:
      "Join a public channel. By default the bot joins (so it can read the channel afterwards); set as='user' to join as the authenticated user.",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel to join",
        },
        as: {
          type: "string",
          description: "Which identity joins: 'bot' (default) or 'user'",
          enum: ["bot", "user"],
          default: "bot",
        },
      },
      required: ["channel_id"],
    },
  },
  {
    name: "slack_leave_channel",
    description:
      "Leave a channel. By default the bot leaves; set as='user' to leave as the authenticated user.",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel to leave",
        },
        as: {
          type: "string",
          description: "Which identity leaves: 'bot' (default) or 'user'",
          enum: ["bot", "user"],
          default: "bot",
        },
      },
      required: ["channel_id"],
    },
  },
  {
    name: "slack_list_channel_members",
    description: "List the user IDs of a channel's members",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel",
        },
        limit: {
          type: "number",
          description:
            "Maximum number of members to return (default 100, max 200)",
          default: 100,
        },
        cursor: {
          type: "string",
          description: "Pagination cursor for the next page of results",
        },
      },
      required: ["channel_id"],
    },
  },
  {
    name: "slack_invite_to_channel",
    description: "Invite users to a channel as the authenticated user",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel",
        },
        user_ids: {
          type: "array",
          items: { type: "string" },
          description: "User IDs to invite (up to 1000)",
        },
      },
      required: ["channel_id", "user_ids"],
    },
  },

  // ── Custom emoji ────────────────────────────────────────────────────
  {
    name: "slack_list_emoji",
    description:
      "List the workspace's custom emoji, optionally filtered by a substring of the name. Values are image URLs, or 'alias:<name>' for aliases.",
    inputSchema: {
      type: "object" as const,
      properties: {
        query: {
          type: "string",
          description:
            "Case-insensitive substring to match against emoji names",
        },
        include_aliases: {
          type: "boolean",
          description: "Include alias entries (default true)",
          default: true,
        },
      },
    },
  },

  // ── Users ───────────────────────────────────────────────────────────
  {
    name: "slack_get_users",
    description:
      "Get a list of all users in the workspace with basic profile information",
    inputSchema: {
      type: "object" as const,
      properties: {
        cursor: {
          type: "string",
          description: "Pagination cursor for the next page of results",
        },
        limit: {
          type: "number",
          description:
            "Maximum number of users to return (default 100, max 200)",
          default: 100,
        },
      },
    },
  },
  {
    name: "slack_get_user_profile",
    description: "Get detailed profile information for a specific user",
    inputSchema: {
      type: "object" as const,
      properties: {
        user_id: {
          type: "string",
          description: "The ID of the user",
        },
      },
      required: ["user_id"],
    },
  },

  // ── Search ──────────────────────────────────────────────────────────
  {
    name: "slack_search_messages",
    description:
      "Search for messages across the workspace. Supports Slack search modifiers like 'in:#channel', 'from:@user', 'before:2025-01-01', etc.",
    inputSchema: {
      type: "object" as const,
      properties: {
        query: {
          type: "string",
          description: "The search query (supports Slack search modifiers)",
        },
        count: {
          type: "number",
          description: "Number of results to return (default 20, max 100)",
          default: 20,
        },
        sort: {
          type: "string",
          description: "Sort order: 'score' (relevance) or 'timestamp'",
          default: "score",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "slack_search_files",
    description:
      "Search for files across the workspace. Supports Slack search modifiers like 'in:#channel', 'from:@user', 'type:pdf', etc.",
    inputSchema: {
      type: "object" as const,
      properties: {
        query: {
          type: "string",
          description: "The search query (supports Slack search modifiers)",
        },
        count: {
          type: "number",
          description: "Number of results to return (default 20, max 100)",
          default: 20,
        },
        sort: {
          type: "string",
          description: "Sort order: 'score' (relevance) or 'timestamp'",
          default: "score",
        },
      },
      required: ["query"],
    },
  },

  // ── Messaging ───────────────────────────────────────────────────────
  {
    name: "slack_post_message",
    description:
      "Post a new message to a Slack channel as the authenticated user (not as a bot)",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel to post to",
        },
        text: {
          type: "string",
          description: "The message text to post (supports Slack mrkdwn)",
        },
      },
      required: ["channel_id", "text"],
    },
  },
  {
    name: "slack_reply_to_thread",
    description: "Reply to a specific message thread as the authenticated user",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel containing the thread",
        },
        thread_ts: {
          type: "string",
          description:
            "The timestamp of the parent message (format: '1234567890.123456')",
        },
        text: {
          type: "string",
          description: "The reply text (supports Slack mrkdwn)",
        },
      },
      required: ["channel_id", "thread_ts", "text"],
    },
  },
  {
    name: "slack_update_message",
    description: "Edit a previously sent message",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel containing the message",
        },
        timestamp: {
          type: "string",
          description: "The timestamp of the message to edit",
        },
        text: {
          type: "string",
          description: "The new message text (supports Slack mrkdwn)",
        },
      },
      required: ["channel_id", "timestamp", "text"],
    },
  },
  {
    name: "slack_add_reaction",
    description: "Add a reaction emoji to a message",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel containing the message",
        },
        timestamp: {
          type: "string",
          description: "The timestamp of the message to react to",
        },
        reaction: {
          type: "string",
          description: "The emoji name without colons (e.g. 'thumbsup')",
        },
      },
      required: ["channel_id", "timestamp", "reaction"],
    },
  },

  // ── Pins ────────────────────────────────────────────────────────────
  {
    name: "slack_list_pins",
    description: "List items pinned to a channel",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel",
        },
      },
      required: ["channel_id"],
    },
  },
  {
    name: "slack_pin_message",
    description: "Pin a message to a channel",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel containing the message",
        },
        timestamp: {
          type: "string",
          description: "The timestamp of the message to pin",
        },
      },
      required: ["channel_id", "timestamp"],
    },
  },
  {
    name: "slack_unpin_message",
    description: "Unpin a message from a channel",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel containing the message",
        },
        timestamp: {
          type: "string",
          description: "The timestamp of the message to unpin",
        },
      },
      required: ["channel_id", "timestamp"],
    },
  },

  // ── Bookmarks ───────────────────────────────────────────────────────
  {
    name: "slack_list_bookmarks",
    description: "List bookmarks for a channel",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel",
        },
      },
      required: ["channel_id"],
    },
  },
  {
    name: "slack_add_bookmark",
    description: "Add a bookmark (link) to a channel",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel",
        },
        title: {
          type: "string",
          description: "Title of the bookmark",
        },
        link: {
          type: "string",
          description: "URL for the bookmark",
        },
        emoji: {
          type: "string",
          description: "Emoji icon for the bookmark (e.g. ':link:')",
        },
      },
      required: ["channel_id", "title", "link"],
    },
  },

  // ── Canvases ────────────────────────────────────────────────────────
  {
    name: "slack_create_canvas",
    description:
      "Create a new Slack canvas. Content uses markdown format. Optionally attach to a channel.",
    inputSchema: {
      type: "object" as const,
      properties: {
        title: {
          type: "string",
          description: "Title of the canvas",
        },
        markdown: {
          type: "string",
          description:
            "Markdown content for the canvas body. Supports headings, lists, checklists, code blocks, bold, italic, links, tables, and @mentions.",
        },
        channel_id: {
          type: "string",
          description:
            "Optional channel ID to automatically tab the canvas into",
        },
      },
    },
  },
  {
    name: "slack_edit_canvas",
    description:
      "Edit an existing Slack canvas. Supports insert, replace, delete, and rename operations.",
    inputSchema: {
      type: "object" as const,
      properties: {
        canvas_id: {
          type: "string",
          description: "The ID of the canvas to edit (e.g. F1234ABCD)",
        },
        operation: {
          type: "string",
          description:
            "The edit operation: 'insert_at_start', 'insert_at_end', 'insert_before', 'insert_after', 'replace', 'delete', or 'rename'",
          enum: [
            "insert_at_start",
            "insert_at_end",
            "insert_before",
            "insert_after",
            "replace",
            "delete",
            "rename",
          ],
        },
        markdown: {
          type: "string",
          description:
            "Markdown content for the operation (not used for delete)",
        },
        section_id: {
          type: "string",
          description:
            "Section ID for relative operations (insert_before, insert_after, replace, delete). Use slack_lookup_canvas_sections to find section IDs.",
        },
      },
      required: ["canvas_id", "operation"],
    },
  },
  {
    name: "slack_lookup_canvas_sections",
    description:
      "Find sections within a canvas by heading type and/or text content. Returns section IDs that can be used with slack_edit_canvas.",
    inputSchema: {
      type: "object" as const,
      properties: {
        canvas_id: {
          type: "string",
          description: "The ID of the canvas",
        },
        section_types: {
          type: "array",
          items: { type: "string" },
          description:
            "Filter by section type: 'h1', 'h2', 'h3', or 'any_header'",
        },
        contains_text: {
          type: "string",
          description: "Filter sections containing this text",
        },
      },
      required: ["canvas_id"],
    },
  },
  {
    name: "slack_delete_canvas",
    description: "Permanently delete a canvas. This action cannot be undone.",
    inputSchema: {
      type: "object" as const,
      properties: {
        canvas_id: {
          type: "string",
          description: "The ID of the canvas to delete",
        },
      },
      required: ["canvas_id"],
    },
  },
  // ── Files ───────────────────────────────────────────────────────────
  {
    name: "slack_get_file_info",
    description:
      "Get metadata for a file (name, type, size, who shared it, where it is shared) by file ID or Slack file URL. Private download URLs are not returned.",
    inputSchema: {
      type: "object" as const,
      properties: {
        file: {
          type: "string",
          description:
            "The file ID (e.g. F1234ABCD) or a Slack file URL (https://<workspace>.slack.com/files/<user>/<file>/<name>)",
        },
      },
      required: ["file"],
    },
  },
  {
    name: "slack_read_file",
    description:
      "Read the content of a text file shared in Slack. Binary files are refused; use slack_download_file for those.",
    inputSchema: {
      type: "object" as const,
      properties: {
        file: {
          type: "string",
          description: "The file ID or a Slack file URL",
        },
        max_bytes: {
          type: "number",
          description:
            "Refuse files larger than this many bytes (default 1048576)",
          default: 1048576,
        },
      },
      required: ["file"],
    },
  },
  {
    name: "slack_upload_file",
    description:
      "Upload a file and share it into a channel, optionally in a thread. Provide the content as text, or base64 for binary data.",
    inputSchema: {
      type: "object" as const,
      properties: {
        channel_id: {
          type: "string",
          description: "The ID of the channel to share the file into",
        },
        filename: {
          type: "string",
          description: "File name including extension (e.g. report.csv)",
        },
        content: {
          type: "string",
          description:
            "Text content of the file. Mutually exclusive with content_base64.",
        },
        content_base64: {
          type: "string",
          description:
            "Base64-encoded binary content. Mutually exclusive with content.",
        },
        title: {
          type: "string",
          description: "Title shown in Slack (defaults to the filename)",
        },
        initial_comment: {
          type: "string",
          description: "Message text posted alongside the file",
        },
        thread_ts: {
          type: "string",
          description:
            "Share into this thread instead of the channel top level",
        },
      },
      required: ["channel_id", "filename"],
    },
  },
  {
    name: "slack_download_file",
    description:
      "Download a file from Slack to a path on the local machine. Refuses to overwrite an existing file. Available on the local (stdio) transport only.",
    inputSchema: {
      type: "object" as const,
      properties: {
        file: {
          type: "string",
          description: "The file ID or a Slack file URL",
        },
        output_path: {
          type: "string",
          description: "Absolute path to write the file to",
        },
      },
      required: ["file", "output_path"],
    },
  },

  // ── User groups ─────────────────────────────────────────────────────
  {
    name: "slack_list_user_groups",
    description:
      "List the workspace's user groups (@handles) with their IDs, names and member counts",
    inputSchema: {
      type: "object" as const,
      properties: {
        include_disabled: {
          type: "boolean",
          description: "Include disabled groups (default false)",
          default: false,
        },
      },
    },
  },
  {
    name: "slack_list_user_group_members",
    description: "List the user IDs that belong to a user group",
    inputSchema: {
      type: "object" as const,
      properties: {
        usergroup_id: {
          type: "string",
          description: "The ID of the user group (e.g. S1234ABCD)",
        },
      },
      required: ["usergroup_id"],
    },
  },
  {
    name: "slack_create_user_group",
    description: "Create a user group as the authenticated user",
    inputSchema: {
      type: "object" as const,
      properties: {
        name: {
          type: "string",
          description: "Display name of the group",
        },
        handle: {
          type: "string",
          description: "Mention handle without the @ (e.g. 'platform')",
        },
        description: {
          type: "string",
          description: "Short description of the group",
        },
        channel_ids: {
          type: "array",
          items: { type: "string" },
          description: "Default channels members are added to",
        },
      },
      required: ["name", "handle"],
    },
  },
  {
    name: "slack_update_user_group",
    description:
      "Update a user group's name, handle or description as the authenticated user",
    inputSchema: {
      type: "object" as const,
      properties: {
        usergroup_id: {
          type: "string",
          description: "The ID of the user group",
        },
        name: { type: "string", description: "New display name" },
        handle: { type: "string", description: "New mention handle" },
        description: { type: "string", description: "New description" },
      },
      required: ["usergroup_id"],
    },
  },
  {
    name: "slack_set_user_group_members",
    description:
      "Replace the full member list of a user group as the authenticated user. Slack has no add/remove primitive: read the current members first, then send the complete new list. A group cannot be emptied; disable it instead.",
    inputSchema: {
      type: "object" as const,
      properties: {
        usergroup_id: {
          type: "string",
          description: "The ID of the user group",
        },
        user_ids: {
          type: "array",
          items: { type: "string" },
          description: "The complete list of user IDs the group should contain",
        },
      },
      required: ["usergroup_id", "user_ids"],
    },
  },
  {
    name: "slack_set_user_group_enabled",
    description: "Enable or disable a user group as the authenticated user",
    inputSchema: {
      type: "object" as const,
      properties: {
        usergroup_id: {
          type: "string",
          description: "The ID of the user group",
        },
        enabled: {
          type: "boolean",
          description: "true to enable, false to disable",
        },
      },
      required: ["usergroup_id", "enabled"],
    },
  },
] as const;

/**
 * Tools withheld on the HTTP transport regardless of which tokens exist.
 *
 * `slack_download_file` writes to the local disk. On stdio that is the
 * machine of the person who started the process; on HTTP it would be the
 * pod's filesystem, reachable by every authorised caller and useful to none
 * of them. No credential makes that appropriate, so no credential unlocks it.
 */
export const HTTP_WITHHELD_ALWAYS = new Set<string>(["slack_download_file"]);

/**
 * Tools withheld on the HTTP transport ONLY when `SLACK_USER_TOKEN` is
 * absent. These tools require the user token. When the user token is available
 * (impersonation mode), all tools are unlocked.
 */
export const HTTP_WITHHELD_WITHOUT_USER_TOKEN = new Set([
  "slack_set_channel_topic",
  "slack_invite_to_channel",
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
  // Workspace-scoped, like slack_get_users: member enumeration and every
  // write. The handle list on its own stays available.
  "slack_list_user_group_members",
  "slack_create_user_group",
  "slack_update_user_group",
  "slack_set_user_group_members",
  "slack_set_user_group_enabled",
]);

/**
 * The withheld set for bot-only deployments (where user token is absent).
 */
export const HTTP_WITHHELD_TOOLS = HTTP_WITHHELD_WITHOUT_USER_TOKEN;

export function toolsFor(config: ServerConfig) {
  if (config.transport === "stdio") return [...tools];
  const hasUserToken = Boolean(config.slack.userToken);
  return tools.filter(
    (tool) =>
      !HTTP_WITHHELD_ALWAYS.has(tool.name) &&
      (hasUserToken || !HTTP_WITHHELD_WITHOUT_USER_TOKEN.has(tool.name)),
  );
}
