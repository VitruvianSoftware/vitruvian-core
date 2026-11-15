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

// Instruction-to-code drift tests for apps/antigravity/plugins/vitruvian-orchestrator:
// verifies tiers, initial/transition phases, shipped agents/, and MCP tool names
// match mcp/server.mjs and .agents/roster/.

import assert from "node:assert/strict";
import {
  existsSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { TOOLS, handleJsonRpcMessage } from "./mcp/server.mjs";
import { VALID_TIERS } from "./sidecars/panel/lib/orchestrator-core.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function findRepoRoot() {
  for (const base of [process.cwd(), HERE]) {
    let dir = resolve(base);
    for (let i = 0; i < 8; i += 1) {
      if (
        existsSync(join(dir, ".agents/roster/tiers.tsv")) &&
        existsSync(
          join(
            dir,
            "apps/antigravity/plugins/vitruvian-orchestrator/plugin.json",
          ),
        )
      ) {
        return dir;
      }
      const parent = dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  }
  return HERE;
}

const ROOT = findRepoRoot();
const PLUGIN_DIR = join(
  ROOT,
  "apps/antigravity/plugins/vitruvian-orchestrator",
);

function readPlugin(rel) {
  return readFileSync(join(PLUGIN_DIR, rel), "utf8");
}

function parseRosterTiers() {
  const raw = readFileSync(join(ROOT, ".agents/roster/tiers.tsv"), "utf8");
  const tiers = new Set();
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const cols = trimmed.split("\t");
    if (cols[0] === "tier") continue;
    if (cols[0]) tiers.add(cols[0]);
  }
  return [...tiers];
}

function parseRosterAgents() {
  const raw = readFileSync(join(ROOT, ".agents/roster/agents.tsv"), "utf8");
  const agents = [];
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const cols = trimmed.split("\t");
    if (cols[0] === "name") continue;
    if (cols[0])
      agents.push({ name: cols[0], tier: cols[1], description: cols[2] });
  }
  return agents;
}

function parseSkillRosterNames(skillText) {
  const names = [];
  let inTable = false;
  for (const line of skillText.split(/\r?\n/)) {
    if (line.startsWith("| Agent | Tier |")) {
      inTable = true;
      continue;
    }
    if (inTable) {
      if (!line.startsWith("|")) break;
      if (line.startsWith("|---")) continue;
      const cols = line.split("|").map((s) => s.trim());
      if (cols[1]) names.push(cols[1]);
    }
  }
  return names;
}

function parseSkillTableTiers(skillText) {
  const tiers = new Set();
  let inTable = false;
  for (const line of skillText.split(/\r?\n/)) {
    if (line.startsWith("| Agent | Tier |")) {
      inTable = true;
      continue;
    }
    if (inTable) {
      if (!line.startsWith("|")) break;
      if (line.startsWith("|---")) continue;
      const cols = line.split("|").map((s) => s.trim());
      if (cols[2]) tiers.add(cols[2]);
    }
  }
  return [...tiers];
}

test("progress tool schema and SKILL.md tiers match .agents/roster/tiers.tsv and keep legacy aliases", () => {
  const progressTool = TOOLS.find((t) => t.name === "progress");
  assert.ok(progressTool, "progress tool must exist");
  const codeTierEnum =
    progressTool.inputSchema.properties.tasks.items.properties.tier.enum;
  assert.deepEqual(new Set(codeTierEnum), VALID_TIERS);

  const rosterTiers = parseRosterTiers();
  for (const tier of rosterTiers) {
    assert.ok(
      codeTierEnum.includes(tier),
      `mcp/server.mjs progress tier enum (${JSON.stringify(codeTierEnum)}) must include roster tier "${tier}"`,
    );
  }
  for (const legacy of ["core", "fast"]) {
    assert.ok(
      codeTierEnum.includes(legacy),
      `mcp/server.mjs progress tier enum must retain legacy tier "${legacy}"`,
    );
  }

  const skill = readPlugin("skills/orchestrate/SKILL.md");
  const skillTableTiers = parseSkillTableTiers(skill);
  assert.ok(
    skillTableTiers.length > 0,
    "expected roster table tiers in SKILL.md",
  );
  for (const tier of skillTableTiers) {
    assert.ok(
      codeTierEnum.includes(tier),
      `SKILL.md roster table tier "${tier}" missing from progress tier enum ${JSON.stringify(codeTierEnum)}`,
    );
  }

  const tierBullet = skill.match(/\*\*Tier\*\*:[^\n]+\(([^)]+)\)/);
  assert.ok(tierBullet, "expected **Tier** bullet in SKILL.md");
  const tierClauses = tierBullet[1].split(
    /\bremain accepted\b|\baccepted by\b/,
  )[0];
  const docTiers = [...tierClauses.matchAll(/`([a-z0-9_-]+)`/gi)].map(
    (m) => m[1],
  );
  assert.ok(
    docTiers.length > 0,
    "expected backticked tier names in **Tier** bullet",
  );
  for (const tier of docTiers) {
    assert.ok(
      VALID_TIERS.has(tier) && codeTierEnum.includes(tier),
      `SKILL.md **Tier** doc mentions "${tier}" which is not in VALID_TIERS ${JSON.stringify([...VALID_TIERS])}`,
    );
  }
  for (const tier of rosterTiers) {
    assert.ok(
      docTiers.includes(tier),
      `SKILL.md **Tier** bullet (${docTiers.join(", ")}) omits roster tier "${tier}"`,
    );
  }
});

test("progress tool rejects unknown tier instead of silently falling back to core", () => {
  const flowsDir = mkdtempSync(join(tmpdir(), "orch-drift-"));
  try {
    const res = handleJsonRpcMessage(
      {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "progress",
          arguments: {
            title: "Drift check",
            phase: "plan",
            tasks: [
              { title: "Invalid tier task", specialist: "wren", tier: "bogus" },
            ],
          },
          _meta: {
            "antigravity.google/root_conversation_id": "conv-drift-1",
            "antigravity.google/conversation_id": "conv-drift-1",
          },
        },
      },
      { flowsDir, now: () => 1_700_000_000_000 },
    );
    assert.ok(
      res.error && res.error.code === -32602,
      `expected JSON-RPC -32602 error on unknown tier "bogus", got: ${JSON.stringify(res)}`,
    );
    assert.match(res.error.message, /tier/i);
  } finally {
    rmSync(flowsDir, { recursive: true, force: true });
  }
});

test("initial progress phase in SKILL.md matches rules/AGENTS.md and progress phase enum", () => {
  const progressTool = TOOLS.find((t) => t.name === "progress");
  const codePhases = progressTool.inputSchema.properties.phase.enum;
  assert.equal(codePhases[0], "plan");

  const skill = readPlugin("skills/orchestrate/SKILL.md");
  const rules = readPlugin("rules/AGENTS.md");

  const skillPlanMatch = skill.match(
    /right after you show the plan:\s*`title`,\s*`phase:\s*"([^"]+)"`/,
  );
  assert.ok(
    skillPlanMatch,
    "expected initial progress phase instruction in SKILL.md section 7",
  );
  assert.ok(
    codePhases.includes(skillPlanMatch[1]),
    `SKILL.md initial phase "${skillPlanMatch[1]}" not in code phases ${JSON.stringify(codePhases)}`,
  );

  const rulesPlanMatch = rules.match(
    /Right after creating or revising the numbered task plan[^\n]*`phase:\s*"([^"]+)"/,
  );
  assert.ok(
    rulesPlanMatch,
    "expected initial progress phase instruction in rules/AGENTS.md",
  );
  assert.equal(
    skillPlanMatch[1],
    rulesPlanMatch[1],
    `SKILL.md section 7 starts with phase "${skillPlanMatch[1]}" while rules/AGENTS.md says "${rulesPlanMatch[1]}"`,
  );
  assert.equal(skillPlanMatch[1], "plan");

  const transitionMatch = rules.match(
    /On each phase transition \(`phase:\s*([^`]+)`\)/,
  );
  assert.ok(
    transitionMatch,
    "expected phase transition list in rules/AGENTS.md",
  );
  for (const p of [...transitionMatch[1].matchAll(/"([a-z]+)"/g)].map(
    (m) => m[1],
  )) {
    assert.ok(
      codePhases.includes(p),
      `rules/AGENTS.md transition phase "${p}" missing from code`,
    );
  }
});

test("plugin ships agents/*.md matching the SKILL.md roster and .agents/roster/agents.tsv", () => {
  const skill = readPlugin("skills/orchestrate/SKILL.md");
  const skillNames = parseSkillRosterNames(skill);
  const rosterNames = parseRosterAgents().map((a) => a.name);

  assert.deepEqual(
    skillNames,
    rosterNames,
    "SKILL.md roster table must match .agents/roster/agents.tsv",
  );

  const agentsDir = join(PLUGIN_DIR, "agents");
  assert.ok(
    existsSync(agentsDir),
    "apps/antigravity/plugins/vitruvian-orchestrator/agents/ directory must exist",
  );
  const files = readdirSync(agentsDir)
    .filter((f) => f.endsWith(".md"))
    .map((f) => f.replace(/\.md$/, ""))
    .sort();
  assert.deepEqual(
    files,
    [...rosterNames].sort(),
    `shipped agents/*.md (${files.join(", ")}) must match roster (${rosterNames.join(", ")})`,
  );

  for (const name of rosterNames) {
    const body = readFileSync(join(agentsDir, `${name}.md`), "utf8");
    assert.match(body, new RegExp(`^---[\\s\\S]*?\\bname:\\s*${name}\\b`, "m"));
  }
});

test("tool names cited in SKILL.md and rules/AGENTS.md exist in MCP server TOOLS", () => {
  const toolNames = new Set(TOOLS.map((t) => t.name));
  const skill = readPlugin("skills/orchestrate/SKILL.md");
  const rules = readPlugin("rules/AGENTS.md");

  for (const m of rules.matchAll(/`([a-z_]+)`\s+MCP\s+tool/g)) {
    assert.ok(
      toolNames.has(m[1]),
      `rules/AGENTS.md tool "${m[1]}" missing from TOOLS`,
    );
  }
  for (const m of skill.matchAll(/`([a-z_]+)`\s+tool/g)) {
    // Exclude Antigravity native subagent tool names like invoke_subagent.
    if (m[1] === "invoke_subagent") continue;
    assert.ok(
      toolNames.has(m[1]),
      `SKILL.md tool "${m[1]}" missing from TOOLS`,
    );
  }
});
