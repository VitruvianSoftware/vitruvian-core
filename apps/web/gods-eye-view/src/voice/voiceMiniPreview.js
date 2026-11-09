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

import { getLocale } from '../i18n/index.js';

const segmenters = new Map();
const segmenter = (locale) => {
  if (!segmenters.has(locale))
    segmenters.set(
      locale,
      new Intl.Segmenter(locale, { granularity: 'sentence' }),
    );
  return segmenters.get(locale);
};

/** The final sentence of a transcript, split by the active locale's rules. */
export function lastSentence(text, locale = getLocale()) {
  const clean = String(text ?? '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!clean) return '';
  let parts;
  try {
    parts = [...segmenter(locale).segment(clean)].map((part) =>
      part.segment.trim(),
    );
  } catch {
    parts = clean.split(/(?<=[.!?。！？])\s+/);
  }
  return parts.filter(Boolean).at(-1) ?? clean;
}

/**
 * Keep the minimized voice bar's preview: the last spoken sentence from the
 * user and from the assistant. Typed chat turns belong to the chat panel.
 * Once either side has spoken, the root marks the exchange so the empty
 * preview's "Try saying" hints step aside until the next session.
 */
export function bindVoiceMiniPreview({ ui, session }) {
  let assistant = '';
  let response = null;
  const sentences = { user: '', assistant: '' };
  const show = (role, text) => {
    sentences[role] = lastSentence(text);
    ui.update('mini', { [role]: sentences[role] });
    const spoken = Boolean(sentences.user || sentences.assistant);
    if (ui.state.root.voiceExchange !== spoken)
      ui.update('root', { voiceExchange: spoken });
  };
  const clear = () => {
    assistant = '';
    response = null;
    show('user', '');
    show('assistant', '');
  };
  clear();
  return session.subscribe((event) => {
    // Any new session starts empty, even one whose start is still reported
    // as typed chat while voice takes over.
    if (event.type === 'state' && event.state === 'connecting') clear();
    if (session.adapter?.getStartOptions?.().textOnly) return;
    if (event.type !== 'transcript' || !event.text) return;
    if (event.role === 'user') show('user', event.text);
    if (event.role !== 'assistant') return;
    const id = event.responseId || null;
    // Deltas accumulate per response; a final transcript replaces them.
    assistant = event.final
      ? event.text
      : `${id === response ? assistant : ''}${event.text}`;
    response = id;
    show('assistant', assistant);
  });
}
