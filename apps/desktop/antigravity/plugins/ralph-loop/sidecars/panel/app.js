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

function renderCard(loop) {
  const badgeTone = loop.active
    ? "run"
    : loop.status === "completed"
      ? "good"
      : loop.status === "max_iterations"
        ? "bad"
        : "done";

  const actions = [];
  if (loop.active) {
    actions.push(
      el(
        "button",
        {
          type: "button",
          class: "secondary",
          onclick: async () => {
            notice(null);
            try {
              await callApi("/api/wake-loop", {
                method: "POST",
                body: { conversationId: loop.conversationId },
              });
              await load();
            } catch (err) {
              notice(err.message);
            }
          },
        },
        "Wake now",
      ),
      el(
        "button",
        {
          type: "button",
          class: "secondary",
          onclick: async () => {
            notice(null);
            try {
              await callApi("/api/cancel-loop", {
                method: "POST",
                body: { conversationId: loop.conversationId },
              });
              await load();
            } catch (err) {
              notice(err.message);
            }
          },
        },
        "Cancel loop",
      ),
    );
  }

  return el(
    "article",
    { class: "card" },
    el(
      "div",
      { class: "card-header" },
      el("span", { class: "title" }, loop.conversationId),
      el("span", { class: `badge ${badgeTone}` }, loop.status || "idle"),
    ),
    loop.prompt ? el("p", { class: "small" }, loop.prompt) : null,
    el(
      "p",
      { class: "counts" },
      el(
        "span",
        {},
        `Iteration ${loop.iteration ?? 0}/${loop.maxIterations ?? 10}`,
      ),
      el(
        "span",
        { class: "muted" },
        `Promise: <promise>${loop.completionPromise || "DONE"}</promise>`,
      ),
    ),
    actions.length > 0 ? el("div", { class: "row" }, ...actions) : null,
  );
}

function render(state) {
  const items = state.loops ?? [];
  $("version").textContent = state.version ? `v${state.version}` : "";
  $("summary").textContent =
    `${state.summary?.activeCount ?? 0} active · ${items.length} total`;
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

const hasConv = Boolean(sidecar.conversationId);
$("start-hint").textContent = hasConv
  ? `Starts an iterative loop for conversation ${sidecar.conversationId}.`
  : "Open this panel from a conversation to start a loop.";

$("start-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const errBox = $("start-error");
  errBox.hidden = true;
  try {
    await callApi("/api/start-loop", {
      method: "POST",
      body: {
        conversationId: sidecar.conversationId || "default",
        prompt: $("loop-prompt").value,
        completionPromise: $("loop-promise").value,
        maxIterations: Number($("loop-max").value),
        notify: true,
      },
    });
    $("loop-prompt").value = "";
    await load();
  } catch (err) {
    errBox.textContent = err.message;
    errBox.hidden = false;
  }
});

$("refresh").addEventListener("click", load);

load();
setInterval(load, 5000);
