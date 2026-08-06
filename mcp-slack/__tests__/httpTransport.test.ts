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

// Tests the request boundary itself rather than the pieces behind it. The
// allow-list bypass earlier in this PR lived in a layer that had no tests
// because it was a private method reached only through a running server —
// this is that layer.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";

import {
  IdpUnavailableError,
  MissingTokenError,
  type TokenVerifier,
} from "../src/auth.js";
import { Agent, request } from "node:http";

import { headerSafe, startHttpTransport } from "../src/httpTransport.js";

const CONFIG = {
  port: 0, // ephemeral; the OS picks a free one
  issuer: "https://auth.example.test",
  projectId: "123456789",
};

/** A verifier whose behaviour each test controls. */
function verifierThat(behaviour: () => Promise<never> | Promise<void>): TokenVerifier {
  const run = async () => {
    await behaviour();
    return { subject: "user-42", claims: {} };
  };
  return {
    verify: run,
    verifyAuthorizationHeader: run,
  };
}

async function withServer(
  verifier: TokenVerifier,
  assertions: (baseUrl: string) => Promise<void>
): Promise<void> {
  const server = new Server(
    { name: "mcp-slack-test", version: "0.0.0" },
    { capabilities: { tools: {} } }
  );
  const handle = await startHttpTransport(server, CONFIG, verifier);
  // startHttpTransport listens on CONFIG.port; port 0 means the real port is
  // only knowable after listen, so read it back off the underlying server.
  const address = handle.address();
  const baseUrl = `http://127.0.0.1:${address.port}`;
  try {
    await assertions(baseUrl);
  } finally {
    await handle.close();
  }
}

const okVerifier = verifierThat(async () => {});

describe("http transport request boundary", () => {
  it("serves /health without authentication", async () => {
    // Deliberately unauthenticated: a liveness probe that needs a token tells
    // you the IdP is reachable, not that this process is healthy.
    await withServer(
      verifierThat(async () => {
        throw new Error("verifier must not be consulted for /health");
      }),
      async (baseUrl) => {
        const res = await fetch(`${baseUrl}/health`);
        expect(res.status).toBe(200);
        await expect(res.json()).resolves.toEqual({ status: "ok" });
      }
    );
  });

  it("404s an unknown path without consulting the verifier", async () => {
    await withServer(okVerifier, async (baseUrl) => {
      const res = await fetch(`${baseUrl}/not-a-route`);
      expect(res.status).toBe(404);
    });
  });

  it("rejects an unauthenticated MCP request with the auth error's status", async () => {
    await withServer(
      verifierThat(async () => {
        throw new MissingTokenError();
      }),
      async (baseUrl) => {
        const res = await fetch(`${baseUrl}/mcp`, { method: "POST" });
        expect(res.status).toBe(401);
        // RFC 6750: the challenge carries the machine-readable reason, so the
        // cause is legible from `curl -i` without server log access.
        expect(res.headers.get("www-authenticate")).toContain(
          'error="invalid_request"'
        );
      }
    );
  });

  // The defect this file was added for. A JWKS fetch failure is the realistic
  // way a non-AuthError escapes the verifier — it reaches the network on the
  // auth path. Discarding the handler promise meant that became an unhandled
  // rejection: no response, and process termination under Node's default.
  it("returns 500 for an unexpected verifier failure rather than hanging", async () => {
    await withServer(
      verifierThat(async () => {
        throw new TypeError("fetch failed: JWKS endpoint unreachable");
      }),
      async (baseUrl) => {
        const res = await fetch(`${baseUrl}/mcp`, { method: "POST" });
        expect(res.status).toBe(500);
        const body = (await res.json()) as { error?: { message?: string } };
        // Generic on the wire: an IdP outage is not the caller's business and
        // the detail belongs in the server's stderr, not the response.
        expect(body.error?.message).toBe("Internal server error");
      }
    );
  });

  // A 503 must not carry a WWW-Authenticate challenge: that header tells the
  // caller how to authenticate, which is a lie when the failure is ours. It
  // would send someone holding a valid token to re-authenticate against an
  // IdP that is down.
  it("answers an IdP outage with 503, Retry-After and no auth challenge", async () => {
    await withServer(
      verifierThat(async () => {
        throw new IdpUnavailableError("fetch failed");
      }),
      async (baseUrl) => {
        const res = await fetch(`${baseUrl}/mcp`, { method: "POST" });
        expect(res.status).toBe(503);
        expect(res.headers.get("retry-after")).toBe("30");
        expect(res.headers.get("www-authenticate")).toBeNull();
      }
    );
  });

  it("stays up and serves the next request after an unexpected failure", async () => {
    let shouldFail = true;
    const flaky: TokenVerifier = {
      verify: async () => {
        if (shouldFail) throw new TypeError("transient JWKS failure");
        return { subject: "user-42", claims: {} };
      },
      verifyAuthorizationHeader: async () => {
        if (shouldFail) throw new TypeError("transient JWKS failure");
        return { subject: "user-42", claims: {} };
      },
    };

    await withServer(flaky, async (baseUrl) => {
      expect((await fetch(`${baseUrl}/mcp`, { method: "POST" })).status).toBe(
        500
      );
      shouldFail = false;
      // The point: a transient IdP blip must not take the listener down.
      expect((await fetch(`${baseUrl}/health`)).status).toBe(200);
    });
  });
});

// The WWW-Authenticate description carries a diagnostic message. Two failure
// modes, both measured against a real Node server rather than reasoned about.
describe("headerSafe", () => {
  it("strips CR/LF/NUL, which make writeHead throw and cost us the 403", () => {
    expect(headerSafe("aud\r\nX-Injected: yes")).toBe("aud X-Injected: yes");
    expect(headerSafe("aud\nvalue")).toBe("aud value");
    expect(headerSafe("aud\0value")).toBe("aud value");
  });

  // The quieter of the two: a double quote sends successfully and produces a
  // malformed RFC 7235 quoted-string, so a strict client mis-reads where the
  // value ends. No security consequence; fails silently.
  it("replaces the double quote that would break the quoted-string", () => {
    expect(headerSafe('aud"quoted')).toBe("aud'quoted");
  });

  it("leaves an ordinary diagnostic message intact", () => {
    const msg = "Token audience does not include this server's project (999).";
    expect(headerSafe(msg)).toBe(msg);
  });
});

// Shutdown.
//
// The first version of this test asserted that close() resolves with an idle
// keep-alive socket open. It passed with the fix removed — Node has closed idle
// sockets in close() since v19 and this package pins 22, so it was measuring
// the runtime, not this code. The real unbounded wait is an *active* request:
// without closeAllConnections() the promise never settles, the pod sits in
// Terminating, and the kubelet SIGKILLs every other in-flight request.
describe("close() bounds the wait on an active request", () => {
  it("forces the connection after the grace period instead of hanging", async () => {
    const server = new Server(
      { name: "mcp-slack-test", version: "0.0.0" },
      { capabilities: { tools: {} } }
    );
    const listener = await startHttpTransport(server, CONFIG, {
      // Never resolves: models a handler wedged on a hung upstream call.
      verify: () => new Promise(() => {}),
      verifyAuthorizationHeader: () => new Promise(() => {}),
    });
    const port = listener.address().port;

    const agent = new Agent({ keepAlive: true });
    const inFlight = new Promise<void>((resolve) => {
      const req = request(
        { port, host: "127.0.0.1", path: "/mcp", method: "POST", agent },
        () => resolve()
      );
      req.on("error", () => resolve()); // forced close lands here
      req.setHeader("Authorization", "Bearer wedged");
      req.setHeader("Content-Type", "application/json");
      req.end("{}");
    });
    // Let the request reach the wedged handler before shutting down.
    await new Promise((r) => setTimeout(r, 100));

    const started = process.hrtime.bigint();
    await listener.close(300);
    const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;

    // Resolves because the grace period expired and forced it — not because
    // the request finished, which it never does.
    expect(elapsedMs).toBeGreaterThanOrEqual(250);
    expect(elapsedMs).toBeLessThan(5_000);
    await inFlight;
    agent.destroy();
  });
});
