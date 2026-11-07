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

import { expect, mock, test } from "claude-code/testing";

import type { Flow } from "../types";

const PLUGIN = "vitruvian-orchestrator";
const PANE_ID = "vitruvian-orchestrator";
const PROGRESS_TOOL = "mcp__vitruvian-orchestrator__progress";
const STEP_TOOL = "mcp__vitruvian-orchestrator__step";

const PANE_MOUNT = {
  plugin: PLUGIN,
  component: "Pane",
  requestId: PANE_ID,
  props: {
    title: "Orchestrator",
    isFocused: false,
    bodyColumns: 60,
    placement: "dock",
    scroll: { offset: 0, bodyRows: 24 },
    view: {},
  },
} as const;

const BAND_MOUNT = {
  plugin: PLUGIN,
  component: "AbovePrompt",
  requestId: "band",
  props: {
    bodyColumns: 80,
    hasSurvey: false,
    view: {},
  },
} as const;

test("progress tool builds the flow across plan, accept, return, re-plan, and finished", async ($, on) => {
  const clock = mock.clock(on, { now: 1000 });
  const opened: string[] = [];
  let f: Flow | null = null;

  on("ui.open", (_, e) => {
    opened.push(e.id);
    return { value: { isPlaced: true } };
  });
  on("state.set", { plugin: PLUGIN, key: "flow" }, (_, e, next) => {
    f = e.value as Flow | null;
    return next(e);
  });

  // 1. Initial plan + transition to delegate
  const r1 = await $.tool.call({
    tool: PROGRESS_TOOL,
    title: "Ship orchestrator panels",
    phase: "delegate",
    tasks: [
      {
        title: "Build Claude panel",
        specialist: "wren",
        tier: "lead",
        after: [],
      },
      {
        title: "Verify roster sync",
        specialist: "scout",
        tier: "fast",
        after: [1],
      },
    ],
  } as never);
  expect((r1 as { result?: string }).result).toBe("flow updated: 0/2 accepted");
  expect(opened).toEqual([PANE_ID]);
  expect(f?.title).toBe("Ship orchestrator panels");
  expect(f?.phase).toBe("delegate");
  expect(
    f?.tasks.map((t) => ({ n: t.n, state: t.state, round: t.round })),
  ).toEqual([
    { n: 1, state: "ready", round: 0 },
    { n: 2, state: "waiting", round: 0 },
  ]);

  // 2. Return task 1 -> state becomes returned, round increments to 1
  await clock.advance(500);
  const r2 = await $.tool.call({
    tool: PROGRESS_TOOL,
    phase: "review",
    return: 1,
  } as never);
  expect((r2 as { result?: string }).result).toBe("flow updated: 0/2 accepted");
  expect(f?.phase).toBe("review");
  expect(f?.tasks[0]?.state).toBe("returned");
  expect(f?.tasks[0]?.round).toBe(1);

  // 3. Accept task 1 -> unblocks task 2 from waiting to ready
  await clock.advance(500);
  const r3 = await $.tool.call({
    tool: PROGRESS_TOOL,
    accept: 1,
  } as never);
  expect((r3 as { result?: string }).result).toBe("flow updated: 1/2 accepted");
  expect(f?.tasks[0]?.state).toBe("accepted");
  expect(f?.tasks[0]?.round).toBe(1);
  expect(f?.tasks[1]?.state).toBe("ready");

  // 4. Re-plan adding a 3rd task -> preserves task 1 accepted state and records replan
  await clock.advance(500);
  const r4 = await $.tool.call({
    tool: PROGRESS_TOOL,
    tasks: [
      {
        title: "Build Claude panel",
        specialist: "wren",
        tier: "lead",
        after: [],
      },
      {
        title: "Verify roster sync",
        specialist: "scout",
        tier: "fast",
        after: [1],
      },
      { title: "Update docs", specialist: "quill", tier: "core", after: [2] },
    ],
  } as never);
  expect((r4 as { result?: string }).result).toBe("flow updated: 1/3 accepted");
  // Auto-open should only fire once per flow
  expect(opened).toEqual([PANE_ID]);
  expect(f?.replans).toHaveLength(1);
  expect(f?.replans[0]?.total).toBe(3);
  expect(f?.tasks[0]?.state).toBe("accepted");
  expect(f?.tasks[1]?.state).toBe("ready");
  expect(f?.tasks[2]?.state).toBe("waiting");

  // 5. Accept remaining tasks and mark finished
  await clock.advance(500);
  await $.tool.call({ tool: PROGRESS_TOOL, accept: 2 } as never);
  await clock.advance(500);
  const r5 = await $.tool.call({
    tool: PROGRESS_TOOL,
    accept: 3,
    finished: true,
  } as never);
  expect((r5 as { result?: string }).result).toBe("flow updated: 3/3 accepted");
  expect(f?.phase).toBe("close");
  expect(f?.closedAt).toBe(3500);
});

test("Agent dispatch creates a running run matching a task and step updates the right run", async ($, on) => {
  mock.clock(on, { now: 2000 });
  let f: Flow | null = null;
  let nextId = 0;

  on("ui.open", () => ({ value: { isPlaced: true } }));
  on("state.set", { plugin: PLUGIN, key: "flow" }, (_, e, next) => {
    f = e.value as Flow | null;
    return next(e);
  });
  on("agent.spawn", async (_, e) => ({
    model: e.model ?? "claude-opus-5-5",
    agentId: `worker-${++nextId}`,
  }));

  await $.tool.call({
    tool: PROGRESS_TOOL,
    title: "Dispatch test",
    phase: "delegate",
    tasks: [
      {
        title: "Implement register.tsx",
        specialist: "wren",
        tier: "lead",
        after: [],
      },
      {
        title: "Run plugin tests",
        specialist: "scout",
        tier: "core",
        after: [1],
      },
    ],
  } as never);

  await $.agent.spawn({
    subagentType: "wren",
    description: "Implement register.tsx",
    prompt: "Build the live panel",
    model: "claude-opus-5-5",
  });
  await $.agent.spawn({
    subagentType: "scout",
    description: "Ad-hoc check",
    prompt: "Check status",
    model: "claude-sonnet-5-5",
  });

  expect(f?.runs).toHaveLength(2);
  expect(f?.runs[0]?.id).toBe("worker-1");
  expect(f?.runs[0]?.taskN).toBe(1);
  expect(f?.runs[0]?.status).toBe("running");
  expect(f?.runs[0]?.model).toBe("claude-opus-5-5");
  expect(f?.tasks[0]?.state).toBe("running");
  expect(f?.runs[1]?.id).toBe("worker-2");
  expect(f?.runs[1]?.taskN).toBeNull();

  // Calling step from worker-2 updates only worker-2
  const stepRes = await $.tool.call({
    tool: STEP_TOOL,
    done: 2,
    total: 5,
    note: "Running unit tests",
    agentId: "worker-2",
  } as never);
  expect((stepRes as { result?: string }).result).toBe("ok");
  expect(f?.runs[0]?.steps).toBeNull();
  expect(f?.runs[1]?.steps).toEqual({
    done: 2,
    total: 5,
    note: "Running unit tests",
  });

  // Calling step without an agentId or with an unknown agentId returns a short message without throwing
  const noAgentRes = await $.tool.call({
    tool: STEP_TOOL,
    done: 1,
    total: 3,
  } as never);
  expect((noAgentRes as { result?: string }).result).toContain("ignored");

  const unknownAgentRes = await $.tool.call({
    tool: STEP_TOOL,
    done: 1,
    total: 3,
    agentId: "no-such-agent",
  } as never);
  expect((unknownAgentRes as { result?: string }).result).toContain("ignored");
});

test("pane mounts on BOTH terminal and desktop with an empty and a seeded flow containing task titles, phase, and est.", async ($, on) => {
  mock.clock(on, { now: 5000 });
  on("ui.open", () => ({ value: { isPlaced: true } }));
  on("agent.spawn", async () => ({
    model: "claude-opus-5-5",
    agentId: "wren-1",
  }));
  on("turn.complete", (_, e) => ({
    text: e.answer,
    ...(e.usage ? { usage: e.usage } : {}),
  }));

  // 1. Empty flow on both terminal and desktop
  for (const surface of ["terminal", "desktop"] as const) {
    const ui = await $.ui.mount({ ...PANE_MOUNT, surface });
    const emptyText = await ui.find({
      type: "Text",
      text: /lead skill reports a plan/i,
    });
    expect(emptyText).toBeDefined();
    await ui.unmount();
  }

  // 2. Seed flow with tasks, a worker run, step progress, and lead usage
  await $.tool.call({
    tool: PROGRESS_TOOL,
    title: "Multi-surface verification",
    phase: "delegate",
    tasks: [
      {
        title: "Wire hooks module",
        specialist: "wren",
        tier: "lead",
        after: [],
      },
      {
        title: "Audit Bazel targets",
        specialist: "forge",
        tier: "core",
        after: [1],
      },
    ],
  } as never);

  await $.agent.spawn({
    subagentType: "wren",
    description: "Wire hooks module",
    prompt: "Write register.tsx",
  });
  await $.tool.call({
    tool: STEP_TOOL,
    done: 3,
    total: 4,
    note: "Drawing pane",
    agentId: "wren-1",
  } as never);
  await $.turn.complete({
    turnId: "lead-turn-1",
    reason: "answer",
    answer: "Dispatched wren",
    isAborted: false,
    durationMs: 400,
    usage: {
      model: "claude-opus-5-5",
      input_tokens: 50_000,
      output_tokens: 5_000,
      cache_read_input_tokens: 0,
      cache_creation_input_tokens: 0,
    },
  });

  for (const surface of ["terminal", "desktop"] as const) {
    const ui = await $.ui.mount({ ...PANE_MOUNT, surface });

    const task1 = await ui.find({ type: "Text", text: /Wire hooks module/ });
    const task2 = await ui.find({ type: "Text", text: /Audit Bazel targets/ });
    const waitsOn = await ui.find({ type: "Text", text: /waits on #1/ });
    const estText = await ui.find({ type: "Text", text: /est\./ });

    expect(task1).toBeDefined();
    expect(task2).toBeDefined();
    expect(waitsOn).toBeDefined();
    expect(estText).toBeDefined();

    if (surface === "terminal") {
      expect(await ui.find({ type: "Text", text: /delegate/ })).toBeDefined();
    } else {
      const svgs = await ui.findAll({ type: "Svg" });
      expect(svgs.length).toBeGreaterThanOrEqual(3);
      // The header picture carries the phase; the text copy is not repeated.
      expect(
        svgs.some((s) =>
          String((s.props as { source?: string }).source).includes("delegate"),
        ),
      ).toBe(true);
      expect(
        await ui.find({ type: "Text", text: /\[delegate\]/ }),
      ).toBeUndefined();
      const wrenSvg = svgs.find((s) =>
        String((s.props as { source?: string }).source).includes("c-wren run"),
      );
      expect(wrenSvg).toBeDefined();
    }

    await ui.unmount();
  }
});

test("AbovePrompt band is absent with no flow and shown once a flow exists", async ($, on) => {
  mock.clock(on, { now: 8000 });
  on("ui.open", () => ({ value: { isPlaced: true } }));

  // When no flow exists, the band delegates to next(e) (engine fallback)
  on("ui.render", ($, e) => {
    const { Text } = $.ui.resolve(e);
    return <Text>empty-band</Text>;
  });

  for (const surface of ["terminal", "desktop"] as const) {
    const ui = await $.ui.mount({ ...BAND_MOUNT, surface });
    expect((await ui.find({ type: "Text", text: /empty-band/ }))?.text).toBe(
      "empty-band",
    );
    await ui.unmount();
  }

  // Once a flow exists, the band renders title, phase, "N of M accepted", and crew button
  await $.tool.call({
    tool: PROGRESS_TOOL,
    title: "Band active flow",
    phase: "review",
    tasks: [
      { title: "Task One", specialist: "wren", tier: "core", after: [] },
      { title: "Task Two", specialist: "scout", tier: "fast", after: [1] },
    ],
    accept: 1,
  } as never);

  for (const surface of ["terminal", "desktop"] as const) {
    const ui = await $.ui.mount({ ...BAND_MOUNT, surface });
    if (surface === "terminal") {
      expect(
        await ui.find({ type: "Text", text: /Band active flow/ }),
      ).toBeDefined();
      expect(await ui.find({ type: "Text", text: /review/ })).toBeDefined();
      expect(
        await ui.find({ type: "Text", text: /1 of 2 accepted/ }),
      ).toBeDefined();
    } else {
      // The band picture says it all; no second line repeats it as text.
      const band = (await ui.findAll({ type: "Svg" }))[0];
      expect(String((band?.props as { alt?: string }).alt)).toContain(
        "Band active flow · review · 1 of 2 accepted",
      );
      expect(
        await ui.find({ type: "Text", text: /Band active flow/ }),
      ).toBeUndefined();
    }
    expect(
      await ui.find({ type: "Button", key: "orchestrator-crew" }),
    ).toBeDefined();
    await ui.unmount();
  }
});

test("narrow 60-column terminal pane and band keep every line within 60 columns with no cut words or narrow row columns", async ($, on) => {
  mock.clock(on, { now: 10_000 });
  on("ui.open", () => ({ value: { isPlaced: true } }));
  on("agent.spawn", async () => ({
    model: "claude-opus-5-5",
    agentId: "wren-narrow",
  }));
  on("turn.complete", (_, e) => ({
    text: e.answer,
    ...(e.usage ? { usage: e.usage } : {}),
  }));

  await $.tool.call({
    tool: PROGRESS_TOOL,
    title:
      "Reflow orchestrator terminal panel for narrow sixty column split panes",
    phase: "delegate",
    tasks: [
      {
        title:
          "Lay out header on three lines and keep agent names whole on line one",
        specialist: "wren",
        tier: "lead",
        after: [],
      },
      {
        title:
          "Wrap long task titles onto an indented second line without cutting words",
        specialist: "scout",
        tier: "fast",
        after: [1],
      },
    ],
    accept: 1,
  } as never);

  await $.agent.spawn({
    subagentType: "wren",
    description:
      "Wrap long task titles onto an indented second line without cutting words",
    prompt: "Fix narrow layout",
  });
  await $.tool.call({
    tool: STEP_TOOL,
    done: 2,
    total: 4,
    note: "Checking sixty column wrapping behavior",
    agentId: "wren-narrow",
  } as never);
  await $.turn.complete({
    turnId: "lead-turn-narrow",
    reason: "answer",
    answer: "Checked narrow pane",
    isAborted: false,
    durationMs: 1200,
    usage: {
      model: "claude-opus-5-5",
      input_tokens: 40_000,
      output_tokens: 4_000,
      cache_read_input_tokens: 0,
      cache_creation_input_tokens: 0,
    },
  });

  const ui = await $.ui.mount({
    plugin: PLUGIN,
    surface: "terminal",
    component: "Pane",
    requestId: PANE_ID,
    viewport: { columns: 60, rows: 24, hasDockedPane: true },
    props: {
      title: "Orchestrator",
      isFocused: false,
      bodyColumns: 60,
      placement: "dock",
      scroll: { offset: 0, bodyRows: 24 },
      view: {},
    },
  });

  // Header line 2 has phase pills, line 3 has "accepted 1 of 2 · est. $..."
  expect(await ui.find({ type: "Text", text: /\[delegate\]/ })).toBeDefined();
  expect(
    await ui.find({ type: "Text", text: /^accepted 1 of 2 · est\. \$/ }),
  ).toBeDefined();
  // Agent row line 1 has status dot + full agent name + state on one line
  expect(await ui.find({ type: "Text", text: /● lead running/ })).toBeDefined();
  expect(await ui.find({ type: "Text", text: /● wren running/ })).toBeDefined();

  const allTexts = await ui.findAll({ type: "Text" });
  for (const t of allTexts) {
    expect((t.text ?? "").length).toBeLessThanOrEqual(60);
  }

  // Verify every word from the seeded titles and agent rows appears intact (never split mid-word)
  const joinedLines = allTexts.map((t) => t.text ?? "").join("\n");
  const expectedWords = [
    "Reflow",
    "orchestrator",
    "terminal",
    "narrow",
    "sixty",
    "column",
    "accepted",
    "delegate",
    "header",
    "indented",
    "second",
    "without",
    "cutting",
    "words",
    "lead",
    "wren",
    "running",
    "claude-opus-5-5",
    "Checking",
    "wrapping",
    "behavior",
  ];
  for (const word of expectedWords) {
    expect(joinedLines).toContain(word);
  }

  await ui.unmount();

  const bandUi = await $.ui.mount({
    plugin: PLUGIN,
    surface: "terminal",
    component: "AbovePrompt",
    requestId: "band-narrow",
    viewport: { columns: 60, rows: 24, hasDockedPane: true },
    props: {
      bodyColumns: 60,
      hasSurvey: false,
      view: {},
    },
  });
  const bandTexts = await bandUi.findAll({ type: "Text" });
  for (const t of bandTexts) {
    expect((t.text ?? "").length).toBeLessThanOrEqual(50);
  }
  await bandUi.unmount();
});

test("step call with delegate shows driver → delegate model arrow and delegated spend line", async ($, on) => {
  mock.clock(on, { now: 12_000 });
  on("ui.open", () => ({ value: { isPlaced: true } }));
  on("agent.spawn", async (_, e) => ({
    model: e.model ?? "claude-haiku-5-5",
    agentId: "wren-delegate",
  }));

  await $.tool.call({
    tool: PROGRESS_TOOL,
    title: "Gemini delegation",
    phase: "delegate",
    tasks: [
      {
        title: "Implement feature via agy",
        specialist: "wren",
        tier: "core",
        after: [],
      },
    ],
  } as never);

  await $.agent.spawn({
    subagentType: "wren",
    description: "Implement feature via agy",
    prompt: "Delegate to Gemini",
    model: "claude-haiku-5-5",
  });

  await $.tool.call({
    tool: STEP_TOOL,
    done: 1,
    total: 2,
    note: "agy-delegate running",
    delegate: "gemini-4-argon-high",
    agentId: "wren-delegate",
  } as never);

  for (const surface of ["terminal", "desktop"] as const) {
    const ui = await $.ui.mount({ ...PANE_MOUNT, surface });

    const arrowText = await ui.find({
      type: "Text",
      text: /claude-haiku-5-5 → gemini-4-argon-high/,
    });
    // Terminal shows it as text; desktop draws it once, in the row picture.
    if (surface === "terminal") expect(arrowText).toBeDefined();
    else expect(arrowText).toBeUndefined();

    const spendDelegated = await ui.find({
      type: "Text",
      text: /delegated to Gemini: 1 run \(gemini-4-argon-high ×1\), not priced/,
    });
    expect(spendDelegated).toBeDefined();

    if (surface === "desktop") {
      const svgs = await ui.findAll({ type: "Svg" });
      const agentSvg = svgs.find((s) =>
        String((s.props as { alt?: string }).alt).includes(
          "claude-haiku-5-5 → gemini-4-argon-high",
        ),
      );
      expect(agentSvg).toBeDefined();
      expect(String((agentSvg?.props as { source?: string }).source)).toContain(
        "claude-haiku-5-5 → gemini-4-argon-high",
      );
    }

    await ui.unmount();
  }
});

test("the panel toggle is /orchestrator-panel, not a near-twin of /orchestrate", async ($, on) => {
  const opened: string[] = [];
  on("ui.open", (_, e) => {
    opened.push(e.id);
    return { value: { isPlaced: true } };
  });
  mock.clock(on, { now: 1000 });
  on("ui.panes", () => ({ value: [] }));
  const r = await $.command.run({ command: "orchestrator-panel", args: "" });
  expect(JSON.stringify(r)).toContain("Orchestrator panel");
});

test("a closed flow has no running rows, one row per agent, and the desktop draws each row once", async ($, on) => {
  const clock = mock.clock(on, { now: 1000 });
  let f: Flow | null = null;
  on("ui.open", () => ({ value: { isPlaced: true } }));
  on("state.set", { plugin: PLUGIN, key: "flow" }, (_, e, next) => {
    f = e.value as Flow | null;
    return next(e);
  });
  // The host reports the same background agent each time it wakes it.
  on("agent.spawn", async () => ({
    model: "claude-sonnet-5-5",
    agentId: "helper-1",
  }));
  on("turn.complete", (_, e) => ({
    text: e.answer,
    ...(e.usage ? { usage: e.usage } : {}),
  }));

  await $.tool.call({
    tool: PROGRESS_TOOL,
    title: "Seeded copy",
    phase: "delegate",
    tasks: [{ title: "Build it", specialist: "wren", tier: "core", after: [] }],
  } as never);
  await $.turn.complete({
    turnId: "lead-1",
    reason: "answer",
    answer: "Dispatched",
    isAborted: false,
    durationMs: 100,
    usage: {
      model: "claude-opus-5-5",
      input_tokens: 1000,
      output_tokens: 100,
      cache_read_input_tokens: 0,
      cache_creation_input_tokens: 0,
    },
  });
  for (let i = 0; i < 4; i++) {
    clock.advance(60_000);
    await $.agent.spawn({
      subagentType: "general-purpose",
      description: "Build it",
      prompt: "Build",
    });
  }
  expect(f?.runs.filter((r) => r.id === "helper-1")).toHaveLength(1);

  await $.tool.call({
    tool: PROGRESS_TOOL,
    phase: "review",
    accept: 1,
    finished: true,
  } as never);
  expect(f?.runs.find((r) => r.id === "lead")?.status).toBe("done");
  expect(f?.runs.some((r) => r.status === "running")).toBe(false);

  const ui = await $.ui.mount({ ...PANE_MOUNT, surface: "desktop" });
  const svgs = await ui.findAll({ type: "Svg" });
  // header + burn-down + one picture per agent row (lead and the helper)
  expect(svgs).toHaveLength(4);
  expect(await ui.find({ type: "Text", text: /running/ })).toBeUndefined();
  expect(
    await ui.find({ type: "Text", text: /general-purpose/ }),
  ).toBeUndefined();
  await ui.unmount();
});

test("the band's phase pill label always fits inside the pill", async ($, on) => {
  mock.clock(on, { now: 1000 });
  on("ui.open", () => ({ value: { isPlaced: true } }));
  await $.tool.call({
    tool: PROGRESS_TOOL,
    title: "Seeded Courier test copy",
    phase: "close",
    tasks: [
      { title: "A", specialist: "wren", tier: "core", after: [] },
      { title: "B", specialist: "wren", tier: "core", after: [] },
    ],
    accept: 1,
  } as never);
  await $.tool.call({
    tool: PROGRESS_TOOL,
    accept: 2,
    finished: true,
  } as never);

  for (const bodyColumns of [40, 60, 80, 140]) {
    const ui = await $.ui.mount({
      ...BAND_MOUNT,
      surface: "desktop",
      props: { ...BAND_MOUNT.props, bodyColumns },
    });
    const source = String(
      ((await ui.findAll({ type: "Svg" }))[0]?.props as { source?: string })
        .source,
    );
    const pillW = Number(
      /<rect x="[\d.]+" width="([\d.]+)" height="16"/.exec(source)?.[1],
    );
    const label =
      /font-weight="600" fill="#ffffff">([^<]*)</.exec(source)?.[1] ?? "";
    // Bold 10.5px text: at most ~0.72em per character even for capitals.
    expect(label.length).toBeGreaterThan(0);
    expect(label.length * 10.5 * 0.62).toBeLessThanOrEqual(pillW);
    await ui.unmount();
  }
});
