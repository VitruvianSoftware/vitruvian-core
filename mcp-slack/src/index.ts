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
import { HTTP_WITHHELD_TOOLS, tools, toolsFor } from "./tools.js";
import { SlackClient } from "./slackClient.js";
import {
  ConfigError,
  resolveConfig,
  type ServerConfig,
  type SlackCredentials,
  type WriteTokenPreference,
} from "./config.js";

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

    // Deliberately before the listener binds. The allow-list is the only thing
    // standing between a public endpoint and every conversation this bot can
    // reach, and a typo'd private channel ID pasted into SLACK_CHANNEL_IDS is
    // the mistake it cannot catch on its own — the ID is on the list, so it is
    // admitted. Refusing to start is the whole point: a server that came up and
    // logged a warning would already be serving.
    try {
      await client.verifyAllowlistVisibility();
    } catch (error) {
      console.error(
        `Allow-list verification failed: ` +
          `${error instanceof Error ? error.message : String(error)}`
      );
      process.exit(1);
    }

    const listener = await startHttpTransport(server, config.http!);

    // A pod being rolled gets SIGTERM, and without a handler Node's default is
    // to exit immediately — every in-flight request dies mid-response. The
    // kubelet has already removed this pod from the Service endpoints by the
    // time the signal arrives, so there is nothing to gain by exiting fast and
    // a request to lose. Once, not per-signal: a second SIGTERM during the
    // drain would otherwise start a second one.
    let draining = false;
    const drain = (signal: NodeJS.Signals) => {
      if (draining) return;
      draining = true;
      process.stderr.write(`${signal} received, draining\n`);
      listener
        .close()
        .then(() => process.exit(0))
        .catch((error) => {
          console.error(`Drain failed: ${error}`);
          process.exit(1);
        });
    };
    process.on("SIGTERM", drain);
    process.on("SIGINT", drain);
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
        // The count, not the IDs. It confirms the variable parsed into what
        // the operator meant — the failure worth catching is a quoting mistake
        // that collapses several subjects into one string, which reads as
        // "1 subject" here and as an inexplicable 403 an hour later.
        `  serving:  ${config.http!.allowedSubjects.length} allowed subject(s)\n` +
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
