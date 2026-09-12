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

// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { FastifyRequest as FastifyRequestType, FastifyReply } from "fastify";

export interface AuthenticatedUser {
  id: string;
  email: string;
  tier: string;
}

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: AuthenticatedUser;
    user: AuthenticatedUser;
  }
}

/**
 * Verify JWT token and attach user to request
 */
export async function authenticateUser(
  request: FastifyRequestType,
  reply: FastifyReply,
) {
  try {
    await request.jwtVerify();
    // fastify-jwt automatically populates request.user with the decoded token payload
  } catch (error) {
    const authHeader = request.headers.authorization;
    const hasToken = !!authHeader;
    const tokenPreview = hasToken
      ? `${authHeader.substring(0, 20)}...`
      : "none";
    request.log.warn(
      {
        error: error instanceof Error ? error.message : "Unknown",
        hasToken,
        tokenPreview,
      },
      "JWT verification failed",
    );
    reply
      .code(401)
      .send({ error: "Unauthorized", message: "Authentication failed" });
  }
}

/**
 * Verify JWT, also accepting the token via the `token` query parameter when
 * the Authorization header is absent. EventSource cannot set request headers,
 * so the SSE stream route (GET /sync/stream) needs query-string auth. All
 * other routes must keep using the header-only authenticateUser.
 */
export async function authenticateUserAllowQueryToken(
  request: FastifyRequestType,
  reply: FastifyReply,
) {
  if (!request.headers.authorization) {
    const { token } = request.query as { token?: string };
    if (typeof token === "string" && token.length > 0) {
      // Reuse the standard verification path by promoting the query token to
      // the Authorization header before jwtVerify runs.
      request.headers.authorization = `Bearer ${token}`;
    }
  }
  return authenticateUser(request, reply);
}

/**
 * Optional authentication - does not fail if no token provided
 */
export async function optionalAuth(request: FastifyRequestType) {
  try {
    // Only attempt verification if Authorization header is present
    if (request.headers.authorization) {
      await request.jwtVerify();
    }
  } catch (error) {
    request.log.debug({ error }, "Optional auth error");
    // Do not throw/return 401 for optional auth
  }
}
