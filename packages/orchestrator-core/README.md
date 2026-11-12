# orchestrator-core

`packages/orchestrator-core` is the pure, dependency-free JavaScript state machine shared by the `vitruvian-orchestrator` live panel in Claude Code, Antigravity, and OpenCode.

It contains no I/O, timers, or globals. Time (`at`, in milliseconds) is always passed in as part of an event, and `reduce(flow, event)` always returns a new state object without mutating its inputs.

## Events

Every event carries `at` (timestamp in milliseconds):

- `{ type: "plan", at, title, tasks: [{ title, specialist, tier, after }] }` — starts a new flow, or re-plans an existing one (preserving existing tasks' `state` and `round` when matched by trimmed title, re-deriving readiness for `"waiting"`/`"ready"` tasks, re-matching every run's `taskN` by trimmed title against the new task list, and recording `{ at, total }` in `replans`).
- `{ type: "phase", at, phase }` — moves the flow to `"plan"`, `"design"`, `"delegate"`, `"review"`, or `"close"`.
- `{ type: "run.start", at, id, harness, agent, model, effort, title, role }` — starts a lead or worker run (`startedAt: at`, `lastActivityAt: at`). If `title` (trimmed) matches a task's title, sets `taskN` and transitions that task to `"running"` (preserving `round` if it was `"returned"`). An `id` the flow already has never adds a second row: the same agent starting again (a follow-up message, or the host waking a background agent) reopens its ended run, keeping its tokens and updating `lastActivityAt: at`, and is otherwise ignored.
- `{ type: "run.progress", at, id, tokens?, delegate?, delegateTokens?, steps?, contextPct?, waiting? }` — merges driver token counts, step progress, delegate model, or context percentage into an active run and updates `lastActivityAt`. `delegateTokens` (`{ input, output, thinking, cacheRead }`) replaces the run's Gemini token snapshot (it is a running total for the task, ignoring negative or non-numeric fields). `waiting: true` marks the run as held on work it started (a background command, a Gemini job); any report without it clears the mark.
- `{ type: "run.end", at, id, status: "done" | "error", tokens? }` — marks a run finished, updates `lastActivityAt`, and moves its linked task to `"review"` when `status === "done"`, or to `"returned"` (with `round` unchanged) when `status === "error"`.
- `{ type: "task.accept", at, n }` — accepts task `n` and promotes any `"waiting"` tasks whose `after` dependencies are all `"accepted"` to `"ready"`.
- `{ type: "task.return", at, n }` — returns task `n` for another pass (`state: "returned"`, `round + 1`).
- `{ type: "post", at, from, text, to?, kind?, replyTo?, channel?, runId? }` — strips ANSI escape sequences and C0/DEL control characters (preserving `\n` and `\t`), ignores empty text, appends a numbered post (`seq` = 1, 2, 3 …) on `channel` (default `"main"`) to `flow.posts`, unions explicit `to` with `@name` mentions parsed from `text`, and caps `text` at 4000 characters (`…[truncated]`).
- `{ type: "channel", at, action: "create" | "archive", name }` — creates a named channel (`[a-z0-9][a-z0-9-]{0,31}`, capped at 20 channels including `"main"`) or archives a non-`"main"` channel so new posts to it are rejected while existing posts remain readable.
- `{ type: "wake", at, seq, target }` — records a delivered board wake (`"${seq}:${target}"` in `flow.woken`) so replaying a flow after restart does not re-send already-delivered wakes.
- `{ type: "member.pause", at, id, reason: "quota" | "error", detail? }` — marks specialist run `id` paused (`reason`, optional `detail`); cleared by any later `run.progress` or `run.start` for `id`.
- `{ type: "member.kill", at, id }` — marks specialist run `id` killed (ending it if still open).
- `{ type: "member.retire", at, id }` — marks specialist run `id` retired (ending it if still open).
- `{ type: "close", at }` — closes the flow (`phase: "close"`, `closedAt: at`), ends every run still open as `"done"` at `at`, and retires all members.

After every event, waiting tasks whose `after` lists are all accepted become `"ready"`, and `{ at, remaining }` is appended to `history` whenever the unaccepted task count changes.

## Derived Views

- `remaining(flow)` — count of tasks not yet `"accepted"`.
- `burnDown(flow)` — returns `{ points, replans, ideal }`, where `ideal` is the two-point straight line from `{ at: flow.startedAt, remaining: firstTotal }` (`firstTotal` is `flow.history[0].remaining`, the initial planned count) to `{ at: lastPointAt, remaining: 0 }` (`lastPointAt` is the `at` of the last entry in `flow.history`).
- `taskBoard(flow)` — rows with `{ n, title, specialist, tier, state, round, after, waitingOn }`, where `waitingOn` lists the task numbers in `after` that are not yet `"accepted"`.
- `delegateCost(run)` — estimated USD cost for a delegated run (`run.delegate` + `run.delegateTokens`, pricing `thinking` tokens at the delegate model's `output` rate), or `null` unless both are set and the delegate model has a price in `src/prices.mjs`.
- `runCost(run)` — estimated USD cost (`driverCost + delegateCost`) using model rates from `src/prices.mjs` (Claude `fable`/`mythos`, `opus-5-5`, `opus`, `sonnet`, `haiku-5-5`, `haiku`, plus `gemini-4-(carbon|argon)` and `gemini-3.8-flash`), or `null` when neither driver nor delegate is priced.
- `spend(flow)` — aggregates `{ total, byModel, lead, workers, unpriced: { runs, tokens }, delegated: { runs, unpriced, byModel } }`, attributing `delegateCost` to `byModel[run.delegate]`, `workers`, and `total`, and counting delegated runs without usable delegate cost in `delegated.unpriced`.
- `stalls(flow, now, { quietMs = DEFAULT_QUIET_MS, stallMs = DEFAULT_STALL_MS, waitingStallMs = DEFAULT_WAITING_STALL_MS } = {})` — inspects running worker runs (`status === "running"`, `role !== "lead"`, and not `paused`) and returns `{ id, agent, title, taskN, lastActivityAt, idleMs, state }[]`, where `state` is `"stalled"` (`idleMs >= stallMs`, default 15 min), `"quiet"` (`idleMs >= quietMs`, default 5 min), or `"active"`. A run that is waiting on its own work (`waiting`) or has handed it to Gemini (`delegate`) is silent by design: it reads `"waiting"` instead of `"quiet"`, and only becomes `"stalled"` after `waitingStallMs` (default 60 min, above agy-delegate's 45-minute limit).
- `mentions(text)` — extracts lower-cased, de-duplicated `@name` mentions (`@` followed by `[a-z0-9][a-z0-9-]*`, not preceded by a word character; includes `@all` and `@lead`).
- `members(flow)` — groups specialist runs into `{ active, standingBy, retired }`, where each row has `{ id, agent, state, reason?, detail?, taskN?, model, delegate?, lastPostSeq?, lastActivityAt }` (`active` = `working`; `standingBy` = `waiting` + `paused`; `retired` = `killed` + `retired`).
- `board(flow, { search?, from?, to?, kind?, channel?, limit? })` — returns posts newest last, filtered (case-insensitive `search` across `text`, `from`, and `to`, plus optional `channel` filter that also retains the lead's `@all` broadcasts from `main`), with `limit` keeping the newest N.
- `channels(flow)` — returns `{ name, archived }[]` starting with `{ name: "main", archived: false }`, paired with `validateChannelAction(flow, { action, name })` and `validatePostChannel(flow, channel)`.
- `overview(flow, nowOrOptions?)` — data-only narrator returning `{ members: [{ agent, state, line }], openQuestions: [{ seq, from, text }], openDefects: [{ seq, from, to, text }], stalls }`:
  - `members` emits at most one row per helper, from its latest run; `line` is that run's latest step note, or else the helper's latest post (sanitised, one line, capped at 140 characters).
  - A question stays open while no later post has `replyTo` equal to its `seq`.
  - A defect stays open until a later `result` post by the same author closes it: `replyTo` equal to that defect's `seq` is checked first; as a fallback when `replyTo` is omitted, a later `result` post from the same author closes the defect when it mentions the defect's (non-lead) worker recipient and either the author has only one task or both posts resolve to the same unambiguous task (a defect addressed only to `@lead`, or one from an author with several tasks and no explicit task number, is closed only by `replyTo`).
  - `stalls` reuses `stalls()` and keeps `"quiet"` and `"stalled"` worker runs.
- `pendingWakes(flow, alreadyWoken)` — returns `{ seq, target, runId?, from, excerpt }[]` for waiting members (and `@lead`) mentioned in posts, skipping `(seq:target)` keys in `flow.woken` and `alreadyWoken`, expanding `@all` to non-retired members, and never waking a post's own author.

## How Plugins Use It

Each harness plugin (`Claude Code`, `Antigravity`, `OpenCode`) vendors direct copies of `src/core.mjs` (`orchestrator-core.mjs`) and `src/prices.mjs` (`prices.mjs`) via `//tools/agent-roster` so plugins remain self-contained at runtime without external package resolution. `bazel run //tools/agent-roster -- --check` enforces that every vendored copy stays byte-identical to `packages/orchestrator-core/src/`.

## Subdirectories & Boundaries
- [src](./src/README.md): Component package providing implementation for packages/orchestrator-core/src.

