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

/**
 * Shared id and opaque-token helpers.
 *
 * `generateId` matches the existing app-generated id convention
 * (`WorkspaceService.generateId`) so new VarChar(100) primary keys look the same
 * as ws_/tab_/sg_ ids. The token helpers mirror lib/auth's refresh-token
 * pattern (256 bits of entropy, only the SHA-256 hash stored at rest) but are
 * named generically for share links rather than refresh tokens.
 */
import { createHash, randomBytes } from "crypto";

/** `${prefix}_${base36 time}_${base36 random}` — e.g. `sc_lq3k_9f2a1b3c4`. */
export function generateId(prefix: string): string {
  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).substring(2, 11)}`;
}

/** A 256-bit opaque token (64 hex chars). Returned to the caller exactly once. */
export function generateOpaqueToken(): string {
  return randomBytes(32).toString("hex");
}

/** SHA-256 hex (64 chars) of a token — the only form persisted at rest. */
export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}
