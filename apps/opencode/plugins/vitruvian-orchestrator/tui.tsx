// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createMemo, createSignal, For, onCleanup, Show } from "solid-js";

import {
  EMPTY_PANEL_MESSAGE,
  formatSidebarData,
  formatSidebarTitle,
} from "./lib/adapter.mjs";

export const PLUGIN_ID = "vitruvian-orchestrator";

function getStateFilePath() {
  const dir =
    process.env.VITRUVIAN_ORCHESTRATOR_STATE_DIR ||
    path.join(os.homedir(), ".local", "state", "opencode", PLUGIN_ID);
  return path.join(dir, "state.json");
}

function readFlowForSession(sessionID?: string) {
  const file = getStateFilePath();
  try {
    if (!fs.existsSync(file)) return null;
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    const flows = parsed?.flows || {};
    if (sessionID && flows[sessionID]) {
      return flows[sessionID];
    }
    // Check if sessionID is a worker run inside one of the root flows
    if (sessionID) {
      for (const rootFlow of Object.values(flows) as any[]) {
        if (
          rootFlow &&
          Array.isArray(rootFlow.runs) &&
          rootFlow.runs.some((r: any) => r.id === sessionID)
        ) {
          return rootFlow;
        }
      }
    }
    if (parsed?.activeSessionID && flows[parsed.activeSessionID]) {
      return flows[parsed.activeSessionID];
    }
    const keys = Object.keys(flows);
    return keys.length > 0 ? flows[keys[keys.length - 1]] : null;
  } catch {
    return null;
  }
}

function resolvePalette(themeSource: any) {
  const v2 = themeSource?.text ? themeSource : null;
  const v1 = themeSource?.current ? themeSource.current : null;
  return {
    base: v2?.text?.base ?? v1?.text ?? "#e5e7eb",
    muted: v2?.text?.muted ?? v1?.textMuted ?? "#9ca3af",
    success: v2?.text?.feedback?.success?.base ?? v1?.success ?? "#22c55e",
    info: v2?.text?.feedback?.info?.base ?? v1?.info ?? "#3b82f6",
    warning: v2?.text?.feedback?.warning?.base ?? v1?.warning ?? "#f59e0b",
    error: v2?.text?.feedback?.error?.base ?? v1?.error ?? "#ef4444",
  };
}

function colorForToken(
  palette: ReturnType<typeof resolvePalette>,
  token: "success" | "info" | "warning" | "error" | "muted",
) {
  return palette[token] ?? palette.muted;
}

function OrchestratorSidebarTitle(props: {
  themeSource?: any;
  sessionID?: string;
}) {
  const [tick, setTick] = createSignal(Date.now());
  const timer = setInterval(() => setTick(Date.now()), 1000);
  onCleanup(() => clearInterval(timer));

  const title = createMemo(() => {
    tick();
    const flow = readFlowForSession(props.sessionID);
    return formatSidebarTitle(flow);
  });

  const palette = createMemo(() => resolvePalette(props.themeSource));

  return <text fg={palette().base}>{title()}</text>;
}

function OrchestratorSidebarContent(props: {
  themeSource?: any;
  sessionID?: string;
  includeTitle?: boolean;
}) {
  const [now, setNow] = createSignal(Date.now());
  const timer = setInterval(() => setNow(Date.now()), 1000);
  onCleanup(() => clearInterval(timer));

  const view = createMemo(() => {
    const currentNow = now();
    const flow = readFlowForSession(props.sessionID);
    return formatSidebarData(flow, currentNow);
  });

  const palette = createMemo(() => resolvePalette(props.themeSource));

  return (
    <box flexDirection="column" gap={1}>
      <Show when={props.includeTitle}>
        <text fg={palette().base}>{view().sidebarTitle}</text>
      </Show>

      <Show
        when={!view().empty}
        fallback={<text fg={palette().muted}>{EMPTY_PANEL_MESSAGE}</text>}
      >
        {/* 1. Header: title, phase pills, accepted N of M, est. cost */}
        <box flexDirection="column">
          <text fg={palette().base}>
            {view().header!.title} · {view().header!.acceptedText} ·{" "}
            {view().header!.estCostText}
          </text>
          <text fg={palette().muted}>
            <For each={view().header!.phases}>
              {(p, idx) => (
                <>
                  <Show when={idx() > 0}>
                    <span style={{ fg: palette().muted }}> · </span>
                  </Show>
                  <span
                    style={{
                      fg:
                        p.state === "done"
                          ? palette().success
                          : p.state === "current"
                            ? palette().info
                            : palette().muted,
                    }}
                  >
                    {p.state === "done"
                      ? `✓${p.phase}`
                      : p.state === "current"
                        ? `[${p.phase.toUpperCase()}]`
                        : p.phase}
                  </span>
                </>
              )}
            </For>
          </text>
        </box>

        {/* 2. Burn-down sparkline */}
        <box flexDirection="column">
          <text fg={palette().base}>
            Burn-down {view().burnDown!.sparkline}{" "}
            <span style={{ fg: palette().muted }}>
              ({view().burnDown!.remainingText} ·{" "}
              {view().burnDown!.idealSummary} · {view().burnDown!.replanText})
            </span>
          </text>
        </box>

        {/* 3. Task board */}
        <box flexDirection="column">
          <text fg={palette().base}>Tasks ({view().tasks!.length})</text>
          <For each={view().tasks}>
            {(t) => (
              <text fg={colorForToken(palette(), t.color)}>
                #{t.id} {t.title}{" "}
                <span style={{ fg: palette().muted }}>
                  [{t.specialist}/{t.tier}]
                </span>{" "}
                {t.state}
                <Show when={Boolean(t.roundText)}>
                  <span style={{ fg: palette().warning }}> {t.roundText}</span>
                </Show>
                <Show when={Boolean(t.waitsOnText)}>
                  <span style={{ fg: palette().warning }}>
                    {" "}
                    ({t.waitsOnText})
                  </span>
                </Show>
              </text>
            )}
          </For>
        </box>

        {/* 4. Agents */}
        <box flexDirection="column">
          <text fg={palette().base}>Agents ({view().agents!.length})</text>
          <For each={view().agents}>
            {(a) => (
              <text fg={colorForToken(palette(), a.color)}>
                {a.agent}
                {a.taskId ? ` #${a.taskId}` : ""}{" "}
                <span style={{ fg: palette().muted }}>
                  ({a.model} · {a.effort}) · {a.stepsText} · {a.tokensText} ·{" "}
                  {a.costText} · {a.elapsedText} ·
                </span>{" "}
                {a.status}
              </text>
            )}
          </For>
        </box>

        {/* 5. Spend */}
        <box flexDirection="column">
          <text fg={palette().muted}>
            Spend: lead {view().spend!.leadText} · workers{" "}
            {view().spend!.workersText} · total {view().spend!.totalText}
          </text>
          <Show when={view().spend!.byModel.length > 0}>
            <text fg={palette().muted}>
              Models:{" "}
              {view()
                .spend!.byModel.map((m) => `${m.model} ${m.usdText}`)
                .join(" · ")}
            </text>
          </Show>
          <Show when={view().spend!.unpriced.length > 0}>
            <text fg={palette().warning}>
              Unpriced:{" "}
              {view()
                .spend!.unpriced.map((u) => `${u.model} ${u.tokensText}`)
                .join(" · ")}
            </text>
          </Show>
          <Show when={(view().spend!.delegated?.unpriced ?? 0) > 0}>
            <text fg={palette().muted}>
              {"  "}
              {view().spend!.delegatedText}
            </text>
          </Show>
        </box>

        {/* 6. Shared board (newest 5 single-line clipped posts) & pending wakes */}
        <Show when={(view().board?.posts.length ?? 0) > 0}>
          <box flexDirection="column">
            <text fg={palette().base}>Board ({view().board!.total})</text>
            <Show when={(view().board?.postsDropped ?? 0) > 0}>
              <text fg={palette().muted}>
                {view().board!.postsDropped} older posts not shown
              </text>
            </Show>
            <For each={view().board!.posts}>
              {(p) => (
                <text fg={palette().base}>
                  <span style={{ fg: palette().muted }}>#{p.seq} </span>
                  {p.from}
                  <Show when={Boolean(p.recipientsText)}>
                    <span style={{ fg: palette().muted }}>
                      {" "}
                      {p.recipientsText}
                    </span>
                  </Show>
                  <Show when={Boolean(p.replyText)}>
                    <span style={{ fg: palette().muted }}> {p.replyText}</span>
                  </Show>
                  <span style={{ fg: palette().muted }}> · {p.ageText} </span>
                  <span style={{ fg: colorForToken(palette(), p.color) }}>
                    [{p.kind}]
                  </span>{" "}
                  {p.text}
                </text>
              )}
            </For>
          </box>
        </Show>

        <Show when={(view().pendingWakes?.length ?? 0) > 0}>
          <box flexDirection="column">
            <text fg={palette().warning}>
              Pending wakes ({view().pendingWakes!.length})
            </text>
            <For each={view().pendingWakes}>
              {(w) => (
                <text fg={palette().warning}>
                  #{w.seq} {w.from} → @{w.target}: "{w.excerpt}"
                </text>
              )}
            </For>
          </box>
        </Show>
      </Show>
    </box>
  );
}

function registerLegacySlots(api: any) {
  if (!api?.slots?.register) return;
  api.slots.register({
    id: PLUGIN_ID,
    slots: {
      sidebar_title(_ctx: any, props: { session_id: string }) {
        return (
          <OrchestratorSidebarTitle
            themeSource={api.theme}
            sessionID={props?.session_id}
          />
        );
      },
      sidebar_content(_ctx: any, props: { session_id: string }) {
        return (
          <OrchestratorSidebarContent
            themeSource={api.theme}
            sessionID={props?.session_id}
            includeTitle={false}
          />
        );
      },
    },
  });
}

export default {
  id: PLUGIN_ID,

  // OpenCode 2.2.5 V2 TUI plugin entrypoint
  setup(ctx: any) {
    if (ctx?.ui?.slot) {
      ctx.ui.slot({
        prepend: "sidebar.content",
        render: (props: { sessionID: string }) => (
          <OrchestratorSidebarContent
            themeSource={ctx.theme}
            sessionID={props?.sessionID}
            includeTitle={true}
          />
        ),
      });
    } else if (ctx?.slots?.register) {
      registerLegacySlots(ctx);
    }
  },

  // @opencode-ai/plugin/tui 1.18.30 / 1.19.5 TuiPluginModule entrypoint
  async tui(api: any) {
    registerLegacySlots(api);
  },
};
