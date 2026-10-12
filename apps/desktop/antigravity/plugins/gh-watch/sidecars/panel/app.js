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

// Frontend for the gh-watch panel. /preload.js runs first and defines
// window.sidecar; window.sidecar.fetch adds the token non-GET routes need.

const sidecar = window.sidecar;
const $ = (id) => document.getElementById(id);
const FONT_KEY = "cowork-artifact-fontscale";
const REDRAW_MS = 5000;
const PRESENCE_MS = 10000;

async function callApi(path, { method = "GET", body } = {}) {
  const res = await sidecar.fetch(path, {
    method,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `${res.status} ${res.statusText}`);
  return data;
}

// --- Text size --------------------------------------------------------------

function readScale() {
  try {
    const saved = Number(localStorage.getItem(FONT_KEY));
    return saved >= 0.8 && saved <= 1.4 ? saved : 1;
  } catch {
    return 1;
  }
}

function applyScale(scale) {
  const clamped = Math.min(1.4, Math.max(0.8, Math.round(scale * 10) / 10));
  document.documentElement.style.setProperty("--s", String(clamped));
  $("font-size").textContent = `${Math.round(clamped * 100)}%`;
  try {
    localStorage.setItem(FONT_KEY, String(clamped));
  } catch {
    // Storage can be unavailable in the embedded frame; the size still applies.
  }
  return clamped;
}

let scale = applyScale(readScale());
$("font-down").addEventListener("click", () => {
  scale = applyScale(scale - 0.1);
});
$("font-up").addEventListener("click", () => {
  scale = applyScale(scale + 0.1);
});

// --- Rendering --------------------------------------------------------------

function ago(ms) {
  if (!ms) return "never";
  const seconds = Math.max(0, Math.round((Date.now() - ms) / 1000));
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  return `${Math.round(minutes / 60)} h ago`;
}

function statusOf(watch) {
  if (watch.prState === "MERGED") {
    const landing = watch.progress?.landing;
    if (landing?.phase === "watching")
      return { text: "Merged · checking base", tone: "run" };
    if (landing?.result === "healthy")
      return { text: "Merged · landed", tone: "good" };
    if (landing?.result === "failing")
      return { text: "Merged · base failing", tone: "bad" };
    return { text: "Merged", tone: "done" };
  }
  if (watch.closed) return { text: "Closed", tone: "done" };
  if (!watch.counts) return { text: "Not read yet", tone: "wait" };
  if (watch.conflicting) return { text: "Conflicts", tone: "bad" };
  if (watch.counts.fail > 0) return { text: "Failing", tone: "bad" };
  if (watch.queued) {
    const place = watch.queuePosition ? ` #${watch.queuePosition}` : "";
    return { text: `In merge queue${place}`, tone: "run" };
  }
  if (watch.counts.pending > 0) return { text: "Running", tone: "run" };
  if (watch.readyToMerge) return { text: "Ready to merge", tone: "wait" };
  return { text: "Passing", tone: "good" };
}

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) {
    if (name === "class") node.className = value;
    else if (name.startsWith("on")) node.addEventListener(name.slice(2), value);
    else if (value !== false && value !== undefined)
      node.setAttribute(name, value === true ? "" : value);
  }
  for (const child of children)
    if (child !== null && child !== undefined) node.append(child);
  return node;
}

function card(watch) {
  const status = statusOf(watch);
  const counts = watch.counts ?? {
    pass: 0,
    fail: 0,
    pending: 0,
    skip: 0,
    cancel: 0,
  };
  const toggle = el("input", {
    type: "checkbox",
    "data-focus": `autofix:${watch.key}`,
    onchange: (event) =>
      act("/api/autofix", { key: watch.key, enabled: event.target.checked }),
  });
  toggle.checked = watch.autoFix === true;
  toggle.disabled = watch.closed === true;

  const merge = el("input", {
    type: "checkbox",
    "data-focus": `automerge:${watch.key}`,
    onchange: (event) =>
      act("/api/automerge", { key: watch.key, enabled: event.target.checked }),
  });
  // GitHub clears its auto-merge flag once the pull request is queued.
  merge.checked = watch.autoMerge === true || watch.queued === true;
  merge.disabled = watch.closed === true;

  const comments = el("input", {
    type: "checkbox",
    "data-focus": `comments:${watch.key}`,
    onchange: (event) =>
      act("/api/comments", { key: watch.key, enabled: event.target.checked }),
  });
  comments.checked = watch.comments === true;
  comments.disabled = watch.closed === true;

  const updates = el("input", {
    type: "checkbox",
    "data-focus": `updates:${watch.key}`,
    onchange: (event) =>
      act("/api/updates", { key: watch.key, enabled: event.target.checked }),
  });
  updates.checked = watch.updates === true;
  // Stays usable after the merge: the base branch is still being followed.
  updates.disabled = watch.closed === true && watch.prState !== "MERGED";

  const mine =
    sidecar.conversationId && watch.conversationId === sidecar.conversationId;
  const lines = [
    el(
      "p",
      { class: "muted small" },
      `Checked ${ago(watch.checkedAt)} · wakes ${mine ? "this conversation" : "another conversation"}${watch.addedBy === "hook" ? " · added automatically" : ""}`,
    ),
  ];
  if (watch.failing?.length)
    lines.push(
      el("p", { class: "small" }, `Failing: ${watch.failing.join(", ")}`),
    );
  if (watch.lastWakeAt) {
    lines.push(
      el(
        "p",
        { class: "small" },
        `Woke the agent ${ago(watch.lastWakeAt)} about ${watch.lastWakeChecks.join(", ")} (${watch.wakes} in total)`,
      ),
    );
  }
  if (watch.lastError)
    lines.push(el("p", { class: "error small" }, watch.lastError));

  return el(
    "article",
    { class: "card" },
    el(
      "div",
      { class: "card-header" },
      el(
        "a",
        {
          class: "title",
          href: watch.url ?? "#",
          target: "_blank",
          rel: "noreferrer",
        },
        `#${watch.number} ${watch.title ?? watch.repo}`,
      ),
      el("span", { class: `badge ${status.tone}` }, status.text),
    ),
    el("p", { class: "muted small" }, `${watch.repo} · ${watch.branch ?? ""}`),
    el(
      "p",
      { class: "counts" },
      el("span", { class: "good" }, `${counts.pass} passed`),
      el("span", { class: "bad" }, `${counts.fail} failed`),
      el("span", { class: "run" }, `${counts.pending} running`),
      el("span", { class: "muted" }, `${counts.skip + counts.cancel} skipped`),
    ),
    ...lines,
    el(
      "div",
      { class: "row spread" },
      el(
        "div",
        { class: "checks" },
        el(
          "label",
          { class: "check" },
          toggle,
          "Wake the agent when CI fails or the branch conflicts",
        ),
        el(
          "label",
          { class: "check" },
          comments,
          "Tell the agent about new review comments",
        ),
        el(
          "label",
          { class: "check" },
          updates,
          "Tell the agent when it goes green, merges and lands",
        ),
        el(
          "label",
          { class: "check" },
          merge,
          "Auto-merge on GitHub when ready",
        ),
      ),
      el(
        "button",
        {
          type: "button",
          class: "secondary",
          "data-focus": `unwatch:${watch.key}`,
          onclick: () => act("/api/unwatch", { key: watch.key }),
        },
        "Stop watching",
      ),
    ),
  );
}

// Replaces a container's children and puts keyboard focus back on the control
// that had it, matched by its data-focus name.
function redraw(container, children) {
  const focused = container.contains(document.activeElement)
    ? document.activeElement.dataset.focus
    : undefined;
  container.replaceChildren(...children);
  if (!focused) return;
  for (const control of container.querySelectorAll("[data-focus]")) {
    if (control.dataset.focus === focused) control.focus();
  }
}

function render(state) {
  const watches = [...state.watches].sort((a, b) =>
    a.closed === b.closed ? b.addedAt - a.addedAt : a.closed ? 1 : -1,
  );
  // The rows are rebuilt on every redraw. Put keyboard focus back on the
  // control that had it, so a redraw never takes a checkbox out from under
  // the keyboard and never has to be skipped.
  redraw($("list"), watches.map(card));
  $("empty").hidden = watches.length > 0;
  const open = watches.filter((w) => !w.closed).length;
  const pace = state.pace;
  $("summary").textContent =
    `${open} open · checking every ${pace.intervalSeconds}s (${pace.reason})`;
  $("version").textContent = state.version ? `v${state.version}` : "";
  fillSettings(state);
  renderReviews(state.reviews ?? { items: [] });
  renderFlaky(state.flaky ?? []);
}

// Pull requests where someone is waiting on the user's review, with a tick
// box per repository to choose which ones are listed.
function renderReviews(reviews) {
  const items = reviews.items ?? [];
  const repos = reviews.repos ?? [];
  const total = reviews.total ?? items.length;
  $("reviews").hidden = total === 0 && repos.length === 0 && !reviews.error;
  // GitHub is asked for one page, so a full page means "that many or more".
  const more = reviews.capped ? "+" : "";
  $("reviews-count").textContent =
    items.length === total
      ? `${total}${more}`
      : `${items.length} of ${total}${more}`;
  $("reviews-error").textContent = reviews.error ?? "";
  $("reviews-error").hidden = !reviews.error;

  // One repository needs no filter, unless it is the one switched off.
  $("reviews-filter").hidden =
    repos.length < 2 && repos.every((row) => row.shown);
  redraw(
    $("reviews-repos"),
    repos.map((row) =>
      el(
        "label",
        { class: "check" },
        el("input", {
          type: "checkbox",
          checked: row.shown,
          "data-focus": `review-repo:${row.repo}`,
          onchange: (event) =>
            act("/api/settings", {
              hiddenReviewRepos: repos
                .filter((other) =>
                  other.repo === row.repo
                    ? !event.target.checked
                    : !other.shown,
                )
                .map((other) => other.repo),
            }),
        }),
        `${row.repo} (${row.count})`,
      ),
    ),
  );
  $("reviews-none").hidden = !(items.length === 0 && total > 0);
  $("reviews-list").replaceChildren(
    ...items.map((pr) =>
      el(
        "li",
        {},
        el(
          "a",
          { href: pr.url, target: "_blank", rel: "noreferrer" },
          `${pr.repo}#${pr.number} ${pr.title}`,
        ),
        el("span", { class: "muted small" }, ` · ${pr.author}`),
      ),
    ),
  );
}

// Checks that have recently failed and then passed with no code change.
function renderFlaky(flaky) {
  $("flaky").hidden = flaky.length === 0;
  $("flaky-count").textContent = String(flaky.length);
  $("flaky-list").replaceChildren(
    ...flaky.map((row) =>
      el(
        "li",
        {},
        `${row.name} `,
        el(
          "span",
          { class: "muted small" },
          `· ${row.repo} · ${row.count} times in 30 days`,
        ),
      ),
    ),
  );
}

async function load() {
  try {
    render(await callApi("/api/state"));
  } catch (err) {
    $("summary").textContent = `Could not reach the watcher: ${err.message}`;
  }
}

function notice(message) {
  const box = $("notice");
  box.textContent = message ?? "";
  box.hidden = !message;
}

async function act(path, body) {
  notice(null);
  try {
    await callApi(path, { method: "POST", body });
  } catch (err) {
    notice(err.message);
  }
  await load();
}

// --- Settings ---------------------------------------------------------------

const FIELDS = [
  "fastSeconds",
  "slowSeconds",
  "holdSeconds",
  "removeClosedHours",
];
let settingsFilled = false;

// Fills the form once, and again after a save, so a redraw never overwrites
// what the user is typing.
function fillSettings(state) {
  if (settingsFilled) return;
  for (const name of FIELDS) {
    const input = $(name);
    const [min, max] = state.limits[name];
    input.min = min;
    input.max = max;
    input.value = state.settings[name];
  }
  $("mergeMethod").replaceChildren(
    ...state.mergeMethods.map((method) =>
      el("option", { value: method }, method),
    ),
  );
  $("mergeMethod").value = state.settings.mergeMethod;
  $("autoWatch").checked = state.settings.autoWatch;
  settingsFilled = true;
}

$("settings-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const saved = $("settings-saved");
  const body = {
    mergeMethod: $("mergeMethod").value,
    autoWatch: $("autoWatch").checked,
  };
  for (const name of FIELDS) {
    const input = $(name);
    if (input.value.trim() === "" || !input.checkValidity()) {
      saved.textContent = `Enter a whole number from ${input.min} to ${input.max}`;
      saved.className = "error small";
      input.focus();
      return;
    }
    body[name] = Number(input.value);
  }
  try {
    await callApi("/api/settings", { method: "POST", body });
    saved.textContent = "Saved";
    saved.className = "muted small";
  } catch (err) {
    saved.textContent = err.message;
    saved.className = "error small";
  }
  settingsFilled = false;
  await load();
});

// --- Presence ---------------------------------------------------------------

// Tells the watcher whether this panel is showing, so it polls at the fast
// pace while someone is looking and re-checks at once when they come back.
function reportPresence() {
  const visible = document.visibilityState === "visible";
  callApi("/api/presence", { method: "POST", body: { visible } })
    .then(() => (visible ? load() : undefined))
    .catch(() => undefined);
}
document.addEventListener("visibilitychange", reportPresence);
setInterval(() => {
  if (document.visibilityState === "visible") reportPresence();
}, PRESENCE_MS);

// --- Adding a pull request --------------------------------------------------

const hasConversation = Boolean(sidecar.conversationId);
$("add-hint").textContent = hasConversation
  ? "This conversation will be woken when a check on the pull request starts failing."
  : "Open this panel from a conversation to watch a pull request.";
$("add-submit").disabled = !hasConversation;

$("add-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const error = $("add-error");
  error.hidden = true;
  $("add-submit").disabled = true;
  try {
    const uris = await sidecar.getWorkspaceUris();
    await callApi("/api/watch", {
      method: "POST",
      body: {
        ref: $("add-ref").value,
        conversationId: sidecar.conversationId,
        workspaceUri: uris[0],
      },
    });
    $("add-ref").value = "";
  } catch (err) {
    error.textContent = err.message;
    error.hidden = false;
  } finally {
    $("add-submit").disabled = !hasConversation;
  }
  await load();
});
$("add-ref").addEventListener("input", () => {
  $("add-error").hidden = true;
});

$("refresh").addEventListener("click", () => act("/api/refresh", {}));

load();
reportPresence();
setInterval(load, REDRAW_MS);
