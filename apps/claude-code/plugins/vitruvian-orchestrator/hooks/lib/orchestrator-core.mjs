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

import { PRICES } from "./prices.mjs";

/**
 * @typedef {"plan" | "design" | "delegate" | "review" | "close"} Phase
 */

/**
 * @typedef {"lead" | "core" | "fast"} Tier
 */

/**
 * @typedef {"waiting" | "ready" | "running" | "review" | "returned" | "accepted"} TaskState
 */

/**
 * @typedef {"claude-code" | "antigravity" | "opencode"} Harness
 */

/**
 * @typedef {"running" | "done" | "error"} RunStatus
 */

/**
 * @typedef {"lead" | "worker"} RunRole
 */

/**
 * @typedef {Object} TokenCounts
 * @property {number} input
 * @property {number} output
 * @property {number} cacheRead
 * @property {number} cacheWrite
 */

/**
 * @typedef {Object} DelegateTokenCounts
 * @property {number} input
 * @property {number} output
 * @property {number} thinking
 * @property {number} cacheRead
 */

/**
 * @typedef {Object} StepProgress
 * @property {number} done
 * @property {number} total
 * @property {string} note
 */

/**
 * @typedef {Object} ReplanPoint
 * @property {number} at
 * @property {number} total
 */

/**
 * @typedef {Object} HistoryPoint
 * @property {number} at
 * @property {number} remaining
 */

/**
 * @typedef {Object} Task
 * @property {number} n 1-based task number
 * @property {string} title
 * @property {string} specialist
 * @property {Tier} tier
 * @property {number[]} after
 * @property {TaskState} state
 * @property {number} round 0 = first try
 */

/**
 * @typedef {Object} Run
 * @property {string} id
 * @property {Harness} harness
 * @property {string} agent
 * @property {string} model
 * @property {string | null} effort
 * @property {string | null} delegate
 * @property {string} title
 * @property {number | null} taskN
 * @property {number} startedAt
 * @property {number} lastActivityAt
 * @property {boolean} waiting True while the run is held on work it started
 *   (a background command, a Gemini job), as its harness reports it.
 * @property {number | null} endedAt
 * @property {RunStatus} status
 * @property {TokenCounts} tokens
 * @property {DelegateTokenCounts | null} [delegateTokens]
 * @property {StepProgress | null} steps
 * @property {number | null} contextPct
 * @property {RunRole} role
 */

/**
 * @typedef {"active" | "quiet" | "waiting" | "stalled"} StallState
 */

/**
 * @typedef {Object} StallRow
 * @property {string} id
 * @property {string} agent
 * @property {string} title
 * @property {number | null} taskN
 * @property {number} lastActivityAt
 * @property {number} idleMs
 * @property {StallState} state
 */

/**
 * @typedef {Object} Flow
 * @property {string} title
 * @property {Phase} phase
 * @property {number} startedAt
 * @property {number | null} closedAt
 * @property {Task[]} tasks
 * @property {Run[]} runs
 * @property {ReplanPoint[]} replans
 * @property {HistoryPoint[]} history
 */

/**
 * @typedef {Object} PlanTaskInput
 * @property {string} title
 * @property {string} specialist
 * @property {Tier} tier
 * @property {number[]} [after]
 */

/**
 * @typedef {Object} BurnDown
 * @property {HistoryPoint[]} points
 * @property {ReplanPoint[]} replans
 * @property {HistoryPoint[]} ideal
 */

/**
 * @typedef {Object} TaskBoardRow
 * @property {number} n
 * @property {string} title
 * @property {string} specialist
 * @property {Tier} tier
 * @property {TaskState} state
 * @property {number} round
 * @property {number[]} after
 * @property {number[]} waitingOn
 */

/**
 * @typedef {Object} UnpricedSummary
 * @property {number} runs
 * @property {number} tokens
 */

/**
 * @typedef {Object} DelegatedSummary
 * @property {number} runs
 * @property {number} unpriced
 * @property {Record<string, number>} byModel
 */

/**
 * @typedef {Object} SpendSummary
 * @property {number} total
 * @property {Record<string, number>} byModel
 * @property {number} lead
 * @property {number} workers
 * @property {UnpricedSummary} unpriced
 * @property {DelegatedSummary} delegated
 */

/**
 * @typedef {Object} FlowEvent
 * @property {string} type
 * @property {number} at
 * @property {string} [title]
 * @property {PlanTaskInput[]} [tasks]
 * @property {Phase} [phase]
 * @property {string} [id]
 * @property {Harness} [harness]
 * @property {string} [agent]
 * @property {string} [model]
 * @property {string | null} [effort]
 * @property {string | null} [delegate]
 * @property {RunRole} [role]
 * @property {Partial<TokenCounts>} [tokens]
 * @property {Partial<DelegateTokenCounts> | null} [delegateTokens]
 * @property {Partial<StepProgress> | null} [steps]
 * @property {number | null} [contextPct]
 * @property {RunStatus} [status]
 * @property {number} [n]
 * @property {boolean} [waiting]
 */

const VALID_PHASES = new Set(["plan", "design", "delegate", "review", "close"]);

export const DEFAULT_QUIET_MS = 5 * 60 * 1000;
export const DEFAULT_STALL_MS = 15 * 60 * 1000;
// A run waiting on work it started, or on Gemini, is silent by design.
// agy-delegate's own limit is 45 minutes, so allow an hour before calling it
// stalled.
export const DEFAULT_WAITING_STALL_MS = 60 * 60 * 1000;

const PRICE_RULES = PRICES.map((entry) => ({
  re: new RegExp(entry.match, "i"),
  input: entry.input,
  output: entry.output,
  cacheRead: entry.cacheRead,
  cacheWrite: entry.cacheWrite,
}));

/**
 * Returns the initial empty flow state (`null`).
 *
 * @returns {null}
 */
export function initialFlow() {
  return null;
}

/**
 * Clones a task object without sharing mutable references.
 *
 * @param {Task} task
 * @returns {Task}
 */
function cloneTask(task) {
  return {
    n: task.n,
    title: task.title,
    specialist: task.specialist,
    tier: task.tier,
    after: [...task.after],
    state: task.state,
    round: task.round,
  };
}

/**
 * Clones a run object without sharing mutable references.
 *
 * @param {Run} run
 * @returns {Run}
 */
function cloneRun(run) {
  return {
    id: run.id,
    harness: run.harness,
    agent: run.agent,
    model: run.model,
    effort: run.effort,
    delegate: run.delegate ?? null,
    title: run.title,
    taskN: run.taskN,
    startedAt: run.startedAt,
    lastActivityAt: run.lastActivityAt ?? run.startedAt,
    waiting: run.waiting === true,
    endedAt: run.endedAt,
    status: run.status,
    tokens: {
      input: run.tokens.input,
      output: run.tokens.output,
      cacheRead: run.tokens.cacheRead,
      cacheWrite: run.tokens.cacheWrite,
    },
    delegateTokens: run.delegateTokens
      ? {
          input: run.delegateTokens.input,
          output: run.delegateTokens.output,
          thinking: run.delegateTokens.thinking,
          cacheRead: run.delegateTokens.cacheRead,
        }
      : null,
    steps: run.steps
      ? {
          done: run.steps.done,
          total: run.steps.total,
          note: run.steps.note,
        }
      : null,
    contextPct: run.contextPct,
    role: run.role,
  };
}

/**
 * Normalizes an incoming `delegateTokens` snapshot. Replaces the whole object
 * when at least one known field is a finite non-negative number, ignoring
 * negative or non-numeric fields (treated as 0); otherwise returns `fallback`.
 *
 * @param {unknown} raw
 * @param {DelegateTokenCounts | null} fallback
 * @returns {DelegateTokenCounts | null}
 */
function parseDelegateTokens(raw, fallback) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return fallback;
  }
  const obj = /** @type {Record<string, unknown>} */ (raw);
  const keys = ["input", "output", "thinking", "cacheRead"];
  let hasValid = false;
  /** @type {Record<string, number>} */
  const next = { input: 0, output: 0, thinking: 0, cacheRead: 0 };
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === "number" && Number.isFinite(v) && v >= 0) {
      next[k] = v;
      hasValid = true;
    }
  }
  return hasValid ? /** @type {DelegateTokenCounts} */ (next) : fallback;
}

/**
 * Re-derives readiness for tasks in "waiting" or "ready":
 * "ready" when every task in `after` is "accepted", otherwise "waiting".
 * Tasks in "running", "review", "returned", or "accepted" keep their state.
 *
 * @param {Task[]} tasks
 * @returns {Task[]}
 */
function deriveReadiness(tasks) {
  const accepted = new Set(
    tasks.filter((t) => t.state === "accepted").map((t) => t.n),
  );
  return tasks.map((t) => {
    if (t.state === "waiting" || t.state === "ready") {
      const nextState = t.after.every((dep) => accepted.has(dep))
        ? "ready"
        : "waiting";
      return {
        ...cloneTask(t),
        state: /** @type {TaskState} */ (nextState),
      };
    }
    return cloneTask(t);
  });
}

/**
 * Finalizes a flow transition by deriving task readiness and appending to history
 * whenever the remaining (unaccepted) task count changes.
 *
 * @param {Flow} nextFlow
 * @param {number} at
 * @returns {Flow}
 */
function finalizeFlow(nextFlow, at) {
  const tasks = deriveReadiness(nextFlow.tasks);
  const rem = tasks.filter((t) => t.state !== "accepted").length;
  const prevHistory = nextFlow.history.map((h) => ({
    at: h.at,
    remaining: h.remaining,
  }));
  const lastRem =
    prevHistory.length > 0 ? prevHistory[prevHistory.length - 1].remaining : -1;
  const history =
    prevHistory.length === 0 || lastRem !== rem
      ? [...prevHistory, { at, remaining: rem }]
      : prevHistory;

  return {
    title: nextFlow.title,
    phase: nextFlow.phase,
    startedAt: nextFlow.startedAt,
    closedAt: nextFlow.closedAt,
    tasks,
    runs: nextFlow.runs.map(cloneRun),
    replans: nextFlow.replans.map((r) => ({ at: r.at, total: r.total })),
    history,
  };
}

/**
 * Pure reducer that advances a flow state in response to an event.
 * Never mutates `flow` or `event`.
 *
 * @param {Flow | null} flow
 * @param {FlowEvent} event
 * @returns {Flow | null}
 */
export function reduce(flow, event) {
  if (!event || typeof event !== "object" || typeof event.type !== "string") {
    return flow;
  }

  switch (event.type) {
    case "plan": {
      const rawTasks = Array.isArray(event.tasks) ? event.tasks : [];
      if (!flow) {
        const tasks = rawTasks.map((t, idx) => ({
          n: idx + 1,
          title: String(t.title ?? "").trim(),
          specialist: t.specialist,
          tier: t.tier,
          after: Array.isArray(t.after) ? [...t.after] : [],
          state: /** @type {TaskState} */ ("waiting"),
          round: 0,
        }));
        return finalizeFlow(
          {
            title: String(event.title ?? "").trim(),
            phase: "plan",
            startedAt: event.at,
            closedAt: null,
            tasks,
            runs: [],
            replans: [],
            history: [],
          },
          event.at,
        );
      }

      // Re-plan: preserve matched tasks' state and round by trimmed title,
      // and re-match every run's taskN against the new task numbering.
      const prevByTitle = new Map();
      for (const prevTask of flow.tasks) {
        prevByTitle.set(prevTask.title.trim(), prevTask);
      }

      const tasks = rawTasks.map((t, idx) => {
        const trimmedTitle = String(t.title ?? "").trim();
        const prevTask = prevByTitle.get(trimmedTitle);
        return {
          n: idx + 1,
          title: trimmedTitle,
          specialist: t.specialist,
          tier: t.tier,
          after: Array.isArray(t.after) ? [...t.after] : [],
          state: /** @type {TaskState} */ (
            prevTask ? prevTask.state : "waiting"
          ),
          round: prevTask ? prevTask.round : 0,
        };
      });

      const taskNByTitle = new Map(tasks.map((t) => [t.title, t.n]));
      const runs = flow.runs.map((r) => {
        const runTitle = String(r.title ?? "").trim();
        const matchedN =
          runTitle !== "" && taskNByTitle.has(runTitle)
            ? taskNByTitle.get(runTitle)
            : null;
        return {
          ...cloneRun(r),
          taskN: matchedN ?? null,
        };
      });

      return finalizeFlow(
        {
          ...flow,
          title:
            event.title !== undefined ? String(event.title).trim() : flow.title,
          tasks,
          runs,
          replans: [...flow.replans, { at: event.at, total: tasks.length }],
        },
        event.at,
      );
    }

    case "phase": {
      if (!flow || !VALID_PHASES.has(event.phase)) {
        return flow;
      }
      return finalizeFlow(
        {
          ...flow,
          phase: event.phase,
        },
        event.at,
      );
    }

    case "run.start": {
      if (!flow) {
        return flow;
      }
      const trimmedTitle = String(event.title ?? "").trim();
      const matchedTask =
        trimmedTitle !== ""
          ? flow.tasks.find((t) => t.title.trim() === trimmedTitle)
          : undefined;
      const taskN = matchedTask ? matchedTask.n : null;

      // A run id the flow already has is the same agent starting again (a
      // follow-up message, or the host waking a background agent). Keep one
      // row: reopen it if it had ended, and never append a duplicate.
      const existingRun = flow.runs.find((r) => r.id === event.id);
      if (existingRun) {
        const resumedTaskN = existingRun.taskN ?? taskN;
        return finalizeFlow(
          {
            ...flow,
            tasks: flow.tasks.map((t) =>
              existingRun.endedAt !== null &&
              resumedTaskN !== null &&
              t.n === resumedTaskN &&
              t.state !== "accepted"
                ? {
                    ...cloneTask(t),
                    state: /** @type {TaskState} */ ("running"),
                  }
                : cloneTask(t),
            ),
            runs: flow.runs.map((r) => {
              if (r.id !== event.id) return cloneRun(r);
              const nextActivityAt = Number.isFinite(event.at)
                ? event.at
                : (r.lastActivityAt ?? r.startedAt);
              if (r.endedAt !== null) {
                return {
                  ...cloneRun(r),
                  taskN: resumedTaskN,
                  lastActivityAt: nextActivityAt,
                  waiting: false,
                  endedAt: null,
                  status: /** @type {RunStatus} */ ("running"),
                };
              }
              return {
                ...cloneRun(r),
                waiting: false,
                lastActivityAt: Math.max(
                  r.lastActivityAt ?? r.startedAt,
                  nextActivityAt,
                ),
              };
            }),
          },
          event.at,
        );
      }

      const tasks = flow.tasks.map((t) =>
        taskN !== null && t.n === taskN
          ? { ...cloneTask(t), state: /** @type {TaskState} */ ("running") }
          : cloneTask(t),
      );

      /** @type {Run} */
      const newRun = {
        id: event.id,
        harness: event.harness,
        agent: event.agent,
        model: event.model,
        effort: event.effort ?? null,
        delegate: event.delegate ?? null,
        title: event.title,
        taskN,
        startedAt: event.at,
        lastActivityAt: event.at,
        waiting: false,
        endedAt: null,
        status: "running",
        tokens: {
          input: event.tokens?.input ?? 0,
          output: event.tokens?.output ?? 0,
          cacheRead: event.tokens?.cacheRead ?? 0,
          cacheWrite: event.tokens?.cacheWrite ?? 0,
        },
        delegateTokens: parseDelegateTokens(event.delegateTokens, null),
        steps: event.steps
          ? {
              done: event.steps.done ?? 0,
              total: event.steps.total ?? 0,
              note: event.steps.note ?? "",
            }
          : null,
        contextPct: event.contextPct ?? null,
        role: event.role ?? "worker",
      };

      return finalizeFlow(
        {
          ...flow,
          tasks,
          runs: [...flow.runs, newRun],
        },
        event.at,
      );
    }

    case "run.progress": {
      if (!flow) {
        return flow;
      }
      const idx = flow.runs.findIndex((r) => r.id === event.id);
      if (idx === -1) {
        return flow;
      }

      const runs = flow.runs.map((r, i) => {
        if (i !== idx) return cloneRun(r);
        const tokens = event.tokens
          ? {
              input: event.tokens.input ?? r.tokens.input,
              output: event.tokens.output ?? r.tokens.output,
              cacheRead: event.tokens.cacheRead ?? r.tokens.cacheRead,
              cacheWrite: event.tokens.cacheWrite ?? r.tokens.cacheWrite,
            }
          : { ...r.tokens };
        const steps =
          event.steps === null
            ? null
            : event.steps !== undefined
              ? {
                  done: event.steps.done ?? r.steps?.done ?? 0,
                  total: event.steps.total ?? r.steps?.total ?? 0,
                  note: event.steps.note ?? r.steps?.note ?? "",
                }
              : r.steps
                ? { ...r.steps }
                : null;
        const contextPct =
          event.contextPct !== undefined ? event.contextPct : r.contextPct;
        const delegate =
          typeof event.delegate === "string" && event.delegate.trim().length > 0
            ? event.delegate.trim()
            : (r.delegate ?? null);
        const prevDelegateTokens = r.delegateTokens
          ? {
              input: r.delegateTokens.input,
              output: r.delegateTokens.output,
              thinking: r.delegateTokens.thinking,
              cacheRead: r.delegateTokens.cacheRead,
            }
          : null;
        const delegateTokens =
          event.delegateTokens !== undefined
            ? parseDelegateTokens(event.delegateTokens, prevDelegateTokens)
            : prevDelegateTokens;
        const lastActivityAt = Number.isFinite(event.at)
          ? Math.max(r.lastActivityAt ?? r.startedAt, event.at)
          : (r.lastActivityAt ?? r.startedAt);
        return {
          ...cloneRun(r),
          lastActivityAt,
          // Any report that does not say "waiting" is the run doing something.
          waiting: event.waiting === true,
          delegate,
          tokens,
          delegateTokens,
          steps,
          contextPct,
        };
      });

      return finalizeFlow(
        {
          ...flow,
          runs,
        },
        event.at,
      );
    }

    case "run.end": {
      if (!flow) {
        return flow;
      }
      const targetRun = flow.runs.find((r) => r.id === event.id);
      if (!targetRun) {
        return flow;
      }

      const runs = flow.runs.map((r) => {
        if (r.id !== event.id) return cloneRun(r);
        const tokens = event.tokens
          ? {
              input: event.tokens.input ?? r.tokens.input,
              output: event.tokens.output ?? r.tokens.output,
              cacheRead: event.tokens.cacheRead ?? r.tokens.cacheRead,
              cacheWrite: event.tokens.cacheWrite ?? r.tokens.cacheWrite,
            }
          : { ...r.tokens };
        return {
          ...cloneRun(r),
          lastActivityAt: Number.isFinite(event.at)
            ? Math.max(r.lastActivityAt ?? r.startedAt, event.at)
            : (r.lastActivityAt ?? r.startedAt),
          endedAt: event.at,
          status: event.status,
          tokens,
        };
      });

      const tasks = flow.tasks.map((t) => {
        if (targetRun.taskN !== null && t.n === targetRun.taskN) {
          if (event.status === "done") {
            return {
              ...cloneTask(t),
              state: /** @type {TaskState} */ ("review"),
            };
          }
          if (event.status === "error") {
            return {
              ...cloneTask(t),
              state: /** @type {TaskState} */ ("returned"),
            };
          }
        }
        return cloneTask(t);
      });

      return finalizeFlow(
        {
          ...flow,
          tasks,
          runs,
        },
        event.at,
      );
    }

    case "task.accept": {
      if (!flow) {
        return flow;
      }
      if (!flow.tasks.some((t) => t.n === event.n)) {
        return flow;
      }
      const tasks = flow.tasks.map((t) =>
        t.n === event.n
          ? { ...cloneTask(t), state: /** @type {TaskState} */ ("accepted") }
          : cloneTask(t),
      );
      return finalizeFlow(
        {
          ...flow,
          tasks,
        },
        event.at,
      );
    }

    case "task.return": {
      if (!flow) {
        return flow;
      }
      if (!flow.tasks.some((t) => t.n === event.n)) {
        return flow;
      }
      const tasks = flow.tasks.map((t) =>
        t.n === event.n
          ? {
              ...cloneTask(t),
              state: /** @type {TaskState} */ ("returned"),
              round: t.round + 1,
            }
          : cloneTask(t),
      );
      return finalizeFlow(
        {
          ...flow,
          tasks,
        },
        event.at,
      );
    }

    case "close": {
      if (!flow) {
        return flow;
      }
      // Closing ends the flow, so nothing in it is still running: end every
      // open run (the lead's included) or its row stays blue and its clock
      // keeps counting for as long as the session stays open.
      return finalizeFlow(
        {
          ...flow,
          phase: "close",
          closedAt: event.at,
          runs: flow.runs.map((r) =>
            r.endedAt === null
              ? {
                  ...cloneRun(r),
                  lastActivityAt: Number.isFinite(event.at)
                    ? Math.max(r.lastActivityAt ?? r.startedAt, event.at)
                    : (r.lastActivityAt ?? r.startedAt),
                  endedAt: event.at,
                  status: /** @type {RunStatus} */ ("done"),
                }
              : cloneRun(r),
          ),
        },
        event.at,
      );
    }

    default:
      return flow;
  }
}

/**
 * Returns the number of tasks in `flow` that are not yet `"accepted"`.
 *
 * @param {Flow | null} flow
 * @returns {number}
 */
export function remaining(flow) {
  if (!flow) return 0;
  return flow.tasks.filter((t) => t.state !== "accepted").length;
}

/**
 * Computes burn-down series for `flow`:
 * - `points`: `{ at, remaining }[]` from `flow.history`
 * - `replans`: `{ at, total }[]` from `flow.replans`
 * - `ideal`: two-point straight line `[{ at: flow.startedAt, remaining: firstTotal }, { at: lastPointAt, remaining: 0 }]`
 *   where `firstTotal` is `flow.history[0]?.remaining ?? flow.tasks.length` and `lastPointAt` is the last
 *   history point's `at` (`flow.history[flow.history.length - 1]?.at ?? flow.startedAt`).
 *
 * @param {Flow | null} flow
 * @returns {BurnDown}
 */
export function burnDown(flow) {
  if (!flow) {
    return { points: [], replans: [], ideal: [] };
  }
  const points = flow.history.map((p) => ({
    at: p.at,
    remaining: p.remaining,
  }));
  const replans = flow.replans.map((r) => ({
    at: r.at,
    total: r.total,
  }));
  const firstTotal =
    points.length > 0 ? points[0].remaining : flow.tasks.length;
  const lastAt =
    points.length > 0 ? points[points.length - 1].at : flow.startedAt;
  const ideal = [
    { at: flow.startedAt, remaining: firstTotal },
    { at: lastAt, remaining: 0 },
  ];
  return { points, replans, ideal };
}

/**
 * Builds the task board rows with unresolved dependency numbers in `waitingOn`.
 *
 * @param {Flow | null} flow
 * @returns {TaskBoardRow[]}
 */
export function taskBoard(flow) {
  if (!flow) return [];
  const accepted = new Set(
    flow.tasks.filter((t) => t.state === "accepted").map((t) => t.n),
  );
  return flow.tasks.map((t) => ({
    n: t.n,
    title: t.title,
    specialist: t.specialist,
    tier: t.tier,
    state: t.state,
    round: t.round,
    after: [...t.after],
    waitingOn: t.after.filter((dep) => !accepted.has(dep)),
  }));
}

/**
 * Finds the first matching price entry for `model`, or `null` if unpriced.
 *
 * @param {unknown} model
 * @returns {{ re: RegExp, input: number, output: number, cacheRead: number, cacheWrite: number } | null}
 */
function findPrice(model) {
  if (typeof model !== "string" || model.trim().length === 0) {
    return null;
  }
  return PRICE_RULES.find((rule) => rule.re.test(model)) ?? null;
}

/**
 * Estimates USD cost for the driver model (`run.model` + `run.tokens`),
 * or returns `null` if the driver model has no price entry.
 *
 * @param {Run | null | undefined} run
 * @returns {number | null}
 */
function driverCost(run) {
  if (!run) {
    return null;
  }
  const price = findPrice(run.model);
  if (!price) {
    return null;
  }
  const tokens = run.tokens ?? {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
  };
  const input = tokens.input ?? 0;
  const output = tokens.output ?? 0;
  const cacheRead = tokens.cacheRead ?? 0;
  const cacheWrite = tokens.cacheWrite ?? 0;

  return (
    (input * price.input +
      output * price.output +
      cacheRead * price.cacheRead +
      cacheWrite * price.cacheWrite) /
    1_000_000
  );
}

/**
 * Estimates USD cost for the delegated model (`run.delegate` + `run.delegateTokens`),
 * or returns `null` unless `run.delegate` and `run.delegateTokens` are set and
 * the delegate model has a price entry.
 *
 * Assumption: `thinking` tokens are priced as `output` tokens at the delegate
 * model's output rate.
 *
 * @param {Run | null | undefined} run
 * @returns {number | null}
 */
export function delegateCost(run) {
  if (
    !run ||
    typeof run.delegate !== "string" ||
    run.delegate.trim().length === 0
  ) {
    return null;
  }
  if (!run.delegateTokens || typeof run.delegateTokens !== "object") {
    return null;
  }
  const price = findPrice(run.delegate);
  if (!price) {
    return null;
  }
  const dt = parseDelegateTokens(run.delegateTokens, null);
  if (!dt) {
    return null;
  }
  // Assumption: price `thinking` tokens as `output` tokens.
  return (
    (dt.input * price.input +
      (dt.output + dt.thinking) * price.output +
      dt.cacheRead * price.cacheRead) /
    1_000_000
  );
}

/**
 * Estimates USD cost for a single run (driver cost + delegate cost), or returns
 * `null` only when neither part is priced.
 *
 * @param {Run | null | undefined} run
 * @returns {number | null}
 */
export function runCost(run) {
  if (!run) {
    return null;
  }
  const drv = driverCost(run);
  const del = delegateCost(run);
  if (drv === null && del === null) {
    return null;
  }
  return (drv ?? 0) + (del ?? 0);
}

/**
 * Summarizes spend across all runs in `flow`, broken down by model, role (lead vs workers),
 * unpriced run/token totals, and delegated run counts (including `unpriced` delegated runs).
 *
 * @param {Flow | null} flow
 * @returns {SpendSummary}
 */
export function spend(flow) {
  /** @type {Record<string, number>} */
  const byModel = {};
  /** @type {Record<string, number>} */
  const delegatedByModel = {};
  let total = 0;
  let lead = 0;
  let workers = 0;
  let unpricedRuns = 0;
  let unpricedTokens = 0;
  let delegatedRuns = 0;
  let delegatedUnpriced = 0;

  if (!flow) {
    return {
      total: 0,
      byModel,
      lead: 0,
      workers: 0,
      unpriced: { runs: 0, tokens: 0 },
      delegated: { runs: 0, unpriced: 0, byModel: delegatedByModel },
    };
  }

  for (const run of flow.runs) {
    const drvCost = driverCost(run);
    const delCost = delegateCost(run);

    if (typeof run.delegate === "string" && run.delegate.trim().length > 0) {
      const delModel = run.delegate.trim();
      delegatedRuns += 1;
      delegatedByModel[delModel] = (delegatedByModel[delModel] ?? 0) + 1;
      if (delCost === null) {
        delegatedUnpriced += 1;
      } else {
        total += delCost;
        workers += delCost;
        byModel[delModel] = (byModel[delModel] ?? 0) + delCost;
      }
    }

    if (drvCost !== null) {
      total += drvCost;
      byModel[run.model] = (byModel[run.model] ?? 0) + drvCost;
      if (run.role === "lead") {
        lead += drvCost;
      } else {
        workers += drvCost;
      }
    } else if (delCost === null) {
      unpricedRuns += 1;
      const t = run.tokens ?? {
        input: 0,
        output: 0,
        cacheRead: 0,
        cacheWrite: 0,
      };
      unpricedTokens +=
        (t.input ?? 0) +
        (t.output ?? 0) +
        (t.cacheRead ?? 0) +
        (t.cacheWrite ?? 0);
    }
  }

  return {
    total,
    byModel,
    lead,
    workers,
    unpriced: {
      runs: unpricedRuns,
      tokens: unpricedTokens,
    },
    delegated: {
      runs: delegatedRuns,
      unpriced: delegatedUnpriced,
      byModel: delegatedByModel,
    },
  };
}

/**
 * Inspects running worker runs in `flow` and classifies their activity state
 * (`"active"`, `"quiet"`, or `"stalled"`) relative to `now`.
 *
 * @param {Flow | null | undefined} flow
 * @param {number} now
 * @param {{ quietMs?: number, stallMs?: number, waitingStallMs?: number }} [options]
 * @returns {StallRow[]}
 */
export function stalls(
  flow,
  now,
  {
    quietMs = DEFAULT_QUIET_MS,
    stallMs = DEFAULT_STALL_MS,
    waitingStallMs = DEFAULT_WAITING_STALL_MS,
  } = {},
) {
  if (!flow || flow.closedAt !== null || !Array.isArray(flow.runs)) {
    return [];
  }
  const nowNum = Number(now) || 0;
  /** @type {StallRow[]} */
  const rows = [];
  for (const run of flow.runs) {
    if (run.status !== "running" || run.role === "lead") {
      continue;
    }
    const lastAt = Number.isFinite(run.lastActivityAt)
      ? run.lastActivityAt
      : run.startedAt;
    const idleMs = Math.max(0, nowNum - lastAt);
    // Silence while waiting on its own work or on Gemini is expected, up to a
    // longer limit; past it, the run is stalled like any other.
    const isWaiting = run.waiting === true || Boolean(run.delegate);
    const limit = isWaiting ? Math.max(stallMs, waitingStallMs) : stallMs;
    /** @type {StallState} */
    const state =
      idleMs >= limit
        ? "stalled"
        : idleMs >= quietMs
          ? isWaiting
            ? "waiting"
            : "quiet"
          : "active";
    rows.push({
      id: run.id,
      agent: run.agent,
      title: run.title,
      taskN: run.taskN,
      lastActivityAt: lastAt,
      idleMs,
      state,
    });
  }
  return rows;
}
