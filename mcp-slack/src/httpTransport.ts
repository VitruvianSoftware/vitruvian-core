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
// Streamable HTTP transport
// ---------------------------------------------------------------------------
//
// Gemini Enterprise's custom MCP connector speaks Streamable HTTP exclusively —
// its docs state the legacy SSE transport is not supported — so this is the one
// transport that makes a remote harness work, not a preference.
//
// This module is imported dynamically by index.ts only when MCP_TRANSPORT=http,
// so the stdio path never loads it and its behaviour is untouched.

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";

import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

import { AuthError, createTokenVerifier, type TokenVerifier } from "./auth.js";
import type { HttpConfig } from "./config.js";

const MCP_PATH = "/mcp";
const HEALTH_PATH = "/health";

/**
 * Writes an RFC 6750 style rejection.
 *
 * The `WWW-Authenticate` error/description carry the same self-describing text
 * as the thrown error, so a misconfiguration is legible from `curl -i` without
 * needing access to the server's logs — which is the situation someone
 * debugging a Spark connection is actually in.
 */
function writeAuthFailure(res: ServerResponse, error: AuthError): void {
  res.writeHead(error.status, {
    "Content-Type": "application/json",
    "WWW-Authenticate":
      `Bearer error="${error.code}", ` +
      `error_description="${error.message.replace(/"/g, "'")}"`,
  });
  res.end(
    JSON.stringify({
      jsonrpc: "2.0",
      error: { code: -32001, message: error.message },
      id: null,
    })
  );
}

function writeNotFound(res: ServerResponse): void {
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "not_found" }));
}

/**
 * Starts the HTTP listener and binds the MCP server to it.
 *
 * `verifier` is injectable so the request-routing and rejection behaviour can
 * be tested without a live IdP.
 */
export async function startHttpTransport(
  server: Server,
  config: HttpConfig,
  verifier: TokenVerifier = createTokenVerifier({
    issuer: config.issuer,
    projectId: config.projectId,
  })
): Promise<{
  address: () => { port: number };
  close: () => Promise<void>;
}> {
  // sessionIdGenerator: undefined puts the transport in stateless mode — every
  // request is self-contained. That suits a single-tenant deployment behind an
  // IdP: the bearer token, not a server-side session, is what carries identity.
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
  });
  await server.connect(transport);

  const httpServer = createServer(
    (req: IncomingMessage, res: ServerResponse) => {
      // Every rejection has to be caught here. `handle` is async and its
      // result is discarded, so anything it throws that isn't an AuthError —
      // a JWKS fetch failure is the realistic one, since that reaches the
      // network on the auth path — would otherwise become an unhandled
      // rejection: the request never gets a response, and Node's default
      // behaviour since v15 is to terminate the process. A transient IdP
      // blip taking the server down is not the failure mode to have on a
      // deployment whose whole job is being reachable.
      handle(req, res).catch((error: unknown) => {
        process.stderr.write(
          `mcp-slack: unhandled error serving ${req.method} ${req.url}: ` +
            `${error instanceof Error ? error.stack ?? error.message : String(error)}\n`
        );
        if (res.headersSent) {
          res.destroy();
          return;
        }
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            jsonrpc: "2.0",
            error: { code: -32603, message: "Internal server error" },
            id: null,
          })
        );
      });
    }
  );

  async function handle(
    req: IncomingMessage,
    res: ServerResponse
  ): Promise<void> {
    const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "local"}`);

    // Unauthenticated on purpose: a liveness probe that requires a token tells
    // you the IdP is reachable, not that this process is healthy.
    if (url.pathname === HEALTH_PATH) {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok" }));
      return;
    }

    if (url.pathname !== MCP_PATH) {
      writeNotFound(res);
      return;
    }

    try {
      await verifier.verifyAuthorizationHeader(req.headers.authorization);
    } catch (error) {
      if (error instanceof AuthError) {
        writeAuthFailure(res, error);
        return;
      }
      throw error;
    }

    await transport.handleRequest(req, res);
  }

  await new Promise<void>((resolve) => {
    httpServer.listen(config.port, resolve);
  });

  return {
    /**
     * The address actually bound. Only meaningful after `listen` resolved,
     * which is why it is a method rather than the configured port: tests bind
     * port 0 and need to discover what the OS chose.
     */
    address: () => {
      const address = httpServer.address();
      if (address === null || typeof address === "string") {
        throw new Error("HTTP server is not bound to a TCP port");
      }
      return address;
    },
    close: () =>
      new Promise<void>((resolve, reject) => {
        httpServer.close((err) => (err ? reject(err) : resolve()));
      }),
  };
}
