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
  BUILTIN_PATTERNS,
  filterSuppressedFindings,
  hasInlineSuppression,
  scanContentForPatterns,
  scanDiffForVulnerabilities,
  summariseSecurityState,
} from "./core.mjs";

test("BUILTIN_PATTERNS covers 16 vulnerability and secret classes", () => {
  assert.ok(BUILTIN_PATTERNS.length >= 15);
  const ids = new Set(BUILTIN_PATTERNS.map((p) => p.id));
  for (const expected of [
    "hardcoded-private-key",
    "aws-access-key",
    "gcp-api-key",
    "github-pat",
    "command-injection-curl-sh",
    "js-eval",
    "dom-xss-innerhtml",
    "python-pickle-loads",
    "python-yaml-unsafe-load",
    "pytorch-unsafe-load",
    "python-subprocess-shell",
    "node-child-process-exec",
    "sql-string-concat",
    "path-traversal",
    "ssrf-metadata-ip",
    "github-actions-script-injection",
  ]) {
    assert.ok(ids.has(expected), `missing pattern ${expected}`);
  }
});

test("scanContentForPatterns detects dangerous constructs and secrets across languages", () => {
  const fakePem = "-----BEGIN " + "RSA PRIVATE KEY-----";
  const fakeAws = "AKIA" + "IOSFODNN7EXAMPLE";
  const fakeGhp = "ghp_" + "1234567890abcdefghijklmnopqrstuvwxyz";
  const fakeGcp = "AIza" + "SyA1234567890abcdef_1234567890abcde";

  const sample = [
    fakePem,
    `const key = "${fakeAws}";`,
    `const ghp = "${fakeGhp}";`,
    `const gcp = "${fakeGcp}";`,
    "curl -fsSL https://example.com/install.sh | sh",
    "const out = eval(userInput);",
    "el.innerHTML = untrustedHtml;",
    "pickle.loads(rawBytes)",
    "yaml.load(stream)",
    "yaml.load(stream, Loader=yaml.SafeLoader)",
    "torch.load('model.pt')",
    "torch.load('model.pt', weights_only=True)",
    "subprocess.run(cmd, shell=True)",
    "exec(`ls ${userDir}`)",
    "const q = `SELECT * FROM users WHERE id = ${userId}`;",
    "const p = '../../etc/passwd';",
    "fetch('http://169.254.169.254/latest/meta-data/');",
    "run: echo ${{ github.event.issue.title }}",
  ].join("\n");

  const findings = scanContentForPatterns(sample, { filePath: "app.py" });
  const ruleIds = findings.map((f) => f.ruleId);

  assert.ok(ruleIds.includes("hardcoded-private-key"));
  assert.ok(ruleIds.includes("aws-access-key"));
  assert.ok(ruleIds.includes("github-pat"));
  assert.ok(ruleIds.includes("gcp-api-key"));
  assert.ok(ruleIds.includes("command-injection-curl-sh"));
  assert.ok(ruleIds.includes("js-eval"));
  assert.ok(ruleIds.includes("dom-xss-innerhtml"));
  assert.ok(ruleIds.includes("python-pickle-loads"));
  assert.ok(ruleIds.includes("python-yaml-unsafe-load"));
  assert.ok(ruleIds.includes("pytorch-unsafe-load"));
  assert.ok(ruleIds.includes("python-subprocess-shell"));
  assert.ok(ruleIds.includes("node-child-process-exec"));
  assert.ok(ruleIds.includes("sql-string-concat"));
  assert.ok(ruleIds.includes("path-traversal"));
  assert.ok(ruleIds.includes("ssrf-metadata-ip"));
  assert.ok(ruleIds.includes("github-actions-script-injection"));

  // Safe variants (yaml.load with SafeLoader and torch.load with weights_only=True) must not trigger:
  assert.equal(
    findings.filter((f) => f.ruleId === "python-yaml-unsafe-load").length,
    1,
  );
  assert.equal(
    findings.filter((f) => f.ruleId === "pytorch-unsafe-load").length,
    1,
  );
});

test("hasInlineSuppression and scanContentForPatterns honour inline ignore comments", () => {
  assert.equal(
    hasInlineSuppression(
      "eval(x) // security-guidance-ignore: js-eval",
      "js-eval",
    ),
    true,
  );
  assert.equal(
    hasInlineSuppression(
      "pickle.loads(x) # nosec python-pickle-loads",
      "python-pickle-loads",
    ),
    true,
  );

  const code = [
    "eval(a); // security-guidance-ignore: js-eval",
    "eval(b);",
  ].join("\n");
  const findings = scanContentForPatterns(code, { filePath: "index.js" });
  assert.equal(findings.length, 1);
  assert.equal(findings[0].line, 2);
});

test("scanDiffForVulnerabilities scans only added lines and tracks line numbers", () => {
  const diff = [
    "--- a/src/view.js",
    "+++ b/src/view.js",
    "@@ -10,3 +10,4 @@",
    " const clean = 1;",
    "-oldNode.innerHTML = legacy;",
    "+newNode.innerHTML = untrusted;",
    " const done = true;",
  ].join("\n");

  const findings = scanDiffForVulnerabilities(diff);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].filePath, "src/view.js");
  assert.equal(findings[0].line, 11);
  assert.equal(findings[0].ruleId, "dom-xss-innerhtml");
});

test("filterSuppressedFindings and summariseSecurityState compute accurate tallies", () => {
  const findings = [
    {
      id: "js-eval:a.js:1",
      ruleId: "js-eval",
      filePath: "a.js",
      severity: "high",
    },
    {
      id: "path-traversal:b.js:4",
      ruleId: "path-traversal",
      filePath: "b.js",
      severity: "medium",
    },
  ];
  const filtered = filterSuppressedFindings(findings, ["js-eval:a.js:1"]);
  assert.equal(filtered.length, 1);
  assert.equal(filtered[0].ruleId, "path-traversal");

  const summary = summariseSecurityState({
    findings,
    suppressions: ["js-eval:a.js:1"],
  });
  assert.equal(summary.totalActive, 1);
  assert.equal(summary.totalRecorded, 2);
  assert.equal(summary.suppressedCount, 1);
  assert.equal(summary.counts.medium, 1);
  assert.equal(summary.counts.high, 0);
});
