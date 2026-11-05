# orchestrator-core

`packages/orchestrator-core` is the pure, dependency-free JavaScript state machine shared by the `vitruvian-orchestrator` live panel in Claude Code, Antigravity, and OpenCode.

It contains no I/O, timers, or globals. Time (`at`, in milliseconds) is always passed in as part of an event, and `reduce(flow, event)` always returns a new state object without mutating its inputs.

## Events

Every event carries `at` (timestamp in milliseconds):

- `{ type: "plan", at, title, tasks: [{ title, specialist, tier, after }] }` — starts a new flow, or re-plans an existing one (preserving existing tasks' `state` and `round` when matched by trimmed title, re-deriving readiness for `"waiting"`/`"ready"` tasks, re-matching every run's `taskN` by trimmed title against the new task list, and recording `{ at, total }` in `replans`).
- `{ type: "phase", at, phase }` — moves the flow to `"plan"`, `"design"`, `"delegate"`, `"review"`, or `"close"`.
- `{ type: "run.start", at, id, harness, agent, model, effort, title, role }` — starts a lead or worker run. If `title` (trimmed) matches a task's title, sets `taskN` and transitions that task to `"running"` (preserving `round` if it was `"returned"`).
- `{ type: "run.progress", at, id, tokens?, steps?, contextPct? }` — merges token counts, step progress, or context percentage into an active run.
- `{ type: "run.end", at, id, status: "done" | "error", tokens? }` — marks a run finished and moves its linked task to `"review"` when `status === "done"`, or to `"returned"` (with `round` unchanged) when `status === "error"`.
- `{ type: "task.accept", at, n }` — accepts task `n` and promotes any `"waiting"` tasks whose `after` dependencies are all `"accepted"` to `"ready"`.
- `{ type: "task.return", at, n }` — returns task `n` for another pass (`state: "returned"`, `round + 1`).
- `{ type: "close", at }` — closes the flow (`phase: "close"`, `closedAt: at`).

After every event, waiting tasks whose `after` lists are all accepted become `"ready"`, and `{ at, remaining }` is appended to `history` whenever the unaccepted task count changes.

## Derived Views

- `remaining(flow)` — count of tasks not yet `"accepted"`.
- `burnDown(flow)` — returns `{ points, replans, ideal }`, where `ideal` is the two-point straight line from `{ at: flow.startedAt, remaining: firstTotal }` (`firstTotal` is `flow.history[0].remaining`, the initial planned count) to `{ at: lastPointAt, remaining: 0 }` (`lastPointAt` is the `at` of the last entry in `flow.history`).
- `taskBoard(flow)` — rows with `{ n, title, specialist, tier, state, round, after, waitingOn }`, where `waitingOn` lists the task numbers in `after` that are not yet `"accepted"`.
- `runCost(run)` — estimated USD cost for Claude family models (`fable`/`mythos`, `opus-5-5`, `opus`, `sonnet`, `haiku`), or `null` for unpriced models (Gemini, GPT, local).
- `spend(flow)` — aggregates `{ total, byModel, lead, workers, unpriced: { runs, tokens } }`.

## How Plugins Use It

Each harness plugin (`Claude Code`, `Antigravity`, `OpenCode`) vendors a direct copy of `src/core.mjs` so plugins remain self-contained at runtime without external package resolution. A follow-up check enforces that every vendored copy stays byte-identical to `packages/orchestrator-core/src/core.mjs`.
