# mcp-slack

Custom Slack MCP server with **dual-token support** — reads via Bot Token, writes/searches via User Token so messages appear as the authenticated user (not a bot).

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

## Setup

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
