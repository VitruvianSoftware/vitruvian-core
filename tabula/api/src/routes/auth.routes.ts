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

import { FastifyInstance } from "fastify";
import { AuthService } from "../services/auth.service";

/**
 * Escape a value for safe embedding inside an inline <script> as JSON. Plain
 * JSON.stringify does NOT neutralize the `</script>` sequence, so a profile
 * field containing `</script>` could break out of the script element (reflected
 * XSS). Escaping `<`, `>`, and the U+2028/U+2029 line separators (which are raw
 * newlines in a JS string) closes that hole.
 */
function escapeJsonForScript(value: unknown): string {
  return JSON.stringify(value)
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029");
}

/** HTML-escape a string for safe embedding in element text/attributes. */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function getAllowedOrigins(): string[] {
  const list: string[] = [];
  if (process.env.AUTH_POSTMESSAGE_ORIGIN) {
    list.push(process.env.AUTH_POSTMESSAGE_ORIGIN.trim());
  }
  const corsOrigins = (process.env.CORS_ORIGIN || "").split(",");
  for (const o of corsOrigins) {
    const trimmed = o.trim();
    if (trimmed && trimmed !== "*" && !trimmed.includes("*")) {
      list.push(trimmed);
    }
  }
  if (!list.includes("http://localhost:3000")) list.push("http://localhost:3000");
  if (!list.includes("http://localhost:3001")) list.push("http://localhost:3001");
  return list;
}

function validateOrigin(candidate?: string): string | undefined {
  if (!candidate) return undefined;
  const allowed = getAllowedOrigins();
  return allowed.includes(candidate) ? candidate : undefined;
}

function resolvePostMessageOrigin(requestOrigin?: string): string {
  const valid = validateOrigin(requestOrigin);
  if (valid) return valid;
  if (process.env.AUTH_POSTMESSAGE_ORIGIN)
    return process.env.AUTH_POSTMESSAGE_ORIGIN;
  const corsOrigin = (process.env.CORS_ORIGIN || "").split(",")[0]?.trim();
  if (corsOrigin && corsOrigin !== "*" && !corsOrigin.includes("*"))
    return corsOrigin;
  return "http://localhost:3000";
}

export async function authRoutes(fastify: FastifyInstance) {
  /**
   * GET /api/v1/auth/login
   * Redirect to WorkOS AuthKit
   */
  fastify.get<{ Querystring: { origin?: string } }>("/login", async (request, reply) => {
    const rawOrigin =
      request.query.origin ||
      (request.headers.referer ? new URL(request.headers.referer).origin : undefined);
    const validated = validateOrigin(rawOrigin);
    const url = await AuthService.getAuthorizationUrl(validated);
    return reply.redirect(url);
  });

  /**
   * GET /api/v1/auth/callback
   * Handle WorkOS callback, sync user, issue JWT + refresh token
   */
  fastify.get<{ Querystring: { code: string; state?: string } }>(
    "/callback",
    async (request, reply) => {
      const { code, state } = request.query;

      if (!code) {
        return reply.code(400).send({ error: "Missing code parameter" });
      }

      let requestedOrigin: string | undefined;
      if (state) {
        try {
          const parsed = JSON.parse(state);
          if (typeof parsed.origin === "string") {
            requestedOrigin = parsed.origin;
          }
        } catch {
          // ignore malformed state json
        }
      }

      try {
        const user = await AuthService.authenticateAndSyncUser(code);

        // Short-lived access token (expiry configured globally in app.ts).
        // payload matches AuthenticatedUser interface in middleware/auth.ts
        const token = fastify.jwt.sign({
          id: user.id,
          email: user.email,
          tier: user.tier,
        });

        // Server-side session backing a rotating refresh token so logout and
        // revocation are possible (the access token alone is unrevocable).
        const session = await AuthService.createSession(user.id, {
          userAgent: request.headers["user-agent"],
        });

        const responseData = {
          token,
          refreshToken: session.refreshToken,
          user: {
            id: user.id,
            email: user.email,
            name: user.name,
            tier: user.tier,
            picture: user.picture,
          },
        };

        // Check if request expects HTML (Browser navigation)
        const accept = request.headers.accept || "";
        if (accept.includes("text/html")) {
          const targetOrigin = resolvePostMessageOrigin(requestedOrigin);
          // charset=utf-8 is REQUIRED: the profile (e.g. a name like "Nguyễn")
          // is emitted as raw UTF-8 bytes below. Without a declared charset the
          // browser falls back to a locale default (often windows-1252) and
          // mis-decodes multi-byte characters into mojibake ("Nguyá»…n") BEFORE
          // JSON.parse + postMessage hand the value to the extension — so the
          // corruption is baked in at parse time and shows up everywhere the
          // extension renders the name. The <meta charset> below is belt-and-
          // suspenders for proxies that strip the header.
          reply.type("text/html; charset=utf-8");
          // Token data is delivered via a JSON <script type="application/json">
          // block parsed with JSON.parse — never interpolated into executable JS —
          // and the JSON is additionally escaped so `</script>` cannot break out.
          return `
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <title>Tabula Authentication</title>
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
            <style>
              body { font-family: sans-serif; text-align: center; padding: 2rem; }
              .success { color: green; font-weight: bold; }
            </style>
          </head>
          <body>
            <h2 class="success">Authentication Successful</h2>
            <p>You can close this window now.</p>
            <script id="tabula-auth-data" type="application/json">${escapeJsonForScript(
              responseData,
            )}</script>
            <script>
              // Send token to opener (Extension). Data is read from the JSON
              // block above, never built from interpolated JS, and posted only
              // to the configured origin, never a wildcard.
              (function () {
                var el = document.getElementById('tabula-auth-data');
                var payload = JSON.parse(el.textContent);
                if (window.opener) {
                  window.opener.postMessage(
                    { type: 'TABULA_AUTH_SUCCESS', payload: payload },
                    ${escapeJsonForScript(targetOrigin)}
                  );
                  setTimeout(function () { window.close(); }, 1500);
                }
              })();
            </script>
          </body>
          </html>
        `;
        }

        // Default JSON response
        return responseData;
      } catch (error) {
        request.log.error(error);

        const errorMessage =
          error instanceof Error ? error.message : "Unknown error";

        // HTML Error response
        const accept = request.headers.accept || "";
        if (accept.includes("text/html")) {
          // Same UTF-8 contract as the success page: the error message may carry
          // non-ASCII text, so declare the charset rather than let the browser guess.
          reply.type("text/html; charset=utf-8");
          return `
           <!DOCTYPE html>
           <html>
           <head>
             <meta charset="utf-8">
             <title>Tabula Authentication</title>
           </head>
           <body>
             <h2 style="color: red">Authentication Failed</h2>
             <p>${escapeHtml(errorMessage)}</p>
           </body>
           </html>
         `;
        }

        return reply.code(500).send({
          error: "Authentication failed",
          message: errorMessage,
        });
      }
    },
  );

  /**
   * POST /api/v1/auth/refresh
   * Exchange a refresh token for a fresh access token, rotating the refresh
   * token. Re-reads the user's current tier from the DB so plan changes take
   * effect within an access-token lifetime. Returns 401 for unknown/expired
   * tokens.
   */
  fastify.post<{ Body: { refreshToken?: string } }>(
    "/refresh",
    async (request, reply) => {
      const refreshToken = request.body?.refreshToken;
      if (!refreshToken) {
        return reply
          .code(400)
          .send({ error: "Bad Request", message: "refreshToken is required" });
      }

      const rotated = await AuthService.rotateRefreshToken(refreshToken);
      if (!rotated) {
        return reply.code(401).send({
          error: "Unauthorized",
          message: "Invalid or expired refresh token",
        });
      }

      const token = fastify.jwt.sign({
        id: rotated.user.id,
        email: rotated.user.email,
        tier: rotated.user.tier,
      });

      return {
        token,
        refreshToken: rotated.refreshToken,
      };
    },
  );

  /**
   * POST /api/v1/auth/logout
   * Server-side logout: deletes the session so the refresh token can no longer
   * be rotated. Idempotent — an unknown token still returns 200.
   */
  fastify.post<{ Body: { refreshToken?: string } }>(
    "/logout",
    async (request, reply) => {
      const refreshToken = request.body?.refreshToken;
      if (refreshToken) {
        await AuthService.revokeRefreshToken(refreshToken);
      }
      return reply.code(200).send({ success: true });
    },
  );
}
