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

import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { normaliseChecks } from "./decide.mjs";
import { parsePrUrl } from "./github.mjs";
import { Store, watchKey } from "./store.mjs";
import { Watcher } from "./watcher.mjs";

const run = (name, conclusion, status = "COMPLETED") => ({
  __typename: "CheckRun",
  name,
  status,
  conclusion,
  workflowName: "CI",
});
const snapshot = (headSha, state, ...raw) => ({
  repo: "o/r",
  number: 7,
  title: "Add thing",
  url: "https://github.com/o/r/pull/7",
  state,
  isDraft: false,
  branch: "feat/x",
  headSha,
  mergeable: "MERGEABLE",
  checks: normaliseChecks(raw),
});

function setup({ autoFix = true } = {}) {
  const file = join(mkdtempSync(join(tmpdir(), "pr-watch-")), "watches.json");
  const store = new Store(file);
  const key = watchKey("o/r", 7);
  store.put({ key, repo: "o/r", number: 7, conversationId: "conv-1", autoFix });
  const sent = [];
  const world = {
    snap: snapshot("sha1", "OPEN", run("lint", "SUCCESS")),
    failSend: false,
    failRead: false,
    clock: 1000,
  };
  const watcher = new Watcher({
    store,
    now: () => world.clock,
    fetchPr: async () => {
      if (world.failRead) throw new Error("boom");
      return world.snap;
    },
    sendMessage: async (conversationId, message, opts) => {
      if (world.failSend) throw new Error("offline");
      sent.push({ conversationId, message, opts });
    },
  });
  return { store, key, sent, world, watcher, file };
}

test("stays quiet while checks pass, wakes once when one fails", async () => {
  const { store, key, sent, world, watcher } = setup();
  await watcher.check(key);
  assert.equal(sent.length, 0);
  assert.deepEqual(store.get(key).counts, {
    pass: 1,
    fail: 0,
    pending: 0,
    skip: 0,
    cancel: 0,
  });

  world.snap = snapshot("sha1", "OPEN", run("lint", "FAILURE"));
  await watcher.check(key);
  await watcher.check(key);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].conversationId, "conv-1");
  assert.match(sent[0].message, /- lint/);
  assert.equal(store.get(key).wakes, 1);
  assert.deepEqual(store.get(key).lastWakeChecks, ["lint"]);
});

test("a wake that could not be delivered is retried on the next pass", async () => {
  const { store, key, sent, world, watcher } = setup();
  world.snap = snapshot("sha1", "OPEN", run("lint", "FAILURE"));
  world.failSend = true;
  await watcher.check(key);
  assert.equal(sent.length, 0);
  assert.match(store.get(key).lastError, /offline/);

  world.failSend = false;
  await watcher.check(key);
  assert.equal(sent.length, 1);
  assert.equal(store.get(key).lastError, null);
});

test("auto-fix off records status but never wakes", async () => {
  const { store, key, sent, world, watcher } = setup({ autoFix: false });
  world.snap = snapshot("sha1", "OPEN", run("lint", "FAILURE"));
  await watcher.check(key);
  assert.equal(sent.length, 0);
  assert.deepEqual(store.get(key).failing, ["lint"]);
});

test("a merged pull request is marked closed and skipped afterwards", async () => {
  const { store, key, sent, world, watcher } = setup();
  world.snap = snapshot("sha1", "MERGED", run("lint", "FAILURE"));
  await watcher.pass();
  assert.equal(store.get(key).closed, true);
  assert.equal(sent.length, 0);
  world.snap = snapshot("sha2", "OPEN", run("lint", "FAILURE"));
  await watcher.pass();
  assert.equal(store.get(key).headSha, "sha1");
});

test("read failures are recorded and back off", async () => {
  const { store, key, world, watcher } = setup();
  world.failRead = true;
  await watcher.pass(); // pass 0: read, fails -> 1 failure, retry every 2nd pass
  await watcher.pass(); // pass 1: skipped
  assert.equal(store.get(key).readFailures, 1);
  await watcher.pass(); // pass 2: read again
  assert.equal(store.get(key).readFailures, 2);
  assert.equal(store.get(key).lastError, "boom");
});

test("the watch list survives a restart", () => {
  const { file, key } = setup();
  assert.equal(new Store(file).get(key).conversationId, "conv-1");
});

test("parsePrUrl accepts pull request links only", () => {
  assert.deepEqual(parsePrUrl("https://github.com/o/r/pull/12/files"), {
    repo: "o/r",
    number: 12,
  });
  assert.equal(parsePrUrl("https://github.com/o/r/issues/12"), null);
  assert.equal(parsePrUrl("12"), null);
});
