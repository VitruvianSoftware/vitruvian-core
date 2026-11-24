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

// src/data/youtubeApi.test.mjs — YouTube's IFrame API loader, with the page
// faked: one load per document, and a load that fails is not kept, so the
// LIVE section's Try again loads the API afresh.
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadYouTubeApi } from './youtubeApi.js';

/** A document whose head records the scripts put in it. */
function fakePage() {
  const scripts = [];
  const timers = [];
  const documentRef = {
    createElement(tag) {
      const listeners = {};
      return {
        tag,
        removed: false,
        addEventListener(name, listener) {
          listeners[name] = listener;
        },
        fire(name) {
          listeners[name]?.();
        },
        remove() {
          this.removed = true;
        },
      };
    },
    head: {
      append(node) {
        scripts.push(node);
      },
    },
  };
  const globalRef = {
    setTimeout(callback, delay) {
      timers.push({ callback, delay, cleared: false });
      return timers.length;
    },
    clearTimeout(id) {
      if (timers[id - 1]) timers[id - 1].cleared = true;
    },
  };
  return { documentRef, globalRef, scripts, timers };
}

class Player {}

test('the API loads once per document, and a loaded one is reused', async () => {
  const { documentRef, globalRef, scripts } = fakePage();
  const first = loadYouTubeApi(documentRef, globalRef);
  assert.equal(loadYouTubeApi(documentRef, globalRef), first);
  assert.equal(scripts.length, 1);
  assert.equal(scripts[0].src, 'https://www.youtube.com/iframe_api');
  globalRef.YT = { Player };
  globalRef.onYouTubeIframeAPIReady();
  assert.equal(await first, globalRef.YT);
  assert.equal(await loadYouTubeApi(documentRef, globalRef), globalRef.YT);
  assert.equal(scripts.length, 1);
});

test('a script that fails to load is removed, and the next call loads afresh', async () => {
  const { documentRef, globalRef, scripts } = fakePage();
  const failed = loadYouTubeApi(documentRef, globalRef);
  scripts[0].fire('error');
  await assert.rejects(failed, /YouTube API unavailable/);
  assert.equal(scripts[0].removed, true);
  const again = loadYouTubeApi(documentRef, globalRef);
  assert.notEqual(again, failed);
  assert.equal(scripts.length, 2);
  globalRef.YT = { Player };
  globalRef.onYouTubeIframeAPIReady();
  assert.equal(await again, globalRef.YT);
});

test('a load slower than 5 s fails, and the next call loads afresh', async () => {
  const { documentRef, globalRef, scripts, timers } = fakePage();
  const slow = loadYouTubeApi(documentRef, globalRef);
  assert.equal(timers[0].delay, 5000);
  timers[0].callback();
  await assert.rejects(slow, /YouTube API timed out/);
  loadYouTubeApi(documentRef, globalRef);
  assert.equal(scripts.length, 2);
});
