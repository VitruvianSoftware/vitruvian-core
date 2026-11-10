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

import {
  burnDown,
  DEFAULT_QUIET_MS,
  DEFAULT_STALL_MS,
  delegateCost,
  initialFlow,
  reduce,
  remaining,
  runCost,
  spend,
  stalls,
  taskBoard,
} from "./orchestrator-core.mjs";

export {
  burnDown,
  DEFAULT_QUIET_MS,
  DEFAULT_STALL_MS,
  delegateCost,
  initialFlow,
  reduce,
  remaining,
  runCost,
  spend,
  stalls,
  taskBoard,
};

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
  if (!model) return "unknown";
  return model.replace(/^[^/]+\//, "");
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

  if (Array.isArray(input.accept)) {
    for (const rawN of input.accept) {
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

  if (Array.isArray(input.return)) {
    for (const item of input.return) {
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

  if (input.finished === true) {
    events.push({
      type: "close",
      at,
    });
  }

  return events;
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
    next = { ...next, title: input.title.trim() };
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

  if (!flow) {
    return {
      flow: null,
      matched: false,
      runId: null,
      summary: `step recorded (${done}/${total}) — no active orchestrator flow yet`,
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
      summary: `step ignored (${done}/${total}): caller session is not a tracked worker run`,
    };
  }

  const next = reduce(flow, {
    type: "run.progress",
    at,
    id: targetRun.id,
    steps: {
      done,
      total,
      note,
    },
    ...(delegate ? { delegate } : {}),
    ...(input?.delegateUsage !== undefined
      ? {
          delegateTokens:
            /** @type {Partial<import('./orchestrator-core.mjs').DelegateTokenCounts> | null} */ (
              input.delegateUsage
            ),
        }
      : {}),
  });

  return {
    flow: next,
    matched: true,
    runId: targetRun.id,
    summary: `step updated: ${done}/${total}${note ? ` (${note})` : ""}`,
  };
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

/**
 * Build structured view-model for all 5 required sections in panel-spec.md.
 *
 * @param {import('./orchestrator-core.mjs').Flow | null} flow
 * @param {number} [now]
 */
export function formatSidebarData(flow, now = Date.now()) {
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
  const board = taskBoard(flow);
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

  const tasks = board.map((t) => ({
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
  }));

  const stallRows = stalls(flow, now);
  const stallByRunId = new Map(stallRows.map((s) => [s.id, s]));

  const agents = flow.runs.map((r) => {
    const costUsd = runCost(r);
    const priced = costUsd !== null;
    const totalTokens =
      (r.tokens?.input || 0) +
      (r.tokens?.output || 0) +
      (r.tokens?.cacheRead || 0) +
      (r.tokens?.cacheWrite || 0);
    const stepsText = r.steps
      ? `${r.steps.done}/${r.steps.total}${r.steps.note ? ` ${r.steps.note}` : ""}`
      : r.contextPct !== null && r.contextPct !== undefined
        ? `ctx ${Math.round(r.contextPct)}%`
        : "—";
    const endMs = r.endedAt ?? now;
    const elapsedMs = Math.max(0, endMs - (r.startedAt || endMs));
    const baseModel = shortModelName(r.model);
    const delegateModel = r.delegate ? shortModelName(r.delegate) : null;
    const modelLabel = delegateModel
      ? `${baseModel} → ${delegateModel}`
      : baseModel;
    const stallRow = stallByRunId.get(r.id);
    const stallState = stallRow?.state ?? null;
    const idleMs = stallRow?.idleMs ?? 0;
    const statusText =
      r.status === "running" &&
      (stallState === "quiet" ||
        stallState === "waiting" ||
        stallState === "stalled")
        ? `${r.status} (${stallState})`
        : r.status;
    const color =
      r.status === "running" && stallState === "stalled"
        ? "error"
        : r.status === "running" && stallState === "quiet"
          ? "warning"
          : statusColorToken(r.status);
    return {
      id: r.id,
      taskId:
        r.taskN !== null && r.taskN !== undefined ? String(r.taskN) : undefined,
      role: r.role,
      agent: r.agent,
      model: modelLabel,
      fullModel: r.model,
      delegate: r.delegate ?? null,
      effort: r.effort || "high",
      stepsText,
      tokens: totalTokens,
      tokensText: `${formatTokensCompact(totalTokens)} tok`,
      priced,
      costUsd: costUsd ?? 0,
      costText: priced ? `est. ${formatUsd(costUsd)}` : "unpriced",
      elapsedText: formatDuration(elapsedMs),
      status: statusText,
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
      unpricedDelegatedByModel[r.delegate] =
        (unpricedDelegatedByModel[r.delegate] ?? 0) + 1;
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

  return {
    empty: false,
    sidebarTitle: formatSidebarTitle(flow),
    header: {
      title: flow.title,
      phase: flow.phase,
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
      delegated: sp.delegated,
      delegatedText,
    },
  };
}

/**
 * Format compact terminal sidebar lines for plain-text rendering and tests.
 *
 * @param {import('./orchestrator-core.mjs').Flow | null} flow
 * @param {number} [now]
 * @returns {string[]}
 */
export function formatSidebarLines(flow, now = Date.now()) {
  const data = formatSidebarData(flow, now);
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
      const extras = [t.roundText, t.waitsOnText].filter(Boolean).join(" · ");
      lines.push(
        `  #${t.id} ${t.title} [${t.specialist}/${t.tier}] — ${t.state}${extras ? ` (${extras})` : ""}`,
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
      lines.push(
        `  ${a.agent}${taskRef} (${a.model} · ${a.effort}) · ${a.stepsText} · ${a.tokensText} · ${a.costText} · ${a.elapsedText} · ${a.status}`,
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

  return lines;
}
