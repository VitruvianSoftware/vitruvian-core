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

// src/ui/cockpitBodyClasses.test.mjs — the classes the Cockpit puts on
// <body> must not also name an element's rule. A bare `.name { … }` written
// for a panel matches <body> the moment <body> carries `name`, and its
// pointer-events, position and overflow then apply to the whole page (a
// shared `cockpit-orbital` once made every click in orbit fall through).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const UI_ROOT = fileURLToPath(new URL('.', import.meta.url));
const SRC_ROOT = path.resolve(UI_ROOT, '..');
const CONTROLLER = path.join(UI_ROOT, 'cockpitTrackingController.js');

/** Every stylesheet the app ships. */
function stylesheets(directory = SRC_ROOT) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...stylesheets(absolute));
    else if (entry.isFile() && entry.name.endsWith('.css'))
      files.push(absolute);
  }
  return files;
}

/** A selector list split on its top-level commas, not those in `:not(a, b)`. */
function splitSelectorList(list) {
  const parts = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < list.length; i += 1) {
    if (list[i] === '(') depth += 1;
    else if (list[i] === ')') depth -= 1;
    else if (list[i] === ',' && depth === 0) {
      parts.push(list.slice(start, i));
      start = i + 1;
    }
  }
  parts.push(list.slice(start));
  return parts;
}

/** The classes the tracking controller adds to <body>. */
function cockpitBodyClasses() {
  const source = readFileSync(CONTROLLER, 'utf8');
  const names = [
    ...source.matchAll(/body\.classList\.add\(\s*'([a-z0-9-]+)'/g),
  ].map((match) => match[1]);
  return [...new Set(names)];
}

test('the Cockpit adds its subject classes to <body>', () => {
  const classes = cockpitBodyClasses();
  for (const name of ['cockpit-mode', 'cockpit-bridge', 'cockpit-orbit']) {
    assert.ok(classes.includes(name), `${name} is not added to <body>`);
  }
});

test('no stylesheet rule matches a Cockpit body class on another element', () => {
  const offenders = [];
  for (const name of cockpitBodyClasses()) {
    // `.name` as a whole class token, not as `.name-suffix`.
    const token = new RegExp(`\\.${name}(?![\\w-])`);
    for (const file of stylesheets()) {
      const css = readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
      for (const [, selectors] of css.matchAll(/([^{}]+)\{/g)) {
        for (const selector of splitSelectorList(selectors)) {
          // Prettier wraps long `:not(\n  .name\n)` arguments; unwrap them.
          const compound = selector
            .trim()
            .replace(/\(\s+/g, '(')
            .replace(/\s+\)/g, ')');
          if (!token.test(compound)) continue;
          // Allowed only on <body> itself: `body.name` or `body:not(.name)`.
          const onBody = new RegExp(
            `(^|[\\s>+~])body[^\\s>+~]*\\.${name}(?![\\w-])`,
          );
          if (onBody.test(compound)) continue;
          offenders.push(`${path.relative(SRC_ROOT, file)}: ${compound}`);
        }
      }
    }
  }
  assert.deepEqual(
    offenders,
    [],
    'Selectors that match a Cockpit body class without `body.`: ' +
      offenders.join('; '),
  );
});
