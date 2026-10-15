# Beeper Desktop 4.3.209: gap addendum to the feature spec

**What this is.** We checked all 1,454 English UI strings that do not appear word for word in the
three spec files. Most are already described in other words, or are small messages for features we
already cover. 85 strings point at **18 behaviours the spec does not describe**. This file lists
them, so they can be added to the spec. The spec files themselves were not changed.

**Evidence key.** **[O] Observed**: we read the string and the code around it in the shipped bundle.
**[I] Inferred**: our reading of what the code is for, not confirmed by running the app.

| Count | Bucket | Meaning |
|---|---|---|
| 772 | PARAPHRASED | Already described in the spec |
| 520 | DETAIL | A small message (error, toast, confirm, tooltip, plural, format) for a feature already in the spec |
| 85 | GAP | Points at behaviour the spec does not describe (18 features, below) |
| 77 | NOISE | Punctuation, units, weekday names, alt text, generic words |

The row-by-row classification is kept outside the repo, because it is a copy of the app's text catalogue. It can be regenerated from the installed app; see 04-coverage-ledger.md.

---

## G01. Bridges pane contents

**Belongs under:** 02 §1.7 Other panes, "Bridges" row (which currently says "list fields not
traced"), and 01 §17 Settings.

**What it does.** The Bridges pane splits bridges into two lists: cloud bridges and self-hosted
bridges. If the app has no bridge information yet, it says so. [O]

- **Bridge rows.** Each row shows the network icon, the bridge's current state, and how many
  accounts run on it. Clicking a row expands it to show when the bridge was created, why it is in its
  current state, what reported that state (when it wasn't the bridge itself), and any extra details. [O]
- **Bridge menu.** A "Bridge Actions" button opens a menu with these items: [O]
  - Open the bridge's bot room. If no bot room exists yet, the item creates one, and the new room's
    ID is copied for you. If the room can't be found, you are told to create it again.
  - Copy the bot room ID, copy the bridge ID, or copy all the bridge's details as JSON.
  - "Experimental: Add an account" through this bridge.
  - Delete the bridge, after a confirm. Beeper's own built-in chat bridge can't be deleted.
- **Account rows.** Under each bridge is a list of the accounts it runs. Each one shows the account's
  name on the network (or "No Profile" if it has none), its raw details, and its ID. If the account
  has an error, the row shows the error and the reason for it. [O]
- **Account menu.** Each account row has its own menu: open that account's settings, copy the
  account ID, or copy the account's ID on the network itself. [O]
- The bot room is a chat with the bridge's bot. [I] It is probably used to send the bridge text
  commands, as in standard Matrix bridges.

**Evidence:** "%d account", "Bridge Actions", "Open bot room", "Create a bot room", "Creating bot
room...", "Bot room created! Room ID is copied to clipboard.", "Copy bot room ID", "Bot room ID
copied to clipboard!", "We couldn't find the bot room. Please try creating it again.", "Copy bridge
ID", "Copy bridge info as JSON", "Delete bridge", "Created:", "Reason:", "Source:", "Info:",
"No Profile", "No bridge data available", "Copy Remote ID", "Remote ID copied to clipboard!"

---

## G02. Per-network connection-mode limitations list

**Belongs under:** 01 §16 On-Device vs Cloud, and 03 §1.1 / §1.4.

**What it does.** When you add an account and pick where it runs (in Beeper's cloud or on this
Mac), the picker shows a "Not supported:" line. The line lists the features that the network loses
in the chosen mode. [O] The lists are fixed in the app: [O]

| Network | Cloud: not supported | On-device: not supported |
|---|---|---|
| WhatsApp | online status | online status |
| Facebook Messenger | online status, polls | push notifications, online status, polls |
| Instagram | disappearing messages, online status, polls | media captions, disappearing messages, online status, polls |
| Telegram | online status | online status |
| iMessage | — | push notifications, disappearing messages |
| Google Voice | — | push notifications, deleting messages, starting a new chat |
| Google Chat | starting a new chat, disappearing messages, online status, polls | — |
| X | disappearing messages | disappearing messages |
| Slack | online status | — |
| Discord | starting a new chat, online status, polls | — |
| LinkedIn | online status | online status |
| LINE | editing messages, typing indicators, polls | — |
| Tumblr | starting a new chat, online status | starting a new chat, online status |

That the "Not supported:" label goes with these lists is [I]: the label sits in the same picker
part of the code. The spec already mentions "a limitations list", but not what is in it. A rebuild
should show the same warnings.

**Evidence:** "Not supported:", "Online status", "Online status and polls", "Push notifications,
online status, and polls", "Disappearing messages, online status, and polls", "Media captions,
disappearing messages, online status, and polls", "Push notifications and disappearing messages",
"Push notifications, delete messages, and start a new chat", "Start a new chat, disappearing
messages, online status, and polls", "Start a new chat, online status, and polls", "Edit messages,
typing indicators, and polls", "Start a new chat and online status"

---

## G03. Plan limits, and what a lapsed plan takes away

**Belongs under:** 02 §1.7 Beeper Plus, 01 §17 Subscription, 01 §16 Account limits, and 03 §2.1.

**What it does.**
- **Three separate limits.** A plan caps the number of accounts per network, the total number of
  accounts, and the number of merged chats. [O]
- **Where the numbers come from.** Each limit comes from a server-sent feature value. A special
  value means "unlimited". [O]
- **Plan comparison.** The comparison shows each limit for your current plan and for the plan you
  would upgrade to. Rows that improve on upgrade are highlighted. [O]
- **When a paid plan lapses:** [O]
  - Accounts above the Free limits may be disabled after 24 hours, newest-added first.
  - A custom app icon reverts to the default, with a prompt to renew.
- The spec mentions account limits and "unlimited merged chats and accounts". It doesn't describe
  the per-network cap, the order in which accounts are disabled, or the icon reverting.

**Evidence:** "%d Account Per Network", "Unlimited Accounts Per Network", "%d Total Account",
"Unlimited Total Accounts", "%d Merged Chat", "Unlimited Merged Chats", "In 24 hours any accounts
above the Free account limits may be disabled, in order of most recently added.", "Beeper has
reverted to the default app icon — renew your subscription to keep your custom app icon."

---

## G04. Honeycomb chat cards for mentions, unread and quiet chats

**Belongs under:** 01 §4 Home, empty state and Honeycomb featured cards.

**What it does.** Besides the recommendation, event and stats cards, the Honeycomb carousel has
cards about individual chats. Each one is in one of these states: [O]

- **failed**: a message didn't send
- **sending**: a message is still sending
- **draft**: you have an unsent draft
- **mention**: you were mentioned, with the number of unread mentions
- **unread**: the chat has unread messages
- **quiet**: you haven't talked in a while. The card reads "It's been <time> since you talked", or
  "a while" when the app doesn't know how long.

The mention, unread and quiet cards use the same reply pill, so you can answer from the card. [O]
The spec covers the failed, sending and draft pills only. The quiet card is a "get back in touch"
nudge, and it needs a rule for how long counts as quiet. [I] We did not find that rule.

**Evidence:** "%d unread mention", "Quiet", "It's been %s since you talked"

---

## G05. Merged-chat target switcher in the composer

**Belongs under:** 01 §9a Merged chats, and 01 §6 Composer.

**What it does.** In a merged chat (one conversation made of chats from several networks), the
composer shows an avatar for the chat that your message will go to. [O]

- **Switching.** Hovering the avatar opens a card headed "Switch chats". The card lists each chat
  in the merge, with a subtitle, and you pick the one to send through. [O]
- **Other uses.** Outside merged chats, the same control appears with the heading "Switch Chat".
  [I] It may also pick the sending account.
- **One-time hint.** The first time it is relevant, a small bubble says "Click the avatar to change
  chat.". The app records that the hint was shown, and dismissing it hides it for good. [O]
- **Default chat.** The merged-chat section in Chat Info marks one of the chats as the default. [O]

The spec explains how to build and edit a merged chat. It doesn't say how you choose which network
a message goes out on.

**Evidence:** "Click the avatar to change chat.", "Switch chats", "Switch Chat"

---

## G06. Media viewer sender filter and sort order

**Belongs under:** 01 §8 Media viewer window, and 02 §3.4.3.

**What it does.** The media viewer has a filter menu with two settings: [O]

- **"Sent By"**: All, You or Others.
- **"Sort by"**: Newest or Oldest.

Caption search waits a moment after you stop typing before it runs. The live tabs are labelled
Media, Links and **Docs**, not "Files" as the spec says. Correct the tab name when this is merged in. [O]

**Evidence:** "Sent By", "Sort by"

---

## G07. Search home and result sections

**Belongs under:** 01 §12 Search and Command Bar (message search), and 02 Part B Search.

**What it does.** Search (⌘K) groups its results into sections, in this order: [O]

1. Recent chats
2. Last archived
3. Chats
4. In Groups
5. Bookmarks
6. Media
7. Messages

- **Before you type.** Search shows recent chats. It also shows the chat you archived most recently,
  in its own "Last archived" section, so you can find it again straight away. That section only
  appears if the chat isn't hidden, isn't already in the recent list, and isn't the chat you have
  open. [O]
- **"In Groups".** This section lists people who match your search because they are in a group
  with you, even when you have no direct chat with them. [O] [I] for the "even when" part.
- **"Bookmarks".** Bookmarked messages get their own section. [O]
- **Expanding.** Each section can be expanded with "Show more". The Messages section has the
  partial-matches toggle instead. [O]

**Evidence:** "In Groups", "Last archived"

---

## G08. Room-encryption choice when starting a Matrix group

**Belongs under:** 01 §11 Start new chat (New Group), and 03 §1.3 Beeper native chats.

**What it does.** When you start a group on Beeper's own Matrix network, a "Room encryption"
dialog appears before the group is created. It has an "Encrypted" switch. [O]

- The dialog explains what the switch means for people you invite later:
  - **Encrypted:** they can't see earlier messages.
  - **Not encrypted:** they can.
- The confirm button is "Start group chat". The switch is locked while the group is being created. [O]
- [I] We could not see which way the switch starts.

**Evidence:** "Room encryption", "Encrypted" (new-group toggle), "People invited later cannot see
earlier messages.", "People invited later can see earlier messages."

---

## G09. Per-message disappearing countdown and read-started timers

**Belongs under:** 01 §5 Conversation view (disappearing messages), and 01 §9 Chat Info.

**What it does.** A disappearing message carries its own timer. The timer can be one of two kinds:
it starts when the message is sent, or it starts when the message is read. [O]

- **Before the timer starts** (read-started timers only), the message says when it will disappear:
  [O]
  - Your own message in a one-to-one chat: so long after the recipient reads it.
  - Your own message in a group: so long after someone in the group reads it.
  - A message you received: so long after you mark it read.
- **Once the timer is running**, the message shows a countdown ("Disappears in <time>"). [O]

The spec only describes the chat-level timer setting and the notes when it changes.

**Evidence:** "Disappears %s after the recipient reads it", "Disappears %s after someone in the
group reads it", "Disappears %s after you mark it read", "Disappears in %s"

---

## G10. Voice-note played state and Mark as played

**Belongs under:** 01 §8 Media (Audio), and 01 §5 Conversation view.

**What it does.** Audio attachments can carry a played or unplayed status that comes from the
network. [O]

- A played note is labelled "Played", or shows when it was played.
- An unplayed note has a "Mark as played" button. The button tells the network that the note was
  played, without playing it.

[I] This matches networks that show "played" receipts for voice notes, such as WhatsApp.

**Evidence:** "Played", "Played %s", "Played at %s", "Mark as played"

---

## G11. Inline edit-history expander on edited messages

**Belongs under:** 01 §5 Conversation view (status line, `MessageEditHistory.tsx`).

**What it does.** On an edited message, the "Edited" label can be a button. [O]

- **Opening it.** Clicking it opens the message's earlier versions right below the message. The
  button then reads "Hide Edits".
- **The tooltip.** It shows the original text ("Originally …").
- **When it is plain text.** When there is no history to show, "Edited" is plain text.
- **Thread replies.** A reply in a thread that was also posted to the main chat is marked as sent
  to the chat as well.

The spec names the component but not what it does.

**Evidence:** "Edit history", "Hide Edits", "Originally %s"

---

## G12. Problem report can attach the selected message details

**Belongs under:** 01 §20 Feedback, help and support, and 01 §5 (unknown events).

**What it does.** When you report a problem with a message selected, the report form has an
"Include Message Details" checkbox. The checkbox attaches the message's underlying data to the
report. [O]

- **No message selected:** the checkbox is "Include Latest Message Details" instead.
- **Copy button:** a button copies the same details to the clipboard.
- **Unreadable messages:** a message the app can't display has a "Click here to report" link. The
  link opens the report form with that message attached and a description already filled in: "This
  <network> message didn't render".

**Evidence:** "Include Message Details", "Include Latest Message Details", "Copy message details",
"Copy latest message details", "Click here to report to %s team.", "This %s message didn't render"

---

## G13. Step-up re-authentication by emailed code

**Belongs under:** 01 §15 Onboarding (recovery-key reset), and 02 §1.7 Profile (Sign-In Methods).

**What it does.** Some account actions need you to prove who you are again. When the server asks
for that, the app shows an "Authentication Required" window. [O]

- **The window.** It says to "Check your email" for a sign-in code. You type the six-digit code and
  press Next.
- **One at a time.** Only one of these windows can be open. A second request brings the existing
  window to the front.
- **Triggers seen:** [O]
  - resetting the recovery key or the encryption identity, during onboarding and later
  - managing sign-in methods
- **If you cancel:** the action fails with "Re-authentication is required to continue". [O]
- **After a reset:** you are asked to try again with the new recovery key. [O]

**Evidence:** "Authentication Required", "Check your email", "This action requires
re-authentication. Please check %(email)s for your sign in code.", "Re-authentication is required
to continue", "Authentication is required to manage sign-in methods."

---

## G14. Incoming-call notification overlay

**Belongs under:** 01 §19 Notifications UI (or 01 §1 App shell), and 03 §3.4.

**What it does.** Beeper can't take calls itself. When a call comes in on a connected network, an
overlay card appears. [O]

- **The card.** It shows a voice or video call icon, the caller's avatar and name, and a dismiss
  button.
- **If that network's own app is installed on the Mac,** the card has an "Open <app>" button. The
  button launches that app so you can answer, and closes the card.
- **If the app isn't installed,** the card says "Open <app> to answer".
- **Several calls** stack in the overlay, one card each.

The spec only mentions call types as chat-list preview badges.

**Evidence:** "Open %s to answer" (shown with the "Open %s" button, which is covered elsewhere)

---

## G15. Insert as Draft on received messages

**Belongs under:** 01 §7 Message context menu, and 02 §3.4.2.

**What it does.** Selected messages that someone else sent have an extra menu item, "Insert as
Draft", next to Copy. It puts the message's text into your composer and moves the cursor there, so
you can edit it and send it as your own. Your own messages don't have this item. [O]

**Evidence:** "Insert as Draft"

---

## G16. Archive, Low Priority and Hide have different return rules

**Belongs under:** 01 §3 Chat list (row actions), 01 §18 cross-cutting chat states, and 02 §2.6.

**What it does.** The command bar explains each way of removing a chat from the inbox in a
subtitle, and the empty states say the same thing: [O]

- **Archive** hides the chat only until a new message arrives. Then it comes back to the inbox.
- **Low Priority** hides the chat from the inbox for good.
- **Hide** removes the chat from the inbox (a hidden feature).

[I] So a new incoming message un-archives a chat, but does not undo Low Priority or Hide. The spec
describes each action but not this rule. A rebuild needs it to decide what a new message does to a
chat's place.

**Evidence:** "Hides chat until new messages received", "Archive chats to hide them until new
messages are received", "Hides chat from your inbox", "Removes from inbox"

---

## G17. Relaunch prompt after a system timezone change

**Belongs under:** 01 §1 App shell, global states and system banners.

**What it does.** The app remembers the system timezone offset. When the system timezone changes,
it shows a toast that stays until you act on it. The toast says the app must be relaunched to use
the new timezone, and has a "Relaunch now" button. The toast shows again after each new change. [O]

**Evidence:** "%s must be relaunched to use your new timezone"

---

## G18. Challenge attachments in server-driven login forms

**Belongs under:** 01 §16 Adding accounts (`BridgeV2AuthComponent.tsx`).

**What it does.** A bridge's login step can include attachments above the form fields, as well as
the fields themselves. [O]

- **Images** are shown inline. Their fallback description is "Captcha image".
- **Audio clips** get a small audio player.

So a bridge can ask you to solve a captcha, or listen to a code, as part of logging in. [I] We don't
know which networks use this in practice. The bridge sends the steps when you log in, so the bundle
doesn't show them.

**Evidence:** "Captcha image", "Your browser does not support the audio element."

---

## Strings we were less sure about

- **"Social Account"** and **"Some of your accounts are still on Beeper’s Cloud"** appear only in
  the translation table. We found no code that uses them, so we marked them DETAIL with a note. They
  may belong to a feature that is turned off or was removed.
- **"Last sent message"** is defined as a search section name, next to "Last archived". The search
  code never lists it, so we marked it DETAIL rather than GAP.
- **"thread archived", "notification clicked", "message scheduled"** are labels for local usage
  counters in the dev-only usage stats view. We marked them NOISE.
- **X login passcode errors** (for example "Passcode isn't set up for X Chat") suggest the X login
  also asks for the X Chat passcode. The spec already lists "passcode locked" among the login
  errors, so we marked them DETAIL. If the passcode is a separate login step, it would belong in
  03 §1.3 for X.
