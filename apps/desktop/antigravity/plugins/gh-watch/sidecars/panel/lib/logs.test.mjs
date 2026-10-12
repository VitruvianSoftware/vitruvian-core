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

import { cleanLogLine, extractFailureExcerpt, parseCheckUrl } from "./logs.mjs";

test("parseCheckUrl parses GitHub Actions run and job URLs", () => {
  assert.deepEqual(
    parseCheckUrl(
      "https://github.com/VitruvianSoftware/vitruvian-core/actions/runs/12345/job/67890",
    ),
    {
      owner: "VitruvianSoftware",
      name: "vitruvian-core",
      repo: "VitruvianSoftware/vitruvian-core",
      runId: 12345,
      jobId: 67890,
    },
  );

  assert.deepEqual(
    parseCheckUrl(
      "https://github.com/VitruvianSoftware/vitruvian-core/actions/runs/98765",
    ),
    {
      owner: "VitruvianSoftware",
      name: "vitruvian-core",
      repo: "VitruvianSoftware/vitruvian-core",
      runId: 98765,
      jobId: null,
    },
  );

  assert.equal(parseCheckUrl("https://example.com/other"), null);
  assert.equal(parseCheckUrl(null), null);
});

test("cleanLogLine strips tabs, timestamps, and ANSI escape codes", () => {
  const line =
    "build-job\tRun build\t2026-10-12T12:00:00.0000000Z \x1b[31;1mError: build failed\x1b[0m";
  assert.equal(cleanLogLine(line), "Error: build failed");
});

test("extractFailureExcerpt highlights error section within maxLines", () => {
  const lines = [
    "job\tstep\t2026-10-12T12:00:00Z Setting up runner",
    "job\tstep\t2026-10-12T12:00:01Z Running compilation",
    "job\tstep\t2026-10-12T12:00:02Z Compiling src/index.ts",
    "job\tstep\t2026-10-12T12:00:03Z ##[error]src/index.ts(10,5): error TS2322: Type 'number' is not assignable to type 'string'",
    "job\tstep\t2026-10-12T12:00:04Z ##[error]Process completed with exit code 1.",
    "job\tstep\t2026-10-12T12:00:05Z Post job cleanup",
    "job\tstep\t2026-10-12T12:00:06Z Complete job",
  ];

  const excerpt = extractFailureExcerpt(lines.join("\n"), 10);
  assert.match(excerpt, /##\[error\]src\/index\.ts/);
  assert.match(excerpt, /Process completed with exit code 1/);
});

test("extractFailureExcerpt falls back cleanly when no error marker exists", () => {
  const lines = ["Line 1", "Line 2", "Line 3", "Line 4"];
  const excerpt = extractFailureExcerpt(lines.join("\n"), 2);
  assert.equal(excerpt, "Line 3\nLine 4");
});
