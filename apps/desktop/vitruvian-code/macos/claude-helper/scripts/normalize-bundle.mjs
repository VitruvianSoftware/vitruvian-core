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

// esbuild labels each inlined module with a `// <path>` comment, relative to
// the folder it ran in (this package, under bazel-bin). How that path is
// spelled depends on the machine:
//   - in a macOS sandbox, esbuild follows the inputs' symlinks out to the
//     execroot: `../../…/execroot/_main/bazel-out/<config>/bin/<path>`;
//   - where the inputs are real files (Linux remote execution), it stays
//     relative to this package: `src/main.ts`, `../../../../../node_modules/…`.
// Spell every one from the workspace root instead, which is the same
// everywhere. A path comment in any other form fails the build rather than
// shipping bytes another machine would not reproduce.

import { readFileSync, writeFileSync } from "node:fs";
import { posix } from "node:path";

const PATH_COMMENT =
  /^\/\/ ((?:\.\.\/)*)((?:execroot\/[^/\s]+\/)?bazel-out\/[^/\s]+\/bin\/)?(\S+\.(?:[cm]?[jt]s|json))$/;

function normalizeBundle(source, packageDir) {
  const lines = source.split("\n");
  const out = lines.map((line, i) => {
    const m = PATH_COMMENT.exec(line);
    if (!m) return line;
    const [, ups, binPrefix, rest] = m;
    const fromRoot = binPrefix
      ? rest
      : posix.normalize(posix.join(packageDir, ups + rest));
    if (fromRoot.startsWith("../") || fromRoot.startsWith("/")) {
      throw new Error(
        `normalize-bundle: line ${i + 1} names a path outside the workspace: ${line}`,
      );
    }
    return `// ${fromRoot}`;
  });
  return out.join("\n");
}

function main() {
  const [inputPath, outputPath, packageDir] = process.argv.slice(2);
  if (!inputPath || !outputPath || !packageDir) {
    throw new Error(
      "Usage: normalize-bundle.mjs <esbuild-output.mjs> <normalized-output.mjs> <package dir>",
    );
  }
  const normalized = normalizeBundle(
    readFileSync(inputPath, "utf8"),
    packageDir,
  );
  if (/bazel-out|execroot/.test(normalized)) {
    throw new Error(
      "normalize-bundle: a bazel-out or execroot path is still in the bundle",
    );
  }
  if (/^\/\/ \.\.\//m.test(normalized)) {
    throw new Error("normalize-bundle: a `// ../` path is still in the bundle");
  }
  writeFileSync(outputPath, normalized, "utf8");
}

main();
