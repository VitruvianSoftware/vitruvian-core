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

// Pure rule parser, condition evaluator, and PreToolUse / Stop decision engine
// for the hookify Antigravity plugin.

export const SUPPORTED_OPERATORS = [
  "regex_match",
  "contains",
  "not_contains",
  "equals",
  "starts_with",
  "ends_with",
];

export const SUPPORTED_ACTIONS = [
  "allow",
  "warn",
  "ask",
  "force_ask",
  "block",
  "deny",
  "overwrite",
];

function stripQuotes(val) {
  const trimmed = String(val ?? "").trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed
      .slice(1, -1)
      .replaceAll('\\"', '"')
      .replaceAll("\\\\", "\\")
      .replaceAll("\\n", "\n")
      .replaceAll("\\t", "\t");
  }
  return trimmed;
}

function parseScalar(raw) {
  const s = String(raw ?? "").trim();
  if (s === "true") return true;
  if (s === "false") return false;
  if (s === "null") return null;
  if (/^-?\d+(\.\d+)?$/.test(s)) return Number(s);
  return stripQuotes(s);
}

/**
 * Parses a `.agents/hookify.<name>.md` markdown document with YAML frontmatter
 * and a markdown message body into a normalized Hookify rule object.
 *
 * @param {string} markdown
 * @param {string} [sourcePath]
 * @returns {Record<string, any> | null}
 */
export function parseHookifyMarkdown(markdown, sourcePath = "") {
  const text = String(markdown ?? "").replaceAll("\r\n", "\n");
  const match = text.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!match) return null;

  const frontmatter = match[1];
  const body = match[2].trim();
  const lines = frontmatter.split("\n");

  const meta = {};
  let currentListKey = null;
  let currentItem = null;
  let currentMapKey = null;

  for (const rawLine of lines) {
    if (!rawLine.trim() || rawLine.trim().startsWith("#")) continue;
    const indent = rawLine.match(/^(\s*)/)[1].length;
    const line = rawLine.trim();

    if (indent === 0) {
      currentListKey = null;
      currentItem = null;
      currentMapKey = null;
      const kv = line.match(/^([A-Za-z0-9_-]+)\s*:\s*(.*)$/);
      if (!kv) continue;
      const [, key, rest] = kv;
      if (rest === "") {
        if (key === "conditions") {
          meta[key] = [];
          currentListKey = key;
        } else {
          meta[key] = {};
          currentMapKey = key;
        }
      } else {
        meta[key] = parseScalar(rest);
      }
      continue;
    }

    if (currentListKey) {
      if (line.startsWith("- ")) {
        currentItem = {};
        meta[currentListKey].push(currentItem);
        const afterDash = line.slice(2).trim();
        const kv = afterDash.match(/^([A-Za-z0-9_-]+)\s*:\s*(.*)$/);
        if (kv) {
          currentItem[kv[1]] = parseScalar(kv[2]);
        }
      } else if (currentItem) {
        const kv = line.match(/^([A-Za-z0-9_-]+)\s*:\s*(.*)$/);
        if (kv) {
          currentItem[kv[1]] = parseScalar(kv[2]);
        }
      }
      continue;
    }

    if (currentMapKey) {
      const kv = line.match(/^([A-Za-z0-9_.-]+)\s*:\s*(.*)$/);
      if (kv) {
        meta[currentMapKey][kv[1]] = parseScalar(kv[2]);
      }
    }
  }

  const fallbackName = sourcePath
    ? sourcePath
        .split("/")
        .pop()
        .replace(/^hookify\./, "")
        .replace(/\.md$/, "")
    : "unnamed-rule";

  const name = String(meta.name || fallbackName).trim();
  const event = String(meta.event || "PreToolUse").trim();
  const action = String(meta.action || "warn")
    .trim()
    .toLowerCase();
  const enabled = meta.enabled !== false;

  const conditions = Array.isArray(meta.conditions)
    ? meta.conditions.filter((c) => c && typeof c === "object")
    : [];

  if (conditions.length === 0 && meta.pattern !== undefined) {
    const defaultField =
      event.toLowerCase() === "bash"
        ? "CommandLine"
        : event.toLowerCase() === "file"
          ? "Content"
          : "CommandLine";
    conditions.push({
      field: String(meta.field || defaultField),
      operator: String(meta.operator || "regex_match"),
      pattern: String(meta.pattern),
    });
  }

  return {
    id: String(meta.id || name),
    name,
    enabled,
    event,
    tool: meta.tool
      ? String(meta.tool)
      : meta.matcher
        ? String(meta.matcher)
        : "*",
    action,
    conditions,
    overwrite:
      meta.overwrite && typeof meta.overwrite === "object"
        ? meta.overwrite
        : undefined,
    message: body || String(meta.message || `Rule '${name}' triggered.`),
    source: sourcePath || "markdown",
  };
}

/**
 * Serializes a Hookify rule object back to `.agents/hookify.<name>.md` markdown.
 *
 * @param {Record<string, any>} rule
 * @returns {string}
 */
export function serializeHookifyMarkdown(rule) {
  const r = rule && typeof rule === "object" ? rule : {};
  const name = String(r.name || r.id || "unnamed-rule");
  const enabled = r.enabled !== false;
  const event = String(r.event || "PreToolUse");
  const action = String(r.action || "warn");
  const tool = String(r.tool || r.matcher || "*");
  const lines = [
    "---",
    `name: ${name}`,
    `enabled: ${enabled}`,
    `event: ${event}`,
  ];
  if (tool && tool !== "*") {
    lines.push(`tool: ${tool}`);
  }
  lines.push(`action: ${action}`);

  const conditions = Array.isArray(r.conditions) ? r.conditions : [];
  if (conditions.length > 0) {
    lines.push("conditions:");
    for (const c of conditions) {
      if (!c || typeof c !== "object") continue;
      const pat = JSON.stringify(String(c.pattern ?? ""));
      lines.push(`  - field: ${c.field || "CommandLine"}`);
      lines.push(`    operator: ${c.operator || "regex_match"}`);
      lines.push(`    pattern: ${pat}`);
    }
  } else if (r.pattern) {
    lines.push(`pattern: ${JSON.stringify(String(r.pattern))}`);
  }

  if (r.overwrite && typeof r.overwrite === "object") {
    lines.push("overwrite:");
    for (const [k, v] of Object.entries(r.overwrite)) {
      lines.push(`  ${k}: ${JSON.stringify(v)}`);
    }
  }

  lines.push("---");
  lines.push(String(r.message || `Rule '${name}' triggered.`).trim());
  lines.push("");
  return lines.join("\n");
}

/**
 * Extracts a logical field from an Antigravity or Claude Code hook payload.
 *
 * @param {Record<string, any>} payload
 * @param {string} field
 * @returns {string}
 */
export function extractFieldFromPayload(payload, field) {
  const p = payload && typeof payload === "object" ? payload : {};
  const args =
    p.toolCall?.args && typeof p.toolCall.args === "object"
      ? p.toolCall.args
      : p.tool_input && typeof p.tool_input === "object"
        ? p.tool_input
        : {};
  const key = String(field || "CommandLine").trim();
  const lower = key.toLowerCase();

  if (key in args && args[key] !== undefined && args[key] !== null) {
    return String(args[key]);
  }
  if (key in p && p[key] !== undefined && p[key] !== null) {
    return typeof p[key] === "object" ? JSON.stringify(p[key]) : String(p[key]);
  }

  if (lower === "command" || lower === "commandline" || lower === "cmd") {
    return String(args.CommandLine ?? args.command ?? p.command ?? "");
  }
  if (
    lower === "file_path" ||
    lower === "filepath" ||
    lower === "path" ||
    lower === "file"
  ) {
    return String(
      args.Path ?? args.file_path ?? args.path ?? p.file_path ?? "",
    );
  }
  if (lower === "content" || lower === "new_text" || lower === "replacement") {
    return String(
      args.Content ??
        args.Replacement ??
        args.content ??
        args.new_string ??
        args.new_str ??
        "",
    );
  }
  if (lower === "target" || lower === "old_text" || lower === "old_string") {
    return String(args.Target ?? args.old_string ?? args.old_str ?? "");
  }
  if (lower === "tool" || lower === "tool_name" || lower === "toolname") {
    return String(p.toolCall?.name ?? p.tool_name ?? "");
  }
  if (lower === "reason" || lower === "stop_reason" || lower === "transcript") {
    return String(
      p.reason ?? p.stop_reason ?? p.transcript ?? p.lastMessage ?? "",
    );
  }

  return "";
}

/**
 * Evaluates a single condition against a hook payload.
 *
 * @param {{ field?: string, operator?: string, pattern?: string, caseSensitive?: boolean }} condition
 * @param {Record<string, any>} payload
 * @returns {boolean}
 */
export function evaluateCondition(condition, payload) {
  if (!condition || typeof condition !== "object") return false;
  const field = condition.field || "CommandLine";
  const operator = String(condition.operator || "regex_match")
    .trim()
    .toLowerCase();
  const pattern = String(condition.pattern ?? "");
  const rawValue = extractFieldFromPayload(payload, field);
  const caseSensitive = condition.caseSensitive === true;

  const value = caseSensitive ? rawValue : rawValue.toLowerCase();
  const target = caseSensitive ? pattern : pattern.toLowerCase();

  switch (operator) {
    case "regex_match": {
      try {
        const flags = caseSensitive ? "" : "i";
        const re = new RegExp(pattern, flags);
        return re.test(rawValue);
      } catch {
        return false;
      }
    }
    case "contains":
      return value.includes(target);
    case "not_contains":
      return !value.includes(target);
    case "equals":
      return value === target;
    case "starts_with":
      return value.startsWith(target);
    case "ends_with":
      return value.endsWith(target);
    default:
      return false;
  }
}

function matchesEventAndTool(rule, payload, phase) {
  const ruleEvent = String(rule.event || "PreToolUse")
    .trim()
    .toLowerCase();
  const toolName = String(
    payload?.toolCall?.name ?? payload?.tool_name ?? "",
  ).trim();

  if (phase === "Stop") {
    return ruleEvent === "stop" || ruleEvent === "all" || ruleEvent === "*";
  }

  if (ruleEvent === "stop") return false;
  if (ruleEvent === "bash") {
    if (
      toolName &&
      !["run_command", "bash", "execute_command"].includes(
        toolName.toLowerCase(),
      )
    ) {
      return false;
    }
  } else if (ruleEvent === "file") {
    if (
      toolName &&
      ![
        "write_file",
        "edit_file",
        "multi_edit",
        "write",
        "edit",
        "replace",
      ].includes(toolName.toLowerCase())
    ) {
      return false;
    }
  }

  const matcher = String(rule.tool || rule.matcher || "*").trim();
  if (!matcher || matcher === "*" || matcher.toLowerCase() === "all") {
    return true;
  }
  if (!toolName) return false;
  try {
    const re = new RegExp(`^(${matcher})$`, "i");
    return re.test(toolName);
  } catch {
    return matcher.toLowerCase() === toolName.toLowerCase();
  }
}

function normalizeDecision(action) {
  const a = String(action || "warn")
    .trim()
    .toLowerCase();
  if (a === "block" || a === "deny") return "deny";
  if (a === "force_ask") return "force_ask";
  if (a === "warn" || a === "ask") return "ask";
  if (a === "overwrite") return "overwrite";
  if (a === "allow") return "allow";
  return "ask";
}

function computeOverwrittenInput(rule, currentArgs) {
  const args = {
    ...(currentArgs && typeof currentArgs === "object" ? currentArgs : {}),
  };
  const spec = rule.overwrite;
  if (!spec || typeof spec !== "object") return args;

  if (
    typeof spec.field === "string" &&
    typeof spec.find === "string" &&
    spec.replace !== undefined
  ) {
    const fieldName = spec.field;
    const prev = String(args[fieldName] ?? "");
    try {
      const re = new RegExp(spec.find, "g");
      args[fieldName] = prev.replace(re, String(spec.replace));
    } catch {
      args[fieldName] = prev.replaceAll(spec.find, String(spec.replace));
    }
    return args;
  }

  for (const [key, val] of Object.entries(spec)) {
    args[key] = val;
  }
  return args;
}

/**
 * Evaluates a single Hookify rule against a payload.
 *
 * @param {Record<string, any>} rule
 * @param {Record<string, any>} payload
 * @param {"PreToolUse" | "Stop"} [phase="PreToolUse"]
 * @returns {{ matched: boolean, ruleId: string, ruleName: string, action: string, decision: string, message: string, updatedInput?: Record<string, any> }}
 */
export function evaluateRule(rule, payload, phase = "PreToolUse") {
  const r = rule && typeof rule === "object" ? rule : {};
  const ruleId = String(r.id || r.name || "unnamed");
  const ruleName = String(r.name || ruleId);
  const action = String(r.action || "warn").toLowerCase();
  const decision = normalizeDecision(action);
  const message = String(r.message || `Rule '${ruleName}' matched.`);

  if (r.enabled === false) {
    return { matched: false, ruleId, ruleName, action, decision, message };
  }
  if (!matchesEventAndTool(r, payload, phase)) {
    return { matched: false, ruleId, ruleName, action, decision, message };
  }

  const conditions = Array.isArray(r.conditions) ? r.conditions : [];
  const effectiveConditions =
    conditions.length > 0
      ? conditions
      : r.pattern
        ? [
            {
              field: r.field || (phase === "Stop" ? "reason" : "CommandLine"),
              operator: r.operator || "regex_match",
              pattern: r.pattern,
            },
          ]
        : [];

  if (effectiveConditions.length === 0) {
    return { matched: false, ruleId, ruleName, action, decision, message };
  }

  const allMatch = effectiveConditions.every((cond) =>
    evaluateCondition(cond, payload),
  );
  if (!allMatch) {
    return { matched: false, ruleId, ruleName, action, decision, message };
  }

  const rawArgs =
    payload?.toolCall?.args && typeof payload.toolCall.args === "object"
      ? payload.toolCall.args
      : payload?.tool_input && typeof payload.tool_input === "object"
        ? payload.tool_input
        : {};
  const updatedInput =
    decision === "overwrite" ? computeOverwrittenInput(r, rawArgs) : undefined;

  return {
    matched: true,
    ruleId,
    ruleName,
    action,
    decision,
    message,
    updatedInput,
  };
}

const DECISION_RANK = {
  allow: 1,
  overwrite: 2,
  ask: 3,
  force_ask: 4,
  deny: 5,
};

/**
 * Evaluates a list of Hookify rules for a `PreToolUse` hook event.
 *
 * @param {Array<Record<string, any>>} rules
 * @param {Record<string, any>} payload
 */
export function evaluatePreToolUse(rules, payload) {
  const list = Array.isArray(rules) ? rules : [];
  const matchedRules = [];
  let currentArgs =
    payload?.toolCall?.args && typeof payload.toolCall.args === "object"
      ? { ...payload.toolCall.args }
      : payload?.tool_input && typeof payload.tool_input === "object"
        ? { ...payload.tool_input }
        : {};
  let hasOverwrite = false;

  for (const rule of list) {
    const res = evaluateRule(rule, payload, "PreToolUse");
    if (res.matched) {
      matchedRules.push(res);
      if (res.decision === "overwrite" && res.updatedInput) {
        currentArgs = computeOverwrittenInput(rule, currentArgs);
        hasOverwrite = true;
      }
    }
  }

  if (matchedRules.length === 0) {
    return {
      decision: "allow",
      reason: "",
      matchedRules: [],
      updatedInput: undefined,
      hookOutput: {},
    };
  }

  let winningDecision = "allow";
  for (const m of matchedRules) {
    if (
      (DECISION_RANK[m.decision] ?? 0) > (DECISION_RANK[winningDecision] ?? 0)
    ) {
      winningDecision = m.decision;
    }
  }

  const reasons = matchedRules.map((m) => `[${m.ruleName}] ${m.message}`);
  const reason = reasons.join("\n\n");
  const permissionDecision =
    winningDecision === "overwrite" ? "allow" : winningDecision;

  const hookSpecificOutput = {
    hookEventName: "PreToolUse",
    permissionDecision,
    permissionDecisionReason: reason,
  };
  if (hasOverwrite && permissionDecision !== "deny") {
    hookSpecificOutput.updatedInput = currentArgs;
  }

  const hookOutput = {
    permissionDecision,
    permissionDecisionReason: reason,
    ...(hasOverwrite && permissionDecision !== "deny"
      ? { updatedInput: currentArgs }
      : {}),
    hookSpecificOutput,
  };

  return {
    decision: winningDecision,
    permissionDecision,
    reason,
    matchedRules,
    updatedInput:
      hasOverwrite && permissionDecision !== "deny" ? currentArgs : undefined,
    hookOutput,
  };
}

/**
 * Evaluates a list of Hookify rules for a `Stop` hook event.
 *
 * @param {Array<Record<string, any>>} rules
 * @param {Record<string, any>} payload
 */
export function evaluateStop(rules, payload) {
  const list = Array.isArray(rules) ? rules : [];
  const matchedRules = [];

  for (const rule of list) {
    const res = evaluateRule(rule, payload, "Stop");
    if (res.matched) {
      matchedRules.push(res);
    }
  }

  if (matchedRules.length === 0) {
    return {
      continue: true,
      stopReason: "",
      systemMessage: "",
      matchedRules: [],
      hookOutput: {},
    };
  }

  const blocking = matchedRules.filter((m) => m.decision === "deny");
  const message = matchedRules
    .map((m) => `[${m.ruleName}] ${m.message}`)
    .join("\n\n");

  if (blocking.length > 0) {
    const hookOutput = {
      continue: false,
      decision: "block",
      stopReason: message,
      reason: message,
      systemMessage: message,
    };
    return {
      continue: false,
      stopReason: message,
      systemMessage: message,
      matchedRules,
      hookOutput,
    };
  }

  const hookOutput = {
    continue: true,
    systemMessage: message,
  };
  return {
    continue: true,
    stopReason: "",
    systemMessage: message,
    matchedRules,
    hookOutput,
  };
}

/**
 * Computes summary metrics for the Hookify sidecar panel and OpenUI Lang view.
 *
 * @param {{ rules?: Array<Record<string, any>>, events?: Array<Record<string, any>> }} [state]
 */
export function summariseHookifyState(state = {}) {
  const rules = Array.isArray(state?.rules)
    ? state.rules.filter((r) => r && typeof r === "object")
    : [];
  const events = Array.isArray(state?.events)
    ? state.events.filter((e) => e && typeof e === "object")
    : [];

  const activeRules = rules.filter((r) => r.enabled !== false).length;
  const blockedEvents = events.filter((e) => e.decision === "deny").length;
  const warnEvents = events.filter(
    (e) =>
      e.decision === "ask" ||
      e.decision === "force_ask" ||
      e.decision === "warn",
  ).length;
  const rewriteEvents = events.filter((e) => e.decision === "overwrite").length;

  return {
    totalRules: rules.length,
    activeRules,
    disabledRules: rules.length - activeRules,
    totalEvents: events.length,
    blockedEvents,
    warnEvents,
    rewriteEvents,
  };
}
