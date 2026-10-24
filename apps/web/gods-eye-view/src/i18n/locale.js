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

// Which locale the page runs in: ?lang= → stored choice → browser languages →
// English. Only shipped locales are ever selected.

/** Durable preference key. Matches the repo convention gev:<name>:v1. */
export const LOCALE_STORAGE_KEY = 'gev:locale:v1';

/** Source language and fallback. */
export const DEFAULT_LOCALE = 'en';

/** Shipped locales; order does not matter. Adding one: docs/TRANSLATORS.md. */
export const LOCALES = Object.freeze(['en', 'es', 'ru', 'zh-CN']);

/** Each locale named in its own language, for the selector. */
export const LOCALE_NAMES = Object.freeze({
  en: 'English',
  es: 'Español',
  ru: 'Русский',
  'zh-CN': '简体中文',
});

/** Right-to-left locales. */
const RTL_LOCALES = Object.freeze([]);

/**
 * Map any language tag to a shipped locale: 'ru-RU' and 'RU' → 'ru',
 * 'zh', 'zh-CN' and 'zh-Hans-SG' → 'zh-CN'.
 * @returns {string|null}
 */
export function normalizeLocale(candidate) {
  if (typeof candidate !== 'string') return null;
  const [primary, ...rest] = candidate.trim().toLowerCase().split(/[-_]/);
  // Traditional Chinese readers are not given Simplified: no zh-TW yet.
  if (primary === 'zh')
    return rest.some((part) => ['hant', 'tw', 'hk', 'mo'].includes(part))
      ? null
      : 'zh-CN';
  return LOCALES.includes(primary) ? primary : null;
}

function queryLocale(location) {
  try {
    return normalizeLocale(new URLSearchParams(location?.search).get('lang'));
  } catch {
    return null;
  }
}

function readStoredLocale(storage) {
  try {
    const store = storage !== undefined ? storage : globalThis.localStorage;
    return normalizeLocale(store?.getItem?.(LOCALE_STORAGE_KEY));
  } catch {
    return null;
  }
}

/** Store the choice; false when storage is unavailable. */
export function writeStoredLocale(locale, storage) {
  const normalized = normalizeLocale(locale) || DEFAULT_LOCALE;
  try {
    const store = storage !== undefined ? storage : globalThis.localStorage;
    if (typeof store?.setItem !== 'function') return false;
    store.setItem(LOCALE_STORAGE_KEY, normalized);
    return true;
  } catch {
    return false;
  }
}

/** Resolve the boot locale. Every input is injectable for tests. */
export function resolveLocale({
  location = globalThis.location,
  storage,
  languages = globalThis.navigator?.languages,
} = {}) {
  const fromQuery = queryLocale(location);
  if (fromQuery) return fromQuery;
  const stored = readStoredLocale(storage);
  if (stored) return stored;
  for (const candidate of Array.isArray(languages) ? languages : []) {
    const normalized = normalizeLocale(candidate);
    if (normalized) return normalized;
  }
  return DEFAULT_LOCALE;
}

/** Set <html lang> and <html dir>. */
export function applyDocumentLanguage(doc, locale = DEFAULT_LOCALE) {
  const root = doc?.documentElement;
  if (!root) return false;
  const normalized = normalizeLocale(locale) || DEFAULT_LOCALE;
  root.lang = normalized;
  root.dir = RTL_LOCALES.includes(normalized) ? 'rtl' : 'ltr';
  return true;
}
