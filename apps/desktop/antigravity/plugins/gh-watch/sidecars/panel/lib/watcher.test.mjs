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
import { mkdirSync, mkdtempSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { normaliseChecks } from "./decide.mjs";
import { parsePrUrl, setAutoMerge } from "./github.mjs";
import { Inbox, NOTE_TTL_MS, parseNote } from "./inbox.mjs";
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

function setup({ autoFix = true, comments = false, updates = false } = {}) {
  const file = join(mkdtempSync(join(tmpdir(), "gh-watch-")), "watches.json");
  const store = new Store(file);
  const key = watchKey("o/r", 7);
  store.put({
    key,
    repo: "o/r",
    number: 7,
    conversationId: "conv-1",
    autoFix,
    comments,
    updates,
  });
  const sent = [];
  const world = {
    snap: snapshot("sha1", "OPEN", run("lint", "SUCCESS")),
    failSend: false,
    failRead: false,
    clock: 1000,
    reads: 0,
    feedback: [],
    failFeedback: false,
    queue: { queued: false, position: null },
    baseChecks: [],
    baseReads: 0,
  };
  const watcher = new Watcher({
    store,
    now: () => world.clock,
    fetchPr: async () => {
      world.reads += 1;
      if (world.failRead) throw new Error("boom");
      return world.snap;
    },
    fetchQueue: async () => world.queue,
    fetchCommitChecks: async () => {
      world.baseReads += 1;
      return world.baseChecks;
    },
    fetchFeedback: async () => {
      if (world.failFeedback) throw new Error("graphql down");
      return world.feedback;
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

test("a merged pull request is marked closed and can no longer wake anyone", async () => {
  const { store, key, sent, world, watcher } = setup();
  world.snap = snapshot("sha1", "MERGED", run("lint", "FAILURE"));
  await watcher.pass();
  assert.equal(store.get(key).closed, true);
  assert.equal(store.get(key).closedAt, 1000);
  assert.equal(sent.length, 0);
  // It is not re-read on the very next pass.
  world.clock += 30_000;
  await watcher.pass();
  assert.equal(world.reads, 1);
});

test("a closed pull request is removed after the keep time", async () => {
  const { store, key, world, watcher } = setup();
  world.snap = snapshot("sha1", "MERGED", run("lint", "SUCCESS"));
  await watcher.pass();
  world.clock += 24 * 3_600_000 - 1;
  await watcher.pass();
  assert.ok(store.get(key));
  world.clock += 1;
  await watcher.pass();
  assert.equal(store.get(key), undefined);
});

test("a keep time of zero removes a closed pull request on the next pass", async () => {
  const { store, key, world, watcher } = setup();
  store.updateSettings({ removeClosedHours: 0 });
  world.snap = snapshot("sha1", "CLOSED", run("lint", "SUCCESS"));
  await watcher.pass(); // read: now known to be closed
  assert.equal(store.get(key).closed, true);
  await watcher.pass();
  assert.equal(store.get(key), undefined);
});

test("a reopened pull request is noticed at the slow pace and watched again", async () => {
  const { store, key, sent, world, watcher } = setup();
  world.snap = snapshot("sha1", "CLOSED", run("lint", "SUCCESS"));
  await watcher.pass();
  world.snap = snapshot("sha2", "OPEN", run("lint", "FAILURE"));
  world.clock += 299_000;
  await watcher.pass();
  assert.equal(store.get(key).closed, true);
  world.clock += 1_000;
  await watcher.pass(); // re-read: open again
  assert.equal(store.get(key).closed, false);
  assert.equal(store.get(key).closedAt, undefined);
  // The same read that sees it open reports what is failing on it.
  assert.equal(sent.length, 1);
  assert.match(sent[0].message, /- lint/);
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

test("polls fast while checks run and slow once they settle", async () => {
  const { world, watcher } = setup();
  world.snap = snapshot("sha1", "OPEN", run("lint", null, "IN_PROGRESS"));
  await watcher.pass(); // read at t=1000: one check running
  assert.deepEqual(
    [watcher.status().mode, watcher.status().reason],
    ["fast", "checks running"],
  );
  world.clock = 1000 + 29_000;
  await watcher.tick();
  assert.equal(world.reads, 1);
  world.snap = snapshot("sha1", "OPEN", run("lint", "SUCCESS"));
  world.clock = 1000 + 30_000;
  await watcher.tick(); // due at the fast pace; sees everything settled
  assert.equal(world.reads, 2);
  assert.deepEqual(
    [watcher.status().mode, watcher.status().intervalSeconds],
    ["slow", 300],
  );
  world.clock += 299_000;
  await watcher.tick();
  assert.equal(world.reads, 2);
  world.clock += 1_000;
  await watcher.tick();
  assert.equal(world.reads, 3);
});

test("a changed interval takes effect on the next tick", async () => {
  const { store, world, watcher } = setup();
  await watcher.pass(); // settled, so slow: 300s
  store.updateSettings({ slowSeconds: 60 });
  world.clock += 60_000;
  await watcher.tick();
  assert.equal(world.reads, 2);
});

test("opening the panel checks at once, but not twice in a row", async () => {
  const { world, watcher } = setup();
  await watcher.pass();
  world.clock += 60_000;
  await watcher.notePresence(true); // back after being away
  assert.equal(world.reads, 2);
  assert.equal(watcher.status().reason, "panel open");
  world.clock += 5_000;
  await watcher.notePresence(true); // still open: no extra read
  assert.equal(world.reads, 2);
  await watcher.notePresence(false);
  world.clock += 2_000;
  await watcher.notePresence(true); // reopened seconds after a pass
  assert.equal(world.reads, 2);
});

test("the hold time comes from the saved settings", async () => {
  const { store, key, sent, world, watcher } = setup();
  store.updateSettings({ holdSeconds: 0 });
  world.snap = snapshot(
    "sha1",
    "OPEN",
    run("lint", "FAILURE"),
    run("test", null, "IN_PROGRESS"),
  );
  await watcher.check(key);
  assert.equal(sent.length, 1);
});

test("settings are saved, clamped and survive a restart", () => {
  const { store, file } = setup();
  assert.equal(store.settings().fastSeconds, 30);
  store.updateSettings({ fastSeconds: 3, mergeMethod: "rebase" });
  const reloaded = new Store(file).settings();
  assert.equal(reloaded.fastSeconds, 10);
  assert.equal(reloaded.mergeMethod, "rebase");
  assert.equal(reloaded.slowSeconds, 300);
});

test("setAutoMerge asks GitHub plainly, then names a method if it must", async () => {
  const calls = [];
  const queue = async (args) => void calls.push(args.join(" "));
  await setAutoMerge("o/r", 7, true, "squash", queue);
  await setAutoMerge("o/r", 7, false, "squash", queue);
  assert.deepEqual(calls, [
    "pr merge 7 -R o/r --auto",
    "pr merge 7 -R o/r --disable-auto",
  ]);

  calls.length = 0;
  const noQueue = async (args) => {
    calls.push(args.join(" "));
    if (!args.includes("--rebase"))
      throw new Error(
        "--merge, --rebase, or --squash required when not running interactively",
      );
  };
  await setAutoMerge("o/r", 7, true, "rebase", noQueue);
  assert.deepEqual(calls, [
    "pr merge 7 -R o/r --auto",
    "pr merge 7 -R o/r --auto --rebase",
  ]);

  await assert.rejects(
    setAutoMerge("o/r", 7, true, "squash", async () => {
      throw new Error(
        "GraphQL: Pull request Pull request is a draft (enablePullRequestAutoMerge)",
      );
    }),
    /Mark it ready for review first/,
  );
});

const conflicting = (headSha) => ({
  ...snapshot(headSha, "OPEN", run("lint", "SUCCESS")),
  mergeable: "CONFLICTING",
  base: "main",
});

test("a merge conflict wakes once, and again only after a push that keeps it", async () => {
  const { store, key, sent, world, watcher } = setup();
  world.snap = conflicting("sha1");
  await watcher.check(key);
  await watcher.check(key);
  assert.equal(sent.length, 1);
  assert.match(
    sent[0].message,
    /now has merge conflicts with its base branch `main`/,
  );
  assert.equal(sent[0].opts.title, "o/r#7: merge conflicts");
  assert.equal(store.get(key).conflicting, true);

  world.snap = conflicting("sha2");
  await watcher.check(key); // first read after the push: not believed yet
  assert.equal(sent.length, 1);
  await watcher.check(key);
  assert.equal(sent.length, 2);
  assert.match(sent[1].message, /still has merge conflicts/);

  world.snap = snapshot("sha3", "OPEN", run("lint", "SUCCESS"));
  await watcher.check(key);
  assert.equal(sent.length, 2);
  assert.equal(store.get(key).conflicting, false);
  assert.equal(store.get(key).conflict, null);
});

test("an undelivered conflict notice is sent again, not lost", async () => {
  const { key, sent, world, watcher } = setup();
  world.snap = conflicting("sha1");
  world.failSend = true;
  await watcher.check(key);
  world.failSend = false;
  await watcher.check(key);
  assert.equal(sent.length, 1);
  assert.match(sent[0].message, /now has merge conflicts/);
});

test("review feedback: stock-take first, then only new comments", async () => {
  const { store, key, sent, world, watcher } = setup({ comments: true });
  const item = (n) => ({
    id: `comment:${n}`,
    kind: "comment",
    author: "alice",
    body: `note ${n}`,
    url: "u",
  });
  world.feedback = [item(1)];
  await watcher.check(key); // comment 1 was already there
  assert.equal(sent.length, 0);

  world.feedback = [item(1), item(2)];
  await watcher.check(key);
  await watcher.check(key);
  assert.equal(sent.length, 1);
  assert.match(sent[0].message, /note 2/);
  assert.doesNotMatch(sent[0].message, /note 1/);
  assert.deepEqual(store.get(key).lastWakeChecks, ["1 review comment"]);
});

test("review feedback is not read when its switch is off", async () => {
  const { key, sent, world, watcher } = setup({ comments: false });
  world.failFeedback = true; // would surface as an error if it were read
  await watcher.check(key);
  assert.equal(sent.length, 0);
});

test("a failed feedback read is reported and does not block CI wakes", async () => {
  const { store, key, sent, world, watcher } = setup({ comments: true });
  world.failFeedback = true;
  world.snap = snapshot("sha1", "OPEN", run("lint", "FAILURE"));
  await watcher.check(key);
  assert.equal(sent.length, 1);
  assert.match(sent[0].message, /- lint/);
  assert.match(store.get(key).lastError, /Could not read review comments/);
});

test("with auto-fix off, comments can still be forwarded but conflicts are not", async () => {
  const { key, sent, world, watcher } = setup({
    autoFix: false,
    comments: true,
  });
  world.snap = conflicting("sha1");
  world.feedback = [];
  await watcher.check(key);
  world.feedback = [
    { id: "comment:9", kind: "comment", author: "alice", body: "hi", url: "u" },
  ];
  await watcher.check(key);
  assert.equal(sent.length, 1);
  assert.doesNotMatch(sent[0].message, /merge conflicts/);
});

const note = (command, extra = {}) =>
  JSON.stringify({
    conversationId: "conv-9",
    error: "",
    toolCall: {
      name: "run_command",
      args: { CommandLine: command, Cwd: "/work/repo" },
    },
    workspacePaths: ["/work/repo"],
    ...extra,
  });

test("parseNote accepts a successful gh pr create and nothing else", () => {
  assert.deepEqual(parseNote(note("gh pr create --fill")), {
    conversationId: "conv-9",
    cwd: "/work/repo",
    refs: [""],
  });
  assert.deepEqual(parseNote(note("git push && gh pr create --draft")), {
    conversationId: "conv-9",
    cwd: "/work/repo",
    refs: [""],
  });
  assert.equal(parseNote(note("echo gh pr created")), null);
  assert.equal(parseNote(note("echo gh pr create")), null);
  assert.equal(parseNote(note("true gh pr create")), null);
  assert.equal(parseNote(note("gh pr create --help")), null);
  assert.equal(parseNote(note("gh pr create --dry-run --fill")), null);
  assert.ok(parseNote(note("gh pr create --title 'add -h flag' --fill")));
  assert.equal(parseNote(note("grep -r 'gh pr create' .")), null);
  assert.ok(parseNote(note("cd repo; gh pr create --fill")));
  assert.ok(parseNote(note("git push -u origin x || true\ngh pr create")));
  assert.equal(parseNote(note("gh pr view")), null);
  assert.equal(
    parseNote(note("gh pr create", { error: "exit status 1" })),
    null,
  );
  assert.equal(parseNote(note("gh pr create", { conversationId: "" })), null);
  assert.equal(parseNote("not json"), null);
});

test("parseNote accepts the sign-up command for a pull request opened elsewhere", () => {
  const url = "https://github.com/o/r/pull/12";
  assert.deepEqual(
    parseNote(note(`GH_WATCH=1 gh pr view ${url} --json url --jq .url`)),
    { conversationId: "conv-9", cwd: "/work/repo", refs: [url] },
  );
  assert.deepEqual(parseNote(note("GH_WATCH=1 gh pr view 12")).refs, ["12"]);
  assert.deepEqual(parseNote(note("GH_WATCH=1 gh pr view '#12'")).refs, ["12"]);
  // Several at once, and from inside another folder.
  assert.deepEqual(
    parseNote(
      note(
        "cd /w && GH_WATCH=1 gh pr view 12 --json url && GH_WATCH=1 gh pr view 13",
      ),
    ).refs,
    ["12", "13"],
  );
  // Asked twice in one command, signed up once.
  assert.deepEqual(
    parseNote(note("GH_WATCH=1 gh pr view 12; GH_WATCH=1 gh pr view 12")).refs,
    ["12"],
  );
  // A plain read is not a request to watch, and neither is a mention.
  assert.equal(parseNote(note("gh pr view 12")), null);
  assert.equal(parseNote(note("echo GH_WATCH=1 gh pr view 12")), null);
  assert.equal(parseNote(note("GH_WATCH=1 gh pr view --json url")), null);
  assert.equal(parseNote(note("GH_WATCH=0 gh pr view 12")), null);
  // A failed lookup watches nothing.
  assert.equal(
    parseNote(note("GH_WATCH=1 gh pr view 99", { error: "exit status 1" })),
    null,
  );
});

// With `byRef`, a pull request number given to the sign-up command is the
// number that comes back, and numbers in `world.missing` are not found yet.
function signUpWorld({ byRef = false } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "gh-watch-inbox-"));
  const inboxDir = join(dir, "inbox");
  mkdirSync(inboxDir);
  const store = new Store(join(dir, "watches.json"));
  const world = {
    clock: Date.now(),
    found: true,
    state: "OPEN",
    lookedIn: [],
    missing: new Set(),
  };
  const numbered = (number) => ({
    ...snapshot("sha1", world.state, run("lint", "SUCCESS")),
    ...(byRef && number ? { number: Number(number) } : {}),
  });
  const watcher = new Watcher({
    store,
    inbox: new Inbox(inboxDir),
    now: () => world.clock,
    fetchPr: async (repo, number) => numbered(number),
    resolvePr: async (ref, cwd) => {
      world.lookedIn.push(cwd);
      if (!world.found || world.missing.has(ref))
        throw new Error("no pull requests found");
      return numbered(ref);
    },
    sendMessage: async () => undefined,
  });
  const drop = (name, text) => writeFileSync(join(inboxDir, name), text);
  return { store, world, watcher, drop, inbox: new Inbox(inboxDir), inboxDir };
}

test("a note from the hook starts a watch for the conversation that opened the PR", async () => {
  const { store, world, watcher, drop, inbox } = signUpWorld();
  drop("1.json", note("gh pr create --fill"));
  await watcher.signUp();
  const watch = store.get(watchKey("o/r", 7));
  assert.equal(watch.conversationId, "conv-9");
  assert.equal(watch.addedBy, "hook");
  assert.equal(watch.autoFix, true);
  // Other people's review comments are never passed on unless asked for.
  assert.equal(watch.comments, false);
  assert.deepEqual(world.lookedIn, ["/work/repo"]);
  assert.equal(inbox.list().length, 0);
});

test("a note never takes over a pull request that is already watched", async () => {
  const { store, watcher, drop } = signUpWorld();
  store.put({
    key: watchKey("o/r", 7),
    repo: "o/r",
    number: 7,
    conversationId: "mine",
    autoFix: false,
  });
  drop("1.json", note("gh pr create"));
  await watcher.signUp();
  assert.equal(store.get(watchKey("o/r", 7)).conversationId, "mine");
});

test("a note is retried until the pull request shows up, then given up on", async () => {
  const { store, world, watcher, drop, inbox, inboxDir } = signUpWorld();
  drop("1.json", note("gh pr create"));
  world.found = false;
  await watcher.signUp();
  assert.equal(inbox.list().length, 1);
  world.found = true;
  await watcher.signUp();
  assert.ok(store.get(watchKey("o/r", 7)));

  drop("2.json", note("gh pr create"));
  const old = new Date(world.clock - NOTE_TTL_MS - 1000);
  utimesSync(join(inboxDir, "2.json"), old, old);
  world.found = false;
  await watcher.signUp();
  assert.equal(inbox.list().length, 0);
});

test("a sign-up command watches each pull request it names, marked as added by the agent", async () => {
  const { store, watcher, drop, inbox } = signUpWorld({ byRef: true });
  drop(
    "1.json",
    note("GH_WATCH=1 gh pr view 21 && GH_WATCH=1 gh pr view 22 --json url"),
  );
  await watcher.signUp();
  for (const number of [21, 22]) {
    const watch = store.get(watchKey("o/r", number));
    assert.equal(watch.conversationId, "conv-9");
    assert.equal(watch.addedBy, "agent");
    assert.equal(watch.comments, false);
  }
  assert.equal(inbox.list().length, 0);
});

test("a sign-up note is kept while one of its pull requests cannot be found", async () => {
  const { store, world, watcher, drop, inbox } = signUpWorld({ byRef: true });
  world.missing = new Set(["22"]);
  drop("1.json", note("GH_WATCH=1 gh pr view 21 && GH_WATCH=1 gh pr view 22"));
  await watcher.signUp();
  assert.ok(store.get(watchKey("o/r", 21)));
  assert.equal(store.get(watchKey("o/r", 22)), undefined);
  assert.equal(inbox.list().length, 1);
  world.missing = new Set();
  await watcher.signUp();
  assert.ok(store.get(watchKey("o/r", 22)));
  assert.equal(inbox.list().length, 0);
});

test("a sign-up never takes over a pull request another conversation watches", async () => {
  const { store, watcher, drop } = signUpWorld({ byRef: true });
  store.put({
    key: watchKey("o/r", 21),
    repo: "o/r",
    number: 21,
    conversationId: "mine",
    autoFix: false,
  });
  drop("1.json", note("GH_WATCH=1 gh pr view 21"));
  await watcher.signUp();
  assert.equal(store.get(watchKey("o/r", 21)).conversationId, "mine");
});

test("notes are discarded when automatic watching is switched off, or are not PR creations", async () => {
  const { store, watcher, drop, inbox } = signUpWorld();
  drop("1.json", note("ls"));
  await watcher.signUp();
  assert.equal(inbox.list().length, 0);
  store.updateSettings({ autoWatch: false });
  drop("2.json", note("gh pr create"));
  await watcher.signUp();
  assert.equal(inbox.list().length, 0);
  assert.equal(store.list().length, 0);
});

const merged = (sha) => ({
  ...snapshot(sha, "MERGED", run("lint", "SUCCESS")),
  mergeCommit: "mergesha",
  base: "main",
});
const base = (name, bucket) => ({
  name,
  bucket,
  url: `https://example.test/${name}`,
});

test("the journey: green, merged, landed, each told once", async () => {
  const { store, key, sent, world, watcher } = setup({ updates: true });
  world.snap = snapshot("sha1", "OPEN", run("lint", null, "IN_PROGRESS"));
  await watcher.check(key);
  assert.equal(sent.length, 0);

  world.snap = snapshot("sha1", "OPEN", run("lint", "SUCCESS"));
  await watcher.check(key);
  await watcher.check(key);
  assert.equal(sent.length, 1);
  assert.match(sent[0].message, /All checks have passed/);
  assert.equal(sent[0].opts.title, "o/r#7: checks passed");

  world.queue = { queued: true, position: 2 };
  await watcher.check(key);
  assert.equal(store.get(key).queued, true);
  assert.equal(store.get(key).queuePosition, 2);
  assert.equal(sent.length, 1);

  world.queue = { queued: false, position: null };
  world.snap = merged("sha1");
  await watcher.check(key);
  assert.equal(sent.length, 2);
  assert.match(sent[1].message, /has merged into `main`/);
  assert.equal(world.baseReads, 0);

  world.baseChecks = [base("build", "pending")];
  world.clock += 30_000;
  await watcher.pass(); // closed, but followed at the normal pace
  assert.equal(world.baseReads, 1);
  assert.equal(sent.length, 2);
  assert.equal(watcher.status().reason, "merged, watching the base branch");

  world.baseChecks = [base("build", "pass")];
  world.clock += 90_000;
  await watcher.pass();
  assert.equal(sent.length, 3);
  assert.match(sent[2].message, /landed cleanly/);
  assert.equal(store.get(key).progress.landing.result, "healthy");

  world.clock += 30_000;
  await watcher.pass(); // finished: back to the slow re-read
  assert.equal(world.baseReads, 2);
  assert.equal(sent.length, 3);
});

test("a failing base branch after the merge is reported with its checks", async () => {
  const { store, key, sent, world, watcher } = setup({ updates: true });
  await watcher.check(key);
  world.snap = merged("sha1");
  await watcher.check(key);
  world.baseChecks = [base("build", "fail")];
  await watcher.check(key);
  assert.equal(sent.length, 2);
  assert.match(
    sent[1].message,
    /Checks on `main` are failing after this merge/,
  );
  assert.match(sent[1].message, /- build/);
  assert.deepEqual(store.get(key).failing, ["build"]);
  assert.equal(store.get(key).counts.fail, 1);

  // If the base check passes on a re-run after the settle period, it recovers to healthy.
  world.baseChecks = [base("build", "pass")];
  world.clock += 90_000;
  await watcher.check(key);
  assert.equal(store.get(key).progress.landing.result, "healthy");
  assert.equal(store.get(key).counts.fail, 0);
  assert.equal(store.get(key).counts.pass, 1);
});

test("with updates off the journey is tracked but nothing is sent", async () => {
  const { store, key, sent, world, watcher } = setup({ updates: false });
  world.snap = snapshot("sha1", "OPEN", run("lint", null, "IN_PROGRESS"));
  await watcher.check(key);
  world.snap = snapshot("sha1", "OPEN", run("lint", "SUCCESS"));
  await watcher.check(key);
  world.snap = merged("sha1");
  await watcher.check(key);
  assert.equal(sent.length, 0);
  assert.equal(store.get(key).progress.ended, "merged");
});

test("leaving the merge queue is reported, and an undelivered update is retried", async () => {
  const { key, sent, world, watcher } = setup({ updates: true });
  await watcher.check(key);
  world.queue = { queued: true, position: 1 };
  await watcher.check(key);
  world.queue = { queued: false, position: null };
  world.failSend = true;
  await watcher.check(key);
  assert.equal(sent.length, 0);
  world.failSend = false;
  await watcher.check(key);
  assert.equal(sent.length, 1);
  assert.match(sent[0].message, /left the merge queue without merging/);
});

test("a check that keeps flaking is called out when it fails again", async () => {
  const { store, key, sent, world, watcher } = setup();
  // Twice: fail, then pass on the same commit.
  for (const sha of ["sha1", "sha2"]) {
    world.snap = snapshot(sha, "OPEN", run("e2e", "FAILURE"));
    await watcher.check(key);
    world.snap = snapshot(sha, "OPEN", run("e2e", "SUCCESS"));
    await watcher.check(key);
  }
  assert.equal(sent.length, 2);
  assert.doesNotMatch(sent[1].message, /known flaky/);
  assert.equal(Object.keys(store.flakes()).length, 1);

  world.snap = snapshot(
    "sha3",
    "OPEN",
    run("e2e", "FAILURE"),
    run("lint", "FAILURE"),
  );
  await watcher.check(key);
  assert.equal(sent.length, 3);
  assert.match(
    sent[2].message,
    /- e2e \[CI\] \(known flaky: 2 times in the last 30 days\)/,
  );
  assert.match(sent[2].message, /- lint \[CI\]\n/);
  assert.match(sent[2].message, /Re-run those first/);
});
