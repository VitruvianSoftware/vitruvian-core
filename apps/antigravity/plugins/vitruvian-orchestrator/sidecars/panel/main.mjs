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

// Backend for the vitruvian-orchestrator sidecar panel.
// Reads the newest flow JSONL file (plus transcript-derived invoke_subagent /
// send_message runs for the same conversation, adapted from savvy-fleet),
// folds every event through orchestrator-core's `reduce`, and serves
// `/api/state` and the panel UI. Also runs standalone with `node main.mjs`
// honoring `PORT` and `VITRUVIAN_ORCH_DIR`.

import {
  existsSync,
  readdirSync,
  readFileSync,
  realpathSync,
  statSync,
} from "node:fs";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  burnDown,
  initialFlow,
  reduce,
  remaining,
  runCost,
  spend,
  taskBoard,
} from "./lib/orchestrator-core.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
export const PHASES = Object.freeze([
  "plan",
  "design",
  "delegate",
  "review",
  "close",
]);

function readVersion() {
  try {
    return String(
      JSON.parse(readFileSync(join(HERE, "..", "..", "plugin.json"), "utf8"))
        .version ?? "0.2.0",
    );
  } catch {
    return "0.2.0";
  }
}
const VERSION = readVersion();

export function resolveFlowsDir(overrideDir) {
  if (overrideDir) return overrideDir;
  if (process.env.VITRUVIAN_ORCH_DIR) return process.env.VITRUVIAN_ORCH_DIR;
  return join(
    homedir(),
    ".gemini",
    "antigravity",
    "vitruvian-orchestrator",
    "flows",
  );
}

/**
 * Formats elapsed milliseconds across four human-readable bands:
 * - under 1m: "45s"
 * - under 1h: "12m 05s"
 * - under 1d: "3h 07m"
 * - 1d or more: "2d 4h"
 *
 * @param {number} ms
 * @returns {string}
 */
export function formatElapsed(ms) {
  const totalSec = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
  if (totalSec < 60) {
    return `${totalSec}s`;
  }
  if (totalSec < 3600) {
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    return `${m}m ${String(s).padStart(2, "0")}s`;
  }
  if (totalSec < 86400) {
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    return `${h}h ${String(m).padStart(2, "0")}m`;
  }
  const d = Math.floor(totalSec / 86400);
  const h = Math.floor((totalSec % 86400) / 3600);
  return `${d}d ${h}h`;
}

function unquoteString(val) {
  const s = String(val ?? "").trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    try {
      const parsed = JSON.parse(s);
      if (typeof parsed === "string") return parsed.trim();
    } catch {
      return s.slice(1, -1).trim();
    }
  }
  return s;
}

function readToolArgs(tc) {
  if (!tc || typeof tc !== "object") return {};
  const raw = tc.args ?? tc.arguments ?? tc.input ?? tc.parameters ?? {};
  if (typeof raw === "string") {
    try {
      return JSON.parse(raw);
    } catch {
      return {};
    }
  }
  return raw && typeof raw === "object" ? raw : {};
}

function parseEntryTime(entry, fallbackMs) {
  if (typeof entry?.at === "number" && Number.isFinite(entry.at)) {
    return entry.at;
  }
  if (typeof entry?.created_at === "string" && entry.created_at) {
    const parsed = Date.parse(entry.created_at);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallbackMs;
}

/**
 * Parses a flow `.jsonl` string into an array of raw event objects.
 *
 * @param {string} jsonlText
 * @returns {Array<Record<string, any>>}
 */
export function parseFlowJsonl(jsonlText = "") {
  const events = [];
  for (const line of String(jsonlText ?? "").split("\n")) {
    if (!line.trim()) continue;
    try {
      const parsed = JSON.parse(line);
      if (
        parsed &&
        typeof parsed === "object" &&
        typeof parsed.type === "string"
      ) {
        events.push(parsed);
      }
    } catch {
      // Ignore malformed JSONL line.
    }
  }
  return events;
}

/**
 * Extracts `run.start`, `run.progress`, and `run.end` events from an
 * Antigravity `transcript.jsonl` string, adapting savvy-fleet's parsing of
 * `invoke_subagent` and `send_message`.
 *
 * @param {string} transcriptText
 * @param {number} [baseAt]
 * @returns {Array<Record<string, any>>}
 */
export function extractTranscriptRunEvents(transcriptText = "", baseAt = 0) {
  const entries = [];
  for (const line of String(transcriptText ?? "").split("\n")) {
    if (!line.trim()) continue;
    try {
      const parsed = JSON.parse(line);
      if (parsed && typeof parsed === "object") entries.push(parsed);
    } catch {
      // Ignore malformed transcript line.
    }
  }

  const events = [];
  const subagentsByConvId = new Map();
  let leadStarted = false;
  let leadStartAt = baseAt;
  let leadModel = "pro";
  const leadTokens = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };

  for (let i = 0; i < entries.length; i += 1) {
    const entry = entries[i];
    const stepAt = parseEntryTime(entry, baseAt > 0 ? baseAt + i * 10 : 0);

    // Track lead token usage when reported on PLANNER_RESPONSE steps.
    const inTok = Number(entry.input_tokens ?? entry.inputTokens ?? 0) || 0;
    const outTok = Number(entry.output_tokens ?? entry.outputTokens ?? 0) || 0;
    const cacheReadTok =
      Number(entry.cache_read_tokens ?? entry.cacheReadTokens ?? 0) || 0;
    const cacheWriteTok =
      Number(entry.cache_write_tokens ?? entry.cacheWriteTokens ?? 0) || 0;
    if (inTok > 0 || outTok > 0 || cacheReadTok > 0 || cacheWriteTok > 0) {
      if (!leadStarted) {
        leadStarted = true;
        leadStartAt = stepAt;
        if (typeof entry.model === "string" && entry.model.trim()) {
          leadModel = unquoteString(entry.model);
        }
        events.push({
          type: "run.start",
          at: leadStartAt,
          id: "lead",
          harness: "antigravity",
          agent: "lead",
          model: leadModel,
          effort: null,
          title: "Lead orchestrator",
          role: "lead",
          tokens: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        });
      }
      leadTokens.input += inTok;
      leadTokens.output += outTok;
      leadTokens.cacheRead += cacheReadTok;
      leadTokens.cacheWrite += cacheWriteTok;
      events.push({
        type: "run.progress",
        at: stepAt,
        id: "lead",
        tokens: { ...leadTokens },
      });
    }

    // Detect subagent completion messages delivered via SYSTEM_MESSAGE.
    if (
      entry.type === "SYSTEM_MESSAGE" &&
      typeof entry.content === "string" &&
      entry.content.includes("sender=")
    ) {
      const senderMatch = /\bsender=([a-zA-Z0-9_-]+)/.exec(entry.content);
      if (senderMatch) {
        const senderId = senderMatch[1];
        const sub = subagentsByConvId.get(senderId);
        if (sub && sub.activeRunId) {
          events.push({
            type: "run.end",
            at: stepAt,
            id: sub.activeRunId,
            status: "done",
          });
          sub.activeRunId = null;
        }
      }
    }

    const tcs = Array.isArray(entry.tool_calls) ? entry.tool_calls : [];
    for (let tcIdx = 0; tcIdx < tcs.length; tcIdx += 1) {
      const tc = tcs[tcIdx];
      if (!tc || typeof tc !== "object") continue;
      const name = String(tc.name ?? tc.tool_name ?? "unknown");
      const rawArgs = readToolArgs(tc);

      if (name === "invoke_subagent") {
        let items = [rawArgs];
        if (typeof rawArgs.Subagents === "string") {
          try {
            const parsedList = JSON.parse(rawArgs.Subagents);
            if (Array.isArray(parsedList) && parsedList.length > 0) {
              items = parsedList;
            }
          } catch {
            // Fall back to rawArgs.
          }
        }

        // Check if the immediately following GENERIC entry carries the created subagent's conversationId.
        let createdConvId = "";
        const nextEntry = entries[i + 1];
        if (
          nextEntry &&
          nextEntry.type === "GENERIC" &&
          typeof nextEntry.content === "string"
        ) {
          const cidMatch = /"conversationId"\s*:\s*"([^"]+)"/.exec(
            nextEntry.content,
          );
          if (cidMatch) {
            createdConvId = cidMatch[1].trim();
          }
        }

        for (const item of items) {
          const agent =
            unquoteString(
              item.TypeName ??
                item.subagent_type ??
                item.type ??
                item.agent ??
                "self",
            ) || "self";
          const title =
            unquoteString(
              item.Role ?? item.description ?? item.role ?? agent,
            ) || agent;
          const model =
            unquoteString(item.Model ?? item.model ?? "inherit") || "inherit";
          const effort = item.effort ? unquoteString(item.effort) : null;

          const convId =
            createdConvId ||
            unquoteString(
              item.conversationId ??
                tc.id ??
                tc.tool_call_id ??
                `subagent-${subagentsByConvId.size + 1}`,
            );

          subagentsByConvId.set(convId, {
            convId,
            agent,
            title,
            model,
            effort,
            round: 1,
            activeRunId: convId,
            asyncLifecycle: Boolean(createdConvId),
          });

          events.push({
            type: "run.start",
            at: stepAt,
            id: convId,
            harness: "antigravity",
            agent,
            model,
            effort,
            title,
            role: "worker",
          });

          if (!createdConvId) {
            if (entry.status === "ERROR") {
              events.push({
                type: "run.end",
                at: stepAt > 0 ? stepAt + 1 : 0,
                id: convId,
                status: "error",
              });
              subagentsByConvId.get(convId).activeRunId = null;
            } else if (entry.status === "DONE") {
              events.push({
                type: "run.end",
                at: stepAt > 0 ? stepAt + 1 : 0,
                id: convId,
                status: "done",
              });
              subagentsByConvId.get(convId).activeRunId = null;
            }
          }
        }
      } else if (name === "send_message") {
        const recipient = unquoteString(
          rawArgs.Recipient ?? rawArgs.recipient ?? "",
        );
        if (recipient && subagentsByConvId.has(recipient)) {
          const sub = subagentsByConvId.get(recipient);
          sub.round += 1;
          const nextRunId = `${recipient}#${sub.round}`;
          sub.activeRunId = nextRunId;
          events.push({
            type: "run.start",
            at: stepAt,
            id: nextRunId,
            harness: "antigravity",
            agent: sub.agent,
            model: sub.model,
            effort: sub.effort,
            title: sub.title,
            role: "worker",
          });
          if (!sub.asyncLifecycle) {
            if (entry.status === "ERROR") {
              events.push({
                type: "run.end",
                at: stepAt > 0 ? stepAt + 1 : 0,
                id: nextRunId,
                status: "error",
              });
              sub.activeRunId = null;
            } else if (entry.status === "DONE") {
              events.push({
                type: "run.end",
                at: stepAt > 0 ? stepAt + 1 : 0,
                id: nextRunId,
                status: "done",
              });
              sub.activeRunId = null;
            }
          }
        }
      }
    }
  }

  return events;
}

const EVENT_ORDER = Object.freeze({
  plan: 0,
  phase: 1,
  "run.start": 2,
  "run.progress": 3,
  "run.end": 4,
  "task.return": 5,
  "task.accept": 6,
  close: 7,
});

/**
 * Folds flow JSONL events and transcript-derived subagent events through
 * orchestrator-core's `reduce(flow, event)`.
 *
 * @param {Array<Record<string, any>>} flowEvents
 * @param {Array<Record<string, any>>} [transcriptEvents]
 */
export function foldFlowEvents(flowEvents = [], transcriptEvents = []) {
  const safeFlowEvents = Array.isArray(flowEvents) ? flowEvents : [];
  const safeTranscriptEvents = Array.isArray(transcriptEvents)
    ? transcriptEvents
    : [];

  const firstPlan = safeFlowEvents.find((e) => e?.type === "plan");
  const baseAt =
    typeof firstPlan?.at === "number" && Number.isFinite(firstPlan.at)
      ? firstPlan.at
      : 1000;

  const existingRunIds = new Set(
    safeFlowEvents
      .filter((e) => e?.type === "run.start" && typeof e.id === "string")
      .map((e) => e.id),
  );

  const normalizedTranscript = [];
  for (let i = 0; i < safeTranscriptEvents.length; i += 1) {
    const ev = safeTranscriptEvents[i];
    if (!ev || typeof ev !== "object") continue;
    if (ev.id && existingRunIds.has(ev.id)) continue;
    const at = typeof ev.at === "number" && ev.at > 0 ? ev.at : baseAt + i + 1;
    normalizedTranscript.push({ ...ev, at });
  }

  const combined = [...safeFlowEvents, ...normalizedTranscript]
    .map((ev, idx) => ({ ev, idx }))
    .sort((a, b) => {
      const atA = typeof a.ev.at === "number" ? a.ev.at : baseAt;
      const atB = typeof b.ev.at === "number" ? b.ev.at : baseAt;
      if (atA !== atB) return atA - atB;
      const ordA = EVENT_ORDER[a.ev.type] ?? 99;
      const ordB = EVENT_ORDER[b.ev.type] ?? 99;
      if (ordA !== ordB) return ordA - ordB;
      return a.idx - b.idx;
    })
    .map((item) => item.ev);

  let flow = initialFlow();
  for (const rawEvent of combined) {
    let event = rawEvent;
    if (
      flow &&
      event.type === "run.progress" &&
      !flow.runs.some((r) => r.id === event.id)
    ) {
      const byPrefix =
        event.id &&
        flow.runs.findLast(
          (r) => r.id === event.id || r.id.startsWith(`${event.id}#`),
        );
      const byAgent =
        !byPrefix &&
        event.agent &&
        flow.runs.findLast(
          (r) =>
            r.role === "worker" &&
            r.status === "running" &&
            r.agent === event.agent,
        );
      const fallbackWorker =
        !byPrefix &&
        !byAgent &&
        flow.runs.findLast(
          (r) => r.role === "worker" && r.status === "running",
        );
      const target = byPrefix || byAgent || fallbackWorker;
      if (target) {
        event = { ...event, id: target.id };
      }
    }
    flow = reduce(flow, event);
  }
  return flow;
}

/**
 * Builds the `/api/state` payload from a folded `Flow | null`.
 *
 * @param {import("./lib/orchestrator-core.mjs").Flow | null} flow
 * @param {{ conversationId?: string, version?: string, now?: number }} [meta]
 */
export function buildPanelState(flow, meta = {}) {
  const now =
    typeof meta.now === "number" && Number.isFinite(meta.now)
      ? meta.now
      : Date.now();
  const conversationId = String(meta.conversationId ?? "");
  const version = String(meta.version ?? VERSION);

  const board = taskBoard(flow);
  const burn = burnDown(flow);
  const rem = remaining(flow);
  const spendSummary = spend(flow);
  const totalTasks = flow ? flow.tasks.length : 0;
  const accepted = totalTasks - rem;

  const runs = flow
    ? flow.runs.map((r) => {
        const cost = runCost(r);
        const endMs = r.endedAt ?? flow.closedAt ?? now;
        const elapsedMs = Math.max(0, endMs - (r.startedAt ?? endMs));
        const totalTokens =
          (r.tokens?.input ?? 0) +
          (r.tokens?.output ?? 0) +
          (r.tokens?.cacheRead ?? 0) +
          (r.tokens?.cacheWrite ?? 0);
        return {
          ...r,
          cost,
          elapsedMs,
          elapsedFormatted: formatElapsed(elapsedMs),
          totalTokens,
        };
      })
    : [];

  return {
    version,
    conversationId,
    hasFlow: Boolean(flow),
    flow,
    title: flow?.title ?? "",
    phase: flow?.phase ?? "plan",
    phases: PHASES,
    accepted,
    totalTasks,
    remaining: rem,
    burnDown: burn,
    taskBoard: board,
    runs,
    spend: spendSummary,
    now,
  };
}

/**
 * Finds the newest `.jsonl` flow file in `flowsDir` (or the requested `cid` if present).
 *
 * @param {string} flowsDir
 * @param {string} [requestedCid]
 */
export function selectFlowFile(flowsDir, requestedCid = "") {
  if (!flowsDir || !existsSync(flowsDir)) {
    return null;
  }
  const cleanCid = String(requestedCid ?? "")
    .trim()
    .replace(/[^a-zA-Z0-9._-]/g, "");
  if (cleanCid) {
    const directPath = join(flowsDir, `${cleanCid}.jsonl`);
    if (existsSync(directPath)) {
      return { conversationId: cleanCid, filePath: directPath };
    }
  }

  let candidates = [];
  try {
    candidates = readdirSync(flowsDir)
      .filter((name) => name.endsWith(".jsonl"))
      .map((name) => {
        const filePath = join(flowsDir, name);
        let mtimeMs = 0;
        try {
          mtimeMs = statSync(filePath).mtimeMs;
        } catch {
          mtimeMs = 0;
        }
        return {
          name,
          conversationId: basename(name, ".jsonl"),
          filePath,
          mtimeMs,
        };
      })
      .filter((c) => c.mtimeMs > 0)
      .sort((a, b) => b.mtimeMs - a.mtimeMs || b.name.localeCompare(a.name));
  } catch {
    return null;
  }

  return candidates[0] || null;
}

export function readTranscriptForConversation(conversationId) {
  const cleanCid = String(conversationId ?? "")
    .trim()
    .replace(/[^a-zA-Z0-9._-]/g, "");
  if (!cleanCid) return "";

  const roots = [
    process.env.ANTIGRAVITY_APP_DATA_DIR,
    join(homedir(), ".gemini", "antigravity"),
    join(homedir(), ".gemini", "antigravity-cli"),
  ].filter(Boolean);

  for (const root of roots) {
    const candidate = join(
      root,
      "brain",
      cleanCid,
      ".system_generated",
      "logs",
      "transcript.jsonl",
    );
    if (existsSync(candidate)) {
      try {
        return readFileSync(candidate, "utf8");
      } catch {
        // Try next candidate root.
      }
    }
  }
  return "";
}

/**
 * Loads the newest flow file from `flowsDir` (and its matching conversation transcript),
 * folds them through `orchestrator-core`, and returns the `/api/state` object.
 *
 * @param {{ flowsDir?: string, cid?: string, transcriptText?: string, now?: number }} [options]
 */
export function loadLivePanelState(options = {}) {
  const flowsDir = resolveFlowsDir(options.flowsDir);
  const selected = selectFlowFile(flowsDir, options.cid);
  if (!selected) {
    return buildPanelState(null, {
      conversationId: String(options.cid ?? ""),
      version: VERSION,
      now: options.now,
    });
  }

  let flowJsonl = "";
  try {
    flowJsonl = readFileSync(selected.filePath, "utf8");
  } catch {
    flowJsonl = "";
  }

  const flowEvents = parseFlowJsonl(flowJsonl);
  const firstPlan = flowEvents.find((e) => e.type === "plan");
  const baseAt = typeof firstPlan?.at === "number" ? firstPlan.at : 0;

  const transcriptText =
    options.transcriptText !== undefined
      ? options.transcriptText
      : readTranscriptForConversation(selected.conversationId);
  const transcriptEvents = transcriptText
    ? extractTranscriptRunEvents(transcriptText, baseAt)
    : [];

  const flow = foldFlowEvents(flowEvents, transcriptEvents);
  return buildPanelState(flow, {
    conversationId: selected.conversationId,
    version: VERSION,
    now: options.now,
  });
}

const readLocal = (name) => readFileSync(join(HERE, name), "utf8");
const STANDALONE_PRELOAD_JS = `window.sidecar = window.sidecar || {
  conversationId: new URLSearchParams(window.location.search).get("conversationId") || "",
  fetch: (url, opts) => window.fetch(url, opts),
};
`;

export function createStandaloneServer(options = {}) {
  return createServer((req, res) => {
    const url = new URL(req.url || "/", "http://127.0.0.1");
    if (
      req.method === "GET" &&
      (url.pathname === "/" || url.pathname === "/index.html")
    ) {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      res.end(readLocal("index.html"));
      return;
    }
    if (req.method === "GET" && url.pathname === "/app.js") {
      res.writeHead(200, {
        "Content-Type": "application/javascript; charset=utf-8",
      });
      res.end(readLocal("app.js"));
      return;
    }
    if (req.method === "GET" && url.pathname === "/styles.css") {
      res.writeHead(200, { "Content-Type": "text/css; charset=utf-8" });
      res.end(readLocal("styles.css"));
      return;
    }
    if (req.method === "GET" && url.pathname === "/preload.js") {
      res.writeHead(200, {
        "Content-Type": "application/javascript; charset=utf-8",
      });
      res.end(STANDALONE_PRELOAD_JS);
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/state") {
      const cid = url.searchParams.get("cid") || "";
      const state = loadLivePanelState({
        flowsDir: options.flowsDir,
        cid,
      });
      res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify(state));
      return;
    }
    res.writeHead(404, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ error: "Not found" }));
  });
}

async function startServer() {
  const hasSidecarEnv =
    Boolean(process.env.ANTIGRAVITY_LS_ADDRESS) &&
    Boolean(process.env.ANTIGRAVITY_CSRF_TOKEN) &&
    Boolean(process.env.ANTIGRAVITY_SIDECAR_WEB_PORT) &&
    !process.env.PORT;

  if (hasSidecarEnv) {
    try {
      const { Response, SidecarApp } = await import("sidecar_sdk");
      const app = new SidecarApp();
      app.page("/", () => readLocal("index.html"));
      app.page("/app.js", () => readLocal("app.js"));
      app.api(
        "/styles.css",
        () =>
          new Response(readLocal("styles.css"), { contentType: "text/css" }),
        "GET",
      );
      app.api(
        "/api/state",
        (data) => loadLivePanelState({ cid: data?.cid || "" }),
        "GET",
      );
      await app.run();
      console.log(
        `http://127.0.0.1:${process.env.ANTIGRAVITY_SIDECAR_WEB_PORT}`,
      );
      return;
    } catch {
      // Fall back to standalone HTTP server if sidecar_sdk is unavailable.
    }
  }

  const port = Number(
    process.env.PORT || process.env.ANTIGRAVITY_SIDECAR_WEB_PORT || 0,
  );
  const server = createStandaloneServer();
  server.listen(port, "127.0.0.1", () => {
    const addr = server.address();
    const actualPort = typeof addr === "object" && addr ? addr.port : port;
    console.log(`http://127.0.0.1:${actualPort}`);
  });
}

function isMainModule() {
  try {
    if (!process.argv[1]) return false;
    return (
      realpathSync(process.argv[1]) ===
      realpathSync(fileURLToPath(import.meta.url))
    );
  } catch {
    return false;
  }
}

if (isMainModule()) {
  void startServer();
}
