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

/* global document, setInterval, window */

const sidecar = window.sidecar;
const $ = (id) => document.getElementById(id);

async function callApi(path, { method = "GET", body } = {}) {
  const res = await sidecar.fetch(path, {
    method,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `${res.status} ${res.statusText}`);
  return data;
}

function fmtSize(kb) {
  if (kb === null || kb === undefined || !Number.isFinite(Number(kb)))
    return "…";
  const n = Number(kb);
  if (n >= 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} GB`;
  if (n >= 1024) return `${Math.round(n / 1024)} MB`;
  return `${Math.max(0, Math.round(n))} KB`;
}

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) {
    if (name === "class") node.className = value;
    else if (name.startsWith("on")) node.addEventListener(name.slice(2), value);
    else if (value !== false && value !== undefined) {
      node.setAttribute(name, value === true ? "" : value);
    }
  }
  for (const child of children) {
    if (child !== null && child !== undefined) node.append(child);
  }
  return node;
}

function notice(message) {
  const box = $("notice");
  box.textContent = message ?? "";
  box.hidden = !message;
}

function renderCard(w) {
  const pr = w.pr;
  const c = pr?.checks;
  const prText = !pr
    ? "no PR"
    : pr.state === "MERGED"
      ? `PR #${pr.number} merged`
      : pr.state === "CLOSED"
        ? `PR #${pr.number} closed`
        : !c || c.total === 0
          ? `PR #${pr.number}${pr.isDraft ? " draft" : ""}`
          : c.failed > 0
            ? `PR #${pr.number} · ${c.failed} failed`
            : c.running > 0
              ? `PR #${pr.number} · ${c.passed}/${c.total} running`
              : `PR #${pr.number} · ${c.passed}/${c.total} passed`;

  const badgeTone =
    w.cleanup === "ready" || w.cleanup === "done"
      ? "good"
      : w.cleanup === "blocked" || w.cleanup === "failed"
        ? "bad"
        : "run";

  const cacheKb = Array.isArray(w.caches)
    ? w.caches.reduce((s, item) => s + (Number(item?.kb) || 0), 0)
    : 0;

  const actions = [];
  if (w.cleanup === "ready") {
    actions.push(
      el(
        "button",
        {
          type: "button",
          onclick: async () => {
            notice(null);
            try {
              await callApi("/api/cleanup", {
                method: "POST",
                body: { root: w.root },
              });
              await load();
            } catch (err) {
              notice(err.message);
            }
          },
        },
        `Clean up ${fmtSize((w.treeKb || 0) + cacheKb)}`,
      ),
    );
  }

  return el(
    "article",
    { class: "card" },
    el(
      "div",
      { class: "card-header" },
      el("span", { class: "title" }, `⎇ ${w.branch || w.root}`),
      el("span", { class: `badge ${badgeTone}` }, w.cleanup || "active"),
    ),
    el("p", { class: "muted small" }, w.root),
    el(
      "p",
      { class: "counts" },
      el("span", {}, prText),
      el("span", { class: "muted" }, `tree ${fmtSize(w.treeKb)}`),
      el("span", { class: "muted" }, `bazel ${fmtSize(cacheKb)}`),
    ),
    w.note ? el("p", { class: "muted small" }, w.note) : null,
    actions.length > 0 ? el("div", { class: "row" }, ...actions) : null,
  );
}

function render(state) {
  const items = state.worktrees ?? [];
  $("version").textContent = state.version ? `v${state.version}` : "";
  $("summary").textContent =
    `${items.length} tracked · ${state.summary?.readyCount ?? 0} ready to clean`;
  $("list").replaceChildren(...items.map(renderCard));
  $("empty").hidden = items.length > 0;
  const dslBox = $("openui-dsl");
  if (dslBox && typeof state.openuiDsl === "string") {
    dslBox.textContent = state.openuiDsl;
  }
}

async function load() {
  try {
    render(await callApi("/api/state"));
  } catch (err) {
    $("summary").textContent = `Could not reach sidecar: ${err.message}`;
  }
}

$("track-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const errBox = $("track-error");
  errBox.hidden = true;
  try {
    const uris = (await sidecar.getWorkspaceUris?.()) ?? [];
    await callApi("/api/track", {
      method: "POST",
      body: {
        path: $("track-path").value,
        workspaceUri: uris[0],
        conversationId: sidecar.conversationId,
      },
    });
    $("track-path").value = "";
    await load();
  } catch (err) {
    errBox.textContent = err.message;
    errBox.hidden = false;
  }
});

$("refresh").addEventListener("click", async () => {
  notice(null);
  try {
    await callApi("/api/refresh", {
      method: "POST",
      body: { withSizes: true },
    });
    await load();
  } catch (err) {
    notice(err.message);
  }
});

load();
setInterval(load, 10_000);
