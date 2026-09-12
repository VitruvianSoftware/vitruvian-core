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
import { ClientNotAllowedError, SubjectNotAllowedError } from "../src/auth.js";

const CONFIG = {
  port: 0, // ephemeral; the OS picks a free one
  issuer: "https://auth.example.test",
  projectId: "123456789",
  // Required by HttpConfig; these tests inject their own verifier, so the
  // value is never consulted — but it cannot be omitted, which is the point.
  allowedSubjects: ["user-42"],
  allowedClientId: "111222333",
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

function testServerFactory(): Server {
  return new Server(
    { name: "mcp-slack-test", version: "0.0.0" },
    { capabilities: { tools: {} } }
  );
}

async function withServer(
  verifier: TokenVerifier,
  assertions: (baseUrl: string) => Promise<void>
): Promise<void> {
  const handle = await startHttpTransport(testServerFactory, CONFIG, verifier);
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

  it("serves /.well-known/oauth-protected-resource without authentication", async () => {
    await withServer(
      verifierThat(async () => {
        throw new Error("verifier must not be consulted for /.well-known/oauth-protected-resource");
      }),
      async (baseUrl) => {
        const res = await fetch(`${baseUrl}/.well-known/oauth-protected-resource`);
        expect(res.status).toBe(200);
        const data = (await res.json()) as {
          resource: string;
          authorization_servers: string[];
          scopes_supported: string[];
        };
        expect(data.resource).toBe(`${baseUrl}/mcp`);
        expect(data.authorization_servers).toEqual(["https://auth.example.test"]);
        expect(data.scopes_supported).toEqual([
          "openid",
          "offline_access",
          "urn:zitadel:iam:org:project:id:123456789:aud",
        ]);
      }
    );
  });

  it("serves /.well-known/oauth-protected-resource/mcp with https for public domains", async () => {
    await withServer(okVerifier, async (baseUrl) => {
      const res = await fetch(`${baseUrl}/.well-known/oauth-protected-resource/mcp`, {
        headers: {
          "x-forwarded-host": "mcp-slack.ipv1337.dev",
          "cf-visitor": '{"scheme":"https"}',
        },
      });
      expect(res.status).toBe(200);
      const data = (await res.json()) as { resource: string };
      expect(data.resource).toBe("https://mcp-slack.ipv1337.dev/mcp");
    });
  });

  it("rejects an unauthenticated MCP request with the auth error's status and resource_metadata challenge", async () => {
    await withServer(
      verifierThat(async () => {
        throw new MissingTokenError();
      }),
      async (baseUrl) => {
        const res = await fetch(`${baseUrl}/mcp`, { method: "POST" });
        expect(res.status).toBe(401);
        // RFC 6750 + RFC 9728: the challenge carries the machine-readable reason
        // and resource_metadata for discovery.
        const authHeader = res.headers.get("www-authenticate");
        expect(authHeader).toContain('error="invalid_request"');
        expect(authHeader).toContain(
          `resource_metadata="${baseUrl}/.well-known/oauth-protected-resource/mcp"`
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
    const listener = await startHttpTransport(testServerFactory, CONFIG, {
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

// Detection without attribution was the gap: the presented sub travels to the
// caller in the body and WWW-Authenticate, and we kept none of it. The 403
// alert's own remediation step — "check the rejection logs" — named something
// that could not be done.
describe("refusals are recorded, not only answered", () => {
  function captureStderr() {
    const lines: string[] = [];
    const spy = jest
      .spyOn(process.stderr, "write")
      .mockImplementation((chunk: unknown) => {
        lines.push(String(chunk));
        return true;
      });
    return { lines, restore: () => spy.mockRestore() };
  }

  it("logs the presented subject when a caller is refused", async () => {
    const err = captureStderr();
    try {
      await withServer(
        verifierThat(() => {
          throw new SubjectNotAllowedError("379361013981513322");
        }),
        async (baseUrl) => {
          const res = await fetch(`${baseUrl}/mcp`, {
            method: "POST",
            headers: { Authorization: "Bearer t", "Content-Type": "application/json" },
            body: "{}",
          });
          expect(res.status).toBe(403);
        }
      );
    } finally {
      err.restore();
    }
    const refusal = err.lines.find((l) => l.includes("refused"));
    expect(refusal).toBeDefined();
    // The whole point: the identity is on OUR side of the exchange.
    expect(refusal).toContain("sub=379361013981513322");
  });

  // The label is per-error (#1491), not hardcoded to "sub=" — a client-pinning
  // refusal has no subject to be wrong about, and mislabeling it as one would
  // send whoever reads the log looking for the wrong control.
  it("labels a client-pinning refusal by client_id, not sub", async () => {
    const err = captureStderr();
    try {
      await withServer(
        verifierThat(() => {
          throw new ClientNotAllowedError("777777777");
        }),
        async (baseUrl) => {
          const res = await fetch(`${baseUrl}/mcp`, {
            method: "POST",
            headers: { Authorization: "Bearer t", "Content-Type": "application/json" },
            body: "{}",
          });
          expect(res.status).toBe(403);
        }
      );
    } finally {
      err.restore();
    }
    const refusal = err.lines.find((l) => l.includes("refused"));
    expect(refusal).toBeDefined();
    expect(refusal).toContain("client_id=777777777");
    expect(refusal).not.toContain("sub=777777777");
  });

  it("does not log 401s, which a public endpoint gets by the thousand", async () => {
    // Scanners produce these. Burying a 403 — which requires a validly-signed
    // token audienced for our project — under that noise would defeat the
    // reason for logging at all.
    const err = captureStderr();
    try {
      await withServer(
        verifierThat(() => {
          throw new MissingTokenError();
        }),
        async (baseUrl) => {
          const res = await fetch(`${baseUrl}/mcp`, { method: "POST", body: "{}" });
          expect(res.status).toBe(401);
        }
      );
    } finally {
      err.restore();
    }
    expect(err.lines.filter((l) => l.includes("refused"))).toEqual([]);
  });
});

// #1491 / GHSA-345p-7cg4-v4c7 regression. `StreamableHTTPServerTransport` in
// stateless mode (`sessionIdGenerator: undefined`) is single-use: the SDK
// throws on a transport's *second* `handleRequest` call
// (`_hasHandledRequest`, set unconditionally on the first, never reset). A
// `Server`/transport pair built once and reused across every `/mcp` request —
// this file's own shape before this fix — answers exactly one MCP request per
// pod lifetime and throws on every one after, forever: nothing here restarts
// the pod, because `/health` returns before ever touching the transport, so
// both probes stay green on an endpoint that has already stopped answering.
//
// This exercises the actual regression rather than standing in for it: a real
// `Server`, a real `StreamableHTTPServerTransport`, and a real
// Accept/Content-Type-negotiated `initialize` call, sent twice. Both headers
// are required — the SDK 406s ahead of the reuse guard if either is missing,
// which would make this test pass identically whether or not the bug exists.
// Revert the per-request construction in httpTransport.ts and this goes red.
describe("a fresh Server and transport are used per request (#1491)", () => {
  const initializeBody = JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {
      protocolVersion: "2025-11-25",
      capabilities: {},
      clientInfo: { name: "regression-test-client", version: "0.0.0" },
    },
  });

  async function postInitialize(baseUrl: string) {
    const res = await fetch(`${baseUrl}/mcp`, {
      method: "POST",
      headers: {
        Authorization: "Bearer t",
        "Content-Type": "application/json",
        Accept: "application/json, text/event-stream",
      },
      body: initializeBody,
    });
    // Drains the body so the connection closes before the next request or
    // test teardown, rather than leaving an SSE stream half-read.
    await res.text();
    return res;
  }

  it("answers a second sequential MCP request instead of latching after the first", async () => {
    await withServer(okVerifier, async (baseUrl) => {
      const first = await postInitialize(baseUrl);
      expect(first.status).toBe(200);

      const second = await postInitialize(baseUrl);
      expect(second.status).toBe(200);
    });
  });
});
