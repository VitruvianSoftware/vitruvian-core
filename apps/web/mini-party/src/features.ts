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

// Online rooms need the Node server in server.ts. By default the game talks to
// the server it was loaded from. A static host such as GitHub Pages has no
// server of its own, so that build sets VITE_ROOMS_URL to a separate rooms
// server (the homelab's mini-games-rooms.vitruviansoftware.dev), or
// VITE_REMOTE_PLAY=off to offer shared-screen play only.
export const REMOTE_PLAY = import.meta.env.VITE_REMOTE_PLAY !== "off";

// Where the rooms server is; undefined means the page's own origin.
export const ROOMS_URL: string | undefined =
  import.meta.env.VITE_ROOMS_URL || undefined;
