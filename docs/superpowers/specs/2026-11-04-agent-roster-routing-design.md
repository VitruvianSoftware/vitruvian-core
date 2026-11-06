---
status: draft
date: 2026-11-04
---

# One roster, two harnesses: routing subagents in Claude Code and Antigravity

## The problem in one paragraph

James works in both Claude Code and Antigravity. Both read the same ten agent files in
`.agents/agents/`, but the two tools pick models and run subagents differently. Today the
routing rules are written down in three places, and they disagree:

| Where | What it says |
|---|---|
| `.agents/agents/beacon.md` "Model tiering policy" | Opus / Sonnet / Gemini per agent; never low effort |
| Claude Code `savvy-flow` plugin (savvy-light … savvy-fable) | Every tier is Opus or Fable, light tier at **low** effort |
| Antigravity `savvy-fleet` skill (`skills/savvy-flow/SKILL.md`) | pro / inherit / flash tiers, light tier at **low** effort |

The agent files themselves say `model: inherit` (except `scout`), so none of those tables is
enforced. Claude Code sees the agents only through hand-made symlinks in `~/.claude/agents/`.

> **Update 2026-11-05:** only the lead runs on Claude Opus. Every specialist's work now runs on
> Gemini (tiers `deep` = Gemini 4 Argon, `light` = Gemini 3.8 Flash), through a Haiku driver in
> Claude Code and OpenCode, and each change is staffed with an implementer, `scout` for QA,
> `compass` for UAT and `quill` for docs before the lead's final review. The `core` and `fast` tiers below are gone. See
> [How the agent team works](../../concepts/agent-team.md).

## Goals

1. **Work like buzz.** One lead agent plans and reviews. Specialists do the work, and they can
   message the lead and each other. Buzz does this over a shared relay; here each harness has
   its own message tool, so the lead skill maps the same steps onto each tool.
2. **Save tokens.** Opus only plans and reviews. Most work runs on cheaper models. Bulk
   generation goes to Antigravity, where it costs no Claude tokens.
3. **One source of truth.** Change the roster once and both harnesses follow it.
4. **See it live.** A panel shows which specialist is working on what, on which model, what
   it costs, and a burn-down of the lead's task list.
5. **Replace savvy-\*.** `vitruvian-orchestrator` ships as one plugin per harness and takes over
   from savvy-flow, savvy-progress and savvy-fleet, which are then removed.

## Design

### 1. A harness-neutral roster file

`.agents/roster/` is the only place a person edits to change who does what on which model.

> **As built:** the roster is two TSV files, `.agents/roster/tiers.tsv` and
> `.agents/roster/agents.tsv`, plus `.agents/roster/prompts/<name>.md`. TSV matches the repo's
> other tables (`tools/agent-app/agents.tsv`) and keeps the generator free of external
> libraries, like the other Rust tools. The YAML below shows the shape of the data, not the
> file format.

```yaml
tiers:            # cost ladder; escalate one step on failure, never start high
  lead:   { claude-code: { model: opus,   effort: high   }, antigravity: { model: pro   }, opencode: { model: anthropic/claude-opus-5-5,   effort: high   } }
  core:   { claude-code: { model: sonnet, effort: high   }, antigravity: { model: flash }, opencode: { model: anthropic/claude-sonnet-5-5, effort: high   } }
  fast:   { claude-code: { model: haiku,  effort: medium }, antigravity: { model: flash }, opencode: { model: anthropic/claude-haiku-5-5,  effort: medium } }
  # Antigravity: pro = Gemini 4 Argon, flash = Gemini 3.8 Flash; only inherit|flash|pro, no effort field.
  # OpenCode: full provider/model ids only; effort is written as reasoningEffort (all verified below).

agents:
  wren:   { tier: core, role: "App engineering across every app workspace", prompt: prompts/wren.md }
  scout:  { tier: fast, role: "Bazel tests, flaky tests, CI watch",         prompt: prompts/scout.md, read_only: false }
  # … one line per agent

fallback:         # what to do when a model or harness is out of quota
  claude-code:  [ same tier on the other harness, one tier down on the same harness ]
  antigravity:  [ one tier down on the same harness ]

rules:
  never_low_effort: true
  bulk_to_antigravity: true   # mass scaffolding, test generation, migrations, long reads
```

The prompt bodies (`prompts/*.md`) hold only the role text and say nothing about a specific
harness. Today's agent files are mostly this already.

### 2. A generator that writes each harness's files

`bazel run //tools/agent-roster:generate` reads the roster and writes the agents and the lead
skill into each plugin (section 3). Claude Code agents get the tier's model; Antigravity agents
get `pro` or `flash`. Each harness's lead skill uses that harness's tools. The repo's
`.agents/agents/` keeps a generated copy, so Antigravity sessions without the plugin still find
the specialists.

A test (the same pattern as the generated `presubmit.yaml`) fails CI if a generated file drifts
from the roster. That stops the three tables from drifting apart again. The `~/.claude/agents`
symlinks go away, because Claude Code reads the project's `.claude/agents/` itself.

### 3. Two plugins, one core: `vitruvian-orchestrator`

The generated skill and agents ship inside a plugin for each harness, with a live panel. Both
plugins share one core, so the flow, the task list and the cost maths are written once.

| Part | Claude Code plugin | Antigravity plugin |
|---|---|---|
| Location | `apps/claude-code/plugins/vitruvian-orchestrator/` (new) | `apps/antigravity/plugins/vitruvian-orchestrator/` |
| Generated agents | `agents/*.md` (opus / sonnet / haiku) | `agents/*.md` (`pro` / `flash`, description ≤ 320) |
| Generated lead skill | `skills/orchestrate/SKILL.md` | `skills/orchestrate/SKILL.md` |
| Live view | a mod (`hooks/register.tsx`): bar above the prompt + agents pane | a sidecar side panel (`sidecars/panel/`) |
| How it sees subagents | the mod's own events + a `progress` / `step` tool it registers | `PostToolUse` hook on `invoke_subagent` / `send_message` + transcript |
| Shared core | `packages/orchestrator-core` (TypeScript): flow state, burn-down, cost table, matching runs to tasks | same package, bundled into the sidecar |

Verified from the shipped sources, not built yet: a Claude Code mod can register tools and
commands and open panes (`savvy-progress` uses `$.tool.register`, `$.command.register`,
`$.ui.open`). An Antigravity plugin can run a side-panel sidecar and hooks (`savvy-fleet` passes
`agy plugin validate`: 2 skills, 1 rule, 1 hook, 1 sidecar). The two plugin formats differ
(Antigravity reads a root `plugin.json` and a named-hook `hooks.json`; Claude Code reads
`.claude-plugin/plugin.json` and `hooks/hooks.json`), so they stay two folders.

**OpenCode** gets a third plugin in the same shape, at
`apps/desktop/opencode/plugins/vitruvian-orchestrator/`. The generator writes its agents into
`.opencode/agents/`, the only place OpenCode looks (verified). Its live view is a TUI plugin
filling the `sidebar_content` slot, fed by the plugin's `event.subscribe` stream. Subagent
sessions carry a `parentID`, which ties each run to the lead. The sidebar slot comes from
the plugin SDK's types and has not been built or run yet.

**What the panel shows**, in every harness:
- **Header**: the flow's title, its phase (plan → design → delegate → review → close), and
  tasks accepted out of planned.
- **Burn-down**: tasks remaining over time, with a mark at each re-plan. This is new; savvy
  shows only a done/total count.
- **Task board**: each planned task with its specialist, tier, model, dependencies, state
  (waiting, running, in review, returned, accepted) and return round.
- **Agents**: each running or finished subagent with its model, its own step progress, context
  fill, tokens, estimated cost and time. Work sent to Antigravity from Claude Code via
  `agy-delegate` appears as its own row, so off-Claude work is visible too.
- **Spend**: estimated cost so far by model, split into lead and workers. Showing where the
  Opus tokens go is the point of goal 2.

### 4. The lead skill

The lead is **the session you are typing into**, not a `beacon` subagent. That removes a whole
Opus layer from every request. `beacon.md` becomes the body of the lead skill. The skill is one
template with a per-harness tool map:

| Step | Claude Code | Antigravity | OpenCode |
|---|---|---|---|
| Dispatch a specialist | `Agent`: `subagent_type` = roster name, `model` = tier, `description` = task title | `invoke_subagent`: `TypeName` = roster name, `Model` = tier, `Role` = task title | `subagent`: `agent` = roster name, `model` = `provider/model#variant`, `description` = task title |
| Follow up or answer a question | `SendMessage` to the agent id | `send_message` to the conversation id | `subagent` again with its `sessionID` |
| Run in the background | `run_in_background` | (async by default) | `background: true` |
| Send bulk work off Claude tokens | `agy-delegate` / `antigravity-delegate` | (already on Gemini) | `agy-delegate` |
| Verify | run the gate yourself; a report is a claim, not proof | same | same |

Token rules in the skill:
- Do it yourself when it takes a few tool calls. Delegate when the work is big or parallel.
- Start every task at the lowest tier that can do it. Escalate one tier only on failure.
- Bring back a digest, not file dumps. Never re-read what a specialist already read.
- Read-only search and CI watching go to the `fast` tier.

### 5. What we take from savvy-\*, and what we change

**Keep (from savvy-flow's playbook):**
- The five phases: plan, design, delegate, review, close.
- A task list where every task has a self-contained brief, dependencies (`after`) and a tier.
  Show it to the user before delegating, and ask first if a reading would change the work.
- The lead owns design and final judgment and never delegates them. UI is shown with the
  `visualize` widget before code is written.
- Adversarial review: read the diff, not the report. Each task is accepted, returned with a
  precise list of defects, or (for one-line fixes) taken over. At most two return rounds,
  then re-plan or ask.
- Split "investigate" and "implement" into two tasks when the investigation can change the plan.
- New projects: write the spec and plan into files before delegating, because workers cannot
  see the chat.
- Matching a run to its task by passing the task title as the dispatch description (Claude
  Code) or `Role` (Antigravity).

**Keep (from the panels):**
- Workers report their own steps; a worker that doesn't report shows its context fill instead.
- A price table that turns tokens into an estimated cost per model (shown as an estimate, not
  a bill).
- James's chibi mascots per agent (`MASCOTS` in his savvy-progress fork), with
  `prefers-reduced-motion` respected.
- Antigravity's round counting: a `send_message` to a worker counts as a return round.

**Change:**
- **Tier is chosen per dispatch, not per agent.** savvy has one agent per tier (savvy-light …
  savvy-fable). We have one agent per specialist (wren, forge …) and choose the tier's model on
  each call. That matches what both harnesses support (verified above).
- **Tiers follow the roster's cost ladder** (lead, core, fast), not five Opus levels. savvy's
  rule "when unsure, take the higher tier" becomes "start cheap, step up one tier on a failed
  review", to serve goal 2.

**Drop:**
- savvy's light tier at low effort; it breaks the never-low rule.
- Every Opus-only tier.
- The duplicate tier tables; tiers live only in the roster.

**Removal of savvy-\*:** once both plugins are installed and James has run one real flow in
each harness, uninstall savvy-flow and savvy-progress (Claude Code) and savvy-fleet
(Antigravity), and delete `apps/antigravity/plugins/savvy-fleet/` and its mirror.

## Verified facts (2026-11-04, Antigravity CLI 1.5.0)

1. **Antigravity agent files accept only `model: inherit`, `flash` or `pro`.** Tested by
   dropping temporary agents into the main checkout's `.agents/agents/` and running
   `agy agents`. `inherit`, no `model`, `flash` and `pro` loaded. `sonnet`, `haiku`,
   `claude-opus-5-5-high`, `gemini-3.8-flash-high`, `gemini-4-argon-high`, `argon`, `fast`
   and a bogus value all made the agent **silently disappear**, with no error. That is why
   `scout` (`model: sonnet`) is missing from `agy agents` today.
   - The changelog says `pro` is Gemini 4 Argon and `flash` is Gemini 3.8 Flash.
   - Agent files have no effort field (none in the binary's frontmatter tags; not tested
     further). Effort is set per session (`agy --effort`, `/effort`).
2. **Per call, `invoke_subagent` takes `Model`: `inherit`, `flash_lite`, `flash` or `pro`.**
   Antigravity printed this schema itself (a model self-report, which matches the binary's
   strings and changelog). A subagent cannot be given a Claude model or an effort level this
   way. `send_message` takes a recipient conversation id and a message.
3. **Model ids for an Antigravity session** (`agy models`): `gemini-4-argon-{low,medium,high}`,
   `gemini-3.8-flash-{low,medium,high}`, `claude-opus-5-5-{low,medium,high}`,
   `claude-sonnet-5-5-{low,medium,high}`, `gpt-oss-120b-medium`. There is **no Haiku and no
   Gemini 3.1 Pro**, so `beacon.md`'s Gemini names are stale. These ids apply to the main
   session (`--model`), not to subagents.
4. **Claude Code subagents can start their own subagents.** Tested: a Haiku subagent found
   `Agent` and `SendMessage` in its tools and launched a nested subagent, which answered.
   Antigravity also supports nesting ("grandchild and deeper", per the changelog; not tested
   live). An Antigravity agent that lists `invoke_subagent` in its tools is given the
   subagent roster automatically.
5. **Worktrees are fine; the `agy agents` listing is misleading.** In a real session in this
   worktree, Antigravity loads the worktree's own `.agents/agents/` whether or not the folder is
   trusted. Tested by calling a probe agent placed only in the worktree (it answered) and one
   placed only in the main checkout (not found). The `agy agents` *listing* shows project
   agents only for folders in `trustedWorkspaces` (`--settings '{"trustedWorkspaces":[...]}'`
   makes them appear). Neither reads `~/.agents/agents/`. agent-guard runs in an untrusted
   worktree: it refused a `git init` there.
6. **Antigravity silently drops an agent whose `description` is longer than about 320
   characters.** Probes at 320 characters loaded; probes at 350, 400 and 420 were "not found".
   `forge` (444 characters) is unusable in Antigravity sessions today, although `agy agents`
   still lists it. Its body is not the problem: a probe with forge's body and a short
   description loaded.

7. **OpenCode (CLI 2.2.5, `brew` reports it current)** — all tested with probe agents and a live
   `opencode run`:
   - It reads agents only from `.opencode/agent/` or `.opencode/agents/`. It ignores
     `.agents/agents/` and `.claude/agents/`, so **today it sees none of ours**.
   - `model` must be a full `provider/model` id (`anthropic/claude-sonnet-5-5`). `model: sonnet`
     and `model: inherit` **silently drop the agent**. Leaving `model` out inherits the
     parent's. A wrong id still loads (it would fail only when run; not tested).
   - Effort per agent works: `reasoningEffort: high` is passed through, and `variant: high` is
     read as a model variant.
   - Descriptions have no length limit up to 900 characters, and a missing description loads.
   - The dispatch tool is `subagent`: `agent`, `prompt`, `description`, an optional `model`
     (`provider/model#variant`), `background`, and `sessionID` for follow-ups. Its own help
     text says not to set `model` unless asked, so the lead skill must say explicitly to set it.
   - **Nesting is off by default.** A subagent's call to another subagent failed with "Subagent
     depth limit reached (1)". `experimental.subagent_depth` raises it.
   - No Google provider is configured, so OpenCode has no Gemini models here. Its models are
     Anthropic, OpenAI and local ones (`opencode models`).
   - The installed plugin SDK is `@opencode-ai/plugin` 1.18.30; npm's latest is 1.19.5.

**Today in an Antigravity session:** 8 of the 10 agents work. `forge` is dropped for its
description length and `scout` for `model: sonnet`. Tested by calling each one.

## What the facts change

- The generator must write a **different `model` value per harness**. Claude Code gets
  `opus`/`sonnet`/`haiku`. Antigravity gets `pro`/`flash`, and `flash_lite` is available per
  call. One shared file cannot serve both, so the two output folders in section 2 are required,
  not optional.
- Antigravity cannot pin effort per agent. "Never low effort" there is enforced by the session's
  `--effort`, and the lead skill states it.
- A drift test alone is not enough, because Antigravity drops a bad agent with no error, and
  `agy agents` does not show which ones it dropped. The generator must enforce the rules itself:
  `model` is one of `inherit|flash|pro`, and `description` is 320 characters or fewer. An
  optional live smoke test calls every agent through `invoke_subagent` and expects each to answer.
- **Lead skills must not sit in a shared folder.** OpenCode loads skills from `.opencode/skills/`,
  `.opencode/skill/`, `.agents/skills/` and `.claude/skills/` (verified with probe skills), so a
  Claude Code or Antigravity `orchestrate` skill placed in a shared folder would also show up in
  OpenCode, with the wrong tool names. Each harness's lead skill therefore ships inside its own
  plugin; OpenCode's goes in `.opencode/skills/`. Claude Code documents only `.claude/skills/` and
  plugin skills.
- Claude Code agent files accept `effort` (`medium`…`max`) and `model` aliases or full ids, and a
  project `.claude/agents/` file beats a user-level one of the same name (Claude Code docs,
  sub-agents page). The `~/.claude/agents/` symlinks can be removed once the generated
  `.claude/agents/` lands.
- The roster is checked by `//:tidy` (CI's Tidy Check), not a sealed Bazel test, because Bazel
  ignores `.claude/` (`.bazelignore`).
- The generator writes three different `model` forms: `opus` (Claude Code), `pro` (Antigravity),
  `anthropic/claude-opus-5-5` (OpenCode). Its checks also cover OpenCode: model ids must appear
  in `opencode models`, and the OpenCode lead skill sets `experimental.subagent_depth` if
  specialists are allowed to delegate further.
- **abrialcode.** Its agents share `~/.claude/agents/`. The generator should run per repo so
  the two rosters stay separate.
