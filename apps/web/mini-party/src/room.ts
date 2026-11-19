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

// Share links look like https://mini-games.vitruviansoftware.dev/?room=81D0I7.
// The rooms server accepts 1-16 letters or digits, so anything else is
// ignored rather than sent to it.
const ROOM_ID = /^[A-Za-z0-9]{1,16}$/;

// The room a page was opened to join, or null. App reads this while the first
// render happens, not in an effect: the lobby picks local or online play on
// that first render, so a room learned later left a share link stuck in the
// local lobby with no way to join.
export function roomFromSearch(
  search: string,
  remotePlay: boolean,
): string | null {
  if (!remotePlay) return null;
  const room = new URLSearchParams(search).get("room");
  return room !== null && ROOM_ID.test(room) ? room : null;
}
