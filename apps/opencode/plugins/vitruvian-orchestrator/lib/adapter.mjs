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

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  agentRoleMap,
  applyAgentModels,
  board,
  burnDown,
  channels,
  DEFAULT_QUIET_MS,
  DEFAULT_ROLE_TIERS,
  DEFAULT_STALL_MS,
  delegateCost,
  flowAgentRoleMap,
  formatAgentRoleLabel,
  formatLeadWakes,
  formatWake,
  initialFlow,
  isValidAgentName,
  isValidWorktree,
  MAX_AGENT_FILE_BYTES,
  MAX_TEAM_FILE_BYTES,
  MAX_TEAM_ROLES,
  members,
  mentionGraph,
  mentions,
  overview,
  parseTeam,
  pendingWakes,
  planTeamSync,
  reduce,
  remaining,
  renderStarterTeam,
  resolveTeam,
  ROLES,
  runCost,
  sanitizeDisplayText,
  spend,
  stalls,
  starterAgentFile,
  taskBoard,
  TEAM_AGENT_DIRS,
  TEAM_SYNC_HARNESSES,
  validateChannelAction,
  validatePostChannel,
  validateStarterAgents,
  validateTeamEvent,
} from "./orchestrator-core.mjs";
import { TIER_DEFAULTS } from "./tier-defaults.mjs";

export {
  agentRoleMap,
  applyAgentModels,
  board,
  burnDown,
  channels,
  DEFAULT_QUIET_MS,
  DEFAULT_ROLE_TIERS,
  DEFAULT_STALL_MS,
  delegateCost,
  flowAgentRoleMap,
  formatAgentRoleLabel,
  formatLeadWakes,
  formatWake,
  initialFlow,
  isValidAgentName,
  isValidWorktree,
  MAX_AGENT_FILE_BYTES,
  MAX_TEAM_FILE_BYTES,
  MAX_TEAM_ROLES,
  members,
  mentionGraph,
  mentions,
  overview,
  parseTeam,
  pendingWakes,
  planTeamSync,
  reduce,
  remaining,
  renderStarterTeam,
  resolveTeam,
  ROLES,
  runCost,
  sanitizeDisplayText,
  spend,
  stalls,
  starterAgentFile,
  taskBoard,
  TEAM_AGENT_DIRS,
  TEAM_SYNC_HARNESSES,
  validateChannelAction,
  validatePostChannel,
  validateStarterAgents,
  validateTeamEvent,
};

const VALID_HANDLE_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;

function sanitizeShortField(raw, maxLen = 500) {
  return sanitizeDisplayText(String(raw ?? "").slice(0, 8000))
    .replace(/[\r\n\t]+/g, " ")
    .trim()
    .slice(0, maxLen);
}

export const PHASES = Object.freeze([
  "plan",
  "design",
  "delegate",
  "review",
  "close",
]);

export const EMPTY_PANEL_MESSAGE =
  "Orchestrator panel fills in when the lead skill reports a plan.";

const VALID_EFFORTS = new Set(["medium", "high", "xhigh", "max"]);
const SPARK_CHARS = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"];

/**
 * Semantic color key per panel-spec.md:
 * - accepted / done -> green ("success")
 * - running -> blue ("info")
 * - review / waiting -> amber ("warning")
 * - returned / error -> red ("error")
 * - ready -> neutral ("muted")
 *
 * @param {string} stateOrStatus
 * @returns {"success" | "info" | "warning" | "error" | "muted"}
 */
export function statusColorToken(stateOrStatus) {
  switch (stateOrStatus) {
    case "accepted":
    case "done":
      return "success";
    case "running":
      return "info";
    case "review":
    case "waiting":
      return "warning";
    case "returned":
    case "error":
      return "error";
    case "ready":
    default:
      return "muted";
  }
}

/**
 * Normalize model and effort from OpenCode session/step metadata.
 * Enforces the medium effort floor per orchestrate skill contract.
 *
 * @param {unknown} modelRef
 * @param {string} [effortHint]
 * @returns {{ model: string, effort: "medium" | "high" | "xhigh" | "max" }}
 */
export function parseModelAndEffort(modelRef, effortHint) {
  let model = "unknown";
  let rawEffort = effortHint ?? "";

  if (typeof modelRef === "string" && modelRef.trim().length > 0) {
    const [base, hashVariant] = modelRef.trim().split("#");
    model = base || "unknown";
    if (!rawEffort && hashVariant) rawEffort = hashVariant;
  } else if (modelRef && typeof modelRef === "object") {
    const obj = /** @type {Record<string, unknown>} */ (modelRef);
    const id =
      typeof obj.id === "string"
        ? obj.id
        : typeof obj.modelID === "string"
          ? obj.modelID
          : "";
    const provider = typeof obj.providerID === "string" ? obj.providerID : "";
    if (id) {
      model = provider && !id.includes("/") ? `${provider}/${id}` : id;
    }
    if (!rawEffort) {
      if (typeof obj.effort === "string") rawEffort = obj.effort;
      else if (typeof obj.variant === "string") rawEffort = obj.variant;
    }
  }

  const normalizedEffort = String(rawEffort || "high")
    .toLowerCase()
    .trim();
  const effort = VALID_EFFORTS.has(normalizedEffort)
    ? /** @type {"medium" | "high" | "xhigh" | "max"} */ (normalizedEffort)
    : "medium";

  return { model, effort };
}

/**
 * Strip provider prefix for compact sidebar display while keeping model family clear.
 *
 * @param {string} model
 * @returns {string}
 */
export function shortModelName(model) {
  const clean = sanitizeShortField(model, 256);
  if (!clean) return "unknown";
  return clean.replace(/^[^/]+\//, "");
}

/**
 * Convert OpenCode TokenUsage.Info ({ input, output, reasoning, cache: { read, write } })
 * to orchestrator-core TokenCounts ({ input, output, cacheRead, cacheWrite }).
 *
 * @param {unknown} raw
 * @returns {{ input: number, output: number, cacheRead: number, cacheWrite: number }}
 */
export function mapOpenCodeTokens(raw) {
  if (!raw || typeof raw !== "object") {
    return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
  }
  const t = /** @type {Record<string, unknown>} */ (raw);
  const cache =
    t.cache && typeof t.cache === "object"
      ? /** @type {Record<string, unknown>} */ (t.cache)
      : {};
  const input = Number(t.input) || 0;
  const output = (Number(t.output) || 0) + (Number(t.reasoning) || 0);
  const cacheRead = Number(t.cacheRead ?? cache.read) || 0;
  const cacheWrite = Number(t.cacheWrite ?? cache.write) || 0;
  return {
    input: Math.max(0, input),
    output: Math.max(0, output),
    cacheRead: Math.max(0, cacheRead),
    cacheWrite: Math.max(0, cacheWrite),
  };
}

/**
 * Combine per-message step token snapshots and session-level usage snapshot
 * without double counting.
 *
 * @param {Map<string, { input: number, output: number, cacheRead: number, cacheWrite: number }>} stepMap
 * @param {{ input: number, output: number, cacheRead: number, cacheWrite: number } | null} [usageSnapshot]
 * @returns {{ input: number, output: number, cacheRead: number, cacheWrite: number }}
 */
export function mergeTokenSnapshots(stepMap, usageSnapshot = null) {
  let input = 0;
  let output = 0;
  let cacheRead = 0;
  let cacheWrite = 0;
  if (stepMap) {
    for (const entry of stepMap.values()) {
      input += entry.input || 0;
      output += entry.output || 0;
      cacheRead += entry.cacheRead || 0;
      cacheWrite += entry.cacheWrite || 0;
    }
  }
  if (usageSnapshot) {
    input = Math.max(input, usageSnapshot.input || 0);
    output = Math.max(output, usageSnapshot.output || 0);
    cacheRead = Math.max(cacheRead, usageSnapshot.cacheRead || 0);
    cacheWrite = Math.max(cacheWrite, usageSnapshot.cacheWrite || 0);
  }
  return { input, output, cacheRead, cacheWrite };
}

/**
 * Parse a 1-based task number from a number or string like "1" or "#1".
 *
 * @param {unknown} raw
 * @returns {number}
 */
function toTaskNumber(raw) {
  if (typeof raw === "number") return Math.trunc(raw);
  if (typeof raw === "string") {
    const cleaned = raw.trim().replace(/^#/, "");
    return Number.parseInt(cleaned, 10);
  }
  if (raw && typeof raw === "object") {
    const obj = /** @type {Record<string, unknown>} */ (raw);
    return toTaskNumber(obj.n ?? obj.id);
  }
  return Number.NaN;
}

/**
 * Map a single `progress` tool call input to an ordered list of core events
 * per panel-spec.md:
 *   1. tasks -> plan
 *   2. phase -> phase
 *   3. accept -> task.accept (per n)
 *   4. return -> task.return (per n)
 *   5. finished: true -> close
 *
 * @param {Record<string, unknown>} input
 * @param {number} at
 * @param {import('./orchestrator-core.mjs').Flow | null} [currentFlow]
 * @returns {import('./orchestrator-core.mjs').FlowEvent[]}
 */
export function mapProgressInputToEvents(input, at, currentFlow = null) {
  if (!input || typeof input !== "object") {
    throw new Error("progress input must be an object");
  }
  /** @type {import('./orchestrator-core.mjs').FlowEvent[]} */
  const events = [];

  const title =
    typeof input.title === "string" && input.title.trim().length > 0
      ? input.title.trim()
      : currentFlow?.title || "Orchestrator flow";

  if (Array.isArray(input.tasks)) {
    events.push({
      type: "plan",
      at,
      title,
      tasks: input.tasks.map((t) => ({
        title: String(t.title ?? ""),
        specialist: String(t.specialist ?? "self"),
        tier: /** @type {import('./orchestrator-core.mjs').Tier} */ (
          t.tier || "core"
        ),
        after: Array.isArray(t.after)
          ? t.after.map(toTaskNumber).filter((n) => Number.isFinite(n))
          : [],
        ...(t.model !== undefined && t.model !== null
          ? { model: t.model }
          : {}),
        ...(t.worktree !== undefined && t.worktree !== null
          ? { worktree: t.worktree }
          : {}),
      })),
    });
  } else if (!currentFlow) {
    // Ensure a flow exists if the first progress call sets phase/title before tasks.
    events.push({
      type: "plan",
      at,
      title,
      tasks: [],
    });
  }

  if (typeof input.phase === "string" && input.phase.length > 0) {
    events.push({
      type: "phase",
      at,
      phase: /** @type {import('./orchestrator-core.mjs').Phase} */ (
        input.phase
      ),
    });
  }

  if (input.accept !== undefined && input.accept !== null) {
    const items = Array.isArray(input.accept) ? input.accept : [input.accept];
    for (const rawN of items) {
      const n = toTaskNumber(rawN);
      if (Number.isFinite(n)) {
        events.push({
          type: "task.accept",
          at,
          n,
        });
      }
    }
  }

  if (input.return !== undefined && input.return !== null) {
    const items = Array.isArray(input.return) ? input.return : [input.return];
    for (const item of items) {
      const n = toTaskNumber(item);
      if (Number.isFinite(n)) {
        events.push({
          type: "task.return",
          at,
          n,
        });
      }
    }
  }

  if (typeof input.retire === "string" && input.retire.trim().length > 0) {
    events.push({
      type: "member.retire",
      at,
      id: resolveMemberRunId(currentFlow, input.retire),
    });
  }

  if (typeof input.kill === "string" && input.kill.trim().length > 0) {
    events.push({
      type: "member.kill",
      at,
      id: resolveMemberRunId(currentFlow, input.kill),
    });
  }

  if (input.finished === true) {
    events.push({
      type: "close",
      at,
    });
  }

  return events;
}

function resolveMemberRunId(flow, rawRef) {
  const ref = String(rawRef ?? "").trim();
  if (!ref) return ref;
  const norm = ref.replace(/^@+/, "").toLowerCase();
  if (norm === "lead") {
    throw new Error("progress retire/kill cannot target lead");
  }
  if (!flow || !Array.isArray(flow.runs)) return ref;
  const exact = flow.runs.find((r) => r.id === ref);
  if (exact) {
    if (exact.role === "lead") {
      throw new Error("progress retire/kill cannot target lead");
    }
    return exact.id;
  }
  const activeByAgent = flow.runs.findLast(
    (r) =>
      r.role !== "lead" &&
      String(r.agent ?? "")
        .trim()
        .toLowerCase() === norm &&
      r.memberState !== "killed" &&
      r.memberState !== "retired",
  );
  if (activeByAgent) return activeByAgent.id;
  const anyByAgent = flow.runs.findLast(
    (r) =>
      r.role !== "lead" &&
      String(r.agent ?? "")
        .trim()
        .toLowerCase() === norm,
  );
  return anyByAgent ? anyByAgent.id : ref;
}

/**
 * Apply a `progress` tool call to `flow` via `reduce`.
 *
 * @param {import('./orchestrator-core.mjs').Flow | null} flow
 * @param {Record<string, unknown>} input
 * @param {number} [at]
 * @returns {{ flow: import('./orchestrator-core.mjs').Flow, events: import('./orchestrator-core.mjs').FlowEvent[], summary: string }}
 */
export function applyProgressCall(flow, input, at = Date.now()) {
  const events = mapProgressInputToEvents(input, at, flow);
  let next = flow ?? initialFlow();
  for (const ev of events) {
    next = reduce(next, ev);
  }
  if (
    next &&
    typeof input?.title === "string" &&
    input.title.trim().length > 0 &&
    !Array.isArray(input.tasks)
  ) {
    next = { ...next, title: sanitizeShortField(input.title, 500) };
  }
  const remCount = remaining(next);
  const totalCount = next ? next.tasks.length : 0;
  const acceptedCount = Math.max(0, totalCount - remCount);
  const summary = `flow updated: ${acceptedCount}/${totalCount} accepted (phase: ${next?.phase ?? "plan"})`;
  return {
    flow: /** @type {import('./orchestrator-core.mjs').Flow} */ (next),
    events,
    summary,
  };
}

/**
 * Apply a `step` tool call from a subagent run to `flow`.
 * Never throws when the caller is not a tracked worker run; returns matched=false.
 *
 * @param {import('./orchestrator-core.mjs').Flow | null} flow
 * @param {string | undefined} callerRunId
 * @param {Record<string, unknown>} input
 * @param {number} [at]
 * @returns {{ flow: import('./orchestrator-core.mjs').Flow | null, matched: boolean, runId: string | null, summary: string }}
 */
export function applyStepCall(flow, callerRunId, input, at = Date.now()) {
  const hasDone = input?.done !== undefined && input?.done !== null;
  const hasTotal = input?.total !== undefined && input?.total !== null;
  const done = Number(input?.done);
  const total = Number(input?.total);
  const note =
    typeof input?.note === "string" && input.note.trim().length > 0
      ? input.note.trim()
      : "";
  const delegate =
    typeof input?.delegate === "string" && input.delegate.trim().length > 0
      ? input.delegate.trim()
      : undefined;
  const rawPaused =
    typeof input?.paused === "string" ? input.paused.trim() : input?.paused;
  const hasPaused =
    rawPaused !== undefined && rawPaused !== null && rawPaused !== "";
  const detail =
    typeof input?.detail === "string" && input.detail.trim().length > 0
      ? input.detail.trim()
      : undefined;

  const rawWt =
    typeof input?.worktree === "string" ? input.worktree.trim() : "";
  const validWt = isValidWorktree(rawWt) ? rawWt : undefined;
  const hasOtherField =
    hasPaused ||
    validWt !== undefined ||
    delegate !== undefined ||
    input?.delegateUsage !== undefined;

  if (hasPaused && rawPaused !== "quota" && rawPaused !== "error") {
    throw new Error(
      `step paused must be "quota" or "error" (got paused=${JSON.stringify(input?.paused)})`,
    );
  }

  if (hasDone || hasTotal) {
    if (
      !Number.isInteger(done) ||
      !Number.isInteger(total) ||
      total < 1 ||
      done < 0 ||
      done > total
    ) {
      throw new Error(
        `step requires integers 0 <= done <= total and total >= 1 (got done=${input?.done}, total=${input?.total})`,
      );
    }
  } else if (!hasOtherField) {
    throw new Error(
      "step requires integers 0 <= done <= total and total >= 1, paused ('quota' | 'error'), or a valid worktree",
    );
  }

  const label =
    hasDone && hasTotal
      ? `${done}/${total}`
      : hasPaused
        ? `paused: ${rawPaused}`
        : validWt
          ? `worktree: ${validWt}`
          : `delegate: ${delegate || "usage"}`;

  if (!flow) {
    return {
      flow: null,
      matched: false,
      runId: null,
      summary: `step recorded (${label}) — no active orchestrator flow yet`,
    };
  }

  let targetRun = callerRunId
    ? flow.runs.find((r) => r.id === callerRunId)
    : undefined;

  if (!targetRun) {
    const runningWorkers = flow.runs.filter(
      (r) => r.role === "worker" && r.status === "running",
    );
    if (runningWorkers.length === 1) {
      targetRun = runningWorkers[0];
    }
  }

  if (!targetRun) {
    return {
      flow,
      matched: false,
      runId: null,
      summary: `step ignored (${label}): caller session is not a tracked worker run`,
    };
  }

  let next = flow;
  if (
    (hasDone && hasTotal) ||
    delegate !== undefined ||
    input?.delegateUsage !== undefined ||
    validWt !== undefined
  ) {
    next = reduce(next, {
      type: "run.progress",
      at,
      id: targetRun.id,
      ...(hasDone && hasTotal
        ? {
            steps: {
              done,
              total,
              note,
            },
          }
        : {}),
      ...(delegate ? { delegate } : {}),
      ...(input?.delegateUsage !== undefined
        ? {
            delegateTokens:
              /** @type {Partial<import('./orchestrator-core.mjs').DelegateTokenCounts> | null} */ (
                input.delegateUsage
              ),
          }
        : {}),
      ...(validWt ? { worktree: validWt } : {}),
    });
  }

  if (hasPaused) {
    next = reduce(next, {
      type: "member.pause",
      at,
      id: targetRun.id,
      reason: /** @type {"quota" | "error"} */ (rawPaused),
      ...(detail ? { detail } : {}),
    });
  }

  return {
    flow: next,
    matched: true,
    runId: targetRun.id,
    summary:
      hasDone && hasTotal
        ? `step updated: ${done}/${total}${note ? ` (${note})` : ""}${hasPaused ? ` [${label}]` : ""}`
        : hasPaused
          ? `member paused: ${rawPaused}${detail ? ` (${detail})` : ""}`
          : `step updated: ${label}${note ? ` (${note})` : ""}`,
  };
}

/**
 * Apply a `post` tool call to `flow` via `reduce`.
 *
 * @param {import('./orchestrator-core.mjs').Flow | null} flow
 * @param {string | undefined} callerRunId
 * @param {string | undefined} callerAgent
 * @param {Record<string, unknown>} input
 * @param {number} [at]
 * @returns {{ flow: import('./orchestrator-core.mjs').Flow | null, seq: number }}
 */
export function applyPostCall(
  flow,
  callerRunId,
  callerAgent,
  input,
  at = Date.now(),
) {
  if (typeof input?.text !== "string") {
    throw new Error("post requires string text");
  }
  const chCheck = validatePostChannel(flow, input.channel);
  if (!chCheck.ok) {
    throw new Error(chCheck.error);
  }
  if (!input.text.trim()) {
    return { flow, seq: 0 };
  }

  const baseFlow =
    flow ??
    reduce(initialFlow(), {
      type: "plan",
      at,
      title: "Orchestrator flow",
      tasks: [],
    });

  const matchedRun = callerRunId
    ? baseFlow.runs.find((r) => r.role !== "lead" && r.id === callerRunId)
    : undefined;
  const rawAgent = String(matchedRun?.agent || callerAgent || "")
    .trim()
    .replace(/^@+/, "")
    .toLowerCase();
  const isHelper = Boolean(callerRunId);
  const from = isHelper
    ? rawAgent && rawAgent !== "lead" && VALID_HANDLE_RE.test(rawAgent)
      ? rawAgent
      : "helper"
    : !rawAgent || rawAgent === "lead"
      ? "lead"
      : VALID_HANDLE_RE.test(rawAgent)
        ? rawAgent
        : "helper";
  const prevPosts = Array.isArray(baseFlow.posts) ? baseFlow.posts : [];
  const prevLastSeq =
    prevPosts.length > 0 ? prevPosts[prevPosts.length - 1].seq : 0;

  const next = reduce(baseFlow, {
    type: "post",
    at,
    from,
    text: input.text,
    ...(Array.isArray(input.to) ? { to: input.to.map(String) } : {}),
    ...(typeof input.kind === "string"
      ? {
          kind: /** @type {import('./orchestrator-core.mjs').PostKind} */ (
            input.kind
          ),
        }
      : {}),
    ...(Number.isInteger(input.replyTo) && Number(input.replyTo) >= 1
      ? { replyTo: Number(input.replyTo) }
      : {}),
    ...(chCheck.channel && chCheck.channel !== "main"
      ? { channel: chCheck.channel }
      : {}),
    ...(matchedRun && matchedRun.role !== "lead"
      ? { runId: matchedRun.id }
      : {}),
  });

  const posts = Array.isArray(next?.posts) ? next.posts : [];
  const lastSeq = posts.length > 0 ? posts[posts.length - 1].seq : 0;
  const seq = lastSeq > prevLastSeq ? lastSeq : 0;
  return { flow: next, seq };
}

/**
 * Apply a `channel` tool call (`create`, `archive`, or `list`).
 *
 * @param {import('./orchestrator-core.mjs').Flow | null} flow
 * @param {Record<string, unknown>} input
 * @param {number} [at]
 * @returns {{ flow: import('./orchestrator-core.mjs').Flow | null, channels: Array<{ name: string, archived: boolean }> }}
 */
export function applyChannelCall(flow, input, at = Date.now()) {
  const inp = input && typeof input === "object" ? input : {};
  const action =
    typeof inp.action === "string" ? inp.action.trim().toLowerCase() : "";
  if (action === "list") {
    return { flow, channels: channels(flow) };
  }
  const check = validateChannelAction(flow, { action, name: inp.name });
  if (!check.ok) {
    throw new Error(check.error);
  }
  if (check.noop) {
    return { flow, channels: check.channels ?? channels(flow) };
  }
  const baseFlow =
    flow ??
    reduce(initialFlow(), {
      type: "plan",
      at,
      title: "Orchestrator flow",
      tasks: [],
    });
  const next = reduce(baseFlow, {
    type: "channel",
    at,
    action: /** @type {"create" | "archive"} */ (action),
    name: check.name,
  });
  return { flow: next, channels: channels(next) };
}

/**
 * Query board posts for the `board` read tool, resolving caller identity for
 * OpenCode child sessions when `to` is `"me"` or omitted.
 *
 * @param {import('./orchestrator-core.mjs').Flow | null} flow
 * @param {string | undefined} callerAgent
 * @param {boolean} isChildSession
 * @param {Record<string, unknown>} [input]
 */
export function applyBoardCall(flow, callerAgent, isChildSession, input = {}) {
  const inp = input && typeof input === "object" ? input : {};
  const rawTo = typeof inp.to === "string" ? inp.to.trim() : "";
  const normTo = rawTo.replace(/^@+/, "").toLowerCase();
  const normCaller = String(callerAgent ?? "")
    .trim()
    .replace(/^@+/, "")
    .toLowerCase();
  const safeCaller =
    isChildSession && normCaller === "lead" ? "helper" : normCaller;

  let effectiveTo;
  if (normTo === "me") {
    effectiveTo = isChildSession ? safeCaller || undefined : "lead";
  } else if (rawTo.length > 0) {
    effectiveTo = rawTo;
  } else if (isChildSession && safeCaller) {
    effectiveTo = safeCaller;
  }

  const rawLimit =
    typeof inp.limit === "number" && Number.isFinite(inp.limit)
      ? Math.floor(inp.limit)
      : 20;
  const limit = Math.max(1, Math.min(100, rawLimit));

  return board(flow, {
    to: effectiveTo,
    from: typeof inp.from === "string" ? inp.from : undefined,
    kind:
      typeof inp.kind === "string"
        ? /** @type {import('./orchestrator-core.mjs').PostKind} */ (inp.kind)
        : undefined,
    channel: typeof inp.channel === "string" ? inp.channel : undefined,
    search: typeof inp.search === "string" ? inp.search : undefined,
    limit,
  }).map((p) => ({
    seq: p.seq,
    from: p.from,
    to: p.to,
    kind: p.kind,
    replyTo: p.replyTo,
    at: p.at,
    text: p.text,
    ...(p.channel && p.channel !== "main" ? { channel: p.channel } : {}),
  }));
}

/**
 * Render a compact text sparkline from burnDown(flow).points and replans.
 * Marks replan timestamps with ⟳.
 *
 * @param {Array<{ at: number, remaining: number, replanned?: boolean }>} points
 * @param {Array<{ at: number, total?: number }>} [replans]
 * @returns {string}
 */
export function sparkline(points, replans = []) {
  if (!Array.isArray(points) || points.length === 0) return "—";
  const replanTimes = new Set(
    Array.isArray(replans) ? replans.map((r) => r.at) : [],
  );
  const values = points.map((p) => Math.max(0, Number(p.remaining) || 0));
  const max = Math.max(...values, 1);
  let out = "";
  for (let i = 0; i < points.length; i++) {
    const val = values[i];
    const idx =
      val === 0
        ? 0
        : Math.min(
            SPARK_CHARS.length - 1,
            Math.max(1, Math.round((val / max) * (SPARK_CHARS.length - 1))),
          );
    out += SPARK_CHARS[idx];
    if (points[i].replanned || replanTimes.has(points[i].at)) {
      out += "⟳";
    }
  }
  if (replans.length > 0 && !out.includes("⟳")) {
    out += "⟳";
  }
  return out;
}

/**
 * Format token counts compactly (e.g. "1.2k", "45k", "820").
 *
 * @param {number} count
 * @returns {string}
 */
export function formatTokensCompact(count) {
  const n = Math.max(0, Math.round(Number(count) || 0));
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 10_000) return `${Math.round(n / 1_000)}k`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return `${n}`;
}

/**
 * Format USD value concisely.
 *
 * @param {number} usd
 * @returns {string}
 */
export function formatUsd(usd) {
  const n = Math.max(0, Number(usd) || 0);
  if (n === 0) return "$0.00";
  if (n < 0.01) return `<$0.01`;
  return `$${n.toFixed(2)}`;
}

/**
 * Format elapsed milliseconds as compact duration ("12s", "1m04s").
 *
 * @param {number} ms
 * @returns {string}
 */
export function formatDuration(ms) {
  const totalSec = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
  if (totalSec < 60) return `${totalSec}s`;
  const mins = Math.floor(totalSec / 60);
  const secs = totalSec % 60;
  return `${mins}m${String(secs).padStart(2, "0")}s`;
}

/**
 * Short 1-line title for `sidebar_title`.
 *
 * @param {import('./orchestrator-core.mjs').Flow | null} flow
 * @returns {string}
 */
export function formatSidebarTitle(flow) {
  if (!flow) return "Orchestrator";
  const remCount = remaining(flow);
  const totalCount = flow.tasks.length;
  const acceptedCount = Math.max(0, totalCount - remCount);
  const sp = spend(flow);
  return `Orchestrator · ${flow.phase} · ${acceptedCount}/${totalCount} · est. ${formatUsd(sp.total)}`;
}

function postKindColorToken(kind) {
  switch (kind) {
    case "question":
      return "warning";
    case "defect":
      return "error";
    case "result":
      return "success";
    default:
      return "muted";
  }
}

function clipSingleLine(text, maxLen = 72) {
  const clean = sanitizeShortField(text, 8000);
  if (clean.length <= maxLen) return clean;
  return `${clean.slice(0, maxLen - 1)}…`;
}

/**
 * Resolves the git repository top-level directory for `cwd`, falling back to
 * `cwd` when not inside a git worktree.
 *
 * @param {string} [cwd]
 * @returns {string}
 */
export function resolveRepoRoot(cwd = process.cwd()) {
  const safeCwd =
    typeof cwd === "string" && cwd.trim() ? cwd.trim() : process.cwd();
  try {
    const res = spawnSync(
      "git",
      ["-C", safeCwd, "rev-parse", "--show-toplevel"],
      { encoding: "utf8", timeout: 5000 },
    );
    if (
      res.status === 0 &&
      typeof res.stdout === "string" &&
      res.stdout.trim()
    ) {
      return res.stdout.trim();
    }
  } catch {
    // Fall back to cwd outside git repositories.
  }
  return safeCwd;
}

function isPathInsideRealRoot(realRoot, realTarget) {
  const rel = path.relative(realRoot, realTarget);
  return (
    rel.length > 0 &&
    rel !== ".." &&
    !rel.startsWith(`..${path.sep}`) &&
    !rel.startsWith("../") &&
    !rel.startsWith("..\\") &&
    !path.isAbsolute(rel)
  );
}

function resolveRealTeamPath(root) {
  let realRoot;
  try {
    realRoot = fs.realpathSync(root);
  } catch {
    realRoot = path.resolve(root);
  }
  const agentsDir = path.join(root, ".agents");
  const teamPath = path.join(agentsDir, "team.json");

  let linkStat;
  try {
    linkStat = fs.lstatSync(teamPath);
  } catch (err) {
    const code = err && typeof err === "object" ? err.code : undefined;
    if (code === "ENOENT" || code === "ENOTDIR") {
      try {
        const dirStat = fs.lstatSync(agentsDir);
        if (dirStat.isSymbolicLink()) {
          try {
            fs.realpathSync(agentsDir);
          } catch (dirErr) {
            const msg =
              dirErr instanceof Error ? dirErr.message : String(dirErr);
            return {
              status: "error",
              error: `.agents/team.json is a dangling symlink: ${msg}`,
            };
          }
        }
      } catch {
        // .agents directory does not exist; treat as absent.
      }
      return { status: "absent" };
    }
    const msg = err instanceof Error ? err.message : String(err);
    return {
      status: "error",
      error: `failed to read .agents/team.json: ${msg}`,
    };
  }

  let realTeamPath;
  try {
    realTeamPath = fs.realpathSync(teamPath);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (linkStat.isSymbolicLink()) {
      return {
        status: "error",
        error: `.agents/team.json is a dangling symlink: ${msg}`,
      };
    }
    return {
      status: "error",
      error: `failed to read .agents/team.json: ${msg}`,
    };
  }

  if (!isPathInsideRealRoot(realRoot, realTeamPath)) {
    return {
      status: "error",
      error: ".agents/team.json must be inside the repository",
    };
  }
  return { status: "ok", realPath: realTeamPath };
}

function loadTeamConfigAtRoot(root, defaults = TIER_DEFAULTS) {
  const checked = resolveRealTeamPath(root);
  if (checked.status === "absent") {
    const resolved = resolveTeam(null, "opencode", defaults);
    return {
      file: null,
      errors: [],
      notes: resolved.notes,
      roles: resolved.roles,
    };
  }
  if (checked.status === "error") {
    const resolved = resolveTeam(null, "opencode", defaults);
    return {
      file: ".agents/team.json",
      errors: [checked.error],
      notes: resolved.notes,
      roles: resolved.roles,
    };
  }

  let fd;
  try {
    fd = fs.openSync(checked.realPath, "r");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const resolved = resolveTeam(null, "opencode", defaults);
    return {
      file: ".agents/team.json",
      errors: [`failed to read .agents/team.json: ${msg}`],
      notes: resolved.notes,
      roles: resolved.roles,
    };
  }

  try {
    const st = fs.fstatSync(fd);
    if (!st.isFile()) {
      const resolved = resolveTeam(null, "opencode", defaults);
      return {
        file: ".agents/team.json",
        errors: [".agents/team.json is not a regular file"],
        notes: resolved.notes,
        roles: resolved.roles,
      };
    }
    if (st.size > MAX_TEAM_FILE_BYTES) {
      const resolved = resolveTeam(null, "opencode", defaults);
      return {
        file: ".agents/team.json",
        errors: [
          `.agents/team.json exceeds maximum size of ${MAX_TEAM_FILE_BYTES} bytes (64 KiB)`,
        ],
        notes: resolved.notes,
        roles: resolved.roles,
      };
    }
    const chunks = [];
    let totalBytes = 0;
    const buf = Buffer.allocUnsafe(8192);
    while (true) {
      const n = fs.readSync(fd, buf, 0, buf.length, null);
      if (n === 0) break;
      totalBytes += n;
      if (totalBytes > MAX_TEAM_FILE_BYTES) {
        const resolved = resolveTeam(null, "opencode", defaults);
        return {
          file: ".agents/team.json",
          errors: [
            `.agents/team.json exceeds maximum size of ${MAX_TEAM_FILE_BYTES} bytes (64 KiB)`,
          ],
          notes: resolved.notes,
          roles: resolved.roles,
        };
      }
      chunks.push(Buffer.from(buf.subarray(0, n)));
    }
    const text = Buffer.concat(chunks, totalBytes).toString("utf8");
    const parsed = parseTeam(text);
    const resolved = resolveTeam(parsed.team, "opencode", defaults);
    return {
      file: ".agents/team.json",
      errors: parsed.errors,
      notes: resolved.notes,
      roles: resolved.roles,
    };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const resolved = resolveTeam(null, "opencode", defaults);
    return {
      file: ".agents/team.json",
      errors: [`failed to read .agents/team.json: ${msg}`],
      notes: resolved.notes,
      roles: resolved.roles,
    };
  } finally {
    try {
      fs.closeSync(fd);
    } catch {
      // Ignore close error.
    }
  }
}

export const INVALID_ROOT_ERROR =
  "root must be an absolute path to a directory";

/**
 * Reads `<root>/.agents/team.json` (capped at 64 KiB) from an explicit
 * repository root directory without climbing git top-level, throwing
 * `INVALID_ROOT_ERROR` unless `root` is an absolute path to an existing directory.
 *
 * @param {unknown} root
 * @param {{ tiers?: Record<string, Record<string, unknown>> }} [defaults]
 */
export function loadTeamConfigForRoot(root, defaults = TIER_DEFAULTS) {
  if (typeof root !== "string" || !path.isAbsolute(root)) {
    throw new Error(INVALID_ROOT_ERROR);
  }
  let st;
  try {
    st = fs.statSync(root);
  } catch {
    throw new Error(INVALID_ROOT_ERROR);
  }
  if (!st.isDirectory()) {
    throw new Error(INVALID_ROOT_ERROR);
  }
  return loadTeamConfigAtRoot(root, defaults);
}

/**
 * Reads `<repo root>/.agents/team.json` (capped at 64 KiB), parses and
 * validates it, and resolves roles against OpenCode's tier defaults.
 *
 * @param {string} [cwd]
 * @param {{ tiers?: Record<string, Record<string, unknown>> }} [defaults]
 */
export function loadTeamConfig(cwd = process.cwd(), defaults = TIER_DEFAULTS) {
  return loadTeamConfigAtRoot(resolveRepoRoot(cwd), defaults);
}

const DEFAULT_PLUGIN_AGENTS_DIR = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "agents",
);

function inspectRepoPath(root, realRoot, segments) {
  let cur = root;
  const components = [];
  for (let i = 0; i < segments.length; i += 1) {
    cur = path.join(cur, segments[i]);
    const isLast = i === segments.length - 1;
    let lst;
    try {
      lst = fs.lstatSync(cur);
    } catch (err) {
      const code = err && typeof err === "object" ? err.code : undefined;
      if (code === "ENOENT") {
        return { status: "absent", existingComponents: components };
      }
      if (code === "ENOTDIR") {
        const parentLabel =
          i > 0 ? segments.slice(0, i).join("/") : segments[0];
        return {
          status: "error",
          reason: "parent-not-directory",
          error: `ENOTDIR: ${parentLabel} is not a directory`,
        };
      }
      const msg = err instanceof Error ? err.message : String(err);
      return { status: "error", reason: "stat-error", error: msg };
    }

    if (lst.isSymbolicLink()) {
      return {
        status: "symlink",
        reason: "symlink",
        error: `${segments.slice(0, i + 1).join("/")} is a symlink`,
      };
    }

    let realCur;
    try {
      realCur = fs.realpathSync(cur);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      return { status: "error", reason: "realpath-error", error: msg };
    }
    if (!isPathInsideRealRoot(realRoot, realCur)) {
      return {
        status: "outside-root",
        reason: "outside-root",
        error: `${segments.slice(0, i + 1).join("/")} resolves outside root`,
      };
    }

    components.push({
      path: cur,
      segment: segments[i],
      relPath: segments.slice(0, i + 1).join("/"),
      dev: lst.dev,
      ino: lst.ino,
      realPath: realCur,
    });

    if (!isLast) {
      if (!lst.isDirectory()) {
        return {
          status: "error",
          reason: "parent-not-directory",
          error: `${segments.slice(0, i + 1).join("/")} is not a directory`,
        };
      }
    } else {
      if (!lst.isFile()) {
        return {
          status: "not-a-file",
          reason: "not-a-file",
          error: `${segments.join("/")} is not a regular file`,
        };
      }
      if (lst.nlink > 1) {
        return {
          status: "hardlink",
          reason: "hardlink",
          error: `${segments.join("/")} is a hardlink`,
        };
      }
      return {
        status: "file",
        path: cur,
        realPath: realCur,
        size: lst.size,
        dev: lst.dev,
        ino: lst.ino,
        components,
      };
    }
  }
  return { status: "error", reason: "invalid-path", error: "empty path" };
}

function readBoundedFileNoFollow(filePath, maxBytes, label) {
  const noFollow = fs.constants?.O_NOFOLLOW ?? 0;
  let fd;
  try {
    fd = fs.openSync(filePath, fs.constants.O_RDONLY | noFollow);
  } catch (err) {
    const code = err && typeof err === "object" ? err.code : undefined;
    if (code === "ELOOP") {
      return { ok: false, reason: "symlink", error: `${label} is a symlink` };
    }
    const msg = err instanceof Error ? err.message : String(err);
    return {
      ok: false,
      reason: "read-error",
      error: `failed to read ${label}: ${msg}`,
    };
  }

  try {
    const st = fs.fstatSync(fd);
    if (!st.isFile()) {
      return {
        ok: false,
        reason: "not-a-file",
        error: `${label} is not a regular file`,
      };
    }
    if (st.nlink > 1) {
      return {
        ok: false,
        reason: "hardlink",
        error: `${label} is a hardlink`,
      };
    }
    if (st.size > maxBytes) {
      return {
        ok: false,
        reason: "too-large",
        error: `${label} exceeds maximum size of ${maxBytes} bytes`,
      };
    }
    const chunks = [];
    let totalBytes = 0;
    const buf = Buffer.allocUnsafe(8192);
    while (true) {
      const n = fs.readSync(fd, buf, 0, buf.length, null);
      if (n === 0) break;
      totalBytes += n;
      if (totalBytes > maxBytes) {
        return {
          ok: false,
          reason: "too-large",
          error: `${label} exceeds maximum size of ${maxBytes} bytes`,
        };
      }
      chunks.push(Buffer.from(buf.subarray(0, n)));
    }
    return {
      ok: true,
      text: Buffer.concat(chunks, totalBytes).toString("utf8"),
    };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return {
      ok: false,
      reason: "read-error",
      error: `failed to read ${label}: ${msg}`,
    };
  } finally {
    try {
      fs.closeSync(fd);
    } catch {
      // Ignore close error.
    }
  }
}

function verifyRootUnchanged(root, realRoot, rootSnap, realRootSnap) {
  try {
    const curRootLst = fs.lstatSync(root);
    if (curRootLst.dev !== rootSnap.dev || curRootLst.ino !== rootSnap.ino) {
      return false;
    }
    const curRealRoot = fs.realpathSync(root);
    if (curRealRoot !== realRoot) {
      return false;
    }
    const curRealRootLst = fs.lstatSync(realRoot);
    return (
      curRealRootLst.isDirectory() &&
      curRealRootLst.dev === realRootSnap.dev &&
      curRealRootLst.ino === realRootSnap.ino
    );
  } catch {
    return false;
  }
}

function recordInitDirSnapshot(expectedDirs, segments, existingComponents) {
  for (let i = 0; i < segments.length - 1; i += 1) {
    const relDir = segments.slice(0, i + 1).join("/");
    if (i < existingComponents.length) {
      const comp = existingComponents[i];
      const prev = expectedDirs.get(relDir);
      if (prev === null) {
        return {
          ok: false,
          error: `${relDir} changed before write (changed-during-sync)`,
        };
      }
      if (
        prev &&
        (prev.dev !== comp.dev ||
          prev.ino !== comp.ino ||
          prev.realPath !== comp.realPath)
      ) {
        return {
          ok: false,
          error: `${relDir} changed before write (changed-during-sync)`,
        };
      }
      if (!prev) {
        expectedDirs.set(relDir, {
          dev: comp.dev,
          ino: comp.ino,
          realPath: comp.realPath,
        });
      }
    } else {
      if (expectedDirs.has(relDir) && expectedDirs.get(relDir) !== null) {
        return {
          ok: false,
          error: `${relDir} changed before write (changed-during-sync)`,
        };
      }
      expectedDirs.set(relDir, null);
    }
  }
  return { ok: true };
}

function ensureDirInsideRootChecked(
  root,
  realRoot,
  rootSnap,
  realRootSnap,
  dirSegments,
  expectedDirs,
) {
  if (!verifyRootUnchanged(root, realRoot, rootSnap, realRootSnap)) {
    throw new Error("root changed before write (changed-during-sync)");
  }
  let cur = root;
  for (let i = 0; i < dirSegments.length; i += 1) {
    cur = path.join(cur, dirSegments[i]);
    const relDir = dirSegments.slice(0, i + 1).join("/");
    const expected = expectedDirs.get(relDir);
    let lst;
    try {
      lst = fs.lstatSync(cur);
    } catch (err) {
      const code = err && typeof err === "object" ? err.code : undefined;
      if (code === "ENOENT") {
        if (expected !== null && expected !== undefined) {
          throw new Error(
            `${relDir} disappeared before write (changed-during-sync)`,
          );
        }
        fs.mkdirSync(cur);
        lst = fs.lstatSync(cur);
        if (lst.isSymbolicLink()) {
          throw new Error(`${relDir} is a symlink (changed-during-sync)`);
        }
        if (!lst.isDirectory()) {
          throw new Error(`${relDir} is not a directory (changed-during-sync)`);
        }
        const createdRealCur = fs.realpathSync(cur);
        if (!isPathInsideRealRoot(realRoot, createdRealCur)) {
          throw new Error(
            `${relDir} resolves outside root (changed-during-sync)`,
          );
        }
        expectedDirs.set(relDir, {
          dev: lst.dev,
          ino: lst.ino,
          realPath: createdRealCur,
        });
        continue;
      }
      throw err;
    }
    if (lst.isSymbolicLink()) {
      throw new Error(`${relDir} is a symlink (changed-during-sync)`);
    }
    if (!lst.isDirectory()) {
      throw new Error(`${relDir} is not a directory (changed-during-sync)`);
    }
    const realCur = fs.realpathSync(cur);
    if (!isPathInsideRealRoot(realRoot, realCur)) {
      throw new Error(`${relDir} resolves outside root (changed-during-sync)`);
    }
    if (expected === null) {
      throw new Error(`${relDir} appeared before write (changed-during-sync)`);
    }
    if (
      expected &&
      (lst.dev !== expected.dev ||
        lst.ino !== expected.ino ||
        realCur !== expected.realPath)
    ) {
      throw new Error(`${relDir} changed before write (changed-during-sync)`);
    }
  }
}

function verifyCreatedFileUnchanged(
  root,
  realRoot,
  rootSnap,
  realRootSnap,
  expectedDirs,
  item,
) {
  if (!verifyRootUnchanged(root, realRoot, rootSnap, realRootSnap)) {
    return false;
  }
  let cur = root;
  for (let i = 0; i < item.segments.length - 1; i += 1) {
    cur = path.join(cur, item.segments[i]);
    const relDir = item.segments.slice(0, i + 1).join("/");
    const expected = expectedDirs.get(relDir);
    if (!expected) {
      return false;
    }
    try {
      const lst = fs.lstatSync(cur);
      if (
        lst.isSymbolicLink() ||
        !lst.isDirectory() ||
        lst.dev !== expected.dev ||
        lst.ino !== expected.ino
      ) {
        return false;
      }
      const realCur = fs.realpathSync(cur);
      if (
        realCur !== expected.realPath ||
        !isPathInsideRealRoot(realRoot, realCur)
      ) {
        return false;
      }
    } catch {
      return false;
    }
  }
  try {
    const fileLst = fs.lstatSync(item.path);
    if (
      fileLst.isSymbolicLink() ||
      !fileLst.isFile() ||
      fileLst.dev !== item.dev ||
      fileLst.ino !== item.ino
    ) {
      return false;
    }
    const realFile = fs.realpathSync(item.path);
    return isPathInsideRealRoot(realRoot, realFile);
  } catch {
    return false;
  }
}

function writeNewFileNoFollow(
  root,
  realRoot,
  rootSnap,
  realRootSnap,
  segments,
  text,
  expectedDirs,
  beforeWriteHook = null,
) {
  if (beforeWriteHook) {
    beforeWriteHook({
      action: "init",
      path: segments.join("/"),
      segments: [...segments],
      root,
      realRoot,
    });
  }
  ensureDirInsideRootChecked(
    root,
    realRoot,
    rootSnap,
    realRootSnap,
    segments.slice(0, -1),
    expectedDirs,
  );
  const targetPath = path.join(root, ...segments);
  let preLst = null;
  try {
    preLst = fs.lstatSync(targetPath);
  } catch (err) {
    if (!err || typeof err !== "object" || err.code !== "ENOENT") {
      throw err;
    }
  }
  if (preLst !== null) {
    const why =
      preLst.nlink > 1
        ? "is a hardlink"
        : preLst.isSymbolicLink()
          ? "is a symlink"
          : "appeared before write";
    throw new Error(`${segments.join("/")} ${why} (changed-during-sync)`);
  }
  const noFollow = fs.constants?.O_NOFOLLOW ?? 0;
  const fd = fs.openSync(
    targetPath,
    fs.constants.O_WRONLY |
      fs.constants.O_CREAT |
      fs.constants.O_EXCL |
      noFollow,
    0o644,
  );
  let completed = false;
  let fdStat = null;
  try {
    fdStat = fs.fstatSync(fd);
    if (!fdStat.isFile() || fdStat.nlink !== 1) {
      throw new Error(
        `${segments.join("/")} changed before write (changed-during-sync)`,
      );
    }
    const buf = Buffer.from(text, "utf8");
    let written = 0;
    while (written < buf.length) {
      written += fs.writeSync(fd, buf, written, buf.length - written);
    }
    completed = true;
    return {
      path: targetPath,
      segments: [...segments],
      dev: fdStat.dev,
      ino: fdStat.ino,
    };
  } finally {
    fs.closeSync(fd);
    if (!completed) {
      const canUnlink =
        fdStat &&
        verifyCreatedFileUnchanged(
          root,
          realRoot,
          rootSnap,
          realRootSnap,
          expectedDirs,
          {
            path: targetPath,
            segments: [...segments],
            dev: fdStat.dev,
            ino: fdStat.ino,
          },
        );
      if (canUnlink) {
        try {
          fs.unlinkSync(targetPath);
        } catch {
          // Best-effort cleanup of partial new file.
        }
      }
    }
  }
}

function verifySyncTargetUnchanged(root, realRoot, rootSnap, realRootSnap, op) {
  if (!verifyRootUnchanged(root, realRoot, rootSnap, realRootSnap)) {
    return { ok: false, reason: "changed-during-sync" };
  }
  let cur = root;
  for (let i = 0; i < op.segments.length; i += 1) {
    cur = path.join(cur, op.segments[i]);
    const isLast = i === op.segments.length - 1;
    const expected = op.components[i];
    if (!expected) {
      return { ok: false, reason: "changed-during-sync" };
    }
    let lst;
    try {
      lst = fs.lstatSync(cur);
    } catch {
      return { ok: false, reason: "changed-during-sync" };
    }
    if (lst.isSymbolicLink()) {
      return { ok: false, reason: "changed-during-sync" };
    }
    if (lst.dev !== expected.dev || lst.ino !== expected.ino) {
      return { ok: false, reason: "changed-during-sync" };
    }
    let realCur;
    try {
      realCur = fs.realpathSync(cur);
    } catch {
      return { ok: false, reason: "changed-during-sync" };
    }
    if (
      realCur !== expected.realPath ||
      !isPathInsideRealRoot(realRoot, realCur)
    ) {
      return { ok: false, reason: "changed-during-sync" };
    }
    if (!isLast) {
      if (!lst.isDirectory()) {
        return { ok: false, reason: "changed-during-sync" };
      }
    } else {
      if (!lst.isFile()) {
        return { ok: false, reason: "changed-during-sync" };
      }
      if (lst.nlink > 1) {
        return { ok: false, reason: "hardlink" };
      }
    }
  }
  return { ok: true };
}

function overwriteFileNoFollow(filePath, text, expectedFileStat = null) {
  const noFollow = fs.constants?.O_NOFOLLOW ?? 0;
  let fd;
  try {
    fd = fs.openSync(filePath, fs.constants.O_WRONLY | noFollow);
  } catch (err) {
    const code = err && typeof err === "object" ? err.code : undefined;
    if (code === "ENOENT" || code === "ELOOP" || code === "ENOTDIR") {
      return { ok: false, reason: "changed-during-sync" };
    }
    throw err;
  }
  try {
    const st = fs.fstatSync(fd);
    if (!st.isFile()) {
      return { ok: false, reason: "changed-during-sync" };
    }
    if (st.nlink > 1) {
      return { ok: false, reason: "hardlink" };
    }
    if (
      expectedFileStat &&
      (st.dev !== expectedFileStat.dev || st.ino !== expectedFileStat.ino)
    ) {
      return { ok: false, reason: "changed-during-sync" };
    }
    fs.ftruncateSync(fd, 0);
    const buf = Buffer.from(text, "utf8");
    let written = 0;
    while (written < buf.length) {
      written += fs.writeSync(fd, buf, written, buf.length - written, written);
    }
    return { ok: true };
  } finally {
    fs.closeSync(fd);
  }
}

/**
 * Executes `team_setup` (`init` or `sync`) for OpenCode, enforcing explicit
 * `root`, symlink and hardlink refusal, realpath containment, and TOCTOU rechecks.
 *
 * @param {Record<string, any>} args
 * @param {{ cwd?: string, pluginAgentsDir?: string, _beforeWrite?: (ctx: Record<string, any>) => void }} [options]
 */
export function runTeamSetup(args = {}, options = {}) {
  const inp = args && typeof args === "object" ? args : {};
  const action = typeof inp.action === "string" ? inp.action.trim() : "";
  if (action !== "init" && action !== "sync") {
    return { ok: false, error: 'action must be "init" or "sync"' };
  }
  if (inp.check !== undefined && typeof inp.check !== "boolean") {
    return { ok: false, error: "check must be a boolean" };
  }
  const check = inp.check === true;
  const beforeWriteHook =
    typeof options._beforeWrite === "function" ? options._beforeWrite : null;

  const hasRoot =
    Object.prototype.hasOwnProperty.call(inp, "root") && inp.root !== undefined;
  const rawRoot = hasRoot
    ? inp.root
    : resolveRepoRoot(options.cwd ?? process.cwd());
  if (typeof rawRoot !== "string" || !path.isAbsolute(rawRoot)) {
    return { ok: false, error: INVALID_ROOT_ERROR };
  }
  let rootSt;
  try {
    rootSt = fs.statSync(rawRoot);
  } catch {
    return { ok: false, error: INVALID_ROOT_ERROR };
  }
  if (!rootSt.isDirectory()) {
    return { ok: false, error: INVALID_ROOT_ERROR };
  }
  const root = rawRoot.replace(/\/+$/, "") || "/";
  let realRoot;
  let rootSnap;
  let realRootSnap;
  try {
    rootSnap = fs.lstatSync(root);
    realRoot = fs.realpathSync(root);
    realRootSnap = fs.lstatSync(realRoot);
  } catch {
    return { ok: false, error: INVALID_ROOT_ERROR };
  }

  if (action === "init") {
    const starterCheck = validateStarterAgents(inp.agents);
    if (!starterCheck.ok) {
      return { ok: false, error: starterCheck.error };
    }
    const starterRoles = starterCheck.roles;

    const expectedDirs = new Map();
    const teamInspect = inspectRepoPath(root, realRoot, [
      ".agents",
      "team.json",
    ]);
    if (teamInspect.status !== "absent") {
      return {
        ok: false,
        error:
          teamInspect.status === "file"
            ? ".agents/team.json already exists"
            : teamInspect.error || ".agents/team.json cannot be created",
      };
    }
    const teamSnap = recordInitDirSnapshot(
      expectedDirs,
      [".agents", "team.json"],
      teamInspect.existingComponents,
    );
    if (!teamSnap.ok) {
      return { ok: false, error: teamSnap.error };
    }

    const callingHarness = "opencode";
    const pluginAgentsDir =
      options.pluginAgentsDir || DEFAULT_PLUGIN_AGENTS_DIR;
    const agentDirs = TEAM_AGENT_DIRS[callingHarness];
    /** @type {Array<{ segments: string[], relPath: string, text: string, role: string, agent: string }>} */
    const plannedAgents = [];

    for (const role of starterRoles) {
      const agentName = `team-${role}`;
      const segments = [...agentDirs, `${agentName}.md`];
      const relPath = segments.join("/");
      const targetInspect = inspectRepoPath(root, realRoot, segments);
      if (targetInspect.status !== "absent") {
        return {
          ok: false,
          error:
            targetInspect.status === "file"
              ? `${relPath} already exists`
              : targetInspect.error || `${relPath} cannot be created`,
        };
      }
      const targetSnap = recordInitDirSnapshot(
        expectedDirs,
        segments,
        targetInspect.existingComponents,
      );
      if (!targetSnap.ok) {
        return { ok: false, error: targetSnap.error };
      }
      const templatePath = path.join(pluginAgentsDir, `${role}.md`);
      let templateText;
      try {
        const st = fs.statSync(templatePath);
        if (!st.isFile() || st.size > MAX_AGENT_FILE_BYTES) {
          return {
            ok: false,
            error: `plugin starter template agents/${role}.md is invalid`,
          };
        }
        templateText = fs.readFileSync(templatePath, "utf8");
        if (Buffer.byteLength(templateText, "utf8") > MAX_AGENT_FILE_BYTES) {
          return {
            ok: false,
            error: `plugin starter template agents/${role}.md is invalid`,
          };
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          ok: false,
          error: `failed to read plugin template agents/${role}.md: ${msg}`,
        };
      }
      plannedAgents.push({
        segments,
        relPath,
        text: starterAgentFile(templateText, role),
        role,
        agent: agentName,
      });
    }

    const teamText = renderStarterTeam(starterRoles);
    if (!check) {
      const createdFiles = [];
      try {
        for (const item of plannedAgents) {
          createdFiles.push(
            writeNewFileNoFollow(
              root,
              realRoot,
              rootSnap,
              realRootSnap,
              item.segments,
              item.text,
              expectedDirs,
              beforeWriteHook,
            ),
          );
        }
        createdFiles.push(
          writeNewFileNoFollow(
            root,
            realRoot,
            rootSnap,
            realRootSnap,
            [".agents", "team.json"],
            teamText,
            expectedDirs,
            beforeWriteHook,
          ),
        );
      } catch (err) {
        const cleanupErrors = [];
        for (let i = createdFiles.length - 1; i >= 0; i -= 1) {
          const created = createdFiles[i];
          if (!created) continue;
          if (
            !verifyCreatedFileUnchanged(
              root,
              realRoot,
              rootSnap,
              realRootSnap,
              expectedDirs,
              created,
            )
          ) {
            cleanupErrors.push(`${created.path}: path changed before rollback`);
            continue;
          }
          try {
            fs.unlinkSync(created.path);
          } catch (rmErr) {
            const rmMsg =
              rmErr instanceof Error ? rmErr.message : String(rmErr);
            cleanupErrors.push(`${created.path}: ${rmMsg}`);
          }
        }
        const rollbackNote =
          cleanupErrors.length > 0
            ? `; rollback errors: ${cleanupErrors.join("; ")}`
            : "";
        const msg = err instanceof Error ? err.message : String(err);
        return {
          ok: false,
          error: `failed to write starter files: ${msg}${rollbackNote}`,
        };
      }
    }

    const files = [
      ...plannedAgents.map((item) => ({
        path: item.relPath,
        harness: callingHarness,
        role: item.role,
        agent: item.agent,
        status: "created",
        reason: null,
      })),
      { path: ".agents/team.json", status: "created", reason: null },
    ];
    return {
      ok: true,
      result: { action: "init", root, check, files },
    };
  }

  // action === "sync"
  const teamInspect = inspectRepoPath(root, realRoot, [".agents", "team.json"]);
  if (teamInspect.status === "absent") {
    return { ok: false, error: ".agents/team.json does not exist" };
  }
  if (teamInspect.status !== "file") {
    return {
      ok: false,
      error: teamInspect.error || ".agents/team.json cannot be read",
    };
  }
  if (teamInspect.size > MAX_TEAM_FILE_BYTES) {
    return {
      ok: false,
      error: `.agents/team.json exceeds maximum size of ${MAX_TEAM_FILE_BYTES} bytes (64 KiB)`,
    };
  }
  const teamRead = readBoundedFileNoFollow(
    teamInspect.realPath,
    MAX_TEAM_FILE_BYTES,
    ".agents/team.json",
  );
  if (!teamRead.ok) {
    return { ok: false, error: teamRead.error };
  }
  const parsed = parseTeam(teamRead.text);
  if (parsed.errors.length > 0 || !parsed.team) {
    const firstErr = parsed.errors[0];
    return {
      ok: false,
      error:
        parsed.errors.length === 1 &&
        typeof firstErr === "string" &&
        firstErr.startsWith("invalid JSON:")
          ? firstErr
          : `invalid .agents/team.json: ${parsed.errors.join("; ")}`,
    };
  }

  const targets = planTeamSync(parsed.team);
  const files = [];
  const plannedWrites = [];

  for (const target of targets) {
    const inspected = inspectRepoPath(root, realRoot, target.segments);
    if (inspected.status === "error") {
      return { ok: false, error: inspected.error };
    }
    if (inspected.status === "absent") {
      continue;
    }
    if (inspected.status !== "file") {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "skipped",
        reason: inspected.reason,
      });
      continue;
    }
    if (target.conflict) {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "skipped",
        reason: target.reason,
      });
      continue;
    }
    if (inspected.size > MAX_AGENT_FILE_BYTES) {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "skipped",
        reason: "too-large",
      });
      continue;
    }

    const fileRead = readBoundedFileNoFollow(
      inspected.realPath,
      MAX_AGENT_FILE_BYTES,
      target.path,
    );
    if (!fileRead.ok) {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "skipped",
        reason: fileRead.reason,
      });
      continue;
    }

    const applied = applyAgentModels(fileRead.text, target.harness, {
      model: target.model,
      effort: target.effort,
    });
    if (applied.reason !== null) {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "skipped",
        reason: applied.reason,
      });
      continue;
    }
    if (applied.changed) {
      const fileIndex = files.length;
      plannedWrites.push({
        path: inspected.path,
        realPath: inspected.realPath,
        relPath: target.path,
        segments: target.segments,
        components: inspected.components,
        fileStat: { dev: inspected.dev, ino: inspected.ino },
        fileIndex,
        text: applied.text,
      });
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "changed",
        reason: null,
      });
    } else {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "unchanged",
        reason: null,
      });
    }
  }

  if (!check) {
    for (const op of plannedWrites) {
      if (beforeWriteHook) {
        beforeWriteHook({
          action: "sync",
          path: op.relPath,
          segments: [...op.segments],
          root,
          realRoot,
        });
      }
      const verified = verifySyncTargetUnchanged(
        root,
        realRoot,
        rootSnap,
        realRootSnap,
        op,
      );
      if (!verified.ok) {
        files[op.fileIndex] = {
          ...files[op.fileIndex],
          status: "skipped",
          reason: verified.reason,
        };
        continue;
      }
      try {
        const writeRes = overwriteFileNoFollow(op.path, op.text, op.fileStat);
        if (!writeRes.ok) {
          files[op.fileIndex] = {
            ...files[op.fileIndex],
            status: "skipped",
            reason: writeRes.reason,
          };
          continue;
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          ok: false,
          error: `failed to write ${op.relPath}: ${msg}`,
        };
      }
    }
  }

  return {
    ok: true,
    result: { action: "sync", root, check, files },
  };
}

/**
 * Loads `<repo root>/.agents/team.json` and returns the lowercase
 * `agent -> role` display map for mapped agents. Never throws.
 *
 * @param {string} [cwd]
 * @param {{ tiers?: Record<string, Record<string, string | null | undefined>> }} [defaults]
 * @returns {Record<string, string>}
 */
export function loadAgentRoles(cwd = process.cwd(), defaults = TIER_DEFAULTS) {
  try {
    return agentRoleMap(loadTeamConfig(cwd, defaults));
  } catch {
    return Object.create(null);
  }
}

/**
 * Returns a zero-timer reader that checks `.agents/team.json` mtime/size on
 * each call and reloads `agentRoleMap` whenever the file is created, modified,
 * or removed.
 *
 * @param {string} [cwd]
 * @param {{ tiers?: Record<string, Record<string, string | null | undefined>> }} [defaults]
 * @returns {() => Record<string, string>}
 */
export function createAgentRolesReader(
  cwd = process.cwd(),
  defaults = TIER_DEFAULTS,
) {
  const root = resolveRepoRoot(cwd);
  const teamPath = path.join(root, ".agents", "team.json");
  let initialized = false;
  let lastStamp = null;
  /** @type {Record<string, string>} */
  let cached = Object.create(null);

  const readStamp = () => {
    try {
      const lst = fs.lstatSync(teamPath);
      if (lst.isSymbolicLink()) {
        try {
          const tst = fs.statSync(teamPath);
          return `link:${lst.mtimeMs}:${tst.ino}:${tst.mtimeMs}:${tst.size}`;
        } catch {
          return `dangling:${lst.mtimeMs}`;
        }
      }
      return `file:${lst.ino}:${lst.mtimeMs}:${lst.size}`;
    } catch {
      return "absent";
    }
  };

  return () => {
    const stamp = readStamp();
    if (initialized && stamp === lastStamp) {
      return cached;
    }
    initialized = true;
    lastStamp = stamp;
    try {
      cached = agentRoleMap(loadTeamConfigAtRoot(root, defaults));
    } catch {
      cached = Object.create(null);
    }
    return cached;
  };
}

/**
 * Build structured view-model for all 5 required sections in panel-spec.md.
 *
 * @param {import('./orchestrator-core.mjs').Flow | null} flow
 * @param {number} [now]
 * @param {{ agentRoles?: Record<string, string> }} [options]
 */
export function formatSidebarData(flow, now = Date.now(), options = {}) {
  const flowRoles = flowAgentRoleMap(flow);
  const agentRoles =
    flowRoles !== null
      ? flowRoles
      : options?.agentRoles && typeof options.agentRoles === "object"
        ? options.agentRoles
        : null;
  if (!flow) {
    return {
      empty: true,
      emptyMessage: EMPTY_PANEL_MESSAGE,
      sidebarTitle: formatSidebarTitle(null),
    };
  }

  const remCount = remaining(flow);
  const totalCount = flow.tasks.length;
  const acceptedCount = Math.max(0, totalCount - remCount);
  const bd = burnDown(flow);
  const tBoard = taskBoard(flow);
  const sp = spend(flow);

  const currentPhaseIdx = PHASES.indexOf(flow.phase);
  const phases = PHASES.map((phase, idx) => {
    const isClosed = Boolean(flow.closedAt);
    const state = isClosed
      ? "done"
      : idx < currentPhaseIdx
        ? "done"
        : idx === currentPhaseIdx
          ? "current"
          : "upcoming";
    return { phase, state };
  });

  const replanCount = bd.replans.length;
  const spark = sparkline(bd.points, bd.replans);
  const idealStart = bd.ideal[0]?.remaining ?? totalCount;
  const idealEnd = bd.ideal[bd.ideal.length - 1]?.remaining ?? 0;

  const tasks = tBoard.map((t) => ({
    id: String(t.n),
    n: t.n,
    title: t.title,
    specialist: t.specialist,
    tier: t.tier,
    state: t.state,
    color: statusColorToken(t.state),
    round: t.round,
    roundText: t.round > 0 ? `r${t.round}` : "",
    waitingOn: t.waitingOn,
    waitsOnText:
      t.waitingOn.length > 0
        ? `waits on ${t.waitingOn.map((n) => `#${n}`).join(", ")}`
        : "",
    ...(t.model ? { model: sanitizeShortField(t.model, 128) } : {}),
    ...(t.worktree ? { worktree: sanitizeShortField(t.worktree, 128) } : {}),
    ...(t.warning ? { warning: sanitizeShortField(t.warning, 240) } : {}),
  }));

  const stallRows = stalls(flow, now);
  const stallByRunId = new Map(stallRows.map((s) => [s.id, s]));
  const memberGroups = members(flow);
  const memberById = new Map(
    [
      ...memberGroups.active,
      ...memberGroups.standingBy,
      ...memberGroups.retired,
    ].map((m) => [m.id, m]),
  );

  const agents = flow.runs.map((r) => {
    const costUsd = runCost(r);
    const priced = costUsd !== null;
    const totalTokens =
      (r.tokens?.input || 0) +
      (r.tokens?.output || 0) +
      (r.tokens?.cacheRead || 0) +
      (r.tokens?.cacheWrite || 0);
    const safeNote = r.steps?.note ? sanitizeShortField(r.steps.note, 500) : "";
    const stepsText = r.steps
      ? `${r.steps.done}/${r.steps.total}${safeNote ? ` ${safeNote}` : ""}`
      : r.contextPct !== null && r.contextPct !== undefined
        ? `ctx ${Math.round(r.contextPct)}%`
        : "—";
    const endMs = r.endedAt ?? now;
    const elapsedMs = Math.max(0, endMs - (r.startedAt || endMs));
    const safeFullModel = sanitizeShortField(r.model, 256);
    const baseModel = shortModelName(safeFullModel);
    const member = memberById.get(r.id);
    const effectiveDelegateRaw = r.delegate || member?.taskModel || null;
    const delegateModel = effectiveDelegateRaw
      ? shortModelName(effectiveDelegateRaw)
      : null;
    const modelLabel =
      delegateModel && delegateModel !== baseModel
        ? `${baseModel} → ${delegateModel}`
        : baseModel;
    const worktree =
      r.worktree || member?.worktree
        ? sanitizeShortField(r.worktree || member?.worktree, 128)
        : undefined;
    const stallRow = stallByRunId.get(r.id);
    const stallState = stallRow?.state ?? null;
    const idleMs = stallRow?.idleMs ?? 0;
    const memberBadge =
      member?.state === "killed"
        ? "killed"
        : member?.state === "paused"
          ? `paused: ${sanitizeShortField(member.reason || "error", 64)}`
          : null;
    const statusText = memberBadge
      ? memberBadge
      : r.status === "running" &&
          (stallState === "quiet" ||
            stallState === "waiting" ||
            stallState === "stalled")
        ? `${r.status} (${stallState})`
        : r.status;
    const color =
      member?.state === "killed"
        ? "error"
        : member?.state === "paused"
          ? "warning"
          : r.status === "running" && stallState === "stalled"
            ? "error"
            : r.status === "running" && stallState === "quiet"
              ? "warning"
              : statusColorToken(r.status);
    const cleanAgent = sanitizeShortField(r.agent, 128);
    return {
      id: r.id,
      taskId:
        r.taskN !== null && r.taskN !== undefined ? String(r.taskN) : undefined,
      role: r.role,
      agent: cleanAgent,
      agentLabel: formatAgentRoleLabel(cleanAgent, agentRoles),
      model: modelLabel,
      fullModel: safeFullModel,
      delegate: r.delegate ? sanitizeShortField(r.delegate, 256) : null,
      ...(member?.taskModel
        ? { taskModel: sanitizeShortField(member.taskModel, 128) }
        : {}),
      ...(worktree ? { worktree } : {}),
      effort: sanitizeShortField(r.effort || "high", 64) || "high",
      stepsText,
      tokens: totalTokens,
      tokensText: `${formatTokensCompact(totalTokens)} tok`,
      priced,
      costUsd: costUsd ?? 0,
      costText: priced ? `est. ${formatUsd(costUsd)}` : "unpriced",
      elapsedText: formatDuration(elapsedMs),
      status: statusText,
      memberBadge,
      stallState,
      idleMs,
      color,
    };
  });

  const byModelRows = Object.entries(sp.byModel).map(([model, usd]) => ({
    model: shortModelName(model),
    usd,
    usdText: formatUsd(usd),
  }));

  const unpricedRunsList = flow.runs
    .filter((r) => runCost(r) === null)
    .map((r) => {
      const tok =
        (r.tokens?.input || 0) +
        (r.tokens?.output || 0) +
        (r.tokens?.cacheRead || 0) +
        (r.tokens?.cacheWrite || 0);
      return {
        id: r.id,
        model: shortModelName(r.model),
        tokens: tok,
        tokensText: `${formatTokensCompact(tok)} tok`,
      };
    });

  /** @type {Record<string, number>} */
  const unpricedDelegatedByModel = {};
  for (const r of flow.runs) {
    if (r.delegate && delegateCost(r) === null) {
      const cleanDel = sanitizeShortField(r.delegate, 256);
      if (cleanDel) {
        unpricedDelegatedByModel[cleanDel] =
          (unpricedDelegatedByModel[cleanDel] ?? 0) + 1;
      }
    }
  }
  const delegatedText =
    sp.delegated.unpriced > 0
      ? `delegated to Gemini: ${sp.delegated.unpriced} ${sp.delegated.unpriced === 1 ? "run" : "runs"} (${Object.entries(
          unpricedDelegatedByModel,
        )
          .map(([m, n]) => `${m} ×${n}`)
          .join(", ")}), not priced`
      : "";

  const totalPosts = Array.isArray(flow.posts) ? flow.posts.length : 0;
  const postsDropped =
    Number.isInteger(flow.postsDropped) && flow.postsDropped > 0
      ? flow.postsDropped
      : 0;
  const topEdges = totalPosts > 0 ? mentionGraph(flow).edges.slice(0, 5) : [];
  const whoTalksText =
    topEdges.length > 0
      ? topEdges
          .map(
            (e) =>
              `${sanitizeShortField(e.from, 64)} → ${sanitizeShortField(e.to, 64)} ×${e.count}`,
          )
          .join(", ")
      : "";
  const recentPosts = board(flow, { limit: 5 }).map((p) => ({
    seq: p.seq,
    at: p.at,
    from: p.from,
    to: p.to,
    recipientsText:
      p.to.length > 0
        ? `→ ${p.to.map((t) => (String(t).toLowerCase() === "all" ? "everyone" : `@${t}`)).join(", ")}`
        : "",
    replyText:
      typeof p.replyTo === "number" &&
      Number.isInteger(p.replyTo) &&
      p.replyTo > 0
        ? `↩ #${p.replyTo}`
        : "",
    kind: p.kind,
    color: postKindColorToken(p.kind),
    ageText: `${formatDuration(Math.max(0, now - p.at))} ago`,
    text: clipSingleLine(p.text, 72),
    replyTo: p.replyTo,
    ...(p.channel && p.channel !== "main" ? { channel: p.channel } : {}),
  }));
  const wakes = pendingWakes(flow).map((w) => ({
    ...w,
    excerpt: clipSingleLine(w.excerpt, 64),
  }));
  const channelList = channels(flow);
  const hasNonMainChannel = channelList.some((c) => c.name !== "main");
  const ov = overview(flow, { now });
  const hasOverviewContent =
    ov.members.length > 0 ||
    ov.openQuestions.length > 0 ||
    ov.openDefects.length > 0 ||
    ov.stalls.length > 0;
  const showOverview =
    hasOverviewContent &&
    (totalPosts > 0 || postsDropped > 0 || hasNonMainChannel);
  const overviewData = showOverview
    ? {
        members: ov.members.map((m) => {
          const cleanMemberAgent = sanitizeShortField(m.agent, 64);
          return {
            agent: cleanMemberAgent,
            agentLabel: formatAgentRoleLabel(cleanMemberAgent, agentRoles),
            state: m.state,
            line: m.line,
          };
        }),
        openQuestions: ov.openQuestions.map((q) => ({
          seq: q.seq,
          from: sanitizeShortField(q.from, 64),
          text: clipSingleLine(q.text, 72),
        })),
        openDefects: ov.openDefects.map((d) => ({
          seq: d.seq,
          from: sanitizeShortField(d.from, 64),
          to: d.to,
          toText:
            d.to.length > 0
              ? ` → ${d.to.map((t) => (String(t).toLowerCase() === "all" ? "everyone" : `@${sanitizeShortField(t, 64)}`)).join(", ")}`
              : "",
          text: clipSingleLine(d.text, 72),
        })),
        stalls: ov.stalls.map((s) => {
          const cleanStallAgent = sanitizeShortField(s.agent, 64);
          return {
            id: s.id,
            agent: cleanStallAgent,
            agentLabel: formatAgentRoleLabel(cleanStallAgent, agentRoles),
            state: s.state,
            idleText: formatDuration(s.idleMs),
          };
        }),
      }
    : undefined;

  return {
    empty: false,
    sidebarTitle: formatSidebarTitle(flow),
    header: {
      title: sanitizeShortField(flow.title, 500),
      phase: sanitizeShortField(flow.phase, 64),
      phases,
      accepted: acceptedCount,
      total: totalCount,
      remaining: remCount,
      acceptedText: `accepted ${acceptedCount} of ${totalCount}`,
      estCostText: `est. ${formatUsd(sp.total)}`,
    },
    burnDown: {
      sparkline: spark,
      points: bd.points,
      ideal: bd.ideal,
      idealSummary: `ideal ${idealStart}→${idealEnd}`,
      replanCount,
      replanText:
        replanCount > 0
          ? `${replanCount} replan${replanCount > 1 ? "s" : ""} (⟳)`
          : "0 replans",
      remainingText: `${remCount} left`,
    },
    tasks,
    agents,
    members: memberGroups,
    channels: channelList,
    ...(overviewData ? { overview: overviewData } : {}),
    board: {
      total: totalPosts,
      postsDropped,
      posts: recentPosts,
      ...(whoTalksText ? { whoTalksText } : {}),
    },
    pendingWakes: wakes,
    spend: {
      leadUsd: sp.lead,
      leadText: formatUsd(sp.lead),
      workersUsd: sp.workers,
      workersText: formatUsd(sp.workers),
      totalUsd: sp.total,
      totalText: formatUsd(sp.total),
      byModel: byModelRows,
      unpricedSummary: sp.unpriced,
      unpriced: unpricedRunsList,
      delegated: {
        ...sp.delegated,
        byModel: Object.fromEntries(
          Object.entries(sp.delegated.byModel ?? {}).map(([m, n]) => [
            sanitizeShortField(m, 256),
            n,
          ]),
        ),
      },
      delegatedText,
    },
  };
}

/**
 * Format compact terminal sidebar lines for plain-text rendering and tests.
 *
 * @param {import('./orchestrator-core.mjs').Flow | null} flow
 * @param {number} [now]
 * @param {{ agentRoles?: Record<string, string> }} [options]
 * @returns {string[]}
 */
export function formatSidebarLines(flow, now = Date.now(), options = {}) {
  const data = formatSidebarData(flow, now, options);
  if (data.empty) {
    return [data.emptyMessage];
  }

  /** @type {string[]} */
  const lines = [];

  // 1. Header
  const phasePills = data.header.phases
    .map((p) =>
      p.state === "done"
        ? `✓${p.phase}`
        : p.state === "current"
          ? `[${p.phase.toUpperCase()}]`
          : p.phase,
    )
    .join(" · ");
  lines.push(
    `${data.header.title} — ${data.header.acceptedText} · ${data.header.estCostText}`,
  );
  lines.push(`Phases: ${phasePills}`);

  // 2. Burn-down
  lines.push(
    `Burn-down: ${data.burnDown.sparkline} (${data.burnDown.remainingText}, ${data.burnDown.idealSummary}, ${data.burnDown.replanText})`,
  );

  // 3. Task board
  lines.push(`Tasks (${data.tasks.length}):`);
  if (data.tasks.length === 0) {
    lines.push("  (no tasks planned yet)");
  } else {
    for (const t of data.tasks) {
      const specPart = [
        `${t.specialist}/${t.tier}`,
        t.model || "",
        t.worktree ? `⎇ ${t.worktree}` : "",
      ]
        .filter(Boolean)
        .join(" · ");
      const extras = [
        t.roundText,
        t.waitsOnText,
        t.warning ? `⚠ ${t.warning}` : "",
      ]
        .filter(Boolean)
        .join(" · ");
      lines.push(
        `  #${t.id} ${t.title} [${specPart}] — ${t.state}${extras ? ` (${extras})` : ""}`,
      );
    }
  }

  // 4. Agents
  lines.push(`Agents (${data.agents.length}):`);
  if (data.agents.length === 0) {
    lines.push("  (no runs recorded yet)");
  } else {
    for (const a of data.agents) {
      const taskRef = a.taskId ? ` #${a.taskId}` : "";
      const modelAndEffort = [
        a.model,
        a.effort,
        a.worktree ? `⎇ ${a.worktree}` : "",
      ]
        .filter(Boolean)
        .join(" · ");
      lines.push(
        `  ${a.agentLabel || a.agent}${taskRef} (${modelAndEffort}) · ${a.stepsText} · ${a.tokensText} · ${a.costText} · ${a.elapsedText} · ${a.status}`,
      );
    }
  }

  // 5. Spend
  const modelParts = data.spend.byModel
    .map((m) => `${m.model}: ${m.usdText}`)
    .join(", ");
  lines.push(
    `Spend: lead ${data.spend.leadText} · workers ${data.spend.workersText} · total ${data.spend.totalText}${modelParts ? ` (${modelParts})` : ""}`,
  );
  if (data.spend.unpriced.length > 0) {
    const unpricedParts = data.spend.unpriced
      .map((u) => `${u.model}: ${u.tokensText}`)
      .join(", ");
    lines.push(`Unpriced: ${unpricedParts}`);
  }
  if (data.spend.delegated.unpriced > 0) {
    lines.push(`  ${data.spend.delegatedText}`);
  }

  // 6. Overview (only non-empty subsections)
  if (data.overview) {
    lines.push("Overview:");
    if (data.overview.members.length > 0) {
      for (const m of data.overview.members) {
        lines.push(
          `  ${m.agentLabel || m.agent} (${m.state})${m.line ? `: ${clipSingleLine(m.line, 72)}` : ""}`,
        );
      }
    }
    if (data.overview.openQuestions.length > 0) {
      lines.push(`  Open questions (${data.overview.openQuestions.length}):`);
      for (const q of data.overview.openQuestions) {
        lines.push(`    #${q.seq} ${q.from}: ${q.text}`);
      }
    }
    if (data.overview.openDefects.length > 0) {
      lines.push(`  Open defects (${data.overview.openDefects.length}):`);
      for (const d of data.overview.openDefects) {
        lines.push(`    #${d.seq} ${d.from}${d.toText}: ${d.text}`);
      }
    }
    if (data.overview.stalls.length > 0) {
      lines.push(`  Stalls (${data.overview.stalls.length}):`);
      for (const s of data.overview.stalls) {
        lines.push(
          `    ${s.agentLabel || s.agent} (${s.state} · ${s.idleText})`,
        );
      }
    }
  }

  // 7. Shared board (newest 5 clipped single-line posts) & pending wakes
  if (data.board.total > 0 || data.board.postsDropped > 0) {
    lines.push(`Board (${data.board.total}):`);
    if (data.board.whoTalksText) {
      lines.push(`  Who talks to whom: ${data.board.whoTalksText}`);
    }
    if (data.board.postsDropped > 0) {
      lines.push(`  ${data.board.postsDropped} older posts not shown`);
    }
    for (const p of data.board.posts) {
      const ch = p.channel ? ` #${p.channel}` : "";
      const rec = p.recipientsText ? ` ${p.recipientsText}` : "";
      const rep = p.replyText ? ` ${p.replyText}` : "";
      lines.push(
        `  #${p.seq}${ch} ${p.from}${rec}${rep} · ${p.ageText} [${p.kind}] ${p.text}`,
      );
    }
  }
  if (data.pendingWakes.length > 0) {
    lines.push(`Pending wakes (${data.pendingWakes.length}):`);
    for (const w of data.pendingWakes) {
      lines.push(`  #${w.seq} ${w.from} → @${w.target}: "${w.excerpt}"`);
    }
  }

  return lines;
}
