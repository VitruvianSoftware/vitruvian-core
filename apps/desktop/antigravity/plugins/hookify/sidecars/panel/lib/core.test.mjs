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
  SUPPORTED_ACTIONS,
  SUPPORTED_OPERATORS,
  evaluateCondition,
  evaluatePreToolUse,
  evaluateRule,
  evaluateStop,
  extractFieldFromPayload,
  parseHookifyMarkdown,
  serializeHookifyMarkdown,
  summariseHookifyState,
} from "./core.mjs";

test("parseHookifyMarkdown parses YAML frontmatter, conditions, overwrite, and body", () => {
  const md = `---
name: block-rm-rf
enabled: true
event: bash
tool: run_command
action: block
conditions:
  - field: CommandLine
    operator: regex_match
    pattern: "rm\\\\s+-rf\\\\s+/"
  - field: CommandLine
    operator: not_contains
    pattern: "--dry-run"
---
Do not run destructive \`rm -rf /\` commands.
`;
  const rule = parseHookifyMarkdown(md, ".agents/hookify.block-rm-rf.md");
  assert.ok(rule);
  assert.equal(rule.name, "block-rm-rf");
  assert.equal(rule.enabled, true);
  assert.equal(rule.event, "bash");
  assert.equal(rule.tool, "run_command");
  assert.equal(rule.action, "block");
  assert.equal(rule.conditions.length, 2);
  assert.deepEqual(rule.conditions[0], {
    field: "CommandLine",
    operator: "regex_match",
    pattern: "rm\\s+-rf\\s+/",
  });
  assert.equal(rule.message, "Do not run destructive `rm -rf /` commands.");
});

test("parseHookifyMarkdown supports shorthand pattern and serializeHookifyMarkdown round-trips", () => {
  const md = `---
name: warn-console-log
enabled: false
event: file
action: warn
pattern: "console\\\\.log\\\\("
---
Avoid committing debug console.log calls.
`;
  const parsed = parseHookifyMarkdown(md);
  assert.equal(parsed.name, "warn-console-log");
  assert.equal(parsed.enabled, false);
  assert.equal(parsed.conditions.length, 1);
  assert.equal(parsed.conditions[0].field, "Content");

  const serialized = serializeHookifyMarkdown(parsed);
  const reparsed = parseHookifyMarkdown(serialized);
  assert.equal(reparsed.name, parsed.name);
  assert.equal(reparsed.enabled, parsed.enabled);
  assert.equal(reparsed.action, parsed.action);
  assert.deepEqual(reparsed.conditions, parsed.conditions);
  assert.equal(reparsed.message, parsed.message);
});

test("evaluateCondition supports all 6 operators", () => {
  assert.equal(SUPPORTED_OPERATORS.length, 6);
  assert.ok(SUPPORTED_ACTIONS.includes("overwrite"));

  const payload = {
    toolCall: {
      name: "run_command",
      args: {
        CommandLine: "git push --force origin main",
        Path: "/workspace/src/index.ts",
      },
    },
  };

  assert.equal(
    evaluateCondition(
      {
        field: "CommandLine",
        operator: "regex_match",
        pattern: "git\\s+push.*--force",
      },
      payload,
    ),
    true,
  );
  assert.equal(
    evaluateCondition(
      { field: "CommandLine", operator: "contains", pattern: "--force" },
      payload,
    ),
    true,
  );
  assert.equal(
    evaluateCondition(
      {
        field: "CommandLine",
        operator: "not_contains",
        pattern: "--force-with-lease",
      },
      payload,
    ),
    true,
  );
  assert.equal(
    evaluateCondition(
      { field: "Path", operator: "equals", pattern: "/workspace/src/index.ts" },
      payload,
    ),
    true,
  );
  assert.equal(
    evaluateCondition(
      { field: "CommandLine", operator: "starts_with", pattern: "git push" },
      payload,
    ),
    true,
  );
  assert.equal(
    evaluateCondition(
      { field: "Path", operator: "ends_with", pattern: ".ts" },
      payload,
    ),
    true,
  );
  assert.equal(extractFieldFromPayload(payload, "tool_name"), "run_command");
});

test("evaluatePreToolUse respects action precedence and rewrites arguments on overwrite", () => {
  const rules = [
    {
      name: "rewrite-npm-to-pnpm",
      enabled: true,
      event: "bash",
      action: "overwrite",
      conditions: [
        { field: "CommandLine", operator: "starts_with", pattern: "npm test" },
      ],
      overwrite: {
        field: "CommandLine",
        find: "^npm test",
        replace: "bazel test //...",
      },
      message: "Rewrote npm test to bazel test //...",
    },
    {
      name: "ask-on-test",
      enabled: true,
      event: "bash",
      action: "warn",
      conditions: [
        { field: "CommandLine", operator: "contains", pattern: "test" },
      ],
      message: "Confirm test run.",
    },
  ];

  const payload = {
    toolCall: {
      name: "run_command",
      args: { CommandLine: "npm test --watch" },
    },
  };

  const res = evaluatePreToolUse(rules, payload);
  assert.equal(res.decision, "ask");
  assert.equal(res.permissionDecision, "ask");
  assert.equal(res.matchedRules.length, 2);
  assert.deepEqual(res.updatedInput, {
    CommandLine: "bazel test //... --watch",
  });
  assert.equal(
    res.hookOutput.hookSpecificOutput.updatedInput.CommandLine,
    "bazel test //... --watch",
  );
});

test("evaluatePreToolUse blocks when a deny rule matches and ignores disabled rules", () => {
  const rules = [
    {
      name: "disabled-block",
      enabled: false,
      event: "bash",
      action: "block",
      pattern: ".*",
      message: "Should not fire",
    },
    {
      name: "deny-prod-drop",
      enabled: true,
      event: "bash",
      action: "deny",
      pattern: "DROP\\s+TABLE",
      message: "Prod table drops are forbidden.",
    },
  ];

  const res = evaluatePreToolUse(rules, {
    toolCall: {
      name: "run_command",
      args: { CommandLine: "psql -c 'DROP TABLE users;'" },
    },
  });
  assert.equal(res.decision, "deny");
  assert.equal(res.permissionDecision, "deny");
  assert.match(res.reason, /Prod table drops are forbidden/);
});

test("evaluateStop returns continue: false on blocking Stop rule and summariseHookifyState tallies metrics", () => {
  const rules = [
    {
      name: "require-worktree-hygiene",
      enabled: true,
      event: "Stop",
      action: "block",
      conditions: [
        {
          field: "reason",
          operator: "not_contains",
          pattern: "worktree hygiene",
        },
      ],
      message: "Include worktree hygiene status before stopping.",
    },
  ];

  const blocked = evaluateStop(rules, {
    hook_event_name: "Stop",
    reason: "All done!",
  });
  assert.equal(blocked.continue, false);
  assert.equal(blocked.hookOutput.continue, false);
  assert.match(blocked.stopReason, /Include worktree hygiene status/);

  const allowed = evaluateStop(rules, {
    hook_event_name: "Stop",
    reason: "All done! Verified worktree hygiene is clean.",
  });
  assert.equal(allowed.continue, true);
  assert.deepEqual(allowed.hookOutput, {});

  const summary = summariseHookifyState({
    rules,
    events: [
      { decision: "deny" },
      { decision: "ask" },
      { decision: "overwrite" },
    ],
  });
  assert.equal(summary.totalRules, 1);
  assert.equal(summary.activeRules, 1);
  assert.equal(summary.blockedEvents, 1);
  assert.equal(summary.warnEvents, 1);
  assert.equal(summary.rewriteEvents, 1);
});
