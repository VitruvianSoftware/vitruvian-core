import fs from 'fs';
import path from 'path';

const SESSIONS_FILE = path.join(
  process.env.GEMINI_WORKING_DIR || process.cwd(),
  '.bot-sessions.json'
);

/**
 * Store structure:
 * {
 *   sessions: { chatId: sessionId },
 *   sessionNames: { chatId: name },
 *   workspaces: { alias: absolutePath }
 * }
 */
let store = { sessions: {}, sessionNames: {}, workspaces: {} };

// Load on module init
loadStore();

function loadStore() {
  try {
    if (fs.existsSync(SESSIONS_FILE)) {
      const raw = JSON.parse(fs.readFileSync(SESSIONS_FILE, 'utf-8'));
      // Handle legacy format (flat object of chatId -> sessionId)
      if (raw.sessions) {
        store = { sessions: raw.sessions, sessionNames: raw.sessionNames || {}, workspaces: raw.workspaces || {} };
      } else {
        store = { sessions: raw, sessionNames: {}, workspaces: {} };
      }
      console.log(`📋 Loaded ${Object.keys(store.sessions).length} saved sessions`);
    }
  } catch (err) {
    console.warn(`⚠️ Failed to load sessions: ${err.message}`);
  }
}

function saveStore() {
  try {
    fs.writeFileSync(SESSIONS_FILE, JSON.stringify(store, null, 2), 'utf-8');
  } catch (err) {
    console.warn(`⚠️ Failed to save store: ${err.message}`);
  }
}

// ─── Sessions ────────────────────────────────────────────────────────────────

export function getPersistedSession(chatId) {
  return store.sessions[String(chatId)];
}

export function setPersistedSession(chatId, sessionId) {
  store.sessions[String(chatId)] = sessionId;
  saveStore();
}

export function deletePersistedSession(chatId) {
  delete store.sessions[String(chatId)];
  delete store.sessionNames[String(chatId)];
  saveStore();
}

export function hasPersistedSession(chatId) {
  return String(chatId) in store.sessions;
}

// ─── Session Names ───────────────────────────────────────────────────────────

export function getSessionName(chatId) {
  return store.sessionNames[String(chatId)];
}

export function setSessionName(chatId, name) {
  store.sessionNames[String(chatId)] = name;
  saveStore();
}

// ─── Workspace Shortcuts ─────────────────────────────────────────────────────

export function getWorkspaces() {
  return { ...store.workspaces };
}

export function setWorkspace(alias, absolutePath) {
  store.workspaces[alias] = absolutePath;
  saveStore();
}

export function deleteWorkspace(alias) {
  delete store.workspaces[alias];
  saveStore();
}
