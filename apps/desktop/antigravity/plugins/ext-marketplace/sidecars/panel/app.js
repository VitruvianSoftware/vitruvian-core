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

const sidecar = window.sidecar;
const $ = (id) => document.getElementById(id);
let latestState = null;

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

function showStatus(msg, isError = false) {
  const banner = $("status-banner");
  banner.hidden = false;
  banner.className = isError ? "small bad" : "small good";
  banner.textContent = msg;
}

function renderPlugins() {
  if (!latestState) return;
  const query = $("search-input").value.trim().toLowerCase();
  const filter = $("filter-select").value;
  const listNode = $("plugins-list");
  listNode.replaceChildren();

  const filtered = (latestState.plugins ?? []).filter((p) => {
    if (filter === "vitruvian" && p.source !== "vitruvian") return false;
    if (filter === "installed" && !p.installed) return false;
    if (filter === "enabled" && !p.enabled) return false;
    if (!query) return true;
    const hay =
      `${p.id} ${p.name} ${p.description} ${p.category}`.toLowerCase();
    return hay.includes(query);
  });

  for (const p of filtered) {
    const statusTone = p.enabled ? "good" : p.installed ? "wait" : "run";
    const statusLabel = p.enabled
      ? "Enabled"
      : p.installed
        ? "Disabled"
        : "Not installed";

    const caps = [];
    if (p.hasSidecarUi) caps.push("Sidecar UI");
    if (p.skills?.length) caps.push(`${p.skills.length} skill(s)`);
    if (p.hooks?.length) caps.push(`${p.hooks.length} hook(s)`);
    if (p.rules?.length) caps.push(`${p.rules.length} rule(s)`);

    const actions = el("div", { class: "row" });
    if (p.installed) {
      actions.append(
        el(
          "button",
          {
            type: "button",
            class: p.enabled ? "secondary" : "",
            onclick: async () => {
              try {
                latestState = await callApi("/api/toggle", {
                  method: "POST",
                  body: { name: p.id, enabled: !p.enabled },
                });
                showStatus(
                  `${p.name} ${!p.enabled ? "enabled" : "disabled"} in config.json.`,
                );
                renderState(latestState);
              } catch (err) {
                showStatus(err.message, true);
              }
            },
          },
          p.enabled ? "Disable" : "Enable",
        ),
        el(
          "button",
          {
            type: "button",
            class: "secondary",
            onclick: async () => {
              try {
                latestState = await callApi("/api/update", {
                  method: "POST",
                  body: { name: p.id },
                });
                showStatus(`Updated ${p.name}.`);
                renderState(latestState);
              } catch (err) {
                showStatus(err.message, true);
              }
            },
          },
          "Update",
        ),
        el(
          "button",
          {
            type: "button",
            class: "secondary",
            onclick: async () => {
              try {
                latestState = await callApi("/api/uninstall", {
                  method: "POST",
                  body: { name: p.id },
                });
                showStatus(`Uninstalled ${p.name}.`);
                renderState(latestState);
              } catch (err) {
                showStatus(err.message, true);
              }
            },
          },
          "Uninstall",
        ),
      );
    } else {
      actions.append(
        el(
          "button",
          {
            type: "button",
            onclick: async () => {
              try {
                latestState = await callApi("/api/install", {
                  method: "POST",
                  body: { name: p.id, repoUrl: p.repo },
                });
                showStatus(`Installed ${p.name}.`);
                renderState(latestState);
              } catch (err) {
                showStatus(err.message, true);
              }
            },
          },
          "Install",
        ),
      );
    }

    listNode.append(
      el(
        "div",
        { class: "card" },
        el(
          "div",
          { class: "card-header" },
          el(
            "div",
            {},
            el("span", { class: "title" }, p.name),
            el(
              "span",
              { class: "muted small" },
              ` (${p.id} · v${p.version || "0.1.0"})`,
            ),
          ),
          el("span", { class: `badge ${statusTone}` }, statusLabel),
        ),
        p.description ? el("p", { class: "small" }, p.description) : null,
        el(
          "div",
          { class: "row spread small muted" },
          el("span", {}, `${p.category} · ${p.source}`),
          el("span", {}, caps.join(" · ") || "Standard plugin"),
        ),
        actions,
      ),
    );
  }
}

function renderState(state) {
  latestState = state;
  if (state.version) {
    $("version").textContent = `v${state.version}`;
  }
  const c = state.counts ?? {};
  $("summary").textContent =
    `${c.catalog ?? 9} first-party · ${c.installed ?? 0} installed · ${c.enabled ?? 0} enabled`;
  renderPlugins();
  if (state.openuiDsl) {
    $("openui-dsl").textContent = state.openuiDsl;
  }
}

async function refresh() {
  try {
    const state = await callApi("/api/state");
    renderState(state);
  } catch (err) {
    showStatus(err.message, true);
  }
}

$("refresh").addEventListener("click", refresh);
$("search-input").addEventListener("input", renderPlugins);
$("filter-select").addEventListener("change", renderPlugins);

refresh();
