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

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  DEFAULT_QUIET_MS,
  DEFAULT_STALL_MS,
  DEFAULT_WAITING_STALL_MS,
  burnDown,
  initialFlow,
  reduce,
  remaining,
  runCost,
  spend,
  stalls,
  taskBoard,
} from "./core.mjs";

function deepFreeze(obj) {
  if (obj === null || typeof obj !== "object") {
    return obj;
  }
  Object.freeze(obj);
  for (const value of Object.values(obj)) {
    deepFreeze(value);
  }
  return obj;
}

test("initialFlow returns null and plan creates tasks with dependency readiness", () => {
  assert.equal(initialFlow(), null);

  const flow = reduce(initialFlow(), {
    type: "plan",
    at: 1000,
    title: "Orchestrator rollout",
    tasks: [
      { title: "Build core", specialist: "wren", tier: "core", after: [] },
      { title: "Wire hooks", specialist: "forge", tier: "core", after: [1] },
      { title: "Run smoke", specialist: "scout", tier: "fast", after: [1, 2] },
    ],
  });

  assert.equal(flow.title, "Orchestrator rollout");
  assert.equal(flow.phase, "plan");
  assert.equal(flow.startedAt, 1000);
  assert.equal(flow.closedAt, null);
  assert.equal(remaining(flow), 3);
  assert.deepEqual(flow.tasks, [
    {
      n: 1,
      title: "Build core",
      specialist: "wren",
      tier: "core",
      after: [],
      state: "ready",
      round: 0,
    },
    {
      n: 2,
      title: "Wire hooks",
      specialist: "forge",
      tier: "core",
      after: [1],
      state: "waiting",
      round: 0,
    },
    {
      n: 3,
      title: "Run smoke",
      specialist: "scout",
      tier: "fast",
      after: [1, 2],
      state: "waiting",
      round: 0,
    },
  ]);

  assert.deepEqual(taskBoard(flow), [
    {
      n: 1,
      title: "Build core",
      specialist: "wren",
      tier: "core",
      state: "ready",
      round: 0,
      after: [],
      waitingOn: [],
    },
    {
      n: 2,
      title: "Wire hooks",
      specialist: "forge",
      tier: "core",
      state: "waiting",
      round: 0,
      after: [1],
      waitingOn: [1],
    },
    {
      n: 3,
      title: "Run smoke",
      specialist: "scout",
      tier: "fast",
      state: "waiting",
      round: 0,
      after: [1, 2],
      waitingOn: [1, 2],
    },
  ]);
});

test("run.start matches by trimmed title and sets running; unmatched title gives taskN null", () => {
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Flow",
    tasks: [
      { title: "Build core", specialist: "wren", tier: "core", after: [] },
    ],
  });

  flow = reduce(flow, {
    type: "run.start",
    at: 1100,
    id: "run-1",
    harness: "claude-code",
    agent: "wren",
    model: "claude-sonnet-5-5",
    effort: "high",
    title: "  Build core  ",
    role: "worker",
  });

  assert.equal(flow.runs.length, 1);
  assert.equal(flow.runs[0].taskN, 1);
  assert.equal(flow.tasks[0].state, "running");

  flow = reduce(flow, {
    type: "run.start",
    at: 1200,
    id: "run-lead",
    harness: "claude-code",
    agent: "beacon",
    model: "claude-opus-5-5",
    effort: "high",
    title: "Ad-hoc synthesis",
    role: "lead",
  });

  assert.equal(flow.runs.length, 2);
  assert.equal(flow.runs[1].taskN, null);
  assert.equal(flow.runs[1].role, "lead");
});

test("run.end done moves task to review; accept/return rounds and dependency unblocking", () => {
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Review loop",
    tasks: [
      { title: "Task A", specialist: "wren", tier: "core", after: [] },
      { title: "Task B", specialist: "scout", tier: "fast", after: [1] },
    ],
  });

  flow = reduce(flow, {
    type: "run.start",
    at: 1100,
    id: "r1",
    harness: "antigravity",
    agent: "wren",
    model: "flash",
    effort: null,
    title: "Task A",
    role: "worker",
  });
  assert.equal(flow.tasks[0].state, "running");

  flow = reduce(flow, {
    type: "run.end",
    at: 1200,
    id: "r1",
    status: "done",
    tokens: { input: 1000, output: 500, cacheRead: 0, cacheWrite: 0 },
  });
  assert.equal(flow.tasks[0].state, "review");
  assert.equal(flow.runs[0].status, "done");
  assert.equal(flow.runs[0].endedAt, 1200);

  // Return task 1 -> state "returned", round 1
  flow = reduce(flow, { type: "task.return", at: 1300, n: 1 });
  assert.equal(flow.tasks[0].state, "returned");
  assert.equal(flow.tasks[0].round, 1);
  assert.equal(flow.tasks[1].state, "waiting");

  // Re-run returned task -> goes to "running" and keeps its round (1)
  flow = reduce(flow, {
    type: "run.start",
    at: 1400,
    id: "r2",
    harness: "antigravity",
    agent: "wren",
    model: "flash",
    effort: null,
    title: "Task A",
    role: "worker",
  });
  assert.equal(flow.tasks[0].state, "running");
  assert.equal(flow.tasks[0].round, 1);

  flow = reduce(flow, {
    type: "run.end",
    at: 1500,
    id: "r2",
    status: "done",
  });
  assert.equal(flow.tasks[0].state, "review");

  // Accept task 1 -> unblocks task 2 from "waiting" to "ready"
  flow = reduce(flow, { type: "task.accept", at: 1600, n: 1 });
  assert.equal(flow.tasks[0].state, "accepted");
  assert.equal(flow.tasks[0].round, 1);
  assert.equal(flow.tasks[1].state, "ready");
  assert.deepEqual(taskBoard(flow)[1].waitingOn, []);
});

test("re-plan keeps accepted tasks by matching title and records the replan", () => {
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Initial Plan",
    tasks: [
      { title: "Step 1", specialist: "wren", tier: "core", after: [] },
      { title: "Step 2", specialist: "wren", tier: "core", after: [1] },
    ],
  });

  flow = reduce(flow, { type: "task.accept", at: 2000, n: 1 });
  assert.equal(flow.tasks[0].state, "accepted");
  assert.equal(remaining(flow), 1);

  flow = reduce(flow, {
    type: "plan",
    at: 3000,
    title: "Revised Plan",
    tasks: [
      { title: "Step 1", specialist: "wren", tier: "core", after: [] },
      { title: "Step 2", specialist: "wren", tier: "core", after: [1] },
      { title: "Step 3", specialist: "scout", tier: "fast", after: [2] },
    ],
  });

  assert.equal(flow.title, "Revised Plan");
  assert.deepEqual(flow.replans, [{ at: 3000, total: 3 }]);
  assert.equal(flow.tasks[0].state, "accepted");
  assert.equal(flow.tasks[1].state, "ready");
  assert.equal(flow.tasks[2].state, "waiting");
  assert.equal(remaining(flow), 2);
});

test("history appends only on remaining count change and burnDown computes full series", () => {
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "BurnDown Script",
    tasks: [
      { title: "T1", specialist: "wren", tier: "core", after: [] },
      { title: "T2", specialist: "scout", tier: "fast", after: [1] },
    ],
  });

  // Phase, run.start, run.progress, run.end, task.return do not change remaining count
  flow = reduce(flow, { type: "phase", at: 1100, phase: "delegate" });
  flow = reduce(flow, {
    type: "run.start",
    at: 1200,
    id: "r1",
    harness: "claude-code",
    agent: "wren",
    model: "sonnet",
    effort: "high",
    title: "T1",
    role: "worker",
  });
  flow = reduce(flow, {
    type: "run.progress",
    at: 1300,
    id: "r1",
    steps: { done: 1, total: 2, note: "Coding" },
    contextPct: 24,
  });
  flow = reduce(flow, { type: "run.end", at: 1400, id: "r1", status: "done" });
  assert.deepEqual(flow.history, [{ at: 1000, remaining: 2 }]);

  // Accept T1 at 2000 -> remaining drops to 1
  flow = reduce(flow, { type: "task.accept", at: 2000, n: 1 });
  assert.deepEqual(flow.history, [
    { at: 1000, remaining: 2 },
    { at: 2000, remaining: 1 },
  ]);

  // Re-plan at 2500 adding T3 -> remaining rises to 2
  flow = reduce(flow, {
    type: "plan",
    at: 2500,
    title: "BurnDown Script",
    tasks: [
      { title: "T1", specialist: "wren", tier: "core", after: [] },
      { title: "T2", specialist: "scout", tier: "fast", after: [1] },
      { title: "T3", specialist: "quill", tier: "fast", after: [2] },
    ],
  });

  // Accept T2 at 3000 and T3 at 4000, then close at 4500 (close does not change remaining)
  flow = reduce(flow, { type: "task.accept", at: 3000, n: 2 });
  flow = reduce(flow, { type: "task.accept", at: 4000, n: 3 });
  flow = reduce(flow, { type: "close", at: 4500 });
  assert.equal(flow.phase, "close");
  assert.equal(flow.closedAt, 4500);

  const bd = burnDown(flow);
  assert.deepEqual(bd, {
    points: [
      { at: 1000, remaining: 2 },
      { at: 2000, remaining: 1 },
      { at: 2500, remaining: 2 },
      { at: 3000, remaining: 1 },
      { at: 4000, remaining: 0 },
    ],
    replans: [{ at: 2500, total: 3 }],
    ideal: [
      { at: 1000, remaining: 2 },
      { at: 4000, remaining: 0 },
    ],
  });
});

test("spend splits lead and workers, prices sonnet exactly, and puts gemini in unpriced", () => {
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Cost Check",
    tasks: [{ title: "T1", specialist: "wren", tier: "core", after: [] }],
  });

  // 1) Worker Sonnet run:
  //    Rates for /sonnet/i: [input=2, output=10, cacheRead=0.2, cacheWrite=2.5] per 1M tokens.
  //    Tokens: input=100_000, output=20_000, cacheRead=50_000, cacheWrite=10_000
  //    Arithmetic:
  //      (100_000 * 2 + 20_000 * 10 + 50_000 * 0.2 + 10_000 * 2.5) / 1_000_000
  //      = (200_000 + 200_000 + 10_000 + 25_000) / 1_000_000
  //      = 435_000 / 1_000_000
  //      = 0.435 USD
  flow = reduce(flow, {
    type: "run.start",
    at: 1100,
    id: "sonnet-worker",
    harness: "claude-code",
    agent: "wren",
    model: "claude-sonnet-5-5",
    effort: "high",
    title: "T1",
    role: "worker",
  });
  flow = reduce(flow, {
    type: "run.end",
    at: 1200,
    id: "sonnet-worker",
    status: "done",
    tokens: {
      input: 100_000,
      output: 20_000,
      cacheRead: 50_000,
      cacheWrite: 10_000,
    },
  });

  const expectedSonnetUsd =
    (100_000 * 2 + 20_000 * 10 + 50_000 * 0.2 + 10_000 * 2.5) / 1_000_000;
  assert.equal(expectedSonnetUsd, 0.435);
  assert.equal(runCost(flow.runs[0]), 0.435);

  // 2) Lead Opus 5.5 run:
  //    Rates for /opus-5-5/i: [input=4, output=20, cacheRead=0.2, cacheWrite=5] per 1M tokens.
  //    Tokens: input=50_000, output=5_000, cacheRead=0, cacheWrite=0
  //    Arithmetic: (50_000 * 4 + 5_000 * 20) / 1_000_000 = 300_000 / 1_000_000 = 0.3 USD
  flow = reduce(flow, {
    type: "run.start",
    at: 1300,
    id: "opus-lead",
    harness: "claude-code",
    agent: "beacon",
    model: "claude-opus-5-5",
    effort: "high",
    title: "Plan & review",
    role: "lead",
  });
  flow = reduce(flow, {
    type: "run.progress",
    at: 1350,
    id: "opus-lead",
    tokens: { input: 50_000, output: 5_000, cacheRead: 0, cacheWrite: 0 },
  });
  assert.equal(runCost(flow.runs[1]), 0.3);

  // 3) Unpriced Gemini run:
  flow = reduce(flow, {
    type: "run.start",
    at: 1400,
    id: "gemini-worker",
    harness: "antigravity",
    agent: "scout",
    model: "gemini-3.8-flash-high",
    effort: null,
    title: "CI check",
    role: "worker",
  });
  flow = reduce(flow, {
    type: "run.end",
    at: 1500,
    id: "gemini-worker",
    status: "done",
    tokens: { input: 30_000, output: 4_000, cacheRead: 6_000, cacheWrite: 0 },
  });
  assert.equal(runCost(flow.runs[2]), null);

  const summary = spend(flow);
  assert.deepEqual(summary, {
    total: 0.735,
    byModel: {
      "claude-sonnet-5-5": 0.435,
      "claude-opus-5-5": 0.3,
    },
    lead: 0.3,
    workers: 0.435,
    unpriced: {
      runs: 1,
      tokens: 40_000,
    },
    delegated: {
      runs: 0,
      byModel: {},
    },
  });
});

test("delegate model on run.start, run.progress, and spend.delegated summary", () => {
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Delegated Flow",
    tasks: [
      { title: "T1", specialist: "wren", tier: "core", after: [] },
      { title: "T2", specialist: "atlas", tier: "core", after: [] },
      { title: "T3", specialist: "scout", tier: "fast", after: [] },
    ],
  });

  // 1) run.start without delegate -> defaults to null
  flow = reduce(flow, {
    type: "run.start",
    at: 1100,
    id: "r1",
    harness: "claude-code",
    agent: "wren",
    model: "claude-haiku-5-5",
    effort: "medium",
    title: "T1",
    role: "worker",
  });
  assert.equal(flow.runs[0].delegate, null);

  // 2) run.start with delegate -> sets delegate immediately
  flow = reduce(flow, {
    type: "run.start",
    at: 1150,
    id: "r2",
    harness: "claude-code",
    agent: "atlas",
    model: "claude-haiku-5-5",
    effort: "medium",
    delegate: "gemini-4-argon-high",
    title: "T2",
    role: "worker",
  });
  assert.equal(flow.runs[1].delegate, "gemini-4-argon-high");

  // 3) run.progress with non-empty delegate sets it on r1
  flow = reduce(flow, {
    type: "run.progress",
    at: 1200,
    id: "r1",
    steps: { done: 1, total: 2, note: "delegated via agy" },
    delegate: "gemini-4-argon-high",
  });
  assert.equal(flow.runs[0].delegate, "gemini-4-argon-high");

  // 4) Subsequent run.progress without delegate (or empty string) does not clear it
  flow = reduce(flow, {
    type: "run.progress",
    at: 1250,
    id: "r1",
    steps: { done: 2, total: 2, note: "done" },
    tokens: { input: 10_000, output: 2_000, cacheRead: 0, cacheWrite: 0 },
  });
  assert.equal(flow.runs[0].delegate, "gemini-4-argon-high");

  flow = reduce(flow, {
    type: "run.progress",
    at: 1260,
    id: "r1",
    delegate: "",
  });
  assert.equal(flow.runs[0].delegate, "gemini-4-argon-high");

  // 5) Another delegated run with a different Gemini model
  flow = reduce(flow, {
    type: "run.start",
    at: 1300,
    id: "r3",
    harness: "opencode",
    agent: "scout",
    model: "claude-haiku-5-5",
    effort: "medium",
    title: "T3",
    role: "worker",
  });
  flow = reduce(flow, {
    type: "run.progress",
    at: 1350,
    id: "r3",
    steps: { done: 1, total: 1, note: "ci check" },
    delegate: "gemini-3.8-flash-high",
  });
  assert.equal(flow.runs[2].delegate, "gemini-3.8-flash-high");

  // Driver cost is still estimated from run.model (claude-haiku-5-5: [1, 5, 0.1, 1.25] per 1M)
  // r1 tokens: 10_000 * 1 + 2_000 * 5 = 20_000 / 1_000_000 = 0.02 USD
  const summary = spend(flow);
  assert.equal(summary.total, 0.02);
  assert.deepEqual(summary.delegated, {
    runs: 3,
    byModel: {
      "gemini-4-argon-high": 2,
      "gemini-3.8-flash-high": 1,
    },
  });
});

test("reduce never mutates its input and unknown events or unknown run ids are no-ops", () => {
  const planEvent = deepFreeze({
    type: "plan",
    at: 1000,
    title: "Immutable Flow",
    tasks: [
      { title: "Task 1", specialist: "wren", tier: "core", after: [] },
      { title: "Task 2", specialist: "forge", tier: "core", after: [1] },
    ],
  });

  const flow1 = deepFreeze(reduce(null, planEvent));
  const flow2 = deepFreeze(
    reduce(
      flow1,
      deepFreeze({
        type: "run.start",
        at: 1100,
        id: "r1",
        harness: "opencode",
        agent: "wren",
        model: "anthropic/claude-haiku-5-5",
        effort: "medium",
        title: "Task 1",
        role: "worker",
      }),
    ),
  );

  // Unknown event type and unknown run id in run.progress / run.end return flow unchanged
  assert.equal(
    reduce(flow2, deepFreeze({ type: "unknown.event", at: 1200 })),
    flow2,
  );
  assert.equal(
    reduce(
      flow2,
      deepFreeze({
        type: "run.progress",
        at: 1200,
        id: "missing-id",
        contextPct: 50,
      }),
    ),
    flow2,
  );
  assert.equal(
    reduce(
      flow2,
      deepFreeze({
        type: "run.end",
        at: 1200,
        id: "missing-id",
        status: "done",
      }),
    ),
    flow2,
  );

  const flow3 = deepFreeze(
    reduce(
      flow2,
      deepFreeze({
        type: "run.progress",
        at: 1250,
        id: "r1",
        tokens: { input: 100, output: 50 },
        steps: { done: 1, total: 3, note: "step 1" },
        contextPct: 12,
      }),
    ),
  );
  assert.notEqual(flow3, flow2);
  assert.equal(flow2.runs[0].tokens.input, 0);
  assert.equal(flow3.runs[0].tokens.input, 100);
});

test("run.end with status error moves task to returned with round unchanged", () => {
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Error Flow",
    tasks: [{ title: "Task A", specialist: "wren", tier: "core", after: [] }],
  });

  flow = reduce(flow, {
    type: "run.start",
    at: 1100,
    id: "r1",
    harness: "claude-code",
    agent: "wren",
    model: "sonnet",
    effort: "high",
    title: "Task A",
    role: "worker",
  });
  assert.equal(flow.tasks[0].state, "running");

  flow = reduce(flow, {
    type: "run.end",
    at: 1200,
    id: "r1",
    status: "error",
  });
  assert.equal(flow.tasks[0].state, "returned");
  assert.equal(flow.tasks[0].round, 0);
});

test("re-plan re-matches every run taskN by title against the new task list", () => {
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Replan Runs",
    tasks: [
      { title: "A", specialist: "wren", tier: "core", after: [] },
      { title: "B", specialist: "wren", tier: "core", after: [] },
      { title: "C", specialist: "wren", tier: "core", after: [] },
    ],
  });

  flow = reduce(flow, {
    type: "run.start",
    at: 1100,
    id: "r3",
    harness: "claude-code",
    agent: "wren",
    model: "sonnet",
    effort: "high",
    title: "C",
    role: "worker",
  });
  flow = reduce(flow, {
    type: "run.start",
    at: 1150,
    id: "r-dropped",
    harness: "claude-code",
    agent: "wren",
    model: "sonnet",
    effort: "high",
    title: "B",
    role: "worker",
  });
  assert.equal(flow.runs[0].taskN, 3);
  assert.equal(flow.runs[1].taskN, 2);

  flow = reduce(flow, {
    type: "plan",
    at: 1200,
    title: "Replan Runs",
    tasks: [
      { title: "A", specialist: "wren", tier: "core", after: [] },
      { title: "Z", specialist: "wren", tier: "core", after: [] },
      { title: "B", specialist: "wren", tier: "core", after: [] },
      { title: "C", specialist: "wren", tier: "core", after: [] },
    ],
  });
  assert.equal(flow.runs[0].taskN, 4);
  assert.equal(flow.runs[1].taskN, 3);

  // Removing a task sets its run's taskN to null
  flow = reduce(flow, {
    type: "plan",
    at: 1300,
    title: "Replan Runs",
    tasks: [
      { title: "A", specialist: "wren", tier: "core", after: [] },
      { title: "C", specialist: "wren", tier: "core", after: [] },
    ],
  });
  assert.equal(flow.runs[0].taskN, 2);
  assert.equal(flow.runs[1].taskN, null);
});

test("re-plan preserves running, review, and returned task state and round", () => {
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "State Preservation",
    tasks: [
      { title: "A", specialist: "wren", tier: "core", after: [] },
      { title: "B", specialist: "wren", tier: "core", after: [] },
      { title: "C", specialist: "wren", tier: "core", after: [] },
      { title: "D", specialist: "wren", tier: "core", after: [] },
    ],
  });

  // A: returned with round 1
  flow = reduce(flow, { type: "task.return", at: 1100, n: 1 });
  // B: running
  flow = reduce(flow, {
    type: "run.start",
    at: 1200,
    id: "rb",
    harness: "claude-code",
    agent: "wren",
    model: "sonnet",
    effort: "high",
    title: "B",
    role: "worker",
  });
  // C: in review
  flow = reduce(flow, {
    type: "run.start",
    at: 1250,
    id: "rc",
    harness: "claude-code",
    agent: "wren",
    model: "sonnet",
    effort: "high",
    title: "C",
    role: "worker",
  });
  flow = reduce(flow, { type: "run.end", at: 1300, id: "rc", status: "done" });

  // Re-plan where D now depends on B (so D goes from ready -> waiting), while A, B, C keep state & round
  flow = reduce(flow, {
    type: "plan",
    at: 1400,
    title: "State Preservation",
    tasks: [
      { title: "A", specialist: "wren", tier: "core", after: [] },
      { title: "B", specialist: "wren", tier: "core", after: [] },
      { title: "C", specialist: "wren", tier: "core", after: [] },
      { title: "D", specialist: "wren", tier: "core", after: [2] },
    ],
  });

  assert.equal(flow.tasks[0].state, "returned");
  assert.equal(flow.tasks[0].round, 1);
  assert.equal(flow.tasks[1].state, "running");
  assert.equal(flow.tasks[1].round, 0);
  assert.equal(flow.tasks[2].state, "review");
  assert.equal(flow.tasks[2].round, 0);
  assert.equal(flow.tasks[3].state, "waiting");
});

test("close ends every open run, the lead's included", () => {
  const start = (id, role, at) => ({
    type: "run.start",
    at,
    id,
    harness: "claude-code",
    agent: role === "lead" ? "lead" : "wren",
    model: "claude-opus-5-5",
    effort: null,
    title: role === "lead" ? "Lead orchestrator" : "Build",
    role,
  });
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Flow",
    tasks: [{ title: "Build", specialist: "wren", tier: "core", after: [] }],
  });
  flow = reduce(flow, start("lead", "lead", 1000));
  flow = reduce(flow, start("w1", "worker", 1100));
  flow = reduce(flow, { type: "run.end", at: 1500, id: "w1", status: "done" });
  flow = reduce(flow, { type: "task.accept", at: 1600, n: 1 });
  flow = reduce(flow, { type: "close", at: 2000 });

  const lead = flow.runs.find((r) => r.id === "lead");
  assert.equal(lead.status, "done");
  assert.equal(lead.endedAt, 2000);
  // A run that had already ended keeps its own end time.
  assert.equal(flow.runs.find((r) => r.id === "w1").endedAt, 1500);
  assert.equal(flow.runs.filter((r) => r.status === "running").length, 0);
});

test("run.start with an id the flow already has never adds a second row", () => {
  const start = (at) => ({
    type: "run.start",
    at,
    id: "agent-1",
    harness: "claude-code",
    agent: "general-purpose",
    model: "claude-sonnet-5-5",
    effort: null,
    title: "Build",
    role: "worker",
  });
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Flow",
    tasks: [{ title: "Build", specialist: "wren", tier: "core", after: [] }],
  });
  flow = reduce(flow, start(1100));
  flow = reduce(flow, {
    type: "run.progress",
    at: 1200,
    id: "agent-1",
    tokens: { input: 500 },
  });
  // The host wakes the same background agent again while it runs.
  flow = reduce(flow, start(1300));
  flow = reduce(flow, start(1400));
  assert.equal(flow.runs.length, 1);
  assert.equal(flow.runs[0].startedAt, 1100);
  assert.equal(flow.runs[0].tokens.input, 500);

  // A follow-up message after it finished reopens the same row.
  flow = reduce(flow, {
    type: "run.end",
    at: 1500,
    id: "agent-1",
    status: "done",
  });
  assert.equal(flow.tasks[0].state, "review");
  flow = reduce(flow, start(1600));
  assert.equal(flow.runs.length, 1);
  assert.equal(flow.runs[0].status, "running");
  assert.equal(flow.runs[0].endedAt, null);
  assert.equal(flow.runs[0].tokens.input, 500);
  assert.equal(flow.tasks[0].state, "running");
});

test("lastActivityAt tracks run.start, run.progress, reopened runs, run.end, and close", () => {
  const start = (id, title, at, role = "worker") => ({
    type: "run.start",
    at,
    id,
    harness: "antigravity",
    agent: "wren",
    model: "gemini-3.8-flash-high",
    effort: null,
    title,
    role,
  });

  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Activity Flow",
    tasks: [
      { title: "Task 1", specialist: "wren", tier: "core", after: [] },
      { title: "Task 2", specialist: "wren", tier: "core", after: [] },
    ],
  });

  // 1) Initial run.start sets lastActivityAt = startedAt = at
  flow = reduce(flow, start("r1", "Task 1", 1100));
  flow = reduce(flow, start("r2", "Task 2", 1150));
  assert.equal(flow.runs[0].lastActivityAt, 1100);
  assert.equal(flow.runs[1].lastActivityAt, 1150);

  // 2) run.progress advances lastActivityAt when at is finite, never decreases it
  flow = reduce(flow, {
    type: "run.progress",
    at: 1300,
    id: "r1",
    steps: { done: 1, total: 2, note: "step 1" },
  });
  assert.equal(flow.runs[0].lastActivityAt, 1300);

  flow = reduce(flow, {
    type: "run.progress",
    at: 1200,
    id: "r1",
    steps: { done: 2, total: 2, note: "out-of-order timestamp" },
  });
  assert.equal(flow.runs[0].lastActivityAt, 1300);

  flow = reduce(flow, {
    type: "run.progress",
    at: Number.NaN,
    id: "r1",
    contextPct: 40,
  });
  assert.equal(flow.runs[0].lastActivityAt, 1300);

  // 3) run.end updates lastActivityAt
  flow = reduce(flow, {
    type: "run.end",
    at: 1500,
    id: "r1",
    status: "done",
  });
  assert.equal(flow.runs[0].lastActivityAt, 1500);

  // 4) Reopening an ended run on run.start updates lastActivityAt to new at
  flow = reduce(flow, start("r1", "Task 1", 2000));
  assert.equal(flow.runs[0].status, "running");
  assert.equal(flow.runs[0].startedAt, 1100);
  assert.equal(flow.runs[0].lastActivityAt, 2000);

  // 5) close updates lastActivityAt on open runs
  flow = reduce(flow, { type: "close", at: 2500 });
  assert.equal(flow.runs[0].lastActivityAt, 2500);
  assert.equal(flow.runs[1].lastActivityAt, 2500);
});

test("stalls classifies active, quiet, and stalled worker runs and excludes ended and lead runs", () => {
  assert.equal(DEFAULT_QUIET_MS, 5 * 60 * 1000);
  assert.equal(DEFAULT_STALL_MS, 15 * 60 * 1000);
  assert.deepEqual(stalls(null, 10_000), []);

  const t0 = 1_000_000;
  let flow = reduce(null, {
    type: "plan",
    at: t0,
    title: "Watchdog Flow",
    tasks: [
      { title: "Active task", specialist: "wren", tier: "core", after: [] },
      { title: "Quiet task", specialist: "atlas", tier: "core", after: [] },
      { title: "Stalled task", specialist: "forge", tier: "core", after: [] },
      { title: "Done task", specialist: "scout", tier: "fast", after: [] },
    ],
  });

  // Lead run (should be ignored even if idle past stallMs)
  flow = reduce(flow, {
    type: "run.start",
    at: t0,
    id: "run-lead",
    harness: "antigravity",
    agent: "beacon",
    model: "claude-opus-5-5",
    effort: "high",
    title: "Orchestrate",
    role: "lead",
  });

  // Stalled worker: started at t0, no progress since
  flow = reduce(flow, {
    type: "run.start",
    at: t0,
    id: "run-stalled",
    harness: "antigravity",
    agent: "forge",
    model: "gemini-4-argon-high",
    effort: null,
    title: "Stalled task",
    role: "worker",
  });

  // Quiet worker: started at t0, progressed at t0 + 9 min (idle 6 min at t0 + 15 min)
  flow = reduce(flow, {
    type: "run.start",
    at: t0,
    id: "run-quiet",
    harness: "antigravity",
    agent: "atlas",
    model: "gemini-4-argon-high",
    effort: null,
    title: "Quiet task",
    role: "worker",
  });
  flow = reduce(flow, {
    type: "run.progress",
    at: t0 + 9 * 60 * 1000,
    id: "run-quiet",
    steps: { done: 1, total: 3, note: "reading schema" },
  });

  // Active worker: started at t0, progressed at t0 + 13 min (idle 2 min at t0 + 15 min)
  flow = reduce(flow, {
    type: "run.start",
    at: t0,
    id: "run-active",
    harness: "antigravity",
    agent: "wren",
    model: "gemini-4-argon-high",
    effort: null,
    title: "Active task",
    role: "worker",
  });
  flow = reduce(flow, {
    type: "run.progress",
    at: t0 + 13 * 60 * 1000,
    id: "run-active",
    steps: { done: 2, total: 3, note: "running tests" },
  });

  // Ended worker: should be excluded from stalls()
  flow = reduce(flow, {
    type: "run.start",
    at: t0,
    id: "run-done",
    harness: "antigravity",
    agent: "scout",
    model: "gemini-3.8-flash-high",
    effort: null,
    title: "Done task",
    role: "worker",
  });
  flow = reduce(flow, {
    type: "run.end",
    at: t0 + 60 * 1000,
    id: "run-done",
    status: "done",
  });

  const now = t0 + 15 * 60 * 1000;
  assert.deepEqual(stalls(flow, now), [
    {
      id: "run-stalled",
      agent: "forge",
      title: "Stalled task",
      taskN: 3,
      lastActivityAt: t0,
      idleMs: 15 * 60 * 1000,
      state: "stalled",
    },
    {
      id: "run-quiet",
      agent: "atlas",
      title: "Quiet task",
      taskN: 2,
      lastActivityAt: t0 + 9 * 60 * 1000,
      idleMs: 6 * 60 * 1000,
      state: "quiet",
    },
    {
      id: "run-active",
      agent: "wren",
      title: "Active task",
      taskN: 1,
      lastActivityAt: t0 + 13 * 60 * 1000,
      idleMs: 2 * 60 * 1000,
      state: "active",
    },
  ]);

  // Custom thresholds and fallback to startedAt when lastActivityAt is missing
  const customFlow = {
    ...flow,
    runs: [
      {
        ...flow.runs[1],
        lastActivityAt: undefined,
      },
    ],
  };
  assert.deepEqual(
    stalls(customFlow, t0 + 5000, { quietMs: 1000, stallMs: 10_000 }),
    [
      {
        id: "run-stalled",
        agent: "forge",
        title: "Stalled task",
        taskN: 3,
        lastActivityAt: t0,
        idleMs: 5000,
        state: "quiet",
      },
    ],
  );
});

test("a run waiting on its own work or on Gemini reads waiting, not stalled, until the longer limit", () => {
  assert.equal(DEFAULT_WAITING_STALL_MS, 60 * 60 * 1000);
  const min = 60 * 1000;
  const start = (id, extra = {}) => ({
    type: "run.start",
    at: 0,
    id,
    harness: "claude-code",
    agent: "wren",
    model: "claude-haiku-5-5",
    effort: null,
    title: id,
    role: "worker",
    ...extra,
  });
  let flow = reduce(null, { type: "plan", at: 0, title: "F", tasks: [] });
  flow = reduce(flow, start("plain"));
  flow = reduce(flow, start("gemini", { delegate: "gemini-4-argon-high" }));
  flow = reduce(flow, start("held"));
  flow = reduce(flow, {
    type: "run.progress",
    at: 0,
    id: "held",
    waiting: true,
  });

  const stateAt = (t) =>
    Object.fromEntries(stalls(flow, t).map((r) => [r.id, r.state]));

  assert.deepEqual(stateAt(20 * min), {
    plain: "stalled",
    gemini: "waiting",
    held: "waiting",
  });
  assert.deepEqual(stateAt(61 * min), {
    plain: "stalled",
    gemini: "stalled",
    held: "stalled",
  });

  // Activity without the mark means the run is working again: normal limits.
  flow = reduce(flow, {
    type: "run.progress",
    at: 30 * min,
    id: "held",
    tokens: { input: 10 },
  });
  assert.equal(flow.runs.find((r) => r.id === "held").waiting, false);
  assert.equal(stateAt(46 * min).held, "stalled");
});
