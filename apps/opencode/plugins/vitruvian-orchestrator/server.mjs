// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  applyBoardCall,
  applyPostCall,
  applyProgressCall,
  applyStepCall,
  formatWake,
  mapOpenCodeTokens,
  mergeTokenSnapshots,
  parseModelAndEffort,
  pendingWakes,
  reduce,
} from "./lib/adapter.mjs";

export const PLUGIN_ID = "vitruvian-orchestrator";

const VALID_SESSION_ID_RE = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/;

export function isValidSessionId(raw) {
  if (typeof raw !== "string") return false;
  const id = raw.trim();
  if (!id || id === "." || id === ".." || id.includes("..")) return false;
  return VALID_SESSION_ID_RE.test(id);
}

export function getStateDir() {
  return (
    process.env.VITRUVIAN_ORCHESTRATOR_STATE_DIR ||
    path.join(os.homedir(), ".local", "state", "opencode", PLUGIN_ID)
  );
}

export function getStateFilePath(stateDir = getStateDir()) {
  return path.join(stateDir, "state.json");
}

function readPersistedState(stateDir = getStateDir()) {
  const file = getStateFilePath(stateDir);
  try {
    if (!fs.existsSync(file)) {
      return { updatedAt: 0, activeSessionID: null, flows: {} };
    }
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    if (parsed && typeof parsed === "object" && parsed.flows) {
      return parsed;
    }
  } catch {
    // Ignore corrupted or partial state files
  }
  return { updatedAt: 0, activeSessionID: null, flows: {} };
}

function writeJsonAtomic(filePath, payload) {
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  const tmpPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(payload, null, 2) + "\n", "utf8");
  fs.renameSync(tmpPath, filePath);
}

const PROGRESS_INPUT_SCHEMA = {
  type: "object",
  properties: {
    title: {
      type: "string",
      description:
        "Flow title (set on initial plan or when renaming the flow).",
    },
    phase: {
      type: "string",
      enum: ["plan", "design", "delegate", "review", "close"],
      description: "Current orchestrator lifecycle phase.",
    },
    tasks: {
      type: "array",
      description:
        "Full planned task list (replaces unaccepted tasks on replan; accepted tasks are preserved).",
      items: {
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          specialist: { type: "string" },
          tier: { type: "string" },
          after: {
            type: "array",
            items: { type: "number" },
          },
        },
        required: ["title", "specialist", "tier"],
        additionalProperties: false,
      },
    },
    accept: {
      anyOf: [
        { type: "integer", minimum: 1 },
        { type: "array", items: { type: "number" } },
      ],
      description: "1-based task number(s) accepted after adversarial review.",
    },
    return: {
      anyOf: [
        { type: "integer", minimum: 1 },
        { type: "array", items: { type: "number" } },
      ],
      description: "1-based task number(s) returned for rework.",
    },
    retire: {
      type: "string",
      description: "Run id or specialist agent name to retire.",
    },
    kill: {
      type: "string",
      description: "Run id or specialist agent name to kill.",
    },
    finished: {
      type: "boolean",
      description: "Set true when all tasks are accepted and the flow closes.",
    },
  },
  additionalProperties: false,
};

const STEP_INPUT_SCHEMA = {
  type: "object",
  properties: {
    done: {
      type: "integer",
      minimum: 0,
      description: "Completed sub-steps so far (0 <= done <= total).",
    },
    total: {
      type: "integer",
      minimum: 1,
      description: "Total sub-steps in this worker run (>= 1).",
    },
    note: {
      type: "string",
      description: "Optional short label for the current sub-step.",
    },
    delegate: {
      type: "string",
      description:
        "Model that did the work when you handed it to another engine, e.g. gemini-4-carbon-high.",
    },
    delegateUsage: {
      type: "object",
      description:
        "Gemini's token counts from agy-delegate's AGY_USAGE line, summed over every agy-delegate call in this task so far (cache_read -> cacheRead).",
      properties: {
        input: { type: "integer", minimum: 0 },
        output: { type: "integer", minimum: 0 },
        thinking: { type: "integer", minimum: 0 },
        cacheRead: { type: "integer", minimum: 0 },
      },
      additionalProperties: false,
    },
    paused: {
      type: "string",
      enum: ["quota", "error"],
      description: "Optional pause reason when blocked ('quota' or 'error').",
    },
    detail: {
      type: "string",
      description: "Optional detail explaining why the member paused.",
    },
  },
  additionalProperties: false,
};

const POST_INPUT_SCHEMA = {
  type: "object",
  properties: {
    text: {
      type: "string",
      description: "Post body text (capped at 4000 characters).",
    },
    to: {
      type: "array",
      items: { type: "string" },
      description: "Optional explicit recipient agent names.",
    },
    kind: {
      type: "string",
      enum: ["note", "question", "defect", "result"],
      description: "Post kind: note, question, defect, or result.",
    },
    replyTo: {
      type: "integer",
      minimum: 1,
      description: "Optional seq number of the post being replied to.",
    },
  },
  required: ["text"],
  additionalProperties: false,
};

const BOARD_INPUT_SCHEMA = {
  type: "object",
  properties: {
    to: {
      type: "string",
      description:
        "Optional recipient handle filter (e.g. 'wren', or 'me' for posts mentioning the caller; includes @all broadcasts).",
    },
    from: {
      type: "string",
      description: "Optional author handle filter.",
    },
    kind: {
      type: "string",
      enum: ["note", "question", "defect", "result"],
      description: "Optional post kind filter.",
    },
    search: {
      type: "string",
      description: "Optional case-insensitive substring filter.",
    },
    limit: {
      type: "integer",
      minimum: 1,
      maximum: 100,
      description:
        "Maximum newest matching posts to return (default 20, max 100).",
    },
  },
  additionalProperties: false,
};

export default {
  id: PLUGIN_ID,

  async setup(ctx) {
    const stateDir = getStateDir();
    const persisted = readPersistedState(stateDir);

    /** @type {Map<string, import('./lib/orchestrator-core.mjs').Flow>} */
    const flowsByRoot = new Map(Object.entries(persisted.flows || {}));
    let activeRootSessionID = persisted.activeSessionID || null;

    /**
     * Session metadata cache:
     * sessionID -> { id, parentID, rootID, title, agent, model, effort }
     * @type {Map<string, { id: string, parentID?: string, rootID: string, title?: string, agent?: string, model: string, effort: "medium" | "high" | "xhigh" | "max" }>}
     */
    const sessionMeta = new Map();

    /**
     * Per-session token tracking:
     * sessionID -> { steps: Map<string, TokenCounts>, usage: TokenCounts | null }
     * @type {Map<string, { steps: Map<string, { input: number, output: number, cacheRead: number, cacheWrite: number }>, usage: { input: number, output: number, cacheRead: number, cacheWrite: number } | null }>}
     */
    const tokenLedger = new Map();

    function getSessionTokens(sessionID) {
      const entry = tokenLedger.get(sessionID);
      if (!entry) {
        return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
      }
      return mergeTokenSnapshots(entry.steps, entry.usage);
    }

    function recordStepTokens(sessionID, messageID, rawTokens) {
      if (!sessionID || !rawTokens) return getSessionTokens(sessionID);
      let entry = tokenLedger.get(sessionID);
      if (!entry) {
        entry = { steps: new Map(), usage: null };
        tokenLedger.set(sessionID, entry);
      }
      const mapped = mapOpenCodeTokens(rawTokens);
      entry.steps.set(messageID || `step_${entry.steps.size + 1}`, mapped);
      return mergeTokenSnapshots(entry.steps, entry.usage);
    }

    function recordUsageTokens(sessionID, rawTokens) {
      if (!sessionID || !rawTokens) return getSessionTokens(sessionID);
      let entry = tokenLedger.get(sessionID);
      if (!entry) {
        entry = { steps: new Map(), usage: null };
        tokenLedger.set(sessionID, entry);
      }
      entry.usage = mapOpenCodeTokens(rawTokens);
      return mergeTokenSnapshots(entry.steps, entry.usage);
    }

    function persistFlow(rootID, flow) {
      if (!isValidSessionId(rootID) || !flow) return;
      flowsByRoot.set(rootID, flow);
      activeRootSessionID = rootID;
      const now = Date.now();
      const flowsObj = Object.fromEntries(flowsByRoot.entries());
      try {
        writeJsonAtomic(getStateFilePath(stateDir), {
          updatedAt: now,
          activeSessionID: activeRootSessionID,
          flows: flowsObj,
        });
        writeJsonAtomic(path.join(stateDir, `${rootID}.json`), {
          sessionID: rootID,
          updatedAt: now,
          flow,
        });
      } catch {
        // Never crash the host session if disk write fails
      }
    }

    function upsertSessionMeta(sessionID, patch = {}) {
      if (!isValidSessionId(sessionID) || sessionID.trim() === "default") {
        return null;
      }
      const id = sessionID.trim();
      const prev = sessionMeta.get(id);
      const parentID = patch.parentID ?? prev?.parentID ?? undefined;
      const rootID = parentID
        ? sessionMeta.get(parentID)?.rootID || parentID
        : prev?.rootID || id;
      const parsedModel =
        patch.modelRef !== undefined
          ? parseModelAndEffort(patch.modelRef, patch.effortHint)
          : {
              model: prev?.model || "unknown",
              effort: prev?.effort || /** @type {const} */ ("high"),
            };

      const next = {
        id,
        ...(parentID ? { parentID } : {}),
        rootID,
        title: patch.title ?? prev?.title,
        agent: patch.agent ?? prev?.agent,
        model:
          parsedModel.model !== "unknown"
            ? parsedModel.model
            : prev?.model || "unknown",
        effort: parsedModel.effort || prev?.effort || "high",
        verified: patch.verified === true || prev?.verified === true,
      };
      sessionMeta.set(id, next);
      return next;
    }

    async function resolveSessionMeta(sessionID) {
      if (!isValidSessionId(sessionID) || sessionID.trim() === "default") {
        return null;
      }
      const id = sessionID.trim();
      const cached = sessionMeta.get(id);
      if (cached?.verified && cached.model !== "unknown") {
        if (cached.parentID && sessionMeta.has(cached.parentID)) {
          cached.rootID =
            sessionMeta.get(cached.parentID).rootID || cached.parentID;
        }
        return cached;
      }
      if (typeof ctx?.session?.get === "function") {
        try {
          const info = await ctx.session.get({ sessionID: id });
          if (info && typeof info === "object") {
            let rootID = info.parentID || id;
            if (info.parentID && isValidSessionId(info.parentID)) {
              const parentMeta = await resolveSessionMeta(info.parentID);
              rootID = parentMeta?.rootID || info.parentID.trim();
            }
            const meta = upsertSessionMeta(id, {
              parentID: info.parentID,
              title: info.title,
              agent: info.agent,
              modelRef: info.model,
              verified: true,
            });
            if (meta) {
              meta.rootID = rootID;
              sessionMeta.set(id, meta);
              return meta;
            }
          }
        } catch {
          // Fall back to verified cached metadata if any
        }
      }
      if (cached?.verified) {
        if (cached.parentID && sessionMeta.has(cached.parentID)) {
          cached.rootID =
            sessionMeta.get(cached.parentID).rootID || cached.parentID;
        }
        return cached;
      }
      return null;
    }

    function resolveFallbackRootID() {
      if (activeRootSessionID && flowsByRoot.has(activeRootSessionID)) {
        return activeRootSessionID;
      }
      const keys = [...flowsByRoot.keys()];
      return keys.length > 0 ? keys[keys.length - 1] : null;
    }

    function findWorkerRunEntry(callerID) {
      if (!callerID) return null;
      for (const [rID, f] of flowsByRoot.entries()) {
        if (!Array.isArray(f?.runs)) continue;
        const run = f.runs.findLast(
          (r) =>
            r.role !== "lead" &&
            (r.id === callerID || r.id.startsWith(`${callerID}#`)),
        );
        if (run) {
          return { rootID: rID, flow: f, run };
        }
      }
      return null;
    }

    const VALID_HANDLE_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;

    async function resolveToolCaller(toolCtx) {
      const rawID =
        typeof toolCtx?.sessionID === "string" ? toolCtx.sessionID.trim() : "";
      const validID =
        isValidSessionId(rawID) && rawID !== "default" ? rawID : "";
      if (!validID) {
        return {
          known: false,
          isHelper: true,
          callerID: "",
          rootID: resolveFallbackRootID(),
          meta: null,
          workerRun: null,
          callerAgent: "helper",
        };
      }
      const meta = await resolveSessionMeta(validID);
      if (!meta) {
        return {
          known: false,
          isHelper: true,
          callerID: validID,
          rootID: resolveFallbackRootID(),
          meta: null,
          workerRun: null,
          callerAgent: "helper",
        };
      }
      if (toolCtx?.agent && !meta.agent) {
        meta.agent = toolCtx.agent;
      }
      const workerEntry = findWorkerRunEntry(validID);
      const isHelper = Boolean(meta.parentID) || Boolean(workerEntry);
      const rootID = meta.parentID
        ? meta.rootID
        : workerEntry?.rootID || meta.rootID || validID;
      if (!isHelper) {
        return {
          known: true,
          isHelper: false,
          callerID: validID,
          rootID,
          meta,
          workerRun: null,
          callerAgent: "lead",
        };
      }
      const norm = (s) =>
        String(s ?? "")
          .trim()
          .replace(/^@+/, "")
          .toLowerCase();
      const runAgent = norm(workerEntry?.run?.agent);
      const metaAgent = norm(meta.agent);
      const ctxAgent = norm(toolCtx?.agent);
      let callerAgent = "";
      if (VALID_HANDLE_RE.test(runAgent) && runAgent !== "lead") {
        callerAgent = runAgent;
      } else if (VALID_HANDLE_RE.test(metaAgent) && metaAgent !== "lead") {
        callerAgent = metaAgent;
      } else if (VALID_HANDLE_RE.test(ctxAgent) && ctxAgent !== "lead") {
        callerAgent = ctxAgent;
      } else if (
        runAgent === "lead" ||
        metaAgent === "lead" ||
        ctxAgent === "lead"
      ) {
        callerAgent = "helper";
      }
      return {
        known: true,
        isHelper: true,
        callerID: validID,
        rootID,
        meta,
        workerRun: workerEntry?.run ?? null,
        callerAgent,
      };
    }

    function ensureLeadRun(flow, rootID, meta, at = Date.now()) {
      const leadRunId = `lead:${rootID}`;
      const existing = flow.runs.find((r) => r.id === leadRunId);
      let next = flow;
      if (!existing) {
        next = reduce(next, {
          type: "run.start",
          at,
          id: leadRunId,
          harness: "opencode",
          role: "lead",
          agent: meta?.agent || "lead",
          title: "Lead orchestrator",
          model: meta?.model || "unknown",
          effort: meta?.effort || "high",
        });
      } else if (
        existing.model === "unknown" &&
        meta?.model &&
        meta.model !== "unknown"
      ) {
        next = {
          ...next,
          runs: next.runs.map((r) =>
            r.id === leadRunId
              ? { ...r, model: meta.model, effort: meta.effort || r.effort }
              : r,
          ),
        };
      }
      const tokens = getSessionTokens(rootID);
      if (
        tokens.input > 0 ||
        tokens.output > 0 ||
        tokens.cacheRead > 0 ||
        tokens.cacheWrite > 0
      ) {
        next = reduce(next, {
          type: "run.progress",
          at,
          id: leadRunId,
          tokens,
        });
      }
      return next;
    }

    function ensureWorkerRun(flow, childMeta, at = Date.now()) {
      if (!flow || !childMeta?.id) return flow;
      const existing = flow.runs.find((r) => r.id === childMeta.id);
      let next = flow;
      if (!existing || existing.status !== "running") {
        next = reduce(next, {
          type: "run.start",
          at,
          id: childMeta.id,
          harness: "opencode",
          role: "worker",
          agent: childMeta.agent || "self",
          ...(childMeta.title ? { title: childMeta.title } : {}),
          model: childMeta.model || "unknown",
          effort: childMeta.effort || "high",
        });
      } else if (
        existing.model === "unknown" &&
        childMeta.model &&
        childMeta.model !== "unknown"
      ) {
        next = {
          ...next,
          runs: next.runs.map((r) =>
            r.id === childMeta.id
              ? {
                  ...r,
                  model: childMeta.model,
                  effort: childMeta.effort || r.effort,
                  ...(childMeta.agent ? { agent: childMeta.agent } : {}),
                }
              : r,
          ),
        };
      }
      const tokens = getSessionTokens(childMeta.id);
      if (
        tokens.input > 0 ||
        tokens.output > 0 ||
        tokens.cacheRead > 0 ||
        tokens.cacheWrite > 0
      ) {
        next = reduce(next, {
          type: "run.progress",
          at,
          id: childMeta.id,
          tokens,
        });
      }
      return next;
    }

    /** @type {Set<string>} */
    const wokenMentions = new Set();

    async function isKnownChildSession(sessionID) {
      if (!sessionID) return false;
      const cached = sessionMeta.get(sessionID);
      if (cached?.parentID) return true;
      if (typeof ctx?.session?.get === "function") {
        try {
          const info = await ctx.session.get({ sessionID });
          if (info && typeof info === "object" && info.parentID) {
            let rootID = info.parentID;
            const parentCached = sessionMeta.get(info.parentID);
            if (parentCached?.rootID) {
              rootID = parentCached.rootID;
            }
            const meta = upsertSessionMeta(sessionID, {
              parentID: info.parentID,
              title: info.title,
              agent: info.agent,
              modelRef: info.model,
              verified: true,
            });
            if (meta) {
              meta.rootID = rootID;
              sessionMeta.set(meta.id, meta);
            }
            return true;
          }
        } catch {
          return false;
        }
      }
      return false;
    }

    async function deliverPendingWakes(rootID) {
      if (!rootID || typeof ctx?.session?.prompt !== "function") return;
      const initial = flowsByRoot.get(rootID);
      if (!initial || initial.closedAt) return;

      const wakes = pendingWakes(initial);
      for (const wake of wakes) {
        const current = flowsByRoot.get(rootID);
        if (!current || current.closedAt) break;
        const wakeKey = `${wake.seq}:${wake.target}`;
        const scopedKey = `${rootID}:${current.startedAt}:${wakeKey}`;
        if (
          wokenMentions.has(scopedKey) ||
          (Array.isArray(current.woken) && current.woken.includes(wakeKey))
        ) {
          continue;
        }

        wokenMentions.add(scopedKey);
        try {
          const post = Array.isArray(current.posts)
            ? current.posts.find((p) => p.seq === wake.seq)
            : undefined;

          let targetSessionID = rootID;
          let text;
          if (wake.target === "lead") {
            targetSessionID = rootID;
            text = formatWake(wake, post, {
              mode: "worker",
              harness: "opencode",
            });
          } else {
            const baseRunId = wake.runId
              ? String(wake.runId).split("#")[0]
              : "";
            const candidateChildID = baseRunId || wake.runId || "";
            const knownChild =
              candidateChildID && (await isKnownChildSession(candidateChildID));
            if (knownChild) {
              targetSessionID = candidateChildID;
              text = formatWake(wake, post, {
                mode: "worker",
                harness: "opencode",
              });
            } else {
              targetSessionID = rootID;
              text = formatWake(wake, post, {
                mode: "lead",
                harness: "opencode",
              });
            }
          }

          await ctx.session.prompt({ sessionID: targetSessionID, text });
          const latest = flowsByRoot.get(rootID);
          if (latest) {
            const wokenFlow = reduce(latest, {
              type: "wake",
              at: Date.now(),
              seq: wake.seq,
              target: wake.target,
            });
            persistFlow(rootID, wokenFlow);
          }
        } catch {
          // Swallow prompt errors; remove in-flight key so a later pass retries.
          wokenMentions.delete(scopedKey);
        }
      }
    }

    // 1. Register `progress`, `step`, `post`, and `board` tools
    if (ctx?.tool?.transform) {
      await ctx.tool.transform((registry) => {
        registry.add({
          name: "progress",
          description:
            "Report orchestrator plan, phase transitions, task acceptances, task returns, or flow completion to the live Orchestrator panel.",
          options: { codemode: false },
          input: PROGRESS_INPUT_SCHEMA,
          execute: async (args, toolCtx) => {
            const now = Date.now();
            const caller = await resolveToolCaller(toolCtx);
            if (!caller.known) {
              throw new Error("progress is for the lead only: caller unknown");
            }
            if (caller.isHelper) {
              throw new Error("progress is for the lead only");
            }
            const rootID = caller.rootID;
            const prevFlow = flowsByRoot.get(rootID) ?? null;

            const { flow: updatedFlow, summary } = applyProgressCall(
              prevFlow,
              args || {},
              now,
            );
            let nextFlow = ensureLeadRun(updatedFlow, rootID, caller.meta, now);
            if (args?.finished === true) {
              nextFlow = reduce(nextFlow, {
                type: "run.end",
                at: now,
                id: `lead:${rootID}`,
                status: "done",
                tokens: getSessionTokens(rootID),
              });
            }
            persistFlow(rootID, nextFlow);
            await deliverPendingWakes(rootID);
            return { content: summary };
          },
        });

        registry.add({
          name: "step",
          description:
            "Report subagent step progress (done of total, plus optional short note) or pause status (paused: 'quota' | 'error') to the live Orchestrator panel.",
          options: { codemode: false },
          input: STEP_INPUT_SCHEMA,
          execute: async (args, toolCtx) => {
            const now = Date.now();
            const caller = await resolveToolCaller(toolCtx);
            const rootID = caller.rootID;
            let flow =
              caller.callerID && rootID
                ? (flowsByRoot.get(rootID) ?? null)
                : null;

            if (flow && caller.known && caller.meta?.parentID) {
              flow = ensureWorkerRun(flow, caller.meta, now);
            }

            const { flow: nextFlow, summary } = applyStepCall(
              flow,
              caller.callerID,
              args || {},
              now,
            );
            if (nextFlow && caller.callerID && rootID) {
              persistFlow(rootID, nextFlow);
              await deliverPendingWakes(rootID);
            }
            return { content: summary };
          },
        });

        registry.add({
          name: "post",
          description:
            "Post a message to the shared Orchestrator board (results, defect lists, questions, or notes). Supports @name, @all, and @lead mentions.",
          options: { codemode: false },
          input: POST_INPUT_SCHEMA,
          execute: async (args, toolCtx) => {
            const now = Date.now();
            const caller = await resolveToolCaller(toolCtx);
            const rootID = caller.rootID;
            let flow = rootID ? (flowsByRoot.get(rootID) ?? null) : null;

            if (flow && caller.known && caller.meta?.parentID) {
              flow = ensureWorkerRun(flow, caller.meta, now);
            }

            const postRunId = caller.isHelper
              ? caller.known && caller.callerID
                ? caller.callerID
                : "_unknown"
              : undefined;
            const postAgent = caller.isHelper
              ? caller.callerAgent || "helper"
              : "lead";
            const { flow: nextFlow, seq } = applyPostCall(
              flow,
              postRunId,
              postAgent,
              args || {},
              now,
            );
            if (nextFlow && rootID) {
              persistFlow(rootID, nextFlow);
              await deliverPendingWakes(rootID);
            }
            return { content: JSON.stringify({ seq }) };
          },
        });

        registry.add({
          name: "board",
          description:
            "Read posts from the shared Orchestrator board with optional recipient, author, kind, substring, and limit filters.",
          options: { codemode: false },
          input: BOARD_INPUT_SCHEMA,
          execute: async (args, toolCtx) => {
            const caller = await resolveToolCaller(toolCtx);
            const flow = caller.rootID
              ? (flowsByRoot.get(caller.rootID) ?? null)
              : null;
            const rows = applyBoardCall(
              flow,
              caller.callerAgent,
              caller.isHelper,
              args || {},
            );
            return { content: JSON.stringify(rows) };
          },
        });
      });
    }

    // 2. Subscribe to OpenCode server events for subagent & token tracking
    if (ctx?.event?.subscribe) {
      const controller = new AbortController();
      (async () => {
        try {
          for await (const event of ctx.event.subscribe({
            signal: controller.signal,
          })) {
            const type = event?.type;
            const data = event?.data ?? event?.properties ?? {};
            const now = Date.now();

            if (type === "session.created") {
              const sessionID = data.sessionID ?? data.info?.id;
              const parentID = data.parentID ?? data.info?.parentID;
              const title = data.title ?? data.info?.title;
              const agent = data.agent ?? data.info?.agent;
              const modelRef = data.model ?? data.info?.model;
              const meta = upsertSessionMeta(sessionID, {
                parentID,
                title,
                agent,
                modelRef,
                verified: true,
              });
              if (!meta) continue;
              if (parentID) {
                const parentMeta = await resolveSessionMeta(parentID);
                meta.rootID = parentMeta?.rootID || parentID;
                sessionMeta.set(meta.id, meta);
                const flow = flowsByRoot.get(meta.rootID);
                if (flow) {
                  const nextFlow = ensureWorkerRun(flow, meta, now);
                  persistFlow(meta.rootID, nextFlow);
                }
              }
            } else if (
              type === "session.model.selected" ||
              type === "session.agent.selected" ||
              type === "session.renamed"
            ) {
              const sessionID = data.sessionID;
              if (sessionID) {
                upsertSessionMeta(sessionID, {
                  title: data.title,
                  agent: data.agent,
                  modelRef: data.model,
                });
              }
            } else if (type === "session.step.started") {
              const sessionID = data.sessionID;
              if (!sessionID) continue;
              const existingMeta = await resolveSessionMeta(sessionID);
              if (!existingMeta) continue;
              const meta = upsertSessionMeta(sessionID, {
                parentID: existingMeta.parentID,
                title: existingMeta.title,
                agent: data.agent ?? existingMeta.agent,
                modelRef: data.model ?? existingMeta.model,
                verified: true,
              });
              if (!meta) continue;
              meta.rootID = existingMeta.rootID;
              const flow = flowsByRoot.get(meta.rootID);
              if (flow) {
                const nextFlow = meta.parentID
                  ? ensureWorkerRun(flow, meta, data.started || now)
                  : ensureLeadRun(flow, meta.rootID, meta, data.started || now);
                persistFlow(meta.rootID, nextFlow);
              }
            } else if (type === "session.step.ended") {
              const sessionID = data.sessionID;
              if (!sessionID) continue;
              const tokens = recordStepTokens(
                sessionID,
                data.assistantMessageID,
                data.tokens,
              );
              const meta = await resolveSessionMeta(sessionID);
              if (!meta) continue;
              let flow = flowsByRoot.get(meta.rootID);
              if (flow) {
                flow = meta.parentID
                  ? ensureWorkerRun(flow, meta, now)
                  : ensureLeadRun(flow, meta.rootID, meta, now);
                const runId = meta.parentID ? sessionID : `lead:${meta.rootID}`;
                flow = reduce(flow, {
                  type: "run.progress",
                  at: now,
                  id: runId,
                  tokens,
                });
                persistFlow(meta.rootID, flow);
              }
            } else if (
              type === "session.usage.updated" ||
              type === "session.usage.recorded"
            ) {
              const sessionID = data.sessionID;
              if (!sessionID) continue;
              const tokens = recordUsageTokens(sessionID, data.tokens);
              const meta = await resolveSessionMeta(sessionID);
              if (!meta) continue;
              let flow = flowsByRoot.get(meta.rootID);
              if (flow) {
                flow = meta.parentID
                  ? ensureWorkerRun(flow, meta, now)
                  : ensureLeadRun(flow, meta.rootID, meta, now);
                const runId = meta.parentID ? sessionID : `lead:${meta.rootID}`;
                flow = reduce(flow, {
                  type: "run.progress",
                  at: now,
                  id: runId,
                  tokens,
                });
                persistFlow(meta.rootID, flow);
              }
            } else if (
              type === "session.execution.succeeded" ||
              type === "session.idle"
            ) {
              const sessionID = data.sessionID;
              if (!sessionID) continue;
              const meta = await resolveSessionMeta(sessionID);
              if (meta?.parentID) {
                let flow = flowsByRoot.get(meta.rootID);
                if (flow) {
                  flow = ensureWorkerRun(flow, meta, now);
                  flow = reduce(flow, {
                    type: "run.end",
                    at: now,
                    id: sessionID,
                    status: "done",
                    tokens: getSessionTokens(sessionID),
                  });
                  persistFlow(meta.rootID, flow);
                  await deliverPendingWakes(meta.rootID);
                }
              }
            } else if (
              type === "session.execution.failed" ||
              type === "session.step.failed" ||
              type === "session.error"
            ) {
              const sessionID = data.sessionID;
              if (!sessionID) continue;
              const meta = await resolveSessionMeta(sessionID);
              if (meta?.parentID) {
                let flow = flowsByRoot.get(meta.rootID);
                if (flow) {
                  flow = ensureWorkerRun(flow, meta, now);
                  flow = reduce(flow, {
                    type: "run.end",
                    at: now,
                    id: sessionID,
                    status: "error",
                    tokens: getSessionTokens(sessionID),
                  });
                  persistFlow(meta.rootID, flow);
                  await deliverPendingWakes(meta.rootID);
                }
              }
            }
          }
        } catch {
          // Stream closed on shutdown
        }
      })();
    }

    for (const rootID of flowsByRoot.keys()) {
      await deliverPendingWakes(rootID);
    }
  },
};
