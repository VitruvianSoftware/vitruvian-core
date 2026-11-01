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

// Checks every plugin's hooks.json has the shape Antigravity loads.
//
// Antigravity's hook docs (embedded in its language server) say:
// - PreToolUse and PostToolUse take groups: {"matcher": "<regex>", "hooks": [handler...]}.
// - SessionStart, PreInvocation, PostInvocation and Stop take a flat list of
//   handlers: [{"type": "command", "command": "...", "timeout": 5}].
// A file with one wrong entry is skipped whole (`agy plugin validate --strict`
// then reports "hooks 0"), so every hook in it silently never runs. Until
// this test, hookify, security-guidance, ralph-loop and worktree-band shipped
// that way. `agy` is not available to Bazel, so this checks the same rules.
//
// What a hook may answer also depends on the event. Captured with `agy -p`
// and a logging hook for every event (2026-11-01): `{}` is harmless for
// SessionStart, PreInvocation, PostInvocation, PostToolUse and Stop, but for
// PreToolUse it DENIES the call (the step fails with "tool call denied by
// pre-tool hook: "). So a script wired to PreToolUse must answer with a
// "decision" even when rust-hook.sh falls back (no rustc, failed build).
//
// Usage: node hooks_json.test.mjs <files>...  (from BUILD; the hooks.json
// ones are checked, the hook scripts beside them read for fallbacks)

import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";

const GROUPED = new Set(["PreToolUse", "PostToolUse"]);
const FLAT = new Set([
  "SessionStart",
  "PreInvocation",
  "PostInvocation",
  "Stop",
]);

/** Problems with one handler object; `where` names it in messages. */
function handlerProblems(h, where, pluginDir) {
  const out = [];
  if (!h || typeof h !== "object" || Array.isArray(h)) {
    return [`${where}: a handler must be an object`];
  }
  if ("hooks" in h || "matcher" in h) {
    out.push(`${where}: a handler, but has "hooks"/"matcher" (a group)`);
  }
  if (h.type !== undefined && h.type !== "command") {
    out.push(`${where}: type must be "command"`);
  }
  if (typeof h.command !== "string" || !h.command.trim()) {
    out.push(`${where}: needs a "command" string`);
  } else if (pluginDir && h.command.startsWith("./")) {
    // Existence only: Bazel's copy drops the exec bit, which each plugin's
    // own rust_hook_test checks on the source.
    const script = join(pluginDir, h.command.split(/\s+/)[0]);
    if (!existsSync(script)) out.push(`${where}: ${h.command} does not exist`);
  }
  if (
    h.timeout !== undefined &&
    !(Number.isInteger(h.timeout) && h.timeout > 0)
  ) {
    out.push(`${where}: timeout must be a positive whole number of seconds`);
  }
  return out;
}

/** Every reason Antigravity would reject this parsed hooks.json. */
export function hooksJsonProblems(doc, pluginDir = "") {
  const out = [];
  if (!doc || typeof doc !== "object" || Array.isArray(doc)) {
    return ["hooks.json must be an object of named hook sets"];
  }
  for (const [set, events] of Object.entries(doc)) {
    if (!events || typeof events !== "object" || Array.isArray(events)) {
      out.push(`${set}: must map event names to lists`);
      continue;
    }
    for (const [event, list] of Object.entries(events)) {
      const at = `${set}.${event}`;
      if (!GROUPED.has(event) && !FLAT.has(event)) {
        out.push(`${at}: unknown event`);
        continue;
      }
      if (!Array.isArray(list) || list.length === 0) {
        out.push(`${at}: must be a non-empty list`);
        continue;
      }
      list.forEach((entry, i) => {
        const where = `${at}[${i}]`;
        if (FLAT.has(event)) {
          out.push(...handlerProblems(entry, where, pluginDir));
          return;
        }
        if (
          !entry ||
          typeof entry !== "object" ||
          !Array.isArray(entry.hooks)
        ) {
          out.push(
            `${where}: ${event} takes groups {"matcher", "hooks": [...]}`,
          );
          return;
        }
        if (entry.matcher !== undefined) {
          if (typeof entry.matcher !== "string") {
            out.push(`${where}: matcher must be a string`);
          } else if (entry.matcher !== "*") {
            try {
              new RegExp(entry.matcher);
            } catch {
              out.push(`${where}: matcher is not a valid regex`);
            }
          }
        }
        if (entry.hooks.length === 0) out.push(`${where}: hooks is empty`);
        entry.hooks.forEach((h, j) => {
          out.push(...handlerProblems(h, `${where}.hooks[${j}]`, pluginDir));
        });
      });
    }
  }
  return out;
}

/** The fallback JSON a launcher stub hands to rust-hook.sh, if it is one. */
export function launcherFallback(scriptText) {
  if (!scriptText.includes("rust-hook.sh")) return null;
  const m = scriptText.match(/^\s*'(\{.*\})'\s*$/m);
  return m ? JSON.parse(m[1]) : undefined;
}

/** Scripts wired to PreToolUse whose fallback would deny every tool call. */
export function preToolUseFallbackProblems(doc, readScript) {
  const out = [];
  for (const [set, events] of Object.entries(doc ?? {})) {
    for (const group of events?.PreToolUse ?? []) {
      for (const h of group?.hooks ?? []) {
        const script = String(h?.command ?? "").split(/\s+/)[0];
        const fallback = launcherFallback(readScript(script));
        if (fallback === undefined) {
          out.push(`${set}: ${script} has no readable fallback JSON`);
        } else if (fallback && typeof fallback.decision !== "string") {
          out.push(
            `${set}: ${script} falls back to ${JSON.stringify(fallback)}, which denies every tool call`,
          );
        }
      }
    }
  }
  return out;
}

const files = process.argv.slice(2).filter((f) => f.endsWith("/hooks.json"));

test("every plugin's hooks.json was given", () => {
  assert.ok(
    files.length >= 9,
    `expected the nine plugins, got ${files.length}`,
  );
});

for (const file of files) {
  const plugin = dirname(file).split("/").pop();
  test(`${plugin}/hooks.json has the shape Antigravity loads`, () => {
    const doc = JSON.parse(readFileSync(file, "utf8"));
    assert.deepEqual(hooksJsonProblems(doc, dirname(file)), []);
    assert.deepEqual(
      preToolUseFallbackProblems(doc, (script) =>
        readFileSync(join(dirname(file), script), "utf8"),
      ),
      [],
    );
  });
}

test("a PreToolUse fallback without a decision is rejected", () => {
  const doc = {
    s: { PreToolUse: [{ matcher: "*", hooks: [{ command: "./h.sh" }] }] },
  };
  const stub = (json) => () =>
    `exec "$(dirname "$0")/rust-hook.sh" c main.rs \\\n\t'${json}'\n`;
  assert.notDeepEqual(preToolUseFallbackProblems(doc, stub("{}")), []);
  assert.deepEqual(
    preToolUseFallbackProblems(doc, stub('{"decision":"ask","reason":"x"}')),
    [],
  );
});

test("the check rejects the shapes that got hooks skipped", () => {
  const handler = { type: "command", command: "x", timeout: 5 };
  // Stop/SessionStart grouped like a tool event: the bug this test exists for.
  assert.notDeepEqual(
    hooksJsonProblems({ s: { Stop: [{ matcher: "*", hooks: [handler] }] } }),
    [],
  );
  assert.notDeepEqual(
    hooksJsonProblems({ s: { SessionStart: [{ hooks: [handler] }] } }),
    [],
  );
  // A tool event given bare handlers.
  assert.notDeepEqual(hooksJsonProblems({ s: { PreToolUse: [handler] } }), []);
  assert.notDeepEqual(hooksJsonProblems({ s: { Bogus: [handler] } }), []);
  assert.notDeepEqual(
    hooksJsonProblems({
      s: { PreToolUse: [{ matcher: "(", hooks: [handler] }] },
    }),
    [],
  );
  // And accepts the right ones.
  assert.deepEqual(
    hooksJsonProblems({
      s: {
        Stop: [handler],
        PreToolUse: [{ matcher: "run_command|edit_file", hooks: [handler] }],
      },
    }),
    [],
  );
});
