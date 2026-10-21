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

// Backend for the gh-watch panel. Antigravity starts this file with Node.js
// (see sidecar.json) and keeps it running while the plugin is enabled, so the
// watcher polls whether or not the panel is open. 'sidecar_sdk' is resolved
// by Antigravity; there is nothing to install.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Response, SidecarApp } from "sidecar_sdk";

import { reviewAction } from "./lib/actions.mjs";
import {
  approvePr,
  fetchCommitChecks,
  fetchFailureLog,
  fetchFeedback,
  fetchPr,
  fetchQueue,
  fetchMyPrs,
  fetchRepoPrs,
  fetchReviewRequests,
  rerunFailedJobs,
  resolvePr,
  setAutoMerge,
} from "./lib/github.mjs";
import { extractFailureExcerpt, parseCheckUrl } from "./lib/logs.mjs";
import { listFlaky } from "./lib/flakes.mjs";
import { Inbox } from "./lib/inbox.mjs";
import { LIMITS, MERGE_METHODS } from "./lib/pace.mjs";
import { summariseLists } from "./lib/reviews.mjs";
import { Store, watchKey } from "./lib/store.mjs";
import { Watcher } from "./lib/watcher.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DATA_DIR =
  process.env.ANTIGRAVITY_EXECUTABLE_DATA_DIR || join(HERE, ".data");

// Where hooks/note-pr-create.sh leaves its notes. It is a fixed folder under
// Antigravity's data folder, not inside DATA_DIR, because DATA_DIR is named
// after however the plugin was installed and the hook cannot know that name.
const INBOX_DIR = join(
  process.env.ANTIGRAVITY_APP_DATA_DIR ||
    join(homedir(), ".gemini", "antigravity"),
  "gh-watch-inbox",
);

const app = new SidecarApp();
const store = new Store(join(DATA_DIR, "watches.json"));
const watcher = new Watcher({
  store,
  fetchPr,
  fetchFeedback,
  fetchQueue,
  fetchCommitChecks,
  resolvePr,
  inbox: new Inbox(INBOX_DIR),
  sendMessage: async (conversationId, message, opts) =>
    app.sendMessage(conversationId, message, opts),
});

const readLocal = (name) => readFileSync(join(HERE, name), "utf8");

// The plugin's version, shown in the panel so a bug report can name it.
function readVersion() {
  try {
    return String(
      JSON.parse(readFileSync(join(HERE, "..", "..", "plugin.json"), "utf8"))
        .version ?? "",
    );
  } catch {
    return "";
  }
}
const VERSION = readVersion();
const fail = (message, status = 400) =>
  new Response(JSON.stringify({ error: message }), {
    contentType: "application/json",
    status,
  });

app.page("/", () => readLocal("index.html"));
app.page("/app.js", () => readLocal("app.js"));
app.api(
  "/styles.css",
  () => new Response(readLocal("styles.css"), { contentType: "text/css" }),
  "GET",
);

// The three lists of open pull requests: waiting on the user's review, opened
// by the user, and all of them in the repositories the user has ticked. Read
// only while the panel is being looked at (it is what calls /api/state), at
// most every two minutes, and never in the way of a reply. The last list is
// read after the other two, since they decide which repositories exist.
const REVIEWS_EVERY_MS = 120_000;
let reviews = {
  at: 0,
  items: [],
  mine: [],
  all: [],
  error: null,
  busy: false,
};
const watchedRepos = () => store.list().map((w) => w.repo);
function refreshReviews() {
  if (reviews.busy || Date.now() - reviews.at < REVIEWS_EVERY_MS) return;
  reviews.busy = true;
  (async () => {
    const [items, mine] = await Promise.all([
      fetchReviewRequests(),
      fetchMyPrs(),
    ]);
    const { shownRepos } = summariseLists(
      { reviews: items, mine, watched: watchedRepos() },
      store.settings().hiddenReviewRepos,
    );
    const all = await fetchRepoPrs(shownRepos);
    reviews = { at: Date.now(), items, mine, all, error: null, busy: false };
  })().catch((err) => {
    reviews = { ...reviews, at: Date.now(), error: err.message, busy: false };
  });
}

// GET /api/state: everything the panel shows.
app.api(
  "/api/state",
  () => {
    refreshReviews();
    return {
      watches: store.list(),
      settings: store.settings(),
      limits: LIMITS,
      mergeMethods: MERGE_METHODS,
      pace: watcher.status(),
      flaky: listFlaky(store.flakes(), Date.now()),
      lists: {
        ...summariseLists(
          {
            reviews: reviews.items,
            mine: reviews.mine,
            all: reviews.all,
            watched: watchedRepos(),
          },
          store.settings().hiddenReviewRepos,
        ),
        error: reviews.error,
      },
      version: VERSION,
    };
  },
  "GET",
);

// POST /api/review-action {repo, number, merge}: approve a pull request from
// "Waiting on your review", and with `merge` also set it to merge. Refused
// unless a fresh read shows it is still fully green. GitHub drops the review
// request once it is approved, so the row is taken out of the list at once
// and the list is read again on the next look.
app.api("/api/review-action", async (data) => {
  try {
    const done = await reviewAction(
      {
        repo: data.repo,
        number: data.number,
        merge: data.merge === true,
        mergeMethod: store.settings().mergeMethod,
      },
      { fetchPr, approvePr, setAutoMerge },
    );
    reviews = {
      ...reviews,
      at: 0,
      items: reviews.items.filter(
        (pr) => !(pr.repo === data.repo && pr.number === Number(data.number)),
      ),
    };
    return done;
  } catch (err) {
    return fail(err.message);
  }
});

// POST /api/presence {visible}: the panel reports whether it is showing.
// While it is, the watcher polls at the fast pace.
app.api("/api/presence", async (data) => {
  await watcher.notePresence(data.visible === true);
  return { pace: watcher.status() };
});

// POST /api/settings {fastSeconds?, slowSeconds?, holdSeconds?, mergeMethod?,
// autoWatch?, removeClosedHours?, hiddenReviewRepos?}
// Out-of-range values are clamped; the reply is what was actually stored.
app.api("/api/settings", (data) => {
  // Ticking a repository changes which ones "All open pull requests" covers,
  // so read the lists again on the next look rather than in two minutes.
  if (Array.isArray(data.hiddenReviewRepos)) reviews = { ...reviews, at: 0 };
  return { settings: store.updateSettings(data), pace: watcher.status() };
});

// POST /api/automerge {key, enabled}: turns GitHub's own auto-merge on or
// off. GitHub does the merging once the required checks and reviews are in.
app.api("/api/automerge", async (data) => {
  const watch = store.get(String(data.key ?? ""));
  if (!watch) return fail("That pull request is not being watched", 404);
  try {
    await setAutoMerge(
      watch.repo,
      watch.number,
      data.enabled === true,
      store.settings().mergeMethod,
    );
  } catch (err) {
    return fail(err.message);
  }
  await watcher.check(watch.key);
  return { watch: store.get(watch.key) };
});

// POST /api/watch {ref, conversationId, workspaceUri}: start watching a pull
// request and tie it to the conversation that should be woken.
app.api("/api/watch", async (data) => {
  const conversationId = String(data.conversationId ?? "").trim();
  if (!conversationId)
    return fail("Open the panel from a conversation to watch a pull request");
  let cwd;
  try {
    cwd = data.workspaceUri
      ? fileURLToPath(String(data.workspaceUri))
      : undefined;
  } catch {
    return fail("The workspace folder could not be read");
  }
  let snap;
  try {
    snap = await resolvePr(data.ref, cwd);
  } catch (err) {
    return fail(err.message);
  }
  const key = watchKey(snap.repo, snap.number);
  const existing = store.get(key);
  store.put({
    ...existing,
    key,
    repo: snap.repo,
    number: snap.number,
    conversationId,
    autoFix: existing?.autoFix ?? true,
    // Off unless asked for: review comments are other people's words put in
    // front of an agent that can push code.
    comments: existing?.comments ?? false,
    updates: existing?.updates ?? true,
    addedAt: existing?.addedAt ?? Date.now(),
    closed: false,
    readFailures: 0,
  });
  await watcher.check(key);
  return { watch: store.get(key) };
});

// POST /api/autofix {key, enabled}
app.api("/api/autofix", async (data) => {
  const watch = store.get(String(data.key ?? ""));
  if (!watch) return fail("That pull request is not being watched", 404);
  store.put({ ...watch, autoFix: data.enabled === true });
  if (data.enabled === true) await watcher.check(watch.key);
  return { watch: store.get(watch.key) };
});

// POST /api/comments {key, enabled}: forward new review feedback or not.
// Turning it on takes stock again, so comments written while it was off are
// not all sent at once.
app.api("/api/comments", async (data) => {
  const watch = store.get(String(data.key ?? ""));
  if (!watch) return fail("That pull request is not being watched", 404);
  const enabled = data.enabled === true;
  store.put({ ...watch, comments: enabled, seenFeedback: undefined });
  if (enabled) await watcher.check(watch.key);
  return { watch: store.get(watch.key) };
});

// POST /api/updates {key, enabled}: tell the conversation when the change
// goes green, merges and lands, or not.
app.api("/api/updates", (data) => {
  const watch = store.get(String(data.key ?? ""));
  if (!watch) return fail("That pull request is not being watched", 404);
  store.put({ ...watch, updates: data.enabled === true });
  return { watch: store.get(watch.key) };
});

// POST /api/unwatch {key}
app.api("/api/unwatch", (data) => {
  store.remove(String(data.key ?? ""));
  return { ok: true };
});

// POST /api/failure-log {key, checkName}: fetches the failed log excerpt for a check.
app.api("/api/failure-log", async (data) => {
  const watch = store.get(String(data.key ?? ""));
  if (!watch) return fail("That pull request is not being watched", 404);
  const checks = watch.failingChecks ?? [];
  const check = checks.find((c) => c.name === data.checkName) ?? checks[0];
  if (!check?.url) return fail("No run URL found for that check", 404);
  const parsed = parseCheckUrl(check.url);
  if (!parsed?.runId)
    return fail("Could not parse workflow run ID from check URL", 400);
  try {
    const raw = await fetchFailureLog(watch.repo, parsed.runId);
    const excerpt = extractFailureExcerpt(raw, 50);
    return { checkName: check.name, runId: parsed.runId, excerpt };
  } catch (err) {
    return fail(err.message);
  }
});

// POST /api/rerun {key, checkName?}: reruns failed jobs for failing checks on a PR.
app.api("/api/rerun", async (data) => {
  const watch = store.get(String(data.key ?? ""));
  if (!watch) return fail("That pull request is not being watched", 404);
  let checks = watch.failingChecks ?? [];
  if (data.checkName) checks = checks.filter((c) => c.name === data.checkName);
  const runIds = [
    ...new Set(checks.map((c) => parseCheckUrl(c.url)?.runId).filter(Boolean)),
  ];
  if (runIds.length === 0)
    return fail("No rerun targets found for failing checks", 400);
  try {
    for (const runId of runIds) {
      await rerunFailedJobs(watch.repo, runId);
    }
    await watcher.check(watch.key);
    return { watch: store.get(watch.key), reruns: runIds.length };
  } catch (err) {
    return fail(err.message);
  }
});

// POST /api/refresh: check every watched pull request and refresh lists now.
app.api("/api/refresh", async () => {
  reviews = { ...reviews, at: 0 };
  refreshReviews();
  for (const watch of store.list()) await watcher.check(watch.key);
  return { watches: store.list() };
});

watcher.start();
app.run();
