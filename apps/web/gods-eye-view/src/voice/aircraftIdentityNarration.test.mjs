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

import { readRealtimeSource } from '../testSupport/readRealtimeSource.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { responseInstructionForToolResult } from './realtimeProtocol.js';
import { attachVoiceResult } from './speech.js';

const voiceConfig = readFileSync(
  new URL('../../server/providers/openai/instructions.js', import.meta.url),
  'utf8',
);
const realtime = readRealtimeSource();

test('aircraft identity narration acknowledges missing enrichment', () => {
  const start = voiceConfig.indexOf('\'For "what is this aircraft?"');
  assert.ok(start >= 0, 'aircraft identity honesty instruction is missing');
  const text = voiceConfig.slice(start, voiceConfig.indexOf('\n', start));
  assert.match(text, /get_entity_context/);
  assert.match(
    text,
    /callsign, operator, type and route from returned fields only/,
  );
  assert.match(text, /airport codes verbatim/);
  assert.match(text, /Never infer them from the callsign/);
  assert.match(
    text,
    /Other questions about the selection answer from its properties/,
  );

  // The follow-up now speaks the code-built say line, which always covers
  // operator, type and route (see speech.test.mjs for the field rules).
  const followup = responseInstructionForToolResult(
    attachVoiceResult('get_entity_context', {
      ok: true,
      action: 'get_entity_context',
      selected: {
        id: 'a',
        layerId: 'flights',
        properties: { callsign: 'UAL1' },
      },
    }),
  );
  assert.match(
    followup,
    /asked what the aircraft is, speak its identityLine and add nothing/,
  );
  assert.match(
    followup,
    /any other question \(altitude, speed, registration\), answer from selected\.properties/,
  );
  assert.doesNotMatch(realtime, /Operator details are unavailable/);
});
