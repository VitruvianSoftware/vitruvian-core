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

import { watch } from 'vue';
import { createI18n } from 'vue-i18n';
import {
  bindLocale,
  getCatalog,
  getLocale,
  notifyLocaleChange,
} from '../i18n/index.js';
import { DEFAULT_LOCALE, LOCALES } from '../i18n/locale.js';

let pageI18n = null;

// Catalogs are flat and keyed by English text, which holds dots.
const resolveFlat = (messages, key) =>
  Object.hasOwn(messages, key) ? messages[key] : null;

/**
 * The page's vue-i18n instance, installed in every application view. It
 * holds the active locale and the catalogs; Core's t(), tn() and the Intl
 * formatters read the locale from it, so a view that calls them while
 * rendering re-renders when the locale changes. Views translate through
 * t()/tn() rather than vue-i18n's own t: English is the key, `context` picks
 * an entry, and plural forms follow Intl.PluralRules (docs/I18N.md).
 * @returns {import('vue-i18n').I18n}
 */
export function applicationI18n() {
  if (pageI18n) return pageI18n;
  const messages = {};
  for (const locale of LOCALES)
    if (locale !== DEFAULT_LOCALE) messages[locale] = getCatalog(locale);
  pageI18n = createI18n({
    legacy: false,
    globalInjection: false,
    locale: getLocale(),
    fallbackLocale: DEFAULT_LOCALE,
    messages,
    messageResolver: resolveFlat,
    missingWarn: false,
    fallbackWarn: false,
  });
  // vue-i18n disposes its instance when an app it is installed in unmounts;
  // the page's outlives every view, so an unmounted panel keeps it.
  const install = pageI18n.install;
  pageI18n.install = (app, ...options) => {
    const unmount = app.unmount;
    const installed = install.call(pageI18n, app, ...options);
    app.unmount = unmount;
    return installed;
  };
  bindLocale(pageI18n.global.locale);
  // Code that translated text itself shows it again, whichever way the
  // locale changed (setLocale or the ref).
  watch(
    () => getLocale(),
    () => notifyLocaleChange(),
    { flush: 'sync' },
  );
  return pageI18n;
}
