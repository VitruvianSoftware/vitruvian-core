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

// esbuild labels each inlined module with a `// <path>` comment. Under Bazel
// that path is spelled from the sandbox: a run of `../`, then
// `execroot/_main/bazel-out/<host config>/bin/`, then the module's
// workspace-relative path. The run of `../` depends on how deep the sandbox
// is, and the host config (`darwin_arm64-fastbuild`, `darwin_x86_64-opt`, ...)
// on the machine and the build flags, so the same source would produce
// different bytes on another Mac. Keep only the part after `bin/`, which is the
// same everywhere.

import { readFileSync, writeFileSync } from "node:fs";

const MODULE_COMMENT =
  /^\/\/ (?:\.\.\/)*(?:execroot\/[^/\r\n]+\/)?bazel-out\/[^/\r\n]+\/bin\/(.+)$/gm;

// Only `// <path>` comment lines may change, one line for one line. Anything
// else (a match running past a line end, a changed code line) is a bug in the
// pattern, and the bundle must not ship: the staleness test regenerates through
// this same script, so it cannot catch it.
function normalizeBundle(source) {
  const normalized = source.replace(MODULE_COMMENT, "// $1");
  const before = source.split("\n");
  const after = normalized.split("\n");
  if (before.length !== after.length) {
    throw new Error("normalize-bundle: the line count changed");
  }
  for (let i = 0; i < before.length; i++) {
    if (before[i] !== after[i] && !before[i].startsWith("// ")) {
      throw new Error(`normalize-bundle: line ${i + 1} is not a path comment but changed`);
    }
  }
  return normalized;
}

function main() {
  const [inputPath, outputPath] = process.argv.slice(2);
  if (!inputPath || !outputPath) {
    throw new Error(
      "Usage: normalize-bundle.mjs <esbuild-output.mjs> <normalized-output.mjs>",
    );
  }
  const normalized = normalizeBundle(readFileSync(inputPath, "utf8"));
  if (/bazel-out|execroot/.test(normalized)) {
    throw new Error(
      "normalize-bundle: a bazel-out or execroot path is still in the bundle",
    );
  }
  writeFileSync(outputPath, normalized, "utf8");
}

main();
