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

// Shared OpenUI Lang v0.5 parser, AST resolver, and HTML/DOM renderer for
// Antigravity scheduled automations, skills, and sidecar UI plugins.

/**
 * Escapes HTML special characters to prevent layout bleed-through or XSS.
 * @param {unknown} value
 * @returns {string}
 */
export function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/**
 * Resolves a dotted data path against a context object, supporting OpenUI Lang
 * column plucking when traversing through an array of row objects
 * (e.g. `data.rows.month` -> `["Jan", "Feb", ...]`).
 *
 * @param {Record<string, any>} context
 * @param {string} pathStr
 * @returns {any}
 */
export function resolveDataPath(context, pathStr) {
  const parts = pathStr.split(".");
  let current = context;
  for (let i = 0; i < parts.length; i++) {
    if (current === null || current === undefined) return undefined;
    const key = parts[i];
    if (Array.isArray(current)) {
      const rest = parts.slice(i).join(".");
      return current.map((item) => resolveDataPath(item, rest));
    }
    current = current[key];
  }
  return current;
}

/**
 * Tokenizes an OpenUI Lang v0.5 source string.
 * @param {string} input
 */
function tokenize(input) {
  const tokens = [];
  let i = 0;
  const len = input.length;

  while (i < len) {
    const ch = input[i];
    if (ch === " " || ch === "\t" || ch === "\r" || ch === "\n") {
      i++;
      continue;
    }
    // Line comments (# or //)
    if (ch === "#" || (ch === "/" && input[i + 1] === "/")) {
      while (i < len && input[i] !== "\n") i++;
      continue;
    }
    if ("()[],=:+".includes(ch)) {
      tokens.push({ type: "punct", value: ch });
      i++;
      continue;
    }
    if (ch === '"' || ch === "'") {
      const quote = ch;
      i++;
      let str = "";
      while (i < len && input[i] !== quote) {
        if (input[i] === "\\" && i + 1 < len) {
          const next = input[i + 1];
          if (next === "n") str += "\n";
          else if (next === "t") str += "\t";
          else str += next;
          i += 2;
        } else {
          str += input[i++];
        }
      }
      i++; // closing quote
      tokens.push({ type: "string", value: str });
      continue;
    }
    if (/[0-9-]/.test(ch) && (ch !== "-" || /[0-9]/.test(input[i + 1] ?? ""))) {
      let numStr = ch;
      i++;
      while (i < len && /[0-9.]/.test(input[i])) {
        numStr += input[i++];
      }
      tokens.push({ type: "number", value: Number(numStr) });
      continue;
    }
    if (/[A-Za-z_$]/.test(ch)) {
      let ident = ch;
      i++;
      while (i < len && /[A-Za-z0-9_$.-]/.test(input[i])) {
        ident += input[i++];
      }
      if (ident === "true" || ident === "false") {
        tokens.push({ type: "boolean", value: ident === "true" });
      } else if (ident === "null") {
        tokens.push({ type: "null", value: null });
      } else {
        tokens.push({ type: "ident", value: ident });
      }
      continue;
    }
    // Skip unrecognized character
    i++;
  }
  return tokens;
}

/**
 * Parses an OpenUI Lang v0.5 string into a symbol table and resolves `root`
 * forward references top-down.
 *
 * @param {string} source
 * @param {Record<string, any>} [data={}]
 * @returns {{ root: any, bindings: Record<string, any>, order: string[] }}
 */
export function parseOpenUILang(source, data = {}) {
  const tokens = tokenize(String(source ?? ""));
  let pos = 0;

  const peek = () => tokens[pos];
  const consume = () => tokens[pos++];
  const matchPunct = (val) => {
    if (peek()?.type === "punct" && peek()?.value === val) {
      pos++;
      return true;
    }
    return false;
  };

  function parsePrimary() {
    const tok = peek();
    if (!tok) return null;

    if (
      tok.type === "string" ||
      tok.type === "number" ||
      tok.type === "boolean" ||
      tok.type === "null"
    ) {
      consume();
      return { kind: "literal", value: tok.value };
    }

    if (matchPunct("[")) {
      const items = [];
      while (
        pos < tokens.length &&
        !(peek()?.type === "punct" && peek()?.value === "]")
      ) {
        items.push(parseExpr());
        matchPunct(",");
      }
      matchPunct("]");
      return { kind: "array", items };
    }

    if (tok.type === "ident") {
      consume();
      if (matchPunct("(")) {
        const args = [];
        while (
          pos < tokens.length &&
          !(peek()?.type === "punct" && peek()?.value === ")")
        ) {
          args.push(parseExpr());
          matchPunct(",");
        }
        matchPunct(")");
        return { kind: "component", name: tok.value, args };
      }
      return { kind: "ref", name: tok.value };
    }

    consume();
    return { kind: "literal", value: String(tok.value ?? "") };
  }

  function parseExpr() {
    let left = parsePrimary();
    while (matchPunct("+")) {
      const right = parsePrimary();
      left = { kind: "concat", left, right };
    }
    return left;
  }

  const rawBindings = {};
  const order = [];

  while (pos < tokens.length) {
    const tok = peek();
    if (
      tok?.type === "ident" &&
      tokens[pos + 1]?.type === "punct" &&
      tokens[pos + 1]?.value === "="
    ) {
      const name = consume().value;
      consume(); // '='
      const expr = parseExpr();
      rawBindings[name] = expr;
      if (!order.includes(name)) order.push(name);
    } else {
      const expr = parseExpr();
      if (!rawBindings.root && expr) {
        rawBindings.root = expr;
        order.push("root");
      }
    }
  }

  const resolvedCache = {};
  const visiting = new Set();

  function evaluate(node) {
    if (!node) return null;
    switch (node.kind) {
      case "literal":
        return node.value;
      case "array":
        return node.items.map(evaluate);
      case "concat": {
        const l = evaluate(node.left);
        const r = evaluate(node.right);
        return `${l ?? ""}${r ?? ""}`;
      }
      case "ref": {
        const name = node.name;
        if (name in resolvedCache) return resolvedCache[name];
        if (name in rawBindings && !visiting.has(name)) {
          visiting.add(name);
          const val = evaluate(rawBindings[name]);
          visiting.delete(name);
          resolvedCache[name] = val;
          return val;
        }
        if (name.includes(".")) {
          const fromData = resolveDataPath({ data, ...data }, name);
          if (fromData !== undefined) return fromData;
        }
        if (name in data) return data[name];
        return name;
      }
      case "component": {
        if (node.name === "Query") {
          const fallback = evaluate(node.args[2]) ?? {};
          return fallback;
        }
        return {
          $component: node.name,
          args: node.args.map(evaluate),
        };
      }
      default:
        return null;
    }
  }

  for (const key of order) {
    if (!(key in resolvedCache)) {
      visiting.add(key);
      resolvedCache[key] = evaluate(rawBindings[key]);
      visiting.delete(key);
    }
  }

  return {
    root: resolvedCache.root ?? null,
    bindings: resolvedCache,
    order,
  };
}

/**
 * Maps semantic tone names to theme-adaptive badge/accent classes.
 * @param {string} [tone]
 */
function toneClasses(tone) {
  switch (String(tone ?? "neutral").toLowerCase()) {
    case "success":
    case "good":
    case "green":
      return {
        text: "text-emerald-500",
        bg: "bg-emerald-500/15",
        border: "border-emerald-500/30",
        bar: "bg-emerald-500",
      };
    case "warning":
    case "warn":
    case "amber":
    case "wait":
      return {
        text: "text-amber-500",
        bg: "bg-amber-500/15",
        border: "border-amber-500/30",
        bar: "bg-amber-500",
      };
    case "danger":
    case "error":
    case "bad":
    case "red":
      return {
        text: "text-rose-500",
        bg: "bg-rose-500/15",
        border: "border-rose-500/30",
        bar: "bg-rose-500",
      };
    case "info":
    case "blue":
    case "run":
      return {
        text: "text-blue-500",
        bg: "bg-blue-500/15",
        border: "border-blue-500/30",
        bar: "bg-blue-500",
      };
    case "purple":
      return {
        text: "text-purple-500",
        bg: "bg-purple-500/15",
        border: "border-purple-500/30",
        bar: "bg-purple-500",
      };
    default:
      return {
        text: "text-[var(--foreground)]",
        bg: "bg-[var(--background)]",
        border: "border-[var(--border)]",
        bar: "bg-blue-500",
      };
  }
}

/**
 * Renders a resolved OpenUI AST node into HTML markup.
 * @param {any} node
 * @param {{ dslSource?: string, includeDslTab?: boolean, idPrefix?: string }} [opts]
 * @returns {string}
 */
export function renderNodeToHtml(node, opts = {}) {
  if (node === null || node === undefined) return "";
  if (
    typeof node === "string" ||
    typeof node === "number" ||
    typeof node === "boolean"
  ) {
    return `<span class="text-xs text-[var(--foreground)]">${escapeHtml(node)}</span>`;
  }
  if (Array.isArray(node)) {
    return node.map((child) => renderNodeToHtml(child, opts)).join("\n");
  }
  if (typeof node !== "object" || !node.$component) {
    return "";
  }

  const { $component: name, args = [] } = node;
  const prefix = opts.idPrefix || "openui";

  switch (name) {
    case "Card": {
      const children = Array.isArray(args[0]) ? args[0] : args;
      return `<div class="bg-[var(--card)] text-[var(--foreground)] border border-[var(--border)] rounded-xl p-4 shadow-sm space-y-3" data-openui-component="Card">
        ${children.map((c) => renderNodeToHtml(c, opts)).join("\n")}
      </div>`;
    }

    case "Header": {
      const [title, subtitle, statusText, statusTone = "success"] = args;
      const tone = toneClasses(statusTone);
      const badgeHtml = statusText
        ? `<span class="px-2.5 py-1 rounded-full text-xs font-medium ${tone.bg} ${tone.text} border ${tone.border}">${escapeHtml(statusText)}</span>`
        : "";
      return `<div class="flex flex-wrap items-center justify-between gap-2 pb-2.5 border-b border-[var(--border)]" data-openui-component="Header">
        <div class="flex items-center gap-2.5">
          <span class="relative flex h-2.5 w-2.5">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
            <span class="relative inline-flex rounded-full h-2.5 w-2.5 ${tone.bar}"></span>
          </span>
          <div>
            <div class="flex items-center gap-2">
              <h2 class="font-semibold text-sm text-[var(--foreground)]">${escapeHtml(title)}</h2>
              ${subtitle ? `<span class="px-2 py-0.5 rounded-md bg-[var(--background)] border border-[var(--border)] font-mono text-xs text-[var(--muted-foreground)]">${escapeHtml(subtitle)}</span>` : ""}
            </div>
          </div>
        </div>
        <div class="flex items-center gap-2">
          ${badgeHtml}
        </div>
      </div>`;
    }

    case "Tabs": {
      const rawTabs = Array.isArray(args[0]) ? args[0] : args;
      const tabs = rawTabs.filter((t) => t && t.$component === "Tab");
      if (opts.includeDslTab && opts.dslSource) {
        tabs.push({
          $component: "Tab",
          args: [
            "OpenUI Lang DSL",
            { $component: "CodeBlock", args: [opts.dslSource] },
          ],
        });
      }
      const tabButtons = tabs
        .map((t, idx) => {
          const label = t.args[0] ?? `Tab ${idx + 1}`;
          const activeCls =
            idx === 0
              ? "border-blue-500 font-semibold text-[var(--foreground)]"
              : "border-transparent font-medium text-[var(--muted-foreground)]";
          return `<button type="button" onclick="window.__openuiSwitchTab('${prefix}', ${idx})" id="${prefix}-tab-btn-${idx}" class="px-3 py-1.5 text-xs border-b-2 ${activeCls} hover:text-[var(--foreground)] cursor-pointer transition">${escapeHtml(label)}</button>`;
        })
        .join("\n");

      const tabPanes = tabs
        .map((t, idx) => {
          const content = t.args[1];
          const hiddenCls = idx === 0 ? "" : "hidden";
          return `<div id="${prefix}-tab-pane-${idx}" class="${hiddenCls} space-y-3 pt-1">${renderNodeToHtml(content, { ...opts, includeDslTab: false })}</div>`;
        })
        .join("\n");

      return `<div class="space-y-2.5" data-openui-component="Tabs">
        <div class="flex flex-wrap items-center gap-1 border-b border-[var(--border)]" role="tablist">
          ${tabButtons}
        </div>
        ${tabPanes}
      </div>`;
    }

    case "Stack": {
      const children = Array.isArray(args[0]) ? args[0] : args;
      return `<div class="space-y-2.5" data-openui-component="Stack">
        ${children.map((c) => renderNodeToHtml(c, opts)).join("\n")}
      </div>`;
    }

    case "Split": {
      const children = Array.isArray(args[0]) ? args[0] : args;
      return `<div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5" data-openui-component="Split">
        ${children.map((c) => renderNodeToHtml(c, opts)).join("\n")}
      </div>`;
    }

    case "Grid": {
      const cols = Number(args[0]) || 4;
      const children = Array.isArray(args[1]) ? args[1] : args.slice(1);
      const gridColsCls =
        cols === 2
          ? "grid-cols-1 sm:grid-cols-2"
          : cols === 3
            ? "grid-cols-1 sm:grid-cols-3"
            : "grid-cols-2 sm:grid-cols-4";
      return `<div class="grid ${gridColsCls} gap-2.5" data-openui-component="Grid">
        ${children.map((c) => renderNodeToHtml(c, opts)).join("\n")}
      </div>`;
    }

    case "Kpi": {
      const [label, value, subtext, toneName = "neutral", progressPct] = args;
      const tone = toneClasses(toneName);
      const hasBar =
        typeof progressPct === "number" && !Number.isNaN(progressPct);
      const clampedPct = hasBar ? Math.max(0, Math.min(100, progressPct)) : 0;
      return `<div class="bg-[var(--background)] border border-[var(--border)] rounded-lg p-2.5 space-y-0.5" data-openui-component="Kpi">
        <div class="text-xs text-[var(--muted-foreground)]">${escapeHtml(label)}</div>
        <div class="text-sm font-bold ${tone.text}">${escapeHtml(value)}</div>
        ${subtext ? `<div class="text-xs text-[var(--muted-foreground)]">${escapeHtml(subtext)}</div>` : ""}
        ${hasBar ? `<div class="w-full bg-[var(--border)] h-1.5 rounded-full mt-1 overflow-hidden"><div class="${tone.bar} h-full rounded-full" style="width: ${clampedPct}%"></div></div>` : ""}
      </div>`;
    }

    case "Table": {
      const rawCols = Array.isArray(args[0]) ? args[0] : args;
      const cols = rawCols.filter((c) => c && c.$component === "Col");
      const headers = cols.map((c) => c.args[0] ?? "");
      const colArrays = cols.map((c) =>
        Array.isArray(c.args[1]) ? c.args[1] : [c.args[1] ?? ""],
      );
      const rowCount = colArrays.reduce(
        (max, arr) => Math.max(max, arr.length),
        0,
      );

      const thHtml = headers
        .map(
          (h) =>
            `<th class="py-2 px-3 font-medium text-xs text-[var(--muted-foreground)]">${escapeHtml(h)}</th>`,
        )
        .join("");

      const rowsHtml = [];
      for (let r = 0; r < rowCount; r++) {
        const tds = colArrays
          .map((arr, cIdx) => {
            const cell = String(arr[r] ?? "");
            const isFirst = cIdx === 0;
            const toneMatch =
              cell.startsWith("✓") ||
              cell.toLowerCase().includes("healthy") ||
              cell.toLowerCase().includes("pass") ||
              cell.toLowerCase().includes("synced")
                ? "text-emerald-500 font-semibold"
                : cell.startsWith("✗") ||
                    cell.toLowerCase().includes("fail") ||
                    cell.toLowerCase().includes("degraded")
                  ? "text-rose-500 font-semibold"
                  : cell.startsWith("•") ||
                      cell.toLowerCase().includes("tracked") ||
                      cell.toLowerCase().includes("pending")
                    ? "text-amber-500 font-semibold"
                    : isFirst
                      ? "font-medium text-[var(--foreground)]"
                      : "text-[var(--muted-foreground)]";
            return `<td class="py-2 px-3 text-xs ${toneMatch}">${escapeHtml(cell)}</td>`;
          })
          .join("");
        rowsHtml.push(`<tr>${tds}</tr>`);
      }

      return `<div class="bg-[var(--background)] border border-[var(--border)] rounded-lg overflow-x-auto" data-openui-component="Table">
        <table class="w-full text-left border-collapse text-xs">
          <thead>
            <tr class="border-b border-[var(--border)] bg-[var(--card)]">${thHtml}</tr>
          </thead>
          <tbody class="divide-y divide-[var(--border)]">
            ${rowsHtml.join("\n")}
          </tbody>
        </table>
      </div>`;
    }

    case "BarChart": {
      const labels = Array.isArray(args[0]) ? args[0] : [];
      const rawSeries = Array.isArray(args[1]) ? args[1] : args.slice(1);
      const firstSeries = rawSeries.find(
        (s) => s && s.$component === "Series",
      ) ?? { args: ["Series", [], "info"] };
      const seriesTitle = firstSeries.args[0] ?? "Metrics";
      const values = Array.isArray(firstSeries.args[1])
        ? firstSeries.args[1].map(Number)
        : [];
      const toneName = firstSeries.args[2] ?? "info";
      const total = values.reduce(
        (acc, v) => acc + (Number.isFinite(v) ? v : 0),
        0,
      );
      const maxVal = Math.max(
        1,
        ...values.map((v) => (Number.isFinite(v) ? v : 0)),
      );
      const palette = [
        "bg-emerald-500",
        "bg-blue-500",
        "bg-purple-500",
        "bg-amber-500",
      ];

      const barsHtml = labels
        .map((label, idx) => {
          const val = Number(values[idx] ?? 0);
          const pct = Math.round((val / maxVal) * 100);
          const barCls = firstSeries.args[2]
            ? toneClasses(toneName).bar
            : palette[idx % palette.length];
          return `<div>
            <div class="flex justify-between text-xs mb-1">
              <span>${escapeHtml(label)}</span>
              <span class="font-mono font-semibold">${escapeHtml(val)}</span>
            </div>
            <div class="w-full bg-[var(--border)] h-2 rounded-full overflow-hidden">
              <div class="${barCls} h-full rounded-full" style="width: ${pct}%"></div>
            </div>
          </div>`;
        })
        .join("\n");

      return `<div class="bg-[var(--background)] border border-[var(--border)] rounded-lg p-3 space-y-2" data-openui-component="BarChart">
        <div class="flex items-center justify-between">
          <span class="font-semibold text-xs text-[var(--foreground)]">${escapeHtml(seriesTitle)}</span>
          <span class="text-xs text-[var(--muted-foreground)]">Total: ${escapeHtml(total)}</span>
        </div>
        <div class="space-y-2 pt-1">
          ${barsHtml}
        </div>
      </div>`;
    }

    case "AlertItem": {
      const [title, desc, badgeText = "Info", toneName = "success"] = args;
      const tone = toneClasses(toneName);
      return `<div class="p-2.5 rounded-lg bg-[var(--background)] border border-[var(--border)] flex items-start justify-between gap-2 text-xs" data-openui-component="AlertItem">
        <div>
          <div class="font-medium text-[var(--foreground)]">${escapeHtml(title)}</div>
          ${desc ? `<div class="text-xs text-[var(--muted-foreground)] mt-0.5">${escapeHtml(desc)}</div>` : ""}
        </div>
        ${badgeText ? `<span class="px-2 py-0.5 rounded text-xs font-medium shrink-0 ${tone.bg} ${tone.text}">${escapeHtml(badgeText)}</span>` : ""}
      </div>`;
    }

    case "Checklist": {
      const items = Array.isArray(args[0]) ? args[0] : args;
      const rows = items
        .map((item) => {
          if (item && item.$component === "CheckItem") {
            const [text, checked = false, meta = ""] = item.args;
            const icon = checked ? "✓" : "○";
            const cls = checked
              ? "text-emerald-500 font-bold"
              : "text-[var(--muted-foreground)]";
            return `<div class="flex items-center justify-between py-1.5 px-2.5 rounded bg-[var(--background)] border border-[var(--border)] text-xs">
              <div class="flex items-center gap-2">
                <span class="${cls}">${icon}</span>
                <span class="text-[var(--foreground)]">${escapeHtml(text)}</span>
              </div>
              ${meta ? `<span class="text-xs text-[var(--muted-foreground)] font-mono">${escapeHtml(meta)}</span>` : ""}
            </div>`;
          }
          return renderNodeToHtml(item, opts);
        })
        .join("\n");
      return `<div class="space-y-1.5" data-openui-component="Checklist">${rows}</div>`;
    }

    case "Badge": {
      const [text, toneName = "neutral"] = args;
      const tone = toneClasses(toneName);
      return `<span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${tone.bg} ${tone.text} border ${tone.border}" data-openui-component="Badge">${escapeHtml(text)}</span>`;
    }

    case "TextContent": {
      const [text, variant = "body"] = args;
      const cls =
        variant === "large-heavy"
          ? "text-sm font-bold text-[var(--foreground)]"
          : variant === "muted"
            ? "text-xs text-[var(--muted-foreground)]"
            : "text-xs text-[var(--foreground)]";
      return `<div class="${cls}" data-openui-component="TextContent">${escapeHtml(text)}</div>`;
    }

    case "CodeBlock": {
      const [code] = args;
      return `<pre class="bg-[var(--background)] border border-[var(--border)] rounded-lg p-3 font-mono text-xs overflow-x-auto leading-relaxed text-[var(--foreground)]" data-openui-component="CodeBlock"><code>${escapeHtml(String(code ?? "").trim())}</code></pre>`;
    }

    default: {
      const children = Array.isArray(args[0]) ? args[0] : args;
      return `<div class="space-y-2" data-openui-component="${escapeHtml(name)}">
        ${children.map((c) => renderNodeToHtml(c, opts)).join("\n")}
      </div>`;
    }
  }
}

/**
 * Compiles an OpenUI Lang v0.5 specification into an embeddable HTML fragment
 * (plus tab switching script) that can be mounted inside any sidecar panel or page.
 *
 * @param {string} dslSource
 * @param {{ data?: Record<string, any>, includeDslTab?: boolean, idPrefix?: string }} [options]
 * @returns {string}
 */
export function renderOpenUIFragment(dslSource, options = {}) {
  const { data = {}, includeDslTab = true, idPrefix = "openui" } = options;
  const parsed = parseOpenUILang(dslSource, data);
  const bodyHtml = renderNodeToHtml(parsed.root, {
    dslSource,
    includeDslTab,
    idPrefix,
  });

  return `${bodyHtml}
<script>
window.__openuiSwitchTab = window.__openuiSwitchTab || function(prefix, activeIdx) {
  var i = 0;
  while (true) {
    var btn = document.getElementById(prefix + '-tab-btn-' + i);
    var pane = document.getElementById(prefix + '-tab-pane-' + i);
    if (!btn || !pane) break;
    if (i === activeIdx) {
      pane.classList.remove('hidden');
      btn.classList.add('border-blue-500', 'font-semibold', 'text-[var(--foreground)]');
      btn.classList.remove('border-transparent', 'font-medium', 'text-[var(--muted-foreground)]');
    } else {
      pane.classList.add('hidden');
      btn.classList.remove('border-blue-500', 'font-semibold', 'text-[var(--foreground)]');
      btn.classList.add('border-transparent', 'font-medium', 'text-[var(--muted-foreground)]');
    }
    i++;
  }
};
</script>`;
}

/**
 * Compiles an OpenUI Lang v0.5 specification into a complete, self-contained,
 * CSP-compliant Antigravity `<agent-embed>` HTML artifact.
 *
 * @param {string} dslSource
 * @param {{ title?: string, data?: Record<string, any>, includeDslTab?: boolean, footer?: string }} [options]
 * @returns {string}
 */
export function compileToHtml(dslSource, options = {}) {
  const {
    title = "OpenUI Dashboard",
    data = {},
    includeDslTab = true,
    footer = "",
  } = options;
  const fragment = renderOpenUIFragment(dslSource, {
    data,
    includeDslTab,
    idPrefix: "openui",
  });

  const footerHtml = footer
    ? `<div class="pt-2 border-t border-[var(--border)] text-xs text-[var(--muted-foreground)] flex items-center justify-between">${escapeHtml(footer)}</div>`
    : "";

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${escapeHtml(title)}</title>
  <script src="https://www.gstatic.com/antigravity/web/dev/tailwindcss.min.js"></script>
</head>
<body class="bg-transparent text-[var(--foreground)] antialiased p-3 text-xs">
  ${fragment}
  ${footerHtml}
</body>
</html>
`;
}

// ---------------------------------------------------------------------------
// gh-watch: the panel's /api/state payload as an OpenUI Lang v0.5 document.
// ---------------------------------------------------------------------------

/**
 * Writes a value as an OpenUI Lang literal. Strings are double-quoted with
 * backslashes, quotes, newlines and tabs escaped the way the tokenizer above
 * reads them back; numbers that the tokenizer cannot read (NaN, Infinity,
 * exponents) become strings.
 * @param {unknown} value
 * @returns {string}
 */
export function openuiLiteral(value) {
  if (value === null || value === undefined) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    const text = String(value);
    if (Number.isFinite(value) && /^-?[0-9]+(\.[0-9]+)?$/.test(text))
      return text;
  }
  const escaped = String(value)
    .replaceAll("\\", "\\\\")
    .replaceAll('"', '\\"')
    .replaceAll(/\r\n?/g, "\n")
    .replaceAll("\n", "\\n")
    .replaceAll("\t", "\\t");
  return `"${escaped}"`;
}

const call = (name, args) => `${name}(${args.map(openuiLiteral).join(", ")})`;
const list = (items, indent) =>
  items.length === 0
    ? "[]"
    : `[\n${items.map((item) => `${indent}  ${item}`).join(",\n")}\n${indent}]`;
const asArray = (value) => (Array.isArray(value) ? value : []);
const asNumber = (value) =>
  Number.isFinite(Number(value)) ? Number(value) : 0;

// How many checks are failing on a watched pull request.
function failingCount(watch) {
  if (Array.isArray(watch.failing)) return watch.failing.length;
  if (Array.isArray(watch.failingChecks)) return watch.failingChecks.length;
  return asNumber(watch.counts?.fail);
}

// One word or two on where a watched pull request stands. The leading mark
// (✓ ✗ •) is what renderNodeToHtml's Table colours a cell by.
function watchStatus(watch) {
  if (watch.closed) {
    const state = String(watch.prState ?? "").toUpperCase();
    return state === "MERGED" ? "✓ merged" : "closed";
  }
  if (watch.lastError) return "✗ unreadable";
  const failing = failingCount(watch);
  if (failing > 0) return `✗ ${failing} failing`;
  if (watch.conflicting) return "✗ conflict";
  if (watch.queued) {
    const at = asNumber(watch.queuePosition);
    return at > 0 ? `• queued #${at}` : "• queued";
  }
  if (asNumber(watch.counts?.pending) > 0) return "• running";
  if (watch.isDraft) return "draft";
  if (!watch.counts) return "• not read yet";
  return "✓ green";
}

function watchChecks(watch) {
  const c = watch.counts;
  if (!c) return "";
  return `${asNumber(c.pass)} ok · ${asNumber(c.fail)} red · ${asNumber(c.pending)} running`;
}

/**
 * Converts gh-watch's /api/state payload into an OpenUI Lang v0.5 document:
 * a Card holding a Header, a Grid of four Kpis and a Table with one row per
 * watched pull request. Every field is optional; an empty or missing state
 * gives a valid document with zeros and an empty table.
 *
 * @param {Record<string, any> | null | undefined} state
 * @returns {string}
 */
export function toOpenUILang(state) {
  const s = state && typeof state === "object" ? state : {};
  const watches = asArray(s.watches)
    .filter((w) => w && typeof w === "object")
    // Same order as the panel: open first, then newest first.
    .sort((a, b) =>
      Boolean(a.closed) === Boolean(b.closed)
        ? asNumber(b.addedAt) - asNumber(a.addedAt)
        : a.closed
          ? 1
          : -1,
    );
  const open = watches.filter((w) => !w.closed);
  const failing = open.filter((w) => failingCount(w) > 0).length;
  const running = open.filter((w) => asNumber(w.counts?.pending) > 0).length;
  const queued = open.filter((w) => w.queued).length;
  const flaky = asArray(s.flaky).filter((f) => f && typeof f === "object");
  const pace = s.pace && typeof s.pace === "object" ? s.pace : {};
  const reviews = asArray(s.lists?.reviews?.items).length;

  const header = failing
    ? [`${failing} failing`, "danger"]
    : running
      ? [`${running} running`, "info"]
      : open.length
        ? ["all green", "success"]
        : ["idle", "neutral"];

  const flakyTop = flaky[0]
    ? `top: ${flaky[0].name ?? "?"} ×${asNumber(flaky[0].count)}`
    : "none recorded";
  const interval = Number(pace.intervalSeconds);
  const paceValue =
    Number.isFinite(interval) && interval > 0 ? `${interval}s` : "—";
  const paceNote = [pace.mode, pace.reason].filter(Boolean).join(" · ");

  const kpis = [
    call("Kpi", [
      "Watched PRs",
      watches.length,
      `${open.length} open · ${queued} queued · ${reviews} to review`,
      "info",
    ]),
    call("Kpi", [
      "Failing",
      failing,
      failing ? "PRs with red checks" : "nothing red",
      failing ? "danger" : "success",
    ]),
    call("Kpi", [
      "Flaky checks",
      flaky.length,
      flakyTop,
      flaky.length ? "warning" : "neutral",
    ]),
    call("Kpi", [
      "Pace",
      paceValue,
      paceNote,
      pace.mode === "fast" ? "info" : "neutral",
    ]),
  ];

  const column = (title, cells) =>
    `Col(${openuiLiteral(title)}, ${list(cells.map(openuiLiteral), "    ")})`;
  const label = (w) =>
    w.repo && w.number !== undefined
      ? `${w.repo}#${w.number}`
      : String(w.key ?? "?");
  const columns = [
    column("PR", watches.map(label)),
    column(
      "Title",
      watches.map((w) => w.title ?? ""),
    ),
    column("Status", watches.map(watchStatus)),
    column("Checks", watches.map(watchChecks)),
  ];

  const version = s.version ? `v${s.version}` : "";
  return `# gh-watch state as OpenUI Lang v0.5
root = Card([
  ${call("Header", ["GH Watch", version, header[0], header[1]])},
  Grid(4, ${list(kpis, "  ")}),
  Table(${list(columns, "  ")})
])
`;
}

if (typeof window !== "undefined") {
  window.OpenUI = {
    parseOpenUILang,
    renderNodeToHtml,
    renderOpenUIFragment,
    compileToHtml,
    toOpenUILang,
  };
}
