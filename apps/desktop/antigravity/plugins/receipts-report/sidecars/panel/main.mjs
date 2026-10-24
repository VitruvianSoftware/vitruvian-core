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

// Backend for the receipts-report panel. Scans Antigravity session transcripts
// in ~/.gemini/antigravity/brain, ingests turn notes from hooks/record-turn.sh,
// aggregates project impact receipts, and exports HTML or CSV reports.

import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Response, SidecarApp } from "sidecar_sdk";

import {
  aggregateProjectReceipts,
  detectTokenHotspots,
  formatCsvReceipt,
  parseTranscriptJsonl,
  projectFromPath,
  renderHtmlReceipt,
} from "./lib/core.mjs";
import { parseOpenUILang, toOpenUILang } from "./lib/openui.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const APP_DATA_DIR =
  process.env.ANTIGRAVITY_APP_DATA_DIR ||
  join(homedir(), ".gemini", "antigravity");
const BRAIN_DIR = join(APP_DATA_DIR, "brain");
const INBOX_DIR = join(APP_DATA_DIR, "receipts-report-inbox");
const DATA_DIR =
  process.env.ANTIGRAVITY_EXECUTABLE_DATA_DIR || join(HERE, ".data");

mkdirSync(DATA_DIR, { recursive: true });
const SETTINGS_FILE = join(DATA_DIR, "settings.json");

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

function loadSettings() {
  try {
    const raw = JSON.parse(readFileSync(SETTINGS_FILE, "utf8"));
    return {
      windowDays: Number(raw.windowDays ?? 14),
      projectFilter: String(raw.projectFilter ?? ""),
      maxSessions: Math.min(200, Math.max(5, Number(raw.maxSessions ?? 50))),
    };
  } catch {
    return { windowDays: 14, projectFilter: "", maxSessions: 50 };
  }
}

function saveSettings(patch = {}) {
  const current = loadSettings();
  const next = {
    windowDays:
      patch.windowDays !== undefined
        ? Number(patch.windowDays)
        : current.windowDays,
    projectFilter:
      patch.projectFilter !== undefined
        ? String(patch.projectFilter)
        : current.projectFilter,
    maxSessions:
      patch.maxSessions !== undefined
        ? Math.min(200, Math.max(5, Number(patch.maxSessions)))
        : current.maxSessions,
  };
  writeFileSync(SETTINGS_FILE, JSON.stringify(next, null, 2) + "\n", "utf8");
  return next;
}

const inboxMetaByConv = new Map();

function drainInbox() {
  if (!existsSync(INBOX_DIR)) return;
  let files = [];
  try {
    files = readdirSync(INBOX_DIR).filter((f) => f.endsWith(".json"));
  } catch {
    return;
  }
  for (const name of files) {
    const full = join(INBOX_DIR, name);
    try {
      const note = JSON.parse(readFileSync(full, "utf8"));
      if (note?.conversationId) {
        const ws = Array.isArray(note.workspacePaths)
          ? note.workspacePaths[0]
          : "";
        inboxMetaByConv.set(String(note.conversationId), {
          workspacePath: ws || "",
          project: ws ? projectFromPath(ws) : undefined,
          modelName: note.modelName || undefined,
        });
      }
    } catch {
      // ignore malformed note
    }
    try {
      rmSync(full, { force: true });
    } catch {
      // ignore removal error
    }
  }
}

let cachedSessions = [];
let lastScanAt = 0;

function scanBrainTranscripts(force = false) {
  drainInbox();
  const settings = loadSettings();
  if (!force && cachedSessions.length > 0 && Date.now() - lastScanAt < 30_000) {
    return cachedSessions;
  }
  if (!existsSync(BRAIN_DIR)) {
    cachedSessions = [];
    lastScanAt = Date.now();
    return cachedSessions;
  }
  let entries = [];
  try {
    entries = readdirSync(BRAIN_DIR, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => {
        const transcriptPath = join(
          BRAIN_DIR,
          d.name,
          ".system_generated",
          "logs",
          "transcript.jsonl",
        );
        let mtimeMs = 0;
        try {
          mtimeMs = statSync(transcriptPath).mtimeMs;
        } catch {
          mtimeMs = 0;
        }
        return { convId: d.name, transcriptPath, mtimeMs };
      })
      .filter((e) => e.mtimeMs > 0)
      .sort((a, b) => b.mtimeMs - a.mtimeMs)
      .slice(0, settings.maxSessions);
  } catch {
    entries = [];
  }

  const parsed = [];
  for (const entry of entries) {
    try {
      const raw = readFileSync(entry.transcriptPath, "utf8");
      const meta = inboxMetaByConv.get(entry.convId) || {};
      const receipt = parseTranscriptJsonl(raw, {
        conversationId: entry.convId,
        ...meta,
      });
      if (!receipt.endedAt) receipt.endedAt = entry.mtimeMs;
      parsed.push(receipt);
    } catch {
      // skip unreadable transcript
    }
  }
  cachedSessions = parsed;
  lastScanAt = Date.now();
  return cachedSessions;
}

function buildState(force = false) {
  const settings = loadSettings();
  const sessions = scanBrainTranscripts(force);
  const report = aggregateProjectReceipts(
    sessions,
    {},
    {
      windowDays: settings.windowDays,
      projectFilter: settings.projectFilter,
    },
  );
  const hotspots = detectTokenHotspots(report.sessions);
  return {
    version: VERSION,
    settings,
    lastScanAt,
    report,
    hotspots,
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
    const state = buildState(false);
    return { ...state, openuiDsl: toOpenUILang(state) };
  },
  "GET",
);

app.api(
  "/api/openui",
  () => {
    const dsl = toOpenUILang(buildState(false));
    return { dsl, parsed: parseOpenUILang(dsl) };
  },
  "GET",
);

app.api("/api/scan", () => {
  const state = buildState(true);
  return { ...state, openuiDsl: toOpenUILang(state) };
});

app.api("/api/settings", (data = {}) => {
  saveSettings(data);
  const state = buildState(true);
  return { ...state, openuiDsl: toOpenUILang(state) };
});

app.api("/api/export", (data = {}) => {
  const format = String(data?.format ?? "csv").toLowerCase();
  const state = buildState(false);
  if (format === "html") {
    return {
      format: "html",
      filename: "antigravity-receipt.html",
      content: renderHtmlReceipt(state.report, state.hotspots),
    };
  }
  return {
    format: "csv",
    filename: "antigravity-receipt.csv",
    content: formatCsvReceipt(state.report),
  };
});

app.run();
