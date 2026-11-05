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

// Backend for the savvy-fleet sidecar panel. Antigravity runs this with its
// bundled Node.js runtime and resolves `sidecar_sdk` at launch.

import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Response, SidecarApp } from "sidecar_sdk";

import {
  PHASES,
  TIERS,
  blankFlow,
  mergeFlowProgress,
  summariseFleetState,
} from "./lib/core.mjs";
import { parseOpenUILang, toOpenUILang } from "./lib/openui.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const APP_DATA_DIR =
  process.env.ANTIGRAVITY_APP_DATA_DIR ||
  join(homedir(), ".gemini", "antigravity");
const DATA_DIR =
  process.env.ANTIGRAVITY_EXECUTABLE_DATA_DIR || join(HERE, ".data");
const INBOX_DIR = join(APP_DATA_DIR, "savvy-fleet-inbox");
const STATE_FILE = join(DATA_DIR, "flow-state.json");

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

let currentFlow = loadSavedFlow();
const inboxEvents = [];

function loadSavedFlow() {
  try {
    if (existsSync(STATE_FILE)) {
      return mergeFlowProgress(
        null,
        JSON.parse(readFileSync(STATE_FILE, "utf8")),
      );
    }
  } catch {
    // Fall back to a fresh flow state.
  }
  return blankFlow();
}

function saveFlow(flow) {
  try {
    mkdirSync(DATA_DIR, { recursive: true });
    writeFileSync(STATE_FILE, JSON.stringify(flow, null, 2) + "\n", "utf8");
  } catch {
    // Non-fatal if data directory is read-only.
  }
}

function drainInbox() {
  if (!existsSync(INBOX_DIR)) return;
  try {
    const files = readdirSync(INBOX_DIR)
      .filter((f) => f.endsWith(".json"))
      .sort();
    for (const file of files) {
      const fullPath = join(INBOX_DIR, file);
      try {
        const raw = readFileSync(fullPath, "utf8");
        inboxEvents.push(JSON.parse(raw));
      } catch {
        // Ignore malformed note.
      }
      try {
        unlinkSync(fullPath);
      } catch {
        // Ignore if already removed.
      }
    }
    if (inboxEvents.length > 100) {
      inboxEvents.splice(0, inboxEvents.length - 100);
    }
  } catch {
    // Ignore read errors.
  }
}

function readTranscriptText(cid) {
  if (!cid) return "";
  const safeCid = String(cid).replace(/[^a-zA-Z0-9_-]/g, "");
  if (!safeCid) return "";
  const transcriptPath = join(
    APP_DATA_DIR,
    "brain",
    safeCid,
    ".system_generated",
    "logs",
    "transcript.jsonl",
  );
  if (!existsSync(transcriptPath)) return "";
  try {
    return readFileSync(transcriptPath, "utf8");
  } catch {
    return "";
  }
}

function buildState(cid = "") {
  drainInbox();
  const transcript = readTranscriptText(cid);
  const state = summariseFleetState({
    version: VERSION,
    conversationId: cid,
    flow: currentFlow,
    transcript,
    inboxNotes: inboxEvents,
  });
  return {
    ...state,
    phases: PHASES,
    tiers: TIERS,
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
  (data) => {
    const state = buildState(data?.cid);
    return { ...state, openuiDsl: toOpenUILang(state) };
  },
  "GET",
);

app.api(
  "/api/openui",
  (data) => {
    const state = buildState(data?.cid);
    const dsl = toOpenUILang(state);
    return { dsl, parsed: parseOpenUILang(dsl) };
  },
  "GET",
);

app.api("/api/progress", (data) => {
  currentFlow = mergeFlowProgress(currentFlow, data ?? {});
  saveFlow(currentFlow);
  const state = buildState(data?.cid);
  return { ...state, openuiDsl: toOpenUILang(state) };
});

app.api("/api/reset", (data) => {
  currentFlow = blankFlow();
  inboxEvents.length = 0;
  saveFlow(currentFlow);
  const state = buildState(data?.cid);
  return { ...state, openuiDsl: toOpenUILang(state) };
});

app.run();
