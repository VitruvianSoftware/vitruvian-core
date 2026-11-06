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

function ruleCard(rule) {
  const isGlobal = rule.source === "global";
  const tone =
    rule.enabled === false
      ? "done"
      : rule.action === "block" || rule.action === "deny"
        ? "bad"
        : rule.action === "overwrite"
          ? "run"
          : "wait";

  const toggle = el("input", {
    type: "checkbox",
    disabled: !isGlobal,
    onchange: async (e) => {
      try {
        await callApi("/api/rules/toggle", {
          method: "POST",
          body: { id: rule.id || rule.name, enabled: e.target.checked },
        });
      } catch (err) {
        notice(err.message);
      }
      await load();
    },
  });
  toggle.checked = rule.enabled !== false;

  const condSummary = (rule.conditions ?? [])
    .map((c) => `${c.field} ${c.operator} ${JSON.stringify(c.pattern)}`)
    .join(" AND ");

  return el(
    "article",
    { class: "card" },
    el(
      "div",
      { class: "card-header" },
      el("span", { class: "title" }, rule.name),
      el(
        "div",
        { class: "card-badges" },
        el("span", { class: "badge done" }, rule.event || "PreToolUse"),
        el("span", { class: `badge ${tone}` }, rule.action || "warn"),
      ),
    ),
    el("p", { class: "muted small" }, condSummary || "No conditions"),
    el("p", { class: "small" }, rule.message || ""),
    el(
      "div",
      { class: "row spread" },
      el("label", { class: "check" }, toggle, "Enabled"),
      isGlobal
        ? el(
            "button",
            {
              type: "button",
              class: "secondary small",
              onclick: async () => {
                try {
                  await callApi("/api/rules/delete", {
                    method: "POST",
                    body: { id: rule.id || rule.name },
                  });
                } catch (err) {
                  notice(err.message);
                }
                await load();
              },
            },
            "Delete",
          )
        : el("span", { class: "muted small" }, String(rule.source)),
    ),
  );
}

function render(state) {
  $("version").textContent = state.version ? `v${state.version}` : "";
  const s = state.summary ?? {};
  $("summary").textContent =
    `${s.activeRules ?? 0} active rules · ${s.blockedEvents ?? 0} blocked · ${s.warnEvents ?? 0} warnings`;

  const rules = state.rules ?? [];
  $("rules-empty").hidden = rules.length > 0;
  $("rules-list").replaceChildren(...rules.map(ruleCard));

  const events = state.events ?? [];
  $("events-count").textContent = String(events.length);
  $("events-list").replaceChildren(
    ...events.map((ev) =>
      el(
        "li",
        {},
        el("strong", {}, `[${ev.decision}] `),
        `${ev.tool} · ${(ev.rules ?? []).join(", ")} `,
        el("span", { class: "muted small" }, ev.reason ?? ""),
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

$("rule-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  notice(null);
  try {
    await callApi("/api/rules", {
      method: "POST",
      body: {
        name: $("rule-name").value,
        event: $("rule-event").value,
        action: $("rule-action").value,
        field: $("rule-field").value,
        operator: $("rule-operator").value,
        pattern: $("rule-pattern").value,
        message: $("rule-message").value,
      },
    });
    $("rule-name").value = "";
    $("rule-pattern").value = "";
    $("rule-message").value = "";
    await load();
  } catch (err) {
    notice(err.message);
  }
});

$("test-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const out = $("test-output");
  out.hidden = false;
  out.textContent = "Evaluating…";
  try {
    const res = await callApi("/api/test", {
      method: "POST",
      body: {
        event: $("test-event").value,
        tool: $("test-tool").value,
        CommandLine: $("test-input").value,
        reason: $("test-input").value,
      },
    });
    out.textContent = JSON.stringify(res.result, null, 2);
  } catch (err) {
    out.textContent = `Error: ${err.message}`;
  }
});

$("clear-events").addEventListener("click", async () => {
  await callApi("/api/events/clear", { method: "POST", body: {} });
  await load();
});

$("refresh").addEventListener("click", load);
load();
setInterval(load, REDRAW_MS);
