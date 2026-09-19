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

import { spawn } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";
import {
  getPersistedSession,
  setPersistedSession,
  deletePersistedSession,
  hasPersistedSession,
} from "./sessions.js";

// ─── Antigravity CLI (agy) ───────────────────────────────────────────────────
//
// Google retired Gemini CLI for individual accounts in favour of the
// Antigravity CLI (`agy`). Everything below drives `agy -p` in print mode:
//
//   agy -p "<prompt>" --output-format json|stream-json
//       [--dangerously-skip-permissions | --mode accept-edits|plan]
//       [--model <name>] [--effort low|medium|high] [--sandbox]
//       [--conversation <id>]
//
// stream-json emits one JSON object per line:
//   {"event":"init","conversation_id":...}
//   {"event":"step_update","step_update":{"step_type":"agent_response","text_delta":"..."}}
//   {"event":"step_update","step_update":{"step_type":"tool","tool_name":"..."}}
//   {"event":"result","result":{"conversation_id":...,"status":"SUCCESS|ERROR","response":"...","error":"..."}}
// json emits the `result` object alone.

/** @type {Map<number, object>} chatId -> per-chat settings overrides */
const chatSettings = new Map();

/** @type {Map<number, { proc: ChildProcess, startTime: number, prompt: string }>} chatId -> active process */
const runningProcesses = new Map();

/** @type {Map<number, string[]>} chatId -> conversation ids from the last /sessions listing, by index */
const lastSessionListing = new Map();

/** Env var with an AGY_ name, falling back to the pre-migration GEMINI_ name. */
function envCompat(name, fallback) {
  return process.env[`AGY_${name}`] ?? process.env[`GEMINI_${name}`] ?? fallback;
}

/**
 * Locate the agy binary. GUI-launched processes get a minimal PATH, so the
 * usual install locations are checked explicitly before falling back to PATH.
 * @returns {string}
 */
export function resolveAgyBinary() {
  const explicit = envCompat("BIN", "");
  if (explicit) return explicit;
  const home = os.homedir();
  for (const candidate of [
    path.join(home, ".local/bin/agy"),
    "/opt/homebrew/bin/agy",
    "/usr/local/bin/agy",
  ]) {
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch {
      /* next */
    }
  }
  return "agy";
}

const AGY_BIN = resolveAgyBinary();
const WORKING_DIR = envCompat("WORKING_DIR", process.cwd());
const TIMEOUT_MS = parseInt(envCompat("TIMEOUT_MS", "300000"), 10);
const APPROVAL_MODE = envCompat("APPROVAL_MODE", "yolo");
const MODEL = envCompat("MODEL", "");
const EFFORT = process.env.AGY_EFFORT || "";
// Legacy toggle: GEMINI_THINKING=true meant "deep reasoning"; that is agy's --effort high.
const THINKING = envCompat("THINKING", "") === "true";
const CLI_PROVIDER = (process.env.CLI_PROVIDER || "agy").replace(/^gemini$/, "agy");
const CLI_COMMAND_TEMPLATE = process.env.CLI_COMMAND_TEMPLATE || "";

/**
 * Translate an approval mode into agy flags. Accepts the old Gemini names
 * (`auto_edit`) as well as agy's own (`accept-edits`).
 * @param {string} mode
 * @returns {string[]}
 */
export function approvalArgs(mode) {
  switch ((mode || "").toLowerCase()) {
    case "yolo":
      return ["--dangerously-skip-permissions"];
    case "auto_edit":
    case "accept-edits":
    case "accept_edits":
      return ["--mode", "accept-edits"];
    case "plan":
      return ["--mode", "plan"];
    default:
      return [];
  }
}

/**
 * Build the argv for one `agy -p` run.
 * @param {string} prompt
 * @param {object} settings
 * @param {"json"|"stream-json"} format
 * @param {string|undefined} conversationId
 * @returns {string[]}
 */
export function buildAgyArgs(prompt, settings, format, conversationId) {
  const args = ["-p", prompt, "--output-format", format, ...approvalArgs(settings.approvalMode)];
  if (settings.model) args.push("--model", settings.model);
  const effort = settings.effort || (settings.thinking ? "high" : "");
  if (effort) args.push("--effort", effort);
  if (settings.sandbox) args.push("--sandbox");
  if (conversationId) args.push("--conversation", conversationId);
  return args;
}

/**
 * Parse a provider command template into [executable, ...args] by tokenising
 * the string and substituting {prompt} and {model} as verbatim literal values.
 * Supports single and double-quoted tokens. Never passes through a shell.
 * @param {string} template - Command template string
 * @param {string} prompt - User's prompt to substitute
 * @param {string} model - Active model name to substitute
 * @returns {{ bin: string, args: string[] } | null}
 */
function buildProviderArgs(template, prompt, model) {
  const tokens = [];
  let current = "";
  let inSingle = false;
  let inDouble = false;

  for (const c of template) {
    if (c === "'" && !inDouble) {
      inSingle = !inSingle;
    } else if (c === '"' && !inSingle) {
      inDouble = !inDouble;
    } else if (c === " " && !inSingle && !inDouble) {
      if (current) {
        tokens.push(current);
        current = "";
      }
    } else {
      current += c;
    }
  }
  if (current) tokens.push(current);
  if (!tokens.length) return null;

  const activeModel = model || "gemma4:31b-cloud";
  const resolved = tokens.map((t) =>
    t.replaceAll("{prompt}", prompt).replaceAll("{model}", activeModel),
  );
  return { bin: resolved[0], args: resolved.slice(1) };
}

/**
 * Get effective settings for a chat (merges defaults with per-chat overrides).
 * @param {number} chatId
 * @returns {object}
 */
function getEffectiveSettings(chatId) {
  const overrides = chatSettings.get(chatId) || {};
  return {
    workingDir: overrides.workingDir || WORKING_DIR,
    model: overrides.model || MODEL,
    approvalMode: overrides.approvalMode || APPROVAL_MODE,
    sandbox: overrides.sandbox || false,
    thinking: overrides.thinking ?? THINKING,
    effort: overrides.effort || EFFORT,
  };
}

/**
 * Get per-chat settings (for display).
 * @param {number} chatId
 * @returns {object}
 */
export function getChatSettings(chatId) {
  return getEffectiveSettings(chatId);
}

/**
 * Update a per-chat setting.
 * @param {number} chatId
 * @param {string} key
 * @param {*} value
 */
export function setChatSetting(chatId, key, value) {
  const current = chatSettings.get(chatId) || {};
  current[key] = value;
  chatSettings.set(chatId, current);
}

function defaultSettings() {
  return {
    workingDir: WORKING_DIR,
    model: MODEL,
    approvalMode: APPROVAL_MODE,
    sandbox: false,
    thinking: THINKING,
    effort: EFFORT,
  };
}

/**
 * Interpret a `result` object from agy. Throws on an ERROR status so the
 * caller can surface it; clears a stale conversation when agy says it is gone.
 * @param {object} result
 * @param {number|undefined} chatId
 */
function handleResult(result, chatId) {
  const status = String(result.status || "").toUpperCase();
  if (status === "ERROR") {
    const message = result.error || "agy reported an error";
    if (/conversation/i.test(message) && /not found|unknown|invalid|no such/i.test(message)) {
      if (chatId) deletePersistedSession(chatId);
      throw new Error(
        "Conversation expired or was deleted. Send your message again to start a new one.",
      );
    }
    throw new Error(message);
  }
}

/**
 * Execute a prompt through agy in headless mode.
 * @param {string} prompt - The user's message
 * @param {object} options
 * @param {number} [options.chatId] - Telegram chat ID for session tracking
 * @returns {Promise<{ text: string, sessionId?: string }>}
 */
export async function executePrompt(prompt, { chatId } = {}) {
  const settings = chatId ? getEffectiveSettings(chatId) : defaultSettings();

  // ── Custom provider path ──────────────────────────────────────────────────
  if (CLI_PROVIDER !== "agy" && CLI_COMMAND_TEMPLATE) {
    const parsed = buildProviderArgs(CLI_COMMAND_TEMPLATE, prompt, settings.model);
    if (!parsed) throw new Error(`Invalid CLI_COMMAND_TEMPLATE: ${CLI_COMMAND_TEMPLATE}`);

    return new Promise((resolve, reject) => {
      const chunks = [];
      const errChunks = [];

      const proc = spawn(parsed.bin, parsed.args, {
        cwd: settings.workingDir,
        timeout: TIMEOUT_MS,
        shell: false,
        env: { ...process.env, NO_COLOR: "1" },
      });

      if (chatId)
        runningProcesses.set(chatId, { proc, startTime: Date.now(), prompt: prompt.slice(0, 100) });

      proc.stdout.on("data", (data) => chunks.push(data));
      proc.stderr.on("data", (data) => errChunks.push(data));

      proc.on("close", (code) => {
        if (chatId) runningProcesses.delete(chatId);
        const stdout = Buffer.concat(chunks).toString("utf-8").trim();
        const stderr = Buffer.concat(errChunks).toString("utf-8").trim();
        if (code !== 0 && !stdout) {
          reject(new Error(`Provider exited with code ${code}: ${stderr || "unknown error"}`));
          return;
        }
        // Plain text — no session tracking for custom providers
        resolve({ text: stdout || stderr || "No response from provider." });
      });

      proc.on("error", (err) => {
        if (chatId) runningProcesses.delete(chatId);
        reject(new Error(`Failed to start provider: ${err.message}`));
      });
    });
  }

  // ── agy path ──────────────────────────────────────────────────────────────
  const existingSession = chatId ? getPersistedSession(chatId) : null;
  const args = buildAgyArgs(prompt, settings, "json", existingSession || undefined);

  return new Promise((resolve, reject) => {
    const chunks = [];
    const errChunks = [];
    const timeout = settings.thinking || settings.effort === "high" ? Math.max(TIMEOUT_MS, 600000) : TIMEOUT_MS;

    const proc = spawn(AGY_BIN, args, {
      cwd: settings.workingDir,
      timeout,
      env: { ...process.env, NO_COLOR: "1" },
    });

    if (chatId) {
      runningProcesses.set(chatId, { proc, startTime: Date.now(), prompt: prompt.slice(0, 100) });
    }

    proc.stdout.on("data", (data) => chunks.push(data));
    proc.stderr.on("data", (data) => errChunks.push(data));

    proc.on("close", (code) => {
      if (chatId) runningProcesses.delete(chatId);
      const stdout = Buffer.concat(chunks).toString("utf-8").trim();
      const stderr = Buffer.concat(errChunks).toString("utf-8").trim();

      if (code !== 0 && !stdout) {
        reject(new Error(`agy exited with code ${code}: ${cleanCliOutput(stderr) || "unknown error"}`));
        return;
      }

      try {
        const result = parseAgyOutput(stdout);
        handleResult(result.raw, chatId);
        if (result.sessionId && chatId) setPersistedSession(chatId, result.sessionId);
        resolve({ text: result.text, sessionId: result.sessionId });
      } catch (err) {
        if (err instanceof SyntaxError) {
          // Not JSON at all — hand back whatever agy printed.
          resolve({ text: stdout || stderr || "No response from agy." });
        } else {
          reject(err);
        }
      }
    });

    proc.on("error", (err) => {
      if (chatId) runningProcesses.delete(chatId);
      reject(new Error(`Failed to start agy: ${err.message}`));
    });
  });
}

/**
 * Execute a prompt with streaming output — calls onChunk as text arrives.
 * @param {string} prompt - The user's message
 * @param {object} options
 * @param {number} [options.chatId] - Telegram chat ID for session tracking
 * @param {function} [options.onChunk] - Called with accumulated text on each delta
 * @returns {Promise<{ text: string, sessionId?: string, timedOut?: boolean }>}
 */
export async function executePromptStreaming(prompt, { chatId, onChunk } = {}) {
  const settings = chatId ? getEffectiveSettings(chatId) : defaultSettings();

  // ── Custom provider path ──────────────────────────────────────────────────
  if (CLI_PROVIDER !== "agy" && CLI_COMMAND_TEMPLATE) {
    const parsed = buildProviderArgs(CLI_COMMAND_TEMPLATE, prompt, settings.model);
    if (!parsed) throw new Error(`Invalid CLI_COMMAND_TEMPLATE: ${CLI_COMMAND_TEMPLATE}`);

    return new Promise((resolve, reject) => {
      let accumulatedText = "";
      const errChunks = [];

      const proc = spawn(parsed.bin, parsed.args, {
        cwd: settings.workingDir,
        timeout: TIMEOUT_MS,
        shell: false,
        env: { ...process.env, NO_COLOR: "1" },
      });

      if (chatId)
        runningProcesses.set(chatId, { proc, startTime: Date.now(), prompt: prompt.slice(0, 100) });

      proc.stdout.on("data", (data) => {
        accumulatedText += data.toString("utf-8");
        if (onChunk) onChunk(accumulatedText);
      });

      proc.stderr.on("data", (data) => errChunks.push(data));

      proc.on("close", (code) => {
        if (chatId) runningProcesses.delete(chatId);
        const stderr = Buffer.concat(errChunks).toString("utf-8").trim();
        if (code !== 0 && !accumulatedText) {
          reject(new Error(`Provider exited with code ${code}: ${stderr || "unknown error"}`));
          return;
        }
        resolve({ text: accumulatedText || "No response from provider." });
      });

      proc.on("error", (err) => {
        if (chatId) runningProcesses.delete(chatId);
        reject(new Error(`Failed to start provider: ${err.message}`));
      });
    });
  }

  // ── agy path ──────────────────────────────────────────────────────────────
  const existingSession = chatId ? getPersistedSession(chatId) : null;
  const args = buildAgyArgs(prompt, settings, "stream-json", existingSession || undefined);

  return new Promise((resolve, reject) => {
    let accumulatedText = "";
    let finalText;
    let sessionId;
    let finalResult;
    let timedOut = false;
    const errChunks = [];
    let lineBuffer = "";

    const timeout = settings.thinking || settings.effort === "high" ? Math.max(TIMEOUT_MS, 600000) : TIMEOUT_MS;

    const proc = spawn(AGY_BIN, args, {
      cwd: settings.workingDir,
      env: { ...process.env, NO_COLOR: "1" },
    });

    // Manual timeout so we can capture partial output
    const timeoutHandle = setTimeout(() => {
      timedOut = true;
      proc.kill("SIGTERM");
    }, timeout);

    if (chatId) {
      runningProcesses.set(chatId, { proc, startTime: Date.now(), prompt: prompt.slice(0, 100) });
    }

    const consume = (line) => {
      const update = parseStreamLine(line);
      if (!update) return;
      if (update.sessionId) sessionId = update.sessionId;
      if (update.delta) {
        accumulatedText += update.delta;
        if (onChunk) onChunk(accumulatedText);
      }
      if (update.result) {
        finalResult = update.result;
        if (typeof update.result.response === "string" && update.result.response) {
          finalText = update.result.response;
        }
      }
    };

    proc.stdout.on("data", (data) => {
      lineBuffer += data.toString("utf-8");
      const lines = lineBuffer.split("\n");
      lineBuffer = lines.pop() || ""; // keep incomplete last line in buffer
      for (const line of lines) consume(line);
    });

    proc.stderr.on("data", (data) => errChunks.push(data));

    proc.on("close", (code) => {
      clearTimeout(timeoutHandle);
      if (chatId) runningProcesses.delete(chatId);
      if (lineBuffer.trim()) consume(lineBuffer);

      try {
        if (finalResult) handleResult(finalResult, chatId);
      } catch (err) {
        reject(err);
        return;
      }

      const text = finalText || accumulatedText;
      if (!text && code !== 0 && !timedOut) {
        const stderr = Buffer.concat(errChunks).toString("utf-8").trim();
        reject(new Error(`agy exited with code ${code}: ${cleanCliOutput(stderr) || "unknown error"}`));
        return;
      }

      if (sessionId && chatId) setPersistedSession(chatId, sessionId);

      resolve({ text: text || "No response from agy.", sessionId, timedOut });
    });

    proc.on("error", (err) => {
      clearTimeout(timeoutHandle);
      if (chatId) runningProcesses.delete(chatId);
      reject(new Error(`Failed to start agy: ${err.message}`));
    });
  });
}

/**
 * Cancel a running prompt for a given chat ID.
 * @param {number} chatId
 * @returns {boolean} - True if a process was found and killed, false otherwise.
 */
export function cancelPrompt(chatId) {
  const running = runningProcesses.get(chatId);
  if (running) {
    running.proc.kill("SIGTERM");
    runningProcesses.delete(chatId);
    return true;
  }
  return false;
}

/**
 * Get information about a running prompt for a given chat ID.
 * @param {number} chatId
 * @returns {{ startTime: number, prompt: string } | null}
 */
export function getRunningInfo(chatId) {
  const running = runningProcesses.get(chatId);
  if (running) {
    return { startTime: running.startTime, prompt: running.prompt };
  }
  return null;
}

/**
 * Run an agy subcommand (e.g. `mcp list`, `plugin list`). Returns the raw
 * text output.
 * @param {string[]} args - CLI arguments
 * @param {object} [options]
 * @param {string} [options.cwd] - Working directory
 * @returns {Promise<string>}
 */
export async function runCliCommand(args, { cwd } = {}) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    const errChunks = [];

    const proc = spawn(AGY_BIN, args, {
      cwd: cwd || WORKING_DIR,
      timeout: 30000,
      env: { ...process.env, NO_COLOR: "1" },
    });

    proc.stdout.on("data", (data) => chunks.push(data));
    proc.stderr.on("data", (data) => errChunks.push(data));

    proc.on("close", () => {
      const stdout = Buffer.concat(chunks).toString("utf-8").trim();
      const stderr = Buffer.concat(errChunks).toString("utf-8").trim();
      const cleanOutput = cleanCliOutput(stdout || stderr);
      resolve(cleanOutput || "Command completed (no output).");
    });

    proc.on("error", (err) => {
      reject(new Error(`Failed to run agy command: ${err.message}`));
    });
  });
}

/**
 * Clean CLI output by removing noise lines (telemetry, warnings, etc.)
 * @param {string} raw
 * @returns {string}
 */
function cleanCliOutput(raw) {
  const noisePatterns = [
    /^npm warn/i,
    /^Warning: Skipping/,
    /^Telemetry /,
    /^Loading plugin:/,
    /^Scheduling MCP context/,
    /^Executing MCP context/,
    /^MCP context refresh/,
    /^Registering notification/,
    /^Server '.+' (supports|has)/,
  ];

  return raw
    .split("\n")
    .filter((line) => !noisePatterns.some((p) => p.test(line.trim())))
    .join("\n")
    .trim();
}

// ─── Conversations (agy's session store) ─────────────────────────────────────
//
// agy keeps every conversation in ~/.gemini/antigravity/conversations/<id>.db
// (protobuf step payloads — not readable here) and an index of them in
// ~/.gemini/antigravity/conversation_summaries.db. The index is enough to list,
// resume (`--conversation <id>`) and delete.

const AGY_DATA_DIR = path.join(os.homedir(), ".gemini/antigravity");
const SUMMARIES_DB = path.join(AGY_DATA_DIR, "conversation_summaries.db");
const CONVERSATIONS_DIR = path.join(AGY_DATA_DIR, "conversations");

/**
 * @typedef {{ id: string, title: string, lastModified: Date, steps: number, workspaces: string[] }} Conversation
 */

/**
 * Read the conversation index. Only top-level conversations that belong to
 * `workingDir` (when given) are returned, newest first.
 * @param {string} [workingDir]
 * @returns {Promise<Conversation[]>}
 */
export async function listConversations(workingDir) {
  if (!fs.existsSync(SUMMARIES_DB)) return [];
  const { DatabaseSync } = await import("node:sqlite");
  const db = new DatabaseSync(SUMMARIES_DB, { readOnly: true });
  try {
    const rows = db
      .prepare(
        `SELECT conversation_id, title, preview, step_count, last_modified_time, workspace_uris
         FROM conversation_summaries
         WHERE nesting_depth = 0 AND killed = 0
         ORDER BY last_modified_time DESC LIMIT 200`,
      )
      .all();
    const wanted = workingDir ? `file://${path.resolve(workingDir)}` : null;
    return rows
      .map((r) => {
        let workspaces = [];
        try {
          workspaces = JSON.parse(String(r.workspace_uris || "[]"));
        } catch {
          /* ignore */
        }
        return {
          id: String(r.conversation_id),
          title: String(r.title || r.preview || "").split("\n")[0].slice(0, 80) || "(untitled)",
          lastModified: new Date(String(r.last_modified_time)),
          steps: Number(r.step_count || 0),
          workspaces,
        };
      })
      .filter((c) => !wanted || c.workspaces.length === 0 || c.workspaces.includes(wanted));
  } finally {
    db.close();
  }
}

function relativeTime(date) {
  const diff = Math.max(0, Date.now() - date.getTime());
  const m = Math.floor(diff / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.floor(h / 24)}d ago`;
}

/**
 * List available sessions as numbered lines ("1. title (2h ago)"). The
 * numbering is remembered per chat so /resume <n> can map back to an id.
 * @param {string} [cwd]
 * @param {number} [chatId]
 * @returns {Promise<string>}
 */
export async function listSessions(cwd, chatId) {
  const conversations = await listConversations(cwd);
  if (!conversations.length) return "No conversations yet for this workspace.";
  const shown = conversations.slice(0, 20);
  if (chatId) lastSessionListing.set(chatId, shown.map((c) => c.id));
  return shown
    .map((c, i) => `${i + 1}. ${c.title} (${relativeTime(c.lastModified)}, ${c.steps} steps)`)
    .join("\n");
}

/**
 * Resolve a user-facing session reference (index from the last listing,
 * "latest", or a conversation id) to a conversation id.
 * @param {number} chatId
 * @param {string} ref
 * @param {string} [cwd]
 * @returns {Promise<string|undefined>}
 */
export async function resolveSessionRef(chatId, ref, cwd) {
  const trimmed = String(ref || "").trim();
  if (!trimmed) return undefined;
  if (/^\d+$/.test(trimmed)) {
    let ids = lastSessionListing.get(chatId);
    if (!ids) {
      ids = (await listConversations(cwd)).slice(0, 20).map((c) => c.id);
      lastSessionListing.set(chatId, ids);
    }
    return ids[parseInt(trimmed, 10) - 1];
  }
  if (trimmed === "latest") {
    return (await listConversations(cwd))[0]?.id;
  }
  return trimmed;
}

/**
 * Delete a session by index (from the last listing) or conversation id.
 * Removes the index row and the conversation database files.
 * @param {string} ref
 * @param {string} [cwd]
 * @param {number} [chatId]
 * @returns {Promise<string>}
 */
export async function deleteSession(ref, cwd, chatId) {
  const id = await resolveSessionRef(chatId ?? 0, ref, cwd);
  if (!id) return `No session matches "${ref}". Use /sessions first.`;
  const { DatabaseSync } = await import("node:sqlite");
  const db = new DatabaseSync(SUMMARIES_DB);
  try {
    db.prepare("DELETE FROM conversation_summaries WHERE conversation_id = ?").run(id);
  } finally {
    db.close();
  }
  for (const suffix of [".db", ".db-wal", ".db-shm"]) {
    try {
      fs.rmSync(path.join(CONVERSATIONS_DIR, `${id}${suffix}`), { force: true });
    } catch {
      /* ignore */
    }
  }
  if (chatId) lastSessionListing.delete(chatId);
  return `Deleted conversation ${id.slice(0, 8)}…`;
}

/**
 * List MCP servers.
 * @returns {Promise<string>}
 */
export async function listMcpServers() {
  return runCliCommand(["mcp", "list"]);
}

/**
 * List installed agy plugins (the old /extensions command).
 * @returns {Promise<string>}
 */
export async function listExtensions() {
  return runCliCommand(["plugin", "list"]);
}

/**
 * List skills. agy has no `skills list` subcommand; skills are directories
 * under the customization roots, so they are read from disk.
 * @returns {Promise<string>}
 */
export async function listSkills() {
  const roots = [
    path.join(os.homedir(), ".gemini/config/skills"),
    path.join(os.homedir(), ".agents/skills"),
    path.join(WORKING_DIR, ".agents/skills"),
  ];
  const seen = new Set();
  const lines = [];
  for (const root of roots) {
    let entries = [];
    try {
      entries = fs.readdirSync(root, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      const name = e.name;
      if (seen.has(name) || name.startsWith(".")) continue;
      if (!fs.existsSync(path.join(root, name, "SKILL.md"))) continue;
      seen.add(name);
      lines.push(`• ${name}`);
    }
  }
  return lines.length ? lines.sort().join("\n") : "No skills found.";
}

/**
 * Resume a specific session by index, "latest", or conversation id.
 * @param {number} chatId
 * @param {string} sessionRef
 * @param {string} [cwd]
 */
export async function setSessionResume(chatId, sessionRef, cwd) {
  const id = await resolveSessionRef(chatId, sessionRef, cwd);
  if (!id) throw new Error(`No session matches "${sessionRef}". Use /sessions first.`);
  setPersistedSession(chatId, id);
  return id;
}

// ─── JSON Parsing ────────────────────────────────────────────────────────────

/**
 * Parse one stream-json line from agy.
 * @param {string} line
 * @returns {{ sessionId?: string, delta?: string, result?: object } | null}
 */
export function parseStreamLine(line) {
  const trimmed = line.trim();
  if (!trimmed) return null;
  let event;
  try {
    event = JSON.parse(trimmed);
  } catch {
    return null;
  }
  const out = {};
  if (event.conversation_id) out.sessionId = event.conversation_id;
  if (event.event === "step_update" && event.step_update) {
    const su = event.step_update;
    if (su.conversation_id) out.sessionId = su.conversation_id;
    if (su.step_type === "agent_response" && typeof su.text_delta === "string") {
      out.delta = su.text_delta;
    }
  }
  if (event.event === "result" && event.result) {
    out.result = event.result;
    if (event.result.conversation_id) out.sessionId = event.result.conversation_id;
  }
  return out;
}

/**
 * Parse agy `--output-format json` output.
 * @param {string} raw - Raw stdout from agy
 * @returns {{ text: string, sessionId?: string, raw: object }}
 */
export function parseAgyOutput(raw) {
  const data = JSON.parse(raw);
  const result = data.result && typeof data.result === "object" ? data.result : data;
  const sessionId = result.conversation_id || data.conversation_id;
  const text =
    typeof result.response === "string" && result.response
      ? result.response
      : result.error
        ? ""
        : JSON.stringify(result, null, 2);
  return { text: text || "No response.", sessionId, raw: result };
}

// ─── Session Helpers ─────────────────────────────────────────────────────────

/**
 * Clear session for a specific chat.
 * @param {number} chatId
 */
export function clearSession(chatId) {
  deletePersistedSession(chatId);
}

/**
 * Check if a session exists for a chat.
 * @param {number} chatId
 * @returns {boolean}
 */
export function hasSession(chatId) {
  return hasPersistedSession(chatId);
}

/**
 * Get session info for a chat.
 * @param {number} chatId
 * @returns {string|undefined}
 */
export function getSession(chatId) {
  return getPersistedSession(chatId);
}

// ─── Image Path Extraction ───────────────────────────────────────────────────

const IMAGE_EXTENSIONS = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".webp",
  ".gif",
  ".svg",
]);

/**
 * Scan response text for image file paths that exist on disk.
 * Looks for absolute paths and common artifact patterns.
 * @param {string} text - Response text from agy
 * @returns {string[]} Array of existing image file paths
 */
export function extractImagePaths(text) {
  const paths = new Set();

  // Match absolute file paths ending in image extensions
  // Handles: /path/to/image.png, `/path/to/image.png`, file:///path/to/image.png
  const pathRegex =
    /(?:file:\/\/)?(\/[^\s"'`<>]+\.(?:png|jpg|jpeg|webp|gif|svg))/gi;
  let match;
  while ((match = pathRegex.exec(text)) !== null) {
    let filePath = match[1];
    // Ensure absolute path
    if (filePath.startsWith("/")) {
      try {
        if (fs.existsSync(filePath)) {
          paths.add(filePath);
        }
      } catch {
        // Ignore invalid paths
      }
    }
  }

  return Array.from(paths);
}

const SENDABLE_FILE_EXTENSIONS = new Set([
  ".py",
  ".js",
  ".ts",
  ".jsx",
  ".tsx",
  ".json",
  ".md",
  ".txt",
  ".html",
  ".css",
  ".sh",
  ".yaml",
  ".yml",
  ".csv",
  ".pdf",
  ".xml",
  ".sql",
  ".go",
  ".rs",
  ".swift",
  ".java",
  ".c",
  ".cpp",
  ".h",
  ".rb",
  ".php",
  ".toml",
  ".conf",
  ".cfg",
  ".log",
]);

/**
 * Scan response text for code/document file paths that exist on disk.
 * Excludes image files (handled separately by extractImagePaths).
 * @param {string} text - Response text from agy
 * @returns {string[]} Array of existing file paths
 */
export function extractFilePaths(text) {
  const paths = new Set();

  // Match absolute file paths
  const pathRegex = /(?:file:\/\/)?(\/[^\s"'`<>]+\.\w+)/gi;
  let match;
  while ((match = pathRegex.exec(text)) !== null) {
    const filePath = match[1];
    if (!filePath.startsWith("/")) continue;

    const ext = filePath.substring(filePath.lastIndexOf(".")).toLowerCase();
    if (!SENDABLE_FILE_EXTENSIONS.has(ext)) continue;

    try {
      if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
        paths.add(filePath);
      }
    } catch {
      /* ignore */
    }
  }

  return Array.from(paths);
}
