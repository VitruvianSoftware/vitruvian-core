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
  readdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  board,
  members,
  reduce,
} from "../sidecars/panel/lib/orchestrator-core.mjs";
import {
  extractConversationMeta,
  formatJsonRpcFrame,
  handleJsonRpcMessage,
  mapPostToEvent,
  mapProgressToEvents,
  mapStepToEvent,
  parseJsonRpcFrames,
  queryBoard,
  readFlowFromJsonlFile,
  sanitizeConversationId,
} from "./server.mjs";

test("mapProgressToEvents emits events in contract order: plan -> phase -> task.accept -> task.return -> close", () => {
  const events = mapProgressToEvents(
    {
      title: "Multi-domain Rollout",
      phase: "review",
      tasks: [
        { title: "Build server", specialist: "wren", tier: "core", after: [] },
        { title: "Audit RBAC", specialist: "aegis", tier: "lead", after: [1] },
      ],
      accept: 1,
      return: 2,
      finished: true,
    },
    1700000000000,
    "root-conv-123",
  );

  assert.deepEqual(
    events.map((e) => e.type),
    ["plan", "phase", "task.accept", "task.return", "close"],
  );
  assert.equal(events[0].title, "Multi-domain Rollout");
  assert.equal(events[0].rootConversationId, "root-conv-123");
  assert.equal(events[0].tasks.length, 2);
  assert.equal(events[1].phase, "review");
  assert.equal(events[2].n, 1);
  assert.equal(events[3].n, 2);
  assert.equal(events[4].type, "close");
});

test("mapStepToEvent resolves caller run id from _meta and handles unmatched callers without throwing", () => {
  const meta = {
    "antigravity.google/root_conversation_id": "lead-uuid-1",
    "antigravity.google/conversation_id": "worker-uuid-9",
    "antigravity.google/parent_conversation_id": "lead-uuid-1",
    "antigravity.google/agent_name": "wren",
  };
  const extracted = extractConversationMeta(meta);
  assert.equal(extracted.rootConversationId, "lead-uuid-1");
  assert.equal(extracted.callerConversationId, "worker-uuid-9");
  assert.equal(extracted.parentConversationId, "lead-uuid-1");
  assert.equal(extracted.agentName, "wren");

  const mapped = mapStepToEvent(
    { done: 2, total: 5, note: "writing unit tests" },
    meta,
    1700000005000,
  );
  assert.equal(mapped.matched, true);
  assert.equal(mapped.rootConversationId, "lead-uuid-1");
  assert.deepEqual(mapped.event.steps, {
    done: 2,
    total: 5,
    note: "writing unit tests",
  });
  assert.equal(mapped.event.id, "worker-uuid-9");

  // Unmatched caller when _meta has no conversation id and flow has active runs
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Test",
    tasks: [{ title: "T1", specialist: "wren", tier: "core", after: [] }],
  });
  flow = reduce(flow, {
    type: "run.start",
    at: 1010,
    id: "known-run",
    harness: "antigravity",
    agent: "wren",
    model: "pro",
    effort: null,
    title: "T1",
    role: "worker",
  });

  const unmatched = mapStepToEvent(
    { done: 1, total: 2 },
    { "antigravity.google/root_conversation_id": "lead-uuid-1" },
    1020,
    flow,
  );
  assert.equal(unmatched.matched, false);
  assert.equal(unmatched.event, null);
  assert.match(unmatched.message, /could not be matched/i);
});

test("parseJsonRpcFrames and formatJsonRpcFrame support NDJSON and Content-Length framing", () => {
  const msg1 = { jsonrpc: "2.0", id: 1, method: "initialize", params: {} };
  const msg2 = { jsonrpc: "2.0", id: 2, method: "tools/list" };

  const ndjsonStream =
    formatJsonRpcFrame(msg1, "ndjson") +
    formatJsonRpcFrame(msg2, "ndjson") +
    '{"partial":';
  const parsedNd = parseJsonRpcFrames(ndjsonStream);
  assert.equal(parsedNd.mode, "ndjson");
  assert.deepEqual(parsedNd.messages, [msg1, msg2]);
  assert.equal(parsedNd.rest, '{"partial":');

  const clStream =
    formatJsonRpcFrame(msg1, "content-length") +
    formatJsonRpcFrame(msg2, "content-length");
  const parsedCl = parseJsonRpcFrames(clStream);
  assert.equal(parsedCl.mode, "content-length");
  assert.deepEqual(parsedCl.messages, [msg1, msg2]);
  assert.equal(parsedCl.rest, "");
});

test("handleJsonRpcMessage serves initialize, tools/list, and tools/call for progress and step", () => {
  const tempDir = mkdtempSync(join(tmpdir(), "orch-mcp-test-"));
  try {
    const initRes = handleJsonRpcMessage({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { protocolVersion: "2024-11-05" },
    });
    assert.equal(initRes.result.serverInfo.name, "vitruvian-orchestrator");

    const notifRes = handleJsonRpcMessage({
      jsonrpc: "2.0",
      method: "notifications/initialized",
    });
    assert.equal(notifRes, null);

    const listRes = handleJsonRpcMessage({
      jsonrpc: "2.0",
      id: 2,
      method: "tools/list",
    });
    assert.deepEqual(
      listRes.result.tools.map((t) => t.name),
      ["progress", "step", "post", "board"],
    );

    const callProgress = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: {
          name: "progress",
          arguments: {
            title: "Probe",
            phase: "delegate",
            tasks: [
              { title: "A", specialist: "wren", tier: "core", after: [] },
              { title: "B", specialist: "scout", tier: "fast", after: [1] },
            ],
            accept: 1,
          },
          _meta: {
            "antigravity.google/root_conversation_id": "conv-abc",
            "antigravity.google/conversation_id": "conv-abc",
          },
        },
      },
      { flowsDir: tempDir, now: () => 1762364000000 },
    );

    assert.equal(
      callProgress.result.content[0].text,
      "flow updated: 1/2 accepted",
    );

    const callStep = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 4,
        method: "tools/call",
        params: {
          name: "step",
          arguments: { done: 1, total: 3, note: "compiling" },
          _meta: {
            "antigravity.google/root_conversation_id": "conv-abc",
            "antigravity.google/conversation_id": "worker-xyz",
            "antigravity.google/parent_conversation_id": "conv-abc",
          },
        },
      },
      { flowsDir: tempDir, now: () => 1762364010000 },
    );

    assert.match(callStep.result.content[0].text, /step updated: 1\/3/);

    const lines = readFileSync(join(tempDir, "conv-abc.jsonl"), "utf8")
      .trim()
      .split("\n")
      .map((l) => JSON.parse(l));
    assert.deepEqual(
      lines.map((l) => l.type),
      ["plan", "phase", "task.accept", "run.progress"],
    );
    assert.equal(lines[3].id, "worker-xyz");
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("post tool round-trips posts with @mentions, kind, replyTo, and sequential seq numbers", () => {
  const tempDir = mkdtempSync(join(tmpdir(), "orch-mcp-post-"));
  try {
    handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "progress",
          arguments: {
            title: "Board Flow",
            phase: "delegate",
            tasks: [
              {
                title: "Build UI",
                specialist: "wren",
                tier: "core",
                after: [],
              },
              { title: "QA UI", specialist: "scout", tier: "fast", after: [1] },
            ],
          },
          _meta: {
            "antigravity.google/root_conversation_id": "conv-post",
            "antigravity.google/conversation_id": "conv-post",
          },
        },
      },
      { flowsDir: tempDir, now: () => 1000 },
    );

    const p1 = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: {
          name: "post",
          arguments: {
            text: "UI ready for review @scout @lead",
            kind: "result",
          },
          _meta: {
            "antigravity.google/root_conversation_id": "conv-post",
            "antigravity.google/conversation_id": "worker-wren",
            "antigravity.google/parent_conversation_id": "conv-post",
            "antigravity.google/agent_name": "wren",
          },
        },
      },
      { flowsDir: tempDir, now: () => 2000 },
    );
    assert.deepEqual(JSON.parse(p1.result.content[0].text), { seq: 1 });

    const p2 = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: {
          name: "post",
          arguments: {
            text: "Found contrast issue on badge",
            to: ["wren", "@lead"],
            kind: "defect",
            replyTo: 1,
          },
          _meta: {
            "antigravity.google/root_conversation_id": "conv-post",
            "antigravity.google/conversation_id": "worker-scout",
            "antigravity.google/parent_conversation_id": "conv-post",
            "antigravity.google/agent_name": "scout",
          },
        },
      },
      { flowsDir: tempDir, now: () => 3000 },
    );
    assert.deepEqual(JSON.parse(p2.result.content[0].text), { seq: 2 });

    // Empty post is ignored and returns seq 0.
    const emptyPost = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 4,
        method: "tools/call",
        params: {
          name: "post",
          arguments: { text: "   " },
          _meta: {
            "antigravity.google/root_conversation_id": "conv-post",
            "antigravity.google/conversation_id": "conv-post",
          },
        },
      },
      { flowsDir: tempDir, now: () => 4000 },
    );
    assert.deepEqual(JSON.parse(emptyPost.result.content[0].text), { seq: 0 });
    assert.equal(mapPostToEvent({ text: "" }, {}).valid, false);

    const flow = readFlowFromJsonlFile(join(tempDir, "conv-post.jsonl"));
    const posts = board(flow);
    assert.equal(posts.length, 2);
    assert.equal(posts[0].seq, 1);
    assert.equal(posts[0].from, "wren");
    assert.deepEqual(posts[0].to, ["scout", "lead"]);
    assert.equal(posts[0].kind, "result");
    assert.equal(posts[1].seq, 2);
    assert.equal(posts[1].from, "scout");
    assert.deepEqual(posts[1].to, ["wren", "lead"]);
    assert.equal(posts[1].kind, "defect");
    assert.equal(posts[1].replyTo, 1);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("step accepts paused without done/total, emits member.pause, and rejects step calls with neither done/total nor paused", () => {
  const tempDir = mkdtempSync(join(tmpdir(), "orch-mcp-step-pause-"));
  try {
    const flowPath = join(tempDir, "conv-pause.jsonl");
    handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "progress",
          arguments: {
            title: "Quota Test",
            phase: "delegate",
            tasks: [
              { title: "Run job", specialist: "wren", tier: "core", after: [] },
            ],
          },
          _meta: {
            "antigravity.google/root_conversation_id": "conv-pause",
            "antigravity.google/conversation_id": "conv-pause",
          },
        },
      },
      { flowsDir: tempDir, now: () => 1000 },
    );

    const workerMeta = {
      "antigravity.google/root_conversation_id": "conv-pause",
      "antigravity.google/conversation_id": "worker-1",
      "antigravity.google/parent_conversation_id": "conv-pause",
      "antigravity.google/agent_name": "wren",
    };

    // Seed a worker run in the flow JSONL so member.pause applies to an existing run.
    handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: {
          name: "step",
          arguments: { done: 1, total: 3, note: "starting" },
          _meta: workerMeta,
        },
      },
      { flowsDir: tempDir, now: () => 1100 },
    );

    // Reject step with neither done/total nor paused.
    const emptyStep = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: {
          name: "step",
          arguments: {},
          _meta: workerMeta,
        },
      },
      { flowsDir: tempDir, now: () => 1200 },
    );
    assert.ok(
      emptyStep.error,
      "expected JSON-RPC error when step has neither done/total nor paused",
    );
    assert.equal(emptyStep.error.code, -32602);

    const noteOnlyStep = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 4,
        method: "tools/call",
        params: {
          name: "step",
          arguments: { note: "only a note" },
          _meta: workerMeta,
        },
      },
      { flowsDir: tempDir, now: () => 1250 },
    );
    assert.ok(
      noteOnlyStep.error,
      "expected JSON-RPC error when step omits done/total and paused",
    );
    assert.equal(noteOnlyStep.error.code, -32602);

    const partialStep = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 5,
        method: "tools/call",
        params: {
          name: "step",
          arguments: { done: 1 },
          _meta: workerMeta,
        },
      },
      { flowsDir: tempDir, now: () => 1260 },
    );
    assert.ok(
      partialStep.error,
      "expected JSON-RPC error when total is missing",
    );
    assert.equal(partialStep.error.code, -32602);

    // Accept step with paused: "quota" and WITHOUT done/total.
    const pauseOnly = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 6,
        method: "tools/call",
        params: {
          name: "step",
          arguments: { paused: "quota", detail: "429 quota exhausted" },
          _meta: workerMeta,
        },
      },
      { flowsDir: tempDir, now: () => 1300 },
    );
    assert.equal(pauseOnly.error, undefined);
    assert.match(pauseOnly.result.content[0].text, /paused: quota/);

    const lines = readFileSync(flowPath, "utf8")
      .trim()
      .split("\n")
      .map((l) => JSON.parse(l));
    const pauseEvents = lines.filter((e) => e.type === "member.pause");
    assert.equal(pauseEvents.length, 1);
    assert.equal(pauseEvents[0].id, "worker-1");
    assert.equal(pauseEvents[0].reason, "quota");
    assert.equal(pauseEvents[0].detail, "429 quota exhausted");
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("progress with retire and kill emits member.retire and member.kill resolved against flow runs", () => {
  let flow = reduce(null, {
    type: "plan",
    at: 1000,
    title: "Lifecycle",
    tasks: [
      { title: "Task 1", specialist: "wren", tier: "core", after: [] },
      { title: "Task 2", specialist: "scout", tier: "fast", after: [] },
    ],
  });
  flow = reduce(flow, {
    type: "run.start",
    at: 1100,
    id: "conv-wren#2",
    harness: "antigravity",
    agent: "wren",
    model: "pro",
    effort: null,
    title: "Task 1",
    role: "worker",
  });
  flow = reduce(flow, {
    type: "run.start",
    at: 1200,
    id: "conv-scout",
    harness: "antigravity",
    agent: "scout",
    model: "flash",
    effort: null,
    title: "Task 2",
    role: "worker",
  });

  const events = mapProgressToEvents(
    { retire: "wren", kill: "conv-scout" },
    1500,
    "root-conv",
    undefined,
    flow,
  );
  assert.deepEqual(
    events.map((e) => ({ type: e.type, id: e.id })),
    [
      { type: "member.retire", id: "conv-wren#2" },
      { type: "member.kill", id: "conv-scout" },
    ],
  );

  for (const ev of events) {
    flow = reduce(flow, ev);
  }
  const m = members(flow);
  assert.equal(m.active.length, 0);
  assert.equal(m.standingBy.length, 0);
  assert.deepEqual(
    m.retired.map((r) => ({ id: r.id, state: r.state })),
    [
      { id: "conv-wren#2", state: "retired" },
      { id: "conv-scout", state: "killed" },
    ],
  );
});

test("board tool filters posts, resolves worker caller identity for omitted to and to='me', and clamps limit", () => {
  const tempDir = mkdtempSync(join(tmpdir(), "orch-mcp-board-"));
  try {
    const leadMeta = {
      "antigravity.google/root_conversation_id": "conv-board",
      "antigravity.google/conversation_id": "conv-board",
    };
    const wrenMeta = {
      "antigravity.google/root_conversation_id": "conv-board",
      "antigravity.google/conversation_id": "worker-wren",
      "antigravity.google/parent_conversation_id": "conv-board",
      "antigravity.google/agent_name": "wren",
    };
    const scoutMeta = {
      "antigravity.google/root_conversation_id": "conv-board",
      "antigravity.google/conversation_id": "worker-scout",
      "antigravity.google/parent_conversation_id": "conv-board",
      "antigravity.google/agent_name": "scout",
    };

    const call = (name, args, meta, at) =>
      handleJsonRpcMessage(
        {
          jsonrpc: "2.0",
          id: at,
          method: "tools/call",
          params: { name, arguments: args, _meta: meta },
        },
        { flowsDir: tempDir, now: () => at },
      );

    call(
      "progress",
      {
        title: "Board Read Test",
        phase: "delegate",
        tasks: [
          { title: "Build", specialist: "wren", tier: "core", after: [] },
          { title: "QA", specialist: "scout", tier: "fast", after: [] },
        ],
      },
      leadMeta,
      1000,
    );
    call(
      "post",
      { text: "Broadcast update @all", kind: "note" },
      leadMeta,
      1100,
    );
    call(
      "post",
      { text: "Fix contrast @wren", kind: "defect" },
      scoutMeta,
      1200,
    );
    call(
      "post",
      { text: "Question for @scout only", kind: "question", replyTo: 2 },
      wrenMeta,
      1300,
    );

    // Worker with omitted `to` defaults to posts mentioning that worker (including @all).
    const wrenDefault = JSON.parse(
      call("board", {}, wrenMeta, 1400).result.content[0].text,
    );
    assert.deepEqual(
      wrenDefault.map((p) => p.seq),
      [1, 2],
    );
    assert.deepEqual(Object.keys(wrenDefault[0]).sort(), [
      "at",
      "from",
      "kind",
      "replyTo",
      "seq",
      "text",
      "to",
    ]);

    // Worker with explicit `to: "me"` matches the same caller mentions.
    const scoutMe = JSON.parse(
      call("board", { to: "me" }, scoutMeta, 1410).result.content[0].text,
    );
    assert.deepEqual(
      scoutMe.map((p) => p.seq),
      [1, 3],
    );
    assert.equal(scoutMe[1].replyTo, 2);

    // Lead with omitted `to` sees all newest posts; limit clamps to [1, 100].
    const leadAll = JSON.parse(
      call("board", { limit: 500 }, leadMeta, 1420).result.content[0].text,
    );
    assert.deepEqual(
      leadAll.map((p) => p.seq),
      [1, 2, 3],
    );

    const leadLimited = JSON.parse(
      call("board", { limit: 1 }, leadMeta, 1430).result.content[0].text,
    );
    assert.deepEqual(
      leadLimited.map((p) => p.seq),
      [3],
    );

    const filtered = JSON.parse(
      call(
        "board",
        { from: "scout", kind: "defect", search: "contrast" },
        leadMeta,
        1440,
      ).result.content[0].text,
    );
    assert.equal(filtered.length, 1);
    assert.equal(filtered[0].seq, 2);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("board tool resolves worker caller identity without agent_name (via conversation_id -> run) and falls back to same-flow newest posts for unknown callers", () => {
  const tempDir = mkdtempSync(join(tmpdir(), "orch-mcp-board-realmeta-"));
  try {
    const flowsDir = join(tempDir, "flows");
    const brainRoot = join(tempDir, "app-data");
    mkdirSync(flowsDir, { recursive: true });
    const t0 = 1_762_364_000_000;
    const iso = (t) => new Date(t).toISOString();

    // Seed lead transcript with invoke_subagent runs (how Antigravity records worker runs in production; no agent_name in _meta).
    const leadTranscriptDir = join(
      brainRoot,
      "brain",
      "conv-real-board",
      ".system_generated",
      "logs",
    );
    mkdirSync(leadTranscriptDir, { recursive: true });
    writeFileSync(
      join(leadTranscriptDir, "transcript.jsonl"),
      [
        JSON.stringify({
          step_index: 1,
          type: "PLANNER_RESPONSE",
          status: "DONE",
          created_at: iso(t0 + 500),
          tool_calls: [
            {
              name: "invoke_subagent",
              args: { TypeName: "wren", Role: "Build", Model: "pro" },
            },
          ],
        }),
        JSON.stringify({
          step_index: 2,
          type: "GENERIC",
          status: "DONE",
          created_at: iso(t0 + 600),
          content: 'Created subagent:\n{"conversationId": "uuid-worker-wren"}',
        }),
        JSON.stringify({
          step_index: 3,
          type: "PLANNER_RESPONSE",
          status: "DONE",
          created_at: iso(t0 + 700),
          tool_calls: [
            {
              name: "invoke_subagent",
              args: { TypeName: "scout", Role: "QA", Model: "flash" },
            },
          ],
        }),
        JSON.stringify({
          step_index: 4,
          type: "GENERIC",
          status: "DONE",
          created_at: iso(t0 + 800),
          content: 'Created subagent:\n{"conversationId": "uuid-worker-scout"}',
        }),
      ].join("\n") + "\n",
      "utf8",
    );

    // Realistic Antigravity _meta: NO `antigravity.google/agent_name`.
    const leadMeta = {
      "antigravity.google/root_conversation_id": "conv-real-board",
      "antigravity.google/conversation_id": "conv-real-board",
      "antigravity.google/artifacts_dir": join(
        brainRoot,
        "brain",
        "conv-real-board",
      ),
    };
    const wrenRealMeta = {
      "antigravity.google/root_conversation_id": "conv-real-board",
      "antigravity.google/parent_conversation_id": "conv-real-board",
      "antigravity.google/conversation_id": "uuid-worker-wren",
      "antigravity.google/artifacts_dir": join(
        brainRoot,
        "brain",
        "uuid-worker-wren",
      ),
    };
    const scoutRealMeta = {
      "antigravity.google/root_conversation_id": "conv-real-board",
      "antigravity.google/parent_conversation_id": "conv-real-board",
      "antigravity.google/conversation_id": "uuid-worker-scout",
      "antigravity.google/artifacts_dir": join(
        brainRoot,
        "brain",
        "uuid-worker-scout",
      ),
    };
    const unknownWorkerMeta = {
      "antigravity.google/root_conversation_id": "conv-real-board",
      "antigravity.google/parent_conversation_id": "conv-real-board",
      "antigravity.google/conversation_id": "uuid-untracked-helper",
      "antigravity.google/artifacts_dir": join(
        brainRoot,
        "brain",
        "uuid-untracked-helper",
      ),
    };

    // Seed a separate flow's board in the same flowsDir to ensure cross-flow posts never leak.
    const otherLeadMeta = {
      "antigravity.google/root_conversation_id": "conv-other-flow",
      "antigravity.google/conversation_id": "conv-other-flow",
      "antigravity.google/artifacts_dir": join(
        brainRoot,
        "brain",
        "conv-other-flow",
      ),
    };

    const call = (name, args, meta, at) =>
      handleJsonRpcMessage(
        {
          jsonrpc: "2.0",
          id: at,
          method: "tools/call",
          params: { name, arguments: args, _meta: meta },
        },
        { flowsDir, brainRoots: [brainRoot], now: () => at },
      );

    call(
      "progress",
      {
        title: "Other Flow",
        phase: "delegate",
        tasks: [
          { title: "Other", specialist: "wren", tier: "core", after: [] },
        ],
      },
      otherLeadMeta,
      t0 - 2000,
    );
    call(
      "post",
      { text: "Cross-flow secret @all @wren", kind: "note" },
      otherLeadMeta,
      t0 - 1000,
    );

    call(
      "progress",
      {
        title: "Real Meta Board",
        phase: "delegate",
        tasks: [
          { title: "Build", specialist: "wren", tier: "core", after: [] },
          { title: "QA", specialist: "scout", tier: "fast", after: [] },
        ],
      },
      leadMeta,
      t0,
    );
    call(
      "post",
      { text: "Team update @all", kind: "note" },
      leadMeta,
      t0 + 1000,
    );
    call(
      "post",
      { text: "Defect for @wren", kind: "defect" },
      scoutRealMeta,
      t0 + 2000,
    );
    call(
      "post",
      { text: "Note for @scout only", kind: "question" },
      wrenRealMeta,
      t0 + 3000,
    );

    // 1. Known worker caller (no agent_name in _meta; matched by conversation_id -> transcript run):
    //    omitted `to` and `to: "me"` both default to `wren` (posts #1 and #2, never #3 or other flow).
    const wrenOmitted = JSON.parse(
      call("board", {}, wrenRealMeta, t0 + 4000).result.content[0].text,
    );
    assert.deepEqual(
      wrenOmitted.map((p) => p.seq),
      [1, 2],
    );
    assert.equal(wrenOmitted[1].from, "scout");

    const wrenMe = JSON.parse(
      call("board", { to: "me" }, wrenRealMeta, t0 + 4100).result.content[0]
        .text,
    );
    assert.deepEqual(
      wrenMe.map((p) => p.seq),
      [1, 2],
    );

    // 2. Unknown caller (untracked worker conversation_id, or caller with no conversation_id):
    //    returns newest posts on conv-real-board (#1, #2, #3), never empty [] and never conv-other-flow posts.
    const unknownOmitted = JSON.parse(
      call("board", {}, unknownWorkerMeta, t0 + 4200).result.content[0].text,
    );
    assert.deepEqual(
      unknownOmitted.map((p) => p.seq),
      [1, 2, 3],
    );
    assert.ok(
      unknownOmitted.every((p) => !p.text.includes("Cross-flow secret")),
    );

    const unknownMe = JSON.parse(
      call("board", { to: "me" }, unknownWorkerMeta, t0 + 4300).result
        .content[0].text,
    );
    assert.deepEqual(
      unknownMe.map((p) => p.seq),
      [1, 2, 3],
    );
    assert.ok(unknownMe.every((p) => !p.text.includes("Cross-flow secret")));
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("readFlowFromJsonlFile loads runs from sample-flow.jsonl and folds transcript invoke_subagent runs like the sidecar", () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const sampleFlowPath = join(
    here,
    "..",
    "sidecars",
    "panel",
    "testdata",
    "sample-flow.jsonl",
  );

  // 1. Explicit run.start events in sample-flow.jsonl are loaded directly.
  const sampleFlow = readFlowFromJsonlFile(sampleFlowPath);
  assert.ok(sampleFlow);
  assert.deepEqual(
    sampleFlow.runs.map((r) => r.id),
    ["lead-main", "run-wren-1", "run-wren-2"],
  );

  // 2. Live Antigravity flow (where flow JSONL has plan + run.progress and transcript.jsonl has invoke_subagent runs)
  //    folds transcript runs so MCP server sees the same runs and step progress as the sidecar.
  const tempDir = mkdtempSync(join(tmpdir(), "orch-mcp-loader-"));
  try {
    const flowsDir = join(tempDir, "flows");
    const brainRoot = join(tempDir, "app-data");
    mkdirSync(flowsDir, { recursive: true });
    const cid = "sample-transcript-flow";

    const sampleLines = readFileSync(sampleFlowPath, "utf8")
      .trim()
      .split("\n")
      .map((l) => JSON.parse(l))
      .filter((ev) => ev.type !== "run.start" && ev.type !== "run.end");
    const flowPath = join(flowsDir, `${cid}.jsonl`);
    writeFileSync(
      flowPath,
      sampleLines
        .map((ev) => JSON.stringify({ ...ev, rootConversationId: cid }))
        .join("\n") + "\n",
      "utf8",
    );

    const transcriptDir = join(
      brainRoot,
      "brain",
      cid,
      ".system_generated",
      "logs",
    );
    mkdirSync(transcriptDir, { recursive: true });
    const iso = (t) => new Date(t).toISOString();
    writeFileSync(
      join(transcriptDir, "transcript.jsonl"),
      [
        JSON.stringify({
          step_index: 1,
          type: "PLANNER_RESPONSE",
          status: "DONE",
          model: "claude-opus-5-5",
          input_tokens: 45000,
          output_tokens: 4200,
          created_at: iso(1762364010000),
          tool_calls: [
            {
              name: "invoke_subagent",
              args: {
                TypeName: "wren",
                Role: "Build MCP stdio server",
                Model: "claude-sonnet-4-5",
              },
            },
          ],
        }),
        JSON.stringify({
          step_index: 2,
          type: "GENERIC",
          status: "DONE",
          created_at: iso(1762364015000),
          content: 'Created subagent:\n{"conversationId": "run-wren-1"}',
        }),
        JSON.stringify({
          step_index: 3,
          type: "SYSTEM_MESSAGE",
          status: "DONE",
          created_at: iso(1762364090000),
          content: "[Message] sender=run-wren-1 content=Done",
        }),
        JSON.stringify({
          step_index: 4,
          type: "PLANNER_RESPONSE",
          status: "DONE",
          created_at: iso(1762364130000),
          tool_calls: [
            {
              name: "invoke_subagent",
              args: {
                TypeName: "wren",
                Role: "Build sidecar live panel",
                Model: "gemini-4-argon-high",
              },
            },
          ],
        }),
        JSON.stringify({
          step_index: 5,
          type: "GENERIC",
          status: "DONE",
          created_at: iso(1762364135000),
          content: 'Created subagent:\n{"conversationId": "run-wren-2"}',
        }),
      ].join("\n") + "\n",
      "utf8",
    );

    const folded = readFlowFromJsonlFile(flowPath, { brainRoots: [brainRoot] });
    assert.ok(folded);
    assert.deepEqual(
      folded.runs.map((r) => ({ id: r.id, agent: r.agent, status: r.status })),
      [
        { id: "lead", agent: "lead", status: "running" },
        { id: "run-wren-1", agent: "wren", status: "done" },
        { id: "run-wren-2", agent: "wren", status: "running" },
      ],
    );
    assert.deepEqual(folded.runs[2].steps, {
      done: 2,
      total: 4,
      note: "rendering inline SVG burn-down",
    });
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("security item 1: progress is lead-only in Antigravity MCP server", () => {
  const tempDir = mkdtempSync(join(tmpdir(), "orch-mcp-sec-prog-"));
  try {
    // Lead call works.
    const leadRes = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "progress",
          arguments: {
            title: "Lead Flow",
            phase: "delegate",
            tasks: [
              { title: "Task 1", specialist: "wren", tier: "core", after: [] },
            ],
          },
          _meta: {
            "antigravity.google/root_conversation_id": "lead-root-1",
            "antigravity.google/conversation_id": "lead-root-1",
          },
        },
      },
      { flowsDir: tempDir, now: () => 1000 },
    );
    assert.equal(leadRes.result.content[0].text, "flow updated: 0/1 accepted");

    // Seed a worker run into lead-root-1.jsonl so worker-run lookup is also tested.
    const flowPath = join(tempDir, "lead-root-1.jsonl");
    writeFileSync(
      flowPath,
      `${readFileSync(flowPath, "utf8")}${JSON.stringify({
        type: "run.start",
        at: 1010,
        id: "worker-conv-42",
        harness: "antigravity",
        agent: "wren",
        model: "pro",
        title: "Task 1",
        role: "worker",
      })}\n`,
      "utf8",
    );
    const beforeDisk = readFileSync(flowPath, "utf8");

    // 1) Helper with parent_conversation_id -> rejected
    const helperParentRes = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: {
          name: "progress",
          arguments: { accept: 1, finished: true },
          _meta: {
            "antigravity.google/root_conversation_id": "lead-root-1",
            "antigravity.google/parent_conversation_id": "lead-root-1",
            "antigravity.google/conversation_id": "sub-conv-9",
          },
        },
      },
      { flowsDir: tempDir, now: () => 1020 },
    );
    assert.ok(helperParentRes.error);
    assert.match(
      helperParentRes.error.message,
      /progress is for the lead only/,
    );

    // 2) Helper with agent_name -> rejected
    const helperAgentRes = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: {
          name: "progress",
          arguments: { accept: 1 },
          _meta: {
            "antigravity.google/root_conversation_id": "lead-root-1",
            "antigravity.google/agent_name": "wren",
          },
        },
      },
      { flowsDir: tempDir, now: () => 1030 },
    );
    assert.ok(helperAgentRes.error);
    assert.match(helperAgentRes.error.message, /progress is for the lead only/);

    // 3) Helper whose conversation_id maps to a worker run (even without parent_conversation_id) -> rejected
    const helperRunRes = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 4,
        method: "tools/call",
        params: {
          name: "progress",
          arguments: { kill: "wren" },
          _meta: {
            "antigravity.google/conversation_id": "worker-conv-42",
          },
        },
      },
      { flowsDir: tempDir, now: () => 1040 },
    );
    assert.ok(helperRunRes.error);
    assert.match(helperRunRes.error.message, /progress is for the lead only/);

    assert.equal(readFileSync(flowPath, "utf8"), beforeDisk);
    assert.deepEqual(readdirSync(tempDir), ["lead-root-1.jsonl"]);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("security item 3: post from comes only from caller identity and helper never resolves to lead", () => {
  // Lead ignores arguments.from
  const leadMapped = mapPostToEvent(
    { text: "Lead note", from: "wren" },
    {
      "antigravity.google/root_conversation_id": "lead-1",
      "antigravity.google/conversation_id": "lead-1",
    },
    2000,
  );
  assert.equal(leadMapped.event.from, "lead");

  // Helper with agent_name: "wren" ignores arguments.from: "lead"
  const wrenMapped = mapPostToEvent(
    { text: "Worker note", from: "lead" },
    {
      "antigravity.google/root_conversation_id": "lead-1",
      "antigravity.google/parent_conversation_id": "lead-1",
      "antigravity.google/agent_name": "wren",
    },
    2010,
  );
  assert.equal(wrenMapped.event.from, "wren");

  // Helper spoofing agent_name: "lead" coerces to "helper"
  const spoofLeadMapped = mapPostToEvent(
    { text: "Spoof attempt" },
    {
      "antigravity.google/root_conversation_id": "lead-1",
      "antigravity.google/parent_conversation_id": "lead-1",
      "antigravity.google/agent_name": "lead",
    },
    2020,
  );
  assert.equal(spoofLeadMapped.event.from, "helper");

  // Unknown helper without agent_name coerces to "helper" (never callerConversationId if "lead" or invalid)
  const unknownHelperMapped = mapPostToEvent(
    { text: "Anonymous helper" },
    {
      "antigravity.google/root_conversation_id": "lead-1",
      "antigravity.google/parent_conversation_id": "lead-1",
      "antigravity.google/conversation_id": "sub_invalid_handle!",
    },
    2030,
  );
  assert.equal(unknownHelperMapped.event.from, "helper");
});

test("security item 5: Antigravity MCP stdin reader rejects frames over 256 KB", () => {
  const bigText = "x".repeat(260 * 1024);
  const smallMsg = { jsonrpc: "2.0", id: 2, method: "ping" };

  // Oversized NDJSON frame (> 256 KB) followed by valid frame
  const ndStream =
    JSON.stringify({ jsonrpc: "2.0", id: 1, method: "ping", pad: bigText }) +
    "\n" +
    formatJsonRpcFrame(smallMsg, "ndjson");
  const parsedNd = parseJsonRpcFrames(ndStream);
  assert.deepEqual(parsedNd.messages, [smallMsg]);
  assert.equal(
    Array.isArray(parsedNd.errors) && parsedNd.errors.length === 1,
    true,
  );

  // Oversized Content-Length frame (> 256 KB) followed by valid frame
  const bigJson = JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "ping",
    pad: bigText,
  });
  const clStream =
    `Content-Length: ${Buffer.byteLength(bigJson, "utf8")}\r\n\r\n${bigJson}` +
    formatJsonRpcFrame(smallMsg, "content-length");
  const parsedCl = parseJsonRpcFrames(clStream);
  assert.deepEqual(parsedCl.messages, [smallMsg]);
  assert.equal(
    Array.isArray(parsedCl.errors) && parsedCl.errors.length === 1,
    true,
  );
});

test("security item 6: sanitizeConversationId validates /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/ and skips invalid IDs before path join", () => {
  for (const bad of [
    "",
    ".",
    "..",
    "../etc/passwd",
    ".hidden",
    "a..b",
    "a/b",
    "a".repeat(129),
  ]) {
    assert.equal(
      sanitizeConversationId(bad),
      "",
      `expected ${JSON.stringify(bad)} to be rejected`,
    );
  }
  assert.equal(sanitizeConversationId("conv-abc_1.2"), "conv-abc_1.2");

  const parentDir = mkdtempSync(join(tmpdir(), "orch-mcp-sec-path-"));
  try {
    const flowsDir = join(parentDir, "flows");
    mkdirSync(flowsDir, { recursive: true });
    for (const badRoot of ["..", ".", "../escaped", ".dotfile"]) {
      handleJsonRpcMessage(
        {
          jsonrpc: "2.0",
          id: 1,
          method: "tools/call",
          params: {
            name: "progress",
            arguments: {
              title: "Escape",
              tasks: [
                { title: "T", specialist: "wren", tier: "core", after: [] },
              ],
            },
            _meta: { "antigravity.google/root_conversation_id": badRoot },
          },
        },
        { flowsDir, now: () => 3000 },
      );
    }
    assert.deepEqual(readdirSync(flowsDir), []);
    assert.deepEqual(readdirSync(parentDir), ["flows"]);
  } finally {
    rmSync(parentDir, { recursive: true, force: true });
  }
});

test("round 2 item 1: missing caller identity is rejected for progress and treated as helper for post and board, while lead _meta and ANTIGRAVITY_CONVERSATION_ID fallback work", () => {
  const tempDir = mkdtempSync(join(tmpdir(), "orch-mcp-r2-item1-"));
  const prevEnvCid = process.env.ANTIGRAVITY_CONVERSATION_ID;
  delete process.env.ANTIGRAVITY_CONVERSATION_ID;
  try {
    const call = (name, args, meta, at) =>
      handleJsonRpcMessage(
        {
          jsonrpc: "2.0",
          id: at,
          method: "tools/call",
          params: { name, arguments: args, _meta: meta },
        },
        { flowsDir: tempDir, now: () => at },
      );

    // 1. Empty _meta with no ANTIGRAVITY_CONVERSATION_ID -> progress rejected ("caller unknown")
    const emptyProgress = call(
      "progress",
      {
        title: "Unauthorized Flow",
        phase: "plan",
        tasks: [{ title: "T1", specialist: "wren", tier: "core", after: [] }],
      },
      {},
      1000,
    );
    assert.ok(emptyProgress.error);
    assert.equal(emptyProgress.error.code, -32602);
    assert.match(
      emptyProgress.error.message,
      /progress is for the lead only: caller unknown/,
    );
    assert.deepEqual(readdirSync(tempDir), []);

    // 2. Empty _meta -> post records from: "helper" (never "lead")
    const emptyPostMapped = mapPostToEvent(
      { text: "Unidentified note" },
      {},
      1100,
    );
    assert.equal(emptyPostMapped.valid, true);
    assert.equal(emptyPostMapped.event.from, "helper");

    const emptyPostRpc = call(
      "post",
      { text: "Hello from empty meta" },
      {},
      1150,
    );
    assert.deepEqual(JSON.parse(emptyPostRpc.result.content[0].text), {
      seq: 1,
    });
    const defaultEvent = JSON.parse(
      readFileSync(join(tempDir, "default.jsonl"), "utf8").trim(),
    );
    assert.equal(defaultEvent.from, "helper");

    // 3. Missing conversation_id with only root_conversation_id -> progress rejected ("caller unknown"), post is "helper"
    const rootOnlyProgress = call(
      "progress",
      {
        title: "Root Only",
        phase: "plan",
        tasks: [{ title: "T1", specialist: "wren", tier: "core", after: [] }],
      },
      { "antigravity.google/root_conversation_id": "lead-conv-r2" },
      1200,
    );
    assert.ok(rootOnlyProgress.error);
    assert.match(
      rootOnlyProgress.error.message,
      /progress is for the lead only: caller unknown/,
    );

    // 4. Real lead _meta (root_conversation_id + matching conversation_id) -> progress works, post is "lead"
    const leadMeta = {
      "antigravity.google/root_conversation_id": "lead-conv-r2",
      "antigravity.google/conversation_id": "lead-conv-r2",
    };
    const leadProgress = call(
      "progress",
      {
        title: "Verified Lead Flow",
        phase: "delegate",
        tasks: [{ title: "T1", specialist: "wren", tier: "core", after: [] }],
      },
      leadMeta,
      1300,
    );
    assert.equal(leadProgress.error, undefined);
    assert.equal(
      leadProgress.result.content[0].text,
      "flow updated: 0/1 accepted",
    );

    call("post", { text: "Private note for @lead" }, leadMeta, 1310);
    call("post", { text: "Ping @helper" }, leadMeta, 1320);
    call(
      "post",
      { text: "Unidentified caller on flow" },
      { "antigravity.google/root_conversation_id": "lead-conv-r2" },
      1330,
    );

    const flowR2 = readFlowFromJsonlFile(join(tempDir, "lead-conv-r2.jsonl"));
    assert.equal(flowR2.posts[0].from, "lead");
    assert.equal(flowR2.posts[2].from, "helper");

    // board with no usable caller id treats caller as helper (never lead)
    const boardNoCallerDefault = queryBoard(
      {},
      { "antigravity.google/root_conversation_id": "lead-conv-r2" },
      flowR2,
    );
    assert.deepEqual(
      boardNoCallerDefault.map((p) => p.seq),
      [2],
    );
    const boardNoCallerMe = queryBoard(
      { to: "me" },
      { "antigravity.google/root_conversation_id": "lead-conv-r2" },
      flowR2,
    );
    assert.deepEqual(
      boardNoCallerMe.map((p) => p.seq),
      [2],
    );
    const boardLeadMe = queryBoard({ to: "me" }, leadMeta, flowR2);
    assert.deepEqual(
      boardLeadMe.map((p) => p.seq),
      [1],
    );

    // 5. Fallback to sanitizeConversationId(process.env.ANTIGRAVITY_CONVERSATION_ID) when _meta omits conversation_id
    process.env.ANTIGRAVITY_CONVERSATION_ID = "env-root-conv";
    const envProgress = call(
      "progress",
      {
        title: "Env Root Flow",
        phase: "plan",
        tasks: [{ title: "T1", specialist: "wren", tier: "core", after: [] }],
      },
      {},
      1400,
    );
    assert.equal(envProgress.error, undefined);
    assert.equal(
      envProgress.result.content[0].text,
      "flow updated: 0/1 accepted",
    );
    const envPost = mapPostToEvent({ text: "Lead via env" }, {}, 1410);
    assert.equal(envPost.event.from, "lead");

    // Mismatched explicit root vs ANTIGRAVITY_CONVERSATION_ID is rejected
    const mismatchedEnvProgress = call(
      "progress",
      { accept: 1 },
      { "antigravity.google/root_conversation_id": "different-root" },
      1420,
    );
    assert.ok(mismatchedEnvProgress.error);
    assert.match(
      mismatchedEnvProgress.error.message,
      /progress is for the lead only/,
    );
  } finally {
    if (prevEnvCid === undefined) {
      delete process.env.ANTIGRAVITY_CONVERSATION_ID;
    } else {
      process.env.ANTIGRAVITY_CONVERSATION_ID = prevEnvCid;
    }
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("round 2 item 4: queryBoard never maps a worker named 'lead' to lead (resolving 'me' from run) and resolveServerBrainRoots ignores artifacts_dir outside known app-data roots", () => {
  const tempDir = mkdtempSync(join(tmpdir(), "orch-mcp-r2-item4-"));
  const prevAppData = process.env.ANTIGRAVITY_APP_DATA_DIR;
  try {
    // Part A: queryBoard with worker whose agent_name (or run.agent) is "lead"
    let flow = reduce(null, {
      type: "plan",
      at: 1000,
      title: "Worker Lead Spoof",
      tasks: [{ title: "Build", specialist: "wren", tier: "core", after: [] }],
    });
    flow = reduce(flow, {
      type: "run.start",
      at: 1010,
      id: "worker-run-wren",
      harness: "antigravity",
      agent: "wren",
      model: "pro",
      title: "Build",
      role: "worker",
    });
    flow = reduce(flow, {
      type: "run.start",
      at: 1020,
      id: "worker-run-named-lead",
      harness: "antigravity",
      agent: "lead",
      model: "pro",
      title: "Other",
      role: "worker",
    });
    flow = reduce(flow, {
      type: "post",
      at: 1100,
      from: "lead",
      text: "Eyes only for @lead",
    });
    flow = reduce(flow, {
      type: "post",
      at: 1110,
      from: "lead",
      text: "Task instructions for @wren",
    });
    flow = reduce(flow, {
      type: "post",
      at: 1120,
      from: "lead",
      text: "Fallback ping for @helper",
    });

    // 1. Worker passing agent_name: "lead" whose conversation_id matches run "wren" -> resolves "me" from the run ("wren")
    const backedByWrenRun = queryBoard(
      { to: "me" },
      {
        "antigravity.google/root_conversation_id": "conv-q",
        "antigravity.google/parent_conversation_id": "conv-q",
        "antigravity.google/conversation_id": "worker-run-wren",
        "antigravity.google/agent_name": "lead",
      },
      flow,
    );
    assert.deepEqual(
      backedByWrenRun.map((p) => p.seq),
      [2],
    );

    // 2. Worker passing agent_name: "lead" with no matching run -> never maps "me" or default `to` to "lead"
    const unbackedLeadWorkerMe = queryBoard(
      { to: "me" },
      {
        "antigravity.google/root_conversation_id": "conv-q",
        "antigravity.google/parent_conversation_id": "conv-q",
        "antigravity.google/conversation_id": "worker-no-run",
        "antigravity.google/agent_name": "lead",
      },
      flow,
    );
    assert.deepEqual(
      unbackedLeadWorkerMe.map((p) => p.seq),
      [3],
    );

    // 3. Worker whose run itself has agent: "lead" -> still a worker, never maps "me" to "lead"
    const runNamedLeadMe = queryBoard(
      { to: "me" },
      {
        "antigravity.google/root_conversation_id": "conv-q",
        "antigravity.google/parent_conversation_id": "conv-q",
        "antigravity.google/conversation_id": "worker-run-named-lead",
        "antigravity.google/agent_name": "lead",
      },
      flow,
    );
    assert.deepEqual(
      runNamedLeadMe.map((p) => p.seq),
      [3],
    );

    // Part B: resolveServerBrainRoots / readFlowFromJsonlFile only accepts _meta.artifacts_dir under known app-data roots
    const knownAppData = join(tempDir, "known-appdata");
    const rogueAppData = join(tempDir, "known-appdata-rogue");
    const outsideDir = join(tempDir, "outside-appdata");
    mkdirSync(knownAppData, { recursive: true });
    mkdirSync(rogueAppData, { recursive: true });
    mkdirSync(outsideDir, { recursive: true });
    process.env.ANTIGRAVITY_APP_DATA_DIR = knownAppData;

    const cid = "conv-artifacts-check";
    const flowPath = join(tempDir, `${cid}.jsonl`);
    writeFileSync(
      flowPath,
      `${JSON.stringify({
        type: "plan",
        at: 1_762_364_000_000,
        title: "Artifacts Root Check",
        tasks: [
          { title: "Build", specialist: "wren", tier: "core", after: [] },
        ],
      })}\n`,
      "utf8",
    );

    const writeFakeTranscript = (rootDir, subagentId) => {
      const logDir = join(rootDir, "brain", cid, ".system_generated", "logs");
      mkdirSync(logDir, { recursive: true });
      const iso = (t) => new Date(t).toISOString();
      writeFileSync(
        join(logDir, "transcript.jsonl"),
        [
          JSON.stringify({
            step_index: 1,
            type: "PLANNER_RESPONSE",
            status: "DONE",
            created_at: iso(1_762_364_001_000),
            tool_calls: [
              {
                name: "invoke_subagent",
                args: { TypeName: "wren", Role: "Build", Model: "pro" },
              },
            ],
          }),
          JSON.stringify({
            step_index: 2,
            type: "GENERIC",
            status: "DONE",
            created_at: iso(1_762_364_002_000),
            content: `Created subagent:\n{"conversationId": "${subagentId}"}`,
          }),
        ].join("\n") + "\n",
        "utf8",
      );
    };

    writeFakeTranscript(outsideDir, "forged-outside-run");
    writeFakeTranscript(rogueAppData, "forged-prefix-run");

    // 1. Untrusted outside artifacts_dir is ignored (no forged transcript runs loaded)
    const fromOutside = readFlowFromJsonlFile(flowPath, {
      conversationId: cid,
      meta: {
        "antigravity.google/artifacts_dir": join(outsideDir, "brain", cid),
      },
    });
    assert.equal(
      fromOutside.runs.some((r) => r.id === "forged-outside-run"),
      false,
    );

    // 2. Sibling prefix path `known-appdata-rogue/brain/<cid>` is also ignored
    const fromPrefixSibling = readFlowFromJsonlFile(flowPath, {
      conversationId: cid,
      meta: {
        "antigravity.google/artifacts_dir": join(rogueAppData, "brain", cid),
      },
    });
    assert.equal(
      fromPrefixSibling.runs.some((r) => r.id === "forged-prefix-run"),
      false,
    );

    // 3. Symlink inside known app-data root pointing outside is also ignored
    const symlinkProfileDir = join(knownAppData, "symlinked");
    symlinkSync(outsideDir, symlinkProfileDir);
    const fromSymlinkEscape = readFlowFromJsonlFile(flowPath, {
      conversationId: cid,
      meta: {
        "antigravity.google/artifacts_dir": join(
          symlinkProfileDir,
          "brain",
          cid,
        ),
      },
    });
    assert.equal(
      fromSymlinkEscape.runs.some((r) => r.id === "forged-outside-run"),
      false,
    );

    // 4. Legitimate path under known app-data root (e.g. profile dir inside knownAppData) IS accepted
    const trustedSubRoot = join(knownAppData, "profiles", "work");
    writeFakeTranscript(trustedSubRoot, "trusted-profile-run");
    const fromTrusted = readFlowFromJsonlFile(flowPath, {
      conversationId: cid,
      meta: {
        "antigravity.google/artifacts_dir": join(trustedSubRoot, "brain", cid),
      },
    });
    assert.equal(
      fromTrusted.runs.some((r) => r.id === "trusted-profile-run"),
      true,
    );
  } finally {
    if (prevAppData === undefined) {
      delete process.env.ANTIGRAVITY_APP_DATA_DIR;
    } else {
      process.env.ANTIGRAVITY_APP_DATA_DIR = prevAppData;
    }
    rmSync(tempDir, { recursive: true, force: true });
  }
});
