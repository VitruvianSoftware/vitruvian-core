# Vitruvian Code: live agent connections (ACP and the Claude Agent SDK)

*   **Author:** James Nguyen (drafted with Claude)
*   **Status:** Proposed
*   **Date:** 2026-11-11

--------------------------------------------------------------------------------

## Overview

Vitruvian Code (formerly Nexus Agent, `apps/desktop/vitruvian-code/`) is a
macOS app that runs coding agents such as Claude Code and Antigravity (agy).
It ships in two forms:

*   **The standalone app.**
*   **The Vitruvian extension:** the same code, installed through the Vitruvian
    desktop app's extension catalog.

You chat with an agent in the **notch chat**, a panel that drops from the
MacBook notch. You can also pop the chat out into its own window. The app
also runs agents unattended:

*   **Worktree runs:** an agent works in its own git worktree, or several
    agents race on the same task.
*   **Automation runs:** an agent runs on a schedule or a trigger.

Today the app starts a new command-line process for every prompt and reads its
output. Each agent prints in its own format, so the app has one reader per
agent.

This design keeps one connection open for the whole chat instead:

*   **agy** connects through the [Agent Client Protocol](https://agentclientprotocol.com)
    (ACP). ACP is a shared standard for apps to talk to coding agents. The app
    starts it with `agy acp`.
*   **Claude** connects through Anthropic's [Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview)
    by default. The SDK runs in a helper process on Node that ships inside the
    app. It uses the login the user already has in Claude Code. Two other
    Claude connections stay selectable: the `@agentclientprotocol/claude-agent-acp`
    adapter, and today's command line.
*   **Other agents that support ACP** connect through one shared ACP path. The
    [ACP registry](https://agentclientprotocol.com/get-started/agents) lists
    which agents exist.

**T3 Code is the reference design.** [T3 Code](https://github.com/pingdotgg/t3code)
is an open-source desktop app (Electron) that drives many coding agents over
these same connections. Where T3 Code has already answered a question, this
design copies its answer.

**Terms used below:**

*   **Command-line connection:** today's way of running an agent. The app runs
    one command per prompt and reads its output. The command comes from an
    editable **command template** in settings.
*   **Transcript readers:** the code that reads agy's and Claude's saved session
    files, for session history.
*   **Transcript follower:** the part of the readers that watches a running
    session's files and turns them into chat events.
*   **YOLO:** today's name for the mode that skips all approvals. It is the
    default.

T3 Code file paths below are relative to its repository root, at commit
`d6e5f2e0` (read on 2026-11-11).

## The Problem

What the app cannot do today depends on the agent.

**Claude** runs through the **command-line connection**. The app runs
`claude -p` once per prompt.

*   **Approvals already work, except in YOLO.** In the standard and
    accept-edits modes, the app answers Claude's approval requests mid-turn
    and shows them in `VitruvianCodeApprovalCardView`. To do that it starts
    Claude with `--input-format stream-json --permission-prompt-tool stdio`
    (`VitruvianCodeSupport.swift`). YOLO skips approvals.
*   **One process per prompt.** Each turn starts Claude again and reloads the
    session from disk.
*   **Stopping kills the process.** There is no clean "stop this turn".
*   **No changes mid-chat.** The user can't switch the model or the thinking
    level while chatting.
*   **Events are guessed.** Tool steps, plans and subagents are read out of the
    printed output.

**agy** has larger gaps:

*   **It can't ask anything mid-turn.** The app passes flags by mode
    (`VitruvianCodeApprovalMode.agyArguments`): `--dangerously-skip-permissions`
    for YOLO, `--mode accept-edits`, `--mode plan`, or nothing for standard.
    The default command templates hard-code the YOLO flag. Either way, agy
    can't ask the user to approve an action or answer a question while it
    works.
*   **Events come from transcripts.** Subagents and turn results are inferred
    from agy's transcript files. The stuck subagent list fixed in
    [PR #4538](https://github.com/VitruvianSoftware/vitruvian-core/pull/4538)
    was caused by this: the app had to work out from transcript text that
    subagents had been killed.

**Every agent** needs its own output reader in
`VitruvianCodeFleetAndCatalog.swift` and `VitruvianCodeSupport.swift`. That
covers Claude stream-json, agy, Codex JSONL, Gemini, Qwen, Amp, Cursor and
OpenCode. A new agent, or a format change in an existing one, means new
parsing code and new tests.

For sessions the app starts, ACP and the Agent SDK replace this text parsing
with typed events: text, tool call, plan, approval request, turn finished. They
keep the connection open, so the app can answer the agent while it works.
Sessions started elsewhere still need the transcript readers.

## Goals

*   **A live connection per chat.** agy uses ACP and Claude uses the Agent SDK
    by default. That means one process for the conversation, not one per
    prompt.
*   **Answer the agent mid-turn, for every agent.** The user can:
    *   approve or deny an action;
    *   answer a question;
    *   stop a turn without ending the session.
*   **Approval modes, per chat, as in T3 Code:**
    *   full access (the default);
    *   auto-accept edits;
    *   approval required;
    *   auto, only where the agent has a distinct auto mode.

    A separate **plan** switch sits beside the mode. Today's settings carry
    over (Technical Plan, section 8).
*   **Claude keeps working on the user's existing Claude Code login,** with no
    API key needed. An API key or another endpoint is optional. It's set
    through a Claude config folder and environment variables, as in T3 Code.
*   **Three Claude connections the user can pick from:**
    *   the Agent SDK (default);
    *   the `@agentclientprotocol/claude-agent-acp` adapter;
    *   the command line.
*   **One ACP path for every other ACP agent,** so adding an agent from the ACP
    registry needs no new parsing code.
*   **Each agent gets exactly the ACP features T3 Code enables for it,** listed
    in "What ACP gives us".
*   **No loss of what works today:**
    *   following outside sessions and saved session history;
    *   the subagent list, the timeline and the diff review;
    *   worktree and automation runs;
    *   the notch chat;
    *   plan mode;
    *   the Telegram bot's shared approval setting.
*   **Clear failure handling.** If a live connection fails to start, the chat
    shows the error with **Retry** and **Use command line for this chat**, as
    T3 Code shows the error. It never switches on its own (Technical Plan,
    section 5).

## Non-Goals

*   **Gemini CLI.** It's deprecated in favour of agy. It gets no live
    connection, and its current support isn't extended.
*   **Removing the transcript readers.** They stay the way the app follows
    sessions it didn't start.
*   **Removing the command-line connection.** It stays as a per-agent option
    and as the user's choice when a live connection fails.
*   **Following sessions started outside the app over ACP or the SDK.** Those
    only cover sessions the app starts. Sessions run in a terminal, and saved
    history, still come from the transcript readers.
*   **Codex's own app-server protocol.** T3 Code uses it for Codex, but Codex
    isn't one of the app's supported agents today. If Codex supports ACP, it
    uses the shared ACP path.
*   **Signing users in to Claude.** The app never handles Claude credentials.
    Sign-in stays in Claude Code's own `claude auth login`.
*   **Anthropic approval for subscription use.** This work doesn't seek it
    (see Risks & Mitigations).
*   **Mobile, remote or multi-machine use** of these connections.

## What ACP gives us

The point is to use what a live connection makes possible, not to swap one way
of running agents for another. Each row is something the app either can't do
today, or does only for one agent, or by hand.

**How to read the table:**

*   **The agy, Claude (SDK) and Claude (ACP adapter) columns** say what that
    connection gets. Detail lives in the Technical Plan section named in the cell.
*   **Registry agents** get every ACP feature they advertise, under the client
    policy in Technical Plan, section 2.
*   **A feature is used only when** the agent advertises it in `initialize` and
    the per-agent client policy offers it. The UI hides any control an agent
    doesn't support.
*   **Sources:** the agy column follows T3 Code's
    `apps/server/src/provider/acp/AntigravityAcpSupport.ts`. The Claude (SDK)
    column follows what `apps/server/src/orchestration-v2/Adapters/ClaudeAdapterV2.ts`
    imports and calls. The Claude (ACP adapter) column follows
    `packages/provider-acp-registry/src/server/claudeAcp.ts`.

| What the user gets | ACP feature | agy (ACP) | Claude (SDK) | Claude (ACP adapter) | Today |
|---|---|---|---|---|---|
| **Stop a turn** and keep the session | `session/cancel` | Yes | `interrupt()` | Yes | Kills the process |
| **Approve or deny one action** mid-turn | `session/request_permission` | Yes, new | `canUseTool` | Yes | Claude only, outside YOLO |
| **Answer an agent's question** in a form | `elicitation/create` | Yes; agy sends questions inside `request_permission` (section 2) | `AskUserQuestion`; `onElicitation` for MCP servers | Yes | Claude only |
| **Approval mode per chat**, plus a plan switch | Session config option | The app decides (section 8) | `permissionMode`, `setPermissionMode()` | Yes | One global setting |
| **Pick model, thinking level and other settings** from the agent's live list | `configOptions`, `session/set_config_option` | Yes (section 2, version gates) | `setModel()`, effort and thinking | Yes | Hard-coded in settings |
| **The agent's own slash commands**, kept current | `available_commands_update` | Yes | Skills and commands read from disk (T3 Code `ClaudeSkills.ts`) | Yes | From Claude's output; hand-kept for others |
| **Live plan** with step status | `plan` updates | Yes | TodoWrite events; the helper sets `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` | Yes | Guessed from text |
| **Tool cards:** kind, status, clickable file locations | `tool_call`, `tool_call_update`, `locations` | Yes | Tool use and result messages | Yes | Parsed per agent |
| **Diffs as the agent edits** | Tool content `diff` | Yes, from agy's own edits | Edit and Write tool inputs | Yes | Parsed after the fact |
| **App-hosted terminals** with a Stop button per command | `terminal/*` | Not offered (section 2) | Not used: Claude runs its own commands | Not offered | No |
| **Agent reads and writes files through the app** | `fs/read_text_file`, `fs/write_text_file` | Reads on some releases; no writes (section 2) | Not used | Not offered | No |
| **Attach images and files**; @-mention embeds a file | Prompt content `image`, `resource`, `resource_link` | Where agy advertises them | Image and document content | Yes | Claude only |
| **Context-window meter and cost** | `usage_update` | Where agy reports it (section 2) | Usage in result messages | Yes | Parsed per agent |
| **Usage-limit wait:** when a plan limit is hit, wait for the reset and resume | — | — | Rate-limit messages (T3 Code `claudeUsageLimits.ts`) | — | No |
| **Compaction** as it happens, an "auto-compact after" threshold, and a Compact/Keep chip on idle chats | `compaction_update` | Not supported by agy | Compact messages and settings (T3 Code `docs/user/providers-claude.md`) | Where offered | Not shown |
| **Agent notices** as banners | `notice` | Yes | System and status messages | Yes | Not shown |
| **Subagents from typed events** | — | Start from child-work reports, finish at end of turn (section 2) | Task and subagent messages | `subagent_update` and `session_message`, with child session IDs | Inferred from transcripts |
| **Session history from the agent:** list, reopen without replay, close, live titles, fork | `session/list`, `session/resume`, `session/load`, `session/close`, `session_info_update` | Yes, plus the session-log watch (section 2) | `resume`, `forkSession`, `getSessionMessages` | Yes | Transcript files; fork through `--fork` |
| **The user's MCP servers** for any agent | `mcpServers` on `session/new` | Yes | `mcpServers`, `mcpServerStatus()` | Yes | Each agent set up separately |
| **Extra folders** in a chat's workspace | `additionalDirectories` | Yes | `additionalDirectories` | Yes | No |
| **App instructions added to the system prompt** (for example, how to link PRs) | `systemPrompt` (append) | Only on agy releases that support it (section 2) | `systemPrompt` with append | Yes | No |
| **Sign in to an agent from the app** | `authMethods`, `authenticate` | Yes (`oauth-personal`, section 5) | Claude Code's own login | Claude Code's own login | Done in a terminal |
| **New agents with no new code** | ACP registry | — | — | — | One parser per agent |

### Limited or not used, and why

*   **Session modes** (`session/set_mode`): ACP has deprecated them in favour
    of config options. They're read only for agents that offer modes and no
    config options.
*   **SSE MCP transport:** deprecated by the MCP spec. The app uses stdio and
    HTTP.
*   **Audio prompts:** sent only if an agent advertises
    `promptCapabilities.audio`. None of the target agents do today.
*   **ACP v2 draft and open proposals** (session fork, subagent sessions and
    others): not stable yet. The app adopts them once they're stable, as T3
    Code does.

## Technical Plan (Architecture)

### 0. What changes, in one picture

```mermaid
flowchart LR
    UI["Chat UI<br>(notch, popped-out window, worktree and automation runs)"] --> S["Session<br>(VitruvianCodeQuickPromptSession)"]
    S --> C{"Agent connection<br>(one per open chat)"}
    C -->|agy| A["ACP client"] -->|"stdio: agy acp"| AGY["agy"]
    C -->|registry agent| A2["ACP client"] -->|"stdio: registry command"| REG["OpenCode, Cursor, Kiro, Pi, ..."]
    C -->|"Claude: SDK (default)"| H["Claude helper<br>(bundled Node + Agent SDK)"] -->|"spawns user's claude"| CL["claude"]
    C -->|"Claude: ACP adapter<br>(installed from the registry)"| A3["ACP client"] -->|"stdio: claude-agent-acp"| CL
    C -->|"Command-line connection<br>(per-agent option)"| L["Today's per-prompt runner"]
    L -->|"claude -p"| CL
    L -->|"agy -p"| AGY
    T["Transcript readers (unchanged)"] --> S
```

Every connection turns what its agent sends into the same set of events,
listed in section 1. The session and the UI work only with those events, so
they don't depend on which connection is underneath.

### 1. One connection interface

A new Swift protocol, `AgentConnection`, lives in `VitruvianCodeCore`. Each open
chat owns one. It can:

*   start or reopen a session;
*   send a prompt;
*   cancel the turn;
*   answer an approval or a question;
*   change a setting;
*   stop.

It sends out one stream of events. The full method list is in Detailed
Implementation, Delivery order, step 1.

**One event type.** The session already reads `VitruvianCodeStreamEvent`
(`VitruvianCodeSupport.swift`). It already covers approvals, tool steps,
context usage, slash commands, thinking and turn finished. That type is
renamed `AgentEvent` and extended. It stays the only event type the session,
the timeline, the subagent list and the diff review read. The per-agent
parsers keep producing it for the command-line connection.

After the extension, `AgentEvent` covers:

*   text chunk;
*   thinking chunk;
*   tool call started, updated or finished (with file paths and diff);
*   plan updated;
*   subagent started or finished;
*   approval requested;
*   question asked;
*   settings list replaced;
*   commands replaced;
*   usage updated;
*   compaction;
*   notice;
*   turn finished (with stop reason);
*   connection failed.

The existing approval card (`VitruvianCodeApprovalCardView`) and the session's
approval handling (`decideApproval`, "allow for this session") serve every
connection.

### 2. ACP client (Swift)

One Swift ACP client serves agy, registry agents and the Claude ACP adapter
option. ACP is JSON-RPC 2.0, with one JSON message per line, over the agent
process's standard input and output. The client:

*   sends `initialize`, then `session/new` to start a session;
*   reopens a session with `session/resume` when the agent offers it, and
    otherwise with `session/load`, which replays the whole history;
*   sends `session/prompt` for each turn and `session/cancel` to stop;
*   turns `session/update` notifications into `AgentEvent`s;
*   answers `session/request_permission` either itself (section 8) or through
    the approval card;
*   implements the other features in "What ACP gives us".

**Client policy per agent.** What the app offers an agent (file reads and
writes, terminals, forms) is set per agent. It copies T3 Code's settings in
`packages/provider-acp/src/server/AcpSessionRuntime.ts` (off by default) and
in each agent's support file (on where T3 Code turns it on). For agy, T3 Code's
`apps/server/src/provider/acp/AntigravityAcpSupport.ts` sets three things:

*   **No file writes.** Offering writes makes agy send whole-file writes
    instead of its own diff edits.
*   **No terminals.**
*   **File reads only for older agy releases.** T3 Code serves reads only to
    agy releases it hasn't marked as "qualified" (`isQualifiedAntigravityRelease`,
    currently 1.4.5). Qualified releases read files themselves.

**agy layer.** agy-specific behaviour sits in a layer on top of the client,
copied from T3 Code's `apps/server/src/provider/acp/Antigravity*.ts`. It covers:

*   sign-in through `oauth-personal`, started as soon as the session opens
    (section 5);
*   reopening with `session/resume`;
*   a cancel that waits for the prompt's result;
*   **child-work reports.** These are agy's messages saying it started work in
    a child agent. The app turns them into subagent-started events. A subagent
    is marked finished when the turn ends, as T3 Code does. agy reports no
    child session IDs, so the subagent rules from PR #4538 stay;
*   questions, which agy sends inside `request_permission`, not as
    `elicitation/create`;
*   **the session-log watch.** The app reads agy's own session log files, as
    T3 Code's `AntigravitySessionFiles.ts` does, only to learn whether a turn
    ended on an upstream error. It sends no chat events, so nothing is shown
    twice;
*   **a silent-prompt timeout.** A prompt that sends nothing for a long time
    is stopped and marked failed. The timer pauses while a tool runs or an
    approval waits (T3 Code `promptInactivityTimeout`).

**agy version rules.** The layer reads agy's version from `initialize` and
applies T3 Code's per-release rules and timeouts from `AntigravityAcpSupport.ts`
and `AntigravityAdapterV2.ts`. Those cover which models are listed, whether
the system prompt can be appended, whether per-turn usage is reported, read
repair, and the attachments folder. The values live in code and tests, not in
this design, because they follow T3 Code. One rule is named because the user
would notice it: on the agy releases T3 Code lists, the `run_workflow` tool is
disabled. Otherwise it writes a skills file into the user's repository.

**Registry agents.** Registry agents use the same client. Some need a small
per-agent file of quirks. T3 Code keeps these in
`packages/provider-acp-registry/src/server/` (for example `claudeAcp.ts` and
`copilotAcp.ts`), and the app does the same. The registry lists the agents.
Installing follows T3 Code's
`packages/provider-acp-registry/src/server/AcpRegistrySupport.ts`, `driver.ts`
and `probe.ts`:

*   a package installs only when the user adds that agent in settings;
*   it must name an exact version, and it installs into a folder the app
    manages. npm packages use the bundled Node. uv packages need the user's
    own `uv`; without it, the agent is listed as needing `uv`;
*   it updates only when the user picks a new version;
*   an install that takes more than 20 minutes is stopped;
*   the user's MCP servers are passed to a registry agent only after the user
    turns that on for that agent.

OpenCode uses this path when its ACP mode is available. So does the Claude
ACP adapter (section 4).

### 3. Claude helper (bundled Node + Agent SDK)

The helper is a Node program shipped inside the app. The app starts it with
the bundled Node and talks to it over standard input and output, one JSON
message per line. The messages are a written contract: a JSON Schema file
that both sides test against. The helper:

*   calls the Agent SDK's `query()` with `pathToClaudeCodeExecutable` set to
    the user's own `claude`, so Claude Code's own login and settings apply;
*   passes through an optional `CLAUDE_CONFIG_DIR` and extra environment
    variables (for an API key or another endpoint), as T3 Code's Claude
    instances do (`docs/user/providers-claude.md`);
*   forwards each SDK permission check (`canUseTool`) to the app;
*   reopens a saved conversation with the SDK's `resume` option;
*   takes MCP server secrets over standard input, never as process arguments
    or environment variables, as T3 Code does;
*   sets `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, so Claude's task list (the live
    plan) appears, as T3 Code's docs require.

**Credentials.** The app never handles Claude *login* credentials. Sign-in
stays in `claude auth login`. Optional API keys or tokens that the user enters
as environment values are marked sensitive. The app stores them in the macOS
Keychain, shows them masked, and passes them only into the helper's own
environment.

**Ollama (claude)** is today's setting that runs Claude Code against a local
Ollama server. It uses this same connection, with Ollama's address set through
environment variables, which is how T3 Code points Claude at another endpoint.

**Version check.** At start-up the app runs `claude --version`. It hides
models that version doesn't support and asks the user to upgrade when it is
too old, as T3 Code's `apps/server/src/provider/ClaudeProvider.ts` does.

### 4. Claude through the ACP adapter (option)

The adapter, `@agentclientprotocol/claude-agent-acp`, is installed through
the registry path in section 2 when the user picks it, as T3 Code does. It
isn't shipped inside the app. The app talks to it with the ACP client from
section 2, the same way it talks to agy. It drives
the user's own `claude`, so it uses the same login. Its quirks (Agent and Task
subagents, background subagents, `subagent_update` and `session_message`) live
in one file, copied from T3 Code's
`packages/provider-acp-registry/src/server/claudeAcp.ts`.

### 5. Command-line connection, and when a live connection fails

Today's per-prompt runner, including Claude's stream-json approval path, is
wrapped as an `AgentConnection`. How it works doesn't change. It's used when
the user picks it for an agent, and for agents with no live connection.

**When a live connection fails to start,** the chat shows the error with
**Retry** and **Use command line for this chat**, as T3 Code shows the error.
The app never switches on its own. The user's choice applies to that chat
only. The command line then uses the chat's approval mode with today's flags.
A crash after the session started is handled by section 7.

**Sign-in.** If the agent needs the user to sign in, the chat shows the
sign-in link (`onAuthorizationUrl`) and waits, as T3 Code does. That isn't a
failure.

### 6. Bundled Node and helper packaging

T3 Code runs its server on Electron's own built-in Node
(`apps/desktop/src/backend/DesktopBackendConfiguration.ts`, `ELECTRON_RUN_AS_NODE`).
This Swift app has no built-in Node, so the equivalent is to ship one Node
binary for each architecture (arm64 and x86_64). Bazel builds and signs it
with the app. Alongside it go the helper's JavaScript and its locked
dependency, `@anthropic-ai/claude-agent-sdk`. The costs are listed in Risks &
Mitigations.

The optional Telegram bot keeps using the user's own Node, as it does today.

### 7. Session lifecycle

*   **One connection per open chat.** Opening a chat starts its connection.
    Closing the chat or quitting the app stops it. A notch chat counts as open
    while its session is loaded, even when the panel is hidden.
*   **Process groups.** Each connection owns its process group. `stop()` ends
    the whole group: the helper, `claude`, subagents and MCP servers. It allows
    a grace period, then forces the kill, as T3 Code's `AcpSessionRuntime.ts`
    does.
*   **Idle shutdown.** An idle chat stops its connection and reopens the
    session on the next prompt, using T3 Code's idle limits
    (`apps/server/src/orchestration-v2/ProviderSessionManager.ts`). Like T3
    Code, there is no cap on how many chats can be live at once.
*   **Resource estimate.** A Claude chat on the SDK adds the Node helper to
    the user's `claude` process. As a planning estimate, not a measurement,
    that's roughly 60–100 MB per chat. The real figure is measured in Detailed
    Implementation, Delivery order, step 2.
*   **Crash recovery.** If the process exits during a session:
    *   a turn that was running ends as "interrupted";
    *   pending approvals are cancelled;
    *   the next prompt restarts the process and reopens the session
        (`session/resume` for agy, SDK `resume` for Claude);
    *   a helper crash and a `claude` crash are reported separately;
    *   after 3 failed restarts in a row, the chat shows the error.
*   **No duplicate events.** For chats the app started, the transcript
    follower is off, and the UI uses the connection's events.
*   **Worktree mode.** The app creates the worktree itself
    (`VitruvianCodeWorktreeEngine`) and starts the connection inside it. On the
    live connections this replaces Claude's `-w` flag.

### 8. Approvals

Each chat has an approval mode and a separate plan switch, as in T3 Code
(`packages/contracts/src/providerPolicy.ts`; plan is its own
`interactionMode` in `ClaudeAdapterV2.ts`).

| Mode | Behaviour | Claude (SDK) | agy (ACP), decided by the app |
|---|---|---|---|
| **Full access** (default) | No approvals | `bypassPermissions` | Allow every request |
| **Auto-accept edits** | Edits go through; everything else asks | `acceptEdits` | Allow edit, delete and move; ask about the rest |
| **Approval required** | Guarded actions ask | `default` | Allow reads, searches and thinking; ask about the rest |
| **Auto** (Claude only) | Claude decides for itself what is safe to run | `auto` | Hidden: agy has no separate auto mode |
| **Plan switch** | The agent plans and doesn't act | `plan` | agy's `plan` mode, passed through |

The agy column is T3 Code's client policy
(`packages/provider-acp/src/server/clientPolicy.ts`: "Reads never ask"; edit,
delete and move count as edits).

**How agy runs.** The app never asks agy for its `yolo` or `auto_edit` modes
and never starts it with `--dangerously-skip-permissions`. agy stays in its
`default` mode (or `plan` when the plan switch is on), and the app answers each
request by the table above. T3 Code does the same, because the agy CLI rejects
those two modes (`antigravityCliSessionMode` in `AntigravityAcpSupport.ts`).
This has two benefits:

*   every action is visible to the app;
*   a mode change takes effect on the next turn, with no restart.

The command-line connection keeps today's flags.

**Today's settings carry over:**

| Today (`VitruvianCodeApprovalMode`) | New mode |
|---|---|
| `yolo` | Full access |
| `acceptEdits` | Auto-accept edits |
| `standard` | Approval required |
| `plan` | Approval required, with the plan switch on |

**Who owns the setting.** Each chat has its own mode, as T3 Code has one per
thread. New chats start from the global default. That default stays in
`.env` (`AGY_APPROVAL_MODE`), and the Telegram bot keeps reading it
unchanged. "Auto" can be chosen per chat but not as the global default, so the
bot's four values stay as they are.

**When full access is blocked.** Claude can still ask in full access:

*   some safety checks and settings rules always ask;
*   Claude's settings can switch bypass off (`disableBypassPermissionsMode`);
*   Claude refuses bypass when running as root.

If bypass is switched off, the app uses auto-accept edits, or approval
required if that is also blocked, and shows a notice, as T3 Code does.

**Unattended runs** (worktree and automation runs). An approval request
raises a system notification and waits for the user, as in T3 Code. Nothing
is denied automatically. A prompt that goes silent is caught by the agy
silent-prompt timeout (section 2).

### 9. Settings

The provider settings gain a **Connection** choice per agent:

*   **agy:** ACP (default) or command line.
*   **Claude:** Agent SDK (default), ACP adapter or command line, plus an
    optional Claude config folder and environment variables.
*   **Ollama (claude):** Agent SDK, with Ollama's endpoint.
*   **OpenCode and registry agents:** ACP when available, otherwise command
    line.

**MCP servers.** The app keeps its own MCP server list. On first use it
imports the user's Claude Code MCP configuration. The editable command
templates stay for the command-line connection.

## Alternatives Considered

### Keep today's per-prompt method and improve the parsers

Keep one process per prompt and keep fixing each agent's reader.

*   **Rejected because** it fixes none of the main problems. agy still can't
    ask for approval. No agent can be stopped cleanly or changed mid-chat. The
    app still guesses events such as killed subagents from text (PR #4538).
    Every new agent still needs a new reader.

### ACP for every agent, Claude included, with no other path

Run every agent through ACP. Claude would go only through the
`claude-agent-acp` adapter, and the command templates would go away.

*   **Rejected because** Claude has no built-in ACP mode, so it would depend on
    one third-party adapter keeping up with Claude Code. Dropping the command
    templates would also break any agent without ACP. T3 Code doesn't do this
    either: it uses the Agent SDK for Claude and its own server protocol for
    Codex. The adapter stays as an option.

### Only agents with built-in ACP; Claude stays on the command line

Move agy to ACP and keep Claude on `claude -p`.

*   **Rejected because** Claude is one of the app's two main agents. On the
    command line it keeps one process per prompt, has no clean stop and no
    settings changes mid-chat, and its events are still guessed. The
    command-line connection stays as an option, not as Claude's only path.

### Keep Claude's stream-json path from Swift as the default

Make today's Claude path, the two-way stream-json mode with
`--permission-prompt-tool stdio`, the main Claude connection, and skip the SDK
and Node.

*   **Rejected because** it's still one process per prompt, and the
    stream-json control protocol isn't Anthropic's documented interface. The
    Agent SDK is the documented one, and it drives that protocol for you. This
    path also departs from T3 Code, which uses the SDK. This path stays as the
    command-line option and the fallback.

### Use the user's own Node for the helper

Reuse the app's existing Node lookup (`VitruvianCodeSupport.locateNode`:
Homebrew, the official installer, `~/.local/bin`), as the Telegram bot does,
and fall back to the command line when no Node is found.

*   **Rejected because** macOS ships no Node, so the default Claude connection
    would quietly not work for anyone who hasn't installed Node. T3 Code never
    relies on the user's Node on macOS.

### Compile the helper into one standalone program

Build the helper with Node's single-executable feature or Bun's compiler.

*   **Rejected because (for now):**
    *   the Agent SDK and the ACP adapter load files at run time that these
        compilers may miss;
    *   it needs new Bazel toolchain work;
    *   shipping Node next to plain JavaScript avoids both.

    T3 Code does use a single program for its WSL runtime. If the size and
    signing costs of bundled Node (see Risks) prove too high, this is the
    fallback option.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Anthropic's terms for the SDK default.** [Anthropic's Agent SDK page](https://code.claude.com/docs/en/agent-sdk/overview) says third-party products should not "offer claude.ai login … including agents built on the Claude Agent SDK". The [legal page](https://code.claude.com/docs/en/legal-and-compliance) allows a user's own subscription in the unmodified `claude` when sign-in goes through Anthropic's own flow. | Accepted. T3 Code ships the SDK on the user's own login, and this design does the same: the app never handles credentials. If Anthropic objects, the command-line connection stays available. |
| **Unattended runs waiting** on an approval nobody sees. | A system notification, as in T3 Code; the run shows it is waiting. A silent agy prompt is stopped after 15 minutes (Technical Plan, sections 2 and 8). |
| **Many live processes.** Each live chat holds a helper, `claude`, subagents and MCP servers, and worktree races multiply that. | Process-group shutdown and T3 Code's idle limits (section 7). Memory is measured in Detailed Implementation, Delivery order, step 2. |
| **A failed live connection hiding a weaker mode.** | The app never switches to the command line on its own; the user chooses it per chat (Technical Plan, section 5). |
| **An agent acting with full access**, the default, as in T3 Code. | App file writes and terminals are offered only where T3 Code offers them, and only inside the session's folders. agy's approvals pass through the app, so every action is visible. |
| **agy writing a file into the user's repository** (`run_workflow` on agy 1.4.2–1.4.5). | The agy version gates disable that tool (section 2). |
| **API keys entered in the app.** | Stored in the macOS Keychain, shown masked, passed only to the helper's environment (section 3). |
| **Registry agents run third-party code** with the user's rights. | Installed only when the user adds them, at an exact version, into an app-managed folder; MCP servers only with the user's consent (section 2). |
| **Bundled Node costs:** larger bundle, signing, and patching. | One Node binary per architecture, signed with the app. It needs the entitlements that let Node's JIT compiler run under Apple's hardened runtime. Node is pinned in `//:.nvmrc` and updated with the repo's dependencies. Size is measured in Detailed Implementation, Delivery order, step 3. A single-program helper is the fallback (see Alternatives). |
| **The user's `claude` too old for the SDK or a model.** | The version check in section 3, as in T3 Code's `ClaudeProvider.ts`. |
| **agy behaving differently over ACP than T3 Code expects.** | Recorded replay tests from a real `agy acp` session (Detailed Implementation, Delivery order, step 2), and the checks in Facts to verify. |

## Facts to verify

These don't need a decision. They're checked during implementation.

*   **Whether `agy acp` still writes agy's transcript files.** T3 Code reads
    agy's session logs (`AntigravitySessionFiles.ts`), so this design expects
    them. The first change in Detailed Implementation, Delivery order, step 2 confirms it.
*   **Memory per live connection,** measured in Detailed Implementation, Delivery order, step 2, and recorded here.

## Decisions

Settled with the owner while drafting. For anything not listed here, the rule
is: where T3 Code has solved the same question, copy T3 Code.

| Question | Decision | T3 Code reference |
|---|---|---|
| Scope | Live connections wherever the agent supports them; the command line for the rest | Per-provider adapters plus one ACP registry adapter |
| agy | ACP, started with `agy acp` in `default` mode; the app answers approvals itself | `apps/server/src/orchestration-v2/Adapters/AntigravityAdapterV2.ts`, `apps/server/src/provider/acp/AntigravityAcpSupport.ts` |
| Claude default | Claude Agent SDK on the user's existing Claude Code login; API key optional | `ClaudeAdapterV2.ts`, `docs/user/providers-claude.md` |
| Claude options | Also selectable: `@agentclientprotocol/claude-agent-acp` (installed from the registry), and the command line | `packages/provider-acp-registry/src/server/claudeAcp.ts` |
| When a live connection fails | Show the error with Retry and "Use command line for this chat"; never switch automatically | T3 Code shows the error; it has no automatic fallback |
| Other ACP agents | One shared ACP connection, using the ACP registry | `packages/provider-acp-registry/src/server/AcpRegistrySupport.ts`, `driver.ts`, `probe.ts` |
| Node for the helper | Node ships inside the app; users never install Node | T3 Code reuses Electron's own Node (`apps/desktop/src/backend/DesktopBackendConfiguration.ts`) |
| Approval modes | Per chat: full access (default), auto-accept edits, approval required, auto where offered, and a plan switch | `DEFAULT_RUNTIME_MODE = "full-access"` (`packages/contracts/src/providerPolicy.ts`) |
| Client features per agent | Off by default, on where T3 Code turns them on; agy gets no writes and no terminals | `AcpSessionRuntime.ts`, `AntigravityAcpSupport.ts` |
| Reopening agy sessions | `session/resume`, not `session/load` (load replays every tool call) | `resumeMethod: "resume"` in `AntigravityAcpSupport.ts` |
| Claude terms risk | Accepted; see Risks & Mitigations | `docs/user/providers-claude.md` |
| Gemini CLI | Out of scope (deprecated in favour of agy) | — |

## References

*   T3 Code: <https://github.com/pingdotgg/t3code>, commit `d6e5f2e06faf45eb46ee5999ab1363daaea4e1c2`
*   Agent Client Protocol, v1: <https://agentclientprotocol.com/protocol/overview>
*   ACP registry: <https://agentclientprotocol.com/get-started/agents>
*   Claude Agent SDK: <https://code.claude.com/docs/en/agent-sdk/overview>
*   Claude Code legal and compliance: <https://code.claude.com/docs/en/legal-and-compliance>
*   PR #4538 (stuck subagent list): <https://github.com/VitruvianSoftware/vitruvian-core/pull/4538>

## Detailed Implementation

Paths are relative to `apps/desktop/vitruvian-code/` unless they start with
`//`, which means the repository root. This section has no code. It names the
types and the behaviour, so the work can be done without new design decisions.
Where a behaviour follows T3 Code, the T3 Code file named in the Technical Plan
is the reference for what to do. The Swift code is written fresh, not
translated line by line.

### Delivery order

Each step is its own pull request. Each ships behind the per-agent
**Connection** setting, keeps the default unchanged until step 6, and leaves
the app working.

1.  The connection interface and the single event type. Today's runner is
    wrapped behind them, with no change in behaviour.
2.  The Swift ACP client and agy over ACP.
3.  The Claude helper: bundled Node and the Agent SDK.
4.  The chat UI for the new events.
5.  Registry agents (including the Claude ACP adapter and OpenCode), MCP
    servers, extra folders and sign-in.
6.  The defaults switch to agy over ACP and Claude on the Agent SDK. Docs and
    release notes follow.

### Files

#### Step 1: connection interface and one event type

| File | Change | Why |
|---|---|---|
| `macos/Sources/VitruvianCodeCore/AgentConnection.swift` (new) | `protocol AgentConnection`: start or reopen a session (with folder, extra folders, MCP servers and system-prompt text), send a prompt, cancel, answer a request, set a config option, stop, plus an event stream and a capabilities value | One interface for every agent (Technical Plan, section 1) |
| `macos/Sources/VitruvianCodeCore/VitruvianCodeSupport.swift` | `VitruvianCodeStreamEvent` is renamed `AgentEvent` and gains the cases in section 1 (plan, subagent started/finished, question, config options, commands, usage with cost, compaction, notice, session info, connection failed). `VitruvianCodeApprovalMode` gains the new mode names, keeping the four `.env` values | One event type; today's approval values carry over (section 8) |
| `macos/Sources/VitruvianCodeCore/CommandLineConnection.swift` (new) | Wraps today's per-prompt runner, including Claude's stream-json approval path, as an `AgentConnection`. Its behaviour is unchanged | The command-line connection (section 5) |
| `macos/Sources/VitruvianCodeCore/VitruvianCodeQuickPromptSession.swift` | The session talks only to `AgentConnection`, with one per open chat. The transcript follower is off for chats with a live connection. Adds a per-chat approval mode and a plan switch | Lifecycle (section 7); approvals (section 8) |
| `macos/Sources/VitruvianCodeCore/VitruvianCodeEngine.swift` | Process launching for chat turns moves into the connections. Transcript reading stays | The engine stops owning per-prompt launches |
| `macos/Sources/VitruvianCodeCore/VitruvianCodeFleetAndCatalog.swift` | The parsers emit `AgentEvent`. The Gemini CLI entry is marked deprecated, not removed | One event type |
| `macos/Sources/VitruvianCodeCore/VitruvianCodeStoredProviders.swift` | A per-agent `connection` field: `acp`, `claudeSDK`, `claudeACP` or `commandLine`. Saved without a value until step 6, so the step-6 default applies to everyone who never chose | Settings (section 9) |
| `macos/Tests/AgentConnectionTests.swift` (new) | `CommandLineConnection` produces the same events as today for the existing stream fixtures | Proves step 1 changes nothing |
| `macos/Tests/StreamParityTests.swift`, `EngineHostTests.swift`, `BidirectionalApprovalTests.swift`, `PermissionArgumentsTests.swift`, `SharedCasesTests.swift` | Run through `CommandLineConnection`, with the new mode names. `SharedCasesTests` still proves that saving the global mode never changes the bot | Existing coverage keeps guarding the old path |

#### Step 2: ACP client and agy

| File | Change | Why |
|---|---|---|
| `macos/Sources/VitruvianCodeCore/ACP/ACPTransport.swift` (new) | Starts the agent process in its own process group. Newline-delimited JSON-RPC 2.0 over stdin/stdout; request cancellation; stderr goes to the chat's log with secrets redacted | ACP transport; clean shutdown (section 7) |
| `macos/Sources/VitruvianCodeCore/ACP/ACPSchema.swift` (new) | Codable types for the ACP v1 messages listed in "What ACP gives us" | Typed protocol |
| `macos/Sources/VitruvianCodeCore/ACP/ACPConnection.swift` (new) | `AgentConnection` over ACP. Offers client features according to a per-agent `ACPClientPolicy`, which is off by default. Checks the agent's capabilities before each call, and maps updates to `AgentEvent`. Reopens with `session/resume`, falling back to `session/load`. Closes with `session/close` | The shared ACP path (section 2) |
| `macos/Sources/VitruvianCodeCore/ACP/ACPClientPolicy.swift` (new) | Which client features each agent gets (file reads/writes, terminals, forms), copied from T3 Code. For agy: no writes, no terminals, and reads only on older releases. Also decides approvals for each mode and tool kind, following T3 Code's `clientPolicy.ts` | Client policy and approvals (sections 2 and 8) |
| `macos/Sources/VitruvianCodeCore/ACP/ACPClientFiles.swift` (new) | `fs/read_text_file` and `fs/write_text_file`, used only where the policy allows. Refuses paths outside the session's folders | File features, kept inside the workspace |
| `macos/Sources/VitruvianCodeCore/ACP/ACPClientTerminals.swift` (new) | `terminal/*`, used only where the policy allows. `cwd` must be inside the session's folders | App-hosted terminals for agents T3 Code offers them to |
| `macos/Sources/VitruvianCodeCore/ACP/ACPElicitation.swift` (new) | Form-mode questions with validation and defaults. URL mode shows the full address and opens it only after the user agrees | Forms in the chat |
| `macos/Sources/VitruvianCodeCore/ACP/ACPSessionConfig.swift` (new) | Config options (select and boolean, by category) and `set_config_option`. Falls back to session modes only when an agent has no config options | Model, thinking level and other pickers |
| `macos/Sources/VitruvianCodeCore/ACP/AntigravityACP.swift` (new) | The agy layer from section 2:<ul><li>starts `agy acp` and keeps agy in `default` or `plan`, never `yolo` or `auto_edit`;</li><li>signs in eagerly through `oauth-personal` and shows the sign-in link;</li><li>reopens with `session/resume`;</li><li>a cancel waits for the prompt's result;</li><li>child-work reports become subagent events;</li><li>questions arrive inside `request_permission`;</li><li>the session-log watch;</li><li>the silent-prompt timeout;</li><li>T3 Code's per-release rules, including disabling `run_workflow`.</li></ul> | agy behaves as it does in T3 Code |
| `macos/Tests/ACP/ACPTransportTests.swift` (new) | Framing, partial lines, out-of-order responses, cancellation, killing the process group | Transport correctness |
| `macos/Tests/ACP/ACPConnectionTests.swift` (new) | Replay fixtures from a recorded `agy acp` session cover every `AgentEvent` kind agy sends. Unsupported features are hidden. agy is never asked for `yolo` or `auto_edit` | Event mapping and the agy mode rule |
| `macos/Tests/ACP/ACPClientPolicyTests.swift` (new) | Each approval mode against each tool kind matches T3 Code's `clientPolicy.ts`. agy is offered no writes and no terminals. Paths outside the session's folders are refused | Approval and safety rules |
| `macos/Tests/ACP/Fixtures/agy-*.ndjson` (new) | Recorded with the script below | Repeatable tests without a live agent |
| `macos/scripts/record-acp-fixture` (new) | Records an ACP exchange to ndjson, modelled on T3 Code's `apps/server/scripts/record-*-acp-replay-fixture.ts` | Produces the fixtures |

The first change in step 2 checks whether `agy acp` still writes agy's
transcript files, and measures memory per connection. Both answers go into
Facts to verify.

#### Step 3: Claude helper

| File | Change | Why |
|---|---|---|
| `macos/claude-helper/package.json` (new) | Pins `@anthropic-ai/claude-agent-sdk`. Added to the pnpm workspace (`//pnpm-workspace.yaml`, `//pnpm-lock.yaml`) | Locked dependency |
| `macos/claude-helper/protocol.schema.json` (new) | JSON Schema for every message in both directions between the app and the helper | The written contract (section 3) |
| `macos/claude-helper/src/main.ts` (new) | Calls `query()` with the user's `claude` (`pathToClaudeCodeExecutable`), `resume`, `permissionMode`, `canUseTool` (approvals and `AskUserQuestion`), `onElicitation`, `mcpServers`, `additionalDirectories`, system-prompt append and partial messages. Handles interrupt, model and mode changes, MCP status, fork and history. Sets `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`. Reads MCP secrets from stdin. Maps SDK messages to the contract, following T3 Code's `ClaudeAdapterV2.ts` | The default Claude connection |
| `macos/claude-helper/src/skills.ts` (new) | Reads Claude's skills and commands from disk for the slash menu, as T3 Code's `Drivers/ClaudeSkills.ts` does | Claude slash commands |
| `macos/claude-helper/src/usageLimits.ts` (new) | Detects a plan-limit stop and reports the reset time, as T3 Code's `claudeUsageLimits.ts` does | Usage-limit wait |
| `macos/claude-helper/BUILD` (new) | A JavaScript bundle target with aspect_rules_js. The output is the helper's JavaScript plus `node_modules` | Built by Bazel |
| `macos/claude-helper/test/*.test.ts` (new) | Every message validates against `protocol.schema.json`. SDK message mapping is tested from recorded streams. Approval and question round trips | Helper side of the contract |
| `macos/Sources/VitruvianCodeCore/ClaudeSDKConnection.swift` (new) | `AgentConnection` that starts the bundled Node with the helper in its own process group and speaks the contract. Passes `CLAUDE_CONFIG_DIR` and the user's environment values, reading sensitive values from the Keychain. Runs the `claude --version` check | App side of the helper (section 3) |
| `macos/Sources/VitruvianCodeCore/AgentSecretStore.swift` (new, or shared) | Keychain storage for sensitive environment values. Reuse `apps/desktop/home-speaker/Sources/HomeSpeakerCore/SecretStore.swift` if it can be moved to a shared package | API keys never stored in plain text |
| `macos/Sources/VitruvianCodeCore/BundledNode.swift` (new) | Finds the Node runtime and helper inside the app or extension bundle, never the user's Node | Node ships with the app |
| `macos/BUILD` | Adds a pinned Node runtime for arm64 and x86_64 (from the repository's `rules_nodejs` toolchain, pinned by `//:.nvmrc`) and the helper bundle to the app's Resources and to the extension folder. Both are signed with the rest of the bundle, with the entitlements Node needs under the hardened runtime. Records the size added | Packaging and its cost (section 6) |
| `macos/Tests/ClaudeSDKConnectionTests.swift` (new) | Starts the real bundled helper with a fake `claude` that replays a recorded stream. Every message validates against `protocol.schema.json` | App side of the contract, end to end |

#### Step 4: chat UI

| File | Change | Why |
|---|---|---|
| `macos/Sources/VitruvianCodeUI/VitruvianCodeMessageBubble.swift` | `VitruvianCodeApprovalCardView` shows the agent's own options with icons for their kind. It's reused for every connection | Approvals, with no second card |
| `macos/Sources/VitruvianCodeUI/AgentFormCard.swift` (new) | Shows a form question; the user reviews the answers before sending. URL mode asks for consent first | Forms |
| `macos/Sources/VitruvianCodeUI/AgentPlanView.swift` (new) | Live plan with each step's status | Plans |
| `macos/Sources/VitruvianCodeUI/AgentTerminalView.swift` (new) | Live terminal output in a tool card, with a Stop button. Shown only for agents whose policy offers terminals | Terminals |
| `macos/Sources/VitruvianCodeUI/AgentSettingsBar.swift` (new) | Pickers from the agent's live list (model, thinking level, other options), the approval mode, and the plan switch | Settings from the agent; approvals |
| `macos/Sources/VitruvianCodeUI/VitruvianCodeToolStepViews.swift` | Tool cards use the tool's kind, status and clickable locations, and show diffs as they arrive | Tool cards |
| `macos/Sources/VitruvianCodeUI/VitruvianCodeComposerPopovers.swift` | Slash menu from the agent's list. An @-mention embeds the file. Images can be pasted or dropped | Commands and attachments |
| `macos/Sources/VitruvianCodeUI/VitruvianCodeChatView.swift`, `VitruvianCodeChatControls.swift` | Stop uses `cancel()`. Adds a usage meter with cost, notice banners, compaction entries and the Compact/Keep chip, the usage-limit wait, and the error with **Retry** and **Use command line for this chat** | The remaining rows of the table; failure handling (section 5) |
| `macos/Sources/VitruvianCodeUI/VitruvianCodeChatStrings.swift` | Strings for every new view | Localisation |
| `macos/Sources/VitruvianCodeUI/VitruvianCodeTimelineScrubber.swift`, `VitruvianCodeDiffReviewAndDesignViews.swift` | Read tool, plan and diff events from `AgentEvent` | One event type |
| `macos/Tests/AgentCardSnapshotTests.swift` (new), `BubbleSnapshotTests.swift`, `TimelineSnapshotTests.swift` | Snapshots of each new or changed view, light and dark | Visual checks |

#### Step 5: registry agents, MCP, folders, sign-in

| File | Change | Why |
|---|---|---|
| `macos/Sources/VitruvianCodeCore/ACP/ACPRegistry.swift` (new) | Reads the ACP registry. Installs an agent only when the user adds it, at an exact version, into an app-managed folder. npm uses the bundled Node; uv uses the user's `uv`, and the agent is flagged when `uv` is missing. Updates only on the user's choice. Stops an install after T3 Code's timeout | Registry agents, following T3 Code's `AcpRegistrySupport.ts` |
| `macos/Sources/VitruvianCodeCore/ACP/RegistryAgents/ClaudeACPAdapter.swift` (new) | Quirks for `claude-agent-acp`: Agent and Task subagents, background subagents, `subagent_update` and `session_message` | The Claude ACP option, following T3 Code's `claudeAcp.ts` |
| `macos/Sources/VitruvianCodeCore/ACP/ACPAuth.swift` (new) | Shows the agent's sign-in methods. Runs `authenticate` for agent methods. Terminal methods run in their own process, then the app reconnects | Sign-in from the app |
| `macos/Sources/VitruvianCodeCore/AgentMCPServers.swift` (new) | The app's MCP server list, imported once from Claude Code's MCP config. It's passed to agy and Claude at session start. A registry agent gets it only after the user turns that on. Secrets go over stdin | MCP servers |
| `macos/Sources/VitruvianCodeCore/AgentSessionHistory.swift` (new) | Uses `session/list` and `session_info_update` where an agent offers them, and the transcript readers otherwise | History from the agent |
| `macos/Sources/VitruvianCode/SettingsView.swift`, `ConfigManager.swift` | Per-agent Connection; the global approval default; Claude config folder and environment values (sensitive ones in the Keychain); the registry agent list with add, version and remove; MCP servers with a per-registry-agent switch; extra folders per project | Settings (section 9) |
| `macos/Tests/ACP/ACPRegistryTests.swift`, `ACPAuthTests.swift`, `AgentMCPServersTests.swift` (new) | Registry: exact version required, no install without the user, `uv` missing flagged. Auth flows. MCP secrets never appear in arguments or the environment | Coverage, including the safety rules |

#### Step 6: defaults and docs

| File | Change | Why |
|---|---|---|
| `macos/Sources/VitruvianCodeCore/VitruvianCodeStoredProviders.swift` | When no connection is saved, agy defaults to ACP and Claude to the Agent SDK. A saved choice is kept | Switch the default once everything works |
| `README.md`, `docs/index.md`, `macos/README.md`, `macos/Sources/VitruvianCodeCore/README.md`, `macos/Sources/VitruvianCodeUI/README.md` | Explain connections, approval modes and the plan switch, Claude login and API keys, registry agents and MCP servers | User and contributor docs |
| `docs/designs/vitruvian-code-acp.md` | Status set to Implemented; record the step-2 facts | Design of record |
| `//apps/desktop/AGENTS.md` | Where the ACP client, helper and fixtures live, and how to record fixtures | Guidance for agents working here |
| `THIRD_PARTY_NOTICES.md` | Licences for Node and the Agent SDK | Licence compliance |

### Verification

*   **Every step:** `bazel test //apps/desktop/vitruvian-code/...` passes.
*   **Step 1:** the existing stream fixtures produce identical events through
    `CommandLineConnection`.
*   **Steps 2 and 3:** the replay fixtures cover every event kind each agent
    sends. Each mapping test fails when its mapping is removed. Helper
    messages validate against `protocol.schema.json` on both sides.
*   **Step 4:** a snapshot test for each new view. Then a live click-through
    in an isolated test copy of the app, with its own bundle ID and settings
    domain, separate from the user's real settings. Check each of these:
    *   stop mid-turn;
    *   approve and deny in each mode;
    *   answer a form;
    *   switch model;
    *   a slash command;
    *   the plan view;
    *   an image attachment;
    *   the usage meter;
    *   subagent start and finish;
    *   reopen a session;
    *   a failed start with Retry and "Use command line".
*   **Step 6:** one release through the catalog, then the same click-through
    in the installed extension.
