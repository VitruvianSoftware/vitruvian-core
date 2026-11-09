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

import { realtimeDirectives } from '../openai/instructions.js';

// Voice wording in the shared directives and its written form. A test checks
// each phrase still occurs in the directives, so rewording one there fails
// rather than leaking spoken wording into chat.
export const TEXT_WORDING = Object.freeze([
  ['without speaking first', 'without writing a preamble'],
  ['before speaking', 'before confirming'],
  ['may first say ONE sentence', 'may first write ONE sentence'],
  ["speak the result's say line", "write the result's say line"],
  ['on the voice card: speak a caveat', 'in the tool result: include a caveat'],
  ['as you talk', 'as you write'],
  ['you can read aloud', 'you can report'],
]);

// Shared-manual adaptation follows Darren Dignam's GEV COMMAND approach (#976).
// Keep our Radio handoff and annotation outcome policies from the shared manual.
// `options.overpass` matches the tools offered, as for voice.
export function textInstructions(annotationGuidance, options) {
  return realtimeDirectives(annotationGuidance, options)
    .map((line, index) => {
      if (index === 0)
        return "You are GEV Chat, a concise text assistant for a Cesium geospatial app called God's Eye View.";
      if (index === 1)
        return 'Have a natural written conversation. This is text-only chat; no microphone or generated audio is used.';
      return TEXT_WORDING.reduce(
        (text, [spoken, written]) => text.replace(spoken, written),
        line,
      );
    })
    .join('\n');
}
