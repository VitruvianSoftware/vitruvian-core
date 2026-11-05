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

// Pure logic for the ralph-loop panel: creating loop state, bounding
// iterations, and summarising loops across conversations. The Stop hook's
// decision (promise matching, continue or stop) is in hooks/src/lib.rs.

export const MIN_ITERATIONS = 1;
export const MAX_ITERATIONS_LIMIT = 200;
export const DEFAULT_MAX_ITERATIONS = 10;

/**
 * Creates a fresh active loop state record for a conversation.
 *
 * @param {{
 *   conversationId: string,
 *   prompt?: string,
 *   completionPromise?: string,
 *   maxIterations?: number,
 *   now?: number
 * }} params
 * @returns {Record<string, any>}
 */
export function createLoopState({
  conversationId,
  prompt = "",
  completionPromise = "DONE",
  maxIterations = DEFAULT_MAX_ITERATIONS,
  now = Date.now(),
} = {}) {
  const id = String(conversationId ?? "").trim();
  if (!id) {
    throw new Error("conversationId is required to start a Ralph Loop");
  }
  const rawMax = Number(maxIterations);
  const clampedMax = Number.isFinite(rawMax)
    ? Math.max(
        MIN_ITERATIONS,
        Math.min(MAX_ITERATIONS_LIMIT, Math.round(rawMax)),
      )
    : DEFAULT_MAX_ITERATIONS;
  const promiseToken = String(completionPromise ?? "").trim() || "DONE";

  return {
    conversationId: id,
    prompt: String(prompt ?? "").trim(),
    completionPromise: promiseToken,
    iteration: 0,
    maxIterations: clampedMax,
    active: true,
    status: "running",
    startedAt: now,
    updatedAt: now,
    completedAt: null,
  };
}

/**
 * Advances an active loop state by one iteration.
 *
 * @param {Record<string, any>} state
 * @param {{ now?: number }} [opts]
 * @returns {Record<string, any>}
 */
export function updateLoopIteration(state, { now = Date.now() } = {}) {
  if (!state || typeof state !== "object" || !state.active) {
    return state ? { ...state } : null;
  }
  const nextIteration = (Number(state.iteration) || 0) + 1;
  return {
    ...state,
    iteration: nextIteration,
    status: "running",
    updatedAt: now,
  };
}

/**
 * Summarises a list of loop states for the panel and OpenUI Lang renderer.
 *
 * @param {Array<Record<string, any>> | null | undefined} loops
 * @returns {{
 *   items: Array<Record<string, any>>,
 *   total: number,
 *   activeCount: number,
 *   completedCount: number,
 *   maxedCount: number,
 *   cancelledCount: number,
 *   totalIterations: number
 * }}
 */
export function summariseLoops(loops) {
  const items = (Array.isArray(loops) ? loops : [])
    .filter((l) => l && typeof l === "object")
    .sort((a, b) => {
      const aActive = Boolean(a.active);
      const bActive = Boolean(b.active);
      if (aActive !== bActive) return aActive ? -1 : 1;
      return (Number(b.updatedAt) || 0) - (Number(a.updatedAt) || 0);
    });

  let activeCount = 0;
  let completedCount = 0;
  let maxedCount = 0;
  let cancelledCount = 0;
  let totalIterations = 0;

  for (const l of items) {
    if (l.active) activeCount += 1;
    if (l.status === "completed") completedCount += 1;
    else if (l.status === "max_iterations") maxedCount += 1;
    else if (l.status === "cancelled") cancelledCount += 1;
    totalIterations += Number(l.iteration) || 0;
  }

  return {
    items,
    total: items.length,
    activeCount,
    completedCount,
    maxedCount,
    cancelledCount,
    totalIterations,
  };
}
