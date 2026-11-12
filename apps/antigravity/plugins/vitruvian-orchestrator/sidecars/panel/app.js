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
    else if (name === "onclick" && typeof value === "function") {
      node.addEventListener("click", value);
    } else if (value !== false && value !== undefined && value !== null) {
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

function renderAgents(runs, members) {
  const container = $("agents-list");
  container.replaceChildren();
  $("agents-empty").hidden = runs.length > 0;
  $("agents-caption").textContent =
    `${runs.length} run${runs.length === 1 ? "" : "s"}`;

  const memberById = new Map();
  for (const group of [
    members?.active,
    members?.standingBy,
    members?.retired,
  ]) {
    if (!Array.isArray(group)) continue;
    for (const m of group) {
      if (m && typeof m.id === "string") {
        memberById.set(m.id, m);
      }
    }
  }

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
    const stallBadge =
      run.status === "running" &&
      (run.stallState === "quiet" ||
        run.stallState === "waiting" ||
        run.stallState === "stalled")
        ? el(
            "span",
            {
              class: `status-badge stall-badge ${
                run.stallState === "stalled"
                  ? "status-red"
                  : run.stallState === "waiting"
                    ? "status-blue"
                    : "status-amber"
              }`,
            },
            run.stallState,
          )
        : null;

    const member = memberById.get(run.id) || null;
    const isPausedOrKilled =
      member?.state === "paused" || member?.state === "killed";
    const statusBadge =
      member?.state === "paused"
        ? el(
            "span",
            {
              class: "status-badge status-amber",
              title: member.detail || undefined,
            },
            `paused: ${member.reason || "error"}`,
          )
        : member?.state === "killed"
          ? el("span", { class: "status-badge status-red" }, "killed")
          : el("span", { class: `status-badge ${tone}` }, run.status);

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
        statusBadge,
        isPausedOrKilled ? null : stallBadge,
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
let activeTab = "flow";
let boardFollow = true;
let lastAutoScrolledSeq = 0;
const expandedPostSeqs = new Set();

function postKindTone(kind) {
  switch (kind) {
    case "question":
      return "status-amber";
    case "defect":
      return "status-red";
    case "result":
      return "status-green";
    default:
      return "status-neutral";
  }
}

function memberStateTone(state) {
  switch (state) {
    case "working":
      return "status-blue";
    case "waiting":
    case "paused":
      return "status-amber";
    case "killed":
      return "status-red";
    default:
      return "status-neutral";
  }
}

function exceedsSixLines(text) {
  const str = String(text ?? "");
  const lines = str.split("\n");
  if (lines.length > 6) return true;
  let visualLines = 0;
  for (const line of lines) {
    visualLines += Math.max(1, Math.ceil(line.length / 68));
    if (visualLines > 6) return true;
  }
  return false;
}

function clipSingleLine(text, maxLen = 96) {
  const clean = String(text ?? "")
    .replace(/\s+/g, " ")
    .trim();
  if (clean.length <= maxLen) return clean;
  return `${clean.slice(0, maxLen - 1)}…`;
}

function formatRecipientLabel(raw) {
  const s = String(raw ?? "").trim();
  return s.toLowerCase() === "all" ? "everyone" : `@${s}`;
}

function syncSelectOptions(
  selectNode,
  defaultLabel,
  values,
  formatLabel = (v) => v,
) {
  if (!selectNode) return "";
  const current = String(selectNode.value ?? "");
  const preserved = values.includes(current) ? current : "";
  selectNode.replaceChildren(
    el(
      "option",
      { value: "", selected: preserved === "" ? true : false },
      defaultLabel,
    ),
    ...values.map((v) =>
      el(
        "option",
        { value: v, selected: preserved === v ? true : false },
        formatLabel(v),
      ),
    ),
  );
  selectNode.value = preserved;
  return preserved;
}

function syncFollowControls() {
  const followBtn = $("board-follow");
  const jumpBtn = $("board-jump-latest");
  if (followBtn) {
    followBtn.className = boardFollow
      ? "control-btn small active"
      : "control-btn small";
    followBtn.setAttribute("aria-pressed", boardFollow ? "true" : "false");
  }
  if (jumpBtn) {
    jumpBtn.hidden = boardFollow;
  }
}

function scrollBoardToLatest() {
  const list = $("board-list");
  if (!list) return;
  list.scrollTop = list.scrollHeight;
  const last = list.children?.[list.children.length - 1];
  if (last && typeof last.scrollIntoView === "function") {
    last.scrollIntoView({ block: "end" });
  }
}

function renderBoard(state, forceScroll = false) {
  const list = $("board-list");
  const empty = $("board-empty");
  const badge = $("tab-badge-board");
  if (!list || !empty) return;

  const now = typeof state?.now === "number" ? state.now : Date.now();
  const allPosts = Array.isArray(state?.posts)
    ? state.posts
    : Array.isArray(state?.flow?.posts)
      ? state.flow.posts
      : [];

  if (badge) {
    badge.hidden = allPosts.length === 0;
    badge.textContent = String(allPosts.length);
  }

  const authors = [
    ...new Set(
      allPosts.map((p) => String(p.from ?? "").trim()).filter(Boolean),
    ),
  ].sort();
  const recipients = [
    ...new Set(
      allPosts.flatMap((p) =>
        Array.isArray(p.to)
          ? p.to.map((r) => String(r ?? "").trim()).filter(Boolean)
          : [],
      ),
    ),
  ].sort();

  const fromFilter = syncSelectOptions(
    $("board-filter-from"),
    "All authors",
    authors,
  );
  const toFilter = syncSelectOptions(
    $("board-filter-to"),
    "All recipients",
    recipients,
    (v) => (String(v).toLowerCase() === "all" ? "everyone" : v),
  );
  const kindFilter = String($("board-filter-kind")?.value ?? "");
  const query = String($("board-search")?.value ?? "")
    .trim()
    .toLowerCase();

  const filtered = allPosts.filter((p) => {
    if (fromFilter && p.from !== fromFilter) return false;
    if (toFilter && !(Array.isArray(p.to) && p.to.includes(toFilter))) {
      return false;
    }
    if (kindFilter && p.kind !== kindFilter) return false;
    if (query) {
      const inText = String(p.text ?? "")
        .toLowerCase()
        .includes(query);
      const inFrom = String(p.from ?? "")
        .toLowerCase()
        .includes(query);
      const inTo = Array.isArray(p.to)
        ? p.to.some((r) => {
            const rl = String(r ?? "").toLowerCase();
            return (
              rl.includes(query) || (rl === "all" && "everyone".includes(query))
            );
          })
        : false;
      if (!inText && !inFrom && !inTo) return false;
    }
    return true;
  });

  list.replaceChildren();
  empty.hidden = filtered.length > 0;
  empty.textContent =
    allPosts.length === 0 ? "No board posts yet." : "No matching posts.";

  const postsDropped = Number(
    state?.postsDropped ?? state?.flow?.postsDropped ?? 0,
  );
  if (postsDropped > 0 && filtered.length > 0) {
    list.append(
      el(
        "div",
        { class: "muted small mono" },
        `${postsDropped} older posts not shown`,
      ),
    );
  }

  for (const post of filtered) {
    const kind = post.kind || "note";
    const rel = `${formatElapsed(Math.max(0, now - (post.at ?? now)))} ago`;
    const recipientsText =
      Array.isArray(post.to) && post.to.length > 0
        ? `→ ${post.to.map(formatRecipientLabel).join(", ")}`
        : "";
    const isLong = exceedsSixLines(post.text);
    const isExpanded = expandedPostSeqs.has(post.seq);

    const row = el(
      "div",
      { class: "post-row" },
      el(
        "div",
        { class: "post-header" },
        el(
          "div",
          { class: "post-header-left" },
          el("span", { class: "task-num mono muted" }, `#${post.seq}`),
          el("span", { class: "row-title" }, post.from || "unknown"),
          recipientsText
            ? el("span", { class: "muted small mono" }, recipientsText)
            : null,
          typeof post.replyTo === "number"
            ? el(
                "span",
                { class: "meta-chip mono muted" },
                `↩ #${post.replyTo}`,
              )
            : null,
        ),
        el(
          "div",
          { class: "post-header-right" },
          el("span", { class: "muted small mono" }, rel),
          el("span", { class: `status-badge ${postKindTone(kind)}` }, kind),
        ),
      ),
      el(
        "div",
        {
          class: isLong && !isExpanded ? "post-text clamped" : "post-text",
        },
        String(post.text ?? ""),
      ),
      isLong
        ? el(
            "button",
            {
              type: "button",
              class: "link-btn",
              onclick: () => {
                if (expandedPostSeqs.has(post.seq)) {
                  expandedPostSeqs.delete(post.seq);
                } else {
                  expandedPostSeqs.add(post.seq);
                }
                if (lastRenderedState) renderBoard(lastRenderedState, false);
              },
            },
            isExpanded ? "Show less" : "Show more",
          )
        : null,
    );
    list.append(row);
  }

  syncFollowControls();
  const maxSeq = allPosts.length > 0 ? allPosts[allPosts.length - 1].seq : 0;
  if (boardFollow && (forceScroll || maxSeq > lastAutoScrolledSeq)) {
    lastAutoScrolledSeq = maxSeq;
    scrollBoardToLatest();
  }
}

function renderMemberGroup(container, list, taskByN, postBySeq, now) {
  if (!container) return;
  container.replaceChildren();
  if (list.length === 0) {
    container.append(el("p", { class: "muted small" }, "None."));
    return;
  }

  for (const member of list) {
    const mascot = MASCOTS[member.agent] || "●";
    const task =
      typeof member.taskN === "number" ? taskByN.get(member.taskN) : null;
    const taskLabel =
      typeof member.taskN === "number"
        ? task?.title
          ? `#${member.taskN} · ${task.title}`
          : `#${member.taskN}`
        : null;
    const modelText = member.delegate
      ? `${member.model || "inherit"} → ${member.delegate}`
      : member.model || "inherit";
    const stateLabel =
      member.state === "paused"
        ? `paused: ${member.reason || "error"}`
        : member.state;
    const activityLabel = member.lastActivityAt
      ? `${formatElapsed(Math.max(0, now - member.lastActivityAt))} ago`
      : "—";
    const latestPost =
      typeof member.lastPostSeq === "number"
        ? postBySeq.get(member.lastPostSeq)
        : null;

    container.append(
      el(
        "div",
        { class: "member-card" },
        el(
          "div",
          { class: "member-top" },
          el(
            "div",
            { class: "row-main" },
            el(
              "span",
              { class: "agent-mascot", "aria-hidden": "true" },
              mascot,
            ),
            el("span", { class: "row-title" }, member.agent || "worker"),
            taskLabel ? el("span", { class: "muted small" }, taskLabel) : null,
          ),
          el(
            "div",
            { class: "row-meta" },
            el("span", { class: "meta-chip mono" }, modelText),
            el("span", { class: "meta-chip mono muted" }, activityLabel),
            el(
              "span",
              {
                class: `status-badge ${memberStateTone(member.state)}`,
                title: member.detail || undefined,
              },
              stateLabel,
            ),
          ),
        ),
        member.detail
          ? el("div", { class: "muted small member-post" }, member.detail)
          : null,
        latestPost
          ? el(
              "div",
              { class: "muted small member-post" },
              `Latest #${latestPost.seq}: ${clipSingleLine(latestPost.text)}`,
            )
          : null,
      ),
    );
  }
}

function renderMembers(state) {
  const groups = $("members-groups");
  const empty = $("members-empty");
  const caption = $("members-caption");
  const badge = $("tab-badge-members");
  if (!groups || !empty) return;

  const now = typeof state?.now === "number" ? state.now : Date.now();
  const active = Array.isArray(state?.members?.active)
    ? state.members.active
    : [];
  const standingBy = Array.isArray(state?.members?.standingBy)
    ? state.members.standingBy
    : [];
  const retired = Array.isArray(state?.members?.retired)
    ? state.members.retired
    : [];
  const total = active.length + standingBy.length + retired.length;

  if (badge) {
    badge.hidden = total === 0;
    badge.textContent = String(total);
  }
  if (caption) {
    caption.textContent = `${total} member${total === 1 ? "" : "s"}`;
  }
  empty.hidden = total > 0;
  groups.hidden = total === 0;
  if (total === 0) return;

  $("members-active-count").textContent = `(${active.length})`;
  $("members-standing-count").textContent = `(${standingBy.length})`;
  $("members-retired-count").textContent = `(${retired.length})`;

  const taskByN = new Map(
    (Array.isArray(state?.taskBoard) ? state.taskBoard : []).map((t) => [
      t.n,
      t,
    ]),
  );
  const allPosts = Array.isArray(state?.posts)
    ? state.posts
    : Array.isArray(state?.flow?.posts)
      ? state.flow.posts
      : [];
  const postBySeq = new Map(allPosts.map((p) => [p.seq, p]));

  renderMemberGroup($("members-active"), active, taskByN, postBySeq, now);
  renderMemberGroup($("members-standing"), standingBy, taskByN, postBySeq, now);
  renderMemberGroup($("members-retired"), retired, taskByN, postBySeq, now);
}

function setActiveTab(tab) {
  activeTab = tab;
  const tabs = ["flow", "board", "members"];
  for (const name of tabs) {
    const btn = $(`tab-btn-${name}`);
    const pane = $(`tab-pane-${name}`);
    const isActive = name === tab;
    if (btn) {
      btn.className = isActive ? "tab-btn active" : "tab-btn";
      btn.setAttribute("aria-selected", isActive ? "true" : "false");
    }
    if (pane) {
      pane.hidden = !isActive;
    }
  }
  if (tab === "flow" && lastRenderedState?.hasFlow) {
    renderBurnDownSvg(lastRenderedState.burnDown, lastRenderedState.totalTasks);
  } else if (tab === "board" && boardFollow) {
    scrollBoardToLatest();
  }
}

function wireBoardAndTabControls() {
  for (const name of ["flow", "board", "members"]) {
    const btn = $(`tab-btn-${name}`);
    if (btn) {
      btn.addEventListener("click", () => setActiveTab(name));
    }
  }

  const search = $("board-search");
  if (search) {
    search.addEventListener("input", () => {
      if (lastRenderedState) renderBoard(lastRenderedState, false);
    });
  }
  for (const id of [
    "board-filter-from",
    "board-filter-to",
    "board-filter-kind",
  ]) {
    const sel = $(id);
    if (sel) {
      sel.addEventListener("change", () => {
        if (lastRenderedState) renderBoard(lastRenderedState, false);
      });
    }
  }

  const followBtn = $("board-follow");
  if (followBtn) {
    followBtn.addEventListener("click", () => {
      boardFollow = !boardFollow;
      syncFollowControls();
      if (boardFollow) scrollBoardToLatest();
    });
  }

  const jumpBtn = $("board-jump-latest");
  if (jumpBtn) {
    jumpBtn.addEventListener("click", () => {
      boardFollow = true;
      syncFollowControls();
      scrollBoardToLatest();
    });
  }

  const boardList = $("board-list");
  if (boardList) {
    boardList.addEventListener("scroll", () => {
      const distanceFromBottom =
        boardList.scrollHeight - boardList.scrollTop - boardList.clientHeight;
      if (distanceFromBottom > 24 && boardFollow) {
        boardFollow = false;
        syncFollowControls();
      }
    });
  }
}

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

  const postCount = Array.isArray(state.posts)
    ? state.posts.length
    : Array.isArray(flow.posts)
      ? flow.posts.length
      : 0;
  const hasPosts =
    postCount > 0 || (state.postsDropped ?? flow.postsDropped ?? 0) > 0;
  const hasMemberEvents =
    Boolean(state.hasMemberEvents || flow.hasMemberEvents) ||
    (Array.isArray(flow.runs) &&
      flow.runs.some(
        (r) =>
          Boolean(r.paused) ||
          r.memberState === "killed" ||
          r.memberState === "retired",
      ));
  const showTabs = hasPosts || hasMemberEvents;
  const tabsEl = $("panel-tabs");
  if (tabsEl) {
    tabsEl.hidden = !showTabs;
  }
  if (!showTabs && activeTab !== "flow") {
    setActiveTab("flow");
  }

  const replanCount = state.burnDown?.replans?.length ?? 0;
  $("burndown-caption").textContent =
    `${state.remaining ?? 0} remaining${replanCount > 0 ? ` · ${replanCount} re-plan${replanCount === 1 ? "" : "s"}` : ""}`;
  renderBurnDownSvg(state.burnDown, state.totalTasks);
  renderTaskBoard(Array.isArray(state.taskBoard) ? state.taskBoard : []);
  renderAgents(Array.isArray(state.runs) ? state.runs : [], state.members);
  renderSpend(state.spend);
  renderBoard(state);
  renderMembers(state);
}

wireBoardAndTabControls();

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
