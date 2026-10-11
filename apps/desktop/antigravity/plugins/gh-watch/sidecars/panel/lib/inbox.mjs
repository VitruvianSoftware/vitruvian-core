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

/* global console */

// Notes left by the sign-up hook (../../hooks/note-pr-create.sh). Each one is
// the hook's own payload for a `gh pr create` the agent ran.

import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
  unlinkSync,
} from "node:fs";
import { join } from "node:path";

// A note is kept this long while its pull request cannot be found yet, then
// dropped.
export const NOTE_TTL_MS = 10 * 60 * 1000;

// Matches a command whose own words are `gh pr create`, not one that merely
// mentions them (an echo, a comment, a grep).
const CREATE = /^gh\s+pr\s+create(\s|$)/;

// Asking for help, or for a dry run, opens nothing. The short `-h` is left
// out on purpose: it turns up inside quoted titles, and missing a real pull
// request is worse than one wasted lookup.
const NOT_A_CREATE = /\s(--help|--dry-run)(\s|$)/;

// Splits a command line at the usual shell joiners and reports whether any
// part of it is a `gh pr create`.
function createsPr(command) {
  return command
    .split(/&&|\|\||[;|\n]/)
    .map((part) => part.trim())
    .some((part) => CREATE.test(part) && !NOT_A_CREATE.test(part));
}

// Reads one note. Returns { conversationId, cwd } when it really is a
// successful `gh pr create` with somewhere to look for the pull request, and
// null for anything else.
export function parseNote(text) {
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    return null;
  }
  const call = payload?.toolCall;
  const command = call?.args?.CommandLine;
  if (call?.name !== "run_command" || typeof command !== "string") return null;
  if (!createsPr(command)) return null;
  if (payload.error) return null;
  const conversationId = payload.conversationId;
  const cwd = call.args.Cwd || payload.workspacePaths?.[0];
  if (typeof conversationId !== "string" || !conversationId) return null;
  if (typeof cwd !== "string" || !cwd) return null;
  return { conversationId, cwd };
}

export class Inbox {
  #dir;

  constructor(dir) {
    this.#dir = dir;
  }

  // Every waiting note, oldest first.
  list() {
    if (!existsSync(this.#dir)) return [];
    const notes = [];
    for (const name of readdirSync(this.#dir)) {
      if (!name.endsWith(".json")) continue;
      const file = join(this.#dir, name);
      try {
        notes.push({
          file,
          at: statSync(file).mtimeMs,
          text: readFileSync(file, "utf8"),
        });
      } catch (err) {
        console.error(`gh-watch: could not read note ${file}: ${err.message}`);
      }
    }
    return notes.sort((a, b) => a.at - b.at);
  }

  remove(file) {
    try {
      unlinkSync(file);
    } catch {
      // Already gone.
    }
  }
}
