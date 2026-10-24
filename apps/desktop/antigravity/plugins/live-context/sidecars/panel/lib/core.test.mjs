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
  buildEphemeralContextPayload,
  checkResponseContract,
  evaluateStopShape,
  formatLiveGitSummary,
} from "./core.mjs";

test("formatLiveGitSummary formats git branch, dirty count, open PRs, and merged PRs", () => {
  const text = formatLiveGitSummary(
    {
      branch: "feat/live-context",
      headSha: "abc1234",
      dirtyCount: 2,
      dirtyFiles: ["README.md", "plugin.json"],
    },
    {
      repo: "VitruvianSoftware/vitruvian-core",
      openPrs: [
        { number: 401, title: "feat: add live-context", isDraft: true },
      ],
      mergedPrs: [
        {
          number: 400,
          title: "fix: openui parser",
          mergedAt: "2026-10-23T12:00:00Z",
        },
      ],
      openIssues: 7,
    },
  );

  assert.match(
    text,
    /LIVE GIT WORKSPACE: branch feat\/live-context \(abc1234\)/,
  );
  assert.match(text, /2 uncommitted files: README\.md, plugin\.json/);
  assert.match(text, /#401 \[draft\] feat: add live-context/);
  assert.match(
    text,
    /#400 fix: openui parser  \(merged 2026-10-23T12:00:00Z\)/,
  );
  assert.match(text, /OPEN issues: 7/);
});

test("buildEphemeralContextPayload emits injectSteps with ephemeralMessage", () => {
  const payload = buildEphemeralContextPayload({
    git: { branch: "main", headSha: "1112223", dirtyCount: 0 },
    github: { openPrs: [], mergedPrs: [], openIssues: 0 },
    settings: {
      injectGit: true,
      injectGitHub: true,
      injectContract: true,
    },
  });

  assert.ok(Array.isArray(payload.injectSteps));
  assert.equal(payload.injectSteps.length, 1);
  assert.match(
    payload.injectSteps[0].ephemeralMessage,
    /LIVE GIT WORKSPACE: branch main/,
  );
  assert.match(payload.injectSteps[0].ephemeralMessage, /RESPONSE CONTRACT/);

  assert.deepEqual(
    buildEphemeralContextPayload({
      settings: {
        injectGit: false,
        injectGitHub: false,
        injectContract: false,
      },
    }),
    {},
  );
});

test("checkResponseContract exempts short replies and flags trailing filler lines", () => {
  const shortReply = checkResponseContract("Yes, the build passed.");
  assert.equal(shortReply.exempt, true);
  assert.equal(shortReply.valid, true);

  const fillerReply = checkResponseContract(
    `${"Detailed investigation and verification results for the cluster deployment. ".repeat(6)}\n\nNothing needed from you.`,
  );
  assert.equal(fillerReply.exempt, false);
  assert.equal(fillerReply.hasFiller, true);
  assert.equal(fillerReply.valid, false);

  // Quoting the forbidden phrase inside backticks or quotes is allowed.
  const quotedPhraseReply = checkResponseContract(
    `${"Verified that the Stop hook blocks replies ending with filler phrases. ".repeat(6)}\nWe specifically tested \`Nothing needed from you.\` in the unit suite.`,
  );
  assert.equal(quotedPhraseReply.hasFiller, false);
  assert.equal(quotedPhraseReply.valid, true);
});

test("evaluateStopShape bounces once in enforce mode and allows on second pass or log mode", () => {
  const badMessage = `${"Substantive explanation of the architecture and test coverage across all modules. ".repeat(5)}\n\nNo action needed.`;

  const logModeResult = evaluateStopShape(
    {
      conversationId: "conv-log-1234",
      executionNum: 1,
      terminationReason: "NO_TOOL_CALL",
      lastAssistantMessage: badMessage,
    },
    { mode: "log" },
  );
  assert.equal(logModeResult.bounced, false);
  assert.deepEqual(logModeResult.output, { decision: "allow" });
  assert.equal(logModeResult.logRecord?.verdict, "block");

  const enforceFirstPass = evaluateStopShape(
    {
      conversationId: "conv-enf-1234",
      executionNum: 1,
      terminationReason: "NO_TOOL_CALL",
      lastAssistantMessage: badMessage,
    },
    { mode: "enforce" },
  );
  assert.equal(enforceFirstPass.bounced, true);
  assert.equal(enforceFirstPass.output.decision, "continue");
  assert.match(enforceFirstPass.output.reason, /RESPONSE CONTRACT:/);

  // Second pass (executionNum > 1) never loops
  const enforceSecondPass = evaluateStopShape(
    {
      conversationId: "conv-enf-1234",
      executionNum: 2,
      terminationReason: "NO_TOOL_CALL",
      lastAssistantMessage: badMessage,
    },
    { mode: "enforce" },
  );
  assert.equal(enforceSecondPass.bounced, false);
  assert.deepEqual(enforceSecondPass.output, { decision: "allow" });
});
