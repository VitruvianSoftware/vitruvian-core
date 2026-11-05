// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  applyProgressCall,
  applyStepCall,
  EMPTY_PANEL_MESSAGE,
  formatSidebarData,
  formatSidebarLines,
  formatSidebarTitle,
  mapOpenCodeTokens,
  mapProgressInputToEvents,
  mergeTokenSnapshots,
  parseModelAndEffort,
  reduce,
  sparkline,
  statusColorToken,
} from "./adapter.mjs";

describe("mapProgressInputToEvents & applyProgressCall", () => {
  it("maps progress fields in the contract order (tasks -> phase -> accept -> return -> close)", () => {
    const events = mapProgressInputToEvents(
      {
        title: "Probe",
        phase: "review",
        tasks: [
          { title: "A", specialist: "wren", tier: "core", after: [] },
          { title: "B", specialist: "scout", tier: "rush", after: ["1"] },
        ],
        accept: ["1"],
        return: [{ id: "2", reason: "missing assertion" }],
        finished: true,
      },
      1000,
    );

    assert.deepEqual(
      events.map((e) => e.type),
      ["plan", "phase", "task.accept", "task.return", "close"],
    );

    const { flow, summary } = applyProgressCall(
      null,
      {
        title: "Probe",
        phase: "review",
        tasks: [
          { title: "A", specialist: "wren", tier: "core", after: [] },
          { title: "B", specialist: "scout", tier: "rush", after: ["1"] },
        ],
        accept: ["1"],
        return: [{ id: "2", reason: "missing assertion" }],
        finished: true,
      },
      1000,
    );

    assert.equal(flow.title, "Probe");
    assert.equal(flow.phase, "close");
    assert.equal(flow.closedAt, 1000);
    assert.equal(summary, "flow updated: 1/2 accepted (phase: close)");
  });

  it("initializes a flow even if progress is called with phase before tasks", () => {
    const { flow, summary } = applyProgressCall(
      null,
      { title: "Early phase", phase: "design" },
      500,
    );
    assert.equal(flow.title, "Early phase");
    assert.equal(flow.phase, "design");
    assert.equal(summary, "flow updated: 0/0 accepted (phase: design)");
  });
});

describe("applyStepCall", () => {
  it("updates steps on the matching worker run and never throws on unmatched runs", () => {
    let { flow } = applyProgressCall(
      null,
      {
        title: "Probe",
        phase: "delegate",
        tasks: [{ title: "A", specialist: "wren", tier: "core", after: [] }],
      },
      1000,
    );
    flow = reduce(flow, {
      type: "run.start",
      at: 1100,
      id: "ses_worker_1",
      role: "worker",
      agent: "wren",
      title: "A",
      model: "anthropic/claude-sonnet-5-6",
      effort: "high",
    });

    const matchedRes = applyStepCall(
      flow,
      "ses_worker_1",
      { done: 2, total: 5, note: "running tests" },
      1200,
    );
    assert.equal(matchedRes.matched, true);
    assert.equal(matchedRes.runId, "ses_worker_1");
    assert.equal(matchedRes.summary, "step updated: 2/5 (running tests)");
    assert.deepEqual(matchedRes.flow?.runs[0].steps, {
      done: 2,
      total: 5,
      note: "running tests",
    });

    // Finish the worker and verify an unknown caller session does not throw
    const doneFlow = reduce(matchedRes.flow, {
      type: "run.end",
      at: 1300,
      id: "ses_worker_1",
      status: "done",
    });
    const unmatchedRes = applyStepCall(
      doneFlow,
      "ses_unknown",
      { done: 1, total: 3 },
      1400,
    );
    assert.equal(unmatchedRes.matched, false);
    assert.match(unmatchedRes.summary, /not a tracked worker run/);
  });

  it("validates step bounds", () => {
    assert.throws(
      () => applyStepCall(null, "ses_1", { done: 4, total: 3 }, 1000),
      /0 <= done <= total/,
    );
    assert.throws(
      () => applyStepCall(null, "ses_1", { done: 0, total: 0 }, 1000),
      /total >= 1/,
    );
  });
});

describe("model, token, and sparkline helpers", () => {
  it("parses OpenCode model objects and enforces medium effort floor", () => {
    assert.deepEqual(
      parseModelAndEffort({
        providerID: "anthropic",
        id: "claude-haiku-5-5",
        variant: "low",
      }),
      { model: "anthropic/claude-haiku-5-5", effort: "medium" },
    );
    assert.deepEqual(parseModelAndEffort("claude-opus-5-7#xhigh"), {
      model: "claude-opus-5-7",
      effort: "xhigh",
    });
  });

  it("maps OpenCode token usage and merges step/session snapshots without double counting", () => {
    const mapped = mapOpenCodeTokens({
      input: 1200,
      output: 300,
      reasoning: 100,
      cache: { read: 5000, write: 400 },
    });
    assert.deepEqual(mapped, {
      input: 1200,
      output: 400,
      cacheRead: 5000,
      cacheWrite: 400,
    });

    const stepMap = new Map([
      ["msg_1", { input: 500, output: 100, cacheRead: 1000, cacheWrite: 200 }],
      ["msg_2", { input: 700, output: 300, cacheRead: 4000, cacheWrite: 200 }],
    ]);
    const merged = mergeTokenSnapshots(stepMap, mapped);
    assert.deepEqual(merged, mapped);
  });

  it("renders compact sparkline with replan markers", () => {
    const s = sparkline([
      { at: 100, remaining: 3 },
      { at: 200, remaining: 2 },
      { at: 300, remaining: 4, replanned: true },
      { at: 400, remaining: 0 },
    ]);
    assert.equal(s.includes("⟳"), true);
    assert.equal(s.endsWith("▁"), true);
  });
});

describe("sidebar formatting", () => {
  it("renders the contract empty message when flow is null", () => {
    assert.equal(formatSidebarTitle(null), "Orchestrator");
    assert.deepEqual(formatSidebarLines(null), [EMPTY_PANEL_MESSAGE]);
  });

  it("formats all 5 contract sections (header, burn-down, tasks, agents, spend)", () => {
    let { flow } = applyProgressCall(
      null,
      {
        title: "Auth rollout",
        phase: "delegate",
        tasks: [
          {
            title: "Add middleware",
            specialist: "wren",
            tier: "core",
            after: [],
          },
          {
            title: "Audit RBAC",
            specialist: "aegis",
            tier: "core",
            after: ["1"],
          },
        ],
      },
      1000,
    );

    // Lead run
    flow = reduce(flow, {
      type: "run.start",
      at: 1000,
      id: "lead:ses_root",
      role: "lead",
      agent: "lead",
      model: "anthropic/claude-opus-5-7",
      effort: "xhigh",
    });
    flow = reduce(flow, {
      type: "run.progress",
      at: 1500,
      id: "lead:ses_root",
      tokens: { input: 10_000, output: 2_000, cacheRead: 0, cacheWrite: 0 },
    });

    // Worker run matching task 1
    flow = reduce(flow, {
      type: "run.start",
      at: 1200,
      id: "ses_worker_1",
      role: "worker",
      agent: "wren",
      title: "Add middleware",
      model: "anthropic/claude-sonnet-5-6",
      effort: "high",
    });
    flow = reduce(flow, {
      type: "run.progress",
      at: 1600,
      id: "ses_worker_1",
      steps: { done: 3, total: 4, note: "bazel test" },
      tokens: { input: 20_000, output: 4_000, cacheRead: 0, cacheWrite: 0 },
    });

    // Unpriced worker run
    flow = reduce(flow, {
      type: "run.start",
      at: 1300,
      id: "ses_worker_unpriced",
      role: "worker",
      agent: "scout",
      title: "Unmatched check",
      model: "custom/local-model",
      effort: "medium",
    });
    flow = reduce(flow, {
      type: "run.progress",
      at: 1700,
      id: "ses_worker_unpriced",
      tokens: { input: 1_500, output: 500, cacheRead: 0, cacheWrite: 0 },
    });

    const data = formatSidebarData(flow, 11_200);
    assert.equal(data.empty, false);
    assert.equal(data.header.acceptedText, "accepted 0 of 2");
    assert.equal(data.tasks[0].state, "running");
    assert.equal(data.tasks[0].color, "info");
    assert.equal(data.tasks[1].state, "waiting");
    assert.equal(data.tasks[1].waitsOnText, "waits on #1");
    assert.equal(data.tasks[1].color, "warning");
    assert.equal(statusColorToken("accepted"), "success");
    assert.equal(statusColorToken("returned"), "error");
    assert.equal(statusColorToken("ready"), "muted");

    const lines = formatSidebarLines(flow, 11_200);
    const joined = lines.join("\n");
    assert.match(joined, /Auth rollout — accepted 0 of 2 · est\. \$0\.18/);
    assert.match(
      joined,
      /Phases: ✓plan · ✓design · \[DELEGATE\] · review · close/,
    );
    assert.match(joined, /#1 Add middleware \[wren\/core\] — running/);
    assert.match(
      joined,
      /#2 Audit RBAC \[aegis\/core\] — waiting \(waits on #1\)/,
    );
    assert.match(
      joined,
      /wren #1 \(claude-sonnet-5-6 · high\) · 3\/4 bazel test · 24k tok · est\. \$0\.08/,
    );
    assert.match(
      joined,
      /Spend: lead \$0\.10 · workers \$0\.08 · total \$0\.18/,
    );
    assert.match(joined, /Unpriced: local-model: 2\.0k tok/);
  });
});
