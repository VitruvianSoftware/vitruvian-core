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
    description:
      "Reply to a specific message thread as the authenticated user",
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
    description:
      "Permanently delete a canvas. This action cannot be undone.",
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
] as const;

/**
 * For backwards compatibility with external references: empty set since all
 * tools are available in impersonation mode when user token is present.
 */
export const HTTP_WITHHELD_ALWAYS = new Set<string>();

/**
 * Tools withheld on the HTTP transport ONLY when `SLACK_USER_TOKEN` is
 * absent. These tools require the user token. When the user token is available
 * (impersonation mode), all tools are unlocked.
 */
export const HTTP_WITHHELD_WITHOUT_USER_TOKEN = new Set([
  "slack_set_channel_topic",
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
]);

/**
 * The withheld set for bot-only deployments (where user token is absent).
 */
export const HTTP_WITHHELD_TOOLS = HTTP_WITHHELD_WITHOUT_USER_TOKEN;

export function toolsFor(config: ServerConfig) {
  if (config.transport === "stdio" || config.slack.userToken) {
    return [...tools];
  }
  return tools.filter((tool) => !HTTP_WITHHELD_TOOLS.has(tool.name));
}


