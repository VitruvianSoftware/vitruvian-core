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

// Backend for the ext-marketplace sidecar panel.

import { execFile } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { Response, SidecarApp } from "sidecar_sdk";

import {
  MARKETPLACE_CATALOG,
  applyPluginToggleToConfig,
  inspectPluginDirMeta,
  summariseMarketplace,
} from "./lib/core.mjs";
import { parseOpenUILang, toOpenUILang } from "./lib/openui.mjs";

const execFileAsync = promisify(execFile);
const HERE = dirname(fileURLToPath(import.meta.url));
const GEMINI_CONFIG_DIR =
  process.env.ANTIGRAVITY_CONFIG_DIR || join(homedir(), ".gemini", "config");
const PLUGINS_DIR = join(GEMINI_CONFIG_DIR, "plugins");
const CONFIG_FILE = join(GEMINI_CONFIG_DIR, "config.json");
const MONOREPO_ROOT = resolve(HERE, "..", "..", "..", "..", "..", "..");

const app = new SidecarApp();
const readLocal = (name) => readFileSync(join(HERE, name), "utf8");
const fail = (message, status = 400) =>
  new Response(JSON.stringify({ error: message }), {
    contentType: "application/json",
    status,
  });

function readVersion() {
  try {
    return String(
      JSON.parse(readFileSync(join(HERE, "..", "..", "plugin.json"), "utf8"))
        .version ?? "",
    );
  } catch {
    return "";
  }
}
const VERSION = readVersion();

function readConfigJson() {
  try {
    if (existsSync(CONFIG_FILE)) {
      return JSON.parse(readFileSync(CONFIG_FILE, "utf8"));
    }
  } catch {
    // Return empty object if config.json cannot be parsed.
  }
  return {};
}

function writeConfigJsonAtomically(nextConfig) {
  mkdirSync(GEMINI_CONFIG_DIR, { recursive: true });
  const tmpFile = `${CONFIG_FILE}.tmp-${process.pid}-${Date.now()}`;
  writeFileSync(tmpFile, JSON.stringify(nextConfig, null, 2) + "\n", "utf8");
  renameSync(tmpFile, CONFIG_FILE);
}

function scanInstalledPlugins() {
  if (!existsSync(PLUGINS_DIR)) return [];
  const results = [];
  try {
    for (const entry of readdirSync(PLUGINS_DIR, { withFileTypes: true })) {
      if (entry.isDirectory() || entry.isSymbolicLink()) {
        const pluginPath = join(PLUGINS_DIR, entry.name);
        results.push(inspectPluginDirMeta(pluginPath));
      }
    }
  } catch {
    // Ignore unreadable plugins directory.
  }
  return results;
}

function buildState() {
  const installedList = scanInstalledPlugins();
  const configJson = readConfigJson();
  return summariseMarketplace({
    version: VERSION,
    installedList,
    configJson,
    catalog: MARKETPLACE_CATALOG,
  });
}

async function tryRunCommand(cmd, args) {
  try {
    const { stdout, stderr } = await execFileAsync(cmd, args, {
      timeout: 15_000,
    });
    return { ok: true, stdout: stdout.trim(), stderr: stderr.trim() };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

app.page("/", () => readLocal("index.html"));
app.page("/app.js", () => readLocal("app.js"));
app.api(
  "/styles.css",
  () => new Response(readLocal("styles.css"), { contentType: "text/css" }),
  "GET",
);
app.api(
  "/openui.mjs",
  () =>
    new Response(readLocal(join("lib", "openui.mjs")), {
      contentType: "text/javascript",
    }),
  "GET",
);

app.api(
  "/api/state",
  () => {
    const state = buildState();
    return { ...state, openuiDsl: toOpenUILang(state) };
  },
  "GET",
);

app.api(
  "/api/openui",
  () => {
    const state = buildState();
    const dsl = toOpenUILang(state);
    return { dsl, parsed: parseOpenUILang(dsl) };
  },
  "GET",
);

// POST /api/toggle {name, enabled}: runs `agy plugin enable|disable <name>`
// AND atomically updates ~/.gemini/config/config.json.
app.api("/api/toggle", async (data) => {
  const name = String(data?.name ?? "").trim();
  if (!/^[a-zA-Z0-9._-]+$/.test(name)) {
    return fail("Invalid plugin name");
  }
  const enabled = Boolean(data?.enabled);
  const subcmd = enabled ? "enable" : "disable";
  await tryRunCommand("agy", ["plugin", subcmd, name]);

  try {
    const current = readConfigJson();
    const updated = applyPluginToggleToConfig(current, name, enabled);
    writeConfigJsonAtomically(updated);
  } catch (err) {
    return fail(`Failed to update config.json: ${err.message}`, 500);
  }

  const state = buildState();
  return { ok: true, name, enabled, ...state, openuiDsl: toOpenUILang(state) };
});

// POST /api/install {name, repoUrl?}: installs from the local monorepo path via
// symlink when present, or runs `agy plugin install <repoUrl>`.
app.api("/api/install", async (data) => {
  const name = String(data?.name ?? "").trim();
  if (!/^[a-zA-Z0-9._-]+$/.test(name)) {
    return fail("Invalid plugin name");
  }
  const catalogEntry = MARKETPLACE_CATALOG.find((item) => item.id === name);
  const repoUrl = String(data?.repoUrl ?? catalogEntry?.repo ?? "").trim();
  const localMonorepoPluginDir = catalogEntry?.monorepoPath
    ? join(MONOREPO_ROOT, catalogEntry.monorepoPath)
    : "";

  mkdirSync(PLUGINS_DIR, { recursive: true });
  const targetDir = join(PLUGINS_DIR, name);

  if (
    localMonorepoPluginDir &&
    existsSync(join(localMonorepoPluginDir, "plugin.json")) &&
    !existsSync(targetDir)
  ) {
    try {
      symlinkSync(localMonorepoPluginDir, targetDir, "dir");
    } catch (err) {
      return fail(`Could not link plugin from monorepo: ${err.message}`, 500);
    }
  } else if (repoUrl) {
    const res = await tryRunCommand("agy", ["plugin", "install", repoUrl]);
    if (!res.ok && !existsSync(targetDir)) {
      return fail(res.error || "agy plugin install failed", 500);
    }
  } else if (!existsSync(targetDir)) {
    return fail("No repository URL or local monorepo path found for plugin");
  }

  try {
    const current = readConfigJson();
    const updated = applyPluginToggleToConfig(current, name, true);
    writeConfigJsonAtomically(updated);
  } catch {
    // Non-fatal if config.json update fails after install.
  }

  const state = buildState();
  return { ok: true, name, ...state, openuiDsl: toOpenUILang(state) };
});

// POST /api/uninstall {name}: runs `agy plugin uninstall <name>` and cleans up
// the plugin link/folder if still present.
app.api("/api/uninstall", async (data) => {
  const name = String(data?.name ?? "").trim();
  if (!/^[a-zA-Z0-9._-]+$/.test(name)) {
    return fail("Invalid plugin name");
  }
  await tryRunCommand("agy", ["plugin", "uninstall", name]);
  const targetDir = join(PLUGINS_DIR, name);
  if (existsSync(targetDir)) {
    try {
      rmSync(targetDir, { recursive: true, force: true });
    } catch {
      // Ignore removal error if managed externally.
    }
  }
  try {
    const current = readConfigJson();
    const updated = applyPluginToggleToConfig(current, name, false);
    writeConfigJsonAtomically(updated);
  } catch {
    // Ignore config cleanup failure.
  }

  const state = buildState();
  return { ok: true, name, ...state, openuiDsl: toOpenUILang(state) };
});

// POST /api/update {name}: runs `git -C ~/.gemini/config/plugins/<name> pull`.
app.api("/api/update", async (data) => {
  const name = String(data?.name ?? "").trim();
  if (!/^[a-zA-Z0-9._-]+$/.test(name)) {
    return fail("Invalid plugin name");
  }
  const targetDir = join(PLUGINS_DIR, name);
  if (!existsSync(targetDir)) {
    return fail(`Plugin '${name}' is not installed in ${PLUGINS_DIR}`, 404);
  }
  const res = await tryRunCommand("git", ["-C", targetDir, "pull"]);
  if (!res.ok) {
    return fail(`git pull failed: ${res.error}`, 500);
  }

  const state = buildState();
  return {
    ok: true,
    name,
    output: res.stdout,
    ...state,
    openuiDsl: toOpenUILang(state),
  };
});

app.run();
