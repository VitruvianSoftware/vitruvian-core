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
 * @property {string} title
 * @property {number | null} taskN
 * @property {number} startedAt
 * @property {number | null} endedAt
 * @property {RunStatus} status
 * @property {TokenCounts} tokens
 * @property {StepProgress | null} steps
 * @property {number | null} contextPct
 * @property {RunRole} role
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
 * @typedef {Object} SpendSummary
 * @property {number} total
 * @property {Record<string, number>} byModel
 * @property {number} lead
 * @property {number} workers
 * @property {UnpricedSummary} unpriced
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
 * @property {RunRole} [role]
 * @property {Partial<TokenCounts>} [tokens]
 * @property {Partial<StepProgress> | null} [steps]
 * @property {number | null} [contextPct]
 * @property {RunStatus} [status]
 * @property {number} [n]
 */

const VALID_PHASES = new Set(["plan", "design", "delegate", "review", "close"]);

// rough estimate, not a bill; from savvy-progress PRICES
// Per million tokens: [input, output, cacheRead, cacheWrite]
const PRICES = [
  [/fable|mythos/i, [10, 50, 0.25, 12.5]],
  [/opus-5-5/i, [4, 20, 0.2, 5]],
  [/opus/i, [5, 25, 0.5, 6.25]],
  [/sonnet/i, [2, 10, 0.2, 2.5]],
  [/haiku/i, [1, 5, 0.1, 1.25]],
];

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
    title: run.title,
    taskN: run.taskN,
    startedAt: run.startedAt,
    endedAt: run.endedAt,
    status: run.status,
    tokens: {
      input: run.tokens.input,
      output: run.tokens.output,
      cacheRead: run.tokens.cacheRead,
      cacheWrite: run.tokens.cacheWrite,
    },
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
        title: event.title,
        taskN,
        startedAt: event.at,
        endedAt: null,
        status: "running",
        tokens: {
          input: event.tokens?.input ?? 0,
          output: event.tokens?.output ?? 0,
          cacheRead: event.tokens?.cacheRead ?? 0,
          cacheWrite: event.tokens?.cacheWrite ?? 0,
        },
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
        return {
          ...cloneRun(r),
          tokens,
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
      return finalizeFlow(
        {
          ...flow,
          phase: "close",
          closedAt: event.at,
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
 * Estimates USD cost for a single run, or returns `null` if the model is unpriced
 * (e.g. Gemini, GPT, or local models).
 *
 * @param {Run | null | undefined} run
 * @returns {number | null}
 */
export function runCost(run) {
  if (!run || typeof run.model !== "string") {
    return null;
  }
  const match = PRICES.find(([re]) => re.test(run.model));
  if (!match) {
    return null;
  }
  const [inRate, outRate, cacheReadRate, cacheWriteRate] = match[1];
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
    (input * inRate +
      output * outRate +
      cacheRead * cacheReadRate +
      cacheWrite * cacheWriteRate) /
    1_000_000
  );
}

/**
 * Summarizes spend across all runs in `flow`, broken down by model, role (lead vs workers),
 * and unpriced run/token totals.
 *
 * @param {Flow | null} flow
 * @returns {SpendSummary}
 */
export function spend(flow) {
  /** @type {Record<string, number>} */
  const byModel = {};
  let total = 0;
  let lead = 0;
  let workers = 0;
  let unpricedRuns = 0;
  let unpricedTokens = 0;

  if (!flow) {
    return {
      total: 0,
      byModel,
      lead: 0,
      workers: 0,
      unpriced: { runs: 0, tokens: 0 },
    };
  }

  for (const run of flow.runs) {
    const cost = runCost(run);
    if (cost === null) {
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
    } else {
      total += cost;
      byModel[run.model] = (byModel[run.model] ?? 0) + cost;
      if (run.role === "lead") {
        lead += cost;
      } else {
        workers += cost;
      }
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
  };
}
