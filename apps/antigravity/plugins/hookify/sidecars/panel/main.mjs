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

// Backend for the hookify panel. Antigravity starts this file with Node.js
// (see sidecar.json) and keeps it running while the plugin is enabled.

import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Response, SidecarApp } from "sidecar_sdk";

import {
  SUPPORTED_ACTIONS,
  SUPPORTED_OPERATORS,
  evaluatePreToolUse,
  evaluateStop,
  parseHookifyMarkdown,
  serializeHookifyMarkdown,
  summariseHookifyState,
} from "./lib/core.mjs";
import { parseOpenUILang, toOpenUILang } from "./lib/openui.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const APP_DIR =
  process.env.ANTIGRAVITY_APP_DATA_DIR ||
  join(homedir(), ".gemini", "antigravity");
const RULES_FILE = join(APP_DIR, "hookify-rules.json");
const EVENTS_FILE = join(APP_DIR, "hookify-events.json");

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

const fail = (message, status = 400) =>
  new Response(JSON.stringify({ error: message }), {
    contentType: "application/json",
    status,
  });

function loadGlobalRules() {
  if (!existsSync(RULES_FILE)) return [];
  try {
    const parsed = JSON.parse(readFileSync(RULES_FILE, "utf8"));
    return Array.isArray(parsed)
      ? parsed
      : Array.isArray(parsed?.rules)
        ? parsed.rules
        : [];
  } catch {
    return [];
  }
}

function saveGlobalRules(rules) {
  mkdirSync(dirname(RULES_FILE), { recursive: true });
  const tmp = `${RULES_FILE}.tmp`;
  writeFileSync(tmp, JSON.stringify({ rules }, null, 2) + "\n", "utf8");
  renameSync(tmp, RULES_FILE);
}

function loadWorkspaceRules(workspaceDir) {
  if (!workspaceDir) return [];
  const agentsDir = join(workspaceDir, ".agents");
  if (!existsSync(agentsDir)) return [];
  const list = [];
  try {
    for (const file of readdirSync(agentsDir).sort()) {
      if (/^hookify\..+\.md$/.test(file)) {
        const full = join(agentsDir, file);
        const parsed = parseHookifyMarkdown(readFileSync(full, "utf8"), full);
        if (parsed) list.push(parsed);
      }
    }
  } catch {
    // ignore unreadable workspace dir
  }
  return list;
}

function loadEvents() {
  if (!existsSync(EVENTS_FILE)) return [];
  try {
    const parsed = JSON.parse(readFileSync(EVENTS_FILE, "utf8"));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveEvents(events) {
  mkdirSync(dirname(EVENTS_FILE), { recursive: true });
  const tmp = `${EVENTS_FILE}.tmp`;
  writeFileSync(tmp, JSON.stringify(events, null, 2) + "\n", "utf8");
  renameSync(tmp, EVENTS_FILE);
}

let lastWorkspaceDir = process.cwd();

function buildState() {
  const globalRules = loadGlobalRules().map((r) => ({
    ...r,
    source: r.source || "global",
  }));
  const workspaceRules = loadWorkspaceRules(lastWorkspaceDir);
  const rules = [...workspaceRules, ...globalRules];
  const events = loadEvents();
  return {
    version: VERSION,
    rules,
    events,
    summary: summariseHookifyState({ rules, events }),
    operators: SUPPORTED_OPERATORS,
    actions: SUPPORTED_ACTIONS,
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

// POST /api/rules: create or update a global rule (or markdown rule).
app.api("/api/rules", (data) => {
  const name = String(data?.name ?? "").trim();
  if (!name) return fail("Rule name is required");
  const rule = {
    id: name,
    name,
    enabled: data.enabled !== false,
    event: String(data.event || "PreToolUse"),
    tool: String(data.tool || "*"),
    action: String(data.action || "warn"),
    conditions: Array.isArray(data.conditions)
      ? data.conditions
      : [
          {
            field: String(data.field || "CommandLine"),
            operator: String(data.operator || "regex_match"),
            pattern: String(data.pattern || ""),
          },
        ],
    overwrite:
      data.overwrite && typeof data.overwrite === "object"
        ? data.overwrite
        : undefined,
    message: String(data.message || `Rule '${name}' triggered.`),
    source: "global",
  };

  const current = loadGlobalRules().filter((r) => (r.id || r.name) !== rule.id);
  current.unshift(rule);
  saveGlobalRules(current);
  return { rule, markdownPreview: serializeHookifyMarkdown(rule) };
});

// POST /api/rules/toggle {id, enabled}
app.api("/api/rules/toggle", (data) => {
  const id = String(data?.id ?? "").trim();
  if (!id) return fail("Rule id is required");
  const current = loadGlobalRules();
  const idx = current.findIndex((r) => (r.id || r.name) === id);
  if (idx === -1)
    return fail("Only global rules can be toggled from the panel", 404);
  current[idx] = { ...current[idx], enabled: data.enabled === true };
  saveGlobalRules(current);
  return { rule: current[idx] };
});

// POST /api/rules/delete {id}
app.api("/api/rules/delete", (data) => {
  const id = String(data?.id ?? "").trim();
  if (!id) return fail("Rule id is required");
  const current = loadGlobalRules();
  const next = current.filter((r) => (r.id || r.name) !== id);
  saveGlobalRules(next);
  return { ok: true };
});

// POST /api/test {event, tool, CommandLine, Path, Content, reason}
app.api("/api/test", (data) => {
  const state = buildState();
  const isStop = String(data?.event || "PreToolUse") === "Stop";
  const payload = isStop
    ? {
        hook_event_name: "Stop",
        reason: String(data?.reason ?? data?.CommandLine ?? ""),
      }
    : {
        toolCall: {
          name: String(data?.tool || "run_command"),
          args: {
            CommandLine: String(data?.CommandLine ?? ""),
            Path: String(data?.Path ?? ""),
            Content: String(data?.Content ?? ""),
          },
        },
      };
  const result = isStop
    ? evaluateStop(state.rules, payload)
    : evaluatePreToolUse(state.rules, payload);
  return { result };
});

// POST /api/events/clear
app.api("/api/events/clear", () => {
  saveEvents([]);
  return { ok: true };
});

app.run();
