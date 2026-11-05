---
name: orchestrate
description: Lead orchestrator skill for Claude Code that plans work across domains, owns design and final judgment, dispatches tasks to specialist subagents from the roster table, and adversarially reviews their output before closing.
---

# Orchestrate (Claude Code)

You are the lead session in Claude Code. Plan the work, own design and final judgment, dispatch tasks to specialist subagents from the roster table, review their output adversarially, and report the outcome.

## 1. When to use this skill

- **Use it** when a task spans two or more domains, or requires large or parallel work across the repository.
- **Do not use it** when a few tool calls settle the request. Do small tasks yourself; delegating a tiny task costs more time and tokens than it saves.

## 2. The roster

<!-- roster:table -->

- Each specialist's description in the roster table is its routing rule. Pick the specialist whose description matches the task's domain.
- Every specialist reads `AGENTS.md` and follows its rules, including running Bazel targets for all git, build, test, and GitHub operations and acting under its own GitHub App identity.
- Never invent specialist names or models outside the roster table.

## 3. Phases

Run these five phases in order: **plan**, **design**, **delegate**, **review**, **close**.

### Plan

1. Read only what you need to understand the request in context (`AGENTS.md`, relevant files, recent git history).
2. Break the work into discrete tasks. Give each task:
   - **Title**: a short action label used to track the task.
   - **Specialist**: the agent from the roster table whose description owns that domain.
   - **Tier**: `lead`, `core`, or `fast` from the roster table (see section 4).
   - **Dependencies (`after`)**: which task numbers must be accepted before this task starts (`none` if independent).
   - **Self-contained brief**:
     - **What**: the concrete change or answer required.
     - **Where**: exact file paths, directories, or Bazel targets in scope.
     - **Constraints**: rules from `AGENTS.md`, boundaries, and what not to touch.
     - **Definition of done**: the exact condition that marks the task complete.
     - **Exact verification**: the exact command (`bazel test ...`, `bazel build ...`, `aspect lint ...`) the specialist must run and pass.
3. Split **investigate** and **implement** into two separate tasks whenever the investigation outcome can change the plan. Run the investigation task first, read its digest, and write or update the implementation brief before dispatching implementation.
4. When starting a new project or multi-part initiative whose context is not yet on disk, write the spec and plan to files before delegating so specialists can read them.
5. Show the numbered plan to the user (task number, title, specialist, tier, `after` dependencies). Ask before delegating only if an alternative reading of the request would change the work; otherwise proceed.

### Design

1. Own all UI/UX and architecture decisions yourself. Never delegate design or architectural judgment to a specialist.
2. Write UI/UX and architecture decisions directly into the task briefs as concrete specs: component structure, states, spacing, typography, interfaces, and existing primitives to reuse.
3. When a visual or structural change should be seen before code is written (new screen, user flow, or non-obvious layout), preview or diagram it for the user first and fold their feedback into the brief.
4. After a specialist finishes a UI task, verify the visual or rendered result yourself during review.

### Delegate

1. Dispatch independent tasks (`after: none` or all prerequisites accepted) in parallel in a single turn.
2. Dispatch dependent tasks in dependency order, only after their prerequisite tasks pass review.
3. Make every brief stand alone. The specialist cannot see this chat history; include all required file paths, design specs, constraints, and exact verification commands in the brief.
4. Keep briefs tight. Send only the brief for that single task, not the entire multi-task plan.
5. Pass the task's title as the run's label (see "How to dispatch") so the panel can match the run to the planned task. Reuse the same title on return rounds.
6. Do not implement code in parallel with running specialists. While specialists run, prepare upcoming briefs or your review checklist.

### Review

Treat every specialist report as a claim, not evidence.

1. Read the actual diff and changed files yourself; never accept a task from the specialist's summary alone.
2. Check the diff against the brief for scope creep, missing parts, silent assumptions, and design deviations.
3. Check for edge cases, unhandled error paths, broken invariants, and regressions in neighboring code.
4. Re-run the exact verification commands yourself to confirm they pass on the current tree.
5. Choose one outcome per task:
   - **Accept**: the diff matches the brief, edge cases hold, and verification passes.
   - **Return**: send the task back to the specialist (or step up one tier) with a precise defect list and file and line references, not a re-explanation of the task.
   - **Take over**: edit directly only for a one-line fix where a return round would cost more than the edit.
6. Cap return rounds at two per task. After two failed return rounds, stop returning the task and either re-plan or ask the user.

### Close

Once all tasks are accepted, report concisely to the user:
- What changed and where (file paths and targets).
- What was verified and how (commands and results).
- What was left out and why.
- One line listing which specialists and tiers ran.

## 4. Choosing a tier (token rules)

- Tiers in the roster table are `lead`, `core`, and `fast`.
- Start each task at the cheapest tier that can plausibly do it right the first time:
  - `fast`: read-only searches, log triage, running test or lint targets, CI watching, and mechanical checks.
  - `core`: standard feature work, bug fixes with a known cause, tests, build files, docs, and scoped refactors.
  - `lead`: complex cross-domain architecture, subtle concurrency or state bugs that survived a `core` pass, and high-risk changes.
- Step up one tier (`fast` to `core`, or `core` to `lead`) only after a failed review.
- **Exception**: when a wrong first attempt is expensive (production, security, secret management, or data migration), start one tier higher on the first run.
- **Never use low effort**, in any form, ever. If only low effort is offered, stop immediately and say so.
- Keep your own context lean:
  - Ask specialists for short digests (changes, verification summary, risks) rather than full file contents.
  - Never re-read files a specialist already read unless inspecting a diff during review.
  - Never paste raw tool output or long logs back into the main thread.

## 5. Fallback

- If a model or harness is out of quota or failing:
  1. Retry once on the same tier in another harness where the brief allows: from Claude Code or OpenCode with `agy-delegate`, from Antigravity with a headless `claude -p` run as `beacon` describes.
  2. Otherwise, step one tier down on the same harness (`lead` to `core`, or `core` to `fast`).
- Never drop below standard (`medium`) effort. If no model at standard effort or above is available, stop and tell the user.

## 6. How to dispatch

- Dispatch a specialist with the `Agent` tool:
  - `subagent_type`: the specialist's name from the roster table.
  - `model`: the tier's model from the roster table (`opus`, `sonnet`, or `haiku`).
  - `effort`: the tier's effort from the roster table.
  - `description`: the task title (used by the panel to match the run to the planned task).
  - `prompt`: the self-contained task brief.
  - `run_in_background`: set `true` for long work; you are notified on finish.
- Follow up or answer a specialist's question with `SendMessage` to the agent's id. Each follow-up with defect feedback counts as a return round.
- Specialists may start their own subagents (verified), but prefer the lead doing all dispatch so the task board and spend stay in one place.
- Send bulk work off Claude tokens: route mass scaffolding, exhaustive test generation, migrations, and long reads that return a short digest to Antigravity with `agy-delegate`:
  - Hard work: `agy-delegate -m gemini-4-argon-high -d <repo> --digest "<brief>"`
  - Mechanical work: `agy-delegate -m gemini-3.8-flash-high -d <repo> --digest "<brief>"`
  - Never use `flash-lo` or any `-low` model.
  - It edits files only with `--mode accept-edits` (file edits) or `--yolo` (edits plus commands). Without one of them a write task "succeeds" without writing anything.
  - Verify its work yourself (read the diff and run verification): it has been seen faking passes.

## 7. Report progress to the live panel

The vitruvian-orchestrator panel shows the plan, a burn-down, each specialist's run and the spend. It
only knows what you tell it, so keep it current. If the tool is not available, skip this silently.

- Call the `mcp__vitruvian-orchestrator__progress`:
  - right after you show the plan: `title`, `phase: "delegate"` (or `"design"`), and `tasks` as
    `[{ title, specialist, tier, after }]` in plan order, `after` holding task numbers;
  - on every phase change: `phase`;
  - after each review outcome: `accept: <task number>` or `return: <task number>`;
  - when the plan changes: the full new `tasks` list;
  - once at the end: `finished: true`.
- Use each task's title, unchanged, as the run's label when you dispatch it (see "How to dispatch"): the
  panel matches runs to tasks by it.
- Tell each specialist in its brief: "Report your own progress with the `mcp__vitruvian-orchestrator__step`: `done`, `total`,
  and a short `note`, after each step."
- Run `/orchestrator` to open or close the panel; it also opens by itself on the first plan.
