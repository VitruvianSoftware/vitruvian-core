import { spawn } from 'child_process';
import {
  getPersistedSession, setPersistedSession, deletePersistedSession, hasPersistedSession,
} from './sessions.js';

/** @type {Map<number, object>} chatId -> per-chat settings overrides */
const chatSettings = new Map();

/** @type {Map<number, { proc: ChildProcess, startTime: number, prompt: string }>} chatId -> active process */
const runningProcesses = new Map();

const GEMINI_BIN = process.env.GEMINI_BIN || '/opt/homebrew/bin/gemini';
const WORKING_DIR = process.env.GEMINI_WORKING_DIR || process.cwd();
const TIMEOUT_MS = parseInt(process.env.GEMINI_TIMEOUT_MS || '300000', 10);
const APPROVAL_MODE = process.env.GEMINI_APPROVAL_MODE || 'yolo';
const MODEL = process.env.GEMINI_MODEL || '';
const THINKING = process.env.GEMINI_THINKING === 'true';
const CLI_PROVIDER = process.env.CLI_PROVIDER || 'gemini';
const CLI_COMMAND_TEMPLATE = process.env.CLI_COMMAND_TEMPLATE || '';

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
  let current = '';
  let inSingle = false;
  let inDouble = false;

  for (const c of template) {
    if (c === "'" && !inDouble) {
      inSingle = !inSingle;
    } else if (c === '"' && !inSingle) {
      inDouble = !inDouble;
    } else if (c === ' ' && !inSingle && !inDouble) {
      if (current) { tokens.push(current); current = ''; }
    } else {
      current += c;
    }
  }
  if (current) tokens.push(current);
  if (!tokens.length) return null;

  const activeModel = model || 'gemma4:31b-cloud';
  const resolved = tokens.map((t) => t
    .replaceAll('{prompt}', prompt)
    .replaceAll('{model}', activeModel),
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

/**
 * Execute a prompt through Gemini CLI in headless mode.
 * @param {string} prompt - The user's message
 * @param {object} options
 * @param {number} [options.chatId] - Telegram chat ID for session tracking
 * @returns {Promise<{ text: string, sessionId?: string }>}
 */
export async function executePrompt(prompt, { chatId } = {}) {
  const settings = chatId ? getEffectiveSettings(chatId) : {
    workingDir: WORKING_DIR, model: MODEL, approvalMode: APPROVAL_MODE, sandbox: false, thinking: THINKING,
  };

  // ── Custom provider path ──────────────────────────────────────────────────
  if (CLI_PROVIDER !== 'gemini' && CLI_COMMAND_TEMPLATE) {
    const parsed = buildProviderArgs(CLI_COMMAND_TEMPLATE, prompt, settings.model);
    if (!parsed) throw new Error(`Invalid CLI_COMMAND_TEMPLATE: ${CLI_COMMAND_TEMPLATE}`);

    return new Promise((resolve, reject) => {
      const chunks = [];
      const errChunks = [];
      const timeout = TIMEOUT_MS;

      const proc = spawn(parsed.bin, parsed.args, {
        cwd: settings.workingDir,
        timeout,
        shell: false,
        env: { ...process.env, NO_COLOR: '1' },
      });

      if (chatId) runningProcesses.set(chatId, { proc, startTime: Date.now(), prompt: prompt.slice(0, 100) });

      proc.stdout.on('data', (data) => chunks.push(data));
      proc.stderr.on('data', (data) => errChunks.push(data));

      proc.on('close', (code) => {
        if (chatId) runningProcesses.delete(chatId);
        const stdout = Buffer.concat(chunks).toString('utf-8').trim();
        const stderr = Buffer.concat(errChunks).toString('utf-8').trim();
        if (code !== 0 && !stdout) {
          reject(new Error(`Provider exited with code ${code}: ${stderr || 'unknown error'}`));
          return;
        }
        // Plain text — no session tracking for custom providers
        resolve({ text: stdout || stderr || 'No response from provider.' });
      });

      proc.on('error', (err) => {
        if (chatId) runningProcesses.delete(chatId);
        reject(new Error(`Failed to start provider: ${err.message}`));
      });
    });
  }

  // ── Gemini CLI path (unchanged) ───────────────────────────────────────────
  const args = [
    '-p', prompt,
    '--output-format', 'json',
    '--approval-mode', settings.approvalMode,
  ];

  if (settings.model) {
    args.push('-m', settings.model);
  }

  if (settings.sandbox) {
    args.push('--sandbox');
  }

  // Resume previous session if one exists for this chat
  const existingSession = chatId ? getPersistedSession(chatId) : null;
  if (existingSession) {
    args.push('-r', existingSession);
  }

  return new Promise((resolve, reject) => {
    const chunks = [];
    const errChunks = [];

    // Use longer timeout for thinking models (they can take minutes)
    const timeout = settings.thinking ? Math.max(TIMEOUT_MS, 600000) : TIMEOUT_MS;

    const proc = spawn(GEMINI_BIN, args, {
      cwd: settings.workingDir,
      timeout,
      env: { ...process.env, NO_COLOR: '1' },
    });

    // Track the running process so it can be cancelled
    if (chatId) {
      runningProcesses.set(chatId, {
        proc,
        startTime: Date.now(),
        prompt: prompt.slice(0, 100),
      });
    }

    proc.stdout.on('data', (data) => chunks.push(data));
    proc.stderr.on('data', (data) => errChunks.push(data));

    proc.on('close', (code) => {
      if (chatId) runningProcesses.delete(chatId);
      const stdout = Buffer.concat(chunks).toString('utf-8').trim();
      const stderr = Buffer.concat(errChunks).toString('utf-8').trim();

      if (code !== 0 && !stdout) {
        reject(new Error(`Gemini CLI exited with code ${code}: ${stderr || 'unknown error'}`));
        return;
      }

      try {
        const result = parseGeminiOutput(stdout);

        // Track session for continuity
        if (result.sessionId && chatId) {
          setPersistedSession(chatId, result.sessionId);
        }

        resolve(result);
      } catch (err) {
        // If JSON parsing fails, return raw stdout as text
        resolve({ text: stdout || stderr || 'No response from Gemini.' });
      }
    });

    proc.on('error', (err) => {
      if (chatId) runningProcesses.delete(chatId);
      reject(new Error(`Failed to start Gemini CLI: ${err.message}`));
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
  const settings = chatId ? getEffectiveSettings(chatId) : {
    workingDir: WORKING_DIR, model: MODEL, approvalMode: APPROVAL_MODE, sandbox: false, thinking: THINKING,
  };

  // ── Custom provider path ──────────────────────────────────────────────────
  if (CLI_PROVIDER !== 'gemini' && CLI_COMMAND_TEMPLATE) {
    const parsed = buildProviderArgs(CLI_COMMAND_TEMPLATE, prompt, settings.model);
    if (!parsed) throw new Error(`Invalid CLI_COMMAND_TEMPLATE: ${CLI_COMMAND_TEMPLATE}`);

    return new Promise((resolve, reject) => {
      let accumulatedText = '';
      const errChunks = [];

      const proc = spawn(parsed.bin, parsed.args, {
        cwd: settings.workingDir,
        timeout: TIMEOUT_MS,
        shell: false,
        env: { ...process.env, NO_COLOR: '1' },
      });

      if (chatId) runningProcesses.set(chatId, { proc, startTime: Date.now(), prompt: prompt.slice(0, 100) });

      proc.stdout.on('data', (data) => {
        const chunk = data.toString('utf-8');
        accumulatedText += chunk;
        if (onChunk) onChunk(accumulatedText);
      });

      proc.stderr.on('data', (data) => errChunks.push(data));

      proc.on('close', (code) => {
        if (chatId) runningProcesses.delete(chatId);
        const stderr = Buffer.concat(errChunks).toString('utf-8').trim();
        if (code !== 0 && !accumulatedText) {
          reject(new Error(`Provider exited with code ${code}: ${stderr || 'unknown error'}`));
          return;
        }
        resolve({ text: accumulatedText || 'No response from provider.' });
      });

      proc.on('error', (err) => {
        if (chatId) runningProcesses.delete(chatId);
        reject(new Error(`Failed to start provider: ${err.message}`));
      });
    });
  }

  // ── Gemini CLI path (unchanged) ───────────────────────────────────────────
  const args = [
    '-p', prompt,
    '--output-format', 'stream-json',
    '--approval-mode', settings.approvalMode,
  ];

  if (settings.model) args.push('-m', settings.model);
  if (settings.sandbox) args.push('--sandbox');

  const existingSession = chatId ? getPersistedSession(chatId) : null;
  if (existingSession) args.push('-r', existingSession);


  return new Promise((resolve, reject) => {
    let accumulatedText = '';
    let sessionId;
    let timedOut = false;
    const errChunks = [];
    let lineBuffer = '';

    const timeout = settings.thinking ? Math.max(TIMEOUT_MS, 600000) : TIMEOUT_MS;

    const proc = spawn(GEMINI_BIN, args, {
      cwd: settings.workingDir,
      env: { ...process.env, NO_COLOR: '1' },
    });

    // Manual timeout so we can capture partial output
    const timeoutHandle = setTimeout(() => {
      timedOut = true;
      proc.kill('SIGTERM');
    }, timeout);

    if (chatId) {
      runningProcesses.set(chatId, {
        proc,
        startTime: Date.now(),
        prompt: prompt.slice(0, 100),
      });
    }

    proc.stdout.on('data', (data) => {
      lineBuffer += data.toString('utf-8');
      const lines = lineBuffer.split('\n');
      lineBuffer = lines.pop() || ''; // keep incomplete last line in buffer

      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const event = JSON.parse(line);

          if (event.type === 'init' && event.session_id) {
            sessionId = event.session_id;
          }

          if (event.type === 'message' && event.role === 'assistant' && event.content) {
            accumulatedText += event.content;
            if (onChunk) onChunk(accumulatedText);
          }

          if (event.type === 'result' && event.session_id) {
            sessionId = event.session_id;
          }
        } catch {
          // Skip unparseable lines
        }
      }
    });

    proc.stderr.on('data', (data) => errChunks.push(data));

    proc.on('close', (code) => {
      clearTimeout(timeoutHandle);
      if (chatId) runningProcesses.delete(chatId);

      // Process any remaining buffer
      if (lineBuffer.trim()) {
        try {
          const event = JSON.parse(lineBuffer);
          if (event.type === 'message' && event.role === 'assistant' && event.content) {
            accumulatedText += event.content;
          }
          if (event.session_id) sessionId = event.session_id;
        } catch { /* ignore */ }
      }

      if (!accumulatedText && code !== 0 && !timedOut) {
        const stderr = Buffer.concat(errChunks).toString('utf-8').trim();
        reject(new Error(`Gemini CLI exited with code ${code}: ${stderr || 'unknown error'}`));
        return;
      }

      if (sessionId && chatId) {
        setPersistedSession(chatId, sessionId);
      }

      resolve({
        text: accumulatedText || 'No response from Gemini.',
        sessionId,
        timedOut,
      });
    });

    proc.on('error', (err) => {
      clearTimeout(timeoutHandle);
      if (chatId) runningProcesses.delete(chatId);
      reject(new Error(`Failed to start Gemini CLI: ${err.message}`));
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
    running.proc.kill('SIGTERM'); // or 'SIGKILL'
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
 * Run a Gemini CLI subcommand (e.g. `mcp list`, `extensions list`).
 * Returns the raw text output.
 * @param {string[]} args - CLI arguments
 * @param {object} [options]
 * @param {string} [options.cwd] - Working directory
 * @returns {Promise<string>}
 */
export async function runCliCommand(args, { cwd } = {}) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    const errChunks = [];

    const proc = spawn(GEMINI_BIN, args, {
      cwd: cwd || WORKING_DIR,
      timeout: 30000,
      env: { ...process.env, NO_COLOR: '1' },
    });

    proc.stdout.on('data', (data) => chunks.push(data));
    proc.stderr.on('data', (data) => errChunks.push(data));

    proc.on('close', (code) => {
      const stdout = Buffer.concat(chunks).toString('utf-8').trim();
      const stderr = Buffer.concat(errChunks).toString('utf-8').trim();

      // Filter out noise lines from stderr (warnings, telemetry, etc.)
      const cleanOutput = cleanCliOutput(stdout || stderr);
      resolve(cleanOutput || 'Command completed (no output).');
    });

    proc.on('error', (err) => {
      reject(new Error(`Failed to run gemini command: ${err.message}`));
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
    /^CLI auth is requested/,
    /^Warning: Skipping extension/,
    /^Keychain initialization/,
    /^Require stack:/,
    /^- \/.+\/keytar\.js$/,
    /^Using FileKeychain fallback/,
    /^Loaded cached credentials/,
    /^Telemetry reinit/,
    /^Creating GCP exporters/,
    /^The 'metricReader' option/,
    /^Loading extension:/,
    /^Scheduling MCP context/,
    /^Executing MCP context/,
    /^MCP context refresh/,
    /^Coalescing burst/,
    /^Registering notification/,
    /^Server '.+' (supports|has)/,
  ];

  return raw
    .split('\n')
    .filter((line) => !noisePatterns.some((p) => p.test(line.trim())))
    .join('\n')
    .trim();
}

/**
 * List available sessions.
 * @param {string} [cwd]
 * @returns {Promise<string>}
 */
export async function listSessions(cwd) {
  return runCliCommand(['--list-sessions'], { cwd });
}

/**
 * Delete a session by index.
 * @param {string} index
 * @param {string} [cwd]
 * @returns {Promise<string>}
 */
export async function deleteSession(index, cwd) {
  return runCliCommand(['--delete-session', index], { cwd });
}

/**
 * List MCP servers.
 * @returns {Promise<string>}
 */
export async function listMcpServers() {
  return runCliCommand(['mcp', 'list']);
}

/**
 * List extensions.
 * @returns {Promise<string>}
 */
export async function listExtensions() {
  return runCliCommand(['extensions', 'list']);
}

/**
 * List skills.
 * @returns {Promise<string>}
 */
export async function listSkills() {
  return runCliCommand(['skills', 'list']);
}

/**
 * Resume a specific session by index or ID.
 * @param {number} chatId
 * @param {string} sessionRef - Session index number or "latest"
 */
export function setSessionResume(chatId, sessionRef) {
  setPersistedSession(chatId, sessionRef);
}

// ─── JSON Parsing ────────────────────────────────────────────────────────────

/**
 * Parse Gemini CLI JSON output to extract the response text and session ID.
 * @param {string} raw - Raw stdout from gemini CLI
 * @returns {{ text: string, sessionId?: string }}
 */
function parseGeminiOutput(raw) {
  // Try parsing as a single JSON object first
  try {
    const data = JSON.parse(raw);
    return extractFromJson(data);
  } catch {
    // Not a single JSON object
  }

  // Try parsing as newline-delimited JSON
  const lines = raw.split('\n').filter(Boolean);
  let text = '';
  let sessionId;

  for (const line of lines) {
    try {
      const data = JSON.parse(line);
      if (data.type === 'text' || data.type === 'message') {
        text += data.content || data.text || data.message || '';
      }
      if (data.sessionId || data.session_id) {
        sessionId = data.sessionId || data.session_id;
      }
      if (data.result) text = data.result;
      if (data.response) text = data.response;
    } catch {
      // Skip unparseable lines
    }
  }

  if (!text) text = raw;
  return { text, sessionId };
}

/**
 * Extract text and session ID from a parsed JSON object.
 * @param {object} data
 * @returns {{ text: string, sessionId?: string }}
 */
function extractFromJson(data) {
  const sessionId = data.sessionId || data.session_id || data.metadata?.sessionId;
  let text = '';

  if (typeof data.response === 'string') {
    text = data.response;
  } else if (typeof data.result === 'string') {
    text = data.result;
  } else if (typeof data.message === 'string') {
    text = data.message;
  } else if (data.messages && Array.isArray(data.messages)) {
    text = data.messages
      .filter((m) => m.role === 'assistant' || m.role === 'model')
      .map((m) => m.content || m.text || '')
      .join('\n');
  } else if (typeof data.content === 'string') {
    text = data.content;
  } else {
    text = JSON.stringify(data, null, 2);
  }

  return { text: text || 'No response.', sessionId };
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

import fs from 'fs';

const IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg']);

/**
 * Scan response text for image file paths that exist on disk.
 * Looks for absolute paths and common artifact patterns.
 * @param {string} text - Response text from Gemini CLI
 * @returns {string[]} Array of existing image file paths
 */
export function extractImagePaths(text) {
  const paths = new Set();

  // Match absolute file paths ending in image extensions
  // Handles: /path/to/image.png, `/path/to/image.png`, file:///path/to/image.png
  const pathRegex = /(?:file:\/\/)?(\/[^\s"'`<>]+\.(?:png|jpg|jpeg|webp|gif|svg))/gi;
  let match;
  while ((match = pathRegex.exec(text)) !== null) {
    let filePath = match[1];
    // Ensure absolute path
    if (filePath.startsWith('/')) {
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
  '.py', '.js', '.ts', '.jsx', '.tsx', '.json', '.md', '.txt', '.html', '.css',
  '.sh', '.yaml', '.yml', '.csv', '.pdf', '.xml', '.sql', '.go', '.rs', '.swift',
  '.java', '.c', '.cpp', '.h', '.rb', '.php', '.toml', '.conf', '.cfg', '.log',
]);

/**
 * Scan response text for code/document file paths that exist on disk.
 * Excludes image files (handled separately by extractImagePaths).
 * @param {string} text - Response text from Gemini CLI
 * @returns {string[]} Array of existing file paths
 */
export function extractFilePaths(text) {
  const paths = new Set();

  // Match absolute file paths
  const pathRegex = /(?:file:\/\/)?(\/[^\s"'`<>]+\.\w+)/gi;
  let match;
  while ((match = pathRegex.exec(text)) !== null) {
    const filePath = match[1];
    if (!filePath.startsWith('/')) continue;

    const ext = filePath.substring(filePath.lastIndexOf('.')).toLowerCase();
    if (!SENDABLE_FILE_EXTENSIONS.has(ext)) continue;

    try {
      if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
        paths.add(filePath);
      }
    } catch { /* ignore */ }
  }

  return Array.from(paths);
}
