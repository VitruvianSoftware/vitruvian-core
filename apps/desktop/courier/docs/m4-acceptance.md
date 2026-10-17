<!--
Copyright 2026 VitruvianSoftware
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Courier milestone 4: acceptance list

This is the checklist for milestone 4, one section per part. Each part's section is written by that part's plan, so later parts add theirs below. Use Courier all day, and tick a line when you have seen that thing work. Write down anything wrong, with no names, numbers or message text.

Each ledger line is one row of the inventory (`docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/ledger.tsv`), kept under its row name so you can look it up there. The text after the dash says, in plain words, what Courier does now. A tick means "I saw this work", not "the code exists".

The same rule as milestone 3 holds for the day: do not open the same chat in the other chat app while testing Courier. It would send a read receipt.

## Part 4.1: organise the inbox

Spaces, labels, filters, pins, archive, low priority, hide, reminders, message requests and the settings that shape the chat list. Courier's own organising stays on this Mac: archive, labels, spaces, low priority, hide, reminders, marked unread, drafts and auto-archive rules never reach a phone. What does go out is:

- a pin and a mute, on WhatsApp and Telegram only;
- a read mark when you read a chat, on every network, as opening a chat always has;
- accepting a message request, on Signal only.

Look for nothing else on a phone.

### Before you start

- Install the build with `bazel run --config=macos-app //apps/desktop/courier/app:install`. Your chats and networks from milestone 3 stay as they are.
- A pin or mute made on the phone is taken in only when a chat first reaches Courier. If you want to see that, pin one chat on your phone before it first arrives.
- Settings are in Settings ▸ Inbox (⌘,).

### Check these first

Some things could not be tried by hand while the app was being built, because the Mac's screen was locked. Look at these before anything else. The tests cover the logic behind each one, but nobody has seen them on screen yet.

- [ ] Each built-in space and each filter shows its empty state. Pick every space (Inbox, Reminders, Requests, Low Priority, Send Later, Archive) and every filter in the Filter menu on an account with nothing in it, and check the title and line against this table:

| Where | Title | Line |
|---|---|---|
| Inbox | You're all caught up | New messages show up here. |
| Unread | No unread chats | (none) |
| Drafts | No drafts | A chat shows up here when you start a message and don't send it. |
| Unanswered | Nothing waiting for your answer | (none) |
| No reply | No one owes you a reply | (none) |
| DMs | No one-to-one chats | (none) |
| Groups | No group chats | (none) |
| Unknown | No chats from unknown numbers | (none) |
| Muted | No muted chats | (none) |
| Hidden | No hidden chats | Hide a chat to take it out of your inbox without leaving it. |
| Archive | Nothing archived | Archive a chat to clear it from your inbox. It comes back when someone writes. |
| Low Priority | Nothing in Low Priority | Chats here stay out of your inbox, even when new messages arrive. |
| Requests | No message requests | Messages from people you haven't chatted with before show up here. |
| Reminders | No reminders | Right-click a chat and choose Remind Me. It comes back to your inbox at that time. |
| Send Later | No scheduled messages | Messages you schedule show up here. |
| Label | No chats with this label | Right-click a chat and choose Label. |

- [ ] Creating a label adds its space to the space bar. View ▸ New Label… opens the window; the new label shows with its colour and icon.
- [ ] Edit Spaces: dragging a space below the "Hidden" divider hides it from the space bar, and the toast says "Sidebar updated". With nothing hidden, the list reads "No hidden spaces".
- [ ] ⌘S hides the space bar and shows it again.
- [ ] ⌘A in the chat list selects all the chats in the list. Edit ▸ Select All must not swallow it. If it does, Chat ▸ Select All Chats is the fallback; say so.
- [ ] The popovers take clicks. ⌘L (Remind Me) shows the suggested times and Custom…, and ⌘⌥A (Filter by Account) shows the accounts. Click an item in each.
- [ ] ⌘⇧] and ⌘⇧[ move to the next and previous space on the space bar, any kind of space, skipping hidden ones. After the last space ⌘⇧] goes back to the first, and before the first ⌘⇧[ goes to the last.
- [ ] A notification's buttons work. With Courier in the background, a new message's notification offers Mark as Read, Reply, Remind in 1 Hour and Remind in 8 Hours. Try each one. Then set a reminder a few minutes ahead, close the window, and check that the reminder notification arrives on time.

### Keys

- [ ] `hotkey` Chat: Toggle Archive: ⌘E archives the selected chat and brings it back if pressed again. Plain E does the same when no chat is open and you are not typing. A pinned chat will not archive; the menu item says "Unpin a chat to archive it". An archived chat comes back to the inbox when someone else writes to it.
- [ ] `hotkey` Chat: Toggle Pin: ⌘P pins the chat to the top of the list. The menu item says whether the phone is told ("Also pinned on your phone when it’s connected") or not ("Pinned on this Mac only").
- [ ] `hotkey` Chat: Archive All Read: ⌘⇧E asks "Archive N read chats?". After yes, the read chats leave the inbox, pinned ones stay, and a toast offers Undo. Undo brings back only the chats that action archived.
- [ ] `hotkey` Remind Later: ⌘L opens the Remind Me menu on the selected chat: Last Used, suggested times, Custom…, and Dismiss Reminder. Picking a time sets the reminder.
- [ ] `hotkey` Toggle Space Bar: ⌘S hides or shows the space bar, and View ▸ Hide Space Bar does the same.
- [ ] `hotkey` Switch First 9 Spaces Modifier: ⌘1 to ⌘9 open the first nine visible spaces. A hidden space is skipped.
- [ ] `hotkey` Switch First 9 Chats Modifier: ⌃1 to ⌃9 open the first nine chats in the list.
- [ ] `hotkey` Select Next Account: ⌘⇧] moves to the next space on the space bar, any kind of space, skipping hidden ones. After the last space it goes back to the first.
- [ ] `hotkey` Select Previous Account: ⌘⇧[ moves to the previous space on the space bar the same way. Before the first space it goes to the last.
- [ ] `hotkey` Cycle Filters: ⌥Tab steps through Unread, Drafts, Unanswered, DMs and Groups, then back to All.
- [ ] `hotkey` Filter: Unread: ⌘⇧Y turns the Unread filter on and off and keeps any other filter you have set.
- [ ] `hotkey` Filter By Account: ⌘⌥A shows a popover of accounts; picking one opens that account's space.
- [ ] `hotkey` Chat: Toggle Mark As Read: ⌘⇧U marks the selected chat read, and marks a read chat unread. A chat marked unread shows a dot in its row. Milestone 3 only marked read.

### Settings

All of these are in Settings ▸ Inbox. Each takes effect at once, and is still set after you quit and open Courier again.

**Chat list**

- [ ] `setting:appearance` Show sidebar: "Show the space bar" shows and hides the space bar, the same as ⌘S.
- [ ] `setting:appearance` Use regular style for pinned chats: "Show pinned chats as full rows" turns the compact pinned avatars into full rows.
- [ ] `setting:appearance` Show number of unread messages: "Show unread counts" shows or removes the count on each row.
- [ ] `setting:appearance` Show message previews: "Show message previews" shows or hides the preview line.
- [ ] `setting:appearance` Compact chat list: "Compact chat list" makes the rows shorter.
- [ ] `setting:appearance` Show network icons: "Show network icons" shows or hides the small network badge on each row.
- [ ] `setting:appearance` Colorize network icons: "Colour network icons" colours the badge or makes it grey. It is greyed out while network icons are off.
- [ ] `setting:appearance` Chat action button (on hover) should: "Button on a chat you point at" chooses Archive, Mark Read or Unread, Menu, or None. Pointing at a row shows that button, and it does that.
- [ ] `setting:appearance` On double-clicking a chat: "Double-clicking a chat" chooses Archives it, Marks it read or unread, Mutes or unmutes it, Moves it to Low Priority or back, or Does nothing. The default is Does nothing. Double-click a row and it does what you chose. "Open in New Window" comes in part 4.5.

**Archiving and reminders**

- [ ] `setting:general` Default for remind later: "Remind me" chooses If no reply or Always. A reminder set from the menu follows it. With "If no reply", the reminder only brings the chat back if you have not written to it since you set it.
- [ ] `setting:general` Archive after setting reminder on chat: "Archive a chat when I set a reminder on it" archives the chat as you set the reminder. It comes back to the inbox when the reminder is due.
- [ ] `setting:general` Mark unread chats as read on archive: "Mark chats read when I archive them" marks an unread chat read as it is archived. Your networks are told it was read.
- [ ] `setting:general` After archive: "After archiving the open chat" chooses Open the next chat, Open the previous chat, Close the chat, or Stay on it. Archive the open chat and it does that.
- [ ] `setting:general` Archive: the Archiving section's one-off tool, "Archive [all / read] chats older than [3 days to 1 year]". The button says how many chats it would archive, asks first, archives them, and the toast offers Undo. Pinned chats stay.
- [ ] `setting:general` After mark as read/unread: "After marking the open chat read or unread" chooses the same four choices. Mark the open chat read or unread and it does that.

**Notifications**

- [ ] `setting:notifications` Message request notifications: "Notify me about message requests" is on by default. With it on, a message request raises a notification; turn it off and requests stay quiet.

### Menus

- [ ] `menu:View` Hide Space Bar: View ▸ Hide Space Bar hides the space bar, and the item then reads Show Space Bar.

### Components

- [ ] `component` Badge.tsx: A space's icon in the space bar shows a badge when it has unread chats. Hovering gives its title and "%d chats" ("%d reminders" in Reminders, "%d requests" in Requests).
- [ ] `component` BrandTypingIndicator.tsx: A chat that someone is typing in shows "Name is typing…" in place of the preview, or "N people are typing…" for several.
- [ ] `component` CheckboxPlus.tsx: In selection mode each row has a tick mark that shows whether it is selected.
- [ ] `component` CreateLabelBrowserWindow.tsx: View ▸ New Label… opens a window with a title field, a row of 12 colours and a grid of 24 icons. It reads "Pick a name, a colour and an icon. This is how the label looks everywhere in Courier."
- [ ] `component` CreateLabelNudgeIcon.tsx: While there are no labels, the space bar shows a dashed "New label" button. It goes away once you have one.
- [ ] `component` Drag.tsx: In Edit Spaces, a space can be picked up and moved to another place in the list.
- [ ] `component` Drop.tsx: Dropping it above the "Hidden" divider shows the space, and below it hides the space. The Inbox cannot be moved and stays first.
- [ ] `component` EditLabelsBrowserWindow.tsx: View ▸ Edit Labels… lists the labels, each with Edit… and Delete…, and New Label…. Delete asks "Delete this label?" and says the chats stay.
- [ ] `component` EditSidebar.tsx: Edit Spaces has a "Search Spaces" field that narrows the list, and each space has an eye button that hides or shows it from the keyboard.
- [ ] `component` EditSidebarBrowserWindow.tsx: Edit Spaces (from the View menu or any space's menu) opens as its own window, titled "Edit Spaces". Opening it again brings the open one forward. Each change saves at once and says "Sidebar updated".
- [ ] `component` GroupAvatar.tsx: A group chat with no picture shows a group mark instead of initials.
- [ ] `component` IconColorPicker.tsx: Colours and icons in the label window can be chosen by click, and moved through with the arrow keys.
- [ ] `component` PinnedThreadListItem.tsx: Pinned chats sit at the top of the list as small avatars, or as full rows when "Show pinned chats as full rows" is on.
- [ ] `component` SelectionModeActions.tsx: In selection mode the action bar offers Mark as Read, Mark as Unread, Move to Inbox or Low Priority, Remind Me, Dismiss Reminder, Archive or Unarchive, and More (Mute, Hide, Label).
- [ ] `component` SelectionModeHeader.tsx: The list header reads "%d chat selected" with Select All and Cancel. Esc leaves selection first, before anything else closes.
- [ ] `component` Skeleton.tsx: Opening Courier shows grey placeholder rows until the first page of chats arrives.
- [ ] `component` ThreadPreviewMedia.tsx: A chat whose newest message is a picture shows a small thumbnail in its row.
- [ ] `component` Toasts.tsx: Archive, reminder and bulk actions show a message at the bottom of the chat list, with Undo where there is one. ⌘Z does the same as pressing Undo while the toast shows.
- [ ] `component` TypingIndicator.tsx: The typing line in a row has animated dots.
- [ ] `component` UnknownAvatar.tsx: A chat with no name shows "?" as its avatar and "Unnamed chat" as its title.
- [ ] `component` UnreadMentionIndicator.tsx: A chat where you were mentioned and have not read shows "@" in its row.

### Commands

These 13 are registered in Courier for the command bar (⌘J), which part 4.7 builds. They have no tick box here: they are "registered; shown in ⌘J by 4.7". The ones with a menu item or key above are checked there.

- `command` Archive all chats
- `command` Archive all chats older than a week
- `command` Archive all read chats
- `command` Mark all chats as read
- `command` Next Chat
- `command` Show message requests
- `command` Toggle space bar
- `command` Edit spaces
- `command` Filter Chats
- `command` Filter by folder type
- `command` Filter by type
- `command` Filter by account
- `command` Toggle chat selection mode

### Not ledger rows

The inventory has no row for these, but they are what this part was built to do. Look at the first five before the rest. They are the five things the plan was most worried about.

**The five things to check**

- [ ] Archived chats come back only when they should. An archived chat comes back to the inbox when someone else writes to it. It does not come back for an older message that was only loaded late, a message you sent from your phone, a reaction or an edit. A chat in Low Priority or Hidden stays where it is when new messages arrive.
- [ ] A reminder fires once, even if Courier was not running. Set a reminder an hour ahead and close the window: it still fires on time. Quit Courier, or let the Mac sleep, past the time: at the next chance the reminder fires once, not never and not twice.
- [ ] A very large inbox stays quick. With thousands of chats, the first page shows at once, the Unread filter is quick, and scrolling down loads more without any chat repeating or going missing.
- [ ] Undo undoes exactly what it did. "Archive all read chats" on a big inbox, then Undo: it brings back those chats and leaves alone the ones that were archived before, and any chat that a new message already brought back.
- [ ] A phone that will not take a change does not break it. Pin a WhatsApp chat while WhatsApp is offline: it is pinned in Courier at once, stays pinned, and shows no error. Courier does not try again; the phone catches up the next time you change that chat.

**What the chat menu does** (right-click a chat, in this order)

- [ ] Accept / Decline: only on a message request. Accept moves the chat out of Requests. Decline hides it on this Mac, and the person is not told.
- [ ] Archive / Unarchive: help text reads "Clears the chat from your inbox until someone writes again."
- [ ] Mute / Unmute: ⌘⇧M. A greyed line under it says what else mutes the chat, such as a label or an account.
- [ ] Mark as Read / Mark as Unread: help text on Mark as Unread reads "On this Mac only".
- [ ] Pin / Unpin: ⌘P.
- [ ] Hide / Unhide: help text reads "Takes the chat out of your inbox without leaving it. Filter ▸ Hidden shows it again."
- [ ] Move to Low Priority / Move to Inbox: help text reads "Keeps the chat out of your inbox, even when new messages arrive." Low priority and hidden chats do not notify.
- [ ] Label ▸: ticks the labels the chat has, and New Label… makes another.
- [ ] Remind Me ▸: Last Used, the suggested times, Custom… with a date picker, and Dismiss Reminder. A fired reminder shows a "Reminder" badge on the row, and the chat comes back to the inbox.
- [ ] Begin Selecting: starts selection with that chat selected. Selecting also starts with x on a chat you point at, Shift-click, ⇧J and ⇧K, Command-click, or ⌘A.

**The filters, the sorts and the rest**

- [ ] The 15 choices in the Filter menu (it reads "Filter (N)" while N filters are on): All, Unread, DMs, Groups, Drafts, Unanswered, No reply, From unknown numbers, Muted, Hidden, Archived, Low Priority, Requests, Reminders, Send Later. Each one narrows the list to what its name says. Several together narrow it more. "Clear all filters" puts it back.
- [ ] The 4 sorts in Display Options: Newest message first, Oldest message first, Reminder soonest, Reminder latest. Pinned chats stay at the top in every sort.
- [ ] Low priority: Move to Low Priority takes a chat out of the inbox and into the Low Priority space. It is behind a plan; on a build without one it reads "Available with a plan".
- [ ] Hide: a hidden chat leaves the inbox and shows only under Filter ▸ Hidden.
- [ ] Auto-archive rules: on a label or an account space, "Archive [all / read] chats older than [3 days … 1 year]" archives what matches, says "%d chat(s) here already match this rule.", and has an "Archive %d chat(s)" button. In Settings ▸ Inbox, "Archive chats by themselves" (Never / After I reply / After I read them) with a delay archives a chat by itself that long after. Both are behind a plan.
- [ ] Message requests: a first message from someone new shows in the Requests space and in the inbox row as "Message request" with Accept and Decline buttons.
- Mark as Unread stays on this Mac. A chat marked unread shows its dot here and is never sent to a phone, on any network. WhatsApp's bridge turns an unread mark the wrong way round (checked up to its newest release), so Courier keeps the mark to itself. Do not look for it on a phone.

### Carried to later parts

Not in 4.1, and not expected to work yet:

- Show WhatsApp Communities / Telegram Topics as separate spaces: part 4.5.
- "Open in New Window" as a choice for double-clicking a chat, and opening a chat or a space in its own window: part 4.5.
- Editing the reminder time suggestions: part 4.6, with Settings.
- The §22 icon-library rows: part 4.7.
- Send Later has its space and filter, and they are empty until part 4.3.
