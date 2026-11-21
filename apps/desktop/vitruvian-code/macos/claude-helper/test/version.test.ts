// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

import { detectClaudeVersion, parseClaudeVersion } from "../src/version.js";

describe("version detection", () => {
  const tempDirs: string[] = [];

  function makeTempDir(): string {
    const dir = mkdtempSync(path.join(os.tmpdir(), "claude-version-test-"));
    tempDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    while (tempDirs.length > 0) {
      rmSync(tempDirs.pop()!, { recursive: true, force: true });
    }
  });

  test("parseClaudeVersion extracts semver strings and rejects invalid output", () => {
    expect(parseClaudeVersion("2.1.45 (Claude Code)\n")).toBe("2.1.45");
    expect(parseClaudeVersion("v2.1.45-beta.1")).toBe("2.1.45-beta.1");
    expect(parseClaudeVersion("2.1.45+build.42")).toBe("2.1.45+build.42");
    expect(
      parseClaudeVersion("Warning: experimental flag\nclaude 2.3.0-rc.2 (cli)"),
    ).toBe("2.3.0-rc.2");

    expect(parseClaudeVersion("")).toBeNull();
    expect(parseClaudeVersion("   \n")).toBeNull();
    expect(parseClaudeVersion("claude unknown build")).toBeNull();
  });

  test("detectClaudeVersion parses output from an executable script", async () => {
    const dir = makeTempDir();
    const script = path.join(dir, "claude-ok.sh");
    writeFileSync(script, "#!/bin/sh\necho '2.1.45 (Claude Code)'\n", "utf8");
    chmodSync(script, 0o755);

    await expect(detectClaudeVersion(script)).resolves.toBe("2.1.45");
  });

  test("detectClaudeVersion returns null on missing binary, non-zero exit, bad output, or timeout", async () => {
    const dir = makeTempDir();

    const failScript = path.join(dir, "claude-fail.sh");
    writeFileSync(
      failScript,
      "#!/bin/sh\necho '2.1.45 (Claude Code)'\nexit 1\n",
      "utf8",
    );
    chmodSync(failScript, 0o755);

    const garbageScript = path.join(dir, "claude-garbage.sh");
    writeFileSync(garbageScript, "#!/bin/sh\necho 'not a version'\n", "utf8");
    chmodSync(garbageScript, 0o755);

    const slowScript = path.join(dir, "claude-slow.sh");
    writeFileSync(slowScript, "#!/bin/sh\nsleep 2\necho '2.1.45'\n", "utf8");
    chmodSync(slowScript, 0o755);

    await expect(detectClaudeVersion("")).resolves.toBeNull();
    await expect(
      detectClaudeVersion(path.join(dir, "does-not-exist")),
    ).resolves.toBeNull();
    await expect(detectClaudeVersion(failScript)).resolves.toBeNull();
    await expect(detectClaudeVersion(garbageScript)).resolves.toBeNull();

    const started = Date.now();
    await expect(detectClaudeVersion(slowScript, 75)).resolves.toBeNull();
    expect(Date.now() - started).toBeLessThan(1_500);
  });
});
