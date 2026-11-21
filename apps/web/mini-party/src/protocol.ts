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

// The rooms protocol version, shared by the game page and the rooms server.
// The two go live at different times: the page from GitHub Pages as soon as a
// change merges, the server when its image update lands. A phone can also keep
// an old page open for hours. So each side says which version it speaks, and
// a side that is too old for the other gets told so instead of half-working.
//
// Bump PROTOCOL whenever the messages between page and server change. Raise a
// minimum only when a change breaks the other side; until then, old and new
// keep playing together.
//
//   1  every build before this check: it sends and announces no version.
//   2  the page sends its version when it connects; the server announces its
//      own in "server-info".
export const PROTOCOL = 2;

// The oldest page this server still seats. An older one is turned away with
// VERSION_REFUSED and asked to reload.
export const MIN_CLIENT_PROTOCOL = 1;

// The oldest server this page can play on. On an older one the page stays out
// of online play and says the server is being updated.
export const MIN_SERVER_PROTOCOL = 1;

// The connect_error message a too-old page receives.
export const VERSION_REFUSED = "version-refused";

// What the server sends with VERSION_REFUSED, and in "server-info".
export interface ServerInfo {
  protocol: number;
  minClientProtocol: number;
}

// The version a connection claims; a page that sends none is protocol 1.
export function claimedProtocol(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : 1;
}
