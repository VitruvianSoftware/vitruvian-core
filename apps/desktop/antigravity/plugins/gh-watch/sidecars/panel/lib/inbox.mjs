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
// the hook's own payload for a command the agent ran that either opened a pull
// request (`gh pr create`) or asked for one to be watched (the sign-up
// command below).

import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
  unlinkSync,
} from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";

// A note is kept this long while its pull request cannot be found yet, then
// dropped.
export const NOTE_TTL_MS = 10 * 60 * 1000;

// Matches a command whose own words open a pull request, not one that merely
// mentions them (an echo, a comment, a grep). Three spellings count:
//
//   gh pr create ...                                (after any VAR=val words)
//   bazel run //tools/agent-app -- pr-create ...    (the repo's own target,
//                                                    flags allowed around it)
//   tools/agent-app/agent-app.sh pr-create ...      (the script it wraps)
const ENV_PREFIX = String.raw`(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*`;
const CREATE = [
  new RegExp(String.raw`^${ENV_PREFIX}gh\s+pr\s+create(\s|$)`),
  new RegExp(
    String.raw`^${ENV_PREFIX}bazel\s+(?:-\S+\s+)*run\s+(?:-\S+\s+)*\/\/tools\/agent-app(?::\S+)?\s+(?:-\S+\s+)*--\s+(?:-{1,2}\S+\s+(?:[^\s-]\S*\s+)?)*pr-create(\s|$)`,
  ),
  /(?:^|\s|\S*\/)agent-app\.sh\s+pr-create(\s|$)/,
];
const isCreate = (part) => CREATE.some((re) => re.test(part));

// Asking for help, or for a dry run, opens nothing. The short `-h` is left
// out on purpose: it turns up inside quoted titles, and missing a real pull
// request is worse than one wasted lookup.
const NOT_A_CREATE = /\s(--help|--dry-run)(\s|$)/;

// The sign-up command. An agent runs it for a pull request that something
// else opened on its behalf (a subagent, `claude -p`, a script), since the
// hook never sees a `gh pr create` that ran outside Antigravity:
//
//   GH_WATCH=1 gh pr view <number or URL> --json url --jq .url
//
// It is an ordinary `gh pr view`, so it works with nothing installed and
// prints the link back as confirmation. The GH_WATCH=1 prefix is what marks
// it as a request to watch; a plain `gh pr view` is only someone reading.
// Without a number or URL it means the pull request for the current branch,
// which is looked up from the folder it ran in, like `gh pr create`.
const SIGN_UP = /^GH_WATCH=1\s+gh\s+pr\s+view(?:\s+([^\s-]\S*))?(?=\s|$)/;

// A `cd <dir>` part, which changes the folder the parts after it run in.
const CD = /^cd\s+(\S.*)$/;

// A pull request link, as `gh pr create` prints it.
const PR_URL =
  /https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/pull\/\d+/;

// Splits a command line at the usual shell joiners into its parts.
function partsOf(command) {
  return command.split(/&&|\|\||[;|\n]/).map((part) => part.trim());
}

const unquote = (text) => text.trim().replace(/^(['"])(.*)\1$/, "$2");

// Follows one `cd` from `cwd`. Returns the new folder, or `cwd` unchanged when
// it cannot be worked out (no starting folder for a relative path, `cd -`).
function changeDir(cwd, target) {
  let dir = unquote(target);
  if (!dir || dir === "-") return cwd;
  if (dir === "~" || dir.startsWith("~/")) dir = join(homedir(), dir.slice(1));
  if (isAbsolute(dir)) return resolve(dir);
  return typeof cwd === "string" && cwd ? resolve(cwd, dir) : cwd;
}

// Reads the command part by part. Returns the refs to watch (see refsIn) and
// the folder the first part that asked for one ran in, following any `cd`
// before it from `cwd`.
function scan(command, cwd) {
  const refs = [];
  let dir = cwd;
  let foundIn;
  for (const part of partsOf(command)) {
    const cd = CD.exec(part);
    if (cd) {
      dir = changeDir(dir, cd[1]);
      continue;
    }
    const before = refs.length;
    if (isCreate(part) && !NOT_A_CREATE.test(part)) refs.push("");
    const signUp = SIGN_UP.exec(part);
    if (signUp) refs.push((signUp[1] ?? "").replace(/^['"#]+|['"]+$/g, ""));
    if (refs.length > before && foundIn === undefined) foundIn = dir;
  }
  return { refs: [...new Set(refs)], cwd: foundIn ?? dir };
}

// Lists what the command asks to have watched: "" for a pull request opened
// by `gh pr create` or the agent-app `pr-create` (found later from the folder
// it ran in), or the number or URL given to the sign-up command ("" when it
// was given none). Empty when the command is neither.
export function refsIn(command) {
  return scan(command).refs;
}

// The first pull request link in what the command printed, or null. Hook
// payloads have carried the output under more than one name.
function printedPrUrl(payload) {
  for (const value of [payload.toolResponse, payload.output, payload.result]) {
    if (value === undefined || value === null) continue;
    let text = value;
    if (typeof text !== "string") {
      try {
        text = JSON.stringify(text);
      } catch {
        continue;
      }
    }
    const match = PR_URL.exec(text ?? "");
    if (match) return match[0];
  }
  return null;
}

// Reads one note. Returns { conversationId, cwd, refs } when it really is a
// successful `gh pr create` or sign-up command with somewhere to look for the
// pull request, and null for anything else.
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
  const scanned = scan(command, call.args.Cwd || payload.workspacePaths?.[0]);
  let refs = scanned.refs;
  if (refs.length === 0) return null;
  if (payload.error) return null;
  const conversationId = payload.conversationId;
  const cwd = scanned.cwd;
  if (typeof conversationId !== "string" || !conversationId) return null;
  if (typeof cwd !== "string" || !cwd) return null;
  // A lone "look it up from the folder" is better answered by the link the
  // command printed, when it printed one: the branch may have moved since.
  if (refs.length === 1 && refs[0] === "") {
    const url = printedPrUrl(payload);
    if (url) refs = [url];
  }
  return { conversationId, cwd, refs };
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
