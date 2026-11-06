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

// Pure state, transcript parsing, and cost estimation logic for savvy-fleet.
// Ported from savvy-progress (hooks/register.tsx) and adapted for Antigravity
// subagent transcripts and hook inbox events.

export const PHASES = Object.freeze([
  "plan",
  "design",
  "delegate",
  "review",
  "close",
]);

export const TIERS = Object.freeze({
  fable: Object.freeze({
    id: "fable",
    label: "Fable",
    model: "Fable · high",
    color: "#7F77DD",
  }),
  heavy: Object.freeze({
    id: "heavy",
    label: "Heavy",
    model: "Opus · xhigh",
    color: "#D85A30",
  }),
  careful: Object.freeze({
    id: "careful",
    label: "Careful",
    model: "Opus · high",
    color: "#BA7517",
  }),
  medium: Object.freeze({
    id: "medium",
    label: "Medium",
    model: "Opus · medium",
    color: "#378ADD",
  }),
  light: Object.freeze({
    id: "light",
    label: "Light",
    model: "Opus · low",
    color: "#1D9E75",
  }),
  other: Object.freeze({
    id: "other",
    label: "Other",
    model: "inherit",
    color: "#888780",
  }),
});

export const SPECIALIST_DEFAULTS = Object.freeze({
  beacon: Object.freeze({ tier: "heavy", color: "#E0A106" }),
  wren: Object.freeze({ tier: "medium", color: "#A0703F" }),
  atlas: Object.freeze({ tier: "heavy", color: "#378ADD" }),
  ridge: Object.freeze({ tier: "careful", color: "#1D9E75" }),
  forge: Object.freeze({ tier: "heavy", color: "#D85A30" }),
  scout: Object.freeze({ tier: "light", color: "#3B9C5F" }),
  aegis: Object.freeze({ tier: "careful", color: "#5B6CC9" }),
  compass: Object.freeze({ tier: "fable", color: "#D0453F" }),
  pace: Object.freeze({ tier: "light", color: "#12A5A0" }),
  quill: Object.freeze({ tier: "light", color: "#8A63D2" }),
});

// USD per million tokens: [input, output, cache_read, cache_write].
const PRICES = [
  [/fable|mythos/i, [10, 50, 0.25, 12.5]],
  [/opus-5-5/i, [4, 20, 0.2, 5]],
  [/opus/i, [5, 25, 0.5, 6.25]],
  [/sonnet|gemini-pro|\bpro\b/i, [2, 10, 0.2, 2.5]],
  [/haiku|flash/i, [1, 5, 0.1, 1.25]],
];

export function blankFlow() {
  return {
    title: "savvy-flow",
    total: 0,
    done: 0,
    running: 0,
    phase: "plan",
    isFinished: false,
    tasks: [],
  };
}

export function normalizeText(text) {
  return String(text ?? "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

export function inferTier(typeName, roleText = "", explicitTier = "") {
  const rawExplicit = String(explicitTier ?? "")
    .replace(/^[^:]*:/, "")
    .replace(/^savvy-/, "")
    .trim()
    .toLowerCase();
  if (rawExplicit && rawExplicit in TIERS) return rawExplicit;

  const bracketMatch = /\[(fable|heavy|careful|medium|light)\]/i.exec(
    String(roleText ?? ""),
  );
  if (bracketMatch) return bracketMatch[1].toLowerCase();

  const bareType = String(typeName ?? "")
    .replace(/^[^:]*:/, "")
    .trim()
    .toLowerCase();
  const stripped = bareType.replace(/^savvy-/, "");
  if (stripped in TIERS && bareType.startsWith("savvy-")) return stripped;
  if (bareType in SPECIALIST_DEFAULTS)
    return SPECIALIST_DEFAULTS[bareType].tier;
  return "other";
}

function isNewFlow(prev, input) {
  return (
    !prev ||
    prev.isFinished ||
    (input.title !== undefined &&
      String(input.title).trim() !== "" &&
      String(input.title).trim() !== prev.title)
  );
}

function cleanTasks(tasks) {
  if (!Array.isArray(tasks)) return undefined;
  return tasks
    .filter((t) => t && typeof t === "object" && String(t.title ?? "").trim())
    .map((t) => {
      const title = String(t.title ?? "").trim();
      const tier = inferTier(t.specialist ?? t.tier, title, t.tier);
      const after = Array.isArray(t.after)
        ? t.after.filter((n) => Number.isInteger(n) && n > 0)
        : [];
      const specialist = String(t.specialist ?? "").trim() || undefined;
      return {
        title,
        tier: tier === "other" ? "medium" : tier,
        after,
        ...(specialist ? { specialist } : {}),
      };
    });
}

/**
 * Merges a flow progress update into the current flow state.
 * A new title (or updating after a finished flow) resets counters cleanly.
 *
 * @param {Record<string, any> | null | undefined} prev
 * @param {Record<string, any> | null | undefined} input
 */
export function mergeFlowProgress(prev, input = {}) {
  const inp = input && typeof input === "object" ? input : {};
  const base =
    isNewFlow(prev, inp) || !prev ? blankFlow() : { ...blankFlow(), ...prev };
  const tasks = cleanTasks(inp.tasks) ?? base.tasks;
  const rawTotal =
    inp.total !== undefined
      ? Number(inp.total)
      : Array.isArray(inp.tasks)
        ? tasks.length
        : base.total;
  const total = Math.max(
    0,
    Math.round(Number.isFinite(rawTotal) ? rawTotal : 0),
  );
  const rawDone = inp.done !== undefined ? Number(inp.done) : base.done;
  const done = Math.min(
    total || Infinity,
    Math.max(0, Math.round(Number.isFinite(rawDone) ? rawDone : 0)),
  );
  const rawRunning =
    inp.running !== undefined ? Number(inp.running) : base.running;
  const running = Math.max(
    0,
    Math.round(Number.isFinite(rawRunning) ? rawRunning : 0),
  );
  const phase =
    typeof inp.phase === "string" && PHASES.includes(inp.phase)
      ? inp.phase
      : base.phase;
  const isFinished = inp.finished === true;
  const title =
    typeof inp.title === "string" && inp.title.trim()
      ? inp.title.trim()
      : base.title;

  return {
    ...base,
    title,
    total,
    done,
    running: isFinished ? 0 : running,
    phase: isFinished ? "close" : phase,
    isFinished,
    tasks,
  };
}

/**
 * Estimates token consumption and USD cost for a model and usage record.
 *
 * @param {string} [model]
 * @param {Record<string, any>} [usage]
 */
export function estimateRunCost(model = "inherit", usage = {}) {
  const modelStr = String(model ?? "inherit");
  const u = usage && typeof usage === "object" ? usage : {};
  const priceRow = PRICES.find(([re]) => re.test(modelStr))?.[1] ?? [
    4, 20, 0.2, 5,
  ];
  const [inRate, outRate, readRate, writeRate] = priceRow;

  const hasExplicitTokens =
    u.input_tokens !== undefined ||
    u.output_tokens !== undefined ||
    u.inputTokens !== undefined ||
    u.outputTokens !== undefined;

  const inputTokens = hasExplicitTokens
    ? Math.max(0, Number(u.input_tokens ?? u.inputTokens ?? 0) || 0)
    : Math.max(0, Number(u.steps ?? 0) * 420 + Number(u.toolCalls ?? 0) * 180);
  const outputTokens = hasExplicitTokens
    ? Math.max(0, Number(u.output_tokens ?? u.outputTokens ?? 0) || 0)
    : Math.max(0, Number(u.steps ?? 0) * 160);
  const cacheReadTokens = Math.max(
    0,
    Number(u.cache_read_input_tokens ?? u.cacheReadTokens ?? 0) || 0,
  );
  const cacheWriteTokens = Math.max(
    0,
    Number(u.cache_creation_input_tokens ?? u.cacheWriteTokens ?? 0) || 0,
  );

  const tokens =
    inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens;
  const costUsd =
    (inputTokens * inRate +
      outputTokens * outRate +
      cacheReadTokens * readRate +
      cacheWriteTokens * writeRate) /
    1e6;
  const contextMax = /haiku|flash_lite/i.test(modelStr) ? 200_000 : 1_000_000;
  const formattedTokens =
    tokens >= 1e6
      ? `${(tokens / 1e6).toFixed(1)}M`
      : tokens >= 1e3
        ? `${Math.round(tokens / 1e3)}k`
        : `${Math.round(tokens)}`;
  const formattedCost = `$${costUsd < 10 ? costUsd.toFixed(2) : costUsd.toFixed(1)}`;

  return {
    costUsd,
    tokens,
    contextMax,
    formattedCost,
    formattedTokens,
  };
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

/**
 * Extracts subagent runs, tool call breakdowns, and step counts from an
 * Antigravity transcript.jsonl string and optional hook inbox notes.
 *
 * @param {string} [jsonlText]
 * @param {Array<Record<string, any> | string>} [inboxNotes]
 */
export function extractSubagentsFromTranscript(
  jsonlText = "",
  inboxNotes = [],
) {
  let totalSteps = 0;
  let toolCalls = 0;
  const toolsBreakdown = {};
  const subagentsById = new Map();
  const roundCountsByRole = new Map();

  const recordInvoke = (args, meta = {}) => {
    const typeName = String(
      args.TypeName ?? args.subagent_type ?? args.type ?? args.agent ?? "self",
    ).trim();
    const role = String(
      args.Role ?? args.description ?? args.role ?? typeName,
    ).trim();
    const model = String(args.Model ?? args.model ?? "inherit").trim();
    const workspace = String(args.Workspace ?? args.workspace ?? "inherit");
    const normRole = normalizeText(role || typeName);
    const round = (roundCountsByRole.get(normRole) ?? 0) + 1;
    roundCountsByRole.set(normRole, round);

    const id = String(
      meta.conversationId ??
        args.conversationId ??
        meta.id ??
        `subagent-${subagentsById.size + 1}`,
    );
    const tier = inferTier(typeName, role, args.tier);
    const est = estimateRunCost(model, {
      steps: meta.steps ?? 6,
      toolCalls: meta.toolCalls ?? 4,
      ...(meta.usage ?? {}),
    });

    subagentsById.set(id, {
      id,
      type: typeName,
      role,
      tier,
      model,
      workspace,
      round,
      status: meta.status ?? "running",
      messagesSent: 0,
      tokens: est.tokens,
      costUsd: est.costUsd,
      formattedCost: est.formattedCost,
      formattedTokens: est.formattedTokens,
      startedAt: meta.startedAt ?? 0,
    });
  };

  const lines = String(jsonlText ?? "").split("\n");
  for (const line of lines) {
    if (!line.trim()) continue;
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }
    totalSteps += 1;
    const tcs = Array.isArray(entry.tool_calls) ? entry.tool_calls : [];
    for (const tc of tcs) {
      if (!tc || typeof tc !== "object") continue;
      const name = String(tc.name ?? tc.tool_name ?? "unknown");
      toolCalls += 1;
      toolsBreakdown[name] = (toolsBreakdown[name] ?? 0) + 1;
      const args = readToolArgs(tc);
      if (name === "invoke_subagent") {
        recordInvoke(args, {
          id: tc.id ?? tc.tool_call_id ?? `step-${totalSteps}-${toolCalls}`,
          status: entry.status === "ERROR" ? "failed" : "done",
        });
      } else if (name === "send_message") {
        const recipient = String(args.Recipient ?? args.recipient ?? "").trim();
        if (recipient && subagentsById.has(recipient)) {
          const existing = subagentsById.get(recipient);
          existing.messagesSent += 1;
          existing.round += 1;
        }
      }
    }
  }

  for (const rawNote of Array.isArray(inboxNotes) ? inboxNotes : []) {
    let note = rawNote;
    if (typeof rawNote === "string") {
      try {
        note = JSON.parse(rawNote);
      } catch {
        continue;
      }
    }
    if (!note || typeof note !== "object") continue;
    const toolName = String(
      note.tool_name ?? note.toolName ?? note.name ?? "",
    ).trim();
    const args = readToolArgs(
      note.tool_input ? { args: note.tool_input } : note,
    );
    if (toolName === "invoke_subagent" || args.TypeName || args.Role) {
      const normRole = normalizeText(args.Role ?? args.TypeName ?? "");
      const alreadyTracked = [...subagentsById.values()].some(
        (a) => normalizeText(a.role) === normRole && normRole !== "",
      );
      if (!alreadyTracked) {
        recordInvoke(args, {
          id: note.id ?? note.tool_use_id,
          status: note.status ?? "running",
        });
      }
    }
  }

  return {
    totalSteps,
    toolCalls,
    toolsBreakdown,
    subagents: [...subagentsById.values()],
  };
}

/**
 * Summarises the complete Savvy Fleet state for the panel and OpenUI Lang.
 *
 * @param {Record<string, any>} [options]
 */
export function summariseFleetState(options = {}) {
  const opts = options && typeof options === "object" ? options : {};
  const flow = mergeFlowProgress(null, opts.flow ?? {});
  const parsed =
    opts.transcript && typeof opts.transcript === "object"
      ? opts.transcript
      : extractSubagentsFromTranscript(
          String(opts.transcript ?? ""),
          opts.inboxNotes,
        );

  const subagents = Array.isArray(parsed.subagents) ? parsed.subagents : [];
  const startedNorm = new Set(
    subagents.map((a) => normalizeText(a.role || a.type)),
  );
  const planned = flow.isFinished
    ? []
    : (flow.tasks ?? [])
        .map((t, idx) => ({ ...t, number: idx + 1 }))
        .filter((t) => !startedNorm.has(normalizeText(t.title)));

  const runningSubagents = subagents.filter((a) => a.status === "running");
  const finishedSubagents = subagents.filter((a) => a.status !== "running");

  const hostEst = estimateRunCost("gemini-pro", {
    steps: parsed.totalSteps ?? 0,
    toolCalls: parsed.toolCalls ?? 0,
  });
  const fleetCostUsd = subagents.reduce(
    (sum, a) => sum + (Number(a.costUsd) || 0),
    0,
  );
  const fleetTokens = subagents.reduce(
    (sum, a) => sum + (Number(a.tokens) || 0),
    0,
  );
  const totalCostUsd = hostEst.costUsd + fleetCostUsd;
  const totalTokens = hostEst.tokens + fleetTokens;
  const totalsEst = estimateRunCost("opus-5-5", {
    input_tokens: totalTokens,
    output_tokens: 0,
  });

  const progressPct = flow.isFinished
    ? 100
    : flow.total > 0
      ? Math.min(100, Math.round((flow.done / flow.total) * 100))
      : parsed.toolCalls > 0
        ? Math.min(100, Math.round((parsed.toolCalls / 45) * 100))
        : 0;

  return {
    version: String(opts.version ?? ""),
    conversationId: String(opts.conversationId ?? ""),
    connected: Boolean(opts.conversationId || parsed.totalSteps > 0),
    flow: {
      ...flow,
      running: runningSubagents.length || flow.running,
      progressPct,
    },
    totalSteps: parsed.totalSteps ?? 0,
    toolCalls: parsed.toolCalls ?? 0,
    toolsBreakdown: parsed.toolsBreakdown ?? {},
    subagents,
    planned,
    counts: {
      running: runningSubagents.length,
      finished: finishedSubagents.length,
      planned: planned.length,
      total: subagents.length + planned.length,
    },
    totals: {
      costUsd: totalCostUsd,
      formattedCost: `$${totalCostUsd < 10 ? totalCostUsd.toFixed(2) : totalCostUsd.toFixed(1)}`,
      tokens: totalTokens,
      formattedTokens: totalsEst.formattedTokens,
    },
  };
}
