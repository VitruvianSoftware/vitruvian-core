# Gemini CLI Telegram Bot

A Telegram bot that bridges your messages to the locally-installed [Gemini CLI](https://github.com/google-gemini/gemini-cli), giving you remote access to its full coding agent capabilities — file editing, terminal commands, MCP tools — from any device with Telegram.

---

## System Architecture

### Overview

The bot acts as a thin bridge between the Telegram Bot API and a locally-running Gemini CLI process. Every message you send on Telegram is forwarded as a headless prompt to `gemini -p`, and the CLI's JSON response is parsed, formatted, and sent back as a Telegram reply.

```
┌──────────────────────────────────────────────────────────────────┐
│                        YOUR MACHINE                              │
│                                                                  │
│  ┌───────────┐    HTTP    ┌──────────────┐   child    ┌────────┐ │
│  │ Telegram  │◄──────────►│  Bot Server  │  process   │ Gemini │ │
│  │   API     │  long-poll │  (Node.js)   │───────────►│  CLI   │ │
│  └───────────┘            └──────────────┘            └────────┘ │
│       ▲                        │                        │        │
│       │                        │                        ▼        │
│       │                   ┌────┴────┐              ┌─────────┐   │
│       │                   │ Session │              │  Local  │   │
│       │                   │  Store  │              │  File   │   │
│       │                   │ (in-mem)│              │ System  │   │
│       │                   └─────────┘              └─────────┘   │
│       │                                                 │        │
│       ▼                                                 ▼        │
│  ┌──────────┐                                    ┌────────────┐  │
│  │   You    │                                    │  Terminal, │  │
│  │(Telegram)│                                    │  MCP, Git  │  │
│  └──────────┘                                    └────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Long polling** (not webhooks) | No public URL or TLS certificate required — runs entirely on your local machine |
| **Child process per prompt** | Gemini CLI is stateless per invocation; session continuity is handled via `--resume` flag |
| **In-memory session store** | Simple `Map<chatId, sessionId>` — no database needed for single-user use |
| **JSON output format** | Structured parsing of CLI responses instead of fragile text scraping |
| **`yolo` approval mode** | Auto-approves all tool actions for unattended operation (configurable) |

---

## Software Architecture

### Module Dependency Graph

```
src/bot.js          ← Entry point, orchestration
  ├── src/gemini.js     ← Gemini CLI process management
  └── src/formatter.js  ← Telegram message formatting
```

### Module Details

#### `src/bot.js` — Bot Server & Orchestration

The main entry point. Initializes the Telegraf bot, registers middleware, commands, and message handlers.

**Responsibilities:**
- Load configuration from environment variables via `dotenv`
- Initialize Telegraf with the bot token
- Apply authentication middleware (user ID whitelist)
- Register command handlers (`/start`, `/new`, `/session`, `/help`)
- Forward incoming text messages to the Gemini module
- Format and send responses back, splitting if needed
- Maintain typing indicator during long-running prompts
- Graceful shutdown on `SIGINT`/`SIGTERM`

**Middleware pipeline:**

```
Incoming Update
      │
      ▼
┌─────────────┐    Reject
│   Auth      │──────────────► "Not authorized"
│  Middleware │
└──────┬──────┘
       │ Pass
       ▼
┌──────────────┐
│  Command or  │
│  Text Handler│
└──────────────┘
```

#### `src/gemini.js` — Gemini CLI Interface

Manages spawning of Gemini CLI child processes and tracking sessions per chat.

**Responsibilities:**
- Spawn `gemini -p "<prompt>" --output-format json --approval-mode <mode>` as a child process
- Set working directory to `GEMINI_WORKING_DIR`
- If a session exists for the chat, append `--resume <sessionId>` for context continuity
- Collect stdout/stderr buffers and parse on process exit
- Multi-strategy JSON parsing (single object → newline-delimited → raw fallback)
- Store session IDs returned by CLI in an in-memory `Map`
- Enforce configurable timeout via `child_process` timeout option

**Exported API:**

| Function | Description |
|----------|-------------|
| `executePrompt(prompt, { chatId })` | Run a prompt, return `{ text, sessionId }` |
| `clearSession(chatId)` | Forget session for a chat |
| `hasSession(chatId)` | Check if a session is tracked |
| `getSession(chatId)` | Get the session ID for a chat |

**CLI invocation example:**
```bash
gemini -p "explain this function" \
  --output-format json \
  --approval-mode yolo \
  --resume 910c55f0-f6a2-450e-9129-215a4e07abe2
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

```
1. User sends message on Telegram
                │
2. Telegram API delivers update via long-poll
                │
3. Telegraf receives update
                │
4. Auth middleware checks user ID against whitelist
                │
5. Text handler fires:
   a. Send "typing" chat action
   b. Start 4-second typing interval
   c. Call executePrompt(message, { chatId })
                │
6. gemini.js spawns child process:
   ┌──────────────────────────────────────────────────┐
   │ gemini -p "message" --output-format json         │
   │         --approval-mode yolo [--resume sessionId]│
   │ cwd: GEMINI_WORKING_DIR                          │
   └──────────────────────────────────────────────────┘
                │
7. Gemini CLI runs (may take seconds to minutes):
   - Reads/writes files
   - Executes shell commands
   - Calls MCP tools
   - Returns JSON to stdout
                │
8. gemini.js parses JSON output:
   - Extracts response text
   - Captures session ID for future --resume
                │
9. formatter.js splits response if > 4096 chars
                │
10. Bot sends reply message(s) to Telegram
                │
11. Clear typing interval
```

---

## Session Management

Sessions provide conversation continuity so follow-up messages have context.

```
Chat 1 ──► sessions.get(1) ──► "session-uuid-abc" ──► gemini --resume session-uuid-abc
Chat 2 ──► sessions.get(2) ──► "session-uuid-xyz" ──► gemini --resume session-uuid-xyz
```

- **First message** in a chat: no `--resume` flag is sent. Gemini CLI starts a new session and returns a `sessionId` in its JSON output.
- **Subsequent messages**: the stored `sessionId` is passed via `--resume`, giving the CLI full conversation history.
- **`/new` command**: deletes the stored session ID, so the next message starts fresh.
- **Storage**: in-memory `Map` — sessions are lost on bot restart (by design; Gemini CLI retains its own session history on disk).

---

## Security Model

```
┌─────────────────────────────────────────────┐
│              Security Layers                │
├─────────────────────────────────────────────┤
│ 1. Telegram Bot Token (only you know it)    │
│ 2. User ID Whitelist (ALLOWED_USER_IDS)     │
│ 3. Local-only execution (no public server)  │
│ 4. Process-level sandboxing (optional -s)   │
└─────────────────────────────────────────────┘
```

| Layer | Protection |
|-------|------------|
| **Bot token** | Only someone with the token can receive updates. Keep it secret. |
| **User ID whitelist** | Even if someone finds your bot, they can't interact unless their Telegram user ID is in `ALLOWED_USER_IDS`. Unauthorized attempts are logged. |
| **Local execution** | The bot uses long-polling, not webhooks — no ports are exposed to the internet. |
| **Sandbox mode** | Pass `GEMINI_APPROVAL_MODE=default` or use Gemini CLI's `--sandbox` flag for restricted execution in a Docker/Podman container. |

> ⚠️ **Warning**: `GEMINI_APPROVAL_MODE=yolo` auto-approves all tool actions (file writes, command execution). Only use this when you trust all messages will come from you.

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
GEMINI_WORKING_DIR=/path/to/your/project
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

Download the latest DMG from the [Releases page](https://github.com/BlueCentre/gemini-bot/releases). Open it and drag the app to your Applications folder.

A native SwiftUI app that lives in the menu bar (no dock icon). Provides a GUI to start/stop the bot, view logs, configure settings, and handle Quick Prompts. See [macOS App Setup](#macos-menu-bar-app) below for Gatekeeper instructions.

#### Option D: Gemini CLI Extension

```bash
gemini extensions install https://github.com/<your-repo>/gemini-bot
# or link locally:
gemini extensions link /path/to/gemini-bot
```

Installs the bot as a Gemini CLI extension. Ask Gemini *"help me set up the Telegram bot"* and it will walk you through configuration using the bundled playbook.

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

The application is distributed as a universal DMG. Because it is currently **unsigned**, macOS Gatekeeper will block the first launch. Follow these steps to install and open it:

1. **Download** the latest `GeminiBotBar-x.x.x-universal.dmg` from the [GitHub Releases page](https://github.com/BlueCentre/gemini-bot/releases).
2. **Mount the DMG** by double-clicking it.
3. **Install** by dragging the `GeminiBotBar` app into the `Applications` folder shortcut.
4. **First Launch (Important):**
   - Open your `Applications` folder in Finder.
   - You **cannot** double-click the app (macOS will say it's damaged or from an unidentified developer).
   - Instead, **Right-click (or Control-click)** the app and select **Open**.
   - A dialog will appear asking if you are sure you want to open it. Click **Open**.

*You only need to do this exact "Right-click -> Open" process once. For subsequent launches, or when the app auto-updates, it will open normally.*

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
| `/sessions` | List all available Gemini CLI sessions |
| `/resume <n>` | Resume a session by index (e.g. `/resume 5` or `/resume latest`) |
| `/delete_session <n>` | Delete a session by index |

### CLI Management

| Command | Description |
|---------|-------------|
| `/extensions` | List installed Gemini CLI extensions |
| `/skills` | List available agent skills |
| `/mcp` | List configured MCP servers |

### Settings (per-chat)

| Command | Description |
|---------|-------------|
| `/model <name>` | Set the Gemini model (e.g. `/model gemini-2.5-flash`) |
| `/mode <mode>` | Set approval mode (`default`, `auto_edit`, `yolo`) |
| `/sandbox` | Toggle sandbox mode (Docker/Podman) |
| `/workdir <path>` | Set working directory for Gemini CLI |
| `/settings` | Show all current settings |


## Configuration Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `TELEGRAM_BOT_TOKEN` | Bot token from BotFather | *required* |
| `ALLOWED_USER_IDS` | Comma-separated Telegram user IDs | *empty = all allowed* |
| `GEMINI_WORKING_DIR` | Working directory for Gemini CLI | Current directory |
| `GEMINI_TIMEOUT_MS` | Max execution time per prompt (ms) | `300000` (5 min) |
| `GEMINI_APPROVAL_MODE` | Tool approval mode (`default`, `auto_edit`, `yolo`) | `yolo` |
| `GEMINI_MODEL` | Gemini model to use | CLI default |
| `GEMINI_BIN` | Path to the `gemini` binary | `/opt/homebrew/bin/gemini` |

## Requirements

- Node.js 18+
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) installed and authenticated (`npm i -g @google/gemini-cli`)
- A Telegram bot token from [@BotFather](https://t.me/BotFather)
