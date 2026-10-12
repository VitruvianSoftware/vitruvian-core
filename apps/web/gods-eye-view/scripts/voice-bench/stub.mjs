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

/**
 * Stub tool results fed back to the model after each call. Pure.
 *
 * core suite: the neutral `{ ok:true }` stub qa-voice-routing has always
 *   used, so continuations behave exactly as in that harness.
 * coverage suite: the same stub, except a call whose arguments violate the
 *   tool schema gets `{ ok:false, error }` — what the app's runner returns
 *   for an unknown layer id — so the model's follow-up words can be judged
 *   for honesty.
 */
import { validateCall } from './grade.mjs';

export const STUB_OK = Object.freeze({ ok: true, note: 'qa-harness stub result' });

export function stubResult(suite, c, tools) {
  if (suite === 'coverage') {
    const errors = validateCall(tools, c);
    if (errors.length) return { ok: false, error: `Invalid arguments: ${errors.join('; ')}` };
  }
  return { ...STUB_OK };
}
