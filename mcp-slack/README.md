# mcp-slack

Custom Slack MCP server with **dual-token support** — reads via Bot Token, writes/searches via User Token so messages appear as the authenticated user (not a bot).

## Why is this different from the official Slack MCP server?

The official `@modelcontextprotocol/server-slack` provides a great foundation, but this repository was built to solve two major limitations for advanced AI agents:

1. **User Impersonation (Dual-Token Architecture):** The official server uses only a Bot Token, meaning every message the AI sends appears as a generic "Bot" user. This implementation uses a **Dual-Token** architecture. Read-only and infrastructure tasks use the Bot token, while write operations (posting messages, reacting, pinning, editing) and searches use the User token. This allows the AI agent to truly act *as you*, preserving your identity in threads and direct messages.
2. **Expanded Capabilities (22 Tools vs 9 Tools):** The official server is limited to basic read/reply functions. This server expands the toolkit to 22 specialized tools, adding native support for:
   - **Canvas Management:** Full CRUD operations for Slack Canvases (create, read, edit sections, delete).
   - **Workspace Orchestration:** Read and manage channel pins, bookmarks, and topics.
   - **Advanced Search:** Utilize user-context search modifiers for both messages and files across the workspace.

## Tools

| Tool | Token | Description |
|---|---|---|
| `slack_list_channels` | Bot | List public channels |
| `slack_get_channel_info` | Bot | Get channel details & canvas IDs |
| `slack_get_channel_history` | Bot | Read recent channel messages |
| `slack_get_thread_replies` | Bot | Read thread replies |
| `slack_set_channel_topic` | User | Set channel topic |
| `slack_get_users` | Bot | List workspace users |
| `slack_get_user_profile` | Bot | Get user profile details |
| `slack_search_messages` | **User** | Search messages (modifiers supported) |
| `slack_search_files` | **User** | Search files |
| `slack_post_message` | **User** | Post a message as the authenticated user |
| `slack_reply_to_thread` | **User** | Reply to a thread as the authenticated user |
| `slack_update_message` | **User** | Edit a sent message |
| `slack_add_reaction` | **User** | React to a message |
| `slack_list_pins` | Bot | List pinned items |
| `slack_pin_message` | **User** | Pin a message |
| `slack_unpin_message` | **User** | Unpin a message |
| `slack_list_bookmarks` | Bot | List channel bookmarks |
| `slack_add_bookmark` | **User** | Add channel bookmark |
| `slack_create_canvas` | **User** | Create a Slack canvas |
| `slack_edit_canvas` | **User** | Edit an existing canvas |
| `slack_lookup_canvas_sections`| **User** | Find canvas sections |
| `slack_delete_canvas` | **User** | Delete a canvas |

## 🤖 For AI Agents: Auto-Configuration Instructions

If you are an AI agent (like Antigravity, Claude Code, Codex, Opencode, or Gemini CLI) and your user has asked you to install this MCP server, follow these steps:

### 1. Configure the IDE / Agent Runtime
Depending on your runtime, locate the MCP configuration file (typically `mcp.json` or `mcp_config.json` in the user's configuration directory, e.g., `~/.gemini/antigravity/mcp_config.json` or `~/.config/claude/mcp.json`).
Inject the following server definition into the `mcpServers` object:

```json
"slack": {
  "command": "npx",
  "args": ["-y", "@vitruviansoftware/mcp-slack@latest"],
  "env": {
    "SLACK_BOT_TOKEN": "xoxb-...",
    "SLACK_USER_TOKEN": "xoxp-...",
    "SLACK_TEAM_ID": "T..."
  }
}
```

### 2. Guide the User or Automate Slack App Creation
To populate the tokens, a Slack app must be created.
- **If you have browser control tools**: Navigate to `https://api.slack.com/apps`, create an app "From an app manifest", and paste the contents of `manifest.json`. Install it to the workspace and extract the `xoxb-` and `xoxp-` tokens from the "OAuth & Permissions" page.
- **If you have Slack CLI access**: Use `slack app create` and apply the manifest.
- **Otherwise**: Explicitly instruct the USER to perform Step 1 and Step 2 of the manual setup below, and ask them to provide you with the two tokens and their Team ID.

Once you have the tokens, update the configuration file and restart the MCP server connection!

## Two Slack apps, on purpose

This package ships **two** manifests, and they must not be merged into one.

| | `manifest.json` | `manifest.remote.json` |
|---|---|---|
| Backs | the local **stdio** transport | the **HTTP** transport |
| Reachable from | the machine that spawned it | the public internet |
| Bot scopes | broad, incl. `im:history`, `mpim:history` | channels, pins, bookmarks, `users:read`, `chat:write` |
| User-token scopes | yes — search, canvases, bookmark writes | **none** |

**Why two apps rather than one with the union of the scopes.**

*Independent revocation.* The cluster's token and the local token belong to
different apps, so the public endpoint can be killed without breaking anyone's
local setup. Under a single app the only way to cut off the endpoint is to
revoke a credential the laptop also uses — an emergency control you would
hesitate to pull is not much of an emergency control. **Consolidating the two
apps removes this silently: nothing in the code or the chart expresses it, and
the loss surfaces only when someone needs to revoke.**

*A bot's reach is its channel membership.* A fresh app's bot starts in zero
conversations, so the remote endpoint reaches exactly the channels it is
deliberately invited to — no accumulated history to audit.

*Scopes are the only boundary that survives a leaked token.* The channel
allow-list is a property of this code; it is void if the credential leaves the
process. What the bot's scopes forbid, Slack refuses regardless.

**`manifest.json` is not a template for the remote app.** It is the local app's
manifest, it is broader on purpose, and copying it forward would reinstate the
reach the remote app exists to avoid — `im:history` and `mpim:history` (DMs the
bot belongs to) and `users:read.email` (member email addresses, which nothing in
this codebase reads). The remote manifest's scopes are derived from the tools
the HTTP transport actually advertises. If that tool set changes, re-derive them
rather than adding to them.

**Creating the remote app is a console step, not a CLI one.** Verified against
`slack` v4.6.0 rather than assumed: `slack app link` *"Saves an existing app to
a project"* and needs an App ID that already exists; `slack app install` has no
manifest flag; and `apps.manifest.create` — the only API that creates an app
from a manifest — requires an app configuration access token, which only the
console mints. So: **Create New App → From an app manifest**, paste
`manifest.remote.json`.

`slack app link` afterwards is worth doing, because it unlocks
`slack manifest diff` for drift between the live app settings and this repo.
One caveat before relying on it: `slack manifest` reads the *project* manifest
through the `get-manifest` hook in `.slack/hooks.json`, so a plain file is not
automatically what it compares against — the hook has to be wired to emit this
manifest first.

**No user-token scopes in the remote manifest, by construction.** `resolveConfig`
refuses to start the HTTP transport when `SLACK_USER_TOKEN` is set, and the tools
that need one are withheld from its tool list. Search, canvases, bookmark writes
and topic-set remain local-only features.

## Manual Setup

### 1. Create the Slack App

Go to [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **From an app manifest** → select your workspace → paste the contents of [`manifest.json`](./manifest.json).

### 2. Install and collect tokens

After creating the app, click **Install to Workspace**. Then navigate to **OAuth & Permissions** and copy:

- **Bot User OAuth Token** (`xoxb-...`)
- **User OAuth Token** (`xoxp-...`)

### 3. Environment variables

| Variable | Required | Description |
|---|---|---|
| `SLACK_BOT_TOKEN` | ✅ | Bot User OAuth Token (`xoxb-...`) |
| `SLACK_USER_TOKEN` | ✅ | User OAuth Token (`xoxp-...`) |
| `SLACK_TEAM_ID` | ✅ | Workspace Team ID |
| `SLACK_CHANNEL_IDS` | ❌ | Comma-separated channel IDs to restrict channel listing |

### 4. Build & run

```bash
npm install
npm run build
npm start
```

### 5. MCP Configuration (Claude Desktop / Gemini)

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@vitruviansoftware/mcp-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "xoxb-...",
        "SLACK_USER_TOKEN": "xoxp-...",
        "SLACK_TEAM_ID": "T0123456"
      }
    }
  }
}
```
