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
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  buildPanelState,
  extractTranscriptRunEvents,
  foldFlowEvents,
  formatElapsed,
  loadLivePanelState,
  parseFlowJsonl,
} from "./main.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

test("formatElapsed formats each duration band (<1m, <1h, <1d, >=1d)", () => {
  // Under 1m -> "45s"
  assert.equal(formatElapsed(0), "0s");
  assert.equal(formatElapsed(45_000), "45s");
  assert.equal(formatElapsed(59_999), "59s");

  // Under 1h -> "12m 05s"
  assert.equal(formatElapsed(60_000), "1m 00s");
  assert.equal(formatElapsed((12 * 60 + 5) * 1000), "12m 05s");
  assert.equal(formatElapsed((59 * 60 + 59) * 1000), "59m 59s");

  // Under 1d -> "3h 07m"
  assert.equal(formatElapsed(3600 * 1000), "1h 00m");
  assert.equal(formatElapsed((3 * 3600 + 7 * 60 + 42) * 1000), "3h 07m");
  assert.equal(formatElapsed((23 * 3600 + 59 * 60) * 1000), "23h 59m");

  // 1d or more -> "2d 4h"
  assert.equal(formatElapsed(86400 * 1000), "1d 0h");
  assert.equal(formatElapsed((2 * 86400 + 4 * 3600 + 15 * 60) * 1000), "2d 4h");
});

test("extractTranscriptRunEvents parses invoke_subagent, GENERIC conversationId, SYSTEM_MESSAGE completion, and send_message return rounds", () => {
  const transcriptJsonl = [
    JSON.stringify({
      step_index: 1,
      source: "MODEL",
      type: "PLANNER_RESPONSE",
      status: "DONE",
      created_at: "2026-11-05T17:00:10Z",
      input_tokens: 12000,
      output_tokens: 800,
      cache_read_tokens: 50000,
      tool_calls: [
        {
          name: "invoke_subagent",
          args: {
            TypeName: '"wren"',
            Role: '"Implement MCP server"',
            Model: '"pro"',
          },
        },
      ],
    }),
    JSON.stringify({
      step_index: 2,
      source: "MODEL",
      type: "GENERIC",
      status: "DONE",
      created_at: "2026-11-05T17:00:12Z",
      content:
        'Created the following subagent:\n{\n  "conversationId": "sub-uuid-1"\n}',
    }),
    JSON.stringify({
      step_index: 3,
      source: "SYSTEM",
      type: "SYSTEM_MESSAGE",
      status: "DONE",
      created_at: "2026-11-05T17:01:00Z",
      content:
        "<SYSTEM_MESSAGE>\n[Message] timestamp=2026-11-05T17:01:00Z sender=sub-uuid-1 priority=MESSAGE_PRIORITY_HIGH content=Done\n</SYSTEM_MESSAGE>",
    }),
    JSON.stringify({
      step_index: 4,
      source: "MODEL",
      type: "PLANNER_RESPONSE",
      status: "DONE",
      created_at: "2026-11-05T17:01:20Z",
      tool_calls: [
        {
          name: "send_message",
          args: {
            Recipient: "sub-uuid-1",
            Message: "Fix edge case in framing",
          },
        },
      ],
    }),
  ].join("\n");

  const runEvents = extractTranscriptRunEvents(transcriptJsonl);
  const types = runEvents.map((e) => `${e.type}:${e.id}`);
  assert.deepEqual(types, [
    "run.start:lead",
    "run.progress:lead",
    "run.start:sub-uuid-1",
    "run.end:sub-uuid-1",
    "run.start:sub-uuid-1#2",
  ]);
  const workerStart = runEvents.find((e) => e.id === "sub-uuid-1");
  assert.equal(workerStart.agent, "wren");
  assert.equal(workerStart.title, "Implement MCP server");
  assert.equal(workerStart.model, "pro");
});

test("foldFlowEvents combines flow JSONL events with transcript runs and matches step progress", () => {
  const flowEvents = [
    {
      type: "plan",
      at: 1000,
      title: "Panel Feature",
      tasks: [
        {
          title: "Implement MCP server",
          specialist: "wren",
          tier: "core",
          after: [],
        },
        {
          title: "Run verification",
          specialist: "scout",
          tier: "fast",
          after: [1],
        },
      ],
    },
    {
      type: "phase",
      at: 1005,
      phase: "delegate",
    },
    {
      type: "run.progress",
      at: 1050,
      id: "sub-uuid-1",
      steps: { done: 2, total: 3, note: "testing" },
    },
  ];

  const transcriptEvents = [
    {
      type: "run.start",
      at: 1010,
      id: "sub-uuid-1",
      harness: "antigravity",
      agent: "wren",
      model: "claude-sonnet-4-5",
      effort: null,
      title: "Implement MCP server",
      role: "worker",
    },
  ];

  const flow = foldFlowEvents(flowEvents, transcriptEvents);
  assert.ok(flow);
  assert.equal(flow.title, "Panel Feature");
  assert.equal(flow.phase, "delegate");
  assert.equal(flow.tasks[0].state, "running");
  assert.equal(flow.tasks[1].state, "waiting");
  assert.equal(flow.runs.length, 1);
  assert.equal(flow.runs[0].taskN, 1);
  assert.deepEqual(flow.runs[0].steps, {
    done: 2,
    total: 3,
    note: "testing",
  });
});

test("loadLivePanelState and buildPanelState produce contract /api/state shape from sample-flow.jsonl", () => {
  const emptyState = buildPanelState(null, {
    conversationId: "",
    version: "0.2.0",
    now: 2000,
  });
  assert.equal(emptyState.hasFlow, false);
  assert.equal(emptyState.flow, null);
  assert.deepEqual(emptyState.taskBoard, []);
  assert.equal(emptyState.remaining, 0);

  const testdataDir = join(HERE, "testdata");
  const liveState = loadLivePanelState({
    flowsDir: testdataDir,
    now: 1762364200000,
  });
  assert.equal(liveState.hasFlow, true);
  assert.equal(liveState.conversationId, "sample-flow");
  assert.equal(liveState.title, "Orchestrator Live Panels");
  assert.equal(liveState.phase, "delegate");
  assert.equal(liveState.accepted, 1);
  assert.equal(liveState.totalTasks, 4);
  assert.equal(liveState.remaining, 3);
  assert.equal(liveState.burnDown.replans.length, 1);
  assert.equal(liveState.burnDown.ideal.length, 2);
  assert.equal(liveState.taskBoard.length, 4);
  assert.equal(liveState.taskBoard[0].state, "accepted");
  assert.equal(liveState.taskBoard[1].state, "running");
  assert.equal(liveState.taskBoard[2].state, "ready");
  assert.deepEqual(liveState.taskBoard[3].waitingOn, [2, 3]);
  assert.equal(liveState.runs.length, 3);
  assert.ok(liveState.spend.total > 0);
  assert.equal(liveState.spend.unpriced.runs, 1);
  assert.ok(liveState.spend.unpriced.tokens > 0);

  // Also verify selecting the newest flow file in a temp directory
  const tmpDir = mkdtempSync(join(tmpdir(), "orch-panel-test-"));
  try {
    writeFileSync(
      join(tmpDir, "conv-1.jsonl"),
      JSON.stringify({
        type: "plan",
        at: 5000,
        title: "Temp Flow",
        tasks: [
          { title: "Only task", specialist: "wren", tier: "core", after: [] },
        ],
      }) + "\n",
      "utf8",
    );
    const parsedEvents = parseFlowJsonl(
      '{"type":"plan","at":5000,"title":"Temp Flow","tasks":[]}\ninvalid',
    );
    assert.equal(parsedEvents.length, 1);
    const tmpState = loadLivePanelState({ flowsDir: tmpDir, now: 6000 });
    assert.equal(tmpState.hasFlow, true);
    assert.equal(tmpState.title, "Temp Flow");
    assert.equal(tmpState.totalTasks, 1);
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
});
