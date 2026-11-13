---
status: completed
---
# vitruvian-slack-mcp PR 2: names, DMs and scheduled messages

Follow-up to `2026-11-11-guard-and-agent-ergonomics.md` (PR #4616).

## Hard rule: no behaviour change for existing callers

Every existing tool, called with the arguments it accepts today, returns exactly what it
returns on `main`. Everything below is either a new tool or a new input form that no
current caller can send (a `#` or `@` prefix: Slack IDs never start with either).
`tools/list` gains the new tools and nothing else changes in it.

## A. Name resolution (`#channel`, `@user`)

Wherever a tool takes `channel_id`, also accept `#name` (e.g. `#general`).

- Bare IDs (`C…`, `G…`, `D…`) take the existing path untouched: no extra API call.
- `#name` resolves through `conversations.list` (public + private the token can see,
  paged until found), matching `name` exactly, case-insensitive. Cache name→ID in-process
  for the client's lifetime (bounded; a miss re-lists once).
- **Allow-list:** when `channel_guard` is restricted, resolve ONLY against the allowed
  channel IDs (`conversations.info` on each allowed ID, cached), never list the workspace.
  A name that isn't an allowed channel returns the same refusal as a disallowed ID, with
  no hint whether the channel exists.
- Not found (unrestricted): error `channel_not_found: #name`.
- Resolution happens once, at dispatch, before the guard check, so the guard always sees
  a real ID.

Wherever a tool takes a user ID (`user_id`, `users` lists), also accept `@handle`.

- Resolves through `users.list` (paged, cached) matching `name`, then
  `profile.display_name`, then `profile.real_name`, exact and case-insensitive.
  More than one match → error listing the matching IDs; never guess.
- User lookup is not channel-scoped, so the allow-list does not limit it (same as the
  existing `slack_get_users`).

## B. New tools

| Tool | Slack method | Token | HTTP lists |
|---|---|---|---|
| `slack_open_dm` | `conversations.open` | user | withheld without user token |
| `slack_schedule_message` | `chat.scheduleMessage` | user | withheld without user token |
| `slack_list_scheduled_messages` | `chat.scheduledMessages.list` | user | withheld without user token |
| `slack_delete_scheduled_message` | `chat.deleteScheduledMessage` | user | withheld without user token **and** destructive |

- `slack_open_dm(users)`: 1–8 user IDs or `@handles`; returns the DM/group-DM channel
  ID. When restricted, return the ID only if it is on the allow-list; otherwise the
  standard refusal.
- `slack_schedule_message(channel_id, text, post_at, thread_ts?, reply_broadcast?)`:
  `post_at` is a Unix timestamp (seconds) or an ISO 8601 date-time with offset; reject
  anything in the past or more than 120 days out before calling Slack. Guarded like
  `slack_post_message`.
- `slack_list_scheduled_messages(channel_id?, cursor?, limit?)`: when restricted, drop
  entries for disallowed channels and report `filtered_out` (same pattern as search).
  Cursor in `response_metadata.next_cursor`, as today.
- `slack_delete_scheduled_message(channel_id, scheduled_message_id)`: guarded.

All four accept `compact` like every other tool.

## C. Docs

README: new tools, the `#`/`@` forms, updated counts (47 total; HTTP with destructive
on 46, off 42 — recount from code, don't trust these). Mark this spec completed.

## Tests (must fail without the change)

- Bare ID → no `conversations.list` / `users.list` call (mock asserts call count 0).
- `#name` resolves; restricted guard resolves only among allowed IDs and refuses others
  with the identical refusal text used for IDs.
- `@handle` resolves; ambiguous handle errors.
- `open_dm` restricted and DM not allowed → refusal, no ID leaked.
- `schedule_message` rejects past / >120 days; ISO and Unix both accepted.
- `list_scheduled_messages` filters and sets `filtered_out` when restricted.
- `tools/list` for each HTTP configuration has the expected names; the existing tool
  entries are byte-identical to `main`.

## Out of scope (PR 3+)

Block Kit, delete own message (ownership check via `whoami`), channel admin, bookmark
edit/remove, mentions inbox.
