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

// src/voice/panel/preferencesView.test.mjs — the rendered minutes field keeps
// a draft across renders and shows a refused edit's applied value again.
import '../../testSupport/registerDom.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  bindPreferenceControls,
  createVoicePreferences,
  VOICE_TIMEOUT_STORAGE_KEY as T,
} from './preferences.js';
import { createTestVoiceUi } from '../../testSupport/voiceUi.mjs';
import { mountVoiceView } from '../../testSupport/voiceView.mjs';

test('a minutes draft survives unrelated renders; a refused edit is written back', async (t) => {
  const { pinia, settle } = mountVoiceView(t);
  const ui = createTestVoiceUi({ panel: true, pinia });
  ui.update('preferences', { timeoutMinutes: '17' });
  const prefs = createVoicePreferences({
    storage: { getItem: (key) => (key === T ? '17' : null), setItem() {} },
  });
  bindPreferenceControls({
    ui,
    preferences: prefs,
    copy: { previewNote: '', timeoutNote: 'Local', notSaved: 'Not saved' },
  });
  await settle();
  const input = document.getElementById('gev-voice-timeout-input');
  assert.equal(input.value, '17');
  // Typing, before the field commits: the waveform renders every frame.
  input.value = '2';
  ui.update('status', { text: 'LISTENING' });
  await settle();
  assert.equal(input.value, '2');
  input.value = '0';
  input.dispatchEvent(new Event('change', { bubbles: true }));
  await settle();
  assert.equal(input.value, '17');
});
