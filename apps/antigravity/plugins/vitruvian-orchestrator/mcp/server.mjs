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

// Minimal stdio MCP server (JSON-RPC 2.0) for vitruvian-orchestrator.
// Exposes `progress` (called by the lead session) and `step` (called by worker
// subagents) and appends contract events to:
//   ~/.gemini/antigravity/vitruvian-orchestrator/flows/<root_conversation_id>.jsonl
//
// Antigravity passes `_meta` on MCP tools/call requests with:
//   - _meta["antigravity.google/root_conversation_id"]: lead conversation UUID
//   - _meta["antigravity.google/conversation_id"]: calling session's own UUID
//     (for a subagent, its worker conversation ID; for the root session, same
//     as root_conversation_id)
//   - _meta["antigravity.google/parent_conversation_id"]: parent UUID when in a subagent
//   - _meta["antigravity.google/agent_name"]: subagent type name (e.g. "wren")
//   - _meta["antigravity.google/artifacts_dir"]: conversation brain directory

import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  realpathSync,
} from "node:fs";
import { homedir } from "node:os";
import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
} from "node:path";
import { fileURLToPath } from "node:url";

import {
  board as boardView,
  initialFlow,
  isValidWorktree,
  reduce,
  remaining,
} from "../sidecars/panel/lib/orchestrator-core.mjs";

export const SERVER_INFO = Object.freeze({
  name: "vitruvian-orchestrator",
  version: "0.2.0",
});

export const TOOLS = Object.freeze([
  Object.freeze({
    name: "progress",
    description:
      "Called by the lead orchestrator to report the task plan, phase transitions, task accept/return review verdicts, and flow completion.",
    inputSchema: {
      type: "object",
      properties: {
        title: {
          type: "string",
          description: "Title of the orchestrated flow.",
        },
        phase: {
          type: "string",
          enum: ["plan", "design", "delegate", "review", "close"],
          description: "Current orchestration phase.",
        },
        tasks: {
          type: "array",
          description: "Planned tasks in 1-based order.",
          items: {
            type: "object",
            properties: {
              title: { type: "string" },
              specialist: { type: "string" },
              tier: { type: "string", enum: ["lead", "core", "fast"] },
              after: {
                type: "array",
                items: { type: "integer" },
              },
              model: {
                type: "string",
                description:
                  "Optional Gemini model override for this task (e.g. gemini-4-carbon-high).",
              },
              worktree: {
                type: "string",
                description:
                  "Optional git worktree branch name for isolating parallel edits.",
              },
            },
            required: ["title", "specialist", "tier"],
          },
        },
        accept: {
          type: "integer",
          description: "1-based task number accepted after review.",
        },
        return: {
          type: "integer",
          description: "1-based task number returned for another pass.",
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
          description: "Set true to close the flow.",
        },
      },
    },
  }),
  Object.freeze({
    name: "step",
    description:
      "Called by a worker subagent about itself to report step progress (done, total, optional note) or pause status (paused: 'quota' | 'error').",
    inputSchema: {
      type: "object",
      properties: {
        done: {
          type: "integer",
          description: "Number of steps completed so far.",
        },
        total: {
          type: "integer",
          description: "Total steps planned for this worker task.",
        },
        note: {
          type: "string",
          description: "Optional short status note for the current step.",
        },
        delegate: {
          type: "string",
          description:
            "Optional delegated model identifier (e.g. gemini-4-carbon-high).",
        },
        delegateUsage: {
          type: "object",
          description: "Optional delegated token usage totals.",
          properties: {
            input: { type: "integer" },
            output: { type: "integer" },
            thinking: { type: "integer" },
            cacheRead: { type: "integer" },
          },
        },
        paused: {
          type: "string",
          enum: ["quota", "error"],
          description:
            "Optional pause reason when blocked ('quota' or 'error').",
        },
        detail: {
          type: "string",
          description: "Optional detail explaining why the member paused.",
        },
        worktree: {
          type: "string",
          description:
            "Optional git worktree branch name created or used by this helper.",
        },
      },
    },
  }),
  Object.freeze({
    name: "post",
    description:
      "Called by the lead or any specialist subagent to post a message to the shared Orchestrator board (results, defect lists, questions, or notes). Supports @name, @all, and @lead mentions.",
    inputSchema: {
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
    },
  }),
  Object.freeze({
    name: "board",
    description:
      "Read posts from the shared Orchestrator board with optional recipient, author, kind, substring, and limit filters.",
    inputSchema: {
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
    },
  }),
]);

export function defaultFlowsDir() {
  if (process.env.VITRUVIAN_ORCH_DIR) {
    return process.env.VITRUVIAN_ORCH_DIR;
  }
  return join(
    homedir(),
    ".gemini",
    "antigravity",
    "vitruvian-orchestrator",
    "flows",
  );
}

const VALID_CONVERSATION_ID_RE = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/;
const VALID_HANDLE_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;
export const MAX_STDIO_FRAME_BYTES = 256 * 1024;

export function sanitizeConversationId(rawId) {
  const trimmed = String(rawId ?? "").trim();
  if (
    !trimmed ||
    trimmed === "." ||
    trimmed === ".." ||
    trimmed.includes("..")
  ) {
    return "";
  }
  return VALID_CONVERSATION_ID_RE.test(trimmed) ? trimmed : "";
}

function canonicalizePathPrefix(p) {
  const raw = String(p ?? "").trim();
  if (!raw) return "";
  const abs = resolve(raw);
  let cur = abs;
  const suffix = [];
  while (true) {
    if (existsSync(cur)) {
      try {
        return join(realpathSync(cur), ...suffix);
      } catch {
        return abs;
      }
    }
    const parent = dirname(cur);
    if (parent === cur) {
      return abs;
    }
    suffix.unshift(basename(cur));
    cur = parent;
  }
}

function knownServerAppDataRoots(brainRoots) {
  const raw = Array.isArray(brainRoots)
    ? brainRoots
    : [
        process.env.ANTIGRAVITY_APP_DATA_DIR,
        join(homedir(), ".gemini", "antigravity"),
        join(homedir(), ".gemini", "antigravity-cli"),
      ];
  return raw.filter(Boolean);
}

function isTrustedArtifactsDir(artifactsDir, brainRoots) {
  const raw = String(artifactsDir ?? "").trim();
  if (!raw) return false;
  if (
    basename(dirname(raw)) !== "brain" ||
    !sanitizeConversationId(basename(raw))
  ) {
    return false;
  }
  const cand = canonicalizePathPrefix(raw);
  if (!cand) return false;
  for (const root of knownServerAppDataRoots(brainRoots)) {
    const canonRoot = canonicalizePathPrefix(root);
    if (!canonRoot) continue;
    const rel = relative(canonRoot, cand);
    if (rel && !rel.startsWith("..") && !isAbsolute(rel)) {
      return true;
    }
  }
  return false;
}

/**
 * Extracts root and calling subagent conversation metadata from MCP `_meta`.
 *
 * @param {Record<string, any> | null | undefined} meta
 * @param {string[]} [brainRoots]
 */
export function extractConversationMeta(meta = {}, brainRoots = undefined) {
  const m = meta && typeof meta === "object" ? meta : {};
  const artifactsDir = String(
    m["antigravity.google/artifacts_dir"] ?? m.artifacts_dir ?? "",
  ).trim();
  const artifactsCid = isTrustedArtifactsDir(artifactsDir, brainRoots)
    ? sanitizeConversationId(basename(artifactsDir))
    : "";
  const envCid = sanitizeConversationId(
    process.env.ANTIGRAVITY_CONVERSATION_ID,
  );

  const rawParent =
    m["antigravity.google/parent_conversation_id"] ??
    m.parent_conversation_id ??
    m.parentConversationId ??
    "";
  const parentConversationId = String(rawParent ?? "").trim();

  const rawAgent =
    m["antigravity.google/agent_name"] ?? m.agent_name ?? m.agentName ?? "";
  const agentName = String(rawAgent ?? "").trim();

  const explicitRoot =
    m["antigravity.google/root_conversation_id"] ??
    m.root_conversation_id ??
    m.rootConversationId ??
    m["antigravity.google/parent_conversation_id"] ??
    (envCid || undefined) ??
    m["antigravity.google/conversation_id"] ??
    (artifactsCid || undefined) ??
    m.conversation_id ??
    m.conversationId;

  const hasExplicitRoot =
    explicitRoot !== undefined && String(explicitRoot).trim() !== "";
  const rootConversationId = !hasExplicitRoot
    ? "default"
    : sanitizeConversationId(explicitRoot);

  const rawMetaCaller =
    m["antigravity.google/conversation_id"] ??
    m.conversation_id ??
    m.conversationId ??
    m.run_id ??
    m.runId ??
    m.id ??
    (artifactsCid || undefined);

  const hasMetaCaller =
    rawMetaCaller !== undefined && String(rawMetaCaller).trim() !== "";
  const callerConversationId = hasMetaCaller
    ? sanitizeConversationId(rawMetaCaller)
    : !parentConversationId && !agentName
      ? envCid
      : "";

  return {
    rootConversationId,
    callerConversationId,
    parentConversationId,
    agentName,
    rawMeta: m,
  };
}

function resolveMemberTarget(ref, flow) {
  const trimmed = String(ref ?? "").trim();
  if (!trimmed) return null;
  const norm = trimmed.replace(/^@+/, "").toLowerCase();
  if (norm === "lead") return null;
  if (flow && Array.isArray(flow.runs)) {
    if (flow.runs.some((r) => r.role === "lead" && r.id === trimmed)) {
      return null;
    }
    const exact = flow.runs.find((r) => r.role !== "lead" && r.id === trimmed);
    if (exact) return { id: exact.id, agent: exact.agent };
    const byPrefix = flow.runs.findLast(
      (r) => r.role !== "lead" && r.id.startsWith(`${trimmed}#`),
    );
    if (byPrefix) return { id: byPrefix.id, agent: byPrefix.agent };
    const activeByAgent = flow.runs.findLast(
      (r) =>
        r.role !== "lead" &&
        String(r.agent ?? "")
          .trim()
          .toLowerCase() === norm &&
        r.memberState !== "killed" &&
        r.memberState !== "retired",
    );
    if (activeByAgent)
      return { id: activeByAgent.id, agent: activeByAgent.agent };
    const anyByAgent = flow.runs.findLast(
      (r) =>
        r.role !== "lead" &&
        String(r.agent ?? "")
          .trim()
          .toLowerCase() === norm,
    );
    if (anyByAgent) return { id: anyByAgent.id, agent: anyByAgent.agent };
  }
  return {
    id: trimmed,
    agent: norm,
  };
}

/**
 * Maps `progress` tool arguments to an ordered list of orchestrator-core events:
 *   tasks -> plan; phase -> phase; accept -> task.accept; return -> task.return;
 *   retire -> member.retire; kill -> member.kill; finished -> close
 *
 * @param {Record<string, any>} args
 * @param {number} at
 * @param {string} [rootConversationId]
 * @param {Record<string, any>} [rawMeta]
 * @param {import("../sidecars/panel/lib/orchestrator-core.mjs").Flow | null} [flow]
 */
export function mapProgressToEvents(
  args = {},
  at = Date.now(),
  rootConversationId = "default",
  rawMeta = undefined,
  flow = undefined,
) {
  const inp = args && typeof args === "object" ? args : {};
  const events = [];
  const metaFields = {
    rootConversationId,
    ...(rawMeta && Object.keys(rawMeta).length > 0 ? { _meta: rawMeta } : {}),
  };

  if (Array.isArray(inp.tasks)) {
    const tasks = inp.tasks.map((t) => ({
      title: String(t?.title ?? "").trim(),
      specialist: String(t?.specialist ?? "wren").trim(),
      tier: t?.tier === "lead" || t?.tier === "fast" ? t.tier : "core",
      after: Array.isArray(t?.after)
        ? t.after.map((n) => Number(n)).filter((n) => Number.isInteger(n))
        : [],
      ...(t?.model !== undefined && t?.model !== null
        ? { model: t.model }
        : {}),
      ...(t?.worktree !== undefined && t?.worktree !== null
        ? { worktree: t.worktree }
        : {}),
    }));
    const planEvent = {
      type: "plan",
      at,
      ...metaFields,
      tasks,
    };
    if (inp.title !== undefined) {
      planEvent.title = String(inp.title).trim();
    }
    events.push(planEvent);
  }

  if (typeof inp.phase === "string" && inp.phase.trim() !== "") {
    events.push({
      type: "phase",
      at,
      ...metaFields,
      phase: inp.phase.trim(),
    });
  }

  if (inp.accept !== undefined && inp.accept !== null) {
    const n = Number(inp.accept);
    if (Number.isInteger(n) && n > 0) {
      events.push({
        type: "task.accept",
        at,
        ...metaFields,
        n,
      });
    }
  }

  if (inp.return !== undefined && inp.return !== null) {
    const n = Number(inp.return);
    if (Number.isInteger(n) && n > 0) {
      events.push({
        type: "task.return",
        at,
        ...metaFields,
        n,
      });
    }
  }

  if (typeof inp.retire === "string" && inp.retire.trim() !== "") {
    const target = resolveMemberTarget(inp.retire, flow);
    if (target) {
      events.push({
        type: "member.retire",
        at,
        ...metaFields,
        id: target.id,
        ...(target.agent ? { agent: target.agent } : {}),
      });
    }
  }

  if (typeof inp.kill === "string" && inp.kill.trim() !== "") {
    const target = resolveMemberTarget(inp.kill, flow);
    if (target) {
      events.push({
        type: "member.kill",
        at,
        ...metaFields,
        id: target.id,
        ...(target.agent ? { agent: target.agent } : {}),
      });
    }
  }

  if (inp.finished === true) {
    events.push({
      type: "close",
      at,
      ...metaFields,
    });
  }

  return events;
}

/**
 * Maps `step` tool arguments and `_meta` to a `run.progress` event.
 * If the caller cannot be matched to a run, returns `{ matched: false, event: null, message }`.
 *
 * @param {Record<string, any>} args
 * @param {Record<string, any>} meta
 * @param {number} at
 * @param {import("../sidecars/panel/lib/orchestrator-core.mjs").Flow | null} [flow]
 */
export function mapStepToEvent(
  args = {},
  meta = {},
  at = Date.now(),
  flow = undefined,
  brainRoots = undefined,
) {
  const inp = args && typeof args === "object" ? args : {};
  const {
    rootConversationId,
    callerConversationId,
    parentConversationId,
    agentName,
    rawMeta,
  } = extractConversationMeta(meta, brainRoots);

  const hasPause = inp.paused === "quota" || inp.paused === "error";
  const hasInvalidPause =
    inp.paused !== undefined && inp.paused !== null && !hasPause;
  const rawWorktree =
    typeof inp.worktree === "string" ? inp.worktree.trim() : "";
  const validWorktree = isValidWorktree(rawWorktree) ? rawWorktree : undefined;
  const hasDelegateUpdate =
    (typeof inp.delegate === "string" && Boolean(inp.delegate.trim())) ||
    Boolean(inp.delegateUsage && typeof inp.delegateUsage === "object");
  const hasOtherField = hasPause || Boolean(validWorktree) || hasDelegateUpdate;
  const hasAnyStepCount = inp.done !== undefined || inp.total !== undefined;
  const hasValidStepCounts =
    typeof inp.done === "number" &&
    Number.isInteger(inp.done) &&
    inp.done >= 0 &&
    typeof inp.total === "number" &&
    Number.isInteger(inp.total) &&
    inp.total >= 1 &&
    inp.done <= inp.total;

  if (
    hasInvalidPause ||
    (hasAnyStepCount && !hasValidStepCounts) ||
    (!hasValidStepCounts && !hasOtherField)
  ) {
    const error =
      "Invalid params: step requires integer done (0 <= done <= total) and total (>= 1), paused ('quota' | 'error'), or a valid worktree";
    return {
      valid: false,
      matched: false,
      rootConversationId,
      event: null,
      events: [],
      error,
      message: error,
    };
  }

  const done = hasValidStepCounts ? inp.done : 0;
  const total = hasValidStepCounts ? inp.total : 0;
  const note = inp.note !== undefined ? String(inp.note) : "";

  let runId = callerConversationId;
  if (flow && Array.isArray(flow.runs)) {
    const directMatch =
      runId &&
      flow.runs.findLast((r) => r.id === runId || r.id.startsWith(`${runId}#`));
    if (directMatch) {
      runId = directMatch.id;
    } else if (agentName) {
      const agentMatch = flow.runs.findLast(
        (r) =>
          r.role === "worker" &&
          r.status === "running" &&
          r.agent === agentName,
      );
      if (agentMatch) {
        runId = agentMatch.id;
      } else if (flow.runs.length > 0 && !parentConversationId) {
        return {
          valid: true,
          matched: false,
          rootConversationId,
          event: null,
          events: [],
          message: `step ignored: caller '${callerConversationId || agentName}' could not be matched to an active run`,
        };
      }
    } else if (flow.runs.length > 0 && !parentConversationId) {
      return {
        valid: true,
        matched: false,
        rootConversationId,
        event: null,
        events: [],
        message: `step ignored: caller '${callerConversationId || "unknown"}' could not be matched to an active run`,
      };
    }
  }

  if (!runId) {
    return {
      valid: true,
      matched: false,
      rootConversationId,
      event: null,
      events: [],
      message: "step ignored: caller could not be matched to a run",
    };
  }

  const metaFields = {
    rootConversationId,
    ...(agentName ? { agent: agentName } : {}),
    ...(rawMeta && Object.keys(rawMeta).length > 0 ? { _meta: rawMeta } : {}),
  };

  const hasStepFields =
    hasValidStepCounts || hasDelegateUpdate || Boolean(validWorktree);

  const events = [];
  if (hasStepFields) {
    events.push({
      type: "run.progress",
      at,
      ...metaFields,
      id: runId,
      ...(hasValidStepCounts
        ? {
            steps: {
              done,
              total,
              note,
            },
          }
        : {}),
      ...(typeof inp.delegate === "string" && inp.delegate.trim()
        ? { delegate: inp.delegate.trim() }
        : {}),
      ...(inp.delegateUsage && typeof inp.delegateUsage === "object"
        ? { delegateTokens: inp.delegateUsage }
        : {}),
      ...(validWorktree ? { worktree: validWorktree } : {}),
    });
  }

  if (hasPause) {
    const detail =
      typeof inp.detail === "string" && inp.detail.trim()
        ? inp.detail.trim()
        : undefined;
    events.push({
      type: "member.pause",
      at,
      ...metaFields,
      id: runId,
      reason: inp.paused,
      ...(detail ? { detail } : {}),
    });
  }

  const event = events[0] ?? null;
  const pauseSuffix = hasPause
    ? ` [paused: ${inp.paused}${inp.detail ? ` — ${String(inp.detail).trim()}` : ""}]`
    : "";

  return {
    valid: true,
    matched: true,
    rootConversationId,
    event,
    events,
    message: hasValidStepCounts
      ? `step updated: ${done}/${total}${note ? ` (${note})` : ""}${pauseSuffix}`
      : hasPause
        ? `step paused: ${inp.paused}${inp.detail ? ` (${String(inp.detail).trim()})` : ""}`
        : `step updated: ${validWorktree ? `worktree ${validWorktree}` : `delegate ${String(inp.delegate ?? "").trim() || "usage"}`}${note ? ` (${note})` : ""}`,
  };
}

/**
 * Maps `post` tool arguments and `_meta` to a `post` event.
 *
 * @param {Record<string, any>} args
 * @param {Record<string, any>} meta
 * @param {number} at
 * @param {import("../sidecars/panel/lib/orchestrator-core.mjs").Flow | null} [flow]
 */
export function mapPostToEvent(
  args = {},
  meta = {},
  at = Date.now(),
  flow = undefined,
  brainRoots = undefined,
) {
  const inp = args && typeof args === "object" ? args : {};
  const {
    rootConversationId,
    callerConversationId,
    parentConversationId,
    agentName,
    rawMeta,
  } = extractConversationMeta(meta, brainRoots);

  const text = typeof inp.text === "string" ? inp.text : "";
  if (text.trim().length === 0) {
    return {
      valid: false,
      rootConversationId,
      event: null,
    };
  }

  let matchedRun = null;
  if (flow && Array.isArray(flow.runs)) {
    if (callerConversationId) {
      matchedRun =
        flow.runs.findLast(
          (r) =>
            r.id === callerConversationId ||
            r.id.startsWith(`${callerConversationId}#`),
        ) ?? null;
    }
    if (!matchedRun && agentName) {
      matchedRun =
        flow.runs.findLast(
          (r) =>
            r.role === "worker" &&
            String(r.agent ?? "").toLowerCase() === agentName.toLowerCase(),
        ) ?? null;
    }
  }

  const matchedWorkerRun =
    matchedRun && matchedRun.role !== "lead" ? matchedRun : null;
  const isLead =
    Boolean(callerConversationId) &&
    Boolean(rootConversationId) &&
    rootConversationId !== "default" &&
    callerConversationId === rootConversationId &&
    !parentConversationId &&
    !agentName &&
    !matchedWorkerRun;
  const isWorker = !isLead;

  let from = "lead";
  if (isWorker) {
    const runCandidate = String(matchedWorkerRun?.agent || "")
      .trim()
      .replace(/^@+/, "")
      .toLowerCase();
    const metaCandidate = String(agentName || "")
      .trim()
      .replace(/^@+/, "")
      .toLowerCase();
    const candidate =
      VALID_HANDLE_RE.test(runCandidate) && runCandidate !== "lead"
        ? runCandidate
        : metaCandidate;
    from =
      VALID_HANDLE_RE.test(candidate) && candidate !== "lead"
        ? candidate
        : "helper";
  }

  const runId =
    matchedWorkerRun?.id ||
    (isWorker && callerConversationId ? callerConversationId : undefined);

  const metaFields = {
    rootConversationId,
    ...(agentName ? { agent: agentName } : {}),
    ...(rawMeta && Object.keys(rawMeta).length > 0 ? { _meta: rawMeta } : {}),
  };

  const event = {
    type: "post",
    at,
    ...metaFields,
    from,
    text,
    ...(Array.isArray(inp.to) ? { to: inp.to } : {}),
    ...(typeof inp.kind === "string" && inp.kind.trim()
      ? { kind: inp.kind.trim() }
      : {}),
    ...(typeof inp.replyTo === "number" &&
    Number.isInteger(inp.replyTo) &&
    inp.replyTo > 0
      ? { replyTo: inp.replyTo }
      : {}),
    ...(runId ? { runId } : {}),
  };

  return {
    valid: true,
    rootConversationId,
    event,
  };
}

/**
 * Queries board posts for the `board` MCP read tool, resolving caller identity
 * for Antigravity worker subagents when `to` is `"me"` or omitted.
 *
 * @param {Record<string, any>} args
 * @param {Record<string, any>} meta
 * @param {import("../sidecars/panel/lib/orchestrator-core.mjs").Flow | null} [flow]
 */
export function queryBoard(
  args = {},
  meta = {},
  flow = undefined,
  brainRoots = undefined,
) {
  const inp = args && typeof args === "object" ? args : {};
  const {
    rootConversationId,
    callerConversationId,
    parentConversationId,
    agentName,
  } = extractConversationMeta(meta, brainRoots);

  let matchedRun = null;
  if (flow && Array.isArray(flow.runs) && callerConversationId) {
    matchedRun =
      flow.runs.findLast(
        (r) =>
          r.role !== "lead" &&
          (r.id === callerConversationId ||
            r.id.startsWith(`${callerConversationId}#`)),
      ) ?? null;
  }

  const isLead =
    Boolean(callerConversationId) &&
    Boolean(rootConversationId) &&
    rootConversationId !== "default" &&
    callerConversationId === rootConversationId &&
    !parentConversationId &&
    !agentName &&
    !matchedRun;
  const isWorker = !isLead;

  let callerAgent = "";
  if (isWorker) {
    const runAgent = String(matchedRun?.agent || "")
      .trim()
      .replace(/^@+/, "")
      .toLowerCase();
    const metaAgent = String(agentName || "")
      .trim()
      .replace(/^@+/, "")
      .toLowerCase();
    if (VALID_HANDLE_RE.test(runAgent) && runAgent !== "lead") {
      callerAgent = runAgent;
    } else if (VALID_HANDLE_RE.test(metaAgent) && metaAgent !== "lead") {
      callerAgent = metaAgent;
    } else if (
      !callerConversationId ||
      runAgent === "lead" ||
      metaAgent === "lead"
    ) {
      callerAgent = "helper";
    }
  }

  const rawTo = typeof inp.to === "string" ? inp.to.trim() : "";
  const normTo = rawTo.replace(/^@+/, "").toLowerCase();
  let effectiveTo;
  if (normTo === "me") {
    effectiveTo = isWorker ? callerAgent || undefined : "lead";
  } else if (rawTo.length > 0) {
    effectiveTo = rawTo;
  } else if (isWorker && callerAgent) {
    effectiveTo = callerAgent;
  }

  const rawLimit =
    typeof inp.limit === "number" && Number.isFinite(inp.limit)
      ? Math.floor(inp.limit)
      : 20;
  const limit = Math.max(1, Math.min(100, rawLimit));

  return boardView(flow ?? null, {
    to: effectiveTo,
    from: typeof inp.from === "string" ? inp.from : undefined,
    kind: typeof inp.kind === "string" ? inp.kind : undefined,
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
  }));
}

function unquoteTranscriptString(val) {
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

function readTranscriptToolArgs(tc) {
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

function parseTranscriptEntryTime(entry, fallbackMs) {
  if (typeof entry?.at === "number" && Number.isFinite(entry.at)) {
    return entry.at;
  }
  if (typeof entry?.created_at === "string" && entry.created_at) {
    const parsed = Date.parse(entry.created_at);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallbackMs;
}

function extractTranscriptRunEventsForServer(transcriptText = "", baseAt = 0) {
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
    const stepAt = parseTranscriptEntryTime(
      entry,
      baseAt > 0 ? baseAt + i * 10 : 0,
    );

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
          leadModel = unquoteTranscriptString(entry.model);
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
      const rawArgs = readTranscriptToolArgs(tc);

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
            unquoteTranscriptString(
              item.TypeName ??
                item.subagent_type ??
                item.type ??
                item.agent ??
                "self",
            ) || "self";
          const title =
            unquoteTranscriptString(
              item.Role ?? item.description ?? item.role ?? agent,
            ) || agent;
          const model =
            unquoteTranscriptString(item.Model ?? item.model ?? "inherit") ||
            "inherit";
          const effort = item.effort
            ? unquoteTranscriptString(item.effort)
            : null;

          const convId =
            createdConvId ||
            unquoteTranscriptString(
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
        const recipient = unquoteTranscriptString(
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
              subagentsByConvId.get(recipient).activeRunId = null;
            } else if (entry.status === "DONE") {
              events.push({
                type: "run.end",
                at: stepAt > 0 ? stepAt + 1 : 0,
                id: nextRunId,
                status: "done",
              });
              subagentsByConvId.get(recipient).activeRunId = null;
            }
          }
        }
      }
    }
  }

  return events;
}

const SERVER_EVENT_ORDER = Object.freeze({
  plan: 0,
  phase: 1,
  "run.start": 2,
  "run.progress": 3,
  "member.pause": 3,
  "run.end": 4,
  post: 5,
  wake: 6,
  "member.retire": 7,
  "member.kill": 7,
  "task.return": 8,
  "task.accept": 9,
  close: 10,
});

function foldServerFlowEvents(flowEvents = [], transcriptEvents = []) {
  const firstPlan = flowEvents.find((e) => e?.type === "plan");
  const baseAt =
    typeof firstPlan?.at === "number" && Number.isFinite(firstPlan.at)
      ? firstPlan.at
      : 1000;

  const existingRunIds = new Set(
    flowEvents
      .filter((e) => e?.type === "run.start" && typeof e.id === "string")
      .map((e) => e.id),
  );

  const normalizedTranscript = [];
  for (let i = 0; i < transcriptEvents.length; i += 1) {
    const ev = transcriptEvents[i];
    if (!ev || typeof ev !== "object") continue;
    if (ev.id && existingRunIds.has(ev.id)) continue;
    const at = typeof ev.at === "number" && ev.at > 0 ? ev.at : baseAt + i + 1;
    normalizedTranscript.push({ ...ev, at });
  }

  const combined =
    normalizedTranscript.length > 0
      ? [...flowEvents, ...normalizedTranscript]
          .map((ev, idx) => ({ ev, idx }))
          .sort((a, b) => {
            const atA = typeof a.ev.at === "number" ? a.ev.at : baseAt;
            const atB = typeof b.ev.at === "number" ? b.ev.at : baseAt;
            if (atA !== atB) return atA - atB;
            const ordA = SERVER_EVENT_ORDER[a.ev.type] ?? 99;
            const ordB = SERVER_EVENT_ORDER[b.ev.type] ?? 99;
            if (ordA !== ordB) return ordA - ordB;
            return a.idx - b.idx;
          })
          .map((item) => item.ev)
      : flowEvents;

  let flow = initialFlow();
  for (const rawEvent of combined) {
    let event = rawEvent;
    if (
      flow &&
      (event.type === "run.progress" || event.type === "member.pause") &&
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
    } else if (
      flow &&
      (event.type === "member.retire" || event.type === "member.kill") &&
      !flow.runs.some((r) => r.id === event.id)
    ) {
      const byPrefix =
        event.id &&
        flow.runs.findLast(
          (r) =>
            r.role !== "lead" &&
            (r.id === event.id || r.id.startsWith(`${event.id}#`)),
        );
      const norm = String(event.agent || event.id || "")
        .trim()
        .replace(/^@+/, "")
        .toLowerCase();
      const activeByAgent =
        !byPrefix &&
        norm &&
        flow.runs.findLast(
          (r) =>
            r.role !== "lead" &&
            String(r.agent ?? "")
              .trim()
              .toLowerCase() === norm &&
            r.memberState !== "killed" &&
            r.memberState !== "retired",
        );
      const anyByAgent =
        !byPrefix &&
        !activeByAgent &&
        norm &&
        flow.runs.findLast(
          (r) =>
            r.role !== "lead" &&
            String(r.agent ?? "")
              .trim()
              .toLowerCase() === norm,
        );
      const target = byPrefix || activeByAgent || anyByAgent;
      if (target) {
        event = { ...event, id: target.id };
      }
    }
    try {
      flow = reduce(flow, event);
    } catch {
      // Ignore malformed event.
    }
  }
  return flow;
}

export function resolveServerBrainRoots(options = {}) {
  const m =
    options?.meta && typeof options.meta === "object" ? options.meta : {};
  const artifactsDir = String(
    m["antigravity.google/artifacts_dir"] ?? m.artifacts_dir ?? "",
  ).trim();
  const knownRoots = knownServerAppDataRoots(options.brainRoots);
  const inferredRoot = isTrustedArtifactsDir(artifactsDir, options.brainRoots)
    ? dirname(dirname(canonicalizePathPrefix(artifactsDir)))
    : "";

  const rawRoots = [inferredRoot, ...knownRoots];
  return [...new Set(rawRoots.filter(Boolean))];
}

function readServerTranscript(conversationId, roots) {
  const safeCid = sanitizeConversationId(conversationId);
  if (!safeCid || safeCid === "default") return "";
  for (const root of roots) {
    const candidate = join(
      root,
      "brain",
      safeCid,
      ".system_generated",
      "logs",
      "transcript.jsonl",
    );
    if (!existsSync(candidate)) continue;
    try {
      return readFileSync(candidate, "utf8");
    } catch {
      // Try next candidate root.
    }
  }
  return "";
}

export function readFlowFromJsonlFile(filePath, options = {}) {
  if (!existsSync(filePath)) return initialFlow();
  const flowEvents = [];
  try {
    const raw = readFileSync(filePath, "utf8");
    for (const line of raw.split("\n")) {
      if (!line.trim()) continue;
      try {
        const parsed = JSON.parse(line);
        if (parsed && typeof parsed === "object") {
          flowEvents.push(parsed);
        }
      } catch {
        // Ignore malformed line.
      }
    }
  } catch {
    return initialFlow();
  }

  const firstPlan = flowEvents.find((e) => e?.type === "plan");
  const baseAt = typeof firstPlan?.at === "number" ? firstPlan.at : 0;
  const roots = resolveServerBrainRoots(options);
  const rootCid = sanitizeConversationId(
    options.conversationId || basename(filePath, ".jsonl"),
  );
  const parentCid = options.parentConversationId
    ? sanitizeConversationId(options.parentConversationId)
    : "";

  const transcriptEvents = [];
  const rootTranscript = readServerTranscript(rootCid, roots);
  if (rootTranscript) {
    transcriptEvents.push(
      ...extractTranscriptRunEventsForServer(rootTranscript, baseAt),
    );
  }
  if (parentCid && parentCid !== "default" && parentCid !== rootCid) {
    const parentTranscript = readServerTranscript(parentCid, roots);
    if (parentTranscript) {
      transcriptEvents.push(
        ...extractTranscriptRunEventsForServer(parentTranscript, baseAt),
      );
    }
  }

  return foldServerFlowEvents(flowEvents, transcriptEvents);
}

export function appendFlowEvents(flowsDir, rootConversationId, events) {
  if (!Array.isArray(events) || events.length === 0) return null;
  const safeId = sanitizeConversationId(rootConversationId);
  if (!safeId) return null;
  mkdirSync(flowsDir, { recursive: true });
  const filePath = join(flowsDir, `${safeId}.jsonl`);
  const payload = events.map((ev) => JSON.stringify(ev)).join("\n") + "\n";
  appendFileSync(filePath, payload, "utf8");
  return filePath;
}

function isKnownWorkerCaller(
  callerConversationId,
  currentFlow,
  flowsDir,
  options,
) {
  if (!callerConversationId) return false;
  const matchesWorker = (f) =>
    Boolean(
      f &&
      Array.isArray(f.runs) &&
      f.runs.some(
        (r) =>
          r.role !== "lead" &&
          (r.id === callerConversationId ||
            r.id.startsWith(`${callerConversationId}#`)),
      ),
    );
  if (matchesWorker(currentFlow)) return true;
  if (!flowsDir || !existsSync(flowsDir)) return false;
  try {
    for (const name of readdirSync(flowsDir)) {
      if (!name.endsWith(".jsonl")) continue;
      const cid = sanitizeConversationId(basename(name, ".jsonl"));
      if (!cid) continue;
      const candidatePath = join(flowsDir, `${cid}.jsonl`);
      const f = readFlowFromJsonlFile(candidatePath, {
        brainRoots: options?.brainRoots,
        conversationId: cid,
      });
      if (matchesWorker(f)) return true;
    }
  } catch {
    return false;
  }
  return false;
}

export function formatFlowSummary(flow) {
  if (!flow) {
    return "flow updated: 0/0 accepted";
  }
  const total = flow.tasks.length;
  const accepted = total - remaining(flow);
  return `flow updated: ${accepted}/${total} accepted`;
}

/**
 * Handles a single JSON-RPC 2.0 request or notification message.
 * Returns a JSON-RPC response object, or `null` for notifications.
 *
 * @param {Record<string, any>} message
 * @param {{ flowsDir?: string, now?: () => number, flow?: any }} [options]
 */
export function handleJsonRpcMessage(message, options = {}) {
  if (!message || typeof message !== "object") {
    return {
      jsonrpc: "2.0",
      id: null,
      error: { code: -32600, message: "Invalid Request" },
    };
  }

  const hasId = Object.prototype.hasOwnProperty.call(message, "id");
  const id = message.id ?? null;
  const method = String(message.method ?? "");
  const params =
    message.params && typeof message.params === "object" ? message.params : {};

  if (!hasId) {
    // JSON-RPC notification (e.g., notifications/initialized)
    return null;
  }

  if (method === "initialize") {
    const protocolVersion =
      typeof params.protocolVersion === "string" && params.protocolVersion
        ? params.protocolVersion
        : "2024-11-05";
    return {
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion,
        capabilities: {
          tools: {},
        },
        serverInfo: SERVER_INFO,
      },
    };
  }

  if (method === "ping") {
    return {
      jsonrpc: "2.0",
      id,
      result: {},
    };
  }

  if (method === "tools/list") {
    return {
      jsonrpc: "2.0",
      id,
      result: {
        tools: TOOLS,
      },
    };
  }

  if (method === "tools/call") {
    const toolName = String(params.name ?? "");
    const toolArgs =
      params.arguments && typeof params.arguments === "object"
        ? params.arguments
        : {};
    const meta =
      params._meta && typeof params._meta === "object"
        ? params._meta
        : message._meta && typeof message._meta === "object"
          ? message._meta
          : {};
    const flowsDir = options.flowsDir || defaultFlowsDir();
    const at = typeof options.now === "function" ? options.now() : Date.now();

    if (toolName === "progress") {
      const {
        rootConversationId,
        callerConversationId,
        parentConversationId,
        agentName,
        rawMeta,
      } = extractConversationMeta(meta, options.brainRoots);
      const isMetaHelper =
        Boolean(parentConversationId) ||
        Boolean(agentName) ||
        (Boolean(callerConversationId) &&
          Boolean(rootConversationId) &&
          callerConversationId !== rootConversationId);
      if (isMetaHelper) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: "progress is for the lead only",
          },
        };
      }
      if (
        !callerConversationId ||
        !rootConversationId ||
        rootConversationId === "default" ||
        callerConversationId !== rootConversationId
      ) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: "progress is for the lead only: caller unknown",
          },
        };
      }
      const loaderOpts = {
        brainRoots: options.brainRoots,
        meta,
        conversationId: rootConversationId,
        parentConversationId,
      };
      const existingPath = join(flowsDir, `${rootConversationId}.jsonl`);
      const currentFlow =
        options.flow !== undefined
          ? options.flow
          : existsSync(existingPath)
            ? readFlowFromJsonlFile(existingPath, loaderOpts)
            : undefined;
      if (
        isKnownWorkerCaller(
          callerConversationId,
          currentFlow,
          flowsDir,
          options,
        )
      ) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: "progress is for the lead only",
          },
        };
      }
      const events = mapProgressToEvents(
        toolArgs,
        at,
        rootConversationId,
        rawMeta,
        currentFlow,
      );
      const filePath =
        appendFlowEvents(flowsDir, rootConversationId, events) || existingPath;
      const flow = readFlowFromJsonlFile(filePath, loaderOpts);
      const text = formatFlowSummary(flow);
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text }],
        },
      };
    }

    if (toolName === "step") {
      const { rootConversationId, parentConversationId } =
        extractConversationMeta(meta, options.brainRoots);
      if (!rootConversationId) {
        return {
          jsonrpc: "2.0",
          id,
          result: {
            content: [
              {
                type: "text",
                text: "step ignored: invalid conversation id",
              },
            ],
          },
        };
      }
      const loaderOpts = {
        brainRoots: options.brainRoots,
        meta,
        conversationId: rootConversationId,
        parentConversationId,
      };
      const filePath = join(flowsDir, `${rootConversationId}.jsonl`);
      const currentFlow =
        options.flow !== undefined
          ? options.flow
          : existsSync(filePath)
            ? readFlowFromJsonlFile(filePath, loaderOpts)
            : undefined;
      const mapped = mapStepToEvent(
        toolArgs,
        meta,
        at,
        currentFlow,
        options.brainRoots,
      );
      if (mapped.valid === false) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: mapped.error,
          },
        };
      }
      const toAppend =
        Array.isArray(mapped.events) && mapped.events.length > 0
          ? mapped.events
          : mapped.event
            ? [mapped.event]
            : [];
      if (mapped.matched && toAppend.length > 0) {
        appendFlowEvents(flowsDir, mapped.rootConversationId, toAppend);
      }
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: mapped.message }],
        },
      };
    }

    if (toolName === "post") {
      const { rootConversationId, parentConversationId } =
        extractConversationMeta(meta, options.brainRoots);
      if (!rootConversationId) {
        return {
          jsonrpc: "2.0",
          id,
          result: {
            content: [{ type: "text", text: JSON.stringify({ seq: 0 }) }],
          },
        };
      }
      const loaderOpts = {
        brainRoots: options.brainRoots,
        meta,
        conversationId: rootConversationId,
        parentConversationId,
      };
      const filePath = join(flowsDir, `${rootConversationId}.jsonl`);
      const currentFlow =
        options.flow !== undefined
          ? options.flow
          : existsSync(filePath)
            ? readFlowFromJsonlFile(filePath, loaderOpts)
            : undefined;
      const mapped = mapPostToEvent(
        toolArgs,
        meta,
        at,
        currentFlow,
        options.brainRoots,
      );
      if (!mapped.valid || !mapped.event) {
        return {
          jsonrpc: "2.0",
          id,
          result: {
            content: [{ type: "text", text: JSON.stringify({ seq: 0 }) }],
          },
        };
      }
      appendFlowEvents(flowsDir, mapped.rootConversationId, [mapped.event]);
      const nextFlow = readFlowFromJsonlFile(filePath, loaderOpts);
      let seq = nextFlow?.posts?.[nextFlow.posts.length - 1]?.seq ?? 0;
      if (!seq && existsSync(filePath)) {
        try {
          seq = readFileSync(filePath, "utf8")
            .split("\n")
            .filter((line) => {
              if (!line.trim()) return false;
              try {
                const parsed = JSON.parse(line);
                return (
                  parsed?.type === "post" &&
                  typeof parsed.text === "string" &&
                  parsed.text.trim().length > 0
                );
              } catch {
                return false;
              }
            }).length;
        } catch {
          seq = 1;
        }
      }
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify({ seq }) }],
        },
      };
    }

    if (toolName === "board") {
      const { rootConversationId, parentConversationId } =
        extractConversationMeta(meta, options.brainRoots);
      if (!rootConversationId) {
        return {
          jsonrpc: "2.0",
          id,
          result: {
            content: [{ type: "text", text: "[]" }],
          },
        };
      }
      const loaderOpts = {
        brainRoots: options.brainRoots,
        meta,
        conversationId: rootConversationId,
        parentConversationId,
      };
      const filePath = join(flowsDir, `${rootConversationId}.jsonl`);
      const currentFlow =
        options.flow !== undefined
          ? options.flow
          : existsSync(filePath)
            ? readFlowFromJsonlFile(filePath, loaderOpts)
            : null;
      const rows = queryBoard(toolArgs, meta, currentFlow, options.brainRoots);
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify(rows) }],
        },
      };
    }

    return {
      jsonrpc: "2.0",
      id,
      error: {
        code: -32601,
        message: `Unknown tool: ${toolName}`,
      },
    };
  }

  return {
    jsonrpc: "2.0",
    id,
    error: {
      code: -32601,
      message: `Method not found: ${method}`,
    },
  };
}

/**
 * Parses incoming stdio data supporting both newline-delimited JSON (MCP standard)
 * and Content-Length header framing, rejecting frames larger than `MAX_STDIO_FRAME_BYTES` (256 KB).
 *
 * @param {string} buffer
 * @returns {{ messages: any[], errors: any[], rest: string, mode: "ndjson" | "content-length", discardUntilNewline?: boolean }}
 */
export function parseJsonRpcFrames(buffer) {
  let rest = String(buffer ?? "");
  const messages = [];
  const errors = [];
  let mode = "ndjson";
  let discardUntilNewline = false;

  const makeOversizedError = () => ({
    jsonrpc: "2.0",
    id: null,
    error: {
      code: -32600,
      message: `Frame exceeds maximum size of ${MAX_STDIO_FRAME_BYTES} bytes`,
    },
  });

  while (rest.length > 0) {
    const leadingTrimmed = rest.replace(/^[ \t\r\n]+/, "");
    if (!leadingTrimmed) {
      rest = "";
      break;
    }

    if (/^Content-Length:/i.test(leadingTrimmed)) {
      mode = "content-length";
      rest = leadingTrimmed;
      const sepMatch = /\r?\n\r?\n/.exec(rest);
      if (!sepMatch) {
        if (Buffer.byteLength(rest, "utf8") > MAX_STDIO_FRAME_BYTES) {
          errors.push(makeOversizedError());
          rest = "";
        }
        break;
      }
      const headerBlock = rest.slice(0, sepMatch.index);
      const lenMatch = /Content-Length:\s*(\d+)/i.exec(headerBlock);
      if (!lenMatch) {
        rest = rest.slice(sepMatch.index + sepMatch[0].length);
        continue;
      }
      const byteLength = Number(lenMatch[1]);
      const bodyStart = sepMatch.index + sepMatch[0].length;
      const bodyBuf = Buffer.from(rest, "utf8");
      const headerByteLen = Buffer.byteLength(rest.slice(0, bodyStart), "utf8");
      if (
        !Number.isFinite(byteLength) ||
        byteLength > MAX_STDIO_FRAME_BYTES ||
        headerByteLen > MAX_STDIO_FRAME_BYTES
      ) {
        errors.push(makeOversizedError());
        if (
          Number.isFinite(byteLength) &&
          bodyBuf.length >= headerByteLen + byteLength
        ) {
          rest = bodyBuf.subarray(headerByteLen + byteLength).toString("utf8");
          continue;
        }
        rest = "";
        break;
      }
      if (bodyBuf.length < headerByteLen + byteLength) {
        break;
      }
      const jsonText = bodyBuf
        .subarray(headerByteLen, headerByteLen + byteLength)
        .toString("utf8");
      rest = bodyBuf.subarray(headerByteLen + byteLength).toString("utf8");
      try {
        messages.push(JSON.parse(jsonText));
      } catch {
        // Ignore malformed frame payload.
      }
      continue;
    }

    const newlineIdx = rest.indexOf("\n");
    if (newlineIdx === -1) {
      if (Buffer.byteLength(rest, "utf8") > MAX_STDIO_FRAME_BYTES) {
        errors.push(makeOversizedError());
        rest = "";
        discardUntilNewline = true;
      }
      break;
    }
    const rawLine = rest.slice(0, newlineIdx);
    rest = rest.slice(newlineIdx + 1);
    if (Buffer.byteLength(rawLine, "utf8") > MAX_STDIO_FRAME_BYTES) {
      errors.push(makeOversizedError());
      continue;
    }
    const line = rawLine.trim();
    if (!line) continue;
    try {
      messages.push(JSON.parse(line));
    } catch {
      // Ignore malformed JSON line.
    }
  }

  return { messages, errors, rest, mode, discardUntilNewline };
}

/**
 * Formats a JSON-RPC response object for stdio output.
 *
 * @param {Record<string, any>} message
 * @param {"ndjson" | "content-length"} [mode]
 */
export function formatJsonRpcFrame(message, mode = "ndjson") {
  const json = JSON.stringify(message);
  if (mode === "content-length") {
    const byteLength = Buffer.byteLength(json, "utf8");
    return `Content-Length: ${byteLength}\r\n\r\n${json}`;
  }
  return `${json}\n`;
}

export function startStdioServer(options = {}) {
  let buffer = "";
  let discardUntilNewline = false;
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => {
    let incoming = String(chunk ?? "");
    if (discardUntilNewline) {
      const nl = incoming.indexOf("\n");
      if (nl === -1) {
        return;
      }
      incoming = incoming.slice(nl + 1);
      discardUntilNewline = false;
    }
    buffer += incoming;
    const parsed = parseJsonRpcFrames(buffer);
    buffer = parsed.rest;
    if (parsed.discardUntilNewline) {
      discardUntilNewline = true;
    }
    for (const errResp of parsed.errors) {
      process.stdout.write(formatJsonRpcFrame(errResp, parsed.mode));
    }
    for (const msg of parsed.messages) {
      const response = handleJsonRpcMessage(msg, options);
      if (response) {
        process.stdout.write(formatJsonRpcFrame(response, parsed.mode));
      }
    }
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
  startStdioServer();
}
