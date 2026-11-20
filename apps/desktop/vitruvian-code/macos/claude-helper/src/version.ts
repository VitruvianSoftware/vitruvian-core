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

import { execFile } from "node:child_process";

export const CLAUDE_VERSION_TIMEOUT_MS = 5_000;

const SEMVER_PATTERN =
  /\bv?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)\b/;

/** Extracts a semantic version string from `claude --version` output (T3 `ClaudeProvider.ts:696`). */
export function parseClaudeVersion(output: string): string | null {
  const match = SEMVER_PATTERN.exec(output);
  return match ? match[1] : null;
}

/** Executes `<claudePath> --version` with a timeout and returns the parsed version or `null` (T3 `ClaudeProvider.ts:649-716`). */
export async function detectClaudeVersion(
  claudePath: string,
  timeoutMs: number = CLAUDE_VERSION_TIMEOUT_MS,
): Promise<string | null> {
  if (claudePath.trim().length === 0) {
    return null;
  }

  return new Promise<string | null>((resolve) => {
    execFile(
      claudePath,
      ["--version"],
      {
        timeout: timeoutMs,
        killSignal: "SIGKILL",
        maxBuffer: 64 * 1024,
        windowsHide: true,
      },
      (error, stdout, stderr) => {
        if (error) {
          resolve(null);
          return;
        }
        resolve(parseClaudeVersion(stdout) ?? parseClaudeVersion(stderr));
      },
    );
  });
}
