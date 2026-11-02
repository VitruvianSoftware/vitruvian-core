<!--
Copyright 2026 VitruvianSoftware
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Courier milestone 5: acceptance list

Milestone 5 lets Claude, and any other app that speaks MCP, use Courier the way it used the reference app's MCP. Only the address and the token change. Tick a line when you have seen it work. Write down anything wrong, with no names, numbers or message text.

A tick means "I saw this work", not "the code exists". The plan is `docs/superpowers/plans/2026-11-01-courier-m5-local-api-mcp.md`.

## What leaves this Mac

Nothing, unless you turn it on. Connections are off until you turn on **Allow connections**. Then Courier listens on 127.0.0.1 only, so only apps on this Mac can connect, and each needs a token you approved. **Remote Access** lets other devices on your network connect too, with a token. That traffic is plain HTTP, not encrypted, which is why turning it on asks first.

## Before you start

- Install the build with `bazel run --config=macos-app //apps/desktop/courier/app:install`.
- Open Settings ▸ Integrations (⌘,).

## Settings ▸ Integrations

- [ ] Allow connections is off on a fresh install, and the status line says "Off".
- [ ] Turning it on: the status line says "Listening on 127.0.0.1:23390". It stays on after quitting and reopening Courier.
- [ ] Port: type 80, or letters, and press Return. It says "Enter a port from 1024 to 65535." and nothing changes. Type 24000: the status line and the MCP endpoint move to 24000 at once, with no relaunch. Put it back to 23390.
- [ ] Port in use: start something else on the port (for example `python3 -m http.server 23390` in Terminal), then turn connections off and on. The status line says, in red, "Port 23390 is in use by another app". Courier keeps working. Stop the other program and turn connections off and on again.
- [ ] Remote Access asks first: "Other devices on your network will be able to connect to Courier with an approved token. Traffic is not encrypted." Cancel leaves it off. Turn On: the status line says "Listening on all addresses, port 23390", and the MCP endpoint shows this Mac's network address. It applies at once, with no relaunch. Turning it off needs no confirm.
- [ ] MCP endpoint's Copy puts the address on the clipboard.

## A new connection

- [ ] New connection… asks for a name and "Can send messages". Create shows the secret, once, with Copy buttons for: the secret; the Claude Code command over HTTP; the Claude Code command over stdio; and Add and Copy link for Cursor and VS Code.
- [ ] Done closes it. The secret can't be shown again: the connection's row has no way to see it.
- [ ] The row shows the name, when it was made, and "Never used" until a client uses it. After a request it shows when it was last used (to the minute).
- [ ] "Can send messages" can be turned on and off on the row. With it off, `send_message` is refused.
- [ ] Revoke… asks first. After Revoke, a client that is still connected gets refused on its very next request.

## A client asking to connect (pairing)

- [ ] `curl -X POST http://127.0.0.1:23390/v0/pair -d '{"clientName":"Test client"}'` shows one alert on Courier's main window: "“Test client” wants to read your chats in Courier.", with Allow, Allow and Send Messages, and Don't Allow.
- [ ] Allow: curl prints a token. Don't Allow: curl gets 403. Allow and Send Messages: the new row has "Can send messages" on.
- [ ] Waiting 2 minutes without answering: the alert goes away by itself and curl gets 403.
- [ ] Pressing Ctrl-C on curl while the alert shows: the alert goes away.
- [ ] A second curl while the first waits gets 429, and no second alert appears.
- [ ] While Courier is locked, no alert appears and the request ends with 403 after 2 minutes.

## The tools

Use each from Claude Code, connected over HTTP. None of them may crash Courier or answer with an HTTP 500, whatever you give them.

- [ ] `get_accounts` lists every network you have signed in to.
- [ ] `search` finds chats, people in groups and messages for a word you know is there.
- [ ] `search_chats` filters by network, inbox (primary, low priority, archive), unread and name, and pages with its cursor.
- [ ] `search_messages` finds a known word. `sender: "me"` keeps only your messages.
- [ ] `get_chat` gives the chat's details and its people.
- [ ] `list_messages` pages back through a chat with no gaps or repeats, even when new messages arrive between pages.
- [ ] Edit a message, then delete another. `list_messages`, `search_messages` and `search` show the edited one's new text with `isEdited: true`, never its old text, and leave the deleted one out.
- [ ] `send_message` sends from a token with "Can send messages" on, and is refused from one without.
- [ ] `archive_chat`, `set_chat_reminder` and `clear_chat_reminder` show in Courier at once.
- [ ] `focus_app` brings Courier forward at the chat and message. With draft text and a file, they are in the composer, with the file's name on its chip, and nothing is sent until you press Send. A file path that doesn't exist is an error and the composer is left alone.
- [ ] `search_docs` answers with one line: "Courier has no documentation search. Each tool's description is its documentation."
- [ ] An unknown chat ID, message ID or cursor is a plain error message from the tool.

## Who may connect

- [ ] No `Authorization` header, a wrong token, or a revoked one: 401 `{"error":"unauthorized"}`.
- [ ] A request with an `Origin` header (from a web page): 403.
- [ ] With Remote Access off, a request to this Mac's network address from another device does not connect. With it on, it connects with a token and is refused without one.
- [ ] stdio: `COURIER_TOKEN=<token> /Applications/Courier.app/Contents/Helpers/courier-engine mcp-stdio` works as an MCP server. With no token, or with connections off, it prints one plain line and stops.

## The by-hand check

- [ ] In `~/.claude.json`, point `mcpServers.beeper` (or a new `courier` entry) at `http://<this Mac's address>:23390/v0/mcp` (Remote Access on) or `http://127.0.0.1:23390/v0/mcp` with a Courier token; `get_accounts` lists all six networks; `search_messages` finds a known word.

## Ledger rows (`setting:integrations`)

Each line is one row of the inventory's `ledger.tsv`, kept under its row name. The text after the dash says what Courier does now.

- `Allow connections` — shipped: the switch for the local MCP server, off by default.
- `Remote Access` — shipped, with a confirm. Unlike the reference app, it applies at once rather than after a relaunch.
- `Cursor` — shipped as an install link (Add, or Copy link) in the new-connection sheet, using HTTP.
- `VS Code` — shipped as an install link, the same way.
- `Install to` — partly shipped: Claude Code commands for HTTP and for stdio. There is no Codex command and no picker; the sheet lists every option at once.
- `Claude Desktop` — not planned in iteration 1. The reference app downloads a Claude Desktop extension file (`.dxt`). Courier doesn't build one. Claude Desktop can still use Courier through its MCP settings with the stdio command.
- `Raycast` — not planned in iteration 1. Raycast's extension talks to the reference app's REST API, which Courier doesn't have.

## Not ledger rows

These were in the reference app but have no ledger row of their own. They are out of scope for milestone 5.

- The REST API (`/v1`) and its OpenAPI spec endpoint. Courier serves MCP only.
- The OAuth flow third-party apps used to get a token. In Courier you make a token in Settings, or a client asks with `POST /v0/pair` and you answer the alert.
- The approval dialog's "Expires in" choice. Courier's tokens last until revoked.
- "Join Developer Community chat".
