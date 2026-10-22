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

// Pure decision logic for gh-watch: no I/O, so it runs under `node --test`.
//
// The rules mirror what Claude Code's desktop auto-fix does:
//   * wake once per failing check per commit, never twice for the same one;
//   * when a check fails while others in the same workflow are still running,
//     wait (up to holdMs) so the failures arrive together.

export const DEFAULT_HOLD_MS = 5 * 60 * 1000;

const FAIL_CONCLUSIONS = new Set([
  "FAILURE",
  "TIMED_OUT",
  "ACTION_REQUIRED",
  "STARTUP_FAILURE",
]);
const SKIP_CONCLUSIONS = new Set(["SKIPPED", "NEUTRAL"]);

// Maps one entry of `gh pr view --json statusCheckRollup` to a bucket:
// 'pass' | 'fail' | 'pending' | 'skip' | 'cancel'.
export function bucketOf(raw) {
  if (raw.__typename === "StatusContext") {
    const state = (raw.state ?? "").toUpperCase();
    if (state === "SUCCESS") return "pass";
    if (state === "FAILURE" || state === "ERROR") return "fail";
    return "pending";
  }
  if ((raw.status ?? "").toUpperCase() !== "COMPLETED") return "pending";
  const conclusion = (raw.conclusion ?? "").toUpperCase();
  if (conclusion === "SUCCESS") return "pass";
  if (FAIL_CONCLUSIONS.has(conclusion)) return "fail";
  if (SKIP_CONCLUSIONS.has(conclusion)) return "skip";
  if (conclusion === "CANCELLED") return "cancel";
  return "pending";
}

const RANK = { fail: 4, pending: 3, cancel: 2, pass: 1, skip: 0 };

// Normalises the rollup into one entry per check name. A name that appears
// more than once keeps its newest run when both runs carry a start (or end)
// time and belong to the same workflow, so a re-run that is pending or passed
// supersedes the failure it replaces. Otherwise (matrix legs, status contexts
// without times) it keeps its worst bucket.
export function normaliseChecks(rollup) {
  const byName = new Map();
  for (const raw of rollup ?? []) {
    const name = raw.name ?? raw.context;
    if (!name) continue;
    const parsed = Date.parse(raw.startedAt ?? raw.completedAt ?? "");
    const at = Number.isNaN(parsed) ? null : parsed;
    const check = {
      name,
      bucket: bucketOf(raw),
      workflow: raw.workflowName || undefined,
      url: raw.detailsUrl ?? raw.targetUrl ?? undefined,
      waiting: (raw.status ?? "").toUpperCase() === "WAITING",
    };
    const seen = byName.get(name);
    if (!seen) {
      byName.set(name, { check, at });
    } else if (
      at !== null &&
      seen.at !== null &&
      check.workflow === seen.check.workflow &&
      at !== seen.at
    ) {
      if (at > seen.at) byName.set(name, { check, at });
    } else if (RANK[check.bucket] > RANK[seen.check.bucket]) {
      byName.set(name, { check, at });
    }
  }
  return [...byName.values()].map((entry) => entry.check);
}

export function countChecks(checks) {
  const counts = { pass: 0, fail: 0, pending: 0, skip: 0, cancel: 0 };
  for (const check of checks) counts[check.bucket] += 1;
  return counts;
}

export function emptyState() {
  return { headSha: null, notified: [], held: null };
}

// Decides whether to wake the conversation.
//   prev: { headSha, notified: string[], held: { since } | null }
//   snap: { headSha, checks: normalised checks }
// Returns { wake: checks to report (empty = stay quiet), state: next state }.
// The caller commits `state` only once the wake was delivered.
export function decide(prev, snap, now, { holdMs = DEFAULT_HOLD_MS } = {}) {
  const sameHead = prev?.headSha === snap.headSha;
  const notified = new Set(sameHead ? prev.notified : []);
  const held = sameHead ? prev.held : null;

  // Forget a notified check once it has passed, so a later failure of the
  // same check on the same commit (a re-run) is reported again.
  const stillOpen = new Set(
    snap.checks
      .filter((c) => c.bucket === "fail" || c.bucket === "pending")
      .map((c) => c.name),
  );
  for (const name of [...notified])
    if (!stillOpen.has(name)) notified.delete(name);

  const fresh = snap.checks.filter(
    (c) => c.bucket === "fail" && !notified.has(c.name),
  );
  const quiet = { headSha: snap.headSha, notified: [...notified], held: null };
  if (fresh.length === 0) return { wake: [], state: quiet };

  const workflows = new Set(fresh.map((c) => c.workflow).filter(Boolean));
  const siblingsRunning = snap.checks.some(
    (c) =>
      c.bucket === "pending" &&
      !c.waiting &&
      c.workflow &&
      workflows.has(c.workflow),
  );
  const since = held?.since ?? now;
  if (siblingsRunning && now - since < holdMs) {
    return { wake: [], state: { ...quiet, held: { since } } };
  }

  for (const check of fresh) notified.add(check.name);
  return {
    wake: fresh,
    state: { headSha: snap.headSha, notified: [...notified], held: null },
  };
}

// The list of newly failing checks, shared by every message that has one.
// A check that is known to be flaky is marked, with advice to re-run it
// before changing code. A check that carries an `excerpt` (the tail of its
// failing log) has it quoted, indented, under its line.
export function failingLines(failing) {
  const lines = [`Newly failing checks (${failing.length}):`];
  for (const c of failing) {
    lines.push(
      `- ${c.name}${c.workflow ? ` [${c.workflow}]` : ""}${c.url ? ` ${c.url}` : ""}${c.flaky ? ` (known flaky: ${c.flaky} times in the last 30 days)` : ""}`,
    );
    const excerpt = typeof c.excerpt === "string" ? c.excerpt.trim() : "";
    if (excerpt)
      for (const line of excerpt.split("\n")) lines.push(`  | ${line}`);
  }
  if (failing.some((c) => c.flaky)) {
    lines.push(
      "A check marked known flaky has recently failed and then passed on a re-run with no code change. Re-run those first (for example `gh run rerun <run-id> --failed`) and only change code if they fail again.",
    );
  }
  return lines;
}

// The text sent into the conversation. It arrives as a system notice, so it
// says who is speaking and exactly what is being asked.
export function wakeMessage(pr, failing) {
  const lines = [
    `Automated notice from the gh-watch plugin: CI is failing on ${pr.repo}#${pr.number} ("${pr.title}").`,
    `PR: ${pr.url}`,
    `Branch: ${pr.branch}  Commit: ${(pr.headSha ?? "").slice(0, 12)}`,
    "",
    ...failingLines(failing),
    "",
    "Please look at the failing logs (for example `gh run view --log-failed`), fix the cause on this branch and push.",
    "You will not be told about these checks again for this commit. If the failure is not caused by this PR, say so instead of changing code.",
  ];
  return lines.join("\n");
}
