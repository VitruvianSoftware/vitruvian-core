---
status: approved
date: 2026-10-18
---

# Extension settings you can find, and a HomeSpeaker island you can tune

## Why

James changes what HomeSpeaker announces, and from where, many times a day. He
does most of it from the island, but some switches are missing there. On
2026-10-18 he could not find Beeper's "Announce: Every message" at all. It
sits in the settings sheet under the "Chat & Slack" section. You only reach that
section through a "Section" pop-up at the top of the sheet, and then you have to
scroll. A family message went unannounced because of it.

His words: missing the section "will likely cause others to miss those hidden
config options", and "I just want more [on the island], especially toggles like
the one I was trying to find earlier."

There are two parts to this, and they can ship separately:

1. **The HomeSpeaker island** gets the settings James changes often.
2. **Every extension's settings sheet** in Vitruvian shows all its sections on
   one page, with jump links and search, in place of the Section pop-up.

## Goals

- Everything James tunes day to day is on the island: what gets announced,
  from which chat app and Beeper network, how much is spoken, and when quiet
  hours run.
- No setting in any extension's settings sheet is hidden behind a control you
  have to know about. Every section's name is visible without clicking
  anything, and typing part of a setting's name finds it.
- Older Vitruvian builds and older extensions keep working. A new control
  falls back to something an old app can draw, as the protocol already
  requires.

## Non-goals

- One-time setup stays in the settings sheet: tokens, Google sign-in, the
  Google Cloud project, speaker discovery. The island keeps its current
  setup-only flow for first run.
- No per-chat (per-conversation) announce rules. That is a separate idea,
  still parked.
- No change to how messages are read or spoken, apart from the new Beeper
  network filter.

## Anti-goals (would count as failure even if it works)

- An island so tall it needs scrolling on a 14-inch laptop with every source
  on. James chose option A below *because* it adds only a few lines, and only
  for the switches that are on.
- Settings that exist in two places and can disagree. The island and the sheet
  read and write the same saved value.
- Search that silently misses settings because an extension labelled them in
  a way search can't see.

## Part 1: the HomeSpeaker island (James chose layout A)

Each new option sits indented directly under the switch it belongs to, and
shows only while that switch is on. Nothing folds, and there's nothing to open.

| Where | New on the island | Control | Saved as (exists today) |
|---|---|---|---|
| Under **Broadcasting** | Speak: Headline, Summary or Full | menu (`choice`) | `speech_length` |
| Under **Quiet hours**, while it's on | From and Until, in half-hour steps | two menus, as `DoorPages.quietHourBlocks` already draws them | `quiet_hours_start` / `_end` |
| Under **Beeper**, while it's on | Announce: Direct messages and mentions, or Every message | menu | `beeper_announce` |
| Under **Beeper**, while it's on | One chip per Beeper network; tap to mute or unmute that network | **new** multi-pick control (see below) | **new** setting |
| After the chat apps | Skip messages I sent | switch | `mute_own_messages` |

The order of the existing island stays the same otherwise: say field,
Broadcasting, Quiet hours, speaker, volume, Mute, Speak on, coding agents, chat
apps, recent, More settings….

### Beeper networks (new behaviour)

Today Beeper is all or nothing. The new setting lists the networks that are
**muted**, and every other network is announced. A network Beeper adds later is
therefore announced until James mutes it.

- The chips show every network HomeSpeaker knows about: the ones it reads,
  the ones it skips, and any James has muted, so a muted network stays visible
  and can be unmuted. On James's Mac today these are WhatsApp, Signal,
  Telegram, Google Messages, Google Chat and Beeper's own chat (checked with
  Beeper's account list, 2026-10-18).
- Today the status file only has display names, in two lists:
  `beeper_networks` (read) and `beeper_skipped_networks` (skipped). It is blank
  while the monitor isn't running. *Claude's call:* the status file gains
  each network's stable key (the monitor already has `accountID` and, when
  Beeper reports it, `bridgeType`), alongside its display name. The muted
  setting stores those keys. While the monitor isn't running, the island
  shows the saved mutes, plus a caption saying the rest appear once Beeper is
  being read.
- A network that is already skipped because HomeSpeaker reads it directly
  (Slack or Google Chat with their own switch on) shows as a disabled chip
  that says why. Muting it would change nothing, and the chip should not
  pretend otherwise.
- The settings sheet's Beeper section gets the same control, so it is not
  island-only. *Claude's call:* so does the HomeSpeaker Mac app's own Settings
  window (`Sources/HomeSpeaker/SettingsView.swift`), which has its own Beeper
  Announce menu today. All three read and write the same saved value.
- How a network is named and matched is left to the builder. Reuse whatever
  the monitor uses to fill `beeper_networks`. The muted list must survive a
  network's display name changing, so key on something stable if one exists.

### The multi-pick control (protocol addition)

The protocol has 13 kinds of block, and none of them picks several options at
once. Add one: a set of labelled options, each on or off, with an optional
disabled state and reason per option. It reports the full set of values that
are on.

- It is gated like other additions: the app advertises it through
  `ProtocolFeature`, and the extension only sends it to an app that says it
  can draw it.
- **Fallback (builder's choice of mechanism):** an older app must still be
  able to change every network. One switch per network is acceptable.
- The name, shape and schema follow the existing blocks in
  `packages/vitruvian-sdk`: the schema (`messages.schema.json`), the
  generated message code, all five kits (Swift, TypeScript, Python, Rust and
  Go), the examples, and the conformance suite (`conformance/`).

## Part 2: every extension's settings sheet (James chose layout B)

The sheet becomes one page with every section on it, in order. Across the top
is a row of section names that jumps to a section and lights up the one you're
in as you scroll. Above that is a search field. Typing keeps only the matching
settings, from every section, each one labelled with the section it came from.
Clearing the search restores the full page.

- **This is Vitruvian's job, not each extension's.** Vitruvian builds the jump
  row and does the search from what the extension sends, so every extension
  gets it, including third-party ones.
- **It covers the whole sheet** (*Claude's call*). An extension's sheet holds
  more than the extension's own page. Vitruvian adds settings from the
  manifest, the "Show in island" switches, and the commands list. Search and
  the jump row cover all of it, so they live in the sheet itself
  (`ExternalToolsSection.swift`), not only in `BlockTreeView`. A settings page
  that is a web page can't be searched. Its section still appears in the jump
  row, and a search that can't look inside it says so rather than showing
  nothing.
- **Sections need to be told apart from sub-headings.** Today a heading block
  only has text, so "Beeper" (a sub-heading) and "Chats" (a section) look the
  same. The protocol needs a way to mark a section. The builder picks how:
  a heading level, or a section container. It must degrade on an older app to
  what that app shows today, a plain heading.
- **What search matches:** a setting's title, its help text, and its
  sub-heading. Typing "announce" must find Beeper's Announce menu. Where a
  sub-heading matches, its whole group shows. *Claude's call:* today
  switches and menus have no caption of their own (captions are separate text
  blocks, some after one control and some after a group), so step 1 adds an
  optional help-text field to controls, and HomeSpeaker moves its per-control
  captions into it. For extensions that don't use the field, search treats a
  caption directly after a control as that control's, which is a best guess.
- **Extensions that use the Section pop-up** switch
  to sending every section at once, marked as sections, *when the app
  supports it*. On an older app they keep the pop-up.
- **Rename** HomeSpeaker's "Chat & Slack" section to **"Chats"**, in the
  extension and in the Mac app's own Settings window. It covers Slack, Google
  Chat and Beeper.
- HomeSpeaker is the only extension that uses a Section pop-up today
  (checked 2026-10-18).
- **Page size.** Sending every section at once may approach the protocol's
  block limit (`UILimits.maxBlocks`, 200). *Claude's call:* measure it
  first. If HomeSpeaker goes over, raise the limit for apps that advertise the
  new section feature, and keep the old limit for older apps.
- Very long sections are allowed. The jump row is what makes them navigable.
  Vitruvian keeps the search and jump row visible while the page scrolls.

## Constraints

- All the protocol rules in `packages/vitruvian-sdk/protocol/README.md` hold:
  additions are optional, a newer block degrades to its fallback, and an
  extension never sends an app something it hasn't said it can draw.
- HomeSpeaker's island and sheet are built in
  `apps/desktop/home-speaker/Sources/HomeSpeakerToolCore/Pages.swift` and
  `DoorPages.swift`. Vitruvian draws blocks in
  `apps/desktop/vitruvian/Sources/Vitruvian/UI/ToolPanels/BlockTreeView.swift`.
- Never run a built HomeSpeaker binary against the real environment while
  testing. It re-points the live hook (see the repo's HomeSpeaker
  `AGENTS.md`).
- The usual repo path applies: worktree, Bazel targets, a PR per shippable
  part, auto-merge armed.

## Order

1. Protocol: the multi-pick block, the section marker and the help-text
   field (and the larger block limit, if step 3's measurement needs it), with
   schema, generated code, all five kits, examples and conformance. One PR.
2. Vitruvian: draw both, and build the one-page sheet with the jump row and
   search. Ships in a Vitruvian release.
3. HomeSpeaker: the island additions, the Beeper network setting and filter,
   the sections sent at once, the rename. Ships in a HomeSpeaker release, and
   works (with fallbacks) on a Vitruvian that doesn't have step 2 yet.

Step 3 doesn't depend on step 2 shipping first: the island items that use
existing controls (Speak, quiet times, Announce, Skip messages I sent) can go
out at once.

## Left to the builder

- Exact names and wire shapes of the two protocol additions.
- How Vitruvian lays out and styles the jump row and search field, within the
  existing settings sheet.
- Chip styling, wrapping and the disabled-chip wording.
- How the monitor matches a Beeper message to a muted network.
