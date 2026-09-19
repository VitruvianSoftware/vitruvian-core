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
3. Choose a name (e.g. "My Nexus Bot")
4. Choose a username (must end in `bot`, e.g. `my_nexus_agent_bot`)
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

### Step 4: Install Dependencies

```bash
cd <plugin-directory>
npm install
```

### Step 5: Start the Bot

```bash
cd <plugin-directory>
./bot.sh start
```

Check status with `./bot.sh status` and logs with `./bot.sh logs`.

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
| `/model <name>`      | Set the model (`agy models` lists them)        |
| `/mode <mode>`       | Set approval mode (default/accept-edits/plan/yolo) |
| `/sandbox`           | Toggle sandbox mode                            |
| `/workdir <path>`    | Set working directory                          |
| `/settings`          | Show all current settings                      |

## Managing the Bot

- **Start**: `./bot.sh start`
- **Stop**: `./bot.sh stop`
- **Restart**: `./bot.sh restart`
- **Status**: `./bot.sh status`
- **Logs**: `./bot.sh logs`

## How It Works

```
Telegram → Bot (Node.js) → agy -p "prompt" --output-format json → reply
```

Each Telegram message spawns `agy -p` in print mode. Conversations are tracked
per chat for continuity via `--conversation <id>`. Only whitelisted user IDs
can interact. Responses are formatted as Telegram HTML with automatic message
splitting for long outputs.

## Troubleshooting

- **Empty responses**: The working directory may not have the right context. Use
  `/workdir /path/to/project` to change it.
- **Double messages**: Make sure only one bot instance is running. Use
  `./bot.sh status` to check and `./bot.sh stop` to clean up.
- **Auth errors**: Ensure your Telegram user ID is in `ALLOWED_USER_IDS`.
- **Formatting issues**: If markdown doesn't render, check the bot logs with
  `./bot.sh logs` for HTML parse warnings.
