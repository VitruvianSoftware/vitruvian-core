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

import test from 'node:test';
import assert from 'node:assert/strict';
import { createGoogleTokenSource, GOOGLE_TOKEN_PATH } from './googleTokens.js';

function server(answers) {
  const calls = [];
  return {
    calls,
    fetchImpl: async (url) => {
      calls.push(url);
      const answer = answers.shift();
      if (answer instanceof Error) throw answer;
      return answer;
    },
  };
}

const offer = (accessToken, expiresAt) =>
  Response.json({ accessToken, expiresAt });

test('a token is reused until shortly before it expires', async () => {
  let now = 1_000_000;
  const { calls, fetchImpl } = server([
    offer('first', now + 900_000),
    offer('second', now + 1_800_000),
  ]);
  const tokens = createGoogleTokenSource({ fetchImpl, now: () => now });
  assert.equal(await tokens.token(), 'first');
  assert.equal(await tokens.token(), 'first');
  assert.deepEqual(calls, [GOOGLE_TOKEN_PATH]);
  now += 850_000;
  assert.equal(await tokens.token(), 'second');
  assert.equal(calls.length, 2);
});

test('requests refused for the same token renew it once', async () => {
  const now = 1_000_000;
  const { calls, fetchImpl } = server([
    offer('first', now + 900_000),
    offer('second', now + 900_000),
  ]);
  const tokens = createGoogleTokenSource({ fetchImpl, now: () => now });
  await tokens.token();
  const renewed = await Promise.all([
    tokens.token({ replacing: 'first' }),
    tokens.token({ replacing: 'first' }),
  ]);
  assert.deepEqual(renewed, ['second', 'second']);
  assert.equal(await tokens.token({ replacing: 'first' }), 'second');
  assert.equal(calls.length, 2);
});

test('a server that does not offer tokens yields none', async () => {
  for (const answer of [
    new Response('Not found', { status: 404 }),
    new Response('<!doctype html>', { status: 200 }),
    Response.json({ accessToken: '', expiresAt: Date.now() + 60_000 }),
    Response.json({ accessToken: 'stale', expiresAt: 1 }),
    new TypeError('offline'),
  ]) {
    const { fetchImpl } = server([answer]);
    assert.equal(await createGoogleTokenSource({ fetchImpl }).token(), null);
  }
});
