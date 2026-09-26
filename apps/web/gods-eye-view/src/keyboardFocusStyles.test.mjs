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

import { readStylesheet } from './testSupport/readStylesheet.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const css = readStylesheet(new URL('../style.css', import.meta.url));

function ruleBody(selector) {
  const start = css.indexOf(selector);
  assert.ok(start >= 0, `${selector} rule exists`);
  const open = css.indexOf('{', start);
  const close = css.indexOf('}', open);
  return css.slice(open + 1, close);
}

function ruleText(selector) {
  const start = css.indexOf(selector);
  assert.ok(start >= 0, `${selector} rule exists`);
  const close = css.indexOf('}', css.indexOf('{', start));
  return css.slice(start, close + 1);
}

function ruleBodyContaining(selector, declaration) {
  let start = -1;
  while ((start = css.indexOf(selector, start + 1)) >= 0) {
    const open = css.indexOf('{', start);
    const close = css.indexOf('}', open);
    const body = css.slice(open + 1, close);
    if (body.includes(declaration)) return body;
  }
  assert.fail(`${selector} rule containing ${declaration} exists`);
}

test('the global keyboard ring survives local active and outline-reset rules', () => {
  const rule = ruleText(':where(\n  button,');
  assert.match(rule, /outline:\s*2px solid var\(--text-primary\) !important;/);
  for (const selector of [
    "[role='button']",
    "[role='radio']",
    "[role='slider']",
    "[role='tab']",
    '[tabindex]',
    'a[href]',
  ]) assert.ok(rule.includes(selector), `${selector} receives the global ring`);
});

test('Location city, POI, search toggle and search field use an inset ring', () => {
  const rule = ruleText('.location-pill:focus-visible,');
  assert.match(rule, /\.poi-pill:focus-visible/);
  assert.match(rule, /\.search-toggle-btn:focus-visible/);
  assert.match(rule, /#location-search:focus-visible/);
  assert.match(rule, /outline:\s*2px solid var\(--text-primary\)/);
  assert.match(rule, /outline-offset:\s*-3px/);
  for (const selector of ['.location-pill {', '.poi-pill {', '.search-toggle-btn {']) {
    assert.doesNotMatch(ruleBody(selector), /transition:\s*all\b/);
  }
});

test('Cockpit Display and Radio launcher glyphs have a complete inset ring', () => {
  const body = ruleBody('.cockpit-utility-glyph:focus-visible');
  assert.match(body, /outline:\s*2px solid var\(--text-primary\)/);
  assert.match(body, /outline-offset:\s*-3px/);
  assert.doesNotMatch(body, /outline:\s*none/);
});

test('focusable controls do not animate the global outline', () => {
  for (const selector of [
    '.panel-collapse-btn {',
    '#top-center-actions button {',
    '.data-toggle-chip {',
    '.scene-btn {',
    '.scene-shot-btn {',
  ]) {
    assert.doesNotMatch(
      ruleBody(selector),
      /transition:\s*all\b/,
      `${selector} must leave the focus outline immediate`,
    );
  }
});

test('opening a dock popover makes its controls keyboard-reachable immediately', () => {
  const base = ruleBodyContaining('#command-dock .dock-popover-content {', 'visibility: hidden');
  assert.match(base, /visibility\s+0s\s+linear\s+180ms/);
  const open = ruleText('#command-dock #location-bar:not(.collapsed) .dock-popover-content,');
  assert.match(open, /transition-delay:\s*0s/);
});
