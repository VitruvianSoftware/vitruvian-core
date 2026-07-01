#!/usr/bin/env node
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


import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

const tools = [
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

// ---------------------------------------------------------------------------
// Slack API client with dual-token support
// ---------------------------------------------------------------------------

class SlackClient {
  private botHeaders: Record<string, string>;
  private userHeaders: Record<string, string>;
  private teamId: string;

  constructor(botToken: string, userToken: string, teamId: string) {
    this.botHeaders = {
      Authorization: `Bearer ${botToken}`,
      "Content-Type": "application/json",
    };
    this.userHeaders = {
      Authorization: `Bearer ${userToken}`,
      "Content-Type": "application/json",
    };
    this.teamId = teamId;
  }

  // Helper to make Slack API calls
  private async api(
    method: string,
    params: Record<string, unknown>,
    token: "bot" | "user" = "bot",
    httpMethod: "GET" | "POST" = "GET"
  ): Promise<unknown> {
    const headers = token === "bot" ? this.botHeaders : this.userHeaders;

    if (httpMethod === "GET") {
      const qs = new URLSearchParams();
      for (const [k, v] of Object.entries(params)) {
        if (v !== undefined && v !== null) qs.append(k, String(v));
      }
      const res = await fetch(`https://slack.com/api/${method}?${qs}`, {
        headers,
      });
      return res.json();
    }

    const res = await fetch(`https://slack.com/api/${method}`, {
      method: "POST",
      headers,
      body: JSON.stringify(params),
    });
    return res.json();
  }

  // ── Channels (Bot Token) ────────────────────────────────────────────

  async listChannels(limit = 100, cursor?: string) {
    const predefinedChannelIds = process.env.SLACK_CHANNEL_IDS;

    if (!predefinedChannelIds) {
      const params: Record<string, unknown> = {
        types: "public_channel",
        exclude_archived: "true",
        limit: Math.min(limit, 200),
        team_id: this.teamId,
      };
      if (cursor) params.cursor = cursor;
      return this.api("conversations.list", params);
    }

    const channels = [];
    for (const channelId of predefinedChannelIds.split(",").map((s: string) => s.trim())) {
      const data = (await this.api("conversations.info", {
        channel: channelId,
      })) as { ok: boolean; channel?: { is_archived: boolean } };
      if (data.ok && data.channel && !data.channel.is_archived) {
        channels.push(data.channel);
      }
    }
    return { ok: true, channels, response_metadata: { next_cursor: "" } };
  }

  async getChannelInfo(channelId: string) {
    return this.api("conversations.info", {
      channel: channelId,
      include_num_members: "true",
    });
  }

  async getChannelHistory(channelId: string, limit = 10) {
    return this.api("conversations.history", {
      channel: channelId,
      limit,
    });
  }

  async getThreadReplies(channelId: string, threadTs: string) {
    return this.api("conversations.replies", {
      channel: channelId,
      ts: threadTs,
    });
  }

  async setChannelTopic(channelId: string, topic: string) {
    return this.api(
      "conversations.setTopic",
      { channel: channelId, topic },
      "user",
      "POST"
    );
  }

  // ── Users (Bot Token) ───────────────────────────────────────────────

  async getUsers(limit = 100, cursor?: string) {
    const params: Record<string, unknown> = {
      limit: Math.min(limit, 200),
      team_id: this.teamId,
    };
    if (cursor) params.cursor = cursor;
    return this.api("users.list", params);
  }

  async getUserProfile(userId: string) {
    return this.api("users.profile.get", {
      user: userId,
      include_labels: "true",
    });
  }

  // ── Search (User Token) ─────────────────────────────────────────────

  async searchMessages(query: string, count = 20, sort = "score") {
    return this.api(
      "search.messages",
      { query, count: Math.min(count, 100), sort },
      "user"
    );
  }

  async searchFiles(query: string, count = 20, sort = "score") {
    return this.api(
      "search.files",
      { query, count: Math.min(count, 100), sort },
      "user"
    );
  }

  // ── Messaging (User Token) ─────────────────────────────────────────

  async postMessage(channelId: string, text: string) {
    return this.api(
      "chat.postMessage",
      { channel: channelId, text },
      "user",
      "POST"
    );
  }

  async replyToThread(channelId: string, threadTs: string, text: string) {
    return this.api(
      "chat.postMessage",
      { channel: channelId, thread_ts: threadTs, text },
      "user",
      "POST"
    );
  }

  async updateMessage(channelId: string, ts: string, text: string) {
    return this.api(
      "chat.update",
      { channel: channelId, ts, text },
      "user",
      "POST"
    );
  }

  async addReaction(channelId: string, timestamp: string, reaction: string) {
    return this.api(
      "reactions.add",
      { channel: channelId, timestamp, name: reaction },
      "user",
      "POST"
    );
  }

  // ── Pins (User Token) ──────────────────────────────────────────────

  async listPins(channelId: string) {
    return this.api("pins.list", { channel: channelId }, "bot");
  }

  async pinMessage(channelId: string, timestamp: string) {
    return this.api(
      "pins.add",
      { channel: channelId, timestamp },
      "user",
      "POST"
    );
  }

  async unpinMessage(channelId: string, timestamp: string) {
    return this.api(
      "pins.remove",
      { channel: channelId, timestamp },
      "user",
      "POST"
    );
  }

  // ── Bookmarks (Bot Token for read, User Token for write) ───────────

  async listBookmarks(channelId: string) {
    return this.api("bookmarks.list", { channel_id: channelId }, "bot");
  }

  async addBookmark(
    channelId: string,
    title: string,
    link: string,
    emoji?: string
  ) {
    const params: Record<string, unknown> = {
      channel_id: channelId,
      title,
      type: "link",
      link,
    };
    if (emoji) params.emoji = emoji;
    return this.api("bookmarks.add", params, "user", "POST");
  }

  // ── Canvases (User Token) ──────────────────────────────────────────

  async createCanvas(title?: string, markdown?: string, channelId?: string) {
    const params: Record<string, unknown> = {};
    if (title) params.title = title;
    if (markdown) {
      params.document_content = { type: "markdown", markdown };
    }
    if (channelId) params.channel_id = channelId;
    return this.api("canvases.create", params, "user", "POST");
  }

  async editCanvas(
    canvasId: string,
    operation: string,
    markdown?: string,
    sectionId?: string
  ) {
    const change: Record<string, unknown> = { operation };

    if (operation === "rename" && markdown) {
      change.title_content = { type: "markdown", markdown };
    } else if (operation !== "delete" && markdown) {
      change.document_content = { type: "markdown", markdown };
    }

    if (sectionId) change.section_id = sectionId;

    return this.api(
      "canvases.edit",
      { canvas_id: canvasId, changes: [change] },
      "user",
      "POST"
    );
  }

  async lookupCanvasSections(
    canvasId: string,
    sectionTypes?: string[],
    containsText?: string
  ) {
    const criteria: Record<string, unknown> = {};
    if (sectionTypes?.length) criteria.section_types = sectionTypes;
    if (containsText) criteria.contains_text = containsText;

    return this.api(
      "canvases.sections.lookup",
      { canvas_id: canvasId, criteria },
      "user",
      "POST"
    );
  }

  async deleteCanvas(canvasId: string) {
    return this.api(
      "canvases.delete",
      { canvas_id: canvasId },
      "user",
      "POST"
    );
  }
}

// ---------------------------------------------------------------------------
// MCP Server
// ---------------------------------------------------------------------------

async function main() {
  const botToken = process.env.SLACK_BOT_TOKEN;
  const userToken = process.env.SLACK_USER_TOKEN;
  const teamId = process.env.SLACK_TEAM_ID;

  if (!botToken || !userToken || !teamId) {
    console.error(
      "Required environment variables: SLACK_BOT_TOKEN, SLACK_USER_TOKEN, SLACK_TEAM_ID"
    );
    process.exit(1);
  }

  const server = new Server(
    { name: "mcp-slack", version: "2.0.0" },
    { capabilities: { tools: {} } }
  );

  const client = new SlackClient(botToken, userToken, teamId);

  // ── Tool handler ─────────────────────────────────────────────────────

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const args = (request.params.arguments ?? {}) as Record<string, unknown>;
    try {
      let result: unknown;

      switch (request.params.name) {
        // Channels
        case "slack_list_channels":
          result = await client.listChannels(
            args.limit as number | undefined,
            args.cursor as string | undefined
          );
          break;
        case "slack_get_channel_info":
          result = await client.getChannelInfo(args.channel_id as string);
          break;
        case "slack_get_channel_history":
          result = await client.getChannelHistory(
            args.channel_id as string,
            args.limit as number | undefined
          );
          break;
        case "slack_get_thread_replies":
          result = await client.getThreadReplies(
            args.channel_id as string,
            args.thread_ts as string
          );
          break;
        case "slack_set_channel_topic":
          result = await client.setChannelTopic(
            args.channel_id as string,
            args.topic as string
          );
          break;

        // Users
        case "slack_get_users":
          result = await client.getUsers(
            args.limit as number | undefined,
            args.cursor as string | undefined
          );
          break;
        case "slack_get_user_profile":
          result = await client.getUserProfile(args.user_id as string);
          break;

        // Search
        case "slack_search_messages":
          result = await client.searchMessages(
            args.query as string,
            args.count as number | undefined,
            args.sort as string | undefined
          );
          break;
        case "slack_search_files":
          result = await client.searchFiles(
            args.query as string,
            args.count as number | undefined,
            args.sort as string | undefined
          );
          break;

        // Messaging
        case "slack_post_message":
          result = await client.postMessage(
            args.channel_id as string,
            args.text as string
          );
          break;
        case "slack_reply_to_thread":
          result = await client.replyToThread(
            args.channel_id as string,
            args.thread_ts as string,
            args.text as string
          );
          break;
        case "slack_update_message":
          result = await client.updateMessage(
            args.channel_id as string,
            args.timestamp as string,
            args.text as string
          );
          break;
        case "slack_add_reaction":
          result = await client.addReaction(
            args.channel_id as string,
            args.timestamp as string,
            args.reaction as string
          );
          break;

        // Pins
        case "slack_list_pins":
          result = await client.listPins(args.channel_id as string);
          break;
        case "slack_pin_message":
          result = await client.pinMessage(
            args.channel_id as string,
            args.timestamp as string
          );
          break;
        case "slack_unpin_message":
          result = await client.unpinMessage(
            args.channel_id as string,
            args.timestamp as string
          );
          break;

        // Bookmarks
        case "slack_list_bookmarks":
          result = await client.listBookmarks(args.channel_id as string);
          break;
        case "slack_add_bookmark":
          result = await client.addBookmark(
            args.channel_id as string,
            args.title as string,
            args.link as string,
            args.emoji as string | undefined
          );
          break;

        // Canvases
        case "slack_create_canvas":
          result = await client.createCanvas(
            args.title as string | undefined,
            args.markdown as string | undefined,
            args.channel_id as string | undefined
          );
          break;
        case "slack_edit_canvas":
          result = await client.editCanvas(
            args.canvas_id as string,
            args.operation as string,
            args.markdown as string | undefined,
            args.section_id as string | undefined
          );
          break;
        case "slack_lookup_canvas_sections":
          result = await client.lookupCanvasSections(
            args.canvas_id as string,
            args.section_types as string[] | undefined,
            args.contains_text as string | undefined
          );
          break;
        case "slack_delete_canvas":
          result = await client.deleteCanvas(args.canvas_id as string);
          break;

        default:
          throw new Error(`Unknown tool: ${request.params.name}`);
      }

      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              error: error instanceof Error ? error.message : String(error),
            }),
          },
        ],
      };
    }
  });

  // ── Tool listing ─────────────────────────────────────────────────────

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [...tools],
  }));

  // ── Start ────────────────────────────────────────────────────────────

  const transport = new StdioServerTransport();
  await server.connect(transport);
  
  // Note: All initialization logs must strictly use stderr to avoid violating the MCP stdio transport protocol.
  process.stderr.write("mcp-slack server v2.0.0 running on stdio (22 tools)\n");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
