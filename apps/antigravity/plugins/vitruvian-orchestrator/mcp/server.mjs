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
  readFileSync,
  realpathSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  initialFlow,
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
      "Called by a worker subagent about itself to report step progress (done, total, optional note).",
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
      },
      required: ["done", "total"],
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

export function sanitizeConversationId(rawId) {
  const cleaned = String(rawId ?? "")
    .trim()
    .replace(/[^a-zA-Z0-9._-]/g, "");
  return cleaned || "default";
}

/**
 * Extracts root and calling subagent conversation metadata from MCP `_meta`.
 *
 * @param {Record<string, any> | null | undefined} meta
 */
export function extractConversationMeta(meta = {}) {
  const m = meta && typeof meta === "object" ? meta : {};
  const artifactsDir = String(
    m["antigravity.google/artifacts_dir"] ?? m.artifacts_dir ?? "",
  ).trim();
  const artifactsCid = artifactsDir ? basename(artifactsDir) : "";

  const rawRoot =
    m["antigravity.google/root_conversation_id"] ??
    m.root_conversation_id ??
    m.rootConversationId ??
    m["antigravity.google/parent_conversation_id"] ??
    m["antigravity.google/conversation_id"] ??
    (artifactsCid || undefined) ??
    m.conversation_id ??
    m.conversationId ??
    process.env.ANTIGRAVITY_CONVERSATION_ID ??
    "default";

  const rawCaller =
    m["antigravity.google/conversation_id"] ??
    m.conversation_id ??
    m.conversationId ??
    m.run_id ??
    m.runId ??
    m.id ??
    (artifactsCid || "");

  const rawParent =
    m["antigravity.google/parent_conversation_id"] ??
    m.parent_conversation_id ??
    m.parentConversationId ??
    "";

  const rawAgent =
    m["antigravity.google/agent_name"] ?? m.agent_name ?? m.agentName ?? "";

  return {
    rootConversationId: sanitizeConversationId(rawRoot),
    callerConversationId: String(rawCaller ?? "").trim(),
    parentConversationId: String(rawParent ?? "").trim(),
    agentName: String(rawAgent ?? "").trim(),
    rawMeta: m,
  };
}

/**
 * Maps `progress` tool arguments to an ordered list of orchestrator-core events:
 *   tasks -> plan; phase -> phase; accept -> task.accept; return -> task.return; finished -> close
 *
 * @param {Record<string, any>} args
 * @param {number} at
 * @param {string} [rootConversationId]
 * @param {Record<string, any>} [rawMeta]
 */
export function mapProgressToEvents(
  args = {},
  at = Date.now(),
  rootConversationId = "default",
  rawMeta = undefined,
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
) {
  const inp = args && typeof args === "object" ? args : {};
  const {
    rootConversationId,
    callerConversationId,
    parentConversationId,
    agentName,
    rawMeta,
  } = extractConversationMeta(meta);

  const done = Math.max(0, Math.trunc(Number(inp.done ?? 0) || 0));
  const total = Math.max(0, Math.trunc(Number(inp.total ?? 0) || 0));
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
          matched: false,
          rootConversationId,
          event: null,
          message: `step ignored: caller '${callerConversationId || agentName}' could not be matched to an active run`,
        };
      }
    } else if (flow.runs.length > 0 && !parentConversationId) {
      return {
        matched: false,
        rootConversationId,
        event: null,
        message: `step ignored: caller '${callerConversationId || "unknown"}' could not be matched to an active run`,
      };
    }
  }

  if (!runId) {
    return {
      matched: false,
      rootConversationId,
      event: null,
      message: "step ignored: caller could not be matched to a run",
    };
  }

  const metaFields = {
    rootConversationId,
    ...(agentName ? { agent: agentName } : {}),
    ...(rawMeta && Object.keys(rawMeta).length > 0 ? { _meta: rawMeta } : {}),
  };

  const event = {
    type: "run.progress",
    at,
    ...metaFields,
    id: runId,
    steps: {
      done,
      total,
      note,
    },
  };

  return {
    matched: true,
    rootConversationId,
    event,
    message: `step updated: ${done}/${total}${note ? ` (${note})` : ""}`,
  };
}

export function readFlowFromJsonlFile(filePath) {
  if (!existsSync(filePath)) return initialFlow();
  let flow = initialFlow();
  try {
    const raw = readFileSync(filePath, "utf8");
    for (const line of raw.split("\n")) {
      if (!line.trim()) continue;
      try {
        flow = reduce(flow, JSON.parse(line));
      } catch {
        // Ignore malformed line.
      }
    }
  } catch {
    return initialFlow();
  }
  return flow;
}

export function appendFlowEvents(flowsDir, rootConversationId, events) {
  if (!Array.isArray(events) || events.length === 0) return null;
  mkdirSync(flowsDir, { recursive: true });
  const safeId = sanitizeConversationId(rootConversationId);
  const filePath = join(flowsDir, `${safeId}.jsonl`);
  const payload = events.map((ev) => JSON.stringify(ev)).join("\n") + "\n";
  appendFileSync(filePath, payload, "utf8");
  return filePath;
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
      const { rootConversationId, rawMeta } = extractConversationMeta(meta);
      const events = mapProgressToEvents(
        toolArgs,
        at,
        rootConversationId,
        rawMeta,
      );
      const filePath =
        appendFlowEvents(flowsDir, rootConversationId, events) ||
        join(flowsDir, `${rootConversationId}.jsonl`);
      const flow = readFlowFromJsonlFile(filePath);
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
      const { rootConversationId } = extractConversationMeta(meta);
      const filePath = join(flowsDir, `${rootConversationId}.jsonl`);
      const currentFlow =
        options.flow !== undefined
          ? options.flow
          : existsSync(filePath)
            ? readFlowFromJsonlFile(filePath)
            : undefined;
      const mapped = mapStepToEvent(toolArgs, meta, at, currentFlow);
      if (mapped.matched && mapped.event) {
        appendFlowEvents(flowsDir, mapped.rootConversationId, [mapped.event]);
      }
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: mapped.message }],
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
 * and Content-Length header framing.
 *
 * @param {string} buffer
 * @returns {{ messages: any[], rest: string, mode: "ndjson" | "content-length" }}
 */
export function parseJsonRpcFrames(buffer) {
  let rest = String(buffer ?? "");
  const messages = [];
  let mode = "ndjson";

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
      if (!sepMatch) break;
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
      break;
    }
    const line = rest.slice(0, newlineIdx).trim();
    rest = rest.slice(newlineIdx + 1);
    if (!line) continue;
    try {
      messages.push(JSON.parse(line));
    } catch {
      // Ignore malformed JSON line.
    }
  }

  return { messages, rest, mode };
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
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => {
    buffer += chunk;
    const parsed = parseJsonRpcFrames(buffer);
    buffer = parsed.rest;
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
