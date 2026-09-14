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

import fs from "node:fs";
import path from "node:path";

const SESSIONS_FILE = path.join(
  process.env.GEMINI_WORKING_DIR || process.cwd(),
  ".bot-sessions.json",
);

/**
 * @typedef {Object} SessionStore
 * @property {Record<string, string>} sessions
 * @property {Record<string, string>} sessionNames
 * @property {Record<string, string>} workspaces
 */

/** @type {SessionStore} */
let store = { sessions: {}, sessionNames: {}, workspaces: {} };

// Load on module init
loadStore();

function loadStore() {
  try {
    if (fs.existsSync(SESSIONS_FILE)) {
      const raw = JSON.parse(fs.readFileSync(SESSIONS_FILE, "utf-8"));
      // Handle legacy format (flat object of chatId -> sessionId)
      if (raw.sessions) {
        store = {
          sessions: raw.sessions,
          sessionNames: raw.sessionNames || {},
          workspaces: raw.workspaces || {},
        };
      } else {
        store = { sessions: raw, sessionNames: {}, workspaces: {} };
      }
      console.log(
        `📋 Loaded ${Object.keys(store.sessions).length} saved sessions`,
      );
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(`⚠️ Failed to load sessions: ${message}`);
  }
}

function saveStore() {
  try {
    fs.writeFileSync(SESSIONS_FILE, JSON.stringify(store, null, 2), "utf-8");
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(`⚠️ Failed to save store: ${message}`);
  }
}

// ─── Sessions ────────────────────────────────────────────────────────────────

/**
 * @param {string | number} chatId
 * @returns {string | undefined}
 */
export function getPersistedSession(chatId) {
  return store.sessions[String(chatId)];
}

/**
 * @param {string | number} chatId
 * @param {string} sessionId
 */
export function setPersistedSession(chatId, sessionId) {
  store.sessions[String(chatId)] = sessionId;
  saveStore();
}

/**
 * @param {string | number} chatId
 */
export function deletePersistedSession(chatId) {
  delete store.sessions[String(chatId)];
  delete store.sessionNames[String(chatId)];
  saveStore();
}

/**
 * @param {string | number} chatId
 * @returns {boolean}
 */
export function hasPersistedSession(chatId) {
  return String(chatId) in store.sessions;
}

// ─── Session Names ───────────────────────────────────────────────────────────

/**
 * @param {string | number} chatId
 * @returns {string | undefined}
 */
export function getSessionName(chatId) {
  return store.sessionNames[String(chatId)];
}

/**
 * @param {string | number} chatId
 * @param {string} name
 */
export function setSessionName(chatId, name) {
  store.sessionNames[String(chatId)] = name;
  saveStore();
}

// ─── Workspace Shortcuts ─────────────────────────────────────────────────────

/**
 * @returns {Record<string, string>}
 */
export function getWorkspaces() {
  return { ...store.workspaces };
}

/**
 * @param {string} alias
 * @param {string} absolutePath
 */
export function setWorkspace(alias, absolutePath) {
  store.workspaces[alias] = absolutePath;
  saveStore();
}

/**
 * @param {string} alias
 */
export function deleteWorkspace(alias) {
  delete store.workspaces[alias];
  saveStore();
}
