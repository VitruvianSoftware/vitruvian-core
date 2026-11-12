---
status: in-progress
---

# Orchestrator: swarm parity (board, members, graph, overview, channels)

Google Antigravity shipped `/swarm` (preview, 2026-11-10): a coordinator splits a task across named workers and verifiers that talk on one shared message board. This brings its useful parts into `vitruvian-orchestrator` in all three harnesses (Claude Code, Antigravity, OpenCode), on top of what we already have (plan and task board, phases, runs, steps, stall watchdog, review loop).

Source for the swarm feature set: <https://antigravity.google/docs/swarm/>, plus the Antigravity CLI 1.5.6 binary, which also contains a narrator, channels and stages that the docs do not mention yet.

## Principles

- **The lead still rules.** The board is the team's shared record and lets specialists read each other's findings directly. It does not replace the lead's review: every report is still a claim, the lead accepts or returns each task, and disputes come to the lead.
- **Pure core, thin harnesses.** All state and derived views live in `packages/orchestrator-core/src/core.mjs` (vendored byte-identical into the three plugins by `//tools/agent-roster`). Each harness adds tools, rendering and the wake mechanism only.
- **Old flow files keep loading.** Every new event field is optional; a flow with no posts renders exactly as today.
- **Agent text is untrusted when rendered.** Post text is escaped everywhere it is drawn (HTML in Antigravity, SVG in Claude Code).

## Phase 1: board and member states

### Core

- New event `post`: `{ type: "post", at, from, text, to?: string[], kind?: "note"|"question"|"defect"|"result", replyTo?: number, channel?: string }`.
  - The reducer assigns `seq` (1, 2, 3 … per flow) and stores it in `flow.posts`.
  - `to` is the union of the explicit list and the `@name` mentions parsed from `text` (`mentions(text)`: `@` followed by `[a-z0-9][a-z0-9-]*`, not preceded by a word character; `@all` and `@lead` are special names). Names are lower-cased and de-duplicated.
  - Text is capped at 4000 characters (longer text is cut and marked `…[truncated]`); empty text is ignored.
- Member state. A member is a run (one specialist dispatch). Derived view `members(flow)` returns `{ active, standingBy, retired }`, each a list of `{ id, agent, state, reason?, taskN?, model, delegate?, lastPostSeq?, lastActivityAt }`:
  - `working`: run running and not waiting.
  - `waiting`: run running and waiting on background work, or run ended normally (it can be woken by a message).
  - `paused`: new event `member.pause` `{ id, reason: "quota"|"error", detail? }`. Cleared by any later `run.progress` or `run.start` for that id.
  - `killed`: new event `member.kill` `{ id }`.
  - `retired`: new event `member.retire` `{ id }`, or the flow closed.
  - `active` = working; `standingBy` = waiting + paused; `retired` = killed + retired.
- Derived view `board(flow, { search?, from?, to?, kind?, channel?, limit? })`: posts newest last, filtered (search is case-insensitive on text, from and to). `limit` keeps the newest N.
- Derived view `pendingWakes(flow, alreadyWoken)`: for each post, each mentioned member whose state is `waiting` (or the lead for `@lead`) and that is not the post's author, one `{ seq, target, runId?, from, excerpt }`, skipping keys (`seq:target`) already in `alreadyWoken`. `@all` expands to every non-retired member except the author.

### Tools (every harness)

- `post`: `{ text, to?, kind?, replyTo? }` → `{ seq }`. Available to the lead and every specialist.
- The `step` tool gains optional `paused: "quota"|"error"` (and `detail`), which emits `member.pause`.
- The lead's `progress` tool gains `retire: <run id or agent name>` and `kill: <run id or agent name>`.

### Wake on mention

- **Claude Code** (`hooks/register.tsx`): a sleeping subagent cannot wake itself, so the plugin wakes the lead. On each new post, compute `pendingWakes`; for each, call `$.prompt.submit` once with: `[Orchestrator board] Post #N from <from> mentions <target>: "<excerpt>". Wake <target> with SendMessage to agent id <runId> and pass it the post.` For `@lead` the message is just the post. Remember woken keys in memory (per session) so each wake is sent once. Same idle guard and `.catch(() => {})` as the stall watchdog.
- **Antigravity** (`sidecars/panel/main.mjs`): the sidecar can message any conversation (`app.sendMessage`). Deliver the post straight to the mentioned worker's conversation when its conversation id is known (from the `invoke_subagent` transcript tracking already in `main.mjs`); otherwise to the lead, as in Claude Code.
- **OpenCode** (`server.mjs`): use the same mechanism its plugin API offers to send a message into a session (find it in the OpenCode plugin API in this repo's existing code first). If none exists, show the wake in the sidebar and do not invent one; say so in the PR.

### Review flow

- Reviewers (`scout`, `aegis`, `compass`) post their verdict and defect list with `kind: "defect"` (or `"result"` for a pass), mentioning the implementer and `@lead`.
- The lead's skill text: a reviewer's board post is the defect list. The lead still decides; a return round is the lead's message to the implementer (`Return round N: see board post #M`, plus any ruling).
- The driver agents (generated by `//tools/agent-roster`) are told: read the board posts that mention you when you start and when woken; post your result with `kind: "result"`; post questions with `kind: "question"` mentioning `@lead`; on a Gemini quota error call `step` with `paused: "quota"`.

### Rendering

- **Antigravity** panel (`sidecars/panel/app.js` + HTML): tabs **Board** and **Members** next to the existing view.
  - Board: one row per post: `#seq`, author, `→ recipients`, relative time, kind badge (question = amber, defect = red, result = green, note = grey), text with "Show more" past 6 lines. Search box, filters for author, recipient and kind, a "Follow" toggle that keeps the newest post in view, and a "Jump to latest" button when not following.
  - Members: groups Active, Standing by, Retired (collapsed by default), each member with agent name, task, model (and Gemini delegate), state badge, last activity, and its latest post.
- **Claude Code** panel (SVG and terminal): a "Board" section with the newest 6 posts (same row format, single line, text clipped) and member state badges on the existing agent rows (paused: amber "paused: quota"). Full board browsing comes in phase 3.
- **OpenCode** sidebar (`tui.tsx`): the newest 5 posts and member state badges.

## Phase 2: mention graph, per-task model, worktree per worker

- Core `mentionGraph(flow, { uptoSeq? })` → `{ nodes: [{ id: agentName, posts }], edges: [{ from, to, count }] }` from posts up to `uptoSeq`.
- **Antigravity** Graph tab: nodes in a circle, edge width by count, arrowheads; replay controls (play/pause, step back/forward, slider over `seq`, "Live" returns to the newest); "Hide inactive" hides retired members.
- **Claude Code / OpenCode**: a "Who talks to whom" line list of the top 5 edges (`scout → wren ×4`).
- **Per-task model**: tasks gain optional `model` (a Gemini id from `agy models`, never `-low`, `-lite` or `flash-lo`; the core rejects those). The lead puts `Gemini model: <id>` in the brief; the driver template uses it instead of its default when present and valid. The panel shows the override on the task and run.
- **Worktree per worker**: a task may carry `worktree: "<branch>"`. The brief then says `Worktree: <branch>`; the driver creates it with `bazel run //tools/worktree -- <branch>` (or reuses it), runs `agy-delegate -d <that path>`, reports the path in its first step note (`step` gains optional `worktree`), and must report what it changed there before finishing. The panel shows the worktree on the member. The lead's skill text: give parallel implementers on the same repo separate worktrees.

## Phase 3: terminal board, overview, channels

- **Claude Code** command `/orchestrator-board` prints the board in the terminal: `--from <name>`, `--to <name>`, `--kind <kind>`, `--channel <name>`, `--search <text>`, `--last <N>` (default 30). Plus `/orchestrator-board members`. (Claude Code offers no custom key binding, so no Alt+S.)
- **Overview** (our "narrator", built from data, no extra model calls): core `overview(flow)` → per active or standing-by member one line (latest step note, else latest post), open questions (question posts with no later post that has `replyTo` = that seq), open defects (defect posts with no later `result` post from the same reviewer about the same task), and stalls. Shown as an Overview tab in Antigravity, a section in Claude Code and OpenCode.
- **Channels**: posts carry `channel` (default `main`). New event and tool `channel`: `{ action: "create"|"archive"|"list", name }`; archived channels accept no posts. Board filters and `/orchestrator-board --channel` use it; Antigravity shows channel tabs once a non-main channel exists.
- **Not built**: staged pipelines with a conductor (our plans already carry dependencies), Alt+S, approvals jump (Claude Code has its own).

## Acceptance criteria (what James can see)

1. When specialists work, their results, questions and defect lists appear as numbered posts on a board in each tool's panel, with who sent them to whom.
2. Mentioning a finished helper wakes it (directly in Antigravity, via the lead in Claude Code), once per mention.
3. Each helper shows as working, waiting, paused (with the reason) or retired.
4. Antigravity shows Board, Members, Graph (with replay) and Overview tabs; search and filters work.
5. `/orchestrator-board` in Claude Code lists and filters the board.
6. Old flows with no posts look exactly as before.
