# Vitruvian Code

A macOS menu bar app and Telegram bot that bridges your messages to locally-installed AI coding CLI tools, giving you remote access to full coding agent capabilities (file editing, terminal commands, MCP tools, multi-provider support) from any device with Telegram or directly from your Mac's Quick Prompt.

---

## System Architecture

### Overview

The bot acts as a thin bridge between the Telegram Bot API and a locally-running AI CLI process. Every message you send on Telegram is forwarded as a headless prompt to your configured CLI tool (e.g. `agy -p`, or a custom provider), and the CLI's JSON response is parsed, formatted, and sent back as a Telegram reply.

```mermaid
flowchart LR
    A[Telegram API] <-->|long-poll| B[Bot Server\nNode.js]
    B -->|child process| C[AI CLI\nagy/Custom]
    B <--> D[(Session Store\nin-mem)]
    C <--> E[(Local File System)]
    C <--> F[Terminal, MCP, Git]

    subgraph "Your Machine"
        B
        C
        D
        E
        F
    end
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Long polling** (not webhooks) | No public URL or TLS certificate required — runs entirely on your local machine |
| **Child process per prompt** | The CLI is stateless per invocation; session continuity is handled via CLI flags (`--resume`) |
| **In-memory session store** | Simple `Map<chatId, sessionId>` — no database needed for single-user use |
| **JSON output format** | Structured parsing of CLI responses instead of fragile text scraping |
| **`yolo` approval mode** | Auto-approves all tool actions for unattended operation (configurable) |

---

## Software Architecture

### Module Dependency Graph

```mermaid
graph TD
    A[src/bot.js<br>Entry point, orchestration] --> B[src/agy.js<br>CLI Process & Provider Logic]
    A --> C[src/formatter.js<br>Telegram Message Formatting]
    A --> D[src/sessions.js<br>Session Management]
```

### Module Details

#### `src/bot.js` — Bot Server & Orchestration

The main entry point. Initializes the Telegraf bot, registers middleware, commands, and message handlers.

**Responsibilities:**
- Load configuration from environment variables via `dotenv`
- Initialize Telegraf with the bot token
- Apply authentication middleware (user ID whitelist)
- Register command handlers (`/start`, `/new`, `/session`, `/help`)
- Forward incoming text messages to the agy module
- Format and send responses back, splitting if needed
- Maintain typing indicator during long-running prompts
- Graceful shutdown on `SIGINT`/`SIGTERM`

**Middleware pipeline:**

```mermaid
flowchart TD
    A[Incoming Update] --> B{Auth Middleware}
    B -->|Reject| C["Not authorized message"]
    B -->|Pass| D[Command or Text Handler]
```

#### `src/agy.js` — AI CLI Interface & Pluggable Provider Management

Manages spawning of AI CLI child processes and tracking sessions per chat.

**Responsibilities:**
- Spawn `agy -p "<prompt>"` or custom provider using `CLI_COMMAND_TEMPLATE`
- Tokenize and inject `{prompt}` and `{model}` into custom provider arguments
- Set working directory to `AGY_WORKING_DIR`
- If a session exists for the chat, pass it to context continuity (e.g., via `--resume`)
- Collect stdout/stderr buffers and parse on process exit
- Stream support (`executePromptStreaming`) and multi-strategy JSON parsing
- Track active running processes to allow prompt cancellation

**Exported API:**

| Function | Description |
|----------|-------------|
| `executePrompt(prompt, options)` | Run a prompt and wait, return `{ text, sessionId }` |
| `executePromptStreaming(prompt, options)` | Run prompt with callback chunks |
| `cancelPrompt(chatId)` | Terminate a running process for a chat |
| `clearSession(chatId)` | Forget session for a chat |

**CLI invocation example:**
```bash
agy -p "explain this function" \
  --output-format json \
  --dangerously-skip-permissions \
  --conversation 910c55f0-f6a2-450e-9129-215a4e07abe2
```

#### `src/formatter.js` — Response Formatting

Handles Telegram's message constraints and format conversion.

**Responsibilities:**
- Split responses exceeding Telegram's 4096-character limit into multiple messages
- Intelligent splitting at paragraph boundaries → newlines → spaces → hard break
- MarkdownV2 escaping utility (for future use)
- Format selection (currently sends as plain text for maximum compatibility)

---

## Request Lifecycle

A full request-response cycle for a text message:

```mermaid
sequenceDiagram
    participant U as User (Telegram)
    participant T as Telegram API
    participant B as Bot Server
    participant C as AI CLI Process

    U->>T: Send message
    T->>B: Deliver update via long-poll
    B->>B: Auth middleware check
    B->>T: Send "typing" action
    B->>C: Spawn process (e.g. agy -p "message")
    Note over C: Executes shell, reads files, runs MCP
    C-->>B: Return JSON to stdout
    B->>B: Parse JSON & extract session ID
    B->>B: Split response via formatter if > 4096 chars
    B->>T: Send reply message(s)
```

---

## Session Management

Sessions provide conversation continuity so follow-up messages have context.

```mermaid
flowchart LR
    C1[Chat 1] --> S1[sessions.get] --> U1[session-uuid-abc] --> G1[CLI --resume session-uuid-abc]
    C2[Chat 2] --> S2[sessions.get] --> U2[session-uuid-xyz] --> G2[CLI --resume session-uuid-xyz]
```

- **First message** in a chat: no resume flag is passed. The CLI starts a new session and returns a `sessionId` in its JSON output.
- **Subsequent messages**: the stored `sessionId` is passed (via `--resume`), giving the CLI full conversation history.
- **`/new` command**: deletes the stored session ID, so the next message starts fresh.
- **Storage**: persisted across restarts using `.bot-sessions.json`.

---

## Security Model

```mermaid
block-beta
    columns 1
    A("1. Telegram Bot Token (only you know it)"):1
    B("2. User ID Whitelist (ALLOWED_USER_IDS)"):1
    C("3. Local-only execution (no public server)"):1
    D("4. Process-level sandboxing (optional -s)"):1
```

| Layer | Protection |
|-------|------------|
| **Bot token** | Only someone with the token can receive updates. Keep it secret. |
| **User ID whitelist** | Even if someone finds your bot, they can't interact unless their Telegram user ID is in `ALLOWED_USER_IDS`. Unauthorized attempts are logged. |
| **Local execution** | The bot uses long-polling, not webhooks — no ports are exposed to the internet. |
| **Sandbox mode** | Pass `AGY_APPROVAL_MODE=default` or use agy's `--sandbox` flag for restricted execution. |

> ⚠️ **Warning**: `AGY_APPROVAL_MODE=yolo` auto-approves all tool actions (file writes, command execution). Only use this when you trust all messages will come from you.

---

## Quick Start

### 1. Create a Telegram Bot

1. Message [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot` and follow the prompts
3. Copy the bot token

### 2. Get Your Telegram User ID

Message [@userinfobot](https://t.me/userinfobot) on Telegram — it will reply with your user ID.

### 3. Configure

```bash
cp .env.example .env
```

Edit `.env`:
```
TELEGRAM_BOT_TOKEN=your_bot_token_here
ALLOWED_USER_IDS=your_user_id_here
AGY_WORKING_DIR=/path/to/your/project
```

### 4. Install Dependencies

```bash
npm install
```

### 5. Run

There are four ways to run the bot:

#### Option A: Direct (foreground)

```bash
npm start
```

Runs in the foreground — you'll see logs in your terminal. Press `Ctrl+C` to stop.

#### Option B: Daemon via `bot.sh`

```bash
./bot.sh start     # Start in background
./bot.sh stop      # Graceful shutdown
./bot.sh restart   # Stop + start
./bot.sh status    # Check if running
./bot.sh logs      # Tail the log file
```

Runs in the background with PID tracking and orphan process cleanup. Logs are written to `bot.log`.

#### Option C: macOS Menu Bar App

Download the latest DMG from the [Releases page](https://github.com/VitruvianSoftware/vitruvian-code/releases). Open it and drag the app to your Applications folder.

A native SwiftUI app that lives in the menu bar (no dock icon). Provides a GUI to start/stop the bot, view logs, configure settings, and handle Quick Prompts. See [macOS Menu Bar App](#macos-menu-bar-app) below for installation and release signing details.

#### Option D: Antigravity plugin

```bash
agy plugin install https://github.com/VitruvianSoftware/vitruvian-code
```

Clones this repository into Antigravity's plugin folder (`~/.gemini/config/plugins/vitruvian-code`) and loads its setup guide (`rules/AGENTS.md`) into every session. Ask agy *"help me set up the Telegram bot"* and it will walk you through configuration, then start the bot from that folder. To install from a local clone instead, pass its path in place of the URL.

---

## macOS Menu Bar App

A native SwiftUI companion app that manages the bot daemon from the menu bar.

### Features

| Feature | Description |
|---------|-------------|
| **Status icon** | ✈️ filled = running, outline = stopped |
| **Controls** | Start / Stop / Restart from the dropdown |
| **Logs** | Recent log lines inline + open full log |
| **Settings** | GUI for bot token, user IDs, working dir, model, approval mode |
| **Auto-start** | Optionally start the bot when the app launches |
| **No dock icon** | `LSUIElement=true` — menu bar only |

### Installation

Releases are signed with the Apple Developer ID Application certificate and notarized by Apple so macOS Gatekeeper opens them directly:

1. **Download** the latest `VitruvianCode-x.x.x-macos.dmg` (universal) — or `-arm64.dmg` / `-x86_64.dmg` — from the [GitHub Releases page](https://github.com/VitruvianSoftware/vitruvian-code/releases).
2. **Mount the DMG** by double-clicking it.
3. **Install** by dragging `Vitruvian Code.app` into the `Applications` folder shortcut, then open it from `/Applications`.

### Release Signing

Every standalone release signs and notarizes all shipped macOS binaries and disk images via [`scripts/sign-and-notarize.sh`](./scripts/sign-and-notarize.sh) before generating `.zip` archives and `.sha256` checksums:

- **What is signed:** `Vitruvian Code.app` (`com.vitruviansoftware.code`, universal + `arm64` + `x86_64`), the standalone `bin/tool` Mach-O inside `vitruvian-code-tool-<version>.zip`, and all three `.dmg` disk images (`-macos.dmg`, `-arm64.dmg`, `-x86_64.dmg`). App bundles and `.dmg` images have notarization tickets stapled via `xcrun stapler`.
- **Entitlements:** `Vitruvian Code.app` carries only `com.apple.security.automation.apple-events` ([`macos/Resources/VitruvianCode.entitlements`](./macos/Resources/VitruvianCode.entitlements)) because it launches AI coding tools (`claude`, `gemini`, and others) as child processes that may run `osascript`; TCC treats Vitruvian Code as the responsible process and Hardened Runtime refuses Apple Events without this entitlement. `vitruvian-code-tool` carries no entitlements.
- **Where secrets live:** the `vitruvian-code-release` GitHub Environment on `VitruvianSoftware/vitruvian-code` (declared in monorepo `repo-config`, restricted to branch `main` only), holding `VITRUVIAN_SIGNING_CERT_P12`, `VITRUVIAN_SIGNING_CERT_PASSWORD`, `VITRUVIAN_NOTARY_API_KEY_P8`, `VITRUVIAN_NOTARY_KEY_ID`, and `VITRUVIAN_NOTARY_ISSUER_ID`.
- **Loading secrets from `vitruvian-core`:**
  ```sh
  REPO=VitruvianSoftware/vitruvian-code bazel run //tools/sync-env-secrets:apply -- vitruvian-code-release
  ```

### Auto-Update

The app includes a built-in auto-updater. It will periodically check the GitHub Releases page for new versions. When an update is available:
1. An "Update available" banner will appear in the menu bar dropdown.
2. Click the **Update** button.
3. The app will download the new version, replace itself in the `Applications` folder, and automatically relaunch.

---

## Bot Commands

### Core

| Command | Description |
|---------|-------------|
| `/start` | Welcome message and info |
| `/help` | Show all available commands |

### Session Management

| Command | Description |
|---------|-------------|
| `/new` | Clear session and start fresh |
| `/session` | Show current session info |
| `/sessions` | List agy conversations for this workspace |
| `/resume <n>` | Resume a session by index (e.g. `/resume 5` or `/resume latest`) |
| `/delete_session <n>` | Delete a session by index |

### CLI Management

| Command | Description |
|---------|-------------|
| `/extensions` | List installed agy plugins |
| `/skills` | List available agent skills |
| `/mcp` | List configured MCP servers |

### Settings (per-chat)

| Command | Description |
|---------|-------------|
| `/model [id]` | Pick a model from a tap list, or set one by id |
| `/effort <low\|medium\|high>` | Reasoning effort (`--effort`); high extends the wait to 10 min |
| `/mode <mode>` | Approval mode: `yolo`, `accept-edits`, `plan`, `default` (headless `default` denies tools that need approval) |
| `/sandbox` | Toggle sandbox mode (Docker/Podman) |
| `/workdir <path>` | Set working directory for agy |
| `/settings` | Show all current settings |


## Configuration Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `TELEGRAM_BOT_TOKEN` | Bot token from BotFather | *required* |
| `ALLOWED_USER_IDS` | Comma-separated Telegram user IDs | *empty = all allowed* |
| `AGY_WORKING_DIR` | Working directory for the AI CLI | Current directory |
| `AGY_TIMEOUT_MS` | Max execution time per prompt (ms) | `300000` (5 min) |
| `AGY_APPROVAL_MODE` | Tool approval mode (`yolo`, `accept-edits`, `plan`, `default`) | `yolo` |
| `AGY_MODEL` | Default model to use | CLI default |
| `AGY_BIN` | Path to the `agy` binary | `~/.local/bin/agy`, Homebrew, or PATH |
| `CLI_PROVIDER` | Provider selection (`agy`, `custom`) | `agy` |
| `CLI_COMMAND_TEMPLATE` | Custom CLI template (e.g. `ollama run {model} "{prompt}"`) | *empty* |
| `AGY_EFFORT` | Reasoning effort (`low`, `medium`, `high`); `high` also extends the timeout | CLI default |

The pre-migration `GEMINI_*` names are still read as fallbacks.

## Requirements

- Node.js 18+
- [Antigravity CLI](https://antigravity.google) (`agy`) installed and signed in — Google retired Gemini CLI for individual accounts
- A Telegram bot token from [@BotFather](https://t.me/BotFather)

## Subdirectories & Boundaries
- [macos](./macos/README.md): Component package providing implementation for apps/desktop/vitruvian-code/macos.
- [scripts](./scripts/README.md): Release code-signing and notarization scripts for Vitruvian Code macOS bundles and disk images.
- [src](./src/README.md): Component package providing implementation for apps/desktop/vitruvian-code/src.

