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

// Pure logic for the live-context Antigravity plugin:
// - Formats live Git branch/status and GitHub PR/issue state
// - Builds Antigravity PreInvocation `{ injectSteps: [{ ephemeralMessage }] }` payloads
// - Checks assistant reply shape against the user's response contract
// - Evaluates Antigravity Stop hook events (`{ decision: "continue" | "allow" }`)

export const DEFAULT_RESPONSE_CONTRACT = `RESPONSE CONTRACT: Scale to the question.
- Simple or factual question: one or two sentences. No headers, no sections.
- Substantive work: GIST first (one or two plain sentences, answer first, no jargon), then DETAIL (how it works, evidence, caveats).
- SURPRISE first: if a finding contradicts what the user expects, or they may have missed it, it goes at the very top.
- CONFIDENCE: mark what you verified versus what you assumed. Never present a guess as a fact.
- CHOICES: give your pick and a one-line why. Alternatives only if they would change the decision.
- DIAGRAM only when it earns its place: a workflow, pipeline, state machine or genuinely complex topic.
- NEXT only when the user must do or decide something, or there is a concrete follow-up. Otherwise end after the detail. Never write 'Nothing needed from you.'`;

const FILLER_REGEX =
  /(nothing needed from you|nothing for you|no action (is )?(needed|required)|nothing (else )?(is )?needed)/i;

/**
 * Formats live local Git state and GitHub open/merged pull requests into a
 * concise context block.
 *
 * @param {{ branch?: string, headSha?: string, dirtyCount?: number, dirtyFiles?: string[], repoRoot?: string }} [git={}]
 * @param {{ repo?: string, openPrs?: Array<{ number: number, title: string, isDraft?: boolean }>, mergedPrs?: Array<{ number: number, title: string, mergedAt?: string }>, openIssues?: number, unavailable?: boolean }} [github={}]
 * @param {{ includeGit?: boolean, includeGitHub?: boolean }} [opts={}]
 * @returns {string}
 */
export function formatLiveGitSummary(git = {}, github = {}, opts = {}) {
  const includeGit = opts.includeGit !== false;
  const includeGitHub = opts.includeGitHub !== false;
  const sections = [];

  if (includeGit && git && (git.branch || git.headSha)) {
    const branch = git.branch || "detached";
    const sha = git.headSha ? ` (${git.headSha})` : "";
    const dirty = Number(git.dirtyCount ?? 0);
    const dirtyDesc =
      dirty > 0
        ? `${dirty} uncommitted file${dirty === 1 ? "" : "s"}${Array.isArray(git.dirtyFiles) && git.dirtyFiles.length > 0 ? `: ${git.dirtyFiles.slice(0, 5).join(", ")}` : ""}`
        : "clean working tree";
    sections.push(`LIVE GIT WORKSPACE: branch ${branch}${sha} · ${dirtyDesc}`);
  }

  if (includeGitHub && github && typeof github === "object") {
    const repo = github.repo || "VitruvianSoftware/vitruvian-core";
    if (github.unavailable) {
      sections.push(
        `GitHub state unavailable this turn (gh query failed or timed out).\nTreat all remembered PR/issue status as STALE and re-query before reporting it.`,
      );
    } else {
      const openList = Array.isArray(github.openPrs) ? github.openPrs : [];
      const mergedList = Array.isArray(github.mergedPrs)
        ? github.mergedPrs
        : [];
      const openLines =
        openList.length > 0
          ? openList
              .map(
                (pr) =>
                  `  #${pr.number}${pr.isDraft ? " [draft]" : ""} ${pr.title}`,
              )
              .join("\n")
          : "  (none)";
      const mergedLines =
        mergedList.length > 0
          ? mergedList
              .map(
                (pr) =>
                  `  #${pr.number} ${pr.title}${pr.mergedAt ? `  (merged ${pr.mergedAt})` : ""}`,
              )
              .join("\n")
          : "  (none)";
      const issueCount =
        github.openIssues !== undefined && github.openIssues !== null
          ? String(github.openIssues)
          : "?";

      sections.push(
        `LIVE ${repo} state, fetched just now — this SUPERSEDES any PR/issue status stated earlier in this conversation. Do not restate status from earlier turns; if something you are about to report is not reflected here, re-query it.\n\nOPEN PRs:\n${openLines}\n\nRECENTLY MERGED PRs (last 10):\n${mergedLines}\n\nOPEN issues: ${issueCount}`,
      );
    }
  }

  return sections.join("\n\n").trim();
}

/**
 * Builds the Antigravity `PreInvocation` JSON output payload (`injectSteps: [{ ephemeralMessage }]`).
 *
 * @param {{ git?: Record<string, any>, github?: Record<string, any>, settings?: Record<string, any> }} [input={}]
 * @returns {Record<string, any>}
 */
export function buildEphemeralContextPayload(input = {}) {
  const settings =
    input.settings && typeof input.settings === "object" ? input.settings : {};
  const injectGit = settings.injectGit !== false;
  const injectGitHub = settings.injectGitHub !== false;
  const injectContract = settings.injectContract !== false;
  const contractText = String(
    settings.contractText ?? DEFAULT_RESPONSE_CONTRACT,
  ).trim();

  const blocks = [];
  if (injectGit || injectGitHub) {
    const liveSummary = formatLiveGitSummary(
      input.git ?? {},
      input.github ?? {},
      {
        includeGit: injectGit,
        includeGitHub: injectGitHub,
      },
    );
    if (liveSummary) blocks.push(liveSummary);
  }

  if (injectContract && contractText) {
    blocks.push(contractText);
  }

  if (blocks.length === 0) {
    return {};
  }

  return {
    injectSteps: [
      {
        ephemeralMessage: blocks.join("\n\n---\n\n"),
      },
    ],
  };
}

/**
 * Checks an assistant reply against the response shape contract.
 *
 * @param {string} message
 * @param {{ minChars?: number, diagramMinChars?: number }} [options={}]
 */
export function checkResponseContract(message, options = {}) {
  const msg = String(message ?? "").trim();
  const chars = msg.length;
  const minChars = Number(options.minChars ?? 300);
  const diagramMinChars = Number(options.diagramMinChars ?? 2600);

  if (chars < minChars) {
    return {
      exempt: true,
      chars,
      hasFiller: false,
      hasDiagram: null,
      longNoDiagram: false,
      finalLine: "",
      failures: [],
      valid: true,
    };
  }

  const hasDiagram =
    chars >= diagramMinChars
      ? /```mermaid\b|<agent-embed\b|show_widget/i.test(msg)
      : null;
  const longNoDiagram = hasDiagram === false;

  // Strip fenced code blocks so trailing commands do not hide or fake the ending.
  const withoutCode = msg.replace(/```[\s\S]*?```/g, "");
  const nonEmptyLines = withoutCode
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  const rawLastLine =
    nonEmptyLines.length > 0 ? nonEmptyLines[nonEmptyLines.length - 1] : "";
  // Strip inline code spans and quoted phrases so quoting the forbidden phrase
  // in an explanation does not trigger a false positive.
  const strippedLastLine = rawLastLine.replace(
    /`[^`]*`|"[^"]*"|\u201c[^\u201d]*\u201d|'[^']*'/g,
    "",
  );
  const hasFiller = FILLER_REGEX.test(strippedLastLine);

  const failures = [];
  if (hasFiller) {
    failures.push(
      "closes with an empty 'nothing needed' line -- end after the detail instead; only add a next step when there is a real one",
    );
  }

  return {
    exempt: false,
    chars,
    hasFiller,
    hasDiagram,
    longNoDiagram,
    finalLine: rawLastLine,
    failures,
    valid: failures.length === 0,
  };
}

/**
 * Evaluates an Antigravity `Stop` hook event and returns the hook stdout object
 * (`{ decision: "allow" }` or `{ decision: "continue", reason: "..." }`) plus a
 * structured log record.
 *
 * @param {{ conversationId?: string, executionNum?: number, terminationReason?: string, lastAssistantMessage?: string, stopHookActive?: boolean }} [stopEvent={}]
 * @param {{ mode?: "log" | "enforce", minChars?: number, diagramMinChars?: number, nowIso?: string }} [options={}]
 */
export function evaluateStopShape(stopEvent = {}, options = {}) {
  const mode = options.mode === "enforce" ? "enforce" : "log";
  const executionNum = Number(stopEvent.executionNum ?? 1);
  const reason = String(stopEvent.terminationReason ?? "NO_TOOL_CALL");

  // Never bounce more than once per turn, or on abnormal termination reasons.
  if (
    stopEvent.stopHookActive === true ||
    executionNum > 1 ||
    (reason && reason !== "NO_TOOL_CALL")
  ) {
    return {
      output: { decision: "allow" },
      bounced: false,
      logRecord: null,
    };
  }

  const check = checkResponseContract(stopEvent.lastAssistantMessage ?? "", {
    minChars: options.minChars,
    diagramMinChars: options.diagramMinChars,
  });

  if (check.exempt) {
    return {
      output: { decision: "allow" },
      bounced: false,
      logRecord: null,
    };
  }

  const msg = String(stopEvent.lastAssistantMessage ?? "").trim();
  const logRecord = {
    ts: options.nowIso || new Date().toISOString(),
    conversationId: String(stopEvent.conversationId ?? "").slice(0, 8),
    mode,
    chars: check.chars,
    filler: check.hasFiller,
    diagram: check.hasDiagram,
    longNoDiagram: check.longNoDiagram,
    verdict: check.valid ? "pass" : "block",
    tail: msg.slice(-120).replaceAll("\n", " "),
  };

  if (!check.valid && mode === "enforce") {
    return {
      output: {
        decision: "continue",
        reason: `RESPONSE CONTRACT: ${check.failures.join("; ")}. Revise once; keep the evidence, cut the padding.`,
      },
      bounced: true,
      logRecord,
    };
  }

  return {
    output: { decision: "allow" },
    bounced: false,
    logRecord,
  };
}
