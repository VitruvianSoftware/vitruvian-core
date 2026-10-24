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

// Pure catalog, metadata inspection, and non-destructive config management
// functions for the ext-marketplace Antigravity plugin.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { basename, join } from "node:path";

export const MARKETPLACE_CATALOG = Object.freeze([
  Object.freeze({
    id: "gh-watch",
    name: "GH Watch",
    version: "0.8.1",
    description:
      "Watches your pull requests on GitHub and wakes the conversation that owns one when its CI starts failing.",
    repo: "https://github.com/VitruvianSoftware/gh-watch",
    monorepoPath: "apps/desktop/antigravity/plugins/gh-watch",
    category: "CI & GitHub",
    highlights: Object.freeze([
      "Auto-watches PRs on gh pr create",
      "Wakes conversation with failure log excerpts",
      "Tracks merge queue & post-merge landing",
    ]),
  }),
  Object.freeze({
    id: "worktree-band",
    name: "Worktree Band",
    version: "0.1.0",
    description:
      "Tracks active git worktrees, dirty status, branch hygiene, and one-click safe pruning.",
    repo: "https://github.com/VitruvianSoftware/worktree-band",
    monorepoPath: "apps/desktop/antigravity/plugins/worktree-band",
    category: "Git & Workspaces",
    highlights: Object.freeze([
      "Live worktree status & branch tracking",
      "Safe pruning of merged ephemeral worktrees",
      "Worktree lock & hygiene status",
    ]),
  }),
  Object.freeze({
    id: "ralph-loop",
    name: "Ralph Loop",
    version: "0.1.0",
    description:
      "Autonomous iterative verification loop that keeps refining and testing until completion criteria pass.",
    repo: "https://github.com/VitruvianSoftware/ralph-loop",
    monorepoPath: "apps/desktop/antigravity/plugins/ralph-loop",
    category: "Autonomous Loops",
    highlights: Object.freeze([
      "Self-correcting test & lint iterations",
      "Configurable max iterations and guardrails",
      "Live iteration progress sidecar",
    ]),
  }),
  Object.freeze({
    id: "hookify",
    name: "Hookify",
    version: "0.1.0",
    description:
      "Declarative PreToolUse and PostToolUse hook rule builder, tester, and policy inspector.",
    repo: "https://github.com/VitruvianSoftware/hookify",
    monorepoPath: "apps/desktop/antigravity/plugins/hookify",
    category: "Guardrails & Hooks",
    highlights: Object.freeze([
      "Author and test regex/command hook rules",
      "Dry-run payload simulator",
      "Zero-latency shell hook templates",
    ]),
  }),
  Object.freeze({
    id: "security-guidance",
    name: "Security Guidance",
    version: "0.1.0",
    description:
      "Real-time security posture advisor, secret pattern detector, and high-risk command inspector.",
    repo: "https://github.com/VitruvianSoftware/security-guidance",
    monorepoPath: "apps/desktop/antigravity/plugins/security-guidance",
    category: "Security",
    highlights: Object.freeze([
      "Pre-commit secret & token pattern checks",
      "Supply-chain and RBAC review checklists",
      "Live security advisories in sidecar pane",
    ]),
  }),
  Object.freeze({
    id: "receipts-report",
    name: "Receipts Report",
    version: "0.1.0",
    description:
      "Generates verifiable engineering receipts, tool audit ledgers, and PR delivery summaries.",
    repo: "https://github.com/VitruvianSoftware/receipts-report",
    monorepoPath: "apps/desktop/antigravity/plugins/receipts-report",
    category: "Telemetry & Audit",
    highlights: Object.freeze([
      "Structured proof-of-work receipts",
      "Command and test execution ledger",
      "Exportable Markdown & OpenUI Lang reports",
    ]),
  }),
  Object.freeze({
    id: "live-context",
    name: "Live Context",
    version: "0.1.0",
    description:
      "Inspects active workspace rules, loaded skills, MCP server tools, and context budget utilization.",
    repo: "https://github.com/VitruvianSoftware/live-context",
    monorepoPath: "apps/desktop/antigravity/plugins/live-context",
    category: "Context & Memory",
    highlights: Object.freeze([
      "Live AGENTS.md & user rule hierarchy",
      "MCP server and skill discovery inventory",
      "Context token budget breakdown",
    ]),
  }),
  Object.freeze({
    id: "savvy-fleet",
    name: "Savvy Fleet",
    version: "0.1.0",
    description:
      "Tiered orchestrator-worker subagent flow (savvy-flow) and live subagent fleet telemetry.",
    repo: "https://github.com/VitruvianSoftware/savvy-fleet",
    monorepoPath: "apps/desktop/antigravity/plugins/savvy-fleet",
    category: "Subagents",
    highlights: Object.freeze([
      "5-phase savvy-flow orchestration skill",
      "Live subagent tier, round & status tracking",
      "Token & USD run cost estimation",
    ]),
  }),
  Object.freeze({
    id: "ext-marketplace",
    name: "Extensions Marketplace",
    version: "0.1.0",
    description:
      "Unified Extensions Marketplace catalog and installed plugin manager sidecar for Antigravity.",
    repo: "https://github.com/VitruvianSoftware/ext-marketplace",
    monorepoPath: "apps/desktop/antigravity/plugins/ext-marketplace",
    category: "Extensions",
    highlights: Object.freeze([
      "Browse all 9 first-party Vitruvian plugins",
      "Safe non-destructive config.json toggling",
      "One-click install, update, and capability view",
    ]),
  }),
]);

function safeParseJson(text) {
  if (!text) return null;
  if (typeof text === "object") return text;
  try {
    return JSON.parse(String(text));
  } catch {
    return null;
  }
}

/**
 * Inspects a plugin directory on disk or an in-memory descriptor object and
 * returns its capabilities (`hasSidecarUi`, `skills`, `hooks`, `mcpServers`, `rules`).
 *
 * @param {string | Record<string, any>} dirOrDescriptor
 */
export function inspectPluginDirMeta(dirOrDescriptor) {
  if (typeof dirOrDescriptor === "string") {
    const dirPath = dirOrDescriptor;
    const id = basename(dirPath);
    const pluginJsonPath = join(dirPath, "plugin.json");
    const pluginJson = existsSync(pluginJsonPath)
      ? safeParseJson(readFileSync(pluginJsonPath, "utf8"))
      : null;

    const skills = [];
    const skillsDir = join(dirPath, "skills");
    if (existsSync(skillsDir)) {
      try {
        for (const entry of readdirSync(skillsDir, { withFileTypes: true })) {
          if (
            entry.isDirectory() &&
            existsSync(join(skillsDir, entry.name, "SKILL.md"))
          ) {
            skills.push(entry.name);
          }
        }
      } catch {
        // Ignore unreadable skills directory.
      }
    }

    const rules = [];
    const rulesDir = join(dirPath, "rules");
    if (existsSync(rulesDir)) {
      try {
        for (const entry of readdirSync(rulesDir)) {
          if (entry.endsWith(".md")) rules.push(entry);
        }
      } catch {
        // Ignore unreadable rules directory.
      }
    }

    const sidecars = [];
    const sidecarsDir = join(dirPath, "sidecars");
    if (existsSync(sidecarsDir)) {
      try {
        for (const entry of readdirSync(sidecarsDir, { withFileTypes: true })) {
          if (!entry.isDirectory()) continue;
          const scPath = join(sidecarsDir, entry.name, "sidecar.json");
          if (existsSync(scPath)) {
            const sc = safeParseJson(readFileSync(scPath, "utf8"));
            if (sc) sidecars.push({ id: entry.name, ...sc });
          }
        }
      } catch {
        // Ignore unreadable sidecars directory.
      }
    }

    const hooksJsonPath = join(dirPath, "hooks.json");
    const hooksJson = existsSync(hooksJsonPath)
      ? safeParseJson(readFileSync(hooksJsonPath, "utf8"))
      : null;

    const mcpJsonPath = join(dirPath, "mcp.json");
    const mcpJson = existsSync(mcpJsonPath)
      ? safeParseJson(readFileSync(mcpJsonPath, "utf8"))
      : null;

    return inspectPluginDirMeta({
      id,
      pluginJson,
      sidecars,
      skills,
      rules,
      hooksJson,
      mcpJson,
    });
  }

  const desc =
    dirOrDescriptor && typeof dirOrDescriptor === "object"
      ? dirOrDescriptor
      : {};
  const pjson = safeParseJson(desc.pluginJson) ?? {};
  const id = String(desc.id ?? pjson.name ?? "").trim();
  const name = String(desc.name ?? pjson.name ?? id).trim();
  const version = String(desc.version ?? pjson.version ?? "").trim();
  const description = String(
    desc.description ?? pjson.description ?? "",
  ).trim();
  const repository = String(desc.repository ?? pjson.repository ?? "").trim();

  const sidecars = Array.isArray(desc.sidecars) ? desc.sidecars : [];
  const hasSidecarUi =
    Boolean(desc.hasSidecarUi) ||
    sidecars.some((s) => s && (s.has_web_ui === true || Boolean(s.ui_config)));

  const skills = Array.isArray(desc.skills)
    ? desc.skills.map(String).sort()
    : [];
  const rules = Array.isArray(desc.rules) ? desc.rules.map(String).sort() : [];

  const hooksObj = safeParseJson(desc.hooksJson);
  const hooks = Array.isArray(desc.hooks)
    ? desc.hooks.map(String)
    : hooksObj && typeof hooksObj === "object"
      ? Object.keys(hooksObj)
      : [];

  const mcpObj = safeParseJson(desc.mcpJson);
  const mcpServers = Array.isArray(desc.mcpServers)
    ? desc.mcpServers.map(String)
    : mcpObj && typeof mcpObj === "object"
      ? Object.keys(mcpObj.mcpServers ?? mcpObj)
      : [];

  return {
    id,
    name,
    version,
    description,
    repository,
    hasSidecarUi,
    skills,
    hooks,
    mcpServers,
    rules,
  };
}

/**
 * Non-destructively updates `configObj.plugins[pluginName].enabled = Boolean(enabled)`
 * while preserving `installedFrom` and all other top-level and per-plugin keys.
 *
 * @param {Record<string, any> | null | undefined} configObj
 * @param {string} pluginName
 * @param {boolean} enabled
 * @returns {Record<string, any>}
 */
export function applyPluginToggleToConfig(configObj, pluginName, enabled) {
  const base =
    configObj && typeof configObj === "object"
      ? structuredClone(configObj)
      : {};
  const name = String(pluginName ?? "").trim();
  if (!name) return base;

  if (!base.plugins || typeof base.plugins !== "object") {
    base.plugins = {};
  }
  const prevEntry =
    base.plugins[name] && typeof base.plugins[name] === "object"
      ? base.plugins[name]
      : {};
  base.plugins[name] = {
    ...prevEntry,
    enabled: Boolean(enabled),
  };
  return base;
}

function compareSemver(installedVer, catalogVer) {
  if (!installedVer || !catalogVer) return false;
  const parse = (v) =>
    String(v)
      .replace(/^v/, "")
      .split(".")
      .map((n) => Number(n) || 0);
  const [aMaj = 0, aMin = 0, aPat = 0] = parse(installedVer);
  const [bMaj = 0, bMin = 0, bPat = 0] = parse(catalogVer);
  if (bMaj !== aMaj) return bMaj > aMaj;
  if (bMin !== aMin) return bMin > aMin;
  return bPat > aPat;
}

/**
 * Merges discovered plugins from `~/.gemini/config/plugins/` and
 * `~/.gemini/config/config.json` with `MARKETPLACE_CATALOG`.
 *
 * @param {Array<Record<string, any>>} [installedList]
 * @param {Record<string, any>} [configJson]
 * @param {ReadonlyArray<Record<string, any>>} [catalog]
 */
export function mergeInstalledWithCatalog(
  installedList = [],
  configJson = {},
  catalog = MARKETPLACE_CATALOG,
) {
  const installedById = new Map();
  for (const raw of Array.isArray(installedList) ? installedList : []) {
    if (!raw || typeof raw !== "object") continue;
    const meta = inspectPluginDirMeta(raw);
    if (meta.id) installedById.set(meta.id, meta);
  }

  const configPlugins =
    configJson &&
    typeof configJson === "object" &&
    configJson.plugins &&
    typeof configJson.plugins === "object"
      ? configJson.plugins
      : {};

  const catalogById = new Map();
  for (const item of Array.isArray(catalog) ? catalog : []) {
    if (item && item.id) catalogById.set(item.id, item);
  }

  const allIds = new Set([
    ...catalogById.keys(),
    ...installedById.keys(),
    ...Object.keys(configPlugins),
  ]);

  const merged = [];
  for (const id of allIds) {
    const cat = catalogById.get(id);
    const inst = installedById.get(id);
    const cfg =
      configPlugins[id] && typeof configPlugins[id] === "object"
        ? configPlugins[id]
        : null;

    const installed = Boolean(inst || cfg?.installedFrom || cfg?.enabled);
    const enabled = cfg ? cfg.enabled === true : false;
    const version =
      inst?.version || cfg?.installedFrom?.version || cat?.version || "0.1.0";
    const source = cat
      ? "vitruvian"
      : cfg?.installedFrom?.marketplace
        ? "official"
        : "local";
    const hasSidecarUi = Boolean(
      inst?.hasSidecarUi ||
      cat ||
      (configJson?.sidecars && `${id}/panel` in configJson.sidecars),
    );
    const skills = inst?.skills ?? [];
    const hooks = inst?.hooks ?? [];
    const mcpServers = inst?.mcpServers ?? [];
    const rules = inst?.rules ?? [];
    const updateAvailable = Boolean(
      installed && cat?.version && compareSemver(version, cat.version),
    );

    merged.push({
      id,
      name: cat?.name || inst?.name || id,
      description: cat?.description || inst?.description || "",
      category:
        cat?.category || (source === "official" ? "Official" : "Custom"),
      repo: cat?.repo || inst?.repository || "",
      monorepoPath: cat?.monorepoPath || "",
      highlights: cat?.highlights ? [...cat.highlights] : [],
      installed,
      enabled,
      version,
      catalogVersion: cat?.version || "",
      source,
      hasSidecarUi,
      skills,
      hooks,
      mcpServers,
      rules,
      updateAvailable,
    });
  }

  // Sort Vitruvian catalog items first (preserving catalog order), then alphabetical.
  const catalogOrder = new Map(
    [...catalogById.keys()].map((id, index) => [id, index]),
  );
  merged.sort((a, b) => {
    const aIdx = catalogOrder.has(a.id) ? catalogOrder.get(a.id) : 999;
    const bIdx = catalogOrder.has(b.id) ? catalogOrder.get(b.id) : 999;
    if (aIdx !== bIdx) return aIdx - bIdx;
    return a.id.localeCompare(b.id);
  });

  return merged;
}

/**
 * Summarises the full Extensions Marketplace state for `/api/state` and OpenUI Lang.
 *
 * @param {Record<string, any>} [options]
 */
export function summariseMarketplace(options = {}) {
  const opts = options && typeof options === "object" ? options : {};
  const catalog = opts.catalog ?? MARKETPLACE_CATALOG;
  const plugins = mergeInstalledWithCatalog(
    opts.installedList ?? [],
    opts.configJson ?? {},
    catalog,
  );

  const installedCount = plugins.filter((p) => p.installed).length;
  const enabledCount = plugins.filter((p) => p.enabled).length;
  const disabledCount = plugins.filter((p) => p.installed && !p.enabled).length;
  const availableCount = plugins.filter((p) => !p.installed).length;
  const withSidecarUi = plugins.filter((p) => p.hasSidecarUi).length;
  const updatesAvailable = plugins.filter((p) => p.updateAvailable).length;

  const categories = [...new Set(plugins.map((p) => p.category))];

  return {
    version: String(opts.version ?? ""),
    plugins,
    categories,
    counts: {
      total: plugins.length,
      catalog: Array.isArray(catalog) ? catalog.length : 0,
      installed: installedCount,
      enabled: enabledCount,
      disabled: disabledCount,
      available: availableCount,
      withSidecarUi,
      updatesAvailable,
    },
  };
}
