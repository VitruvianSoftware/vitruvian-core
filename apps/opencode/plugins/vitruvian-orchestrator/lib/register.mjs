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

// Registers the plugin's own agents (agents/*.md) and skills
// (skills/<name>/SKILL.md) with OpenCode, so one `plugins` entry in
// opencode.json brings the whole team. OpenCode only discovers agent and skill
// files in its config folders, never inside a plugin, so the plugin adds them
// through the editors OpenCode 2.3 hands a server plugin:
//   - ctx.agent.transform(editor): the editor has no `add`; `update(id, fn)`
//     creates a missing agent and passes `fn` a draft to change.
//   - ctx.skill.transform(editor): `add({ id, name, description, path, content })`.
//
// Agents are named `vitruvian-orchestrator:<role>`, the same ids the team tool
// hands out for a role with no agent of its own. The prefix keeps them clear
// of OpenCode's built-in agents (it ships one called `build`) and of the
// repository's own. Skills keep their plain names (`orchestrate`), and one
// whose name the repository already uses is left to the repository.

import fs from "node:fs";
import path from "node:path";

export const PLUGIN_AGENT_PREFIX = "vitruvian-orchestrator:";

const AGENT_NAME_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;
const AGENT_MODES = new Set(["primary", "subagent", "all"]);
// `provider/model`, the form agent files use; same charset as the team file.
const MODEL_RE =
  /^([a-z0-9][a-z0-9._-]{0,63})\/([A-Za-z0-9][A-Za-z0-9._:-]{0,127})$/;
const EFFORTS = new Set(["minimal", "low", "medium", "high", "xhigh", "max"]);
const MAX_FILE_BYTES = 256 * 1024;

/**
 * Strips the plugin's agent prefix: `vitruvian-orchestrator:qa` -> `qa`.
 * Anything else is returned unchanged.
 *
 * @template T
 * @param {T} name
 * @returns {T | string}
 */
export function bareAgentName(name) {
  if (typeof name !== "string") return name;
  return name.toLowerCase().startsWith(PLUGIN_AGENT_PREFIX)
    ? name.slice(PLUGIN_AGENT_PREFIX.length)
    : name;
}

/**
 * Splits a Markdown file into its YAML frontmatter (flat `key: value` lines
 * only, which is all the generated files use) and its body.
 *
 * @param {string} text
 * @returns {{ data: Record<string, string>, body: string } | null}
 */
export function parseFrontmatter(text) {
  if (typeof text !== "string") return null;
  const m = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(text);
  if (!m) return null;
  /** @type {Record<string, string>} */
  const data = Object.create(null);
  for (const line of m[1].split(/\r?\n/)) {
    const kv = /^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/.exec(line);
    if (!kv) continue;
    let value = kv[2].trim();
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    data[kv[1]] = value;
  }
  const body = text.slice(m[0].length).replace(/^(?:\r?\n)+/, "");
  return { data: { ...data }, body };
}

function readSmallFile(file) {
  try {
    const st = fs.lstatSync(file);
    if (!st.isFile() || st.size > MAX_FILE_BYTES) return null;
    return fs.readFileSync(file, "utf8");
  } catch {
    return null;
  }
}

function listDir(dir) {
  try {
    return fs.readdirSync(dir).sort();
  } catch {
    return [];
  }
}

/**
 * The plugin's agents, from `<pluginDir>/agents/<role>.md`.
 *
 * @param {string} pluginDir
 * `model` (`provider/model`) and `reasoningEffort` are kept in the shape
 * OpenCode 2.3 gives an agent it read from a file: `model: { providerID, id }`
 * and `request.body.reasoningEffort`. An unusable value is left out, so the
 * session's own model applies.
 *
 * @returns {Array<{ id: string, description: string, mode: string, system: string, model?: { providerID: string, id: string }, reasoningEffort?: string }>}
 */
export function pluginAgentDefinitions(pluginDir) {
  const dir = path.join(pluginDir, "agents");
  const defs = [];
  for (const file of listDir(dir)) {
    if (!file.endsWith(".md")) continue;
    const role = file.slice(0, -3);
    if (!AGENT_NAME_RE.test(role)) continue;
    const parsed = parseFrontmatter(readSmallFile(path.join(dir, file)));
    const description = parsed?.data.description?.trim();
    if (!parsed || !description) continue;
    const mode = AGENT_MODES.has(parsed.data.mode)
      ? parsed.data.mode
      : "subagent";
    /** @type {{ id: string, description: string, mode: string, system: string, model?: { providerID: string, id: string }, reasoningEffort?: string }} */
    const def = {
      id: `${PLUGIN_AGENT_PREFIX}${role}`,
      description,
      mode,
      system: parsed.body,
    };
    const model = MODEL_RE.exec(parsed.data.model ?? "");
    if (model) def.model = { providerID: model[1], id: model[2] };
    const effort = parsed.data.reasoningEffort;
    if (EFFORTS.has(effort)) def.reasoningEffort = effort;
    defs.push(def);
  }
  return defs;
}

/**
 * The plugin's skills, from `<pluginDir>/skills/<name>/SKILL.md`.
 *
 * @param {string} pluginDir
 * @returns {Array<{ id: string, name: string, description: string, path: string, content: string }>}
 */
export function pluginSkillDefinitions(pluginDir) {
  const dir = path.join(pluginDir, "skills");
  const defs = [];
  for (const name of listDir(dir)) {
    if (!AGENT_NAME_RE.test(name)) continue;
    const file = path.join(dir, name, "SKILL.md");
    const parsed = parseFrontmatter(readSmallFile(file));
    const description = parsed?.data.description?.trim();
    if (!parsed || !description) continue;
    defs.push({
      id: name,
      name,
      description,
      path: path.resolve(file),
      content: parsed.body,
    });
  }
  return defs;
}

function asArray(value) {
  if (Array.isArray(value)) return value;
  if (value && Array.isArray(value.data)) return value.data;
  return [];
}

/**
 * Adds the plugin's agents and skills through OpenCode's editors. An agent or
 * skill that already exists (the user's or the repository's) is kept as it
 * is. Missing editors (an older OpenCode) or an editor that throws are
 * skipped, never fatal: the tools and the panel still load.
 *
 * @param {any} ctx OpenCode server plugin context
 * @param {string} pluginDir
 * @returns {Promise<{ agents: string[], skills: string[] }>} what was added
 */
export async function registerPluginAgentsAndSkills(ctx, pluginDir) {
  /** @type {{ agents: string[], skills: string[] }} */
  const added = { agents: [], skills: [] };

  if (typeof ctx?.agent?.transform === "function") {
    const defs = pluginAgentDefinitions(pluginDir);
    try {
      await ctx.agent.transform((editor) => {
        for (const def of defs) {
          if (editor.get?.(def.id)) continue;
          editor.update(def.id, (draft) => {
            draft.description = def.description;
            draft.mode = def.mode;
            draft.system = def.system;
            if (def.model) draft.model = { ...def.model };
            if (def.reasoningEffort) {
              const request = draft.request ?? {};
              draft.request = {
                ...request,
                body: {
                  ...(request.body ?? {}),
                  reasoningEffort: def.reasoningEffort,
                },
              };
            }
          });
          added.agents.push(def.id);
        }
      });
    } catch {
      // Agents updated before the throw may stay; report none as added.
      added.agents = [];
    }
  }

  if (typeof ctx?.skill?.transform === "function") {
    const defs = pluginSkillDefinitions(pluginDir);
    try {
      await ctx.skill.transform((editor) => {
        const taken = new Set();
        for (const s of asArray(editor.list?.())) {
          if (typeof s?.id === "string") taken.add(s.id.toLowerCase());
          if (typeof s?.name === "string") taken.add(s.name.toLowerCase());
        }
        for (const def of defs) {
          if (taken.has(def.id) || editor.get?.(def.id)) continue;
          editor.add(def);
          added.skills.push(def.id);
        }
      });
    } catch {
      added.skills = [];
    }
  }

  return added;
}
