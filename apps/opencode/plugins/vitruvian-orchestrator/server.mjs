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
  applyProgressCall,
  applyStepCall,
  mapOpenCodeTokens,
  mergeTokenSnapshots,
  parseModelAndEffort,
  reduce,
} from "./lib/adapter.mjs";

export const PLUGIN_ID = "vitruvian-orchestrator";

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
      type: "array",
      items: { type: "number" },
      description: "1-based task numbers accepted after adversarial review.",
    },
    return: {
      type: "array",
      items: { type: "number" },
      description: "1-based task numbers returned for rework.",
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
  },
  required: ["done", "total"],
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
      if (!rootID || !flow) return;
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
      if (!sessionID) {
        return {
          id: "default",
          rootID: "default",
          model: "unknown",
          effort: /** @type {const} */ ("high"),
        };
      }
      const prev = sessionMeta.get(sessionID);
      const parentID = patch.parentID ?? prev?.parentID ?? undefined;
      let rootID = parentID
        ? sessionMeta.get(parentID)?.rootID || parentID
        : sessionID;
      const parsedModel =
        patch.modelRef !== undefined
          ? parseModelAndEffort(patch.modelRef, patch.effortHint)
          : {
              model: prev?.model || "unknown",
              effort: prev?.effort || /** @type {const} */ ("high"),
            };

      const next = {
        id: sessionID,
        ...(parentID ? { parentID } : {}),
        rootID,
        title: patch.title ?? prev?.title,
        agent: patch.agent ?? prev?.agent,
        model:
          parsedModel.model !== "unknown"
            ? parsedModel.model
            : prev?.model || "unknown",
        effort: parsedModel.effort || prev?.effort || "high",
      };
      sessionMeta.set(sessionID, next);
      return next;
    }

    async function resolveSessionMeta(sessionID) {
      if (!sessionID) {
        return upsertSessionMeta("default");
      }
      const cached = sessionMeta.get(sessionID);
      if (
        cached &&
        (cached.parentID !== undefined || cached.model !== "unknown")
      ) {
        if (cached.parentID && sessionMeta.has(cached.parentID)) {
          cached.rootID = sessionMeta.get(cached.parentID).rootID;
        }
        return cached;
      }
      if (ctx?.session?.get) {
        try {
          const info = await ctx.session.get({ sessionID });
          if (info && typeof info === "object") {
            let rootID = info.parentID || sessionID;
            if (info.parentID) {
              const parentMeta = await resolveSessionMeta(info.parentID);
              rootID = parentMeta.rootID || info.parentID;
            }
            const meta = upsertSessionMeta(sessionID, {
              parentID: info.parentID,
              title: info.title,
              agent: info.agent,
              modelRef: info.model,
            });
            meta.rootID = rootID;
            sessionMeta.set(sessionID, meta);
            return meta;
          }
        } catch {
          // Fall back to cached or default metadata
        }
      }
      return upsertSessionMeta(sessionID);
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

    // 1. Register `progress` and `step` tools
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
            const callerSessionID = toolCtx?.sessionID || "default";
            const meta = await resolveSessionMeta(callerSessionID);
            if (toolCtx?.agent && !meta.agent) {
              meta.agent = toolCtx.agent;
            }
            const rootID = meta.rootID || callerSessionID;
            const prevFlow = flowsByRoot.get(rootID) ?? null;

            const { flow: updatedFlow, summary } = applyProgressCall(
              prevFlow,
              args || {},
              now,
            );
            let nextFlow = ensureLeadRun(updatedFlow, rootID, meta, now);
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
            return { content: summary };
          },
        });

        registry.add({
          name: "step",
          description:
            "Report subagent step progress (done of total, plus optional short note) to the live Orchestrator panel.",
          options: { codemode: false },
          input: STEP_INPUT_SCHEMA,
          execute: async (args, toolCtx) => {
            const now = Date.now();
            const callerSessionID = toolCtx?.sessionID || "default";
            const meta = await resolveSessionMeta(callerSessionID);
            if (toolCtx?.agent && !meta.agent) {
              meta.agent = toolCtx.agent;
            }
            const rootID = meta.rootID || callerSessionID;
            let flow = flowsByRoot.get(rootID) ?? null;

            if (flow && meta.parentID) {
              flow = ensureWorkerRun(flow, meta, now);
            }

            const { flow: nextFlow, summary } = applyStepCall(
              flow,
              callerSessionID,
              args || {},
              now,
            );
            if (nextFlow) {
              persistFlow(rootID, nextFlow);
            }
            return { content: summary };
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
              });
              if (parentID) {
                const parentMeta = await resolveSessionMeta(parentID);
                meta.rootID = parentMeta.rootID || parentID;
                sessionMeta.set(sessionID, meta);
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
              const meta = upsertSessionMeta(sessionID, {
                parentID: existingMeta.parentID,
                title: existingMeta.title,
                agent: data.agent ?? existingMeta.agent,
                modelRef: data.model ?? existingMeta.model,
              });
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
              if (meta.parentID) {
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
              if (meta.parentID) {
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
                }
              }
            }
          }
        } catch {
          // Stream closed on shutdown
        }
      })();
    }
  },
};
