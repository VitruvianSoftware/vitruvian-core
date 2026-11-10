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
import {
  mkdirSync,
  mkdtempSync,
  rmSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  buildPanelState,
  checkAndWakeStalledRuns,
  extractTranscriptRunEvents,
  foldFlowEvents,
  formatElapsed,
  loadLivePanelState,
  parseFlowJsonl,
  readChildTranscriptActivityAt,
  readChildTranscriptState,
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

test("buildPanelState exposes stallState, idleMs, and stalls, and child transcript activity advances lastActivityAt", () => {
  const tmpDir = mkdtempSync(join(tmpdir(), "orch-stall-test-"));
  try {
    const flowsDir = join(tmpDir, "flows");
    const brainRoot = join(tmpDir, "app-data");
    mkdirSync(flowsDir, { recursive: true });

    const startAt = Date.parse("2026-11-05T17:00:00Z");
    const childStepAt = startAt + 14 * 60 * 1000; // 14m after start
    const nowAt = startAt + 16 * 60 * 1000; // 16m after start (would be stalled without child transcript, active with child transcript)

    writeFileSync(
      join(flowsDir, "root-conv.jsonl"),
      [
        JSON.stringify({
          type: "plan",
          at: startAt,
          title: "Watchdog Flow",
          tasks: [
            {
              title: "Implement feature",
              specialist: "wren",
              tier: "core",
              after: [],
            },
          ],
        }),
        JSON.stringify({
          type: "phase",
          at: startAt + 1000,
          phase: "delegate",
        }),
        JSON.stringify({
          type: "run.start",
          at: startAt + 2000,
          id: "child-conv-1#2",
          harness: "antigravity",
          agent: "wren",
          model: "claude-sonnet-4-5",
          title: "Implement feature",
          role: "worker",
        }),
      ].join("\n") + "\n",
      "utf8",
    );

    // Without child transcript activity, 16m idle is stalled (>= 15m default).
    const stalledState = loadLivePanelState({
      flowsDir,
      brainRoots: [brainRoot],
      now: nowAt,
    });
    assert.equal(stalledState.stalls.length, 1);
    assert.equal(stalledState.stalls[0].state, "stalled");
    assert.equal(stalledState.runs[0].stallState, "stalled");
    assert.equal(stalledState.runs[0].idleMs, nowAt - (startAt + 2000));

    // Write child transcript for base conversation ID "child-conv-1" (stripping "#2").
    const childLogDir = join(
      brainRoot,
      "brain",
      "child-conv-1",
      ".system_generated",
      "logs",
    );
    mkdirSync(childLogDir, { recursive: true });
    const childTranscriptPath = join(childLogDir, "transcript.jsonl");
    writeFileSync(
      childTranscriptPath,
      JSON.stringify({
        step_index: 5,
        type: "PLANNER_RESPONSE",
        created_at: new Date(childStepAt).toISOString(),
      }) + "\n",
      "utf8",
    );
    const mtimeDate = new Date(childStepAt);
    utimesSync(childTranscriptPath, mtimeDate, mtimeDate);

    assert.equal(
      readChildTranscriptActivityAt("child-conv-1#2", [brainRoot]),
      childStepAt,
    );

    // Now loadLivePanelState sees the child activity 2m ago and keeps the worker active.
    const activeState = loadLivePanelState({
      flowsDir,
      brainRoots: [brainRoot],
      now: nowAt,
    });
    assert.equal(activeState.runs[0].lastActivityAt, childStepAt);
    assert.equal(activeState.runs[0].stallState, "active");
    assert.equal(activeState.runs[0].idleMs, 2 * 60 * 1000);
    assert.equal(activeState.stalls[0].state, "active");
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("checkAndWakeStalledRuns calls sendMessage once per stall and re-alerts only when lastActivityAt advances and stalls again", async () => {
  const tmpDir = mkdtempSync(join(tmpdir(), "orch-watchdog-test-"));
  try {
    const flowsDir = join(tmpDir, "flows");
    const brainRoot = join(tmpDir, "app-data");
    mkdirSync(flowsDir, { recursive: true });

    const t0 = 1_000_000;
    const flowPath = join(flowsDir, "lead-conv-42.jsonl");
    writeFileSync(
      flowPath,
      [
        JSON.stringify({
          type: "plan",
          at: t0,
          title: "Stall Wakeup Test",
          tasks: [
            {
              title: "Build watchdog",
              specialist: "wren",
              tier: "core",
              after: [],
            },
          ],
        }),
        JSON.stringify({
          type: "run.start",
          at: t0 + 1000,
          id: "worker-uuid-1",
          harness: "antigravity",
          agent: "wren",
          model: "claude-sonnet-4-5",
          title: "Build watchdog",
          role: "worker",
        }),
      ].join("\n") + "\n",
      "utf8",
    );

    const sent = [];
    const notifiedStalls = new Set();
    const sendMessage = async (cid, msg, opts) => {
      sent.push({ cid, msg, opts });
    };

    // 1. Before stall threshold (10m idle < 15m): no wake-up sent.
    await checkAndWakeStalledRuns({
      flowsDir,
      brainRoots: [brainRoot],
      sendMessage,
      notifiedStalls,
      now: t0 + 1000 + 10 * 60 * 1000,
    });
    assert.equal(sent.length, 0);

    // 2. At 16m idle: stalled -> sends exactly 1 wake-up message.
    await checkAndWakeStalledRuns({
      flowsDir,
      brainRoots: [brainRoot],
      sendMessage,
      notifiedStalls,
      now: t0 + 1000 + 16 * 60 * 1000,
    });
    assert.equal(sent.length, 1);
    assert.equal(sent[0].cid, "lead-conv-42");
    assert.equal(sent[0].opts.title, "Orchestrator Watchdog");
    assert.match(
      sent[0].msg,
      /\[Orchestrator Watchdog\] Subagent wren \(worker-uuid-1\) has had no transcript or step activity for 16m 00s on task #1 \("Build watchdog"\)\./,
    );

    // 3. Subsequent tick at 20m idle with no new activity: deduplicated, does not spam.
    await checkAndWakeStalledRuns({
      flowsDir,
      brainRoots: [brainRoot],
      sendMessage,
      notifiedStalls,
      now: t0 + 1000 + 20 * 60 * 1000,
    });
    assert.equal(sent.length, 1);

    // 4. Worker makes progress at +21m, then stalls again 15m later (+36m): alerts again.
    const nextActivityAt = t0 + 1000 + 21 * 60 * 1000;
    await checkAndWakeStalledRuns({
      flowsDir,
      brainRoots: [brainRoot],
      childActivityByRunId: { "worker-uuid-1": nextActivityAt },
      sendMessage,
      notifiedStalls,
      now: nextActivityAt + 15 * 60 * 1000,
    });
    assert.equal(sent.length, 2);
    assert.match(sent[1].msg, /15m 00s on task #1 \("Build watchdog"\)/);
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
});

// One flow with a single worker run, written at `t0`, for the watchdog tests.
function writeWatchdogFlow(flowsDir, cid, t0, runId = "worker-1") {
  const flowPath = join(flowsDir, `${cid}.jsonl`);
  writeFileSync(
    flowPath,
    [
      {
        type: "plan",
        at: t0,
        title: "Watchdog limits",
        tasks: [
          { title: "Long build", specialist: "forge", tier: "core", after: [] },
        ],
      },
      {
        type: "run.start",
        at: t0,
        id: runId,
        harness: "antigravity",
        agent: "forge",
        model: "gemini-4-argon-high",
        title: "Long build",
        role: "worker",
      },
    ]
      .map((e) => JSON.stringify(e))
      .join("\n") + "\n",
    "utf8",
  );
  return flowPath;
}

test("the watchdog leaves old flows and long-abandoned runs alone", async () => {
  const tmpDir = mkdtempSync(join(tmpdir(), "orch-watchdog-age-"));
  try {
    const flowsDir = join(tmpDir, "flows");
    mkdirSync(flowsDir, { recursive: true });
    const min = 60 * 1000;
    const now = Date.UTC(2026, 10, 9, 12, 0, 0);
    const sent = [];
    const sendMessage = async (cid, msg) => sent.push({ cid, msg });
    const brainRoots = [join(tmpDir, "no-brain")];

    // Written two days ago and never closed: an old conversation.
    const old = writeWatchdogFlow(flowsDir, "old-conv", now - 48 * 60 * min);
    utimesSync(old, (now - 48 * 60 * min) / 1000, (now - 48 * 60 * min) / 1000);
    // Written today, but its run has been silent for three hours: abandoned.
    const quiet = writeWatchdogFlow(
      flowsDir,
      "abandoned-conv",
      now - 180 * min,
    );
    utimesSync(quiet, (now - 60 * min) / 1000, (now - 60 * min) / 1000);
    // Written today and silent for 20 minutes: really stalled.
    const live = writeWatchdogFlow(flowsDir, "live-conv", now - 20 * min);
    utimesSync(live, (now - 20 * min) / 1000, (now - 20 * min) / 1000);

    await checkAndWakeStalledRuns({
      flowsDir,
      brainRoots,
      sendMessage,
      notifiedStalls: new Set(),
      now,
    });
    assert.deepEqual(
      sent.map((m) => m.cid),
      ["live-conv"],
    );
    // It asks the lead to check before restarting anything.
    assert.match(sent[0].msg, /a long build or test can run this long/);
    assert.doesNotMatch(sent[0].msg, /nudge or restart it\./);
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("a subagent waiting on its own background command is not woken until the longer limit", async () => {
  const tmpDir = mkdtempSync(join(tmpdir(), "orch-watchdog-waiting-"));
  try {
    const flowsDir = join(tmpDir, "flows");
    const brainRoot = join(tmpDir, "app-data");
    mkdirSync(flowsDir, { recursive: true });
    const min = 60 * 1000;
    const t0 = Date.UTC(2026, 10, 9, 12, 0, 0);
    writeWatchdogFlow(flowsDir, "lead-conv", t0, "child-conv");

    // The child started a background build and has heard nothing back yet.
    const logs = join(
      brainRoot,
      "brain",
      "child-conv",
      ".system_generated",
      "logs",
    );
    mkdirSync(logs, { recursive: true });
    const transcript = join(logs, "transcript.jsonl");
    const iso = (t) => new Date(t).toISOString();
    const started = {
      step_index: 1,
      type: "GENERIC",
      status: "RUNNING",
      created_at: iso(t0),
      content:
        "Tool is running as a background task with task id: child-conv/task-7",
    };
    writeFileSync(transcript, JSON.stringify(started) + "\n", "utf8");
    utimesSync(transcript, t0 / 1000, t0 / 1000);
    assert.deepEqual(readChildTranscriptState("child-conv", [brainRoot]), {
      activityAt: t0,
      waiting: true,
    });

    const sent = [];
    const tick = (now) =>
      checkAndWakeStalledRuns({
        flowsDir,
        brainRoots: [brainRoot],
        sendMessage: async (cid, msg) => sent.push({ cid, msg }),
        notifiedStalls: new Set(),
        now,
      });

    const state = loadLivePanelState({
      flowsDir,
      cid: "lead-conv",
      brainRoots: [brainRoot],
      now: t0 + 20 * min,
    });
    assert.equal(state.runs[0].stallState, "waiting");
    await tick(t0 + 20 * min);
    assert.equal(sent.length, 0);

    // Past the waiting limit it is stalled after all.
    await tick(t0 + 61 * min);
    assert.equal(sent.length, 1);

    // Once the build reports back, the child is no longer waiting.
    const finished = {
      step_index: 2,
      type: "SYSTEM_MESSAGE",
      status: "DONE",
      created_at: iso(t0 + 5 * min),
      content:
        "[Message] timestamp=x sender=child-conv/task-7 priority=HIGH content=done",
    };
    writeFileSync(
      transcript,
      [started, finished].map((r) => JSON.stringify(r)).join("\n") + "\n",
      "utf8",
    );
    utimesSync(transcript, (t0 + 5 * min) / 1000, (t0 + 5 * min) / 1000);
    assert.equal(
      readChildTranscriptState("child-conv", [brainRoot]).waiting,
      false,
    );
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
});
