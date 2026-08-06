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

import { ChannelNotAllowedError } from "./channelAllowlist.js";
import { SlackClient } from "./slackClient.js";
import {
  ConfigError,
  resolveConfig,
  type ServerConfig,
  type SlackCredentials,
  type WriteTokenPreference,
} from "./config.js";

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
// MCP Server
// ---------------------------------------------------------------------------

/**
 * Tools that call Slack with the user token and have no bot-token equivalent.
 *
 * They are withheld from the HTTP transport's tool list because the user token
 * is not present there at all — advertising them would offer a remote caller
 * capabilities that can only fail. Note `slack_post_message`,
 * `slack_reply_to_thread` and `slack_update_message` are deliberately absent
 * from this list: they route to whichever credential the transport configures,
 * so they work on both.
 */
const USER_TOKEN_ONLY_TOOLS = new Set([
  "slack_set_channel_topic",
  "slack_search_messages",
  "slack_search_files",
  "slack_add_reaction",
  "slack_pin_message",
  "slack_unpin_message",
  "slack_add_bookmark",
  "slack_create_canvas",
  "slack_edit_canvas",
  "slack_lookup_canvas_sections",
  "slack_delete_canvas",
]);

function toolsFor(config: ServerConfig) {
  if (config.transport === "stdio") return [...tools];
  return tools.filter((tool) => !USER_TOKEN_ONLY_TOOLS.has(tool.name));
}

async function main() {
  let config: ServerConfig;
  try {
    config = resolveConfig(process.env);
  } catch (error) {
    if (error instanceof ConfigError || error instanceof Error) {
      // stderr only: stdout is the MCP stdio transport's wire protocol.
      console.error(`Configuration error: ${error.message}`);
      process.exit(1);
    }
    throw error;
  }

  const server = new Server(
    { name: "mcp-slack", version: "2.0.0" },
    { capabilities: { tools: {} } }
  );

  const client = new SlackClient(config.slack, {
    channelGuard: config.channelGuard,
    writeToken: config.writeToken,
  });

  // ── Tool handler ─────────────────────────────────────────────────────

  const advertisedToolNames = new Set<string>(toolsFor(config).map((t) => t.name));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const args = (request.params.arguments ?? {}) as Record<string, unknown>;
    try {
      // Dispatch consults the same set ListTools advertises. It previously did
      // not, which made the filter presentation-only: a withheld tool could be
      // invoked by name and was refused further down, by api() finding no
      // user-token headers. That still holds as a backstop, but three separate
      // reviewers read this filter as the control while it wasn't one — so the
      // code now does what it reads as doing, and the credential is the second
      // line rather than the only one.
      if (!advertisedToolNames.has(request.params.name)) {
        throw new Error(
          `Tool ${request.params.name} is not available on this transport.`
        );
      }

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

  const advertisedTools = toolsFor(config);
  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: advertisedTools,
  }));

  // ── Start ────────────────────────────────────────────────────────────

  if (config.transport === "http") {
    const { startHttpTransport } = await import("./httpTransport.js");
    const { fullScopeString } = await import("./auth.js");
    await startHttpTransport(server, config.http!);
    process.stderr.write(
      `mcp-slack server v2.0.0 running on http :${config.http!.port} ` +
        `(${advertisedTools.length} tools, ` +
        `${config.channelGuard.allowed.length} channels allow-listed)\n`
    );
    // Echo the identity settings at startup. OIDC_PROJECT_ID has to match a
    // value produced elsewhere (the zitadel-apps-mcp-slack stack output), and a
    // wrong-but-well-formed one is otherwise only discovered on the first
    // request — as a 403 demanding a scope that is itself wrong. Printing the
    // scope this server expects makes it comparable against the stack output
    // and against what gets pasted into the client, before anyone connects.
    process.stderr.write(
      `  issuer:   ${config.http!.issuer}\n` +
        `  project:  ${config.http!.projectId}\n` +
        `  expects scope: ${fullScopeString(config.http!.projectId)}\n`
    );
    return;
  }

  const transport = new StdioServerTransport();
  await server.connect(transport);

  // Note: All initialization logs must strictly use stderr to avoid violating the MCP stdio transport protocol.
  process.stderr.write(
    `mcp-slack server v2.0.0 running on stdio (${advertisedTools.length} tools)\n`
  );
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
