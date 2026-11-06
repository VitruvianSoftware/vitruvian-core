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

// Frontend for the live-context sidecar panel.

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
    else if (value !== false && value !== undefined)
      node.setAttribute(name, value === true ? "" : value);
  }
  for (const child of children) {
    if (child !== null && child !== undefined) node.append(child);
  }
  return node;
}

function render(state) {
  const settings = state.settings ?? {};
  const snapshot = state.snapshot ?? {};
  const git = snapshot.git ?? {};
  const github = snapshot.github ?? {};
  const verdicts = state.verdicts ?? [];

  $("version").textContent = state.version ? `v${state.version}` : "";
  const openCount = (github.openPrs ?? []).length;
  $("summary").textContent =
    `Branch: ${git.branch || "—"} · ${openCount} open PRs · Stop mode: ${settings.mode || "log"}`;

  if (
    !document.getElementById("settings-form").contains(document.activeElement)
  ) {
    $("injectGit").checked = settings.injectGit !== false;
    $("injectGitHub").checked = settings.injectGitHub !== false;
    $("injectContract").checked = settings.injectContract !== false;
    $("mode").value = settings.mode || "log";
    $("repo").value = settings.repo || "";
    $("contractText").value = settings.contractText || "";
  }

  $("preview-box").textContent =
    state.previewMessage || "(All context injections are currently disabled)";

  $("verdicts-count").textContent = String(verdicts.length);
  $("verdicts-empty").hidden = verdicts.length > 0;
  $("verdicts-list").replaceChildren(
    ...verdicts.map((v) =>
      el(
        "li",
        {},
        el(
          "span",
          { class: `badge ${v.verdict === "block" ? "bad" : "good"}` },
          v.verdict === "block" ? "BOUNCED" : "PASS",
        ),
        ` ${v.conversationId || "?"} (${v.chars ?? 0} chars, ${v.mode || "log"}) — `,
        el("span", { class: "muted small" }, v.tail || ""),
      ),
    ),
  );

  const dslBox = $("openui-dsl");
  if (dslBox && state.openuiDsl && dslBox.textContent !== state.openuiDsl) {
    dslBox.textContent = state.openuiDsl;
  }
}

async function load() {
  try {
    const state = await callApi("/api/state");
    render(state);
  } catch (err) {
    $("summary").textContent = `Error: ${err.message}`;
  }
}

$("refresh-now").addEventListener("click", async () => {
  const state = await callApi("/api/refresh", { method: "POST" });
  render(state);
});

$("settings-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const state = await callApi("/api/settings", {
    method: "POST",
    body: {
      injectGit: $("injectGit").checked,
      injectGitHub: $("injectGitHub").checked,
      injectContract: $("injectContract").checked,
      mode: $("mode").value,
      repo: $("repo").value,
      contractText: $("contractText").value,
    },
  });
  $("saved-status").textContent = "Saved";
  setTimeout(() => {
    $("saved-status").textContent = "";
  }, 2500);
  render(state);
});

load();
setInterval(load, 10000);
