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

export const VOICE_PROVIDERS = Object.freeze({
  openai: Object.freeze({ label: 'OpenAI' }), // i18n-ignore: provider product name
  gemini: Object.freeze({ label: 'Gemini' }), // i18n-ignore: provider product name
});

/** Optional providers require an explicit host opt-in and an available factory. */
export function supportedVoiceProviders(
  requested = ['openai'],
  factories = {},
) {
  if (!Array.isArray(requested))
    throw new TypeError('supportedProviders must be an array');
  const selected = [...new Set(requested)].filter(
    (name) =>
      Object.hasOwn(VOICE_PROVIDERS, name) &&
      typeof factories[name] === 'function',
  );
  if (!selected.length)
    throw new Error('No supported voice provider is configured');
  return Object.freeze(selected);
}
