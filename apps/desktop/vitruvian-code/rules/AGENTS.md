# Telegram Bot Plugin for the Antigravity CLI

This plugin bridges Telegram messages to the Antigravity CLI (`agy`), giving you remote access
to the full coding agent (file editing, terminal commands, MCP tools) from your
phone or any device with Telegram.

## Setup Guide

When the user asks to set up, configure, or start the Telegram bot, walk them
through these steps in order.

### Step 1: Create a Telegram Bot

1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot`
3. Choose a name (e.g. "My Vitruvian Code Bot")
4. Choose a username (must end in `bot`, e.g. `my_vitruvian_code_bot`)
5. Copy the **bot token** that BotFather gives you

### Step 2: Get Your Telegram User ID

Message [@userinfobot](https://t.me/userinfobot) on Telegram — it will reply
with your numeric user ID. This is used to restrict the bot so only you can use
it.

### Step 3: Configure the Bot

Copy `.env.example` to `.env` in the plugin directory and fill in:

```bash
TELEGRAM_BOT_TOKEN="<your-bot-token>"
ALLOWED_USER_IDS="<your-user-id>"
AGY_WORKING_DIR="<project-directory>"
AGY_APPROVAL_MODE="yolo"
```

### Step 4: Build the Rust Bot

The Telegram bot is a native Rust binary built with Bazel (`src/BUILD`: `bot-engine`, aliased as `bot`; source under `src/rs/`):

```bash
bazel build //apps/desktop/vitruvian-code/src:bot
```

### Step 5: Run & Verify the Bot

Load `.env` from the directory where you run the binary (or export its variables in your shell) and run the bot in the foreground:

```bash
bazel run //apps/desktop/vitruvian-code/src:bot -- --dry-run   # Verify config & command count
bazel run //apps/desktop/vitruvian-code/src:bot               # Start polling Telegram (Ctrl+C to stop)
```

Use `-- --print-agy-flags "<prompt>"` to inspect the `agy` CLI flags generated for a prompt.

### Step 6: Test It

Open Telegram, find your bot, and send it a message like "hello". You should get
a response from agy.

## Available Bot Commands

| Command              | Description                                    |
|----------------------|------------------------------------------------|
| `/help`              | Show all available commands                    |
| `/new`               | Start a fresh session (clears context)         |
| `/session`           | Show current session info                      |
| `/sessions`          | List agy conversations for this workspace      |
| `/resume <n>`        | Resume a session by index                      |
| `/delete_session <n>`| Delete a session by index                      |
| `/extensions`        | List installed agy plugins                     |
| `/skills`            | List available agent skills                    |
| `/mcp`               | List configured MCP servers                    |
| `/model [id]`        | Pick a model from a list, or set one by id     |
| `/effort <level>`    | Reasoning effort: low, medium, high, default   |
| `/mode <mode>`       | Set approval mode (default/accept-edits/plan/yolo) |
| `/sandbox`           | Toggle sandbox mode                            |
| `/workdir <path>`    | Set working directory                          |
| `/settings`          | Show all current settings                      |

## Managing the Bot

The Rust `bot-engine` (`//apps/desktop/vitruvian-code/src:bot`) runs in the foreground (stdout/stderr):

- **Start**: `bazel run //apps/desktop/vitruvian-code/src:bot` (reads `.env` from the current directory and process environment)
- **Stop**: `Ctrl+C` in the running terminal (or `pkill -f bot-engine` if backgrounded)
- **Verify config (dry run)**: `bazel run //apps/desktop/vitruvian-code/src:bot -- --dry-run`
- **Inspect CLI flags**: `bazel run //apps/desktop/vitruvian-code/src:bot -- --print-agy-flags "hi"`

## How It Works

```
Telegram → Bot (Rust, src/rs/) → agy -p "prompt" --output-format stream-json → reply
```

Each Telegram message spawns `agy -p` in print mode. Conversations are tracked
per chat for continuity via `--conversation <id>`. Only whitelisted user IDs
can interact. Responses are formatted as Telegram HTML with automatic message
splitting for long outputs.

## Troubleshooting

- **Empty responses**: The working directory may not have the right context. Use
  `/workdir /path/to/project` to change it.
- **Double messages**: Make sure only one `bot-engine` instance is running (`pgrep -fl bot-engine`).
- **Auth errors**: Ensure your Telegram user ID is in `ALLOWED_USER_IDS`.
- **Formatting issues**: If markdown doesn't render, check the bot's stderr/stdout output for HTML parse warnings.
