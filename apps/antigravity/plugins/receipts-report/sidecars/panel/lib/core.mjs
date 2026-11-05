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

// Pure transcript parser, project impact receipt aggregator, token/error
// hotspot detector, and CSV/HTML receipt formatters for receipts-report.

import { escapeHtml } from "./openui.mjs";

const CHARS_PER_TOKEN = 4;

/**
 * Infers a readable project name from a workspace path.
 * @param {string} [workspacePath]
 * @returns {string}
 */
export function projectFromPath(workspacePath) {
  const cleaned = String(workspacePath ?? "")
    .trim()
    .replace(/\/+$/, "");
  if (!cleaned) return "unassigned";
  const parts = cleaned.split("/").filter(Boolean);
  return parts[parts.length - 1] || "unassigned";
}

/**
 * Extracts workspace paths, commit references, and pull request references
 * from a step's content and tool calls.
 * @param {Record<string, any>} step
 */
function extractStepSignals(step) {
  const workspaces = new Set();
  const commits = new Set();
  const prs = new Set();

  const text = `${String(step.content ?? "")}\n${String(step.thinking ?? "")}`;

  // Active Workspaces header in user/system context
  const wsMatches = text.matchAll(
    /Active Workspaces:\s*\n(?:-\s*([^\n]+)\n?)+/g,
  );
  for (const m of wsMatches) {
    if (m[1]) workspaces.add(m[1].trim());
  }
  const cwdMatch = text.match(/Command Working Directory:\s*([^\n]+)/);
  if (cwdMatch?.[1]) workspaces.add(cwdMatch[1].trim());

  const toolCalls = Array.isArray(step.tool_calls)
    ? step.tool_calls
    : Array.isArray(step.toolCalls)
      ? step.toolCalls
      : [];

  for (const tc of toolCalls) {
    if (!tc || typeof tc !== "object") continue;
    const args = tc.args ?? tc.arguments ?? tc.input ?? {};
    const pathArg = args.Path ?? args.path ?? args.cwd ?? "";
    if (typeof pathArg === "string" && pathArg.startsWith("/")) {
      const repoMatch = pathArg.match(
        /^(\/Users\/[^/]+\/Workspace\/(?:gh\/[^/]+\/[^/]+\/[^/]+|[^/]+))/,
      );
      if (repoMatch?.[1]) workspaces.add(repoMatch[1]);
    }
    const cmd = String(args.CommandLine ?? args.command ?? "");
    if (cmd) {
      if (/\bgit\s+commit\b/.test(cmd) || /\/\/tools\/git:commit\b/.test(cmd)) {
        const msgMatch = cmd.match(/-m\s+["']([^"']+)["']/);
        commits.add(msgMatch ? msgMatch[1] : `commit@${step.step_index ?? 0}`);
      }
      if (/\bgh\s+pr\s+create\b/.test(cmd) || /\bpr-create\b/.test(cmd)) {
        const titleMatch = cmd.match(/--title\s+["']([^"']+)["']/);
        prs.add(titleMatch ? titleMatch[1] : `pr@${step.step_index ?? 0}`);
      }
      for (const prUrl of cmd.matchAll(
        /https:\/\/github\.com\/[^/\s]+\/[^/\s]+\/pull\/(\d+)/g,
      )) {
        prs.add(`#${prUrl[1]}`);
      }
    }
  }

  for (const prUrl of text.matchAll(
    /https:\/\/github\.com\/[^/\s]+\/[^/\s]+\/pull\/(\d+)/g,
  )) {
    prs.add(`#${prUrl[1]}`);
  }
  for (const shaMatch of text.matchAll(/\[[\w/.-]+\s+([0-9a-f]{7,40})\]/g)) {
    commits.add(shaMatch[1]);
  }

  return {
    workspaces: [...workspaces],
    commits: [...commits],
    prs: [...prs],
  };
}

/**
 * Parses a JSONL transcript (`transcript.jsonl`) into a structured session receipt.
 *
 * @param {string} jsonlText
 * @param {{ conversationId?: string, workspacePath?: string, project?: string, modelName?: string }} [meta]
 * @returns {Record<string, any>}
 */
export function parseTranscriptJsonl(jsonlText, meta = {}) {
  const lines = String(jsonlText ?? "")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);

  let stepCount = 0;
  let userPromptCount = 0;
  let plannerTurnCount = 0;
  let toolCallCount = 0;
  let subagentCount = 0;
  let errorCount = 0;
  let truncatedStepCount = 0;
  let totalChars = 0;
  let startedAt = null;
  let endedAt = null;
  let firstUserPrompt = "";
  let detectedWorkspace = meta.workspacePath || "";
  let detectedModel = meta.modelName || "";

  const toolCounts = {};
  const subagentRoles = [];
  const truncatedFieldCounts = {};
  const commits = new Set();
  const prs = new Set();

  for (const line of lines) {
    let step;
    try {
      step = JSON.parse(line);
    } catch {
      continue;
    }
    if (!step || typeof step !== "object") continue;

    stepCount += 1;

    const ts = step.created_at ?? step.createdAt ?? null;
    if (typeof ts === "string" && ts) {
      const ms = Date.parse(ts);
      if (Number.isFinite(ms)) {
        if (startedAt === null || ms < startedAt) startedAt = ms;
        if (endedAt === null || ms > endedAt) endedAt = ms;
      }
    }

    if (step.model_name || step.modelName) {
      detectedModel = String(step.model_name ?? step.modelName);
    }

    const type = String(step.type ?? "").toUpperCase();
    const content = String(step.content ?? "");
    const thinking = String(step.thinking ?? "");
    const toolCalls = Array.isArray(step.tool_calls)
      ? step.tool_calls
      : Array.isArray(step.toolCalls)
        ? step.toolCalls
        : [];

    totalChars +=
      content.length + thinking.length + JSON.stringify(toolCalls).length;

    if (type === "USER_INPUT") {
      userPromptCount += 1;
      if (!firstUserPrompt && content.trim()) {
        const reqMatch = content.match(
          /<USER_REQUEST>\s*([\s\S]*?)\s*<\/USER_REQUEST>/,
        );
        const rawTitle = (reqMatch ? reqMatch[1] : content)
          .trim()
          .split("\n")[0];
        firstUserPrompt = rawTitle.slice(0, 120);
      }
    } else if (type === "PLANNER_RESPONSE") {
      plannerTurnCount += 1;
    }

    if (
      String(step.status ?? "").toUpperCase() === "ERROR" ||
      Boolean(step.error)
    ) {
      errorCount += 1;
    }

    const truncated = Array.isArray(step.truncated_fields)
      ? step.truncated_fields
      : Array.isArray(step.truncatedFields)
        ? step.truncatedFields
        : [];
    if (truncated.length > 0) {
      truncatedStepCount += 1;
      for (const field of truncated) {
        const key = String(field);
        truncatedFieldCounts[key] = (truncatedFieldCounts[key] ?? 0) + 1;
      }
    }

    for (const tc of toolCalls) {
      if (!tc || typeof tc !== "object") continue;
      toolCallCount += 1;
      const name = String(tc.name ?? tc.tool_name ?? "unknown");
      toolCounts[name] = (toolCounts[name] ?? 0) + 1;
      if (name === "invoke_subagent") {
        subagentCount += 1;
        const args = tc.args ?? tc.arguments ?? {};
        const role = args.Role ?? args.TypeName ?? "subagent";
        subagentRoles.push(String(role));
      }
    }

    const signals = extractStepSignals(step);
    if (!detectedWorkspace && signals.workspaces.length > 0) {
      detectedWorkspace = signals.workspaces[0];
    }
    for (const c of signals.commits) commits.add(c);
    for (const p of signals.prs) prs.add(p);
  }

  const workspacePath = detectedWorkspace || "";
  const project =
    meta.project ||
    (workspacePath ? projectFromPath(workspacePath) : "unassigned");
  const estimatedTokens = Math.ceil(totalChars / CHARS_PER_TOKEN);

  return {
    conversationId: String(meta.conversationId ?? "unknown"),
    project,
    workspacePath,
    modelName: detectedModel || "auto",
    title:
      firstUserPrompt ||
      `Session ${String(meta.conversationId ?? "").slice(0, 8)}`,
    startedAt,
    endedAt,
    stepCount,
    userPromptCount,
    plannerTurnCount,
    toolCallCount,
    toolCounts,
    subagentCount,
    subagentRoles,
    errorCount,
    truncatedStepCount,
    truncatedFieldCounts,
    totalChars,
    estimatedTokens,
    commits: [...commits],
    prs: [...prs],
  };
}

/**
 * Aggregates parsed session receipts by project, merges optional external
 * git/PR lists, and computes overall totals.
 *
 * @param {Array<Record<string, any>>} sessions
 * @param {Record<string, { commits?: string[], prs?: string[] }>} [externalByProject={}]
 * @param {{ windowDays?: number, nowMs?: number, projectFilter?: string }} [options={}]
 */
export function aggregateProjectReceipts(
  sessions,
  externalByProject = {},
  options = {},
) {
  const nowMs = Number.isFinite(options.nowMs) ? options.nowMs : Date.now();
  const windowDays = Number(options.windowDays ?? 0);
  const cutoffMs =
    windowDays > 0 ? nowMs - windowDays * 24 * 60 * 60 * 1000 : null;
  const projectFilter = String(options.projectFilter ?? "")
    .trim()
    .toLowerCase();

  const validSessions = (Array.isArray(sessions) ? sessions : []).filter(
    (s) => {
      if (!s || typeof s !== "object") return false;
      if (cutoffMs !== null) {
        const refTime = s.endedAt ?? s.startedAt ?? null;
        if (refTime !== null && refTime < cutoffMs) return false;
      }
      if (
        projectFilter &&
        !String(s.project ?? "")
          .toLowerCase()
          .includes(projectFilter)
      ) {
        return false;
      }
      return true;
    },
  );

  const byProject = new Map();

  for (const s of validSessions) {
    const key = String(s.project || "unassigned");
    if (!byProject.has(key)) {
      byProject.set(key, {
        project: key,
        workspacePath: s.workspacePath || "",
        conversations: 0,
        userPrompts: 0,
        plannerTurns: 0,
        toolCalls: 0,
        subagents: 0,
        errors: 0,
        truncatedSteps: 0,
        estimatedTokens: 0,
        commitSet: new Set(),
        prSet: new Set(),
        toolCounts: {},
        latestAt: null,
      });
    }
    const bucket = byProject.get(key);
    if (!bucket.workspacePath && s.workspacePath) {
      bucket.workspacePath = s.workspacePath;
    }
    bucket.conversations += 1;
    bucket.userPrompts += Number(s.userPromptCount ?? 0);
    bucket.plannerTurns += Number(s.plannerTurnCount ?? 0);
    bucket.toolCalls += Number(s.toolCallCount ?? 0);
    bucket.subagents += Number(s.subagentCount ?? 0);
    bucket.errors += Number(s.errorCount ?? 0);
    bucket.truncatedSteps += Number(s.truncatedStepCount ?? 0);
    bucket.estimatedTokens += Number(s.estimatedTokens ?? 0);

    for (const c of Array.isArray(s.commits) ? s.commits : []) {
      bucket.commitSet.add(String(c));
    }
    for (const p of Array.isArray(s.prs) ? s.prs : []) {
      bucket.prSet.add(String(p));
    }
    for (const [tool, count] of Object.entries(s.toolCounts ?? {})) {
      bucket.toolCounts[tool] = (bucket.toolCounts[tool] ?? 0) + Number(count);
    }
    const ts = s.endedAt ?? s.startedAt ?? null;
    if (ts !== null && (bucket.latestAt === null || ts > bucket.latestAt)) {
      bucket.latestAt = ts;
    }
  }

  for (const [projName, ext] of Object.entries(externalByProject ?? {})) {
    if (!ext || typeof ext !== "object") continue;
    if (projectFilter && !projName.toLowerCase().includes(projectFilter)) {
      continue;
    }
    if (!byProject.has(projName)) {
      byProject.set(projName, {
        project: projName,
        workspacePath: "",
        conversations: 0,
        userPrompts: 0,
        plannerTurns: 0,
        toolCalls: 0,
        subagents: 0,
        errors: 0,
        truncatedSteps: 0,
        estimatedTokens: 0,
        commitSet: new Set(),
        prSet: new Set(),
        toolCounts: {},
        latestAt: null,
      });
    }
    const bucket = byProject.get(projName);
    for (const c of Array.isArray(ext.commits) ? ext.commits : []) {
      bucket.commitSet.add(String(c));
    }
    for (const p of Array.isArray(ext.prs) ? ext.prs : []) {
      bucket.prSet.add(String(p));
    }
  }

  const projects = [...byProject.values()]
    .map((b) => {
      const topTools = Object.entries(b.toolCounts)
        .sort((a, c) => c[1] - a[1])
        .slice(0, 5)
        .map(([name, count]) => ({ name, count }));
      return {
        project: b.project,
        workspacePath: b.workspacePath,
        conversations: b.conversations,
        userPrompts: b.userPrompts,
        plannerTurns: b.plannerTurns,
        toolCalls: b.toolCalls,
        subagents: b.subagents,
        errors: b.errors,
        truncatedSteps: b.truncatedSteps,
        estimatedTokens: b.estimatedTokens,
        commits: b.commitSet.size,
        commitList: [...b.commitSet],
        prs: b.prSet.size,
        prList: [...b.prSet],
        topTools,
        latestAt: b.latestAt,
      };
    })
    .sort(
      (a, b) =>
        b.toolCalls - a.toolCalls ||
        b.conversations - a.conversations ||
        a.project.localeCompare(b.project),
    );

  const totals = projects.reduce(
    (acc, p) => {
      acc.conversations += p.conversations;
      acc.userPrompts += p.userPrompts;
      acc.plannerTurns += p.plannerTurns;
      acc.toolCalls += p.toolCalls;
      acc.subagents += p.subagents;
      acc.errors += p.errors;
      acc.truncatedSteps += p.truncatedSteps;
      acc.estimatedTokens += p.estimatedTokens;
      acc.commits += p.commits;
      acc.prs += p.prs;
      return acc;
    },
    {
      projects: projects.length,
      conversations: 0,
      userPrompts: 0,
      plannerTurns: 0,
      toolCalls: 0,
      subagents: 0,
      errors: 0,
      truncatedSteps: 0,
      estimatedTokens: 0,
      commits: 0,
      prs: 0,
    },
  );

  return {
    generatedAt: nowMs,
    windowDays,
    totals,
    projects,
    sessions: validSessions,
  };
}

/**
 * Detects token-bloat, truncation, and tool-error hotspots across sessions.
 *
 * @param {Array<Record<string, any>>} sessions
 * @param {{ truncatedStepsWarn?: number, errorCountWarn?: number, toolBurstWarn?: number, tokenWarn?: number }} [thresholds={}]
 */
export function detectTokenHotspots(sessions, thresholds = {}) {
  const truncatedStepsWarn = Number(thresholds.truncatedStepsWarn ?? 2);
  const errorCountWarn = Number(thresholds.errorCountWarn ?? 2);
  const toolBurstWarn = Number(thresholds.toolBurstWarn ?? 25);
  const tokenWarn = Number(thresholds.tokenWarn ?? 25_000);

  const hotspots = [];

  for (const s of Array.isArray(sessions) ? sessions : []) {
    if (!s || typeof s !== "object") continue;
    const convId = String(s.conversationId ?? "unknown");
    const project = String(s.project ?? "unassigned");
    const truncated = Number(s.truncatedStepCount ?? 0);
    const errors = Number(s.errorCount ?? 0);
    const tools = Number(s.toolCallCount ?? 0);
    const prompts = Math.max(1, Number(s.userPromptCount ?? 1));
    const toolsPerPrompt = tools / prompts;
    const tokens = Number(s.estimatedTokens ?? 0);

    if (truncated >= truncatedStepsWarn) {
      hotspots.push({
        conversationId: convId,
        project,
        severity: truncated >= truncatedStepsWarn * 2 ? "danger" : "warning",
        kind: "truncation",
        summary: `${truncated} steps had truncated fields in ${project} (${convId.slice(0, 8)})`,
        metrics: { truncatedStepCount: truncated, estimatedTokens: tokens },
      });
    }

    if (errors >= errorCountWarn) {
      hotspots.push({
        conversationId: convId,
        project,
        severity: errors >= errorCountWarn * 2 ? "danger" : "warning",
        kind: "error-burst",
        summary: `${errors} tool/step errors recorded in ${project} (${convId.slice(0, 8)})`,
        metrics: { errorCount: errors, toolCallCount: tools },
      });
    }

    if (toolsPerPrompt >= toolBurstWarn) {
      hotspots.push({
        conversationId: convId,
        project,
        severity: "warning",
        kind: "tool-loop",
        summary: `${Math.round(toolsPerPrompt)} tool calls per user prompt in ${project} (${convId.slice(0, 8)})`,
        metrics: { toolCallCount: tools, userPromptCount: prompts },
      });
    } else if (tokens >= tokenWarn) {
      hotspots.push({
        conversationId: convId,
        project,
        severity: "info",
        kind: "token-heavy",
        summary: `~${tokens.toLocaleString("en-US")} estimated tokens in ${project} (${convId.slice(0, 8)})`,
        metrics: { estimatedTokens: tokens },
      });
    }
  }

  const rank = { danger: 3, warning: 2, info: 1 };
  return hotspots.sort(
    (a, b) => (rank[b.severity] ?? 0) - (rank[a.severity] ?? 0),
  );
}

function csvCell(value) {
  const str = String(value ?? "");
  if (/[",\r\n]/.test(str)) {
    return `"${str.replaceAll('"', '""')}"`;
  }
  return str;
}

/**
 * Formats an aggregated receipts report as RFC-4180 CSV.
 *
 * @param {Record<string, any>} report
 * @returns {string}
 */
export function formatCsvReceipt(report) {
  const projects = Array.isArray(report?.projects) ? report.projects : [];
  const header = [
    "project",
    "conversations",
    "user_prompts",
    "planner_turns",
    "tool_calls",
    "subagents",
    "errors",
    "truncated_steps",
    "estimated_tokens",
    "commits",
    "prs",
  ];
  const rows = [header.join(",")];
  for (const p of projects) {
    rows.push(
      [
        csvCell(p.project),
        csvCell(p.conversations ?? 0),
        csvCell(p.userPrompts ?? 0),
        csvCell(p.plannerTurns ?? 0),
        csvCell(p.toolCalls ?? 0),
        csvCell(p.subagents ?? 0),
        csvCell(p.errors ?? 0),
        csvCell(p.truncatedSteps ?? 0),
        csvCell(p.estimatedTokens ?? 0),
        csvCell(p.commits ?? 0),
        csvCell(p.prs ?? 0),
      ].join(","),
    );
  }
  return rows.join("\n") + "\n";
}

/**
 * Renders a standalone HTML receipt artifact from an aggregated report and hotspots.
 *
 * @param {Record<string, any>} report
 * @param {Array<Record<string, any>>} [hotspots=[]]
 * @returns {string}
 */
export function renderHtmlReceipt(report, hotspots = []) {
  const r = report && typeof report === "object" ? report : {};
  const totals = r.totals && typeof r.totals === "object" ? r.totals : {};
  const projects = Array.isArray(r.projects) ? r.projects : [];
  const hs = Array.isArray(hotspots) ? hotspots : [];

  const projectRows = projects
    .map(
      (p) => `<tr>
        <td><strong>${escapeHtml(p.project)}</strong></td>
        <td>${escapeHtml(p.conversations ?? 0)}</td>
        <td>${escapeHtml(p.userPrompts ?? 0)}</td>
        <td>${escapeHtml(p.plannerTurns ?? 0)}</td>
        <td>${escapeHtml(p.toolCalls ?? 0)}</td>
        <td>${escapeHtml(p.subagents ?? 0)}</td>
        <td>${escapeHtml(p.commits ?? 0)} commits / ${escapeHtml(p.prs ?? 0)} PRs</td>
        <td>${escapeHtml(p.truncatedSteps ?? 0)} truncated / ${escapeHtml(p.errors ?? 0)} errors</td>
      </tr>`,
    )
    .join("\n");

  const hotspotRows = hs
    .map(
      (h) =>
        `<li><strong>[${escapeHtml(String(h.severity ?? "info").toUpperCase())}]</strong> ${escapeHtml(h.summary)}</li>`,
    )
    .join("\n");

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Antigravity Engineering Impact Receipt</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 2rem; color: #1f2937; background: #f9fafb; }
    h1 { font-size: 1.4rem; margin-bottom: 0.25rem; }
    .kpis { display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.75rem; margin: 1rem 0; }
    .kpi { background: #fff; border: 1px solid #e5e7eb; border-radius: 8px; padding: 0.75rem; }
    .kpi-label { font-size: 0.75rem; color: #6b7280; }
    .kpi-val { font-size: 1.25rem; font-weight: 700; margin-top: 0.25rem; }
    table { width: 100%; border-collapse: collapse; background: #fff; border: 1px solid #e5e7eb; border-radius: 8px; overflow: hidden; }
    th, td { text-align: left; padding: 0.6rem 0.75rem; border-bottom: 1px solid #e5e7eb; font-size: 0.85rem; }
    th { background: #f3f4f6; font-weight: 600; }
  </style>
</head>
<body>
  <h1>Antigravity Engineering Impact Receipt</h1>
  <div class="kpis">
    <div class="kpi"><div class="kpi-label">Sessions</div><div class="kpi-val">${escapeHtml(totals.conversations ?? 0)}</div></div>
    <div class="kpi"><div class="kpi-label">Tool Calls</div><div class="kpi-val">${escapeHtml(totals.toolCalls ?? 0)}</div></div>
    <div class="kpi"><div class="kpi-label">Shipped</div><div class="kpi-val">${escapeHtml((totals.commits ?? 0) + (totals.prs ?? 0))}</div></div>
    <div class="kpi"><div class="kpi-label">Hotspots</div><div class="kpi-val">${escapeHtml(hs.length)}</div></div>
  </div>
  <table>
    <thead>
      <tr>
        <th>Project</th>
        <th>Sessions</th>
        <th>Prompts</th>
        <th>Turns</th>
        <th>Tool Calls</th>
        <th>Subagents</th>
        <th>Shipped</th>
        <th>Health</th>
      </tr>
    </thead>
    <tbody>
      ${projectRows}
    </tbody>
  </table>
  ${hs.length > 0 ? `<h2>Token &amp; Error Hotspots</h2><ul>${hotspotRows}</ul>` : ""}
</body>
</html>
`;
}
