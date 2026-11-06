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

// Backend for the security-guidance panel. Antigravity starts this file with
// Node.js (see sidecar.json) and keeps it running while the plugin is enabled.

import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Response, SidecarApp } from "sidecar_sdk";

import {
  BUILTIN_PATTERNS,
  scanContentForPatterns,
  scanDiffForVulnerabilities,
  summariseSecurityState,
} from "./lib/core.mjs";
import { parseOpenUILang, toOpenUILang } from "./lib/openui.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const APP_DIR =
  process.env.ANTIGRAVITY_APP_DATA_DIR ||
  join(homedir(), ".gemini", "antigravity");
const STATE_FILE = join(APP_DIR, "security-guidance-state.json");

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

function loadStore() {
  if (!existsSync(STATE_FILE)) {
    return { findings: [], suppressions: [] };
  }
  try {
    const parsed = JSON.parse(readFileSync(STATE_FILE, "utf8"));
    return {
      findings: Array.isArray(parsed?.findings) ? parsed.findings : [],
      suppressions: Array.isArray(parsed?.suppressions)
        ? parsed.suppressions
        : [],
    };
  } catch {
    return { findings: [], suppressions: [] };
  }
}

function saveStore(store) {
  mkdirSync(dirname(STATE_FILE), { recursive: true });
  const tmp = `${STATE_FILE}.tmp`;
  writeFileSync(tmp, JSON.stringify(store, null, 2) + "\n", "utf8");
  renameSync(tmp, STATE_FILE);
}

function buildState() {
  const store = loadStore();
  const summary = summariseSecurityState(store);
  return {
    version: VERSION,
    findings: summary.activeFindings,
    suppressions: store.suppressions,
    summary,
    patterns: BUILTIN_PATTERNS.map((p) => ({
      id: p.id,
      category: p.category,
      severity: p.severity,
      cwe: p.cwe,
      message: p.message,
      remediation: p.remediation,
    })),
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

// POST /api/scan {content, filePath, isDiff?, record?, conversationId?}
app.api("/api/scan", (data) => {
  const content = String(data?.content ?? "");
  const filePath = String(data?.filePath || "<ad-hoc>");
  const isDiff = data?.isDiff === true || content.startsWith("--- ");
  const findings = isDiff
    ? scanDiffForVulnerabilities(content)
    : scanContentForPatterns(content, { filePath });

  if (data?.record === true && findings.length > 0) {
    const store = loadStore();
    const byId = new Map();
    for (const item of [...findings, ...store.findings]) {
      if (item && item.id && !byId.has(item.id)) byId.set(item.id, item);
    }
    store.findings = [...byId.values()].slice(0, 200);
    saveStore(store);
  }
  return { findings };
});

// POST /api/suppress {id}
app.api("/api/suppress", (data) => {
  const id = String(data?.id ?? "").trim();
  if (!id) return fail("Finding id or ruleId is required");
  const store = loadStore();
  if (!store.suppressions.includes(id)) {
    store.suppressions.push(id);
    saveStore(store);
  }
  return { suppressions: store.suppressions };
});

// POST /api/unsuppress {id}
app.api("/api/unsuppress", (data) => {
  const id = String(data?.id ?? "").trim();
  const store = loadStore();
  store.suppressions = store.suppressions.filter((s) => s !== id);
  saveStore(store);
  return { suppressions: store.suppressions };
});

// POST /api/clear
app.api("/api/clear", () => {
  const store = loadStore();
  store.findings = [];
  saveStore(store);
  return { ok: true };
});

// POST /api/wake-now {id, conversationId}
app.api("/api/wake-now", async (data) => {
  const store = loadStore();
  const finding = store.findings.find((f) => f.id === data?.id);
  if (!finding) return fail("Finding not found", 404);
  const conversationId = String(
    data?.conversationId || finding.conversationId || "",
  ).trim();
  if (!conversationId) {
    return fail("Open the panel from a conversation to wake the agent");
  }
  const msg = `[security-guidance] Please remediate ${finding.severity.toUpperCase()} finding '${finding.ruleId}' (${finding.cwe}) at ${finding.filePath}:${finding.line}:\n- Issue: ${finding.message}\n- Remediation: ${finding.remediation}`;
  await app.sendMessage(conversationId, msg, {});
  return { ok: true };
});

app.run();
