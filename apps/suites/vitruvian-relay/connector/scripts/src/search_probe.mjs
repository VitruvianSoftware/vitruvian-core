// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// The installer's search check, run by the installed `node`: finds `rg`
// from desktop-commander's real entry point (argv[1]) exactly as
// desktop-commander 0.3.1 does (`import('@vscode/ripgrep')`'s `rgPath`,
// dist/utils/ripgrep-resolver.js), runs `rg --version`, and prints its path.
// Embedded in the installer and run by package_layout_test against the real
// package.
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const req = createRequire(process.argv[1]);
const { rgPath } = await import(
  pathToFileURL(req.resolve("@vscode/ripgrep")).href
);
const r = spawnSync(rgPath, ["--version"], { encoding: "utf8" });
if (r.status !== 0) {
  console.error(`${rgPath} --version failed: ${r.error ?? r.stderr}`);
  process.exit(1);
}
console.log(rgPath);
