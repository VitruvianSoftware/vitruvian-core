<!--
Copyright 2026 VitruvianSoftware
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Seed scenarios

Made-up chats that fill the Vitruvian Courier Test Copy, so a change to how chats look can be checked by hand or by
screenshot without signing in to any real account:

```sh
bazel run --config=macos-app //apps/desktop/vitruvian-courier/app:run_test_copy -- --seed group-threads
```

The same files feed the Swift view tests (`app/Tests/VitruvianCourierViewTests/SeedScenario.swift`), so what you see in
the running copy and what the snapshots draw come from one place.

**Only made-up names, numbers and messages.** Never paste a real chat in here.

## The scenarios

| Name | What it shows |
|---|---|
| `group-threads` | A busy WhatsApp group with two threads, replies and reactions, plus three one-to-one chats. The default for UI work. |
| `direct` | One long one-to-one conversation, both sides, with a reply and reactions. |
| `long-content` | Very long messages and chat names, URLs, multi-line text, a word with no spaces, emoji. |
| `multi-network` | Three accounts (WhatsApp, Slack, Telegram) and nine chats across them, some pinned, muted or unread. |
| `empty` | One account and no chats. |

## How a scenario gets into the app

The test copy bundles a separate engine binary, `vitruvian-courier-engine-seeded`, built with the Go build tag
`courierseed`. When the app starts it with `VITRUVIAN_COURIER_SEED=/path/to/scenario.json` in its environment, that engine
runs in-memory fake networks (named after the scenario's networks, so the icons and names match) instead of the
real bridges, and plays the scenario once into the empty data folder: it signs in each account, describes each chat,
then sends every message at its real past time, oldest first, followed by the reactions and read receipts. A file
named `seeded` in the data folder records that it has played; a later start on the same folder keeps the chats and
plays nothing again. The released app's engine is built without the tag and holds none of this code (the app's
`release_engine_has_no_seed_test` checks that).

## Format

```json
{
  "accounts": [ { "network": "whatsapp", "login": "seed-wa", "name": "Sam Seed" } ],
  "people":   [ { "id": "ann", "name": "Ann Example" } ],
  "chats": [ {
    "account": "seed-wa", "id": "grp-launch", "name": "Launch crew", "direct": false,
    "members": ["ann", "bo"], "pinned": false, "muted": false, "unread": true,
    "messages": [
      { "id": "m1", "from": "ann", "minutesAgo": 90, "text": "Hello",
        "replyTo": "m0", "thread": "m-root", "reactions": [ { "from": "bo", "emoji": "👍" } ] }
    ]
  } ]
}
```

- `accounts`: one sign-in each. `network` is a real network name (`whatsapp`, `slack`, `telegram`, …), `login` the
  account's ID inside the scenario, `name` what the account is called.
- `people`: everyone else, by an ID the chats and messages use, with the name the app shows.
- `chats`: `account` is a `login` above. `direct` is a one-to-one chat (its `members` is just the other person; its
  `name` may be left out and is then theirs). `pinned`, `muted` and `unread` default to false; a chat with
  `unread: false` is read up to its last message.
- `messages`: `from` is a person's ID or `"me"`. `minutesAgo` is when it was sent, counted back from when the
  scenario plays (or from `Fixture.now` in the view tests). `replyTo` and `thread` (the thread's root) name other
  messages of the same chat by `id`. `reactions` come after every message has been sent.

Every ID must be unique within its kind, every reference must exist, and `minutesAgo` must not be negative: the
engine and the view tests both refuse a scenario that breaks this, naming what is wrong.
