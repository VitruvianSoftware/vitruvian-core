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
  aggregateProjectReceipts,
  detectTokenHotspots,
  formatCsvReceipt,
  parseTranscriptJsonl,
  projectFromPath,
  renderHtmlReceipt,
} from "./core.mjs";

const SAMPLE_JSONL = [
  JSON.stringify({
    step_index: 0,
    type: "USER_INPUT",
    status: "DONE",
    created_at: "2026-10-23T18:00:00Z",
    content:
      "Active Workspaces:\n- /Users/james/Workspace/gh/application/vitruvian/vitruvian-core\n<USER_REQUEST>\nBuild receipts-report plugin\n</USER_REQUEST>",
  }),
  JSON.stringify({
    step_index: 1,
    type: "PLANNER_RESPONSE",
    status: "DONE",
    created_at: "2026-10-23T18:01:00Z",
    thinking: "Planning the plugin architecture",
    content: "Let's inspect the directory and commit changes.",
    truncated_fields: ["thinking"],
    tool_calls: [
      {
        name: "read_file",
        args: {
          Path: "/Users/james/Workspace/gh/application/vitruvian/vitruvian-core/README.md",
        },
      },
      {
        name: "invoke_subagent",
        args: {
          TypeName: "scout",
          Role: "CI Test Runner",
          Prompt: "Run tests",
        },
      },
      {
        name: "run_command",
        args: {
          CommandLine:
            'bazel run //tools/git:commit -- --agent wren -m "feat(receipts): add parser"',
        },
      },
      {
        name: "run_command",
        args: {
          CommandLine:
            'bazel run //tools/agent-app -- pr-create --title "feat(receipts): initial plugin"',
        },
      },
    ],
  }),
  JSON.stringify({
    step_index: 2,
    type: "PLANNER_RESPONSE",
    status: "ERROR",
    created_at: "2026-10-23T18:05:00Z",
    content:
      "Opened https://github.com/VitruvianSoftware/vitruvian-core/pull/4120 [main 9f8e7d6]",
    truncated_fields: ["content", "tool_calls"],
    tool_calls: [{ name: "run_command", args: { CommandLine: "node --test" } }],
  }),
].join("\n");

test("projectFromPath extracts the trailing directory name", () => {
  assert.equal(
    projectFromPath(
      "/Users/james/Workspace/gh/application/vitruvian/vitruvian-core/",
    ),
    "vitruvian-core",
  );
  assert.equal(projectFromPath(""), "unassigned");
});

test("parseTranscriptJsonl parses steps, tool calls, subagents, truncations, commits, and PRs", () => {
  const session = parseTranscriptJsonl(SAMPLE_JSONL, {
    conversationId: "conv-12345678",
  });

  assert.equal(session.conversationId, "conv-12345678");
  assert.equal(session.project, "vitruvian-core");
  assert.equal(session.title, "Build receipts-report plugin");
  assert.equal(session.stepCount, 3);
  assert.equal(session.userPromptCount, 1);
  assert.equal(session.plannerTurnCount, 2);
  assert.equal(session.toolCallCount, 5);
  assert.equal(session.subagentCount, 1);
  assert.deepEqual(session.subagentRoles, ["CI Test Runner"]);
  assert.equal(session.errorCount, 1);
  assert.equal(session.truncatedStepCount, 2);
  assert.deepEqual(session.truncatedFieldCounts, {
    thinking: 1,
    content: 1,
    tool_calls: 1,
  });
  assert.ok(session.commits.includes("feat(receipts): add parser"));
  assert.ok(session.commits.includes("9f8e7d6"));
  assert.ok(session.prs.includes("feat(receipts): initial plugin"));
  assert.ok(session.prs.includes("#4120"));
  assert.ok(session.estimatedTokens > 0);
});

test("aggregateProjectReceipts groups sessions by project and merges external commits/PRs", () => {
  const s1 = parseTranscriptJsonl(SAMPLE_JSONL, {
    conversationId: "conv-1",
  });
  const s2 = parseTranscriptJsonl(
    JSON.stringify({
      step_index: 0,
      type: "USER_INPUT",
      created_at: "2026-10-23T19:00:00Z",
      content: "<USER_REQUEST>Quick check</USER_REQUEST>",
    }),
    {
      conversationId: "conv-2",
      project: "nexus-agent",
    },
  );

  const report = aggregateProjectReceipts([s1, s2], {
    "nexus-agent": { commits: ["a1b2c3d"], prs: ["#99"] },
  });

  assert.equal(report.totals.projects, 2);
  assert.equal(report.totals.conversations, 2);
  assert.equal(report.totals.userPrompts, 2);
  assert.equal(report.totals.toolCalls, 5);
  assert.equal(report.totals.subagents, 1);
  assert.equal(report.totals.commits, 3);
  assert.equal(report.totals.prs, 3);

  const nexus = report.projects.find((p) => p.project === "nexus-agent");
  assert.ok(nexus);
  assert.equal(nexus.commits, 1);
  assert.equal(nexus.prs, 1);
});

test("detectTokenHotspots flags truncated steps, error bursts, and tool loops", () => {
  const s1 = parseTranscriptJsonl(SAMPLE_JSONL, {
    conversationId: "conv-hotspot",
  });
  const hotspots = detectTokenHotspots([s1], {
    truncatedStepsWarn: 2,
    errorCountWarn: 1,
  });

  assert.equal(hotspots.length, 2);
  assert.ok(hotspots.some((h) => h.kind === "truncation"));
  assert.ok(hotspots.some((h) => h.kind === "error-burst"));
});

test("formatCsvReceipt and renderHtmlReceipt escape special characters", () => {
  const report = {
    totals: {
      conversations: 1,
      toolCalls: 4,
      commits: 1,
      prs: 1,
    },
    projects: [
      {
        project: 'proj,"special"',
        conversations: 1,
        userPrompts: 2,
        plannerTurns: 3,
        toolCalls: 4,
        subagents: 1,
        errors: 0,
        truncatedSteps: 1,
        estimatedTokens: 500,
        commits: 1,
        prs: 1,
      },
    ],
  };

  const csv = formatCsvReceipt(report);
  assert.match(csv, /^project,conversations,user_prompts/);
  assert.match(csv, /"proj,""special""",1,2,3,4,1,0,1,500,1,1/);

  const html = renderHtmlReceipt(report, [
    { severity: "warning", summary: "<script>bad</script>" },
  ]);
  assert.match(html, /<!DOCTYPE html>/);
  assert.ok(!html.includes("<script>bad</script>"));
  assert.match(html, /&lt;script&gt;bad&lt;\/script&gt;/);
});
