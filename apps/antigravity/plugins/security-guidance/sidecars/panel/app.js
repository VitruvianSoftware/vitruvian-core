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
const FONT_KEY = "cowork-artifact-fontscale";
const REDRAW_MS = 5000;

async function callApi(path, { method = "GET", body } = {}) {
  const res = await sidecar.fetch(path, {
    method,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `${res.status} ${res.statusText}`);
  return data;
}

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
  } catch {}
  return clamped;
}

let scale = applyScale(readScale());
$("font-down").addEventListener("click", () => {
  scale = applyScale(scale - 0.1);
});
$("font-up").addEventListener("click", () => {
  scale = applyScale(scale + 0.1);
});

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

function notice(msg) {
  const box = $("notice");
  box.textContent = msg ?? "";
  box.hidden = !msg;
}

function findingCard(f) {
  const tone =
    f.severity === "critical" || f.severity === "high"
      ? "bad"
      : f.severity === "medium"
        ? "wait"
        : "run";

  return el(
    "article",
    { class: "card" },
    el(
      "div",
      { class: "card-header" },
      el("span", { class: "title" }, `${f.ruleId} · ${f.filePath}:${f.line}`),
      el(
        "div",
        { class: "card-badges" },
        el("span", { class: `badge ${tone}` }, f.severity),
        el("span", { class: "badge done" }, f.cwe || "CWE"),
      ),
    ),
    el("p", { class: "small" }, f.message),
    f.snippet ? el("pre", { class: "log-box" }, f.snippet) : null,
    el("p", { class: "muted small" }, `Remediation: ${f.remediation}`),
    el(
      "div",
      { class: "row spread" },
      el(
        "button",
        {
          type: "button",
          class: "secondary small",
          onclick: async () => {
            try {
              await callApi("/api/suppress", {
                method: "POST",
                body: { id: f.id },
              });
              await load();
            } catch (err) {
              notice(err.message);
            }
          },
        },
        "Suppress",
      ),
      el(
        "button",
        {
          type: "button",
          class: "secondary small",
          onclick: async () => {
            try {
              await callApi("/api/wake-now", {
                method: "POST",
                body: {
                  id: f.id,
                  conversationId: sidecar.conversationId,
                },
              });
            } catch (err) {
              notice(err.message);
            }
          },
        },
        "Wake agent now",
      ),
    ),
  );
}

function render(state) {
  $("version").textContent = state.version ? `v${state.version}` : "";
  const counts = state.summary?.counts ?? {};
  $("summary").textContent =
    `${state.findings?.length ?? 0} active (${counts.critical ?? 0} critical, ${counts.high ?? 0} high) · ${state.suppressions?.length ?? 0} suppressed`;

  const findings = state.findings ?? [];
  $("findings-empty").hidden = findings.length > 0;
  $("findings-list").replaceChildren(...findings.map(findingCard));

  const suppressions = state.suppressions ?? [];
  $("suppressed-count").textContent = String(suppressions.length);
  $("suppressed-list").replaceChildren(
    ...suppressions.map((id) =>
      el(
        "li",
        { class: "row spread" },
        el("span", { class: "small" }, String(id)),
        el(
          "button",
          {
            type: "button",
            class: "secondary small",
            onclick: async () => {
              await callApi("/api/unsuppress", {
                method: "POST",
                body: { id },
              });
              await load();
            },
          },
          "Restore",
        ),
      ),
    ),
  );

  const patterns = state.patterns ?? [];
  $("patterns-count").textContent = String(patterns.length);
  $("patterns-list").replaceChildren(
    ...patterns.map((p) =>
      el(
        "li",
        {},
        el("strong", {}, `${p.id} `),
        el(
          "span",
          { class: "muted small" },
          `(${p.severity} · ${p.cwe}) — ${p.message}`,
        ),
      ),
    ),
  );

  const box = $("openui-dsl");
  if (box && box.textContent !== (state.openuiDsl ?? "")) {
    box.textContent = state.openuiDsl ?? "";
  }
}

async function load() {
  try {
    render(await callApi("/api/state"));
  } catch (err) {
    $("summary").textContent = `Could not reach sidecar: ${err.message}`;
  }
}

$("scan-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const out = $("scan-output");
  out.hidden = false;
  out.textContent = "Scanning…";
  try {
    const res = await callApi("/api/scan", {
      method: "POST",
      body: {
        filePath: $("scan-path").value,
        content: $("scan-content").value,
        record: $("scan-record").checked,
      },
    });
    out.textContent = JSON.stringify(res.findings, null, 2);
    await load();
  } catch (err) {
    out.textContent = `Error: ${err.message}`;
  }
});

$("clear-findings").addEventListener("click", async () => {
  await callApi("/api/clear", { method: "POST", body: {} });
  await load();
});

$("refresh").addEventListener("click", load);
load();
setInterval(load, REDRAW_MS);
