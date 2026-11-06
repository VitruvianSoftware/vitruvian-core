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

// Frontend for the receipts-report sidecar panel.

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

function renderProjectCard(proj) {
  const topTools = (proj.topTools ?? [])
    .map((t) => `${t.name} (${t.count})`)
    .join(" · ");
  const badgeTone =
    proj.errors > 0 ? "bad" : proj.truncatedSteps > 0 ? "wait" : "good";
  const badgeText =
    proj.errors > 0
      ? `${proj.errors} errors`
      : proj.truncatedSteps > 0
        ? `${proj.truncatedSteps} truncated`
        : "Healthy";

  return el(
    "article",
    { class: "card" },
    el(
      "div",
      { class: "card-header" },
      el("strong", { class: "title" }, proj.project),
      el("span", { class: `badge ${badgeTone}` }, badgeText),
    ),
    el(
      "p",
      { class: "counts" },
      el("span", {}, `${proj.conversations} sessions`),
      el("span", {}, `${proj.userPrompts} prompts`),
      el("span", { class: "run" }, `${proj.toolCalls} tool calls`),
      el("span", {}, `${proj.subagents} subagents`),
      el(
        "span",
        { class: "good" },
        `${proj.commits} commits · ${proj.prs} PRs`,
      ),
    ),
    topTools
      ? el("p", { class: "muted small" }, `Top tools: ${topTools}`)
      : null,
  );
}

function render(state) {
  const report = state.report ?? {};
  const totals = report.totals ?? {};
  const projects = report.projects ?? [];
  const hotspots = state.hotspots ?? [];

  $("version").textContent = state.version ? `v${state.version}` : "";
  $("summary").textContent =
    `${totals.conversations ?? 0} sessions across ${totals.projects ?? 0} projects · ~${(totals.estimatedTokens ?? 0).toLocaleString("en-US")} est. tokens`;

  if (state.settings) {
    $("windowDays").value = String(state.settings.windowDays ?? 14);
    if (document.activeElement !== $("projectFilter")) {
      $("projectFilter").value = state.settings.projectFilter ?? "";
    }
  }

  $("kpi-sessions").textContent = String(totals.conversations ?? 0);
  $("kpi-sessions-sub").textContent =
    `${totals.projects ?? 0} projects · ${totals.userPrompts ?? 0} prompts`;
  $("kpi-tools").textContent = String(totals.toolCalls ?? 0);
  $("kpi-tools-sub").textContent =
    `${totals.plannerTurns ?? 0} turns · ${totals.subagents ?? 0} subagents`;
  $("kpi-shipped").textContent = String(
    (totals.commits ?? 0) + (totals.prs ?? 0),
  );
  $("kpi-shipped-sub").textContent =
    `${totals.commits ?? 0} commits · ${totals.prs ?? 0} PRs`;
  $("kpi-hotspots").textContent = String(hotspots.length);
  $("kpi-hotspots-sub").textContent =
    `${totals.truncatedSteps ?? 0} truncated · ${totals.errors ?? 0} errors`;

  $("projects-list").replaceChildren(...projects.map(renderProjectCard));
  $("projects-empty").hidden = projects.length > 0;

  $("hotspots-count").textContent = String(hotspots.length);
  $("hotspots-list").replaceChildren(
    ...hotspots.map((h) =>
      el(
        "li",
        {},
        el(
          "span",
          {
            class: `badge ${h.severity === "danger" ? "bad" : h.severity === "warning" ? "wait" : "run"}`,
          },
          h.kind,
        ),
        ` ${h.summary}`,
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

$("scan-now").addEventListener("click", async () => {
  const state = await callApi("/api/scan", { method: "POST" });
  render(state);
});

$("filter-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const state = await callApi("/api/settings", {
    method: "POST",
    body: {
      windowDays: Number($("windowDays").value),
      projectFilter: $("projectFilter").value,
    },
  });
  render(state);
});

async function runExport(format) {
  const res = await callApi("/api/export", {
    method: "POST",
    body: { format },
  });
  const card = $("export-preview-card");
  card.hidden = false;
  card.open = true;
  $("export-preview-title").textContent = `Export Preview (${res.filename})`;
  $("export-preview").textContent = res.content;
}

$("export-csv").addEventListener("click", () => runExport("csv"));
$("export-html").addEventListener("click", () => runExport("html"));

load();
setInterval(load, 15000);
