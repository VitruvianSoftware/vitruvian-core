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

function renderState(state) {
  if (state.version) {
    $("version").textContent = `v${state.version}`;
  }
  const cidShort = state.conversationId
    ? state.conversationId.slice(0, 8)
    : "no active conversation";
  $("summary").textContent =
    `${cidShort} · ${state.totalSteps ?? 0} steps · ${state.toolCalls ?? 0} tool calls`;

  const flow = state.flow ?? {};
  $("flow-title").textContent = flow.title || "savvy-flow";
  $("phase-badge").textContent = flow.isFinished
    ? "close"
    : flow.phase || "plan";
  $("flow-progress-bar").style.width = `${flow.progressPct ?? 0}%`;

  const counts = state.counts ?? { running: 0, finished: 0, planned: 0 };
  $("flow-counts").textContent =
    `${counts.running} running · ${counts.finished} done · ${counts.planned} planned`;
  $("flow-cost").textContent =
    `≈${state.totals?.formattedCost ?? "$0.00"} · ${state.totals?.formattedTokens ?? "0"} tokens`;

  const subagents = Array.isArray(state.subagents) ? state.subagents : [];
  const listNode = $("subagents-list");
  listNode.replaceChildren();
  $("subagents-empty").hidden = subagents.length > 0;

  for (const agent of subagents) {
    const badgeTone =
      agent.status === "done"
        ? "good"
        : agent.status === "failed"
          ? "bad"
          : "run";
    const card = el(
      "div",
      { class: "card agent-card" },
      el(
        "div",
        { class: "card-header" },
        el(
          "div",
          {},
          el("span", { class: "title" }, agent.role || agent.type),
          el(
            "span",
            { class: "muted small" },
            ` (${agent.type} · ${agent.tier})`,
          ),
        ),
        el("span", { class: `badge ${badgeTone}` }, agent.status),
      ),
      el(
        "div",
        { class: "row spread small muted" },
        el(
          "span",
          {},
          `model: ${agent.model || "inherit"} · round ${agent.round || 1}`,
        ),
        el(
          "span",
          {},
          `≈${agent.formattedCost || "$0.00"} · ${agent.formattedTokens || "0"} tkn`,
        ),
      ),
    );
    listNode.append(card);
  }

  const planned = Array.isArray(state.planned) ? state.planned : [];
  const plannedSection = $("planned-section");
  const plannedList = $("planned-list");
  plannedList.replaceChildren();
  plannedSection.hidden = planned.length === 0;
  for (const task of planned) {
    plannedList.append(
      el(
        "div",
        { class: "card" },
        el(
          "div",
          { class: "card-header" },
          el("span", { class: "title" }, `${task.number}. ${task.title}`),
          el("span", { class: "badge wait" }, task.tier || "medium"),
        ),
      ),
    );
  }

  const breakdown = state.toolsBreakdown ?? {};
  const toolEntries = Object.entries(breakdown);
  $("tools-count").textContent = String(state.toolCalls ?? 0);
  const toolsGrid = $("tools-grid");
  toolsGrid.replaceChildren();
  for (const [toolName, count] of toolEntries) {
    toolsGrid.append(
      el(
        "div",
        { class: "tool-pill" },
        el("span", { class: "mono small" }, toolName),
        el("strong", { class: "small" }, String(count)),
      ),
    );
  }

  if (state.openuiDsl) {
    $("openui-dsl").textContent = state.openuiDsl;
  }
}

async function refresh() {
  const cid = sidecar?.conversationId || "";
  try {
    const state = await callApi(`/api/state?cid=${encodeURIComponent(cid)}`);
    renderState(state);
  } catch (err) {
    $("summary").textContent = `Error: ${err.message}`;
  }
}

$("refresh").addEventListener("click", () => {
  refresh();
});

$("phase-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const cid = sidecar?.conversationId || "";
  const title = $("flow-name-input").value.trim();
  const phase = $("flow-phase-select").value;
  const state = await callApi("/api/progress", {
    method: "POST",
    body: {
      cid,
      ...(title ? { title } : {}),
      phase,
      finished: phase === "close",
    },
  });
  $("flow-name-input").value = "";
  renderState(state);
});

refresh();
setInterval(refresh, 4000);
