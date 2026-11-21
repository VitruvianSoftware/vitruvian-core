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

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";

import {
  bareAgentName,
  parseFrontmatter,
  PLUGIN_AGENT_PREFIX,
  pluginAgentDefinitions,
  pluginSkillDefinitions,
  registerPluginAgentsAndSkills,
} from "./register.mjs";

const PLUGIN_DIR = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);

// A stand-in for OpenCode 2.3's ctx.agent / ctx.skill, shaped like the real
// editors (checked against opencode 2.3.2): the agent editor has no `add`, and
// `update(id, fn)` creates a missing agent and hands `fn` a draft to change.
function fakeCtx({ agents = [], skills = [] } = {}) {
  const agentMap = new Map(agents.map((a) => [a.id, { ...a }]));
  const skillMap = new Map(skills.map((s) => [s.id, { ...s }]));
  const agentEditor = {
    list: () => [...agentMap.values()],
    get: (id) => agentMap.get(id),
    default: () => "build",
    update: (id, fn) => {
      const draft = agentMap.get(id) ?? { id, name: id, mode: "primary" };
      fn(draft);
      agentMap.set(id, draft);
    },
    remove: (id) => agentMap.delete(id),
  };
  const skillEditor = {
    list: () => [...skillMap.values()],
    get: (id) => skillMap.get(id),
    add: (skill) => {
      if (skillMap.has(skill.id)) throw new Error(`duplicate ${skill.id}`);
      skillMap.set(skill.id, { ...skill });
    },
    update: () => {},
    remove: (id) => skillMap.delete(id),
  };
  return {
    agents: agentMap,
    skills: skillMap,
    ctx: {
      agent: { transform: async (fn) => fn(agentEditor) },
      skill: { transform: async (fn) => fn(skillEditor) },
    },
  };
}

describe("parseFrontmatter", () => {
  it("reads key: value lines and the body", () => {
    const parsed = parseFrontmatter(
      '---\ndescription: "Does: things"\nmode: subagent\n---\n\nBody line\n',
    );
    assert.deepEqual(parsed?.data, {
      description: "Does: things",
      mode: "subagent",
    });
    assert.equal(parsed?.body, "Body line\n");
  });

  it("handles CRLF files", () => {
    const parsed = parseFrontmatter("---\r\nname: x\r\n---\r\nhi\r\n");
    assert.equal(parsed?.data.name, "x");
    assert.equal(parsed?.body, "hi\r\n");
  });

  it("returns null without frontmatter", () => {
    assert.equal(parseFrontmatter("no frontmatter"), null);
    assert.equal(parseFrontmatter("---\nunterminated: yes\n"), null);
  });
});

describe("bareAgentName", () => {
  it("drops the plugin prefix and nothing else", () => {
    assert.equal(bareAgentName(`${PLUGIN_AGENT_PREFIX}qa`), "qa");
    assert.equal(bareAgentName("Vitruvian-Orchestrator:QA"), "QA");
    assert.equal(bareAgentName("wren"), "wren");
    assert.equal(bareAgentName("other:qa"), "other:qa");
    assert.equal(bareAgentName(undefined), undefined);
  });
});

describe("pluginAgentDefinitions", () => {
  it("defines every shipped agent under the plugin prefix", () => {
    const defs = pluginAgentDefinitions(PLUGIN_DIR);
    const shipped = fs
      .readdirSync(path.join(PLUGIN_DIR, "agents"))
      .filter((f) => f.endsWith(".md"))
      .map((f) => `${PLUGIN_AGENT_PREFIX}${f.slice(0, -3)}`)
      .sort();
    assert.deepEqual(defs.map((d) => d.id).sort(), shipped);
    // OpenCode has its own `build` agent; ours must not take its name.
    assert.ok(!defs.some((d) => d.id === "build"));
    for (const d of defs) {
      assert.ok(d.description.length > 0, d.id);
      assert.equal(d.mode, "subagent", d.id);
      assert.ok(d.system.length > 100, d.id);
      assert.ok(!d.system.startsWith("---"), d.id);
    }
  });

  it("skips files that are not agents", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "oc-agents-"));
    fs.mkdirSync(path.join(dir, "agents"));
    fs.writeFileSync(path.join(dir, "agents", "no-front.md"), "body only");
    fs.writeFileSync(
      path.join(dir, "agents", "Bad Name.md"),
      "---\ndescription: x\n---\nbody",
    );
    fs.writeFileSync(
      path.join(dir, "agents", "nodesc.md"),
      "---\nmode: subagent\n---\nbody",
    );
    fs.writeFileSync(path.join(dir, "agents", "notes.txt"), "ignored");
    fs.writeFileSync(
      path.join(dir, "agents", "ok.md"),
      "---\ndescription: Fine\nmode: weird\n---\nBody",
    );
    const defs = pluginAgentDefinitions(dir);
    assert.deepEqual(defs, [
      {
        id: `${PLUGIN_AGENT_PREFIX}ok`,
        description: "Fine",
        mode: "subagent",
        system: "Body",
      },
    ]);
  });

  it("returns nothing for a missing folder", () => {
    assert.deepEqual(pluginAgentDefinitions("/nonexistent/dir"), []);
  });
});

describe("pluginSkillDefinitions", () => {
  it("defines every shipped skill by its name, with its path and body", () => {
    const defs = pluginSkillDefinitions(PLUGIN_DIR);
    assert.deepEqual(defs.map((d) => d.id).sort(), [
      "orchestrate",
      "team-setup",
    ]);
    for (const d of defs) {
      assert.equal(d.name, d.id);
      assert.ok(d.description.length > 0);
      assert.ok(path.isAbsolute(d.path));
      assert.ok(fs.existsSync(d.path));
      assert.ok(!d.content.startsWith("---"));
    }
  });
});

describe("registerPluginAgentsAndSkills", () => {
  it("adds the agents and skills to a fresh OpenCode", async () => {
    const { ctx, agents, skills } = fakeCtx({
      agents: [{ id: "build", name: "build", mode: "primary", system: "own" }],
    });
    const result = await registerPluginAgentsAndSkills(ctx, PLUGIN_DIR);
    const dev = agents.get(`${PLUGIN_AGENT_PREFIX}developer`);
    assert.equal(dev?.mode, "subagent");
    assert.ok(dev?.description);
    assert.ok(dev?.system);
    // OpenCode's own build agent is left alone.
    assert.deepEqual(agents.get("build"), {
      id: "build",
      name: "build",
      mode: "primary",
      system: "own",
    });
    assert.ok(skills.has("orchestrate"));
    assert.ok(skills.has("team-setup"));
    assert.equal(result.agents.length, 10);
    assert.deepEqual(result.skills.sort(), ["orchestrate", "team-setup"]);
  });

  it("keeps an agent or skill the user already defined", async () => {
    const mine = {
      id: `${PLUGIN_AGENT_PREFIX}qa`,
      name: "qa",
      mode: "subagent",
      system: "my own qa",
      description: "mine",
    };
    const repoSkill = {
      id: "orchestrate",
      name: "orchestrate",
      description: "this repository's own lead skill",
      path: "/repo/.opencode/skills/orchestrate/SKILL.md",
      content: "repo",
    };
    const { ctx, agents, skills } = fakeCtx({
      agents: [mine],
      skills: [repoSkill],
    });
    const result = await registerPluginAgentsAndSkills(ctx, PLUGIN_DIR);
    assert.deepEqual(agents.get(mine.id), mine);
    assert.deepEqual(skills.get("orchestrate"), repoSkill);
    assert.ok(!result.agents.includes(mine.id));
    assert.deepEqual(result.skills, ["team-setup"]);
  });

  it("skips a skill whose name is taken under another id", async () => {
    const { ctx, skills } = fakeCtx({
      skills: [
        {
          id: "repo/orchestrate",
          name: "orchestrate",
          description: "x",
          path: "/x",
          content: "x",
        },
      ],
    });
    const result = await registerPluginAgentsAndSkills(ctx, PLUGIN_DIR);
    assert.ok(!skills.has("orchestrate"));
    assert.deepEqual(result.skills, ["team-setup"]);
  });

  it("does nothing on an OpenCode without the editors", async () => {
    assert.deepEqual(await registerPluginAgentsAndSkills({}, PLUGIN_DIR), {
      agents: [],
      skills: [],
    });
    assert.deepEqual(
      await registerPluginAgentsAndSkills(undefined, PLUGIN_DIR),
      { agents: [], skills: [] },
    );
  });

  it("keeps going when one editor throws", async () => {
    const { ctx, skills } = fakeCtx();
    ctx.agent.transform = async () => {
      throw new Error("agent editor broke");
    };
    const result = await registerPluginAgentsAndSkills(ctx, PLUGIN_DIR);
    assert.deepEqual(result.agents, []);
    assert.ok(skills.has("orchestrate"));
  });
});
