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
 * Presence groundwork (#139), consumed by M4 real-time collaboration.
 *
 * This defines ONLY the Redis key/member naming convention for per-space
 * presence ("who is viewing/editing a shared space"). No live presence endpoint
 * or SSE fan-out ships in #139 — that is M4. The recipient set for a space (who
 * to notify) is already available via PermissionService.listAccessUserIds; this
 * fixes the key shape now so the M4 implementation and any tooling agree on it.
 */

/** Redis key for the presence set of a space, e.g. `presence:workspace:ws_1`. */
export function presenceKey(workspaceId: string): string {
  return `presence:workspace:${workspaceId}`;
}

/**
 * Member token identifying one present device within a space's presence set.
 * Per-device (not per-user) so a user open on two devices counts as two
 * presences, e.g. `user-1:device-abc`.
 */
export function presenceMember(userId: string, deviceId: string): string {
  return `${userId}:${deviceId}`;
}
