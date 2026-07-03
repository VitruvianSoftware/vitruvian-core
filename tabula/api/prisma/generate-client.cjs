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

/**
 * Hermetic Prisma client build step (single Bazel action):
 *   1. `prisma generate` — the engine-free `prisma-client` generator emits
 *      plain TypeScript into src/generated/prisma.
 *   2. Compile that TypeScript to CommonJS JS + .d.ts in place.
 *   3. Delete the .ts sources so downstream ts_project targets resolve the
 *      .d.ts for types (never re-compiling the generated code) while the .js
 *      ships in runfiles for runtime.
 *
 * Steps 2–3 exist because ts_project cannot declare per-file outputs for
 * directory (TreeArtifact) srcs — emit for generated trees is silently
 * dropped. Compiling inside the producing action keeps everything declared.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const GENERATED_DIR = path.join("src", "generated", "prisma");

// 1. prisma generate (cwd is the package dir; schema path is package-relative)
const prismaCli = require.resolve("prisma/build/index.js");
const res = spawnSync(
  process.execPath,
  [prismaCli, "generate", "--schema=prisma/schema.prisma"],
  { stdio: "inherit" },
);
if (res.status !== 0) {
  process.exit(res.status === null ? 1 : res.status);
}

// 2. compile generated TS -> JS + d.ts (CommonJS, matching the api tsconfig)
const ts = require("typescript");

function collectTs(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...collectTs(p));
    else if (entry.name.endsWith(".ts") && !entry.name.endsWith(".d.ts"))
      out.push(p);
  }
  return out;
}

const files = collectTs(GENERATED_DIR);
const program = ts.createProgram(files, {
  module: ts.ModuleKind.NodeNext,
  target: ts.ScriptTarget.ES2022,
  moduleResolution: ts.ModuleResolutionKind.NodeNext,
  declaration: true,
  esModuleInterop: true,
  resolveJsonModule: true,
  skipLibCheck: true,
});
const emitResult = program.emit();
const diags = ts.getPreEmitDiagnostics(program).concat(emitResult.diagnostics);
const errors = diags.filter((d) => d.category === ts.DiagnosticCategory.Error);
if (errors.length > 0) {
  console.error(
    ts.formatDiagnosticsWithColorAndContext(errors, {
      getCanonicalFileName: (f) => f,
      getCurrentDirectory: () => process.cwd(),
      getNewLine: () => "\n",
    }),
  );
  process.exit(1);
}

// 3. strip the .ts sources (keep .js + .d.ts)
for (const f of files) {
  fs.unlinkSync(f);
}
