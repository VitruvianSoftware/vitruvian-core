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
  PHASES,
  TIERS,
  blankFlow,
  estimateRunCost,
  extractSubagentsFromTranscript,
  inferTier,
  mergeFlowProgress,
  summariseFleetState,
} from "./core.mjs";

test("PHASES and TIERS expose the canonical savvy-flow taxonomy", () => {
  assert.deepEqual(PHASES, ["plan", "design", "delegate", "review", "close"]);
  for (const tier of [
    "fable",
    "heavy",
    "careful",
    "medium",
    "light",
    "other",
  ]) {
    assert.ok(tier in TIERS, `missing tier ${tier}`);
    assert.match(TIERS[tier].color, /^#[0-9A-Fa-f]{6}$/);
  }
});

test("inferTier resolves bracket tags, savvy prefixes, and Vitruvian specialists", () => {
  assert.equal(inferTier("wren", "[careful] Audit RBAC policies"), "careful");
  assert.equal(inferTier("savvy-heavy", "Refactor module"), "heavy");
  assert.equal(inferTier("beacon", "Coordinate wave 1"), "heavy");
  assert.equal(inferTier("aegis", "Review IAM bindings"), "careful");
  assert.equal(inferTier("scout", "Watch PR checks"), "light");
  assert.equal(inferTier("compass", "Clarify scope"), "fable");
  assert.equal(inferTier("custom-agent", "Do something"), "other");
});

test("mergeFlowProgress initializes, updates, and resets on a new title or finish", () => {
  const initial = mergeFlowProgress(null, {
    title: "Extensions Suite",
    phase: "delegate",
    tasks: [
      { title: "Build savvy-fleet", tier: "savvy-heavy", after: [] },
      { title: "Build ext-marketplace", tier: "medium", after: [1, -2, "x"] },
      { title: "   " },
    ],
  });
  assert.equal(initial.title, "Extensions Suite");
  assert.equal(initial.phase, "delegate");
  assert.equal(initial.total, 2);
  assert.equal(initial.done, 0);
  assert.deepEqual(initial.tasks, [
    { title: "Build savvy-fleet", tier: "heavy", after: [] },
    { title: "Build ext-marketplace", tier: "medium", after: [1] },
  ]);

  const progressed = mergeFlowProgress(initial, { done: 1, phase: "review" });
  assert.equal(progressed.done, 1);
  assert.equal(progressed.phase, "review");
  assert.equal(progressed.tasks.length, 2);

  const finished = mergeFlowProgress(progressed, { done: 5, finished: true });
  assert.equal(finished.done, 2);
  assert.equal(finished.phase, "close");
  assert.equal(finished.isFinished, true);

  const restarted = mergeFlowProgress(finished, { title: "Next Initiative" });
  assert.equal(restarted.title, "Next Initiative");
  assert.equal(restarted.done, 0);
  assert.equal(restarted.total, 0);
  assert.equal(restarted.phase, "plan");
  assert.equal(restarted.isFinished, false);
  assert.deepEqual(restarted.tasks, []);
});

test("estimateRunCost calculates token and USD estimates across model families", () => {
  const opus = estimateRunCost("claude-opus-5-5", {
    input_tokens: 500_000,
    output_tokens: 50_000,
  });
  assert.equal(opus.tokens, 550_000);
  assert.equal(opus.costUsd, 3.0);
  assert.equal(opus.formattedCost, "$3.00");
  assert.equal(opus.formattedTokens, "550k");
  assert.equal(opus.contextMax, 1_000_000);

  const haiku = estimateRunCost("haiku-4", {
    input_tokens: 100_000,
    output_tokens: 20_000,
  });
  assert.equal(haiku.contextMax, 200_000);
  assert.equal(haiku.costUsd, 0.2);

  const stepEst = estimateRunCost("flash", { steps: 10, toolCalls: 5 });
  assert.ok(stepEst.tokens > 0);
  assert.ok(stepEst.costUsd > 0);
});

test("extractSubagentsFromTranscript parses invoke_subagent, send_message, and inbox notes", () => {
  const sampleJsonl = [
    JSON.stringify({
      step_index: 1,
      status: "DONE",
      tool_calls: [
        {
          id: "sub-1",
          name: "invoke_subagent",
          args: {
            TypeName: "wren",
            Role: "[medium] Build savvy-fleet",
            Model: "inherit",
          },
        },
        {
          id: "cmd-1",
          name: "run_command",
          args: { CommandLine: "node --test" },
        },
      ],
    }),
    "not-valid-json",
    JSON.stringify({
      step_index: 2,
      status: "DONE",
      tool_calls: [
        {
          id: "msg-1",
          name: "send_message",
          args: { Recipient: "sub-1", Message: "Please add extra test" },
        },
      ],
    }),
  ].join("\n");

  const inboxNotes = [
    JSON.stringify({
      id: "sub-2",
      tool_name: "invoke_subagent",
      tool_input: {
        TypeName: "scout",
        Role: "Watch CI checks",
        Model: "flash",
      },
    }),
  ];

  const extracted = extractSubagentsFromTranscript(sampleJsonl, inboxNotes);
  assert.equal(extracted.totalSteps, 2);
  assert.equal(extracted.toolCalls, 3);
  assert.deepEqual(extracted.toolsBreakdown, {
    invoke_subagent: 1,
    run_command: 1,
    send_message: 1,
  });
  assert.equal(extracted.subagents.length, 2);
  assert.equal(extracted.subagents[0].type, "wren");
  assert.equal(extracted.subagents[0].tier, "medium");
  assert.equal(extracted.subagents[0].round, 2);
  assert.equal(extracted.subagents[0].messagesSent, 1);
  assert.equal(extracted.subagents[1].type, "scout");
  assert.equal(extracted.subagents[1].tier, "light");
  assert.equal(extracted.subagents[1].status, "running");
});

test("summariseFleetState combines flow plan with transcript subagents and computes unstarted tasks", () => {
  const state = summariseFleetState({
    version: "0.1.0",
    conversationId: "conv-12345678",
    flow: {
      title: "Fleet Rollout",
      phase: "delegate",
      done: 1,
      tasks: [
        { title: "[medium] Build savvy-fleet", tier: "medium" },
        {
          title: "Verify security posture",
          tier: "careful",
          specialist: "aegis",
        },
      ],
    },
    transcript: JSON.stringify({
      step_index: 1,
      status: "DONE",
      tool_calls: [
        {
          id: "sub-1",
          name: "invoke_subagent",
          args: {
            TypeName: "wren",
            Role: "[medium] Build savvy-fleet",
          },
        },
      ],
    }),
  });

  assert.equal(state.connected, true);
  assert.equal(state.flow.progressPct, 50);
  assert.equal(state.counts.finished, 1);
  assert.equal(state.counts.planned, 1);
  assert.equal(state.planned[0].title, "Verify security posture");
  assert.equal(state.planned[0].specialist, "aegis");
  assert.deepEqual(blankFlow().tasks, []);
});
