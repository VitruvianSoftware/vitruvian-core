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

import { createServer as createHttpServer, type IncomingMessage, type ServerResponse } from "node:http";

import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

import { AuthError, createTokenVerifier, type TokenVerifier } from "./auth.js";
import type { HttpConfig } from "./config.js";

const MCP_PATH = "/mcp";
const HEALTH_PATH = "/health";

/**
 * Makes a message safe to carry inside an RFC 7235 quoted-string.
 *
 * Two distinct failures, both measured rather than reasoned about:
 *
 *   - CR, LF and NUL make Node's `writeHead` throw `ERR_INVALID_CHAR`. Node
 *     rejects them before anything reaches the wire, so this was never an
 *     injection risk — but the throw turned a diagnostic 403 into an opaque
 *     500, losing the self-describing error at exactly the moment something
 *     strange is in the token.
 *   - A double quote *sends successfully* and produces a malformed
 *     quoted-string, so a strict client mis-reads where the value ends. That
 *     one fails silently, which makes it the more dangerous of the two.
 */
export function headerSafe(message: string): string {
  return message
    .replace(/"/g, "'")
    .replace(/[^\x20-\x7e]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Writes an RFC 6750 style rejection.
 *
 * The `WWW-Authenticate` error/description carry the same self-describing text
 * as the thrown error, so a misconfiguration is legible from `curl -i` without
 * needing access to the server's logs — which is the situation someone
 * debugging a Spark connection is actually in.
 */
function writeAuthFailure(res: ServerResponse, error: AuthError): void {
  // Record the refusal before answering it.
  //
  // The presented subject already travels in the response body and the
  // WWW-Authenticate header — which serves the operator setting this up, since
  // they are the caller and can read their own `sub` off a curl. It does
  // nothing for the case the alert exists for: when someone we do not know is
  // knocking with an instance-issued token, that identity went to *them* and
  // we kept none of it. Detection without attribution.
  //
  // Only 403s. This endpoint is on the public internet and will be scanned, so
  // logging every 401 would bury the signal in unauthenticated noise. A 403
  // here means the caller held a validly-signed, unexpired token audienced for
  // our project and was refused anyway — which is precisely the cross-client
  // path Zitadel documents as open, and the only externally-visible evidence
  // it is real rather than theoretical.
  if (error.status === 403) {
    process.stderr.write(
      `mcp-slack: refused ${error.code}` +
        (error.presented
          ? ` ${error.presentedLabel ?? "presented"}=${headerSafe(error.presented)}`
          : "") +
        `: ${headerSafe(error.message)}\n`
    );
  }

  // A 503 must not carry a WWW-Authenticate challenge. That header means
  // "here is how to authenticate", which is a lie when the failure is ours —
  // it would send a caller holding a valid token off to re-authenticate
  // against an IdP that is down.
  if (error.status === 503) {
    res.writeHead(503, {
      "Content-Type": "application/json",
      "Retry-After": "30",
    });
    res.end(
      JSON.stringify({
        jsonrpc: "2.0",
        error: { code: -32001, message: error.message },
        id: null,
      })
    );
    return;
  }

  res.writeHead(error.status, {
    "Content-Type": "application/json",
    "WWW-Authenticate":
      `Bearer error="${error.code}", ` +
      `error_description="${headerSafe(error.message)}"`,
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
 * Starts the HTTP listener.
 *
 * `createServer` is a **factory**, not a shared instance — deliberately.
 * `StreamableHTTPServerTransport` in stateless mode (`sessionIdGenerator:
 * undefined`) is documented as single-use: `handleRequest` throws on a
 * transport's second call (`_hasHandledRequest`, set unconditionally on the
 * first). A `Server`/`transport` pair built once at startup and reused across
 * requests — the shape this function had before — answers exactly one MCP
 * request per pod lifetime and throws on every one after, forever, because
 * nothing here restarts the pod: `/health` returns before ever touching the
 * transport, so both probes stay green on an endpoint that has already
 * stopped answering. This is also the reuse shape GHSA-345p-7cg4-v4c7 names;
 * `^1.30.0` carries the fix for the vulnerability, and enforcing it is what
 * turns the old code from silently wrong into loudly broken instead of
 * correct. A fresh `Server` and transport per `/mcp` call, matching the SDK's
 * own stateless example (`examples/server/simpleStatelessStreamableHttp.ts`),
 * is what stateless mode actually requires.
 *
 * `verifier` is injectable so the request-routing and rejection behaviour can
 * be tested without a live IdP.
 */
export async function startHttpTransport(
  createServer: () => Server,
  config: HttpConfig,
  verifier: TokenVerifier = createTokenVerifier({
    issuer: config.issuer,
    projectId: config.projectId,
    allowedSubjects: config.allowedSubjects,
    allowedClientId: config.allowedClientId,
  })
): Promise<{
  address: () => { port: number };
  close: (gracePeriodMs?: number) => Promise<void>;
}> {
  const httpServer = createHttpServer(
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
    //
    // Keeping it off the internet is a *routing* property, not a server one —
    // the HTTPRoute matches the MCP path only, and kubelet probes reach the
    // pod IP without traversing it. Deliberately not a second listener: that
    // would be more surface, a second bind to get wrong, and one security
    // property implemented in two places that must stay consistent. This
    // version cannot drift because the code is unaware of the distinction.
    //
    // The body is deliberately contentless and must stay that way. Health
    // endpoints accrete — a version string, a config echo, "issuer reachable".
    // Each addition is individually reasonable, and each one turns an
    // in-cluster probe into a reconnaissance response if the route is ever
    // widened. Adding a field here should require arguing with this comment.
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

    // sessionIdGenerator: undefined puts the transport in stateless mode —
    // every request is self-contained, which suits a single-tenant deployment
    // behind an IdP where the bearer token, not a server-side session, is
    // what carries identity. One request per instance is what that mode
    // requires, not a limitation being worked around — see the function
    // doc comment for why a shared instance is actively wrong here.
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
    });
    const requestServer = createServer();
    await requestServer.connect(transport);
    // Matches the SDK's own stateless example: cleanup rides the response's
    // close event rather than a try/finally around handleRequest, because in
    // SSE-streaming mode handleRequest can resolve while the stream is still
    // open — closing on completion of the promise would tear down a
    // connection still in use.
    res.on("close", () => {
      transport.close();
      requestServer.close();
    });

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
    /**
     * Stops accepting connections and drains the ones in flight.
     *
     * `httpServer.close()` gets the easy half right on its own: since Node 19
     * it closes *idle* keep-alive sockets itself, and this package pins 22 via
     * `.nvmrc`. What it will not do is bound the wait on an **active** request.
     * A handler that never responds — a hung Slack call, a client that stops
     * mid-body — leaves `close()` pending forever, so the pod sits in
     * Terminating until the kubelet SIGKILLs it. That kills every *other*
     * request still in flight, which is the opposite of draining.
     *
     * So the only thing added here is the bound: let active requests finish,
     * and force the remainder after `gracePeriodMs`. The default must stay
     * below the pod's `terminationGracePeriodSeconds` or the kubelet wins the
     * race and the grace period is decorative.
     */
    close: (gracePeriodMs = 10_000) =>
      new Promise<void>((resolve, reject) => {
        let force: NodeJS.Timeout | undefined;
        httpServer.close((err) => {
          if (force) clearTimeout(force);
          if (err) reject(err);
          else resolve();
        });
        force = setTimeout(
          () => httpServer.closeAllConnections(),
          gracePeriodMs
        );
        // Never a reason to hold the process open just to fire a timer whose
        // whole purpose is to stop holding the process open.
        force.unref();
      }),
  };
}
