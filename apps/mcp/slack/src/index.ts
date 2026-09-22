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

import { toolsFor } from "./tools.js";
import { dispatch } from "./dispatch.js";
import { SlackClient } from "./slackClient.js";
import { ConfigError, resolveConfig, type ServerConfig } from "./config.js";

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

  const client = new SlackClient(config.slack, {
    channelGuard: config.channelGuard,
    writeToken: config.writeToken,
  });

  const advertisedToolNames = new Set<string>(
    toolsFor(config).map((t) => t.name),
  );
  const advertisedTools = toolsFor(config);

  /**
   * Builds a fresh `Server`. A factory rather than a shared instance because
   * the HTTP transport needs a new `Server` (and a new
   * `StreamableHTTPServerTransport`) per request — see httpTransport.ts's
   * `startHttpTransport` doc comment for why a shared pair is actively wrong
   * in stateless mode, not merely unnecessary.
   *
   * Safe to call repeatedly today: `client`, `advertisedToolNames` and
   * `advertisedTools` above are immutable, derived once from `config`, and
   * hold no per-connection state, so every `Server` this returns behaves
   * identically. **Keep it that way** — anything this closure captures must
   * hold no per-caller state. A cache keyed on anything caller-derived would
   * reintroduce GHSA-345p's failure mode one layer up, in a place a
   * per-request transport can no longer catch.
   */
  function createServer(): Server {
    const server = new Server(
      { name: "mcp-slack", version: "2.0.0" },
      { capabilities: { tools: {} } },
    );

    // ── Tool handler ───────────────────────────────────────────────────

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
            `Tool ${request.params.name} is not available on this transport.`,
          );
        }

        const result = await dispatch(client, request.params.name, args);

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
      tools: advertisedTools,
    }));

    return server;
  }

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
          `${error instanceof Error ? error.message : String(error)}`,
      );
      process.exit(1);
    }

    const listener = await startHttpTransport(createServer, config.http!);

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
        `${config.channelGuard.allowed.length} channels allow-listed)\n`,
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
        `  expects scope: ${fullScopeString(config.http!.projectId)}\n`,
    );
    return;
  }

  const transport = new StdioServerTransport();
  await createServer().connect(transport);

  // Note: All initialization logs must strictly use stderr to avoid violating the MCP stdio transport protocol.
  process.stderr.write(
    `mcp-slack server v2.0.0 running on stdio (${advertisedTools.length} tools)\n`,
  );
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
