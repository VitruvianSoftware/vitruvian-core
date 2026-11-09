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

import test from 'node:test';
import assert from 'node:assert/strict';
import { bindVoiceMiniPreview, lastSentence } from './voiceMiniPreview.js';
import { createTestVoiceUi } from '../testSupport/voiceUi.mjs';

test('lastSentence keeps only the final sentence across scripts', () => {
  assert.equal(
    lastSentence('Flying to Tokyo. Showing flights now.', 'en'),
    'Showing flights now.',
  );
  assert.equal(
    lastSentence('  One   sentence only  ', 'en'),
    'One sentence only',
  );
  assert.equal(
    lastSentence('東京へ移動します。便を表示します。', 'ja'),
    '便を表示します。',
  );
  assert.equal(lastSentence('', 'en'), '');
  assert.equal(lastSentence(null, 'en'), '');
});

function fixture({ textOnly = false } = {}) {
  const ui = createTestVoiceUi({ panel: true });
  const listeners = new Set();
  const mode = { textOnly };
  const session = {
    adapter: { getStartOptions: () => ({ textOnly: mode.textOnly }) },
    subscribe(fn) {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
  };
  const emit = (event) => listeners.forEach((fn) => fn(event));
  const unbind = bindVoiceMiniPreview({ ui, session });
  return { ui, emit, unbind, listeners, mode };
}

test('voice preview shows the last user and assistant sentence', () => {
  const f = fixture();
  const mini = () => f.ui.state.mini;
  assert.deepEqual(mini(), { user: '', assistant: '' });
  assert.equal(f.ui.state.root.voiceExchange, false);
  f.emit({ type: 'transcript', role: 'user', text: 'Hi. Show live flights.' });
  assert.equal(mini().user, 'Show live flights.');
  assert.equal(f.ui.state.root.voiceExchange, true);
  f.emit({
    type: 'transcript',
    role: 'assistant',
    text: 'Showing flights. ',
    responseId: 'r1',
  });
  f.emit({
    type: 'transcript',
    role: 'assistant',
    text: 'There are 214',
    responseId: 'r1',
  });
  assert.equal(mini().assistant, 'There are 214');
  f.emit({
    type: 'transcript',
    role: 'assistant',
    text: 'Showing flights. There are 214 aircraft.',
    responseId: 'r1',
    final: true,
  });
  assert.equal(mini().assistant, 'There are 214 aircraft.');
  f.emit({
    type: 'transcript',
    role: 'assistant',
    text: 'Done.',
    responseId: 'r2',
  });
  assert.equal(mini().assistant, 'Done.');
  f.emit({ type: 'state', state: 'connecting' });
  assert.deepEqual(mini(), { user: '', assistant: '' });
  assert.equal(f.ui.state.root.voiceExchange, false);
  f.unbind();
  assert.equal(f.listeners.size, 0);
});

test('typed chat turns do not reach the voice preview', () => {
  const f = fixture({ textOnly: true });
  f.emit({ type: 'transcript', role: 'user', text: 'Typed question.' });
  f.emit({
    type: 'transcript',
    role: 'assistant',
    text: 'Typed reply.',
    final: true,
  });
  assert.deepEqual(f.ui.state.mini, { user: '', assistant: '' });
  assert.equal(f.ui.state.root.voiceExchange, false);
});

test('a new session clears the preview even while the adapter still reports chat', () => {
  const f = fixture();
  f.emit({ type: 'transcript', role: 'user', text: 'Show live flights.' });
  assert.equal(f.ui.state.mini.user, 'Show live flights.');
  // Voice -> chat -> voice: the next start's connecting can arrive before
  // the adapter has left typed mode.
  f.mode.textOnly = true;
  f.emit({ type: 'state', state: 'connecting' });
  assert.deepEqual(f.ui.state.mini, { user: '', assistant: '' });
  assert.equal(f.ui.state.root.voiceExchange, false);
});
