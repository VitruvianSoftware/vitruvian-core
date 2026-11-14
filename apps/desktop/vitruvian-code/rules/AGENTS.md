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

### Step 3: Configure & Start the Bot in the Vitruvian Code App

1. Open **Vitruvian Code** from Applications (it bundles the Rust `bot-engine` binary in `Contents/Helpers/bot-engine` — no Node.js installation required).
2. Open **Settings** from the menu bar app, paste your **Telegram Bot Token** and **Allowed User IDs**, choose your default **Working Directory**, and click **Save** (writes `~/.config/vitruvian-code/.env`).
3. Click **Start** in the Vitruvian Code app menu to start the bundled bot.

> **Contributors:** To run the Rust bot directly from the monorepo checkout during development, run `bazel run //apps/desktop/vitruvian-code/src:bot`.

### Step 4: Test It

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

- **Start / Stop / Restart**: Use the controls in the **Vitruvian Code** menu bar app.
- **Status & Logs**: Inspect the running indicator and recent log output inside the **Vitruvian Code** menu bar app (`~/Library/Application Support/Vitruvian Code/bot.log`).
- **Contributor dev run**: `bazel run //apps/desktop/vitruvian-code/src:bot`

## How It Works

```
Telegram → Bundled Rust Bot (Contents/Helpers/bot-engine) → agy -p "prompt" --output-format json → reply
```

Each Telegram message spawns `agy -p` in print mode. Conversations are tracked
per chat for continuity via `--conversation <id>`. Only whitelisted user IDs
can interact. Responses are formatted as Telegram HTML with automatic message
splitting for long outputs.

## Troubleshooting

- **Empty responses**: The working directory may not have the right context. Use
  `/workdir /path/to/project` to change it.
- **Double messages**: Make sure only one bot instance is running. Stop and
  restart from the **Vitruvian Code** menu bar app so PID tracking stays clean.
- **Auth errors**: Ensure your Telegram user ID is in `ALLOWED_USER_IDS`.
- **Formatting issues**: If markdown doesn't render, open the bot log from the
  **Vitruvian Code** menu bar app to inspect HTML parse warnings.
