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

// Instruction-to-code drift tests for apps/antigravity/plugins/savvy-fleet:
// checks documented HTTP routes against sidecars/panel/main.mjs and ensures
// savvy-flow docs forbid low-effort models and explain specialist availability.

import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));

function findPluginDir() {
  for (const base of [process.cwd(), HERE]) {
    let dir = resolve(base);
    for (let i = 0; i < 8; i += 1) {
      const candidate = join(dir, "apps/antigravity/plugins/savvy-fleet");
      if (existsSync(join(candidate, "sidecars/panel/main.mjs"))) {
        return candidate;
      }
      if (existsSync(join(dir, "sidecars/panel/main.mjs"))) {
        return dir;
      }
      const parent = dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  }
  return HERE;
}

const PLUGIN_DIR = findPluginDir();

function readPlugin(rel) {
  return readFileSync(join(PLUGIN_DIR, rel), "utf8");
}

function registeredApiRoutes(mainJs) {
  return new Set(
    [...mainJs.matchAll(/app\.api\(\s*["'](\/api\/[^"']+)["']/g)].map(
      (m) => m[1],
    ),
  );
}

test("every /api/* route documented in SKILL.md and README.md exists in sidecars/panel/main.mjs", () => {
  const mainJs = readPlugin("sidecars/panel/main.mjs");
  const codeRoutes = registeredApiRoutes(mainJs);
  assert.ok(codeRoutes.size > 0, "expected /api/* routes in main.mjs");

  for (const docPath of [
    "skills/savvy-fleet/SKILL.md",
    "skills/savvy-flow/SKILL.md",
    "rules/AGENTS.md",
  ]) {
    const doc = readPlugin(docPath);
    const mentioned = [...doc.matchAll(/`(\/api\/[a-zA-Z0-9_-]+)`/g)].map(
      (m) => m[1],
    );
    for (const route of mentioned) {
      assert.ok(
        codeRoutes.has(route),
        `${docPath} documents route ${route} which does not exist in sidecars/panel/main.mjs (${[...codeRoutes].join(", ")})`,
      );
    }
  }
});

test("savvy-flow SKILL.md forbids low-effort models and explains specialist availability fallback", () => {
  const flowSkill = readPlugin("skills/savvy-flow/SKILL.md");
  const agentsRules = readPlugin("rules/AGENTS.md");

  assert.doesNotMatch(
    flowSkill,
    /flash\s*\/\s*low|\bflash-lo\b|\bflash_lite\b/i,
    "savvy-flow/SKILL.md must not recommend forbidden low-effort models",
  );

  // Must state that named specialists come from vitruvian-orchestrator / .agents/agents
  // with built-in fallback when outside the repo.
  assert.match(flowSkill, /vitruvian-orchestrator|\.agents\/agents/);
  assert.match(
    flowSkill,
    /\bself\b[\s\S]{0,40}\bresearch\b|\bresearch\b[\s\S]{0,40}\bself\b/,
  );
  assert.match(
    agentsRules,
    /vitruvian-orchestrator|\.agents\/agents|fallback/i,
  );
});
