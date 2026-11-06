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

const PHASES = ["plan", "design", "delegate", "review", "close"];
const SVG_NS = "http://www.w3.org/2000/svg";

const MASCOTS = {
  lead: "◈",
  beacon: "◈",
  wren: "🐦",
  atlas: "🌐",
  ridge: "⛰",
  forge: "⚒",
  scout: "🔭",
  aegis: "🛡",
  compass: "🧭",
  pace: "⏱",
  quill: "✒",
};

async function callApi(path) {
  const fetcher = sidecar?.fetch
    ? sidecar.fetch.bind(sidecar)
    : window.fetch.bind(window);
  const res = await fetcher(path, { method: "GET" });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.error || `${res.status} ${res.statusText}`);
  }
  return data;
}

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) {
    if (name === "class") node.className = value;
    else if (value !== false && value !== undefined && value !== null) {
      node.setAttribute(name, value === true ? "" : String(value));
    }
  }
  for (const child of children) {
    if (child !== null && child !== undefined) node.append(child);
  }
  return node;
}

function svgEl(tag, attrs = {}, ...children) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [name, value] of Object.entries(attrs)) {
    if (value !== undefined && value !== null) {
      node.setAttribute(name, String(value));
    }
  }
  for (const child of children) {
    if (child !== null && child !== undefined) node.append(child);
  }
  return node;
}

function formatUsd(usd) {
  const val = Number(usd ?? 0) || 0;
  return `$${val < 10 ? val.toFixed(2) : val.toFixed(1)}`;
}

function formatTokens(count) {
  const n = Math.max(0, Number(count ?? 0) || 0);
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1).replace(/\.0$/, "")}k`;
  return `${Math.round(n)}`;
}

function formatElapsed(ms) {
  const totalSec = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
  if (totalSec < 60) {
    return `${totalSec}s`;
  }
  if (totalSec < 3600) {
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    return `${m}m ${String(s).padStart(2, "0")}s`;
  }
  if (totalSec < 86400) {
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    return `${h}h ${String(m).padStart(2, "0")}m`;
  }
  const d = Math.floor(totalSec / 86400);
  const h = Math.floor((totalSec % 86400) / 3600);
  return `${d}d ${h}h`;
}

function statusTone(state) {
  switch (state) {
    case "accepted":
    case "done":
      return "status-green";
    case "running":
      return "status-blue";
    case "review":
    case "waiting":
      return "status-amber";
    case "returned":
    case "error":
      return "status-red";
    default:
      return "status-neutral";
  }
}

function renderPhasePills(currentPhase, isClosed) {
  const container = $("phase-pills");
  container.replaceChildren();
  const currentIdx = PHASES.indexOf(currentPhase);

  for (let i = 0; i < PHASES.length; i += 1) {
    const phase = PHASES[i];
    const isDone = isClosed || (currentIdx !== -1 && i < currentIdx);
    const isCurrent = !isClosed && i === currentIdx;
    const cls = isCurrent
      ? "phase-pill current"
      : isDone
        ? "phase-pill done"
        : "phase-pill";
    const label = isDone ? `✓ ${phase}` : phase;
    container.append(el("span", { class: cls }, label));
  }
}

function renderBurnDownSvg(burn, totalTasks) {
  const container = $("burndown-container");
  container.replaceChildren();

  const points = Array.isArray(burn?.points) ? burn.points : [];
  const ideal = Array.isArray(burn?.ideal) ? burn.ideal : [];
  const replans = Array.isArray(burn?.replans) ? burn.replans : [];

  if (points.length === 0) {
    container.append(
      el("p", { class: "muted small" }, "No burn-down history points yet."),
    );
    return;
  }

  const width = Math.max(240, Math.round(container.clientWidth || 360));
  const height = 116;
  const padLeft = 28;
  const padRight = 16;
  const padTop = 14;
  const padBottom = 22;
  const plotW = width - padLeft - padRight;
  const plotH = height - padTop - padBottom;

  const allTimes = [
    ...points.map((p) => p.at),
    ...ideal.map((p) => p.at),
    ...replans.map((r) => r.at),
  ].filter((t) => typeof t === "number" && Number.isFinite(t));

  const minAt = allTimes.length > 0 ? Math.min(...allTimes) : 0;
  const maxAt = allTimes.length > 0 ? Math.max(...allTimes) : minAt;
  const spanAt = Math.max(1, maxAt - minAt);

  const maxRem = Math.max(
    1,
    totalTasks || 1,
    ...points.map((p) => p.remaining),
    ...ideal.map((p) => p.remaining),
    ...replans.map((r) => r.total),
  );

  const toX = (at, idx, len) => {
    if (maxAt === minAt) {
      if (len <= 1) return padLeft + plotW / 2;
      return padLeft + (idx / (len - 1)) * plotW;
    }
    return padLeft + ((at - minAt) / spanAt) * plotW;
  };
  const toY = (val) => padTop + (1 - Math.max(0, val) / maxRem) * plotH;

  const svg = svgEl("svg", {
    viewBox: `0 0 ${width} ${height}`,
    width: String(width),
    height: String(height),
    class: "burndown-svg",
    role: "img",
    "aria-label": "Remaining tasks burn-down chart",
  });

  // Horizontal baseline & top guide
  svg.append(
    svgEl("line", {
      x1: padLeft,
      y1: toY(maxRem),
      x2: width - padRight,
      y2: toY(maxRem),
      class: "burndown-grid",
    }),
    svgEl("line", {
      x1: padLeft,
      y1: toY(0),
      x2: width - padRight,
      y2: toY(0),
      class: "burndown-grid",
    }),
    svgEl(
      "text",
      {
        x: padLeft - 6,
        y: toY(maxRem) + 4,
        "text-anchor": "end",
        class: "burndown-axis-text",
      },
      String(maxRem),
    ),
    svgEl(
      "text",
      {
        x: padLeft - 6,
        y: toY(0) + 4,
        "text-anchor": "end",
        class: "burndown-axis-text",
      },
      "0",
    ),
  );

  // Dashed ideal line
  if (ideal.length >= 2) {
    const x1 = toX(ideal[0].at, 0, 2);
    const y1 = toY(ideal[0].remaining);
    const x2 = maxAt === minAt ? width - padRight : toX(ideal[1].at, 1, 2);
    const y2 = toY(ideal[1].remaining);
    svg.append(
      svgEl("line", {
        x1: x1.toFixed(1),
        y1: y1.toFixed(1),
        x2: x2.toFixed(1),
        y2: y2.toFixed(1),
        class: "burndown-ideal",
        "stroke-dasharray": "4 4",
      }),
    );
  }

  // Re-plan vertical markers
  for (let i = 0; i < replans.length; i += 1) {
    const rp = replans[i];
    const rx = toX(rp.at, i, replans.length);
    const ry = toY(rp.total);
    svg.append(
      svgEl("line", {
        x1: rx.toFixed(1),
        y1: padTop,
        x2: rx.toFixed(1),
        y2: height - padBottom,
        class: "burndown-replan-line",
        "stroke-dasharray": "2 2",
      }),
      svgEl("polygon", {
        points: `${rx.toFixed(1)},${(ry - 4).toFixed(1)} ${(rx + 4).toFixed(1)},${ry.toFixed(1)} ${rx.toFixed(1)},${(ry + 4).toFixed(1)} ${(rx - 4).toFixed(1)},${ry.toFixed(1)}`,
        class: "burndown-replan-marker",
      }),
      svgEl(
        "text",
        {
          x: rx.toFixed(1),
          y: height - 5,
          // Anchor toward the inside so a re-plan near either edge is not clipped.
          "text-anchor":
            rx > width * 0.8 ? "end" : rx < width * 0.2 ? "start" : "middle",
          class: "burndown-replan-text",
        },
        `re-plan (${rp.total})`,
      ),
    );
  }

  // Actual remaining polyline & points
  const polyCoords = points
    .map((p, idx) => {
      const x = toX(p.at, idx, points.length);
      const y = toY(p.remaining);
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");

  if (points.length > 1) {
    svg.append(
      svgEl("polyline", {
        points: polyCoords,
        fill: "none",
        class: "burndown-actual",
      }),
    );
  }

  for (let i = 0; i < points.length; i += 1) {
    const p = points[i];
    const cx = toX(p.at, i, points.length);
    const cy = toY(p.remaining);
    svg.append(
      svgEl("circle", {
        cx: cx.toFixed(1),
        cy: cy.toFixed(1),
        r: 3.5,
        class: "burndown-point",
      }),
    );
  }

  container.append(svg);
}

function renderTaskBoard(rows) {
  const container = $("task-board");
  container.replaceChildren();
  $("tasks-caption").textContent =
    `${rows.length} task${rows.length === 1 ? "" : "s"}`;

  for (const row of rows) {
    const tone = statusTone(row.state);
    const metaBadges = [
      el("span", { class: "meta-chip mono" }, row.specialist || "wren"),
      el("span", { class: "meta-chip tier-chip" }, row.tier || "core"),
    ];
    if (row.round > 0) {
      metaBadges.push(
        el("span", { class: "meta-chip status-red" }, `round ${row.round}`),
      );
    }
    if (Array.isArray(row.waitingOn) && row.waitingOn.length > 0) {
      metaBadges.push(
        el(
          "span",
          { class: "meta-chip status-amber" },
          `waits on ${row.waitingOn.map((n) => `#${n}`).join(", ")}`,
        ),
      );
    }

    const item = el(
      "div",
      { class: "row-item task-row" },
      el(
        "div",
        { class: "row-main" },
        el("span", { class: "task-num mono muted" }, `#${row.n}`),
        el("span", { class: "row-title" }, row.title),
      ),
      el(
        "div",
        { class: "row-meta" },
        ...metaBadges,
        el("span", { class: `status-badge ${tone}` }, row.state),
      ),
    );
    container.append(item);
  }
}

function renderAgents(runs) {
  const container = $("agents-list");
  container.replaceChildren();
  $("agents-empty").hidden = runs.length > 0;
  $("agents-caption").textContent =
    `${runs.length} run${runs.length === 1 ? "" : "s"}`;

  for (const run of runs) {
    const mascot = MASCOTS[run.agent] || "●";
    const tone = statusTone(run.status);
    const modelLabel = run.effort
      ? `${run.model || "inherit"} · ${run.effort}`
      : run.model || "inherit";

    let progressLabel = "—";
    if (
      run.steps &&
      typeof run.steps.total === "number" &&
      run.steps.total > 0
    ) {
      progressLabel = `${run.steps.done}/${run.steps.total}${run.steps.note ? ` · ${run.steps.note}` : ""}`;
    } else if (typeof run.contextPct === "number") {
      progressLabel = `${Math.round(run.contextPct)}% ctx`;
    }

    const costLabel =
      typeof run.cost === "number" ? `est. ${formatUsd(run.cost)}` : "unpriced";
    const tokensLabel = `${formatTokens(run.totalTokens ?? 0)} tkn`;
    const elapsedLabel = formatElapsed(run.elapsedMs ?? 0);

    const row = el(
      "div",
      { class: "row-item agent-row" },
      el(
        "div",
        { class: "row-main" },
        el("span", { class: "agent-mascot", "aria-hidden": "true" }, mascot),
        el("span", { class: "row-title" }, run.agent || "worker"),
        run.title
          ? el("span", { class: "muted small" }, `· ${run.title}`)
          : null,
      ),
      el(
        "div",
        { class: "row-meta" },
        el("span", { class: "meta-chip mono" }, modelLabel),
        el("span", { class: "meta-chip" }, progressLabel),
        el("span", { class: "meta-chip mono" }, tokensLabel),
        el("span", { class: "meta-chip mono" }, costLabel),
        el("span", { class: "meta-chip mono muted" }, elapsedLabel),
        el("span", { class: `status-badge ${tone}` }, run.status),
      ),
    );
    container.append(row);
  }
}

function renderSpend(spendSummary) {
  const sp = spendSummary || {
    total: 0,
    byModel: {},
    lead: 0,
    workers: 0,
    unpriced: { runs: 0, tokens: 0 },
  };
  $("spend-total").textContent = `est. ${formatUsd(sp.total)}`;

  const rolesNode = $("spend-roles");
  rolesNode.replaceChildren(
    el(
      "div",
      { class: "spend-pill" },
      el("span", { class: "muted small" }, "Lead"),
      el("strong", { class: "mono small" }, `est. ${formatUsd(sp.lead)}`),
    ),
    el(
      "div",
      { class: "spend-pill" },
      el("span", { class: "muted small" }, "Workers"),
      el("strong", { class: "mono small" }, `est. ${formatUsd(sp.workers)}`),
    ),
  );

  const modelsNode = $("spend-models");
  modelsNode.replaceChildren();
  for (const [model, cost] of Object.entries(sp.byModel || {})) {
    modelsNode.append(
      el(
        "div",
        { class: "spend-pill" },
        el("span", { class: "mono small" }, model),
        el("strong", { class: "mono small" }, `est. ${formatUsd(cost)}`),
      ),
    );
  }

  const unpricedNode = $("spend-unpriced");
  const unpricedRuns = sp.unpriced?.runs ?? 0;
  const unpricedTokens = sp.unpriced?.tokens ?? 0;
  if (unpricedRuns > 0) {
    unpricedNode.hidden = false;
    unpricedNode.textContent = `Unpriced runs (${unpricedRuns}): ${formatTokens(unpricedTokens)} tokens`;
  } else {
    unpricedNode.hidden = true;
    unpricedNode.textContent = "";
  }
}

let lastRenderedState = null;

function renderState(state) {
  lastRenderedState = state;
  const hasFlow = Boolean(state?.hasFlow && state?.flow);
  $("empty-state").hidden = hasFlow;
  $("flow-view").hidden = !hasFlow;
  if (!hasFlow) return;

  const flow = state.flow;
  $("flow-title").textContent =
    state.title || flow.title || "Orchestrator Flow";
  const cidShort = state.conversationId
    ? state.conversationId.slice(0, 8)
    : "local";
  $("flow-meta").textContent = `v${state.version || "0.2.0"} · ${cidShort}`;

  $("accepted-summary").textContent =
    `accepted ${state.accepted ?? 0} of ${state.totalTasks ?? 0}`;

  const totalUsd = state.spend?.total ?? 0;
  const unpricedTokens = state.spend?.unpriced?.tokens ?? 0;
  $("cost-summary").textContent =
    totalUsd === 0 && unpricedTokens > 0
      ? `est. $0.00 · ${formatTokens(unpricedTokens)} tkn`
      : `est. ${formatUsd(totalUsd)}`;

  renderPhasePills(state.phase || flow.phase || "plan", Boolean(flow.closedAt));

  const replanCount = state.burnDown?.replans?.length ?? 0;
  $("burndown-caption").textContent =
    `${state.remaining ?? 0} remaining${replanCount > 0 ? ` · ${replanCount} re-plan${replanCount === 1 ? "" : "s"}` : ""}`;
  renderBurnDownSvg(state.burnDown, state.totalTasks);
  renderTaskBoard(Array.isArray(state.taskBoard) ? state.taskBoard : []);
  renderAgents(Array.isArray(state.runs) ? state.runs : []);
  renderSpend(state.spend);
}

async function refresh() {
  const cid = sidecar?.conversationId || "";
  const query = cid ? `?cid=${encodeURIComponent(cid)}` : "";
  try {
    const state = await callApi(`/api/state${query}`);
    renderState(state);
  } catch {
    // Keep last rendered state on transient poll error.
  }
}

window.addEventListener("resize", () => {
  if (lastRenderedState?.hasFlow) {
    renderBurnDownSvg(lastRenderedState.burnDown, lastRenderedState.totalTasks);
  }
});

refresh();
setInterval(refresh, 2500);
