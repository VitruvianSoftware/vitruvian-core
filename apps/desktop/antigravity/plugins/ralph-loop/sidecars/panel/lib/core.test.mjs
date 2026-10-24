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
  checkPromiseMatched,
  createLoopState,
  evaluateStopEvent,
  summariseLoops,
  updateLoopIteration,
} from "./core.mjs";

test("checkPromiseMatched detects exact <promise>...</promise> tags", () => {
  assert.equal(
    checkPromiseMatched("All tests pass! <promise>DONE</promise>", "DONE"),
    true,
  );
  assert.equal(checkPromiseMatched("Still working on DONE...", "DONE"), false);
  assert.equal(
    checkPromiseMatched("<promise>ALL_GREEN</promise>", "ALL_GREEN"),
    true,
  );
  assert.equal(checkPromiseMatched(null, "DONE"), false);
  assert.equal(checkPromiseMatched("<promise></promise>", "   "), false);
});

test("createLoopState normalises fields and clamps maxIterations", () => {
  assert.throws(() => createLoopState({ conversationId: "   " }));

  const loop = createLoopState({
    conversationId: "conv-123",
    prompt: "  Fix all failing tests  ",
    completionPromise: "  SHIP_IT ",
    maxIterations: 500,
    now: 1700000000000,
  });
  assert.deepEqual(loop, {
    conversationId: "conv-123",
    prompt: "Fix all failing tests",
    completionPromise: "SHIP_IT",
    iteration: 0,
    maxIterations: 200,
    active: true,
    status: "running",
    startedAt: 1700000000000,
    updatedAt: 1700000000000,
    completedAt: null,
  });
});

test("updateLoopIteration increments active loops and leaves inactive ones unchanged", () => {
  const loop = createLoopState({
    conversationId: "conv-1",
    maxIterations: 5,
    now: 100,
  });
  const stepped = updateLoopIteration(loop, { now: 200 });
  assert.equal(stepped.iteration, 1);
  assert.equal(stepped.updatedAt, 200);

  const inactive = { ...loop, active: false, iteration: 3 };
  assert.equal(updateLoopIteration(inactive, { now: 300 }).iteration, 3);
});

test("evaluateStopEvent continues until promise is matched or maxIterations is reached", () => {
  let state = createLoopState({
    conversationId: "conv-42",
    prompt: "Implement feature X",
    completionPromise: "FEATURE_X_READY",
    maxIterations: 2,
    now: 1000,
  });

  // 1st stop: no promise yet -> continue (iteration 1/2)
  const step1 = evaluateStopEvent(state, {
    lastAssistantText: "Made progress on step 1.",
    now: 2000,
  });
  assert.equal(step1.action, "continue");
  assert.equal(step1.response.decision, "continue");
  assert.match(
    step1.response.reason,
    /Ralph Loop \(iteration 1\/2\): continue working on the task until completion criteria are met and emit <promise>FEATURE_X_READY<\/promise>\./,
  );
  state = step1.nextState;
  assert.equal(state.iteration, 1);
  assert.equal(state.active, true);

  // 2nd stop: still no promise -> continue (iteration 2/2)
  const step2 = evaluateStopEvent(state, {
    lastAssistantText: "Ran tests, fixing one edge case.",
    now: 3000,
  });
  assert.equal(step2.action, "continue");
  assert.match(step2.response.reason, /iteration 2\/2/);
  state = step2.nextState;
  assert.equal(state.iteration, 2);

  // 3rd stop: reached maxIterations (2/2) -> stops with max_iterations
  const step3 = evaluateStopEvent(state, {
    lastAssistantText: "Still working...",
    now: 4000,
  });
  assert.equal(step3.action, "max_iterations");
  assert.deepEqual(step3.response, {});
  assert.equal(step3.nextState.active, false);
  assert.equal(step3.nextState.status, "max_iterations");

  // Promise match on an active loop completes immediately
  const activeState = createLoopState({
    conversationId: "conv-99",
    completionPromise: "DONE",
    maxIterations: 5,
    now: 1000,
  });
  const doneStep = evaluateStopEvent(activeState, {
    lastAssistantText: "Everything verified. <promise>DONE</promise>",
    now: 1500,
  });
  assert.equal(doneStep.action, "completed");
  assert.deepEqual(doneStep.response, {});
  assert.equal(doneStep.nextState.active, false);
  assert.equal(doneStep.nextState.status, "completed");
});

test("summariseLoops sorts active loops first and tallies status counts", () => {
  const summary = summariseLoops([
    {
      conversationId: "c-done",
      active: false,
      status: "completed",
      iteration: 3,
      maxIterations: 10,
      updatedAt: 500,
    },
    {
      conversationId: "c-active",
      active: true,
      status: "running",
      iteration: 2,
      maxIterations: 5,
      updatedAt: 100,
    },
    {
      conversationId: "c-max",
      active: false,
      status: "max_iterations",
      iteration: 5,
      maxIterations: 5,
      updatedAt: 300,
    },
    {
      conversationId: "c-cancel",
      active: false,
      status: "cancelled",
      iteration: 1,
      maxIterations: 8,
      updatedAt: 200,
    },
  ]);

  assert.equal(summary.total, 4);
  assert.equal(summary.activeCount, 1);
  assert.equal(summary.completedCount, 1);
  assert.equal(summary.maxedCount, 1);
  assert.equal(summary.cancelledCount, 1);
  assert.equal(summary.totalIterations, 11);
  assert.deepEqual(
    summary.items.map((i) => i.conversationId),
    ["c-active", "c-done", "c-max", "c-cancel"],
  );
});
