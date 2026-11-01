---
status: in-progress
---

# Courier milestone 5: local API and MCP — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude (and other MCP clients) can use Courier exactly as it used the reference app's MCP, with only the address and token changed.

**Architecture:** A new engine package `localapi` serves MCP over streamable HTTP on `127.0.0.1:23390/v0/mcp`. Each tool calls the engine's existing RPC method implementations in-process, so no query logic is duplicated. Bearer tokens live hashed in `courier.db`; James creates or approves them in Settings → Integrations. A `courier-engine mcp-stdio` subcommand gives clients a stdio transport that forwards to the HTTP endpoint.

**Tech stack:** Go 1.26.6, `github.com/modelcontextprotocol/go-sdk` v1.8.0 (latest on 2026-11-01; official SDK, streamable HTTP and stdio), SwiftUI.

**Spec:** `docs/superpowers/specs/2026-10-15-courier-iteration-1-design.md` §6 and §7 (milestone 5). Reference tool list: `apps/desktop/courier/protocol/mcp-tools.json`, captured from the running reference app on 2026-11-01.

## Global Constraints

- Listen on **127.0.0.1 only**. No setting, flag or environment variable may bind any other address. Default port **23390**, changeable in Settings → Integrations (1024–65535).
- Path: **`/v0/mcp`** (same path as the reference app, so only host, port and token change).
- Every request needs `Authorization: Bearer <token>`. Missing, unknown or revoked → HTTP 401, body `{"error":"unauthorized"}`.
- Reject any request whose `Host` header is not `127.0.0.1:<port>` or `localhost:<port>` (DNS-rebinding guard) → 403. Reject any request carrying an `Origin` header → 403. No CORS headers, ever.
- Tokens: 32 random bytes, shown once as `courier_` + base64url. Only the SHA-256 is stored. Compare in constant time.
- Sending (`send_message`) is a separate per-token permission, off by default.
- Tool names and input schemas match `protocol/mcp-tools.json` exactly (property names, types, enums, formats, `required`). Descriptions are ours and must never say "Beeper".
- `search_docs` is a stub that returns one fixed text: "Courier has no documentation search. Each tool's description is its documentation."
- Logs never contain tokens, message text, chat titles, names or numbers. Log tool name, duration and outcome only.
- Request body limit 1 MiB. `limit` arguments are clamped to 1–200 (default 50 for chats, 20 for messages).
- Connections are **off** until James turns on "Allow connections". The setting and the port survive restarts.
- Engine and app protocol version goes from 11 to **12**; `protocol/protocol.json` and both conformance tests are updated.
- Out of scope, recorded in the ledger: the reference app's REST API (`/v1`), its OAuth flow, remote (non-loopback) access, the Claude Desktop `.dxt` download and the Raycast installer (Raycast's extension needs the REST API).

## Review Focus

1. An unknown or malformed `chatID`, `messageID` or cursor → a tool error with a plain message (`isError: true`), never a crash or an HTTP 500.
2. A cursor from page 1 still works after new messages arrive: paging `before` returns older messages with no gaps or duplicates.
3. Port already in use → the Integrations pane says "Port 23390 is in use by another app", and the engine keeps running.
4. `focus_app` with a `draftAttachmentPath` that does not exist, is a directory or is not readable → tool error, and the app does not open a half-filled composer.
5. A token revoked while a client is connected → its very next request gets 401.

---

### Task 1: Token store and settings

**Files:** create `engine/internal/store/apitokens.go` and `apitokens_test.go`; a migration in `migrate.go` and `schema.sql`.

**Interfaces — produces:**
- Table `api_tokens(id TEXT PRIMARY KEY, name TEXT NOT NULL, hash BLOB NOT NULL UNIQUE, can_send INTEGER NOT NULL DEFAULT 0, created_ms INTEGER NOT NULL, last_used_ms INTEGER, revoked_ms INTEGER)`.
- `CreateAPIToken(ctx, name string, canSend bool) (APIToken, plaintext string, error)`
- `LookupAPIToken(ctx, plaintext string) (APIToken, error)`: `ErrNotFound` for unknown or revoked; also stamps `last_used_ms` (at most once a minute).
- `ListAPITokens(ctx) ([]APIToken, error)` (no revoked ones), `RevokeAPIToken(ctx, id)`, `SetAPITokenCanSend(ctx, id, bool)`.
- Settings keys `localapi.enabled` (default false) and `localapi.port` (default 23390) through the store's existing settings mechanism.

- [ ] Tests: `TestAPITokenStoredOnlyAsHash` (no column contains the plaintext), `TestAPITokenLookupRejectsRevoked`, `TestAPITokenNamesAreTrimmedAndCapped` (name trimmed, control characters removed, 64 runes max, empty → "Unnamed client"), `TestLocalAPISettingsDefaults`.
- [ ] Implement, run `bazel test //apps/desktop/courier/engine/internal/store:all`, commit.

### Task 2: The MCP server

**Files:** create `engine/internal/localapi/{server.go,tools.go,auth.go,server_test.go,tools_test.go,schema_test.go}`; wire it in `engine/cmd/courier-engine/main.go`.

**Interfaces:**
- Consumes: Task 1; the RPC server's method handlers, called in-process through one small adapter (`Dispatch(ctx, method string, params any) (json.RawMessage, error)`) so tools reuse `search.query`, `inbox.list`, `room.info`, `room.members`, `room.events`, `message.send`, `room.setArchived`, `reminder.set`, `reminder.clear`, `accounts.list`.
- Produces: `localapi.New(store, dispatcher, publisher, logger) *Server`, `(*Server).Apply(ctx, enabled bool, port int) Status` (starts, stops or moves the listener), `Status{Enabled bool; Port int; Listening bool; Error string}`.

**Tool behaviour** (results are one JSON text content block; IDs are Courier's own: account = login ID, chat = room ID, message = event ID):

| Tool | Does |
|---|---|
| `get_accounts` | `[{accountID, network, displayName, status}]` |
| `search` | `{chats, groupParticipantMatches, messages}`: first page of each from the FTS5 search |
| `search_chats` | chats filtered by every argument; `scope:"participants"` matches member names; `cursor`/`direction` page by last activity |
| `search_messages` | messages plus the chats they reference; `sender:"me"`/`"others"`/a user ID; `excludeLowPriority` defaults true, `includeMuted` true |
| `get_chat` | metadata, `participants` (cap `maxParticipantCount`, -1 = all, otherwise 0–500), `lastActivity` |
| `list_messages` | 20 messages per page, newest first, with `cursor`s for both directions |
| `send_message` | needs `can_send`; sends `text` as Markdown through `message.send`, optional reply; returns `{messageID, chatID, deeplink:"courier://chat/<chatID>"}`. Missing `text` → tool error. |
| `archive_chat` | `archived` defaults true |
| `set_chat_reminder` / `clear_chat_reminder` | through `reminder.set` / `reminder.clear`; `remindAtMs` in the past → tool error |
| `focus_app` | validates IDs and `draftAttachmentPath` (an existing, readable regular file), then publishes notification `app.focus {chatID?, messageID?, draftText?, draftAttachmentPath?}` |
| `search_docs` | the fixed stub text |

Chat JSON: `{id, accountID, network, title, type:"single"|"group", unreadCount, isArchived, isMuted, isPinned, isLowPriority, lastActivity (RFC 3339), participants?}`. Message JSON: `{id, chatID, accountID, senderID, senderName, isSender, timestamp, text, attachments:[{type, fileName, mimeType}], replyToMessageID?}`. Cursors are opaque base64url of `{t, id}`.

- [ ] `TestToolsMatchReferenceSchemas` (`schema_test.go`): reads `protocol/mcp-tools.json` and compares every tool's name and input schema (properties, types, enums, formats, nested `reminder` object, `anyOf` for `sender`, `required`) to `tools/list` from an in-memory client. Same set of names, no extras.
- [ ] `TestNoDescriptionMentionsReferenceApp`: no tool or property description contains "Beeper" (case-insensitive).
- [ ] Auth tests: no header 401; wrong token 401; revoked mid-session 401 on the next call; bad `Host` 403; any `Origin` 403; body over 1 MiB 413.
- [ ] `TestListensOnLoopbackOnly`: the bound address is `127.0.0.1`; `Apply` with a port already taken returns `Listening:false` with a plain error, and the engine keeps running.
- [ ] One test per tool against a store seeded through `fakenet`, including the Review Focus cases 1, 2, 4 and 5, `send_message` refused without `can_send`, and `limit: 10000` clamped to 200.
- [ ] Wire into `main.go`: on start, `Apply` with the saved settings. Run `bazel test //apps/desktop/courier/engine/...`, gazelle, commit.

### Task 3: stdio transport

**Files:** `engine/cmd/courier-engine/mcpstdio.go` and test.

- `courier-engine mcp-stdio [--port N]` reads the token from `COURIER_TOKEN`, then serves MCP on stdin/stdout by forwarding each request to `http://127.0.0.1:<port>/v0/mcp`. With no token, or with Courier not running or connections turned off, it exits 1 with one plain line on stderr (for example "Courier isn't accepting connections. Turn on Settings → Integrations → Allow connections.").
- [ ] `TestMCPStdioForwardsToolsList` (against a test server), `TestMCPStdioWithoutTokenExplains`. Commit.

### Task 4: Engine RPC for the app, and pairing

**Files:** `engine/internal/rpc/integrations.go` and test; `protocol/protocol.json`; `engine/internal/rpc/conformance_test.go`.

- Methods: `integrations.status` → `Status`; `integrations.update {enabled?, port?}` → `Status`; `integrations.tokens` → `[APIToken]` (never a hash or plaintext); `integrations.createToken {name, canSend}` → `{token: APIToken, secret}` (the only place a secret ever crosses the socket); `integrations.revokeToken {id}`; `integrations.setCanSend {id, canSend}`; `integrations.answerPairing {requestID, allow, canSend}`.
- Notification `integrations.pairRequest {requestID, clientName}`.
- Pairing endpoint `POST /v0/pair {"clientName": "..."}` needs no token, accepts loopback with the same Host/Origin rules, allows one pending request at a time (a second gets 429) and waits up to 120 s. Allow → 200 `{"token": "<secret>"}`; deny or timeout → 403.
- Protocol version 12. Notification `app.focus` from Task 2 is added here too.
- [ ] Tests: create/list/revoke round trip; pairing allow, deny, timeout and the 429; conformance with version 12. Commit.

### Task 5: Settings → Integrations pane and the pairing prompt

**Files:** replace the Integrations part of `app/Sources/Courier/PlusSettingsPane.swift` with `IntegrationsSettingsPane.swift`; `app/Sources/CourierCore/IntegrationsModel.swift`; the engine client's protocol types; snapshot tests.

- **Allow connections** toggle; **Port** field (1024–65535; invalid input does not save); a status line ("Listening on 127.0.0.1:23390", "Off", or the engine's error); **MCP endpoint** with a Copy button.
- **Approved connections**: name, created, last used, an "Can send messages" toggle, **Revoke** (with a confirm).
- **New connection…** sheet: name and "Can send messages". After create, it shows the secret once with copy buttons for: Claude Code over HTTP (`claude mcp add --transport http courier http://127.0.0.1:<port>/v0/mcp --header "Authorization: Bearer <secret>"`), Claude Code over stdio (`claude mcp add courier -e COURIER_TOKEN=<secret> -- <bundle>/Contents/Helpers/courier-engine mcp-stdio`), and Cursor and VS Code deep links that use the HTTP form. The text says it won't be shown again.
- **Pairing prompt** on `integrations.pairRequest`: a window-level alert, "“<clientName>” wants to read your chats in Courier.", buttons **Allow**, **Allow and Send Messages**, **Don't Allow**. The client name is shown as untrusted text (already cleaned by the engine).
- [ ] `IntegrationsModelTests` (status mapping, port validation, create shows secret once and clears it on dismiss), snapshot PNGs of the pane (off, on with two tokens, port-in-use error) and the new-connection sheet. Look at each PNG before committing.

### Task 6: `focus_app` in the app

**Files:** the app's engine-notification router; `ConversationWiring` or its equivalent.

- On `app.focus`: activate the app, open the main window, select the chat (if given), scroll to the message (if given), and put `draftText` and the attachment into that chat's composer without sending. An unknown chat leaves the app focused on the inbox.
- [ ] `FocusRoutingTests`: chat + draft fills the composer; attachment path is attached; unknown chat falls back to the inbox. Commit.

### Task 7: Docs and acceptance

- [ ] `apps/desktop/courier/docs/m5-acceptance.md`: each tool, auth case and the by-hand check: "In `~/.claude.json`, point `mcpServers.beeper` (or a new `courier` entry) at `http://127.0.0.1:23390/v0/mcp` with a Courier token; `get_accounts` lists all six networks; `search_messages` finds a known word."
- [ ] Ledger rows for the out-of-scope items listed above; this plan's status set to `completed` when the PR lands.
