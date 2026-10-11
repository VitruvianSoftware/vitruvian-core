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

// Backend for the pr-watch panel. Antigravity starts this file with Node.js
// (see sidecar.json) and keeps it running while the plugin is enabled, so the
// watcher polls whether or not the panel is open. 'sidecar_sdk' is resolved
// by Antigravity; there is nothing to install.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Response, SidecarApp } from "sidecar_sdk";

import { fetchPr, resolvePr, setAutoMerge } from "./lib/github.mjs";
import { LIMITS, MERGE_METHODS } from "./lib/pace.mjs";
import { Store, watchKey } from "./lib/store.mjs";
import { Watcher } from "./lib/watcher.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DATA_DIR =
  process.env.ANTIGRAVITY_EXECUTABLE_DATA_DIR || join(HERE, ".data");

const app = new SidecarApp();
const store = new Store(join(DATA_DIR, "watches.json"));
const watcher = new Watcher({
  store,
  fetchPr,
  sendMessage: async (conversationId, message, opts) =>
    app.sendMessage(conversationId, message, opts),
});

const readLocal = (name) => readFileSync(join(HERE, name), "utf8");
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

// GET /api/state: everything the panel shows.
app.api(
  "/api/state",
  () => ({
    watches: store.list(),
    settings: store.settings(),
    limits: LIMITS,
    mergeMethods: MERGE_METHODS,
    pace: watcher.status(),
  }),
  "GET",
);

// POST /api/presence {visible}: the panel reports whether it is showing.
// While it is, the watcher polls at the fast pace.
app.api("/api/presence", async (data) => {
  await watcher.notePresence(data.visible === true);
  return { pace: watcher.status() };
});

// POST /api/settings {fastSeconds?, slowSeconds?, holdSeconds?, mergeMethod?}
// Out-of-range values are clamped; the reply is what was actually stored.
app.api("/api/settings", (data) => ({
  settings: store.updateSettings(data),
  pace: watcher.status(),
}));

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

// POST /api/unwatch {key}
app.api("/api/unwatch", (data) => {
  store.remove(String(data.key ?? ""));
  return { ok: true };
});

// POST /api/refresh: check every open pull request now.
app.api("/api/refresh", async () => {
  for (const watch of store.list())
    if (!watch.closed) await watcher.check(watch.key);
  return { watches: store.list() };
});

watcher.start();
app.run();
