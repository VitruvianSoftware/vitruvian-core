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
  createLoopState,
  summariseLoops,
  updateLoopIteration,
} from "./core.mjs";

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
