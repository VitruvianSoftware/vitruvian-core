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

/* global process */

// Backend for the ralph-loop panel. Antigravity starts this file with Node.js
// (see sidecar.json) and keeps it running while the plugin is enabled.

import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Response, SidecarApp } from "sidecar_sdk";

import {
  createLoopState,
  summariseLoops,
  updateLoopIteration,
} from "./lib/core.mjs";
import { parseOpenUILang, toOpenUILang } from "./lib/openui.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const STATE_DIR = join(
  process.env.ANTIGRAVITY_APP_DATA_DIR ||
    join(homedir(), ".gemini", "antigravity"),
  "ralph-loop-state",
);

const app = new SidecarApp();

const readLocal = (name) => readFileSync(join(HERE, name), "utf8");

function readVersion() {
  try {
    return String(
      JSON.parse(readFileSync(join(HERE, "..", "..", "plugin.json"), "utf8"))
        .version ?? "",
    );
  } catch {
    return "";
  }
}
const VERSION = readVersion();

const fail = (message, status = 400) =>
  new Response(JSON.stringify({ error: message }), {
    contentType: "application/json",
    status,
  });

function stateFileFor(conversationId) {
  const id = String(conversationId ?? "").trim();
  if (!id || /[/\\]/.test(id)) return null;
  return join(STATE_DIR, `${id}.json`);
}

function readLoopState(conversationId) {
  const file = stateFileFor(conversationId);
  if (!file || !existsSync(file)) return null;
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

function writeLoopState(loop) {
  const file = stateFileFor(loop?.conversationId);
  if (!file) throw new Error("Invalid conversationId");
  mkdirSync(STATE_DIR, { recursive: true });
  const tmp = `${file}.tmp`;
  writeFileSync(tmp, JSON.stringify(loop, null, 2), "utf8");
  renameSync(tmp, file);
}

function listAllLoops() {
  if (!existsSync(STATE_DIR)) return [];
  const list = [];
  for (const name of readdirSync(STATE_DIR)) {
    if (!name.endsWith(".json")) continue;
    try {
      const parsed = JSON.parse(readFileSync(join(STATE_DIR, name), "utf8"));
      if (parsed && typeof parsed === "object" && parsed.conversationId) {
        list.push(parsed);
      }
    } catch {
      continue;
    }
  }
  return list;
}

function buildState() {
  const summary = summariseLoops(listAllLoops());
  return {
    version: VERSION,
    loops: summary.items,
    summary,
  };
}

app.page("/", () => readLocal("index.html"));
app.page("/app.js", () => readLocal("app.js"));
app.api(
  "/styles.css",
  () => new Response(readLocal("styles.css"), { contentType: "text/css" }),
  "GET",
);
app.api(
  "/openui.mjs",
  () =>
    new Response(readLocal(join("lib", "openui.mjs")), {
      contentType: "text/javascript",
    }),
  "GET",
);

app.api(
  "/api/state",
  () => {
    const state = buildState();
    return { ...state, openuiDsl: toOpenUILang(state) };
  },
  "GET",
);

app.api(
  "/api/openui",
  () => {
    const dsl = toOpenUILang(buildState());
    return { dsl, parsed: parseOpenUILang(dsl) };
  },
  "GET",
);

app.api("/api/start-loop", async (data) => {
  try {
    const loop = createLoopState({
      conversationId: data?.conversationId,
      prompt: data?.prompt,
      completionPromise: data?.completionPromise,
      maxIterations: data?.maxIterations,
    });
    writeLoopState(loop);
    if (data?.notify === true && typeof app.sendMessage === "function") {
      await app
        .sendMessage(
          loop.conversationId,
          `[ralph-loop] Started iterative loop (max ${loop.maxIterations} iterations). Work on: ${loop.prompt || "the current task"}. Emit <promise>${loop.completionPromise}</promise> only when all completion criteria are verified.`,
        )
        .catch(() => undefined);
    }
    return { loop };
  } catch (err) {
    return fail(err.message);
  }
});

app.api("/api/cancel-loop", (data) => {
  const existing = readLoopState(data?.conversationId);
  if (!existing) return fail("No loop found for that conversation", 404);
  const cancelled = {
    ...existing,
    active: false,
    status: "cancelled",
    completedAt: Date.now(),
    updatedAt: Date.now(),
  };
  writeLoopState(cancelled);
  return { loop: cancelled };
});

app.api("/api/wake-loop", async (data) => {
  const existing = readLoopState(data?.conversationId);
  if (!existing) return fail("No loop found for that conversation", 404);
  const stepped = updateLoopIteration(
    { ...existing, active: true },
    { now: Date.now() },
  );
  writeLoopState(stepped);
  if (typeof app.sendMessage === "function") {
    await app
      .sendMessage(
        stepped.conversationId,
        `[ralph-loop] Manual wake (iteration ${stepped.iteration}/${stepped.maxIterations}): continue working on "${stepped.prompt || "the task"}" until ready to emit <promise>${stepped.completionPromise}</promise>.`,
      )
      .catch(() => undefined);
  }
  return { loop: stepped };
});

app.run();
