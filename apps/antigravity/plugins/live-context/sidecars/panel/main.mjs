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

// Backend for the live-context sidecar panel. Maintains a cached Git & GitHub
// snapshot in ~/.gemini/antigravity/live-context-state/snapshot.json and active
// response contract settings in settings.json. The hooks (hooks/src, Rust)
// read both; the PreInvocation hook re-asks gh itself when this snapshot is
// over two minutes old, so the panel need not be open.

import { execFile } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { Response, SidecarApp } from "sidecar_sdk";

import {
  buildEphemeralContextPayload,
  DEFAULT_RESPONSE_CONTRACT,
} from "./lib/core.mjs";
import { parseOpenUILang, toOpenUILang } from "./lib/openui.mjs";

const execFileAsync = promisify(execFile);
const HERE = dirname(fileURLToPath(import.meta.url));
const APP_DATA_DIR =
  process.env.ANTIGRAVITY_APP_DATA_DIR ||
  join(homedir(), ".gemini", "antigravity");
const STATE_DIR = join(APP_DATA_DIR, "live-context-state");
mkdirSync(STATE_DIR, { recursive: true });

const SETTINGS_FILE = join(STATE_DIR, "settings.json");
const SNAPSHOT_FILE = join(STATE_DIR, "snapshot.json");
const VERDICTS_FILE = join(STATE_DIR, "verdicts.jsonl");

const app = new SidecarApp();
const readLocal = (name) => readFileSync(join(HERE, name), "utf8");

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

function loadSettings() {
  try {
    const raw = JSON.parse(readFileSync(SETTINGS_FILE, "utf8"));
    return {
      injectGit: raw.injectGit !== false,
      injectGitHub: raw.injectGitHub !== false,
      injectContract: raw.injectContract !== false,
      mode: raw.mode === "enforce" ? "enforce" : "log",
      repo: String(raw.repo || "VitruvianSoftware/vitruvian-core"),
      minChars: Math.max(50, Number(raw.minChars ?? 300)),
      contractText: String(raw.contractText ?? DEFAULT_RESPONSE_CONTRACT),
    };
  } catch {
    const defaults = {
      injectGit: true,
      injectGitHub: true,
      injectContract: true,
      mode: "log",
      repo: "VitruvianSoftware/vitruvian-core",
      minChars: 300,
      contractText: DEFAULT_RESPONSE_CONTRACT,
    };
    writeFileSync(
      SETTINGS_FILE,
      JSON.stringify(defaults, null, 2) + "\n",
      "utf8",
    );
    return defaults;
  }
}

function saveSettings(patch = {}) {
  const current = loadSettings();
  const next = {
    injectGit:
      patch.injectGit !== undefined
        ? Boolean(patch.injectGit)
        : current.injectGit,
    injectGitHub:
      patch.injectGitHub !== undefined
        ? Boolean(patch.injectGitHub)
        : current.injectGitHub,
    injectContract:
      patch.injectContract !== undefined
        ? Boolean(patch.injectContract)
        : current.injectContract,
    mode:
      patch.mode !== undefined
        ? patch.mode === "enforce"
          ? "enforce"
          : "log"
        : current.mode,
    repo:
      patch.repo !== undefined
        ? String(patch.repo).trim() || current.repo
        : current.repo,
    minChars:
      patch.minChars !== undefined
        ? Math.max(50, Number(patch.minChars))
        : current.minChars,
    contractText:
      patch.contractText !== undefined
        ? String(patch.contractText)
        : current.contractText,
  };
  writeFileSync(SETTINGS_FILE, JSON.stringify(next, null, 2) + "\n", "utf8");
  return next;
}

function loadSnapshot() {
  try {
    return JSON.parse(readFileSync(SNAPSHOT_FILE, "utf8"));
  } catch {
    return {
      updatedAt: 0,
      git: { branch: "main", headSha: "", dirtyCount: 0, dirtyFiles: [] },
      github: {
        repo: loadSettings().repo,
        openPrs: [],
        mergedPrs: [],
        openIssues: 0,
      },
    };
  }
}

function loadVerdicts() {
  if (!existsSync(VERDICTS_FILE)) return [];
  try {
    return readFileSync(VERDICTS_FILE, "utf8")
      .trim()
      .split(/\r?\n/)
      .filter(Boolean)
      .slice(-30)
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean)
      .reverse();
  } catch {
    return [];
  }
}

let refreshBusy = false;

async function refreshSnapshot() {
  if (refreshBusy) return loadSnapshot();
  refreshBusy = true;
  const settings = loadSettings();
  const git = { branch: "", headSha: "", dirtyCount: 0, dirtyFiles: [] };
  const github = {
    repo: settings.repo,
    openPrs: [],
    mergedPrs: [],
    openIssues: 0,
  };

  try {
    const [branchOut, shaOut, statusOut] = await Promise.all([
      execFileAsync("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
        timeout: 4000,
      }).catch(() => ({ stdout: "" })),
      execFileAsync("git", ["rev-parse", "--short", "HEAD"], {
        timeout: 4000,
      }).catch(() => ({ stdout: "" })),
      execFileAsync("git", ["status", "--porcelain"], {
        timeout: 4000,
      }).catch(() => ({ stdout: "" })),
    ]);
    git.branch = branchOut.stdout.trim();
    git.headSha = shaOut.stdout.trim();
    // Porcelain lines are "XY path": the path starts at column 3, so the
    // status must not be trimmed first (" M a" would lose the "a").
    const statusLines = statusOut.stdout.split(/\r?\n/).filter((l) => l.trim());
    git.dirtyCount = statusLines.length;
    git.dirtyFiles = statusLines.slice(0, 8).map((l) => l.slice(3).trim());
  } catch {
    // ignore git probe errors
  }

  try {
    const [openOut, mergedOut, issuesOut] = await Promise.all([
      execFileAsync(
        "gh",
        [
          "pr",
          "list",
          "--repo",
          settings.repo,
          "--state",
          "open",
          "--limit",
          "20",
          "--json",
          "number,title,isDraft",
        ],
        { timeout: 10000 },
      ),
      execFileAsync(
        "gh",
        [
          "pr",
          "list",
          "--repo",
          settings.repo,
          "--state",
          "merged",
          "--limit",
          "10",
          "--json",
          "number,title,mergedAt",
        ],
        { timeout: 10000 },
      ),
      execFileAsync(
        "gh",
        [
          "issue",
          "list",
          "--repo",
          settings.repo,
          "--state",
          "open",
          "--limit",
          "100",
          "--json",
          "number",
        ],
        { timeout: 10000 },
      ),
    ]);
    github.openPrs = JSON.parse(openOut.stdout || "[]");
    github.mergedPrs = JSON.parse(mergedOut.stdout || "[]");
    github.openIssues = JSON.parse(issuesOut.stdout || "[]").length;
  } catch {
    github.unavailable = true;
  }

  const next = {
    updatedAt: Date.now(),
    git,
    github,
  };
  try {
    writeFileSync(SNAPSHOT_FILE, JSON.stringify(next, null, 2) + "\n", "utf8");
  } catch {
    // ignore write failure
  }
  refreshBusy = false;
  return next;
}

function buildState() {
  const settings = loadSettings();
  const snapshot = loadSnapshot();
  const verdicts = loadVerdicts();
  const preview = buildEphemeralContextPayload({
    git: snapshot.git,
    github: snapshot.github,
    settings,
  });
  return {
    version: VERSION,
    settings,
    snapshot,
    verdicts,
    previewMessage: preview.injectSteps?.[0]?.ephemeralMessage ?? "",
  };
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
    const dsl = toOpenUILang(buildState());
    return { dsl, parsed: parseOpenUILang(dsl) };
  },
  "GET",
);

app.api("/api/settings", (data = {}) => {
  saveSettings(data);
  const state = buildState();
  return { ...state, openuiDsl: toOpenUILang(state) };
});

app.api("/api/refresh", async () => {
  await refreshSnapshot();
  const state = buildState();
  return { ...state, openuiDsl: toOpenUILang(state) };
});

refreshSnapshot();
setInterval(refreshSnapshot, 60_000);
app.run();
