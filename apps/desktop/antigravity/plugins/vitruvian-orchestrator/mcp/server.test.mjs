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
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { reduce } from "../sidecars/panel/lib/orchestrator-core.mjs";
import {
  extractConversationMeta,
  formatJsonRpcFrame,
  handleJsonRpcMessage,
  mapProgressToEvents,
  mapStepToEvent,
  parseJsonRpcFrames,
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
      ["progress", "step"],
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
