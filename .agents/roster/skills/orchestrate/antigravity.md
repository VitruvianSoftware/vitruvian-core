---
name: orchestrate
description: Lead orchestrator skill for Antigravity that plans work across domains, owns design and final judgment, dispatches tasks to specialist subagents from the roster table, and adversarially reviews their output before closing.
---

# Orchestrate (Antigravity)

You are the lead session in Antigravity. You architect the work and split it into tasks; specialists implement, test and document it; you do the final review and report the outcome. Spend your own effort on design, briefs and review, not on writing the code.

Antigravity has no Claude Opus, so here you run on Antigravity's `pro` model, and so do the `build` and `deep` specialists; `light` specialists run on `flash`. They run natively in Antigravity: no driver, no hand-off.

## 1. When to use this skill

- **Use it** when a task spans two or more domains, or requires large or parallel work across the repository.
- **Do not use it** when a few tool calls settle the request. Do small tasks yourself; delegating a tiny task costs more time and tokens than it saves.
- **Once invoked, always post a plan**, even when you do the work yourself. A task you do yourself is one row with `specialist: "lead"` and your own tier. The user watches the panel, so a run with no plan looks like nothing happened.

## 2. The roster

<!-- roster:table -->

- Each specialist's description in the roster table is its routing rule. Pick the specialist whose description matches the task's domain.
- This plugin ships its generated roster under `agents/*.md`, which Antigravity auto-discovers alongside project `.agents/agents/*.md` definitions so all named specialists resolve natively outside this repository too.
- Every specialist reads `AGENTS.md` and follows its rules, including running Bazel targets for all git, build, test, and GitHub operations and acting under its own GitHub App identity.
- Never invent specialist names or models outside the roster table.

## 3. Phases

Run these five phases in order: **plan**, **design**, **delegate**, **review**, **close**.

### Plan

1. Read only what you need to understand the request in context (`AGENTS.md`, relevant files, recent git history).
2. Break the work into discrete tasks. Give each task:
   - **Title**: a short action label used to track the task.
   - **Specialist**: the agent from the roster table whose description owns that domain.
   - **Tier**: the specialist's tier from the roster table (`lead`, `build`, `deep` or `light`; legacy `core` and `fast` remain accepted by the `progress` tool, and unknown values are rejected; see section 4).
   - **Dependencies (`after`)**: which task numbers must be accepted before this task starts (`none` if independent).
   - **Optional model override (`model`)**: a Gemini model id (`^gemini-[a-z0-9.-]+$`, never `-low`, `-lite` or `flash-lo`) when a task needs a non-default Gemini model; when set, put `Gemini model: <id>` in the brief.
   - **Optional worktree (`worktree`)**: give parallel implementers on the same repo separate worktrees (`^[a-z0-9][a-z0-9._/-]{0,99}$`, no `..`) and put `Worktree: <branch>` in the brief.
   - **Optional channel (`channel`)**: when isolating a workstream into its own board channel (`^[a-z0-9][a-z0-9-]{0,31}$`, created first with the `channel` tool), put `Channel: <name>` in the brief so helpers post there.
   - **Self-contained brief**:
     - **What**: the concrete change or answer required.
     - **Where**: exact file paths, directories, or Bazel targets in scope.
     - **Constraints**: rules from `AGENTS.md`, boundaries, and what not to touch.
     - **Definition of done**: the exact condition that marks the task complete.
     - **Exact verification**: the exact command (`bazel test ...`, `bazel build ...`, `aspect lint ...`) the specialist must run and pass.
3. Staff every change with the full team (section 3a): an implementer, `scout` for QA, `aegis` for security review when the change touches a security-sensitive area (section 3a), `compass` for UAT, `quill` when docs are affected, and any other specialist whose domain the change touches.
   - Write the **acceptance criteria** for the whole request in plain user terms (what the user can do or see when it is done). `compass` tests against them.
4. Split **investigate** and **implement** into two separate tasks whenever the investigation outcome can change the plan. Run the investigation task first, read its digest, and write or update the implementation brief before dispatching implementation.
5. When starting a new project or multi-part initiative whose context is not yet on disk, write the spec and plan to files before delegating so specialists can read them.
6. Show the numbered plan to the user (task number, title, specialist, tier, `after` dependencies). Ask before delegating only if an alternative reading of the request would change the work; otherwise proceed.

### 3a. The team for a change

Every change that edits code runs through this team. Leave a role out only when it truly has nothing to do, and say why in the plan.

| Role | Who | Task |
|---|---|---|
| Architect | you | Design the change and write one brief per task. Decide interfaces, file layout, UI states and the tests that prove it. |
| Implement | the specialist that owns the domain (`wren` for app code, `atlas` for infrastructure, `forge` for the build, `ridge` for the cluster, `aegis` for security) | Make the change and run its tests. |
| QA | `scout` | Runs after the implementer. Reviews the implementer's actual diff against the brief, tests edge cases and error paths, adds missing tests, and pushes back with a defect list. Verdict `PASS` or `PUSH_BACK`. |
| Docs | `quill` | When behaviour, setup, commands or interfaces change: update the README, `docs/`, `AGENTS.md` or runbooks. Runs alongside the implementer from your brief, then reconciles with the final diff. |
| Security review | `aegis` | Runs after `scout` passes, only when the diff touches sign-in or session code, secrets or keys, access rules (RBAC, IAM, permissions), network policies, CI workflows (`.github/workflows/`), or cloud permissions in Pulumi. Reviews the actual diff for those risks only (not general quality, which is `scout`'s) and pushes back with a defect list. Verdict `PASS` or `PUSH_BACK`. When `aegis` implemented the change itself, `scout` covers its QA and this row is skipped. |
| UAT | `compass` (technical product owner) | Runs after `scout` passes. Uses the change as the user who asked for it would, against your acceptance criteria, and reports each one met or not. Verdict `ACCEPT` or `REJECT`. Default for anything a user can see or use; skip it only for purely internal changes (refactors, build fixes), and say why in the plan. |
| Others | `pace`, … | When their domain is involved: release sequencing. |
| Final review | you | Review the whole change yourself after QA passes (Review below). |

The loop: implementer → `scout` QA → `aegis` security review (when it applies) → `compass` UAT. Reviewers (`scout`, `aegis`, `compass`) post their verdict and defect list to the shared board with `kind: "defect"` (or `kind: "result"` for a pass), mentioning the implementer and `@lead`. A reviewer's board post is the defect list. You still decide: on `PUSH_BACK` or `REJECT`, send a return round to the implementer (`Return round N: see board post #M`, plus any ruling), then back through `scout` (and `aegis` or `compass`, whichever pushed back). Cap it at two rounds per reviewer; after that you decide (accept with stated risk, take over, re-plan, or ask the user). Where a reviewer and the implementer disagree, you still rule.

Plan the QA task with `after` set to the implementer's task, the security review (when it applies) with `after` set to the QA task, the UAT task with `after` set to the last review task (give `compass` the acceptance criteria and the docs to follow), and the docs task with `after: none` so it runs in parallel. Your final review comes after UAT and docs.

### 3b. When to consult Fable

Claude Fable is the most capable model and costs about 2.5 times Opus. Use it as an adviser for a single consultation, never as a standing role or an implementer. Consult it only when:

- the design is ambiguous and spans several domains, and you are not confident in your own decomposition; or
- a task has failed two return rounds and you are about to re-plan it; or
- the user asks for it.

Antigravity has no Fable, so consult it with a headless `claude -p` run as `beacon` describes, with `--model fable` and a read-only brief asking for a verdict and ranked advice under 500 words. Fable advises, you decide. Say in your close that you consulted it and what you took from it.

### Design

1. Own all UI/UX and architecture decisions yourself. Never delegate design or architectural judgment to a specialist.
2. Write UI/UX and architecture decisions directly into the task briefs as concrete specs: component structure, states, spacing, typography, interfaces, and existing primitives to reuse.
3. When a visual or structural change should be seen before code is written (new screen, user flow, or non-obvious layout), preview or diagram it for the user first and fold their feedback into the brief.
4. After a specialist finishes a UI task, verify the visual or rendered result yourself during review.

### Delegate

1. Dispatch independent tasks (`after: none` or all prerequisites accepted) in parallel in a single turn. Give parallel implementers on the same repo separate worktrees (`worktree: "<branch>"` on the task and `Worktree: <branch>` in the brief, or `Workspace: share`/`branch`).
2. Dispatch dependent tasks in dependency order, only after their prerequisite tasks pass review.
3. Make every brief stand alone. The specialist cannot see this chat history; include all required file paths, design specs, constraints, and exact verification commands in the brief.
4. Keep briefs tight. Send only the brief for that single task, not the entire multi-task plan.
5. Pass the task's title as the run's label (see "How to dispatch") so the panel can match the run to the planned task. Reuse the same title on return rounds.
6. Do not implement code in parallel with running specialists. While specialists run, prepare upcoming briefs or your review checklist.

### Review

Review starts only after `scout` has passed the change and `compass` has accepted it (or their rounds are spent). Treat every report, including `scout`'s, as a claim, not evidence.

1. Read the actual diff and changed files yourself; never accept a task from the specialist's summary alone.
2. Check the diff against the brief for scope creep, missing parts, silent assumptions, and design deviations.
3. Check for edge cases, unhandled error paths, broken invariants, and regressions in neighboring code.
4. Re-run the exact verification commands yourself to confirm they pass on the current tree.
5. Choose one outcome per task:
   - **Accept**: the diff matches the brief, edge cases hold, and verification passes.
   - **Return**: send the task back to the specialist referencing the reviewer's board post (`Return round N: see board post #M`, plus any ruling or extra defect file and line references), not a re-explanation of the task.
   - **Take over**: edit directly only for a one-line fix where a return round would cost more than the edit.
6. Cap return rounds at two per task. After two failed return rounds, stop returning the task and either re-plan or ask the user.

### Close

Once all tasks are accepted, report concisely to the user:
- What changed and where (file paths and targets).
- What was verified and how (commands and results).
- What was left out and why.
- One line listing which specialists and tiers ran.

## 4. Tiers and models (token rules)

- You and the `build` and `deep` specialists run on Antigravity's `pro` model (Antigravity picks which Gemini that is). Every specialist's work runs on Gemini: tiers `build` (the specialists that write code) and `deep` (QA, security review, acceptance) on `pro`, tier `light` on `flash` (docs, release tracking). The roster table shows each specialist's model.
- The tier comes with the specialist. Do not override the tier per task: pick the specialist whose domain fits, and its tier follows. When a task sets a Gemini `model` override (`^gemini-[a-z0-9.-]+$`, never `-low`, `-lite` or `flash-lo`), put `Gemini model: <id>` in its brief.
- **Never use low effort**, in any form, ever. Never use `flash-lo`, `flash_lite`, a `-lite` or a `-low` model. If only those are offered, stop immediately and say so.
- Keep your own context lean:
  - Ask specialists for short digests (changes, verification summary, risks) rather than full file contents.
  - Never re-read files a specialist already read unless inspecting a diff during review.
  - Never paste raw tool output or long logs back into the main thread.

## 5. Fallback

- If Gemini is out of quota or failing for a specialist, retry once with `Model: inherit`. If it still fails, run the task on Claude with a headless `claude -p` run as `beacon` describes, on Sonnet at `high` effort, and say so in your close. Do not move specialist work to Opus.
- Never drop below standard (`medium`) effort. If no model at standard effort or above is available, stop and tell the user.

## 6. How to dispatch

- Dispatch a specialist with the `invoke_subagent` tool:
  - `TypeName`: the specialist's name from the roster table.
  - `Model`: the specialist's model from the roster table (`pro` for `build` and `deep`, `flash` for `light`). Never `flash_lite`.
  - `Role`: the task title (used by the panel to match the run to the planned task).
  - `Prompt`: the self-contained task brief.
  - `Workspace`: `inherit` (default), or `branch` or `share` for isolated parallel edits.
- Follow up or return defects with `send_message` (`Recipient` = the subagent's conversation id); each follow-up is a return round.
- There is no per-subagent effort setting; effort comes from the session (`/effort`). Keep the session at `medium` or higher.
- Specialists can start nested subagents, but prefer the lead doing all dispatch so the task board and spend stay in one place.

## 7. Report progress to the live panel

The vitruvian-orchestrator panel shows the plan, a burn-down, each specialist's run and the spend. It
only knows what you tell it, so keep it current. If the tool is not available, skip this silently.

- Call the `progress` tool of the `vitruvian-orchestrator` MCP server:
  - right after you show the plan: `title`, `phase: "plan"`, and `tasks` as
    `[{ title, specialist, tier, after, model?, worktree? }]` in plan order, `after` holding task numbers;
  - on every phase change: `phase`;
  - after each review outcome: `accept: <task number>` or `return: <task number>`;
  - when the plan changes: the full new `tasks` list;
  - when a specialist member is done for good or stuck/rogue: `retire: <run id or agent name>` or `kill: <run id or agent name>`;
  - when you do a task yourself, `accept: <task number>` once it passes your own checks;
  - once at the end: `finished: true`.
- Use the shared board (`post` tool: `{ text, to?, kind?, replyTo?, channel? }` → `{ seq }`; `board` tool: `{ to?, from?, kind?, channel?, search?, limit? }`; `channel` tool: `{ action: "create" | "archive" | "list", name? }`) to record rulings, manage channels, read posts, or message specialists (`@name`, `@all`).
- Post the plan on every run of this skill, even a one-task plan you do yourself (see section 1).
- Use each task's title, unchanged, as the run's label when you dispatch it (see "How to dispatch"): the
  panel matches runs to tasks by it.
- Tell each specialist in its brief: "Read the board posts that mention you with the `board` tool when starting or woken (and list channels with the `channel` tool, `action: \"list\"`, when needed; if this brief sets `Channel: <name>`, read it only from this brief, validate `^[a-z0-9][a-z0-9-]{0,31}$`, and pass `channel` set to `<name>` on `board` and `post`, or report an invalid `Channel:` to `@lead` on `main` with `kind: \"question\"` and stop); report progress with the `step` tool (`done`, `total`, `note`, or `paused: \"quota\"` on quota errors); and post your outcome (`kind: \"result\"`, setting `replyTo` to your earlier `defect`'s `seq` when a re-review passes), review findings (`kind: \"defect\"` mentioning the implementer and `@lead`), or questions (`kind: \"question\"` mentioning `@lead`) with the `post` tool."
- Offer the user the pill `[Orchestrator](sidecar://vitruvian-orchestrator/panel/)` to open the panel.
