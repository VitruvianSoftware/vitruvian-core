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

// Instruction-to-code drift tests for apps/claude-code/plugins/vitruvian-orchestrator:
// verifies tiers, phases, rejection of unknown tiers, shipped agents/, and external
// driver prerequisite documentation match hooks/register.tsx, types/index.d.ts, and .agents/roster/.

import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  applyAgentModels,
  parseTeam,
  planTeamSync,
} from "./hooks/lib/orchestrator-core.mjs";

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
            "apps/claude-code/plugins/vitruvian-orchestrator/README.md",
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
  "apps/claude-code/plugins/vitruvian-orchestrator",
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

function parseGenericRoles() {
  const raw = readFileSync(
    join(ROOT, ".agents/roster/generic/roles.tsv"),
    "utf8",
  );
  const roles = [];
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const cols = trimmed.split("\t");
    if (cols[0] === "role") continue;
    if (cols[0])
      roles.push({
        role: cols[0],
        tier: cols[1],
        description: cols[2],
      });
  }
  return roles;
}

function parseSkillRoleNames(skillText) {
  const names = [];
  let inTable = false;
  for (const line of skillText.split(/\r?\n/)) {
    if (line.startsWith("| Role | Tier |")) {
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

function parseStringLiterals(block) {
  return [...block.matchAll(/"([^"]+)"/g)].map((m) => m[1]);
}

function parseCodeTiersAndPhases() {
  const typesDts = readPlugin("types/index.d.ts");
  const registerTsx = readPlugin("hooks/register.tsx");

  const typeTierMatch = typesDts.match(/export type Tier\s*=\s*([^;]+);/);
  const typePhaseMatch = typesDts.match(/export type Phase\s*=\s*([^;]+);/);
  const regTiersMatch = registerTsx.match(
    /const TIERS:\s*readonly Tier\[\]\s*=\s*\[([^\]]+)\]/,
  );
  const regPhasesMatch = registerTsx.match(
    /const PHASES:\s*readonly Phase\[\]\s*=\s*\[([^\]]+)\]/,
  );
  assert.ok(typeTierMatch && regTiersMatch, "Tier definitions must exist");
  assert.ok(typePhaseMatch && regPhasesMatch, "Phase definitions must exist");

  return {
    typeTiers: parseStringLiterals(typeTierMatch[1]),
    typePhases: parseStringLiterals(typePhaseMatch[1]),
    regTiers: parseStringLiterals(regTiersMatch[1]),
    regPhases: parseStringLiterals(regPhasesMatch[1]),
    registerTsx,
  };
}

test("register.tsx, types/index.d.ts, and SKILL.md tiers match .agents/roster/tiers.tsv", () => {
  const { typeTiers, regTiers, registerTsx } = parseCodeTiersAndPhases();
  assert.deepEqual(
    typeTiers,
    regTiers,
    "types/index.d.ts Tier must match register.tsx TIERS",
  );

  const rosterTiers = parseRosterTiers();
  for (const tier of rosterTiers) {
    assert.ok(
      regTiers.includes(tier),
      `hooks/register.tsx TIERS (${JSON.stringify(regTiers)}) must include roster tier "${tier}"`,
    );
  }
  for (const legacy of ["core", "fast"]) {
    assert.ok(
      regTiers.includes(legacy),
      `hooks/register.tsx TIERS must retain legacy tier "${legacy}"`,
    );
  }

  // TIER_COLOR must define a swatch for every Tier.
  const tierColorMatch = registerTsx.match(
    /const TIER_COLOR:\s*Record<string,\s*string>\s*=\s*\{([^}]+)\}/,
  );
  assert.ok(tierColorMatch, "TIER_COLOR map must exist in register.tsx");
  for (const tier of regTiers) {
    assert.match(
      tierColorMatch[1],
      new RegExp(`\\b${tier}\\s*:`),
      `TIER_COLOR missing entry for tier "${tier}"`,
    );
  }

  // Must not silently fall back unknown/missing tiers to "core".
  assert.doesNotMatch(
    registerTsx,
    /\?\s*\(rawTier as Tier\)\s*:\s*"core"/,
    'cleanTasks must not silently fall back unknown tiers to "core"',
  );

  // SKILL.md **Tier** bullet matches TIERS.
  const skill = readPlugin("skills/orchestrate/SKILL.md");
  const tierBullet = skill.match(/\*\*Tier\*\*:[^\n]+\(([^)]+)\)/);
  assert.ok(tierBullet, "expected **Tier** bullet in SKILL.md");
  const tierClauses = tierBullet[1].split(
    /\bremain accepted\b|\baccepted by\b/,
  )[0];
  const docTiers = [...tierClauses.matchAll(/`([a-z0-9_-]+)`/gi)].map(
    (m) => m[1],
  );
  assert.ok(docTiers.length > 0);
  for (const tier of docTiers) {
    assert.ok(
      regTiers.includes(tier),
      `SKILL.md **Tier** doc mentions "${tier}" which is not in register.tsx TIERS`,
    );
  }
  for (const tier of rosterTiers) {
    assert.ok(
      docTiers.includes(tier),
      `SKILL.md **Tier** bullet (${docTiers.join(", ")}) omits roster tier "${tier}"`,
    );
  }
});

test('SKILL.md section 7 starts with phase: "plan" matching PHASES[0]', () => {
  const { typePhases, regPhases } = parseCodeTiersAndPhases();
  assert.deepEqual(typePhases, regPhases);
  assert.equal(regPhases[0], "plan");

  const skill = readPlugin("skills/orchestrate/SKILL.md");
  const skillPlanMatch = skill.match(
    /right after you show the plan:\s*`title`,\s*`phase:\s*"([^"]+)"`/,
  );
  assert.ok(
    skillPlanMatch,
    "expected initial progress phase instruction in SKILL.md section 7",
  );
  assert.ok(
    regPhases.includes(skillPlanMatch[1]),
    `SKILL.md initial phase "${skillPlanMatch[1]}" not in PHASES`,
  );
  assert.equal(
    skillPlanMatch[1],
    "plan",
    `SKILL.md section 7 must start with phase: "plan", got "${skillPlanMatch[1]}"`,
  );
});

test("plugin ships role-named agents/*.md matching SKILL.md role table and documents agy-delegate requirement", () => {
  const skill = readPlugin("skills/orchestrate/SKILL.md");
  const skillRoles = parseSkillRoleNames(skill);
  const rosterRoles = parseGenericRoles().map((r) => r.role);

  assert.deepEqual(
    skillRoles,
    rosterRoles,
    "SKILL.md role table must match .agents/roster/generic/roles.tsv",
  );

  const agentsDir = join(PLUGIN_DIR, "agents");
  assert.ok(
    existsSync(agentsDir),
    "apps/claude-code/plugins/vitruvian-orchestrator/agents/ directory must exist",
  );
  const files = readdirSync(agentsDir)
    .filter((f) => f.endsWith(".md"))
    .map((f) => f.replace(/\.md$/, ""))
    .sort();
  assert.deepEqual(
    files,
    [...rosterRoles].sort(),
    `shipped agents/*.md (${files.join(", ")}) must match generic roles (${rosterRoles.join(", ")})`,
  );

  for (const role of rosterRoles) {
    const body = readFileSync(join(agentsDir, `${role}.md`), "utf8");
    assert.match(body, new RegExp(`^---[\\s\\S]*?\\bname:\\s*${role}\\b`, "m"));
  }

  // Must note external CLI requirement (`agy-delegate`) for standalone use.
  assert.match(skill, /agy-delegate[\s\S]{0,120}(PATH|outside)/i);
  const readme = readPlugin("README.md");
  assert.match(readme, /agents\/\*\.md/);
});

test("team_setup sync against the real repository team.json and 30 agent files changes nothing", () => {
  const teamText = readFileSync(join(ROOT, ".agents/team.json"), "utf8");
  const parsed = parseTeam(teamText);
  assert.equal(parsed.errors.length, 0);
  assert.ok(parsed.team);

  const targets = planTeamSync(parsed.team);
  assert.equal(targets.length, 30);

  for (const target of targets) {
    assert.equal(target.conflict, false, `${target.path} unexpected conflict`);
    const filePath = join(ROOT, target.path);
    const text = readFileSync(filePath, "utf8");
    const applied = applyAgentModels(text, target.harness, {
      model: target.model,
      effort: target.effort,
    });
    assert.equal(applied.changed, false, `${target.path} changed`);
    assert.equal(applied.reason, "generated", `${target.path} reason`);
    assert.equal(applied.text, text, `${target.path} text`);
  }
});
