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

// Pure logic for worktree-band: formatting disk sizes, counting GitHub check
// rollups, verifying Bazel output-base removal safety, judging post-merge
// worktree cleanup readiness, and summarising tracked worktrees.

const PASSED = new Set(["SUCCESS", "SKIPPED", "NEUTRAL"]);
const RUNNING = new Set([
  "PENDING",
  "EXPECTED",
  "QUEUED",
  "IN_PROGRESS",
  "WAITING",
  "REQUESTED",
]);

/**
 * Formats a kilobyte count into a human-readable string (`KB`, `MB`, `GB`),
 * or `"…"` when not yet measured.
 *
 * @param {number | null | undefined} kb
 * @returns {string}
 */
export function fmtSize(kb) {
  if (kb === null || kb === undefined || !Number.isFinite(Number(kb))) {
    return "…";
  }
  const n = Number(kb);
  if (n >= 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} GB`;
  if (n >= 1024) return `${Math.round(n / 1024)} MB`;
  return `${Math.max(0, Math.round(n))} KB`;
}

/**
 * Counts passed, failed, and running checks from a GitHub `statusCheckRollup`
 * array. Check runs carry `status` + `conclusion`; commit statuses carry `state`.
 *
 * @param {Array<{ status?: string, conclusion?: string | null, state?: string }>} rollup
 * @returns {{ passed: number, failed: number, running: number, total: number }}
 */
export function countChecks(rollup) {
  const list = Array.isArray(rollup) ? rollup : [];
  const counts = { passed: 0, failed: 0, running: 0, total: list.length };
  for (const r of list) {
    if (!r || typeof r !== "object") continue;
    const verdict =
      r.state ??
      (r.status === "COMPLETED" ? (r.conclusion ?? "") : (r.status ?? ""));
    if (PASSED.has(verdict)) counts.passed += 1;
    else if (RUNNING.has(verdict) || verdict === "") counts.running += 1;
    else counts.failed += 1;
  }
  return counts;
}

/**
 * Verifies whether a candidate Bazel cache directory is safe to remove.
 * Only a folder strictly under `home`, containing `/bazel/`, deeper than the
 * shared Bazel user root, and not named `cache` or `install` may ever be
 * removed.
 *
 * @param {string} path
 * @param {string} home
 * @param {string[]} [sharedRoots=[]]
 * @returns {boolean}
 */
export function isRemovable(path, home, sharedRoots = []) {
  if (
    typeof path !== "string" ||
    typeof home !== "string" ||
    !home ||
    !path.startsWith(`${home}/`) ||
    path.includes("/../") ||
    path.endsWith("/..")
  ) {
    return false;
  }
  if (!/\/bazel\//.test(path)) return false;
  if (Array.isArray(sharedRoots) && sharedRoots.includes(path)) return false;
  if (/\/(cache|install)$/.test(path)) return false;
  return (
    path.split("/").filter(Boolean).length >=
    home.split("/").filter(Boolean).length + 3
  );
}

/**
 * Judges whether a worktree is safe to clean up after its pull request merges.
 * A worktree is only `"ready"` when:
 * - `mode` is not `"off"`
 * - `pr` exists and `pr.state === "MERGED"`
 * - `pr.base === place.defaultBranch`
 * - `place.isLinked` is true (never the main checkout)
 * - `git status --porcelain` succeeded and is empty
 * - `place.head === pr.head` (no unpushed local commits)
 *
 * @param {{ root?: string, mainRoot?: string, isLinked?: boolean, branch?: string, head?: string, defaultBranch?: string } | null | undefined} place
 * @param {{ number?: number, state?: string, base?: string, head?: string } | null | undefined} pr
 * @param {{ ok?: boolean, out?: string } | string | null | undefined} statusResult
 * @param {string} [mode="ask"]
 * @returns {{ cleanup: "none" | "ready" | "blocked", note: string }}
 */
export function judgeCleanup(place, pr, statusResult, mode = "ask") {
  if (!place || mode === "off" || !pr || pr.state !== "MERGED") {
    return { cleanup: "none", note: "" };
  }
  const defaultBranch = place.defaultBranch || "main";
  if (pr.base !== defaultBranch) {
    return {
      cleanup: "none",
      note: `merged into ${pr.base}, not ${defaultBranch}`,
    };
  }
  if (!place.isLinked) {
    return { cleanup: "none", note: "main checkout: nothing to remove" };
  }
  let ok = true;
  let out = "";
  if (typeof statusResult === "string") {
    out = statusResult.trim();
  } else if (statusResult && typeof statusResult === "object") {
    ok = statusResult.ok !== false;
    out = String(statusResult.out ?? "").trim();
  }
  if (!ok) {
    return { cleanup: "blocked", note: "git status failed" };
  }
  if (out.length > 0) {
    return { cleanup: "blocked", note: "uncommitted changes" };
  }
  if (place.head !== pr.head) {
    return {
      cleanup: "blocked",
      note: "local commits the pull request does not have",
    };
  }
  return { cleanup: "ready", note: "" };
}

/**
 * Sums the kilobyte sizes of a worktree's isolated Bazel caches.
 * Returns `null` if any cache entry has `kb: null` (still measuring).
 *
 * @param {Array<{ path: string, kb: number | null }> | null | undefined} caches
 * @returns {number | null}
 */
export function totalCacheKb(caches) {
  if (!Array.isArray(caches)) return 0;
  if (caches.some((c) => c && (c.kb === null || c.kb === undefined))) {
    return null;
  }
  return caches.reduce(
    (sum, c) => sum + (Number.isFinite(Number(c?.kb)) ? Number(c.kb) : 0),
    0,
  );
}

/**
 * Summarises a list of tracked worktree entries for the panel and OpenUI state.
 *
 * @param {Array<Record<string, any>> | null | undefined} worktrees
 * @returns {{
 *   items: Array<Record<string, any>>,
 *   total: number,
 *   linked: number,
 *   readyCount: number,
 *   blockedCount: number,
 *   cleanedCount: number,
 *   failingPrs: number,
 *   mergedPrs: number,
 *   totalTreeKb: number,
 *   totalBazelKb: number,
 *   reclaimableKb: number
 * }}
 */
export function summariseWorktrees(worktrees) {
  const items = (Array.isArray(worktrees) ? worktrees : [])
    .filter((w) => w && typeof w === "object")
    .sort((a, b) => {
      const aDone = a.cleanup === "done";
      const bDone = b.cleanup === "done";
      if (aDone !== bDone) return aDone ? 1 : -1;
      const aReady = a.cleanup === "ready";
      const bReady = b.cleanup === "ready";
      if (aReady !== bReady) return aReady ? -1 : 1;
      return String(a.branch ?? a.root ?? "").localeCompare(
        String(b.branch ?? b.root ?? ""),
      );
    });

  let linked = 0;
  let readyCount = 0;
  let blockedCount = 0;
  let cleanedCount = 0;
  let failingPrs = 0;
  let mergedPrs = 0;
  let totalTreeKb = 0;
  let totalBazelKb = 0;
  let reclaimableKb = 0;

  for (const w of items) {
    if (w.isLinked) linked += 1;
    if (w.cleanup === "ready") readyCount += 1;
    else if (w.cleanup === "blocked") blockedCount += 1;
    else if (w.cleanup === "done") cleanedCount += 1;

    if (w.pr?.state === "MERGED") mergedPrs += 1;
    if (
      w.pr &&
      w.pr.state !== "MERGED" &&
      w.pr.state !== "CLOSED" &&
      Number(w.pr.checks?.failed) > 0
    ) {
      failingPrs += 1;
    }

    if (w.cleanup !== "done") {
      const tKb = Number.isFinite(Number(w.treeKb)) ? Number(w.treeKb) : 0;
      const bKb = totalCacheKb(w.caches) ?? 0;
      totalTreeKb += tKb;
      totalBazelKb += bKb;
      if (w.cleanup === "ready") {
        reclaimableKb += tKb + bKb;
      }
    }
  }

  return {
    items,
    total: items.length,
    linked,
    readyCount,
    blockedCount,
    cleanedCount,
    failingPrs,
    mergedPrs,
    totalTreeKb,
    totalBazelKb,
    reclaimableKb,
  };
}
