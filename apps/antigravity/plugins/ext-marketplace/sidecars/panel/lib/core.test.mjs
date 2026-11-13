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

import assert from "node:assert/strict";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  MARKETPLACE_CATALOG,
  applyPluginToggleToConfig,
  inspectPluginDirMeta,
  mergeInstalledWithCatalog,
  summariseMarketplace,
} from "./core.mjs";

// Plugins that have a standalone mirror repository (tools/copybara/copy.bara.sky).
const STANDALONE_MIRRORS = new Set(["gh-watch"]);

const EXPECTED_IDS = [
  "gh-watch",
  "worktree-band",
  "ralph-loop",
  "hookify",
  "security-guidance",
  "receipts-report",
  "live-context",
  "savvy-fleet",
  "vitruvian-orchestrator",
  "ext-marketplace",
];

test("MARKETPLACE_CATALOG lists all 10 first-party Vitruvian extensions", () => {
  assert.equal(MARKETPLACE_CATALOG.length, 10);
  assert.deepEqual(
    MARKETPLACE_CATALOG.map((item) => item.id),
    EXPECTED_IDS,
  );
  for (const item of MARKETPLACE_CATALOG) {
    // Only plugins with a standalone mirror link to their own repo; the rest install
    // from their monorepo folder (agy installs from a GitHub subpath).
    const expectedRepo = STANDALONE_MIRRORS.has(item.id)
      ? `https://github.com/VitruvianSoftware/${item.id}`
      : `https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/antigravity/plugins/${item.id}`;
    assert.equal(item.repo, expectedRepo);
    assert.equal(item.monorepoPath, `apps/antigravity/plugins/${item.id}`);
    assert.ok(item.name && item.description && item.category);
    assert.ok(Array.isArray(item.highlights) && item.highlights.length > 0);
  }
});

test("inspectPluginDirMeta extracts capabilities from an in-memory descriptor and a real directory", () => {
  const meta = inspectPluginDirMeta({
    id: "savvy-fleet",
    pluginJson: {
      name: "savvy-fleet",
      version: "0.1.0",
      description: "Fleet tracker",
    },
    sidecars: [{ id: "panel", has_web_ui: true }],
    skills: ["savvy-flow", "savvy-fleet"],
    hooksJson: { "savvy-fleet-tracker": { PostToolUse: [] } },
    mcpJson: { mcpServers: { fleet: {} } },
    rules: ["AGENTS.md"],
  });

  assert.equal(meta.id, "savvy-fleet");
  assert.equal(meta.version, "0.1.0");
  assert.equal(meta.hasSidecarUi, true);
  assert.deepEqual(meta.skills, ["savvy-fleet", "savvy-flow"]);
  assert.deepEqual(meta.hooks, ["savvy-fleet-tracker"]);
  assert.deepEqual(meta.mcpServers, ["fleet"]);
  assert.deepEqual(meta.rules, ["AGENTS.md"]);

  const tmpRoot = mkdtempSync(join(tmpdir(), "ext-mp-test-"));
  const selfDir = join(tmpRoot, "ext-marketplace");
  try {
    mkdirSync(join(selfDir, "sidecars", "panel"), { recursive: true });
    mkdirSync(join(selfDir, "skills", "ext-marketplace"), { recursive: true });
    mkdirSync(join(selfDir, "rules"), { recursive: true });
    writeFileSync(
      join(selfDir, "plugin.json"),
      JSON.stringify({ name: "ext-marketplace", version: "0.1.0" }),
    );
    writeFileSync(
      join(selfDir, "sidecars", "panel", "sidecar.json"),
      JSON.stringify({ id: "panel", has_web_ui: true }),
    );
    writeFileSync(
      join(selfDir, "skills", "ext-marketplace", "SKILL.md"),
      "# ext-marketplace\n",
    );
    writeFileSync(join(selfDir, "rules", "AGENTS.md"), "# rules\n");
    writeFileSync(
      join(selfDir, "hooks.json"),
      JSON.stringify({ "ext-marketplace-tracker": { PostToolUse: [] } }),
    );

    const diskMeta = inspectPluginDirMeta(selfDir);
    assert.equal(diskMeta.id, "ext-marketplace");
    assert.equal(diskMeta.version, "0.1.0");
    assert.equal(diskMeta.hasSidecarUi, true);
    assert.deepEqual(diskMeta.skills, ["ext-marketplace"]);
    assert.deepEqual(diskMeta.rules, ["AGENTS.md"]);
    assert.deepEqual(diskMeta.hooks, ["ext-marketplace-tracker"]);
  } finally {
    rmSync(tmpRoot, { recursive: true, force: true });
  }
});

test("applyPluginToggleToConfig updates enabled state non-destructively", () => {
  const original = {
    plugins: {
      "chrome-devtools-plugin": {
        enabled: true,
        installedFrom: {
          id: "antigravity-plugins-official/plugin/chrome-devtools-plugin",
          marketplace: "antigravity-plugins-official",
          version: "1.10.1",
        },
      },
    },
    userSettings: {
      themeMode: "THEME_MODE_INHERIT",
    },
  };

  const disabled = applyPluginToggleToConfig(
    original,
    "chrome-devtools-plugin",
    false,
  );
  assert.equal(disabled.plugins["chrome-devtools-plugin"].enabled, false);
  assert.deepEqual(
    disabled.plugins["chrome-devtools-plugin"].installedFrom,
    original.plugins["chrome-devtools-plugin"].installedFrom,
  );
  assert.equal(original.plugins["chrome-devtools-plugin"].enabled, true);
  assert.deepEqual(disabled.userSettings, original.userSettings);

  const added = applyPluginToggleToConfig(disabled, "savvy-fleet", true);
  assert.equal(added.plugins["savvy-fleet"].enabled, true);
});

test("mergeInstalledWithCatalog and summariseMarketplace combine catalog, installed dirs, and config.json", () => {
  const installedList = [
    {
      id: "gh-watch",
      version: "0.7.0",
      hasSidecarUi: true,
      hooks: ["gh-watch-signup"],
      rules: ["AGENTS.md"],
    },
    {
      id: "ext-marketplace",
      version: "0.1.0",
      hasSidecarUi: true,
      skills: ["ext-marketplace"],
    },
  ];
  const configJson = {
    plugins: {
      "gh-watch": { enabled: true },
      "ext-marketplace": { enabled: false },
      gslides: {
        enabled: true,
        installedFrom: {
          marketplace: "antigravity-plugins-official",
          version: "0.0.6",
        },
      },
    },
  };

  const merged = mergeInstalledWithCatalog(installedList, configJson);
  assert.equal(merged.length, 11);

  const ghWatch = merged.find((p) => p.id === "gh-watch");
  assert.equal(ghWatch.installed, true);
  assert.equal(ghWatch.enabled, true);
  assert.equal(ghWatch.version, "0.7.0");
  assert.equal(ghWatch.updateAvailable, true);
  assert.equal(ghWatch.source, "vitruvian");

  const gslides = merged.find((p) => p.id === "gslides");
  assert.equal(gslides.installed, true);
  assert.equal(gslides.enabled, true);
  assert.equal(gslides.source, "official");

  const summary = summariseMarketplace({
    version: "0.1.0",
    installedList,
    configJson,
  });
  assert.equal(summary.counts.total, 11);
  assert.equal(summary.counts.catalog, 10);
  assert.equal(summary.counts.installed, 3);
  assert.equal(summary.counts.enabled, 2);
  assert.equal(summary.counts.disabled, 1);
  assert.equal(summary.counts.updatesAvailable, 1);
});

test("drift: MARKETPLACE_CATALOG, SKILL.md, README.md, and plugins/README.md match physical plugin folders", () => {
  const here = dirname(fileURLToPath(import.meta.url));
  let pluginsRoot = here;
  for (const base of [process.cwd(), here]) {
    let dir = resolve(base);
    for (let i = 0; i < 8; i += 1) {
      const cand = join(dir, "apps/antigravity/plugins");
      if (
        existsSync(
          join(cand, "ext-marketplace/skills/ext-marketplace/SKILL.md"),
        )
      ) {
        pluginsRoot = cand;
        break;
      }
      const p = dirname(dir);
      if (p === dir) break;
      dir = p;
    }
  }

  const physicalIds = readdirSync(pluginsRoot, { withFileTypes: true })
    .filter(
      (entry) =>
        entry.isDirectory() &&
        (existsSync(join(pluginsRoot, entry.name, "plugin.json")) ||
          existsSync(
            join(pluginsRoot, entry.name, ".claude-plugin/plugin.json"),
          )),
    )
    .map((entry) => entry.name)
    .sort();
  assert.ok(
    physicalIds.length >= 10,
    `expected >= 10 plugin dirs, got ${physicalIds.join(", ")}`,
  );

  const catalogIds = MARKETPLACE_CATALOG.map((p) => p.id).sort();
  assert.deepEqual(
    catalogIds,
    physicalIds,
    `MARKETPLACE_CATALOG (${catalogIds.join(", ")}) must list every physical folder under apps/antigravity/plugins (${physicalIds.join(", ")})`,
  );

  const skill = readFileSync(
    join(pluginsRoot, "ext-marketplace/skills/ext-marketplace/SKILL.md"),
    "utf8",
  );
  const readme = readFileSync(
    join(pluginsRoot, "ext-marketplace/README.md"),
    "utf8",
  );
  const rootReadme = readFileSync(join(pluginsRoot, "README.md"), "utf8");

  for (const id of physicalIds) {
    assert.ok(
      skill.includes(`\`${id}\``),
      `SKILL.md catalog list missing plugin \`${id}\``,
    );
    assert.ok(
      readme.includes(`\`${id}\``),
      `README.md catalog list missing plugin \`${id}\``,
    );
    assert.ok(
      rootReadme.includes(`[${id}](./${id}/`) ||
        rootReadme.includes(`\`${id}/`),
      `apps/antigravity/plugins/README.md missing plugin ${id}`,
    );
  }

  // No hardcoded stale plugin count anywhere in SKILL.md, README.md, or catalog highlights.
  for (const [label, text] of [
    ["SKILL.md", skill],
    ["README.md", readme],
    [
      "MARKETPLACE_CATALOG.highlights",
      MARKETPLACE_CATALOG.flatMap((p) => p.highlights ?? []).join("\n"),
    ],
  ]) {
    for (const m of text.matchAll(/\b(\d+)\s+first-party\b/gi)) {
      assert.equal(
        Number(m[1]),
        physicalIds.length,
        `${label} mentions stale count "${m[0]}" (expected ${physicalIds.length})`,
      );
    }
  }
});
