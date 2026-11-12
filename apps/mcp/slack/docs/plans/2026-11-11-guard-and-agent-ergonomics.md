---
status: completed
---
# mcp-slack: close allow-list gaps, then make agents' lives easier (PR 1)

Source: two independent reviews (Fable 5.1, Gemini 4 Carbon) on 2026-11-11, verified against the code by the lead.
Rust sources: apps/mcp/slack/rs/src/. Tests live inline (`#[cfg(test)]`) and run with
`bazel test //apps/mcp/slack:all`. No new Slack scopes. No tool renamed or removed; existing arguments keep working.

## Decision: production endpoint
The public HTTP endpoint stays as configured (no allow-list, user token, posts as James). It is reachable only
by James's Zitadel identity. This PR makes the allow-list actually hold WHEN it is set, and keeps destructive
tools off HTTP unless explicitly enabled. Do not change gitops/argocd/platform/mcp-slack/values.yaml values.

## A. Security (do first, each with a test that fails before the fix)
A1. Bot->user read fallback. `SlackClient::api()` (slack_client.rs ~591-597) silently retries a bot call with the
    user token on `not_in_channel`/`channel_not_found`. Keep that fallback ONLY when the channel guard is
    unrestricted (no allow-list). When an allow-list is configured, return the bot's error instead.
A2. `config.rs` ~282-285: `enforce_visibility: user_token.is_none()`. Change so visibility is enforced whenever an
    allow-list is configured (SLACK_CHANNEL_IDS non-empty), regardless of user token. `required` stays as is.
A3. Search (`search` ~1424-1441, used by slack_search_messages / slack_search_files): when an allow-list is
    configured, drop matches whose channel id is not allowed, and add `filtered_out: <n>` to the result.
    Unrestricted: unchanged.
A4. Canvas tools `edit_canvas`, `lookup_canvas_sections`, `delete_canvas` (~1632-1701): when restricted, run the
    same share check used for files (`assert_file_share_allowed` or the equivalent existing helper) before acting.
A5. Destructive tools on HTTP: new const `HTTP_WITHHELD_DESTRUCTIVE` in tools.rs = [slack_delete_canvas,
    slack_set_user_group_enabled, slack_set_user_group_members]. Withheld (not listed AND refused if called) on
    HTTP unless env `SLACK_HTTP_ALLOW_DESTRUCTIVE` is `true`/`1`. stdio unaffected. Wire it like the existing
    HTTP_WITHHELD_* lists and through config.rs. Add the env to the Helm chart as an optional value
    (apps/mcp/slack/deploy/chart: values.yaml default false, deployment.yaml env) — default off.
A6. Stale text (no behaviour): manifest.remote.json long_description claims HTTP refuses a user token; chart
    deployment.yaml (~130-133, ~146-149) and gitops/argocd/applications/mcp-slack.yaml comments say the same.
    Make them describe reality: user token optional on HTTP; with it the allow-list is optional.

## B. Paging and history
B1. slack_get_channel_history: add optional `oldest`, `latest` (Slack ts strings), `since` (relative: `30m`,
    `24h`, `7d`; converted to `oldest`; ignored if `oldest` given; invalid value -> clear error), `cursor`,
    `include_activity` (bool, default false: drop subtypes channel_join/channel_leave/group_join/group_leave,
    reuse UNREAD_IGNORED_SUBTYPES). Pass through `response_metadata.next_cursor` as top-level `next_cursor`.
B2. slack_get_thread_replies: add optional `limit` (default 50, max 200), `cursor`, `oldest`, `latest`;
    expose `next_cursor`.
B3. slack_search_messages / slack_search_files: add optional `page` (1-based) and `sort_dir` (`asc`|`desc`).

## C. Compact output by default
C1. Every tool result is serialised compactly (no pretty-print) on both transports
    (http_transport.rs ~916 uses to_string_pretty; find the stdio equivalent too).
C2. Strip noise from results by default, recursively on message and user objects: `blocks` (only when a
    non-empty `text` exists on the same message), `team`, `user_team`, `source_team`, `client_msg_id`,
    `user_profile`, `bot_profile`, `icons`, and every `image_*` / `avatar_hash` field inside `profile`.
    Keep everything else (text, ts, user, thread_ts, reply_count, reactions, files, attachments, edited, subtype).
C3. Every tool accepts optional `raw: true` to get the untouched Slack response. Add `raw` to every tool's
    input schema in one place (the list builder), not by hand per tool; strip `raw` before calling Slack.

## D. Small missing pieces
D1. New tool `slack_whoami`: calls `auth.test` with the bot token, and with the user token when present;
    returns `{bot: {user_id, team_id, ...}, user: {...}|null}`. Available on both transports.
D2. New tool `slack_remove_reaction` (channel_id, timestamp, emoji): `reactions.remove`, user token,
    guarded like slack_add_reaction, and added to HTTP_WITHHELD_WITHOUT_USER_TOKEN.
D3. slack_post_message: optional `thread_ts`, `reply_broadcast`, `unfurl_links`. slack_reply_to_thread: optional
    `reply_broadcast`, `unfurl_links`.
D4. slack_read_file accepts canvases (filetype `canvas` or `quip`, or mimetype `application/vnd.slack-docs`):
    download as today and return the content as text with a `format: "html"` marker. Same size cap.
D5. 429 handling in api(): check the HTTP status BEFORE parsing JSON (a 429 body may not be JSON). Retry at
    most 2 times, waiting min(Retry-After, 10s) each; then return the ratelimited error with `retry_after`.
    list_unread keeps its own patient wrapper.

## Out of scope (PR 2+)
Name resolution (#chan/@user), conversations.open, scheduled messages, Block Kit, delete message (needs
ownership check via whoami), channel admin, bookmarks edit/remove, mentions inbox.

## Acceptance criteria (user terms)
1. With an allow-list set, an agent cannot read, search or edit/delete canvases outside the listed channels, even when a user token is configured.
2. On the HTTP endpoint, delete-canvas and disable/replace-user-group are not offered unless SLACK_HTTP_ALLOW_DESTRUCTIVE is on.
3. An agent can read "the last 7 days" of a channel, page through it, and page through long threads; join/leave notices are gone by default.
4. Tool results are much smaller by default; `raw: true` returns the full Slack response.
5. An agent can ask who it is, remove a reaction, broadcast a thread reply, and read a canvas.
6. A rate-limited call waits briefly and retries instead of failing straight away.
7. Every existing tool name and argument still works unchanged; tool count is 43.

## AMENDMENT 2026-11-11 18:30 — no behaviour change for existing users (overrides A5, B1, B2, C above)
James's rule: his current experience must not change. Everything new is additive or opt-in.
- A5: keep the HTTP_WITHHELD_DESTRUCTIVE mechanism and the chart value (default false for NEW installs), BUT set
  `SLACK_HTTP_ALLOW_DESTRUCTIVE: true` for the existing deployment in gitops/argocd/platform/mcp-slack/values.yaml
  (add the key; do not touch other values), so the live endpoint keeps offering the same tools.
- B1: `include_activity` defaults to TRUE (today's behaviour: join/leave notices included). Agents can pass false.
- B2: send `limit` to Slack only when the caller passes it (no new default of 50).
- C: compact output is OPT-IN. Default output is exactly today's (pretty JSON, nothing stripped). Opt in per call with
  `compact: true`, or server-wide with env `SLACK_COMPACT_OUTPUT=true`. Rename C3's `raw` param to `compact`
  (bool, default from env, else false). Byte-for-byte: a call without `compact` returns what main returns today.
- A1-A4 only act when an allow-list is configured; the live endpoint and James's local stdio have none, so no change.
- D5 retries only affect calls that would otherwise fail with ratelimited; keep.
- Acceptance criterion 8: with today's config (no allow-list, user token, no new env), every existing tool returns
  the same output as main for the same input, and the HTTP tool list is today's 41 plus the 2 new tools.
