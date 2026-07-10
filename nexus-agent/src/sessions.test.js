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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// sessions.js persists to `${GEMINI_WORKING_DIR||cwd}/.bot-sessions.json` and
// reads it once at import time. Point it at a throwaway dir BEFORE importing so
// the test neither reads nor clobbers a real store.
process.env.GEMINI_WORKING_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nexus-sessions-'));
const {
  getPersistedSession, setPersistedSession, deletePersistedSession, hasPersistedSession,
  getSessionName, setSessionName,
  getWorkspaces, setWorkspace, deleteWorkspace,
} = await import('./sessions.js');

test('session ids round-trip and chatId is coerced to a string', () => {
  setPersistedSession(123, 'sess-abc'); // numeric chatId in
  assert.equal(getPersistedSession('123'), 'sess-abc'); // string chatId out
  assert.equal(hasPersistedSession(123), true);
});

test('deleting a session also clears its name', () => {
  setPersistedSession(5, 's');
  setSessionName(5, 'my session');
  deletePersistedSession(5);
  assert.equal(getPersistedSession(5), undefined);
  assert.equal(getSessionName(5), undefined);
  assert.equal(hasPersistedSession(5), false);
});

test('getWorkspaces returns a copy — mutating it does not affect the store', () => {
  setWorkspace('proj', '/abs/proj');
  const ws = getWorkspaces();
  ws.proj = '/tampered';
  ws.injected = '/evil';
  assert.equal(getWorkspaces().proj, '/abs/proj');
  assert.equal(getWorkspaces().injected, undefined);
});

test('deleteWorkspace removes only the named alias', () => {
  setWorkspace('a', '/a');
  setWorkspace('b', '/b');
  deleteWorkspace('a');
  assert.equal(getWorkspaces().a, undefined);
  assert.equal(getWorkspaces().b, '/b');
});

test('changes persist to disk (a fresh read of the store sees them)', () => {
  setPersistedSession(99, 'persisted');
  const file = path.join(process.env.GEMINI_WORKING_DIR, '.bot-sessions.json');
  const onDisk = JSON.parse(fs.readFileSync(file, 'utf-8'));
  assert.equal(onDisk.sessions['99'], 'persisted');
});
