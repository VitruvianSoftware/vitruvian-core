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

## Part 4.2: search

Search finds chats, people and messages, all on this Mac. Nothing you type is sent to a phone or a network. Your recent searches are kept on this Mac only, and "Clear Recent Searches" removes them.

**What search does not find in this part.** Look for none of these, and do not report them as bugs:

- Emoji and punctuation. They are skipped, and a search made of only emoji says so.
- One letter, in messages. Messages need at least two letters to search, so a one-letter word finds nothing. Chats and people search from the first letter. A single Chinese, Japanese, Korean or Thai character does count.
- Messages a network never sent Courier. Courier can only search the history it has on this Mac. Older history appears as each network sends it.

### Before you start

- Install the build with `bazel run --config=macos-app //apps/desktop/courier/app:install`. Your chats and networks stay as they are.
- The first time Courier opens after this update, it adds your older messages to search in the background. Search works at once, and new messages are found straight away. Until the older ones are in, a line at the top of the results says "Still adding older messages to search. Some results may be missing."
- Do not open the same chat in the other chat app while you test. It would send a read receipt.

### Check these first

Not yet checked by eye. The tests cover the logic behind each one. Look at these before anything else.

- [ ] ⌘F works while you are typing a message. Click into the message box of an open chat, type a few words, then press ⌘F. Search opens for that chat ("In: <chat> ×" shows). There is no Find bar and no beep, and your half-written message is still there.
- [ ] Right-click a chat in the list. "Search…" is in the menu, after Pin and before Hide, and it opens search for that chat.
- [ ] The keyboard comes back when search closes. Check each of these, and type a letter straight away without clicking:
  - press Esc out of a search made with ⌘F in a chat where you had a half-written message: typing carries on in that message;
  - search from the same chat you are in, open a result, and the message box has the keyboard;
  - press ⌘K and then Esc with the chat list in front: the list has the keyboard again, and E, x, ⇧J and ⇧K work without a click.
- [ ] ⌘K brings the window forward. Close the main window and press ⌘K: the window comes back with search open. With Settings or Edit Spaces in front, press ⌘K: the main window comes forward with search open, and it does not close again.
- [ ] Jumping to an old result lands on it. Search for a word from months ago and open that message. The chat opens at the message, in the middle of the view, not at the bottom. The message is tinted, and the tint fades away over about three seconds.
- [ ] "Jump to latest" works. Once you have jumped to an old message, a "Jump to latest" button shows. It gets a small dot if something new arrives while you are away. Pressing it, or sending a message, goes back to the newest message. Scrolling down to the bottom brings in newer messages without the view jumping.
- [ ] New messages do not move the view while you are away. Open an old message, let a new one arrive, and the view stays where it was.
- [ ] ⌘K opens search with the home view, and the cursor is already in the field, so typing starts straight away.
- [ ] The keys inside search work:
  - ↑ ↓ and ⌃P ⌃N move the selection, and the list scrolls to follow it;
  - Tab and ⇧Tab jump from one section to the next;
  - Return opens the selected row;
  - Esc steps back one thing at a time: first the filters, then the text, then the "In:" chat, then it closes;
  - ⌫ with nothing typed removes the "In:" chat;
  - ⌘⌫ clears the text.
- [ ] Choosing a recent search puts its words in the field and searches them. Check where the cursor ends up (it should be at the end of the words).
- [ ] Clicks do the right thing. Clicking the dimmed window outside closes search. Clicking inside it does not. A filter chip opens its menu, and afterwards you can still type in the field.
- [ ] The panel is the right size. It is about 640 points wide, grows as rows are added, and stops at about 70% of the window's height, then scrolls.
- [ ] A message's matching words are in bold, also when an emoji comes earlier in the line.
- [ ] Photos and videos show as small pictures, four to a row, under "Media".
- [ ] Each filter narrows the results, and its × clears it. Check Accounts, Type, Sent / Received, Chats and Time. "Show partial matches" adds a "Partial matches" divider, then messages that have only some of your words. "Hide partial matches" takes them away.
- [ ] Search looks right in light and in dark: the background, the tint on the opened message and the filter chips.
- [ ] Window keys still act while the search panel is open. For example, ⌘E archives the chat that is open behind the panel. Check that this is what you expect, and say if it gets in the way.

### Keys

- [ ] `hotkey` Search: ⌘K opens search over every chat. Pressing it again closes it. If another Courier window is in front, it brings the main window forward first.
- [ ] `hotkey` Search: Room: ⌘F searches the chat that is open. With no chat open it does the same as ⌘K. It also works while the cursor is in the message box.

### Menus

- [ ] `menu:Beeper` Search…: Courier ▸ Search… (⌘K), just after Settings. The Chat menu also has "Search in Chat…" (⌘F).

### Components

- [ ] `component` GeneralSearch.tsx: ⌘K opens a search panel over the window. It has a field, a row of filters, and the results in sections. The field reads "Search chats, people and messages", or "Search this chat" inside one chat.
- [ ] `component` GeneralSearchResults.tsx: Before you type, the panel shows Recent (chats you opened lately), Last archived (the chat you archived last), and Recent searches. Once you type it shows Chats, In groups, Media and Messages, whichever have something. A section with more rows has "Show more".
- [ ] `component` JumpToMessage.tsx: Opening a message result opens its chat at that message, tinted, and "Jump to latest" goes back. See the first list for what to look for.
- [ ] `component` SearchIcon.tsx: A magnifying glass sits at the left of the search field.
- [ ] `component` OutlineSearch.tsx: The same magnifying glass, in its outline style. Courier uses one system symbol for both, so there is nothing different to look for.
- [ ] `component` search.tsx: The search icon in the library. Same as above.
- [ ] `component` SelectMessageCommand.tsx: A message row shows who sent it ("You" for yours), the chat, a place tag if the chat is not in the inbox, the date, and the line of text with the matching words in bold. Today shows a time, this year shows day and month, and older shows the whole date. Return opens it.
- [ ] `component` SelectRecentSearchCommand.tsx: A recent search shows as a clock and the words. Return searches them again. "Clear Recent Searches" sits in that section's title row.
- [ ] `component` CommandBarUser.tsx: A person row (under "In groups") shows their picture, name and network, and "In <group>", "In <group> and 1 other group" or "In <group> and N other groups". It lists people you have no direct chat with. Opening one opens the newest group you share. Starting a direct chat comes with part 4.5.

### Commands

These 2 are registered in Courier for the command bar (⌘J), which part 4.7 builds. They have no tick box here: they are "registered; shown in ⌘J by 4.7". The keys above are checked there.

- `command` Search chats
- `command` Search messages in all chats

Courier also registers "Search messages in current chat" (⌘F). It has no ledger row of its own, and is off while no chat is open.

### Not ledger rows

The inventory has no row for these, but they are what this part was built to do. Look at the first five before the rest. They are the five things the plan was most worried about.

**The five things to check**

- [ ] Deleted and edited words go away. Delete a message, then search for a word only it had: it does not come back. Edit a message to different words: search finds the new words and not the old ones. A chat that is gone leaves none of its words or its name in search.
- [ ] Anything you type is safe. Try quotes, `*`, `-`, `(`, the words AND, OR and NOT, `NEAR(`, a single `"`, a colon, a very long paste, and emoji on their own. None gives an error or freezes the app. Each is searched as ordinary words, and emoji alone shows the calm line "Search for a word or a name. Emoji and punctuation aren’t searched." Words in double quotes find that exact run of words.
- [ ] Accents, capitals, width and scripts do not get in the way. "cafe" and "CAFE" both find "café". Full-width letters find the same word in normal letters. A word in Chinese, Japanese, Korean or Thai is found by part of it as well as the whole of it. A Hindi word is found whole, and is not cut in two. (Only try the scripts you have messages in.)
- [ ] A big history stays quick after the update. With a very large chat history, Courier opens as fast as before. New messages can be searched at once, older ones fill in behind, and quitting halfway through carries on where it stopped when you open Courier again. With thousands of chats, each search still answers quickly.
- [ ] Jumping to an old message is steady. Open a message from last year: the chat opens at it, tinted, not at the bottom. New messages arriving meanwhile do not move the view. "Jump to latest" and sending a message both go back to the newest. (This is the same as the jump lines in the first list.)

**The sections, in order**

- [ ] Before you type: Recent, Last archived, then Recent searches. The chat you are in is left out of Recent and Last archived. Last archived also leaves out hidden chats. Inside one chat, home shows only recent searches, or "Search this chat’s messages." when there are none. What Last archived leaves out is Courier's best reading: if the other chat app behaves differently, say so.
- [ ] As you type: Chats, In groups, Media, then Messages. A section with nothing in it is left out. Inside one chat there are only Media and Messages. In groups lists only people you have no direct chat with. That is Courier's best reading: if the other chat app behaves differently, say so.
- [ ] Messages and media come newest first, not best match first. Chats and people whose name starts with your first word come first, then the one with the newest message.
- [ ] Every chat is searched, wherever it is: inbox, Archive, Low Priority, hidden and Requests. A result outside the inbox carries a tag: "Archived", "Low priority", "Hidden" or "Request".
- [ ] Your own messages are found too. The Sent / Received filter narrows them.
- [ ] The Chats section stops at 100 chats and says "Showing the first 100 chats. Type more to narrow it down."
- [ ] The foot of the Messages section reads "Courier searches the messages on this Mac. Older history appears as each network sends it."

**The filters**

- [ ] Accounts: lists your linked networks with ticks. Pick one or more and results come from only those. The chip shows the choice, or "N accounts".
- [ ] Type: Text, Photos, Videos, Voice and audio, Files, Links, Stickers. Several can be ticked.
- [ ] Sent / Received: Anyone, Sent by me, Received.
- [ ] Chats: All chats, Direct messages, Groups. Inside one chat this chip is hidden.
- [ ] Time: Any time, Last hour, Last week, Last 30 days, Last year. The time is counted back from now.
- [ ] An active chip shows its choice and an ×, and the × clears just that filter. "Clear Filters" appears when nothing matches and clears all of them.

**Partial matches**

- [ ] Search wants all of your words. The last word you are still typing matches as a start of a word ("meet" finds "meeting") unless it is in quotes or followed by a space.
- [ ] "Show partial matches" lists, after every full match, messages that have some of the words but not all. They sit under a "Partial matches" divider. That is Courier's best reading of what partial matches are: if the other chat app behaves differently, say so.

**What the panel says**

| When | What it shows |
|---|---|
| Home, nothing recent | Find any chat, person or message on this Mac. |
| Home inside one chat, no recent searches | Search this chat’s messages. |
| Waiting more than a third of a second | Searching… |
| No results | No matches for “…” and, under it, Check the spelling, or try fewer words. |
| No results, with filters on | Nothing matches these filters. and a Clear Filters button |
| One letter, for messages | Under Chats: Type one more letter to search messages. |
| Only emoji or punctuation | Search for a word or a name. Emoji and punctuation aren’t searched. |
| Older messages still being added | Still adding older messages to search. Some results may be missing. |
| Search broke | Search isn’t working right now. and a Try Again button |

- [ ] Each line above shows in its place, word for word.
- [ ] Results do not change by themselves. If a new message arrives while search is open, the rows stay as they are. The next key you type, or the next filter you change, searches again.
- [ ] Filters work with nothing typed. Received with Last week, or Direct messages on its own, lists those messages, newest first. "Nothing matches these filters." shows only when there really are none.

**Good to know**

- While you read an older part of a chat (after opening an old result), new messages in that chat don't show a banner. The dot on "Jump to latest" tells you something new came.
- Recent searches are kept in Courier's settings on this Mac, not in the encrypted message database. "Clear Recent Searches" removes them.

**The chat menu**

- [ ] Right-click a chat ▸ Search…: opens search with "In: <chat> ×" in the field and "Search this chat" as the hint. The chat menu's order is now Pin, Search…, Hide.

### Carried to later parts

Not in 4.2, and not expected to work yet:

- The Bookmarks section of search: part 4.3, with bookmarks.
- Search suggestions, and searching inside Settings: part 4.6.
- "Open recently viewed chats", and the Commands ⌘J switch inside the panel: part 4.7. The search commands above are registered and wait for it.
- Starting a direct chat with someone from "In groups": part 4.5.
- Searching the words in a photo's caption from the media viewer: part 4.5.
- Search tools for other programs (MCP): milestone 5.
- The "find a chat" page of the hotkey tutorial (ThreadSearchPage): not planned.

## Part 4.3: message actions

Formatting, mentions, edit, unsend, delete, forward, polls, threads, bookmarks, quick replies, undo send, send later and the disappearing timer. What leaves this Mac for a network is:

- an edit, an unsend, a poll and a poll vote, on the networks that take them (the table below says which);
- formatted text, mentions, replies and thread replies;
- a forward, which is a new copy of the message with no sign of where it came from;
- a disappearing-timer change, on WhatsApp, Signal and Telegram.

Stays on this Mac: bookmarks, edit history, quick replies, send later while it waits, undo send while it holds, and Delete for Me. The one exception is Google Messages, where Delete for Me also removes the message from the phone.

### Before you start

- Install the build with `bazel run --config=macos-app //apps/desktop/courier/app:install`. Your chats and networks stay as they are.
- Settings are in Settings ▸ Messages (⌘,), a new tab beside Inbox.
- Out of the box: undo send is Off, click-to-undo is off, double-click on a message is Reply, "Press ↑ in the composer to" is Move focus to the message list, and the formatting bar is on.
- Undo send, click-to-undo and the send-later default say "Available with a plan" on a build without one.
- Do not open the same chat in the other chat app while testing. It would send a read receipt.
- Never test on a real person's chat. Use a chat with yourself or a test account.

### Check these first

Nobody could try these by hand while the app was built, because the build had no screen to look at. The tests cover the logic. Look at these before anything else.

- [ ] ⌘C with part of a code block selected copies only that part. If it copies the whole message, say so.
- [ ] Changing a disappearing timer leaves a note in the chat, in Courier's words. Check it both ways: change it in Courier, and change it on the phone. The inbox row and the notification never show the network's own English for it. Someone else changing it does not notify and does not mark the chat unread.
- [ ] A call shows in Courier's words, never the network's English ("Incoming call. Use the WhatsApp app to answer.", "Started a video call", "Ended the video chat (1 minute)"). Call yourself from another phone on WhatsApp, Signal and Telegram, once answered and once not. The chat shows a centred line with a phone or camera ("Incoming call", "Missed video call", "Call ended") and, in a group only, the caller's name. The inbox row and the notification say the same. Someone else's call marks the chat unread and notifies once: as it rings, or when it was missed. "Call ended", declined and dropped show in the chat but don't mark it unread, notify or bring it back from the archive. A call you make counts as your reply for "If no reply". A Telegram call you make shows "Call not answered" or "Voice call ended", and it does not mark the chat unread. A Telegram group video chat shows "Video call started" and then "Video call ended". Only Telegram says voice or video, and only Telegram says missed.
- [ ] Taking back a reaction on a real WhatsApp one-to-one chat works. If it does not, you should see "Couldn’t unsend", never a reaction that looks gone but is still there.
- [ ] A formatted message looks right on the other side. Send bold, italic, a link, a list and a quote on WhatsApp, Signal, Telegram and Slack. Spacing may collapse where the network uses HTML. A message with no formatting arrives exactly as you typed it.
- [ ] Quit Courier while a message is on hold. After you open it again, the message either went out or shows "Not sent" with Retry. It is never silently gone, and quitting never hangs for more than about 15 seconds.
- [ ] Click to undo, double-click and single-click selection do not fight. With undo send on, click a held message and it comes back. Double-click does what Settings says. A single click only selects.
- [ ] Do the by-hand run on the installed build, once, start to end:
  - format a message and see it drawn back in the chat;
  - edit it and open its history;
  - unsend one;
  - set undo send to 5 seconds, send, and undo it;
  - schedule one two minutes ahead, close the window, and watch it arrive;
  - create a poll and vote;
  - open a thread and act on a reply: copy, delete for me, bookmark, edit history.

### The five things to check

These are the five things this part was most worried about. Look at them before the rest.

- [ ] A change the network refuses never looks done. Edit or unsend while the phone is offline, or past the network's limit. A refused edit puts the old words back in the chat and in search. A refused unsend brings the message back in the chat, the inbox row and search, and says "Couldn’t unsend". It never looks deleted to you while everyone else still has it. An unsend that is too old is refused before anything is sent.
- [ ] Undo at the last moment does one thing. Set undo send to 5 seconds, send, and press ⌘Z right as the time runs out. Either nothing was sent and your words are back in the box, or it was sent and Undo says it already went. Never both, never neither. Quitting during the wait loses nothing.
- [ ] Send later survives quit, sleep and restart. Schedule a message a few minutes ahead and quit, or let the Mac sleep past the time. It goes out once at the next chance: not never, not twice. If it is more than an hour late it waits as "Missed its time while Courier was closed" with Send Now, Reschedule and Delete. With "If no reply", a message from them first cancels it: "Canceled: they wrote first".
- [ ] Plain text stays plain, and formatting reads well where a network can't show it. Send these and check them on the other side: 2*3*4, snake_case_name, <b>hi</b>, #1, C:\path, a web address with underscores, emoji, and right-to-left text. Each arrives exactly as typed. Then send a bold, linked, mentioned, listed message to Google Messages. It should read well as plain text, with no stray marks.
- [ ] A disappearing message never outlasts its timer. Set the shortest timer the network allows (Signal has 30 seconds, counted from when it is read). Let the Mac sleep past the time and wake it. The message is gone from the chat, the inbox row and search, even though the network's own clean-up is still asleep.

### What to expect on each network

Courier reads this from each network's own list of what it allows. A button that can't work is greyed, and its help text says why in Courier's words. No error codes reach you.

| | WhatsApp | Signal | Telegram | Google Messages | Slack |
|---|---|---|---|---|---|
| Edit your message | For 15 minutes | For 24 hours, up to 10 edits | No limit shown | Not offered | Yes, unless the workspace turns it off or limits it |
| Unsend | For 2 days | For 24 hours | Yes | Not offered | Yes, unless the workspace forbids it |
| Delete for Me | This Mac only | This Mac only | This Mac only | "Delete from This Mac and Your Phone" | This Mac only |
| Reply | Yes | Yes | Yes | Yes in RCS chats, not in SMS chats | Becomes a thread reply |
| Threads | Community announcement groups only | No | No | No | Every chat |
| Polls | Yes, 2 to 12 options, one or many answers | Yes, 2 to 10 options, one or many answers | Not offered | Not offered | Not offered |
| Disappearing timer | 24 hours, 7 days, 90 days, from sending | Off, or 30 seconds up to 4 weeks, from reading | 1 day up to 1 year, from sending | Not offered | Not offered |
| Mentions | Yes | Yes | Yes | Sent as "@Name" text | Yes, and @room |
| Formatting | Bold, italic, strike, code, quote, lists, links | All of them, with quote, lists and links in part, plus spoiler | All of them, lists in part, plus spoiler | None: sent as plain text | Bold, italic, strike, code, quote, lists, links, no spoiler |

- [ ] Each cell above holds on the real network. Check at least Edit, Unsend and Reply on every network you have.
- [ ] Google Messages never says "unsent". It only offers "Delete from This Mac and Your Phone".
- [ ] In a Slack chat, and in a WhatsApp community announcement group, Reply reads "Reply in Thread…" and opens the thread pane.
- [ ] On Telegram, Google Messages and Slack, Create Poll… is greyed with "Polls aren’t available on" and the network's name. A poll someone sends you on WhatsApp or Signal shows as a poll. A Telegram poll shows as text.
- [ ] The same for everything else greyed: the help text names the network and the reason, in plain words.

### Keys

- [ ] `hotkey` Message: Edit: ⌘T edits the selected message, or your newest message that can still be edited. A message that can't be edited shows greyed in the menu, with why. A timer note can't be edited.
- [ ] `hotkey` Message: Forward: ⌘⇧F opens "Forward message" for the selected message. With none selected, a toast says "Select a message to forward".
- [ ] `hotkey` Message: Quote or Edit Selected Message: Return, with a message selected and the box empty, edits it if it is yours and replies to it if it is someone else's. Where replies are thread replies, it starts a thread reply.
- [ ] `hotkey` Message: Open First Link: ⌘⇧H opens the first web address in the selected message in the browser.
- [ ] `hotkey` Message: Quick React: ⌘⇧R reacts to the selected message with the emoji chosen in Settings ▸ Messages.
- [ ] `hotkey` Message: Send Later: ⌘⇧L opens the Send Later picker for what is in the box.
- [ ] `hotkey` Message: Send Message and Archive: ⌘↩ sends, then archives the chat.
- [ ] `hotkey` Show Replies: ⌘↓ opens the replies of a selected thread root. On any other message, ⌘↓ still jumps to the newest message, and the menu item says which.
- [ ] `hotkey` Composer: Undo Pending Send: ⌘Z takes back a held message in the open chat. With none held, ⌘Z does what it always did: undo the last chat action, or undo typing. ⌘⇧Z sends the held messages now, or redoes.
- [ ] `hotkey` Composer: Bold: ⌘B bolds the selected words. The Message ▸ Format menu lists it.
- [ ] `hotkey` Composer: Italic: ⌘I.
- [ ] `hotkey` Composer: Strikethrough: ⌘⇧X.
- [ ] `hotkey` Composer: Inline code: the backtick wraps the selected words as code. With nothing selected, it types a backtick.

The other formatting keys are in the Format menu: code block ⌘⌥C, quote ⌘⇧9, bulleted list ⌘⇧8, numbered list ⌘⇧7, link ⌘⇧K. None of them takes ⌘K or ⌘F. A kind the chat can't keep tells you why with a toast.

### Settings

All of these are in Settings ▸ Messages. Each takes effect at once, and is still set after you quit and open Courier again.

**Sending**

- [ ] `setting:general` Allow undo send (⌘ Z) for: "Allow undo send (⌘Z) for" chooses Off, 0.75, 1, 2, 3, 5 or 10 seconds. With it on, a sent message waits that long as "Queued", dimmed. It is behind a plan.
- [ ] `setting:general` Click pending messages to undo send: "Click pending messages to undo send" lets a click on a held message take it back. Off, only ⌘Z does.
- [ ] `setting:general` Default for send later: "Default for send later" chooses If no reply or Regardless. The Send Later picker starts on it.

**Composer and messages**

- [ ] `setting:general` Press ↑ in the composer to: "Press ↑ in the composer to" chooses Move focus to the message list or Edit your last message. With an empty box, ↑ does that. With the first choice, ↑ again walks up the chat.
- [ ] `setting:general` On double-clicking a message: "On double-clicking a message" chooses Reply, React with your emoji, Show the reaction picker, Forward, Show the menu, or Do nothing.
- [ ] `setting:general` Include timestamps when copying messages with ⌘ C: "Include timestamps when copying messages with ⌘C" adds the time to what ⌘C copies from a message.
- [ ] `setting:appearance` Show formatting menu: "Show formatting menu" shows a bar of formatting buttons over the words you select. Off, the keys still work.
- [ ] `setting:appearance` Hide deleted messages: "Hide deleted messages" removes a deleted message without a trace. Off, a line says it was deleted.
- [ ] `setting:appearance` Quick reaction emoji: "Quick reaction emoji" sets the emoji ⌘⇧R and the double-click use.

### Components

**Composer and the message itself**

- [ ] `component` Bubble.tsx: A message is drawn from its formatting: bold, italic, strike, code, quotes with a bar, indented lists, links. A held message is dimmed and says "Queued". A failed one says "Not sent" with Retry and Delete. A bookmarked one carries a small bookmark.
- [ ] `component` Code.tsx: Code in a message is monospaced on a tint. A code block scrolls sideways when it is wide.
- [ ] `component` code.tsx: The Code button in the formatting bar, and the Code Block button next to it.
- [ ] `component` ComposeMessage.tsx: The box takes formatted text. It has an "Edit Message" bar with an ✕ while editing, a reply bar, a plus menu (Add Attachment, Send Later…, Create Poll…), and a send button whose menu (right-click) offers Send Later… and Send and Archive.
- [ ] `component` createMentionTriggerSettings.tsx: Typing @ opens the mention picker with the people in the chat, and @room where the network has it. Typing ; opens the quick-reply picker. Both take ↑ ↓, Return and Esc.
- [ ] `component` draft.tsx: "Insert as Draft" on someone else's message puts its words in your box as a draft. Nothing is sent.
- [ ] `component` edit_square.tsx: The Edit… item of the message menu, with ⌘T.
- [ ] `component` forward.tsx: The Forward… item, with ⌘⇧F. The picker is titled "Forward message", searches your chats, and takes up to 20. It says "The people you forward to won’t see who it came from."
- [ ] `component` icons-compose.tsx: The icons in the composer's bar and plus menu. Courier uses system symbols, so there is nothing different to look for.
- [ ] `component` OutlineCompose.tsx: The same compose icon, in its outline style. Same as above.
- [ ] `component` link.tsx: The Link button in the formatting bar, ⌘⇧K. It opens the link dialog.
- [ ] `component` LinkDialog.tsx: A dialog with Text and Address fields, Save and Cancel. Return saves and Esc cancels.
- [ ] `component` linkify.tsx: Web and mail addresses in a message are links that open in the browser or mail app. Unchanged since milestone 3.
- [ ] `component` MessageEditHistory.tsx: An edited message shows "Edited". Clicking it opens the earlier versions under the bubble, and it then reads "Hide Edits". Hovering shows "Originally: …". "Edit not sent" has Retry and Discard.
- [ ] `component` MessageMention.tsx: A mention is a chip, not plain text.
- [ ] `component` PollCreator.tsx: Create Poll… opens "New Poll": a question, options with Add an option and Remove option, "You can enter N more options", and "Allow multiple answers". Closing with something in it asks "Discard poll?".
- [ ] `component` PollCreatorBrowserWindow.tsx: The poll is a sheet over the chat, not a window of its own. See "How it behaves".
- [ ] `component` QuickRepliesPrefsSubView.tsx: Settings ▸ Messages ▸ Quick Replies lists them, with Add…, Edit… and Delete. It says "Type ; and the title in a chat."
- [ ] `component` QuickReplyItem.tsx: A quick reply in the ; picker shows its title and its words. {first_name}, {last_name} and {full_name} fill in the other person's name.
- [ ] `component` reply.tsx: The Reply… item and the reply bar above the box.
- [ ] `component` schedule.tsx: The clock for Send Later in the plus menu and the picker.
- [ ] `component` schedule_send.tsx: The same, on the send button's menu and the scheduled strip.
- [ ] `component` ScheduledMessageDate.tsx: Each scheduled message shows its date and time.
- [ ] `component` ScheduledMessages.tsx: Above the box, "N Message to Send Later" lists them with Send Now, Edit, Reschedule and Delete Without Sending. A waiting one says nothing more. A canceled one says "Canceled: they wrote first". A missed one says "Missed its time while Courier was closed".
- [ ] `component` Spoiler.tsx: A spoiler is covered until you click it. See "How it behaves".
- [ ] `component` ToggleScheduledMessages.tsx: The "N Message to Send Later" line opens and closes that list.

**The timeline**

- [ ] `component` BrandReplyLineSegment.tsx: A reply shows the message it answers above its text, with a line beside it. A thread root shows "N Reply" or "N Replies" and up to three names.
- [ ] `component` DisappearedMessagesGrouper.tsx: A message past its timer is gone from the chat, not left as a gap. A timer change leaves one note in Courier's words.

**Threads**

- [ ] `component` ThreadedRepliesBrowserWindow.tsx: A thread opens as a pane on the right of the chat. Its own window comes in part 4.5.
- [ ] `component` ThreadedRepliesHeader.tsx: The pane's header shows the root and has a close button.
- [ ] `component` ThreadedRepliesPane.tsx: The pane holds the root and its replies and its own box, "Reply in thread…". It is resizable. Esc closes it, after anything that Esc closes first.

**Other**

- [ ] `component` content_copy.tsx: Copy and Copy with Timestamp in the message menu. ⌘C copies the selected message.
- [ ] `component` chevron_forward.tsx: A small right-pointing arrow marks a row that opens more. Courier uses one system symbol, so there is nothing different to look for.

### Commands

These are registered in Courier for the command bar (⌘J), which part 4.7 builds. They have no tick box here: they are "registered; shown in ⌘J by 4.7". The ones with a menu item or key above are checked there.

- `command` Send later
- `command` Create quick reply from draft
- `command` Edit
- `command` Forward
- `command` Unsend
- `command` Delete for me
- `command` Reply in thread

Each one that acts on a message acts on the selected one, and is off when that message can't take it.

### How it behaves

Not failures. Do not report these as bugs.

- A spoiler is covered with a solid tint, not blurred, until you click it. Copying a message copies its spoiler words too.
- The send button's menu opens on right-click. New Poll is a sheet.
- The "Disappears in" count can read up to an hour too high when more than a day is left. Times longer than a day read in days ("7 days").
- A numbered list copied from another app that starts at a number other than 1 reads back from 1.
- With the inbox list in front, ⌘C copies the open chat's selected message. Edit ▸ Copy stays greyed when only a message is selected.
- A timer change the network ignored still shows as set in the chat's note. The header shows the real timer.

### Not ledger rows

The inventory has no row for these, but they are what this part was built to do.

**What the message menu does** (right-click a message, in this order)

- [ ] Edit… (⌘T). Reply… (⌘R) or Reply in Thread…. Show Replies (⌘↓) on a thread root.
- [ ] React….
- [ ] Bookmark or Remove Bookmark.
- [ ] Unsend. Delete for Me… or, on Google Messages, "Delete from This Mac and Your Phone…". Both ask first.
- [ ] Copy (⌘C), Copy with Timestamp, Insert as Draft (on someone else's message), Open Link (⌘⇧H).
- [ ] Forward… (⌘⇧F).
- [ ] Edit History, when the message was edited.
- [ ] Greyed lines that only say something: "Sent at …" or "Received at …", and "Disappears in …".
- [ ] A greyed action shows why, as its help text, in Courier's words.
- [ ] A timer note has no actions except Delete for Me.

**Polls**

- [ ] A poll shows its question, its options with a dot (one answer) or a tick (many), a vote count and a bar for each, and "N votes". It says "Select one option" or "Select one or more options". An ended poll says "Poll ended".
- [ ] Voting on a poll counts at once. If it fails, a toast says "Your vote wasn’t counted. Try again."
- [ ] You can create a poll only where the network has them. Where it doesn't, Create Poll… is greyed with why.

**Forward**

- [ ] Forwarding sends a copy (words and media) to each chat you pick. A toast says "Forwarded to 1 chat" or "Forwarded to N chats". If one fails, it names it.
- [ ] The copy carries no sign of where it came from, on every network.

**Bookmarks**

- [ ] A bookmark is on this Mac only, on every network. A bookmarked message shows a small mark.
- [ ] ⌘K shows a Bookmarks section: your five newest on the home view, after Last archived, and matches as you type. A bookmark row is a message row with a bookmark mark. Opening it opens the chat at that message.

**The disappearing timer**

- [ ] The chat header shows "Messages disappear after …" when a timer is set. A timer button beside it opens Disappearing Messages: Off and the choices the network allows, with the line "For added privacy, new messages disappear after the set time."
- [ ] On a network with no timer (Google Messages, Slack), the button is not there.
- [ ] An open message menu shows "Disappears in …" on a message that has a timer.

**The Send Later space**

- [ ] The Send Later space and filter list chats with a message that is waiting, canceled or missed, in any place except Hidden. They were empty in 4.1.
- [ ] Sending, deleting or rescheduling the last one takes the chat out of Send Later.

**The Messages settings tab**

- [ ] Settings ▸ Messages sits beside Inbox and holds the rows above, plus Quick Replies. A row behind a plan says "Available with a plan" when you have none.

**The Send Later picker**

- [ ] The picker offers the same presets as Remind Me, a date and time, and "If no reply" or "Regardless". The footer says "Courier sends it from this Mac. It needs to be running, and your Mac awake, at that time."
- [ ] A time that has passed says "That time has passed. Choose a later one." A time past five years says "Choose a time within 5 years."

### Carried to later parts

Not in 4.3, and not expected to work yet:

- Reply Privately, Mark as Unread from a message, typing shown to others, read receipts and "Seen": part 4.4.
- Stickers, GIFs, voice notes, emoji autocomplete (":") and emoticon replacement, quick-reply attachments, scheduled attachments, link previews and "Disable link previews in outgoing messages", Copy Image, Quick Look, Download, the Bookmarks pane in Chat Info, threads in their own window, Follow and Unfollow Thread and thread unread counts, and the {username}, {phone_number} and {email} variables: part 4.5.
- The Primary and Secondary composer button settings, and the hotkey editor: part 4.6.
- Talk to Type, Draft with AI, Translate, slash commands, the trial nudges, and the subscription screens behind "Available with a plan": part 4.7.
- Not planned in iteration 1: unsending other people's messages as an admin, End Poll and hidden results (no network takes them), nudges, and Telegram polls (its bridge has none).

## Part 4.4: receipts, typing, Incognito and accounts

Seen and Delivered under your messages, typing in both directions, messages that wait for the network, Incognito, Mark as Unread from a message, Reply Privately and several accounts on one network. What leaves this Mac for a network is:

- your read receipts, as before: opening a chat still tells the network you read it, unless Incognito is on;
- your typing, which is new and has a setting: a network that shows typing is told while you write;
- a private chat, when Reply Privately has to create one through the network.

Stays on this Mac: Mark as Unread from a message, Incognito, and who read what. Courier keeps the record of who has read your messages in its own store. It never goes anywhere.

### Before you start

- Install the build with `bazel run --config=macos-app //apps/desktop/courier/app:install`. Your chats and networks stay as they are.
- Settings are in Settings ▸ Messages ▸ Privacy (⌘,). The typing notification is in Settings ▸ Inbox ▸ Notifications.
- Out of the box: Incognito is off, "Show recipients I’m typing" is on, the incognito mark in the message box is on, and "Notify me when someone starts typing" is off.
- Incognito reads "Available with a plan" on a build without one.
- Do not open the same chat in the other chat app while testing. It would send a read receipt.
- Never test on a real person’s chat. Use a chat with yourself or a test account. Never open a real chat in Beeper while testing.

### Check these first

Nobody could watch the app while it was built. The tests cover the logic, and the views were checked only as still pictures. This is the first time anyone sees the app live. Look at these before anything else.

- [ ] Send with Wi-Fi off, then turn it on. The message says "Waiting to send" with Don’t Send. When the network is back it goes once. Write down how long Courier takes to notice the network is gone, and what a message sent in that gap shows.
- Do the by-hand run on the installed build, once, start to end. Tick each step as you go:
  - [ ] Send while the network is down, watch the message wait, then watch it go.
  - [ ] See Delivered and then Seen appear under your newest message.
  - [ ] Type in a chat and see "typing" on the other phone, then stop typing and see it end.
  - [ ] Use Reply Privately on someone else’s message in a group.
  - [ ] Use Mark as Unread on a message.
  - [ ] Turn Incognito on with an unread chat and open it.
  - [ ] See the "Also hide that you’re typing?" question itself.
- [ ] Sign account A in again by scanning the phone of account B. B must not end up with two live connections. You should see "That signed in … instead of …. Both are linked now." and both accounts still working.
- [ ] The Seen ticks in the inbox use your Mac’s accent colour (red in the pictures). Is that right?
- [ ] Dark mode: can you tell the switches in Settings on from off? Is the greyed "Show the incognito mark in the message box" row readable?
- [ ] In an Incognito chat on Telegram, schedule a message with Send Later and let it go out. The other side must not see that you read the chat: no read receipt goes with it. Only a reply you send from this Mac reads the chat.
- [ ] Chats that existed before you added a second account (or before this part) show their account tag once Courier has started again. Add a second account on a network, quit Courier and open it: the older chats now have the first account’s tag.
- [ ] "Also hide that you’re typing?" shows once, each time Incognito is turned on from Settings, and not when typing is already hidden. Turn Incognito off while it is showing: the question goes away. It is a question for the whole app, so it shows over whichever window is in front. The command bar’s "Turn on incognito mode" arrives with part 4.7.

### The five things to check

These are the five things this part was most worried about. Look at them before the rest.

- [ ] A message sent while the network is down goes exactly once, in order, and never vanishes. Turn Wi-Fi off and send two or three messages in one chat. Each says "Waiting to send" with Don’t Send, the whole time. Quit Courier and open it again: they are still waiting, never "may have been sent". Turn Wi-Fi on: they go oldest first, once each. A message waits for ever if the network never comes back. There is no cut-off.
- [ ] "Seen" is never a lie. Slack shows none. Someone reading an older message does not mark your newer ones. Reading a chat on your own phone never shows as Seen. A group’s Seen names the readers and the count is right. A receipt for a message Courier doesn’t have is ignored without any fuss.
- [ ] Typing never sticks and never leaks. The other side sees you stop when you stop typing, send, clear the box or leave the chat. Someone else’s typing in Courier ends by itself at the network’s own time, even if no stop arrives. Nothing goes out while "Show recipients I’m typing" is off, or to a chat whose network is down.
- [ ] Incognito keeps its promise. Open an unread chat with Incognito on: the count and the New divider stay, and nobody is told. The chat becomes read when you reply from this Mac, or when you mark it read yourself (⌘⇧U, Mark as Read, or "Mark all chats as read…" in the menu). Turn Incognito off: nothing is sent for the chats you looked at while it was on.
- [ ] Two accounts never bleed into each other. Each account’s one-to-one chats are its own. A send goes from the chat’s own account. Sign one account out: its banner names it, and sends on the other account still go. Sign one in again: the other’s chats and state are left alone.

### What to expect on each network

Courier reads this from each network’s own code. Courier shows what arrives and promises nothing more.

| | WhatsApp | Signal | Telegram | Google Messages | Slack |
|---|---|---|---|---|---|
| Your read receipts go out | Yes | Yes | Yes (a bot account sends none) | Yes | Yes (a bot token sends none) |
| "Seen" under your message | One-to-one and groups, per person | One-to-one and groups; no time | One-to-one only | One-to-one; groups only when the phone says "Read by …" | Never |
| "Delivered" | One-to-one only | One-to-one only | No | One-to-one | No |
| Their typing shows | About 15 seconds, or until they pause | About 15 seconds | About 6 seconds each time; never your own other devices | About 15 seconds, in chats with typing indicators on the phone | About 5 seconds |
| Your typing goes out | Yes | Yes | Yes | Start only, never a stop | Start only, never a stop |
| Reply Privately | Yes | Yes | Yes | Yes, if the person’s phone number is known | Yes |
| A second account | A second phone number | Yes | Yes | Yes | One per workspace |

A bot account (Telegram) or a bot token (Slack) is a sign-in made for a program rather than a person, with a key the network gives that program. Signed in that way, no read receipts go out.

- [ ] Each cell above holds on the real network. Check at least Seen, Delivered and typing on every network you have.
- [ ] Slack’s own "read" marks are your own reads from another Slack window. Courier stores them as your marker and never shows them as "Seen". Check that a Slack chat never says "Seen".
- [ ] "Delivered" never shows in a group, on any network. A group message goes Sent, then Seen by.
- [ ] On Google Messages, a group "Seen" shows only when the phone is set to English. Whether one-to-one receipts and typing come at all follows the phone’s RCS settings. RCS is the newer kind of text messaging that Google Messages uses between phones that have it; plain SMS has no receipts or typing.
- [ ] Courier’s typing keeps going while you write, so a network that only hears a start still shows it. Google Messages and Slack never hear a stop, so the other side ends it on its own.
- [ ] A Telegram group message of yours never says more than "Sent". Telegram has no receipts in groups and none for delivery.
- [ ] On WhatsApp and Signal, replying marks the chat read whatever Courier does. So Incognito’s "until you reply" is what those networks do anyway.
- [ ] A second WhatsApp number shares group chats with the first. A group both numbers are in is one chat, shown once, with no account tag. The network chooses which number sends. The same number signed in twice replaces the first sign-in. It does not add one.
- [ ] A shared chat whose only account was deleted says "Can’t send: none of your accounts is in this chat", with Don’t Send. It does not wait for ever.

### Keys

Part 4.4 adds no key. ⌘⇧U (Mark as Read) still works while Incognito is on.

### Settings

- [ ] `setting:general` Incognito mode: Settings ▸ Messages ▸ Privacy, "Incognito mode". Chats stay unread when you open them, and nobody is told, until you reply or mark the chat read. Turning it on asks "Also hide that you’re typing?" once, with Hide Typing and Keep Showing. Without a plan it reads "Available with a plan".
- [ ] `setting:general` Show recipients I'm typing: "Show recipients I’m typing", on out of the box. Off, nothing about your typing goes out. Hide Typing in the question above turns it off.
- [ ] `setting:appearance` Show incognito mode indicator: "Show the incognito mark in the message box", on out of the box. It is greyed while Incognito is off. On, a small eye with a slash and "Incognito" sits in the message box while Incognito is on. Hovering says "Read receipts are off until you reply." The thread pane’s box has it too.
- [ ] `setting:notifications` Notify when someone starts typing (supported platforms only): Settings ▸ Inbox ▸ Notifications, "Notify me when someone starts typing", off out of the box. One notification per typing burst, with the chat’s name as its title. Never for the chat you are looking at, a muted chat, or one in Low Priority or Hidden. The message’s own notification replaces it.

### Components

**On a message and in the chat**

- [ ] `component` icons-toolbar.tsx: The small marks for the new states: a clock beside "Waiting to send", an eye with a slash for Incognito, and ticks. Courier uses system symbols, so there is nothing different to look for.
- [ ] `component` mark_email_unread.tsx: Mark as Unread in a message’s menu, in its own group after Bookmark. Its help says "From this message. On this Mac only." Courier uses a menu line with no special icon.
- [ ] `component` BrandTypingIndicator.tsx: A line above the message box with pulsing dots and "Ana is typing…" or "3 people are typing…". It is new in the chat. Before this part it was only in the inbox.

**In the inbox**

- [ ] `component` ThreadListReadIcon.tsx: After a chat row’s time, one grey tick means Sent, two grey ticks Delivered, two ticks in your accent colour Seen. It shows only when your newest message has gone.
- [ ] `component` TypingIndicator.tsx: A chat row says who is typing, as in part 4.1.

**Accounts**

- [ ] `component` AccountDisconnectedBanner.tsx: The banner for a signed-out account is per account. With more than one account on a network it names the account (its phone number or workspace) after the network’s name, and has its own Reconnect.
- [ ] `component` AccountsBanner.tsx: Several banners can show at once, one for each account that needs you. A network still starting has none.
- [ ] `component` AddMoreAccountsBanner.tsx: In the Add a Network picker, a linked network says "Linked as …" and has "Add Another Account…". Two accounts read "Linked as A and B". More read "Linked: 3 accounts".
- `component` CompactAccountsBanner.tsx: not applicable. It belongs to a migration from another product.

### Commands

These are registered in Courier for the command bar (⌘J), which part 4.7 builds. They have no tick box here.

- `command` Turn on incognito mode: registered; shown in ⌘J by 4.7. Its other state, "Turn off incognito mode", is registered with it.
- `command` Add Account: registered; shown in ⌘J by 4.7. It opens Add a Network.
- `command` Accounts: registered; shown in ⌘J by 4.7. It opens Add a Network too, until the Accounts pane arrives in 4.6.
- Reply privately and Mark as unread are registered too, with no ledger row. They act on the selected message, as the menu items do.

### How it behaves

Not failures. Do not report these as bugs.

- Mark as Unread is offered on other people’s messages and on yours that have gone. It is not offered on a note, or on a message that is waiting, sending or not sent.
- Reply Privately is offered only on someone else’s message in a group, while that network is running. It is not offered in a one-to-one chat or on a note.
- In Incognito, "Mark chats read when I archive them" does not mark the chat read. It archives unread. A reply sent from a notification marks the chat read, like any reply, even outside Incognito.
- Only a reply you send from this Mac (from the chat, its thread pane or a notification) ends Incognito’s hold on that chat and Mark as Unread’s hold. A message you send from your phone does not: your phone tells the network you read the chat itself. A scheduled message that goes out at its time does not either, so a Send Later message in an Incognito chat sends no read receipt.
- A reply you send from a notification reads the chat only once it has gone. A reply that waits and goes later does not read the chat itself. WhatsApp and Signal do that on their own. If the reply fails, a notification says it wasn’t sent; if it waits for the network, a notification says it will be sent when the network is back.
- A waiting message’s menu has Copy and Copy with Timestamp only. Don’t Send is on its status line.
- The thread pane shows no Seen and no typing line.
- The account tag shows only while a network has more than one account. It gives way to the chat’s name when the row is narrow.

### Not ledger rows

The inventory has no row for these, but they are what this part was built to do.

**The status line under your messages**

- [ ] Sent, Delivered and Seen sit under your newest message that has gone, and nowhere else. Older messages show no line.
- [ ] One-to-one: "Seen", or "Seen 10:42" when the network gave a time. Groups: "Seen by Ana", or "Seen by Ana & 2 others".
- [ ] "Waiting to send", "Can’t send: none of your accounts is in this chat" and the not-sent lines stay on every message in that state. A newer message that is waiting does not take away the Seen under an older one that went.

**Don’t Send**

- [ ] On a waiting message, Don’t Send takes it back. It is not sent, and what you typed goes back into the box. It works every time, including after the network went down and came back. Help says "Takes the message back. It isn’t sent." If the engine does not answer, a toast says so and the message is still waiting.

**Waiting messages**

- [ ] A message waits when its network is starting, is down, or its account is signed out. Text and files wait. Edits, reactions, unsends and polls do not: they fail after a short wait, because one that goes out hours later could be wrong.
- [ ] Its help says "It goes when WhatsApp is back online." with the network’s name.

**Reply Privately**

- [ ] Reply Privately… opens the one-to-one chat with the sender, creating it through the network if there is none. The message is quoted in the box, with the cursor on a blank line after it. Where the network keeps no quotes, the quote is plain lines starting with "> ".
- [ ] When the network can’t start the chat, a toast says so in Courier’s words. It names the network.

**Mark as Unread from a message**

- [ ] The chat’s unread count runs from that message on. It is on this Mac only, never sent to a network.
- [ ] Reading the chat (⌘⇧U, Mark as Read, or a reply) clears it. After it, Courier does what Settings ▸ Inbox says for "After marking the open chat read or unread". With "Stay on it", the open chat is not marked read again until you open it again, someone else writes, or you reply.

**Starting**

- [ ] Chats show as each network becomes ready. A network that is still starting says "Starting…" in the picker, the status strip (the row of small network marks at the top of the chat list) and the space bar. It has no banner and no "Add a network" prompt. Its chats are listed and open, and a send in one waits.
- [ ] Signing in to a network that is still starting says "WhatsApp is still starting. Try again in a moment." and starts nothing.

**Several accounts on one network**

- [ ] Add Another Account… signs in a second account beside the first. Signing in again with a different account keeps both: "That signed in … instead of …. Both are linked now."
- [ ] The inbox row shows the account’s name as a small tag after the chat’s name, only while the network has more than one account. Hovering says "On your … account".
- [ ] There is still one space per network. Both accounts’ chats are in it.
- [ ] The status strip and each banner name the account when there is more than one. "Reconnect …" in the account menu names it too.

### Carried to later parts

Not in 4.4, and not expected to work yet:

- Sub-account switches, per-account notification settings and the Accounts pane: part 4.6. So is the Account command and its pane.
- A way to export a crash report for Report a Problem: part 4.6. It must keep only the scrubbed log lines and the code-location lines, replace what follows "panic:" and "fatal error:" with a fixed word, and decide about the engine’s data-path line, which carries the Mac’s account name. Today a crash inside a background task skips the log filter, and the command-line tool prints a raw start error.
- Not planned: read receipts shown on avatars (only Beeper’s own network has them), and "Seen" on Slack (Slack has none).

## Part 4.5a: people, groups, merged chats, contacts and calendar

Chat Info, editing a chat for everyone or just for you, starting a one-to-one chat or group, Blasts, Merged Chats, sender hover cards with macOS Contacts, and the Calendar pane with dates in messages. What leaves this Mac for a network is:

- changing a group’s name, picture or topic when you choose "For Everyone", on the networks that take them;
- adding or removing someone in a group, making or removing an admin, leaving a group, or deleting a chat on the network;
- Report as Spam only when you tick "Also leave the group on …" or "Also delete the chat on …";
- starting a one-to-one chat or a new group, looking someone up by phone number or `@username`, and sending a Blast (which sends a separate one-to-one message to each person).

Stays on this Mac: renaming a chat or changing its picture with "Just for Me" (and "Reset to network name"), Report as Spam with the box unticked, Merged Chats, Export Chat, and everything in macOS Contacts and Calendar. Your contacts and your calendar never leave this Mac.

### Before you start

- Install the build with `bazel run --config=macos-app //apps/desktop/courier/app:install`. Your chats and networks stay as they are.
- Out of the box: "Show chat updates in timeline" in Settings ▸ Messages ▸ Messages is on, and Chat Info and Calendar are closed.
- Neither Contacts nor Calendar asks for permission when Courier opens. Each asks once, only when you open a hover card or the Calendar pane.
- Do not open the same chat in the other chat app while testing. It would send a read receipt.
- Never test on a real person’s chat. Use a chat with yourself or a test account. Never open a real chat in Beeper while testing.

### Check these first

All app checks are by hand on real accounts: there is no fake-network app mode, and views were checked only as PNG snapshots. Look at these before anything else.

- [ ] Delete a WhatsApp group chat: the confirmation says "Delete “…”?" with "This also leaves the group.", and it does. A Signal group delete says "This permanently deletes the chat on the connected network.", says nothing about leaving, and doesn’t leave. On Telegram, "Delete Chat…" is offered on one-to-one chats only (not groups, where Telegram’s bridge would delete the group for everyone).
- [ ] Report as Spam with the box unticked: the chat hides on this Mac, and nothing changes on the network (check on the phone).
- [ ] First open of a hover card’s Contacts section, and of the Calendar pane: each asks for access once; after "Don’t Allow", it never asks again and shows Open System Settings.
- [ ] A merged chat: replies go on the network shown in the "Replying via" pill, and a new message on the other network does not move the pill.
- [ ] The first sync of an older group after updating: how many "joined" lines appear in the chat (consecutive joins, leaves and renames should collapse into one line, such as "Alice and 3 others joined the group").
- [ ] "Just for Me" rename, then a name change from the phone: your name stays, and "Reset to network name" brings back the new network name.
- [ ] ⌘⇧I toggles Chat Info and ⌘I stays Italic. ⌘L stays Remind Me; the reply network is switched from the pill.
- Do the by-hand run on the installed build, once, start to end. Tick each step as you go:
  - [ ] Press ⌘⇧I in a one-to-one chat and a group chat: check the person’s phone number, username and local time, and the Shared Media, Files, Links, Bookmarks and Disappearing Messages sections.
  - [ ] Rename a Google Messages chat with "Just for Me", quit Courier and open it again, and check your name stays without changing anything on the phone; rename a WhatsApp or Signal test group with "For Everyone" and check the group name updates on the phone.
  - [ ] Press ⌘N, look up a phone number or `@username` of someone not in any group with you, and check a one-to-one chat opens; press ⌘⇧N, select two people on different networks, choose "Blast (1:1 to Each)", send a Blast using a quick reply with `{recipient.firstName}`, and check each person receives their own personalized one-to-one message.
  - [ ] Merge two one-to-one chats for the same person across two networks, check the interleaved timeline and click the "Replying via" pill in the message box to switch the reply network, then open "Edit Merged Chat…" and click "Unmerge".
  - [ ] Hold the pointer over a sender’s picture or press ⌘⇧O to check the hover card and Contacts match; press ⌘⌥K to check the Calendar right pane, a "Join" button on a video call, and clicking a dashed-underlined future date in a message bubble.

### The five things to check

These are the five things this part was most worried about. Look at them before the rest.

- [ ] A group or chat change the network refuses never looks done. Rename a group with "For Everyone", change its topic or picture, or add or remove someone while the network refuses it. Courier waits for the network’s answer before updating the chat, and shows "<Network> didn’t accept that change." (or "The network didn’t accept that change."). The old name, topic, picture and member list stay as they were.
- [ ] Report as Spam with the box unticked stays on this Mac. "Report as Spam…" asks "Hide this chat on this Mac and mark it as spam?" with an unticked box ("Also leave the group on <Network>" or "Also delete the chat on <Network>"). With the box unticked, clicking "Report Spam" hides the chat and clears its unread count on this Mac, and changes nothing on the network. Only ticking the box leaves or deletes on the network.
- [ ] Starting a chat by phone number or `@username` works even when the network gives no chat details back at first. Look up a phone number or `@username` in New Chat (⌘N) and open the chat. It appears in the inbox right away with the phone number or handle as its name so you can write at once, and updates to the person’s name and picture as the network sends them.
- [ ] Merged chats interleave messages in time order and keep your chosen reply network. Merge two one-to-one chats: their messages sit in one timeline with a small network badge on each bubble, and the inbox row shows stacked network badges and the combined unread count. Replies go on the network shown in the "Replying via" pill, and a message arriving on the other network never switches the pill while you are writing. Unmerging restores the individual one-to-one rows.
- [ ] Contacts and Calendar stay on this Mac and never ask twice. Opening a hover card asks for Contacts access once; opening the Calendar pane (⌘⌥K) or clicking "Allow Calendar Access" asks for Calendar access once. After "Don’t Allow", Courier never prompts again and shows "Open System Settings". Nothing from Contacts or Calendar is ever sent to a network.

### What to expect on each network

Courier reads this from each network’s own bridge code and your role in the group. What a network or your role does not allow is hidden or greyed, and "Just for Me" is always there on every chat.

| | WhatsApp | Signal | Telegram | Google Messages | Slack |
|---|---|---|---|---|---|
| Phone, username, local time in profile | Phone; bot mark | Phone; bot mark | Username; phone when visible; bot mark | Phone | Slack ID only, plus timezone ("3:27 PM local time"); bot mark |
| Rename group ("For Everyone") | Yes, when allowed in the group | Yes, when allowed in the group | Yes, when allowed in the group | No ("Just for Me" only) | Channels, when allowed |
| Change group photo ("For Everyone") | Yes, when allowed | Yes, when allowed | Yes, when allowed | No ("Just for Me" only) | No ("Just for Me" only) |
| Edit group description | Yes | Yes | No | No | Yes |
| Add, remove, leave group | Yes | Yes | Yes | No | Channels only |
| Make or remove admin | No | Yes, when you are an admin | No | No | No |
| Delete chat on network | Yes; in a group it also leaves | Yes; does not leave the group | One-to-one chats only (not groups) | Yes | Not offered |
| Create a new group | Yes | Yes | Yes | Yes, with 2 or more other people | Yes: a group DM of 2 to 8 people |
| Find someone by phone or `@username` | Phone number (`+1…`) | Phone number (`+1…`) | `@username`, user ID, or a phone number the bridge has already seen | Phone number (`+1…`) | Slack user ID only (use search for names) |
| Contact list in New Chat | Yes | Yes | Yes | Yes | No |
| Search people on the network | Yes (your contacts) | No | Yes | No | Yes (your workspace) |

- [ ] Each cell above holds on the real network. Check at least Chat Info, "Just for Me" vs "For Everyone", and New Chat on every network you have.
- [ ] On Google Messages, a group cannot be renamed, re-pictured or left on the network from Courier. Edit Group opens on "Just for Me", and "For Everyone" is greyed.
- [ ] On Slack, New Group makes a group DM of 2 to 8 people, and "Delete Chat…" is not offered. Finding someone needs their Slack user ID or a workspace search.
- [ ] On WhatsApp, deleting a group chat warns "This also leaves the group." because WhatsApp’s bridge leaves the group before deleting it. On Signal, deleting a group chat deletes it without leaving; on Telegram, deleting is offered on one-to-one chats only.
- [ ] Only Slack sends a person’s timezone, so "3:27 PM local time" shows on Slack profiles and hover cards.

### Keys

- [ ] `hotkey` Chat: Start New: ⌘N opens New Chat in one-to-one mode. ⌘⇧N opens New Group or Blast.
- [ ] `hotkey` Open User Profile: ⌘⇧O opens the sender hover card for the selected message’s sender (or the latest incoming message in the chat when yours is selected).
- [ ] `hotkey` Toggle Chat Info: ⌘⇧I opens and closes the Chat Info pane on the right (⌘I stays Italic in the message box). Message ▸ Show Calendar is ⌘⌥K.

### Settings

- [ ] `setting:appearance` Show membership events: Settings ▸ Messages ▸ Messages, "Show chat updates in timeline", on out of the box. When on, joins, leaves and room renames or picture changes show in the chat (with consecutive changes collapsed into one line). When off, those lines are hidden in the timeline.

### Menus

- [ ] `menu:File` New Chat: File ▸ New Chat… (⌘N), and right below it File ▸ New Group or Blast… (⌘⇧N). The Message menu also has Show Chat Info / Hide Chat Info (⌘⇧I), Show Calendar / Hide Calendar (⌘⌥K), and Show Sender Profile (⌘⇧O).

### Components

**Chat Info and editing a chat**

- [ ] `component` RightPane.tsx: The right-hand pane of the chat window hosts Chat Info (⌘⇧I) or Calendar (⌘⌥K), alongside Thread Replies.
- [ ] `component` ThreadInfo.tsx: The Chat Info pane shows the chat’s picture, name, network, topic, encryption ("Encrypted" with a green lock or "Transport TLS"), "Disappearing Messages" menu, a "Filter chat info…" field, collapsible sections for Participants, Pinned, Shared Media, Files, Links and Bookmarks, and bottom actions: "Refresh Chat Info", "Merge with Another Chat…" (in one-to-one chats), "Export Chat…", "Leave Group…", "Delete Chat…" and "Report as Spam…".
- [ ] `component` ThreadInfoBrowserWindow.tsx: The window button at the top of Chat Info ("Open Chat Info in Separate Window") opens Chat Info in its own "Chat Info" window.
- [ ] `component` ThreadDescription.tsx: Under the chat’s name in Chat Info, a group shows its topic or description and member count ("N members"), and a one-to-one chat shows the person’s identifiers and local time. When renamed with "Just for Me", it also shows "On <Network>: <network name>".
- [ ] `component` BrandChatInfoPaneBookmarks.tsx: The Bookmarks section in Chat Info lists the bookmarked messages in the chat; clicking one jumps to that message in the timeline.
- [ ] `component` GroupParticipantItem.tsx: Each row in Participants shows the member’s picture, name, "Admin" or "Bot" badge, and identifier. Right-clicking opens a menu with "Message <Name>", "Make Admin" or "Remove Admin" (when you can change admins), "Remove from Group" (when you can remove people), and "Copy User ID". "Add Participants…" sits at the top of the list when the chat allows adding people.
- [ ] `component` EditGroupModal.tsx: Clicking the pencil in Chat Info or choosing "Edit Chat…" / "Edit Group…" opens the sheet with "For Everyone" ("Changes are visible to everyone on <Network>.") and "Just for Me" ("Changes apply only on this Mac."), "Choose Photo…", "Name", and (in a group under "For Everyone" when supported) "Topic". Under "Just for Me", when a custom name or picture is set, "Reset to network name" restores the network’s name and picture.
- [ ] `component` EditGroupBrowserWindow.tsx: Editing a chat or group opens as the Edit Chat / Edit Group sheet over the window.
- [ ] `component` MembershipGrouper.tsx: Consecutive join, leave and room-change events in the timeline collapse into one line ("Alice joined the group", "Alice and Bob joined the group", "Alice and 3 others joined the group", "Alice left the group", or "Alice changed the chat").

**Starting a chat, a group or a Blast**

- [ ] `component` StartNewChatView.tsx: ⌘N opens "New Chat" with account filter pills ("All Networks" and each connected account), a search field ("Search name, phone number (+1…), or @username…"), and a "New Group or Blast" button. Selecting one person in one-to-one mode opens the chat immediately.
- [ ] `component` new-chat-utils.tsx: Typing a phone number (`+1…`) or `@username` offers "Look up <query> on <Network>" for each connected account that can resolve it, alongside matches from your contacts and people in your groups.
- [ ] `component` ContactItem.tsx: Each candidate row in New Chat and in "Add Participants" shows the person’s picture, name, network pill, and subtitle (phone number, handle or shared groups).
- [ ] `component` CommandBarUser.tsx: People from your groups who have no one-to-one chat yet appear in New Chat and in ⌘K’s "In groups" section; picking one opens or creates a one-to-one chat with them.
- [ ] `component` DraftChatAvatar.tsx: Selected people in New Group or Blast appear as removable chips with their avatar and name.
- [ ] `component` GroupTitleBar.tsx: With two or more people selected in New Group or Blast, a switch offers "New Group" and "Blast (1:1 to Each)". When the selected people are on different networks or accounts, "New Group" is greyed with "Group members must be on the same network" or "Group members must be on the same account", and the mode switches to "Blast (1:1 to Each)". In "New Group", a "Group Name" field ("Optional group name…") and "Create Group" create the group.
- [ ] `component` QuickReplyItem.tsx: In one-to-one chats and in "Blast (1:1 to Each)", `{recipient.firstName}`, `{recipient.fullName}`, `{sender.firstName}` and `{sender.fullName}` fill in each person’s name and yours. Sending a Blast asks "Send to N people on M networks?" with "Confirm Send", then shows "Blast Delivery Results" with "Sent", "Waiting" or "Failed" for each person.

**Merged Chats**

- [ ] `component` MergedChatEditor.tsx: "Merge with Another Chat…" or "Edit Merged Chat…" opens the sheet ("Merge Chats" or "Edit Merged Chat") with "Merged Chat Name", a "Filter 1:1 chats…" search box, checkboxes on one-to-one chats, "Merge Chats" / "Save", and (when editing an existing merged chat) "Unmerge". At least two one-to-one chats must be ticked.
- [ ] `component` CreateMergedChatBrowserWindow.tsx: Creating or editing a merged chat opens as a sheet over the main window.
- [ ] `component` MergeSuggestionNetworkIcons.tsx: When two or more one-to-one chats share the same normalized phone number, email or display name across networks, "Suggested Merges" appears at the top of the sheet with network badges and a "Use Suggestion" button.
- [ ] `component` StackedAvatars.tsx: A merged chat row in the inbox shows stacked network badges (up to 3) on its avatar, the combined unread count, and the newest preview across its member chats.
- [ ] `component` TextAreaAutocomplete.tsx: In a merged chat, each message bubble carries a small network badge, and the composer shows a "Replying via <Network>" pill ("Switch the network your reply is sent on") that cycles through the member chats when clicked.

**Sender hover card, profiles and Contacts**

- [ ] `component` BrandUserHoverCard.tsx: Holding the pointer over a sender’s avatar or name in a message bubble for half a second (or pressing ⌘⇧O) opens the sender’s hover card with their picture, name, network pill, optional "Bot" pill, "Message" and "Copy Handle" buttons, Shared Groups (up to 5), and Contacts status.
- [ ] `component` HoverCard.tsx: The popover container that holds the sender hover card and stays open while the pointer is over the trigger or the card.
- [ ] `component` HoverCard.context.tsx: The hover state that opens the card after a 0.5-second hover and closes it when the pointer leaves.
- [ ] `component` ProfileField.tsx: Profile rows in Chat Info and in the hover card show handles, identifiers and local time ("3:27 PM local time").
- [ ] `component` PhoneNumber.tsx: Phone numbers in Chat Info and in the hover card are formatted and can be copied.
- [ ] `component` Email.tsx: Email addresses in Chat Info and in the hover card are shown and can be copied.
- [ ] `component` CopyableField.tsx: Each identifier row in Chat Info and the hover card has a "Copy" button ("Copied"), and the participant menu has "Copy User ID".
- [ ] `component` AddContactForm.tsx: When a sender is not in your macOS Contacts, the hover card shows "Save to Contacts…", which opens an inline form with "Given Name", "Family Name", "Phone", "Email", "Cancel" and "Save". When matched, it shows "In Contacts: <Name>". When Contacts access was denied, it shows "Contacts access is turned off in System Settings." and "Open System Settings".

**Calendar**

- [ ] `component` CalendarPane.tsx: ⌘⌥K opens the "Calendar" pane on the right with Previous Day, "Today" and Next Day buttons, a list of that day’s events ("All day" or start–end times, location, and a "Join" button on Google Meet, Zoom, Microsoft Teams and Webex links), or "No events scheduled". Clicking a dashed-underlined future date in a message bubble opens "New Calendar Event" with "Title", the detected date and time, "Cancel" and "Add to Calendar".

### Commands

These are registered in Courier for the command bar (⌘J), which part 4.7 builds. They have no tick box here: they are "registered; shown in ⌘J by 4.7". The ones with a menu item or key above are checked there.

- `command` Create new chat: opened by File ▸ New Chat… (⌘N).
- `command` Create new group: registered as "New group or blast chat" (⌘⇧N) and in File ▸ New Group or Blast….
- `command` Merge chats: opened by "Merge with Another Chat…" / "Edit Merged Chat…" in the chat menu and Chat Info.
- Courier also registers "Toggle chat info" (⌘⇧I), "Search in chat info" (no shortcut), "Jump to date in chat" (⌘⌥K), and "Show sender profile" (⌘⇧O) in `CommandSet.chatInfo`.

### How it behaves

Not failures. Do not report these as bugs.

- Toggle Chat Info is ⌘⇧I so that ⌘I stays Italic in the message box. "Search in chat info" has no keyboard shortcut; use the "Filter chat info…" field at the top of Chat Info.
- ⌘L stays Remind Me. In a merged chat, switch the reply network by clicking the "Replying via" pill in the message box.
- A "Just for Me" name or picture is stored on this Mac only and always wins over the network’s name and picture in the inbox, header, Chat Info and search. If someone renames the chat on the network while your override is set, your name stays on screen and the new network name is saved underneath; clicking "Reset to network name" in Edit Chat / Edit Group brings back the latest network name.
- "Export Chat…" saves the messages already stored on this Mac in chronological plain text (`[YYYY-MM-DD HH:MM:SS UTC] Sender: Body`) to the file you choose in the Save panel (its default filename ends in `.txt`), and shows a toast "Exported N messages". It never fetches from the network or sends anything out.
- In a group chat, `{recipient.firstName}` and `{recipient.fullName}` in a quick reply are left unexpanded so a single group member’s name is never put into a message to the whole group. They expand in one-to-one chats and in each individual message of a Blast.
- Only future dates in messages get a dashed underline for adding to Calendar; past dates stay plain text.

### Not ledger rows

The inventory has no row for these, but they are what this part was built to do.

**Starting a chat with someone who is not in a group with you** (carried from 4.4)

- [ ] Press ⌘N, type a phone number (`+1…`) or `@username` of someone you share no group with, and click "Look up <query> on <Network>". Courier resolves them on the network, creates or opens the one-to-one chat, and selects it.

**Local overrides ("Just for Me" vs "For Everyone")**

- [ ] Every chat (including one-to-one chats and networks that cannot rename groups remotely, like Google Messages) offers "Just for Me" in Edit Chat / Edit Group.
- [ ] When a "Just for Me" name is set, Chat Info shows "On <Network>: <network name>" under your custom title, and Edit Chat / Edit Group shows "Reset to network name".

**Report as Spam**

- [ ] "Report as Spam…" in Chat Info or the chat’s right-click menu opens a sheet asking "Hide this chat on this Mac and mark it as spam?". Its checkbox to also leave the group or delete the chat on the network is unticked by default.

**Participant management confirmations**

- [ ] Removing someone from a group asks "Remove <Person> from “<Group>”?" before calling the network.
- [ ] Leaving a group asks "Leave “<Group>”?" with "You won’t receive new messages from this group unless someone adds you back."
- [ ] Deleting a chat asks "Delete “<Chat>”?" with "This also leaves the group." on WhatsApp groups and "This permanently deletes the chat on the connected network." everywhere else.

**Calendar and Contacts permissions**

- [ ] Before Calendar access is asked, the Calendar pane shows "Show your macOS Calendar schedule here." and an "Allow Calendar Access" button. If denied, it shows "Calendar access is turned off in System Settings." and "Open System Settings".
- [ ] Only `https` links on `meet.google.com`, `zoom.us`, `teams.microsoft.com` and `webex.com` show a "Join" button in the Calendar pane.

### Carried to later parts

Not in 4.5a, and not expected to work yet:

- A reply-network shortcut (⌘L is Remind Me).
- Carried to part 4.5b (rich media playback and capture — 45 ledger rows):
  - `component` AttachmentCarousel.tsx: full-window media lightbox with zoom, pan, rotate, flip, download, copy and Quick Look.
  - `component` Audio.tsx: inline voice-note waveform player, 0.5×–2× speed and played state.
  - `component` Autocomplete.tsx: composer `:` emoji autocomplete popover.
  - `component` BrandStopButton.tsx: stop voice-note recording button in the composer.
  - `component` BrandVideo.tsx: inline video element.
  - `component` Emoji.tsx: composer plus-menu media and emoji items.
  - `component` EmojiItem.tsx: emoji picker cell.
  - `component` EnhancedImg.tsx: inline image view with BlurHash placeholder.
  - `component` FileAttachment.tsx: attachment chip and downloadable file card.
  - `component` FileDropOverlay.tsx: drag-and-drop file attachment overlay.
  - `component` FilePlaceholder.tsx: Audio, PDF, Text and Document placeholder card.
  - `component` FileRowSpinner.tsx: attachment loading indicator.
  - `component` GalleryGrouper.tsx: consecutive image and video gallery grid in the timeline.
  - `component` GalleryVideoPoster.tsx: video poster frame in the gallery grid.
  - `component` GifPicker.tsx: composer GIF picker UI (search provider stubbed in 4.7).
  - `component` GlobalAudioPlayer.tsx: persistent floating audio player across chats.
  - `component` ImageError.tsx: broken-image fallback card.
  - `component` LoadingAttachment.tsx: in-flight attachment placeholder.
  - `component` Location.tsx: inline map card with Apple Maps, Google Maps and Copy Location actions.
  - `component` MediaViewerBrowserWindow.tsx: Media Viewer window with Media, Links and Docs tabs, Sent By filter, sort and caption search.
  - `component` MediaWithSender.tsx: media tile with sender attribution in Media Viewer.
  - `component` MessageIFrame.tsx: sandboxed iframe for external embeds.
  - `component` PDF.tsx: inline paged PDF viewer.
  - `component` PDFAttachment.tsx: PDF attachment card with page controls.
  - `component` PendingAttachments.tsx: pending attachment strip in the composer.
  - `component` PictureInPictureBrowserWindow.tsx: floating Picture-in-Picture video window.
  - `component` StickerPicker.tsx: composer sticker picker.
  - `component` TranscodedAttachment.tsx: transcoded audio and image attachment view.
  - `component` ViewLimitedMediaViewer.tsx: view-once photo, video and voice-note viewer.
  - `command` Media viewer: command bar entry opening the Media Viewer window.
  - `hotkey` Chat: Send File: ⌘O attach file in the composer.
  - `hotkey` Download Attachments: ⌘D download attachments on the selected message.
  - `hotkey` Message: Record Audio: ⌘⇧A record voice note in the composer.
  - `hotkey` Message: Send GIF: ⌘⇧G open GIF picker.
  - `hotkey` Message: Send Sticker: ⌘⌥⇧S open sticker picker.
  - `setting:appearance` Disable link previews in outgoing messages: suppress outgoing link preview cards.
  - `setting:appearance` Load external embeds automatically: auto-load external embeds vs click-to-load.
  - `setting:general` Always ask where to save files before downloading: prompt for destination on attachment download.
  - `setting:general` Automatically play the next voice note: continuous playback across consecutive voice notes.
  - `setting:general` Automatically send GIFs after selection: send picked GIF immediately vs attach to draft.
  - `setting:general` Disable automatic replacement of emoticons with emojis: toggle `:)` → `🙂` replacement in the composer.
  - `setting:general` Downloads location <path>: default attachment download folder.
  - `setting:general` Enable emoji autocomplete: toggle `:` emoji autocomplete in the composer.
  - `setting:general` Microphone: recording input device selector for voice notes.
  - `menu:File` Open…: File ▸ Open… (⌘O) attach file menu item.
- Deferred to later milestones or not planned in iteration 1 (14 ledger rows):
  - `command` Join a Matrix room: not planned in iteration 1 (Courier runs five non-Matrix bridges with no generic Matrix room join).
  - `command` Open space in new window: part 4.6 window management.
  - `command` Profile: not planned in iteration 1 (no Beeper cloud account profile pane).
  - `component` ChangeEmailBrowserWindow.tsx: not planned in iteration 1 (no Beeper cloud account email management).
  - `component` ChatThemeBrowserWindow.tsx: part 4.7 (Appearance, wallpapers and per-chat themes).
  - `component` ChatThemeWindow.tsx: part 4.7 (Appearance, wallpapers and per-chat themes).
  - `component` DeleteAccountModal.tsx: not planned in iteration 1 (no Beeper cloud account deletion).
  - `component` DeleteAccountPrompt.tsx: not planned in iteration 1 (no Beeper cloud account deletion).
  - `component` ThreadedRepliesBrowserWindow.tsx: thread replies open in the right-hand Thread Replies pane (4.3); detached thread windows are part 4.6 window management.
  - `hotkey` Message: Talk to Type: part 4.7 (`AIProvider` dictation stub).
  - `menu:File` Open Chat in New Window: part 4.6 window management (along with double-click chat "Open in New Window").
  - `setting:ai` Use OpenAI's Whisper model for Talk to Type and transcribing: part 4.7 (`AIProvider` voice-note transcription stub).
  - `setting:general` Show Telegram Topics as separate spaces: not planned in iteration 1 (`mautrix-telegram` does not expose forum topics as separate portal spaces).
  - `setting:general` Show WhatsApp Communities as separate spaces: not planned in iteration 1 (`mautrix-whatsapp` bridges community rooms directly without a separate space hierarchy).

## Part 4.5b: rich media playback, capture, previews and media viewer

Inline photos, BlurHash placeholders, photo and video galleries, view-once photos, videos and voice notes, inline video with Picture in Picture, voice-note waveform playback with continuous play and a floating audio bar across chats, voice-note recording in the message box, inline PDFs, downloadable file cards, drag-and-drop and pending attachments with per-network size checks, location cards, link previews, click-to-load external embeds, the full-window attachment lightbox, and the Media Viewer window. What leaves this Mac for a network is:

- photos, videos, audio files, voice notes, documents and locations when you press Send;
- fetching the first `https` web address in a message you send ONLY when you turn "Disable link previews in outgoing messages" off (it is on out of the box, so nothing is fetched unless you change it);
- loading an external embed from YouTube, Vimeo, Spotify or Loom ONLY after you click "Load Embed" on that message (or turn "Load external embeds automatically" on);
- opening a map pin in Apple Maps or Google Maps, or opening a web link in your browser, when you click it.

Stays on this Mac: viewing photos, galleries, videos, Picture in Picture, voice notes, audio files and PDFs; voice-note and view-once played marks (none of the five networks’ bridges send or receive voice-note played receipts); view-once opening and expiry on this Mac; microphone recordings while recording or reviewing until you press Send; incoming link previews and thumbnails (drawn only from text and local files already delivered by the bridge); location cards (drawn with an offline coordinate grid and no map tile downloads); downloaded attachments; the attachment lightbox; and the Media Viewer window.

### Before you start

- Install the build with `bazel run --config=macos-app //apps/desktop/courier/app:install`. Your chats and networks stay as they are.
- Out of the box in Settings ▸ Messages (⌘,): under **Messages**, "Disable link previews in outgoing messages" is on, "Load external embeds automatically" is off, "Automatically play the next voice note" is on, and "Microphone" is "System Default"; under **Downloads**, "Downloads location" is `~/Downloads` and "Always ask where to save files before downloading" is off.
- Microphone, Contacts, Calendar and the Downloads folder never ask for permission when Courier opens. Each asks once, only when you use that feature.
- Do not open the same chat in the other chat app while testing. It would send a read receipt.
- Never test on a real person’s chat. Use a chat with yourself or a test account. Never open a real chat in Beeper while testing.

### Check these first

All app checks are by hand on real accounts: there is no fake-network app mode, and views were checked only as PNG snapshots. Look at these before anything else.

- [ ] In the signed installed app: pressing record (⌘⇧A or the microphone button) asks for the microphone once ("Courier records voice notes only while you hold record. Recordings stay on this Mac until you send them."); opening a hover card’s Contacts and the Calendar pane each ask once (the entitlements fix, #3915); after "Don’t Allow" nothing asks again.
- [ ] Downloading an attachment the first time asks for the Downloads folder, with Courier’s reason ("Courier saves the attachments you download to this folder. Nothing else in it is read or changed.").
- [ ] Sending a link with the setting off ("Disable link previews in outgoing messages" left on, its default, so outgoing link previews are off): no preview appears on the other side, and the Mac makes no request to the link (the outgoing preview is suppressed).
- [ ] An embed shows "Load embed from <host>" and nothing loads until clicked.
- [ ] A view-once photo opens once, then shows "Opened"; it never appears in the Media Viewer.
- [ ] A 1 GB+ video sends on Telegram without the app’s memory jumping (streamed from disk), and WhatsApp/Signal/Google Messages/Slack enforce a 100 MB ceiling so in-memory bridge uploads stay bounded.
- [ ] Voice notes on WhatsApp and Signal arrive as voice notes (not files) on the phone.
- [ ] ⌘O stays Attach Files (Message ▸ Attach Files…); ⌘D downloads (Message ▸ Download Attachments).
- Do the by-hand run on the installed build, once, start to end. Tick each step as you go:
  - [ ] Send and receive 1, 2, 3, 4 and 5+ photos in a test chat: check the BlurHash placeholder while loading, the 1–4+ gallery grid with "+N" overflow badge, and clicking a tile to open the lightbox (`Space`, `+`/`-`, `0`, `R`, `⌘C`, `⌘D`, `Esc`).
  - [ ] Receive a view-once photo or voice note from a test phone on Signal or Telegram: check the "View-once Photo" / "View-once Voice Note" pill ("Tap to view once on this Mac"), open it once in the sheet, close it, and check the pill now says "Opened" ("View-once media expired on this Mac") and cannot be reopened, downloaded or seen in the Media Viewer.
  - [ ] Play an `.mp4` video inline (`0.5×`–`2×` speed and scrub bar), click the Picture in Picture button ("Picture in Picture"), switch to another chat, and check the floating "Picture in Picture" window stays playing on top.
  - [ ] Play two consecutive voice notes at `1.5×` with "Automatically play the next voice note" on: check the waveform scrubs, finishing the first marks it played and starts the second, and switching chats docks the floating audio bar at the top of the window with Play/Pause, scrubber, speed pill, "Jump to Message" and Close.
  - [ ] Choose your microphone in Settings ▸ Messages, press ⌘⇧A, record a short voice note, check the live waveform and the red stop button ("Stop recording"), and send it to a WhatsApp chat and a Signal chat; check on the phone that both arrive as native voice notes.
  - [ ] Drag a multi-page PDF into a chat (and Shift-drop another file to send immediately): check the inline PDF page controls ("Previous Page", "Page X of Y", "Next Page"), press ⌘O to attach a file, and press ⌘D on an attachment to check both saving straight to your Downloads location and asking where to save when "Always ask where to save files before downloading" is on.
  - [ ] View a shared location card and click "Open in Apple Maps", "Open in Google Maps" and "Copy Location"; send a link with "Disable link previews in outgoing messages" on (no preview sent or fetched), then turn it off and send an `https` link (preview card attached); click "Load Embed" on a video link.
  - [ ] Open the Media Viewer window from "See All" in Chat Info’s Shared Media, Files or Links section, and check the "Media", "Links" and "Docs" tabs, "Sent By" ("All", "You", "Others"), "Sort" ("Newest", "Oldest"), the "Search captions, links, or filenames…" field, "Go to Message", and multi-select "Download Selected" and "Clear Selection".

### The five things to check

These are the five things this part was most worried about. Look at them before the rest.

- [ ] Links, embeds and locations make zero unconsented network requests. Incoming link previews only show the text and local `mxc://courier.local/...` thumbnail already stored by the bridge, ignoring any remote image URL. With "Disable link previews in outgoing messages" on (the default), sending a link makes zero HTTP requests from this Mac and tells WhatsApp, Signal, Telegram and Slack to suppress link unfurling. External embeds show "Load embed from <host>" ("External embed from <host> is blocked to protect your IP address") and create no web view until you click "Load Embed". Location cards draw an offline coordinate grid with zero map tile requests.
- [ ] View-once media opens once on this Mac and never leaks into other surfaces. A view-once photo, video or voice note shows as a locked pill ("View-once Photo", "View-once Video" or "View-once Voice Note") with no thumbnail, Quick Look, Copy or Download. Opening it presents the "View-once from <Sender>" sheet (which blocks window screenshots where macOS allows it and shows "Screenshots and screen recordings of this window are blocked where macOS allows it. A camera pointed at the screen can’t be stopped."). Closing the sheet marks it played in the database, redacts its file path from subsequent reads, changes the pill to "Opened" ("View-once media expired on this Mac"), and keeps it out of the lightbox and the Media Viewer window.
- [ ] Voice notes arrive as native voice notes on the phone and play continuously on this Mac. Recording a voice note (⌘⇧A) sends `audio/ogg; codecs=opus` on WhatsApp (converting from M4A via `ffmpeg` when installed) and `audio/mp4` / `audio/aac` on networks that accept MP4/AAC natively, with duration and waveform metadata so the phone shows a voice note instead of a generic audio file. Playing a voice note with "Automatically play the next voice note" on marks it played when it finishes and automatically starts the next consecutive voice note in the chat; switching chats docks the player at the top of the window without interrupting audio.
- [ ] Large files stream from disk without spiking memory and respect each network’s file size ceiling. Attaching a file larger than the chat network’s limit shows an orange warning on the chip ("Exceeds <Network> <limit> limit"). Sending a 1 GB+ video on Telegram streams the file from disk through the media store and bridge upload without buffering the whole file in memory, while networks whose bridges buffer uploads in memory (WhatsApp, Signal, Google Messages, Slack) are capped at 100 MB.
- [ ] Downloaded and opened attachments keep macOS quarantine metadata and never overwrite existing files. Pressing ⌘D or clicking Download saves to your configured Downloads location (or opens a Save panel when "Always ask where to save files before downloading" is on), suffixes duplicates as `file (2).ext`, and stamps `com.apple.quarantine` on every saved or Quick Look temp file so macOS Gatekeeper checks executables.

### What to expect on each network

Courier reads these limits and formats from each network’s pinned bridge capabilities (`mautrix-whatsapp`, `mautrix-signal`, `mautrix-telegram`, `mautrix-gmessages`, `mautrix-slack`).

| | WhatsApp | Signal | Telegram | Google Messages | Slack |
|---|---|---|---|---|---|
| Max file size | 100 MiB (Courier cap; bridge 2000 MiB) | 100 MiB | 2 GiB (4 GiB Premium; 10 MiB photo) | 100 MiB RCS (1 MiB MMS) | 100 MiB (Courier cap; bridge 1 GB) |
| Images and captions | JPEG full, PNG/WebP partial, GIF partial if `ffmpeg`; caption up to 65536 | GIF, PNG, JPEG, WebP, BMP, AVIF full (4096×4096); caption up to 2000 | JPEG full, WebP/PNG/GIF partial (10 MiB photo, larger sent as document); caption 1024 (2048 Premium) | PNG, JPEG, GIF, BMP, WBMP, WebP full; RCS sends caption as a separate text message | JPEG, PNG, GIF, WebP full; caption up to 40000 |
| Videos | MP4, 3GPP full (100 MiB cap); WebM, QuickTime partial if `ffmpeg`; caption full | MP4, OGG, WebM full (100 MiB); caption full | MP4 full (2 GiB / 4 GiB Premium); caption full | MP4, 3GPP, WebM full (100 MiB RCS) | MP4, WebM full (100 MiB cap); caption full |
| Audio files | MPEG, MP4, OGG, AAC, AMR full; caption dropped | AAC, MPEG, MP3, FLAC full; caption unsupported | MPEG, MP4 full; caption full | AAC, AMR, MPEG, MP4, MP4-LATM, 3GPP, OGG full | MPEG, WebM, WAV full; caption full |
| Voice notes and waveform | `audio/ogg; codecs=opus` full (`audio/ogg` rewritten); waveform 0–100 and duration both ways | Outgoing `audio/aac` full (`audio/ogg` converted via `ffmpeg`), max 3600s; incoming converted to `.ogg` opus if `ffmpeg`, waveform not bridged | `audio/ogg`, `audio/mpeg`, `audio/mp4` full; 5-bit packed waveform and duration both ways | Outgoing `audio/mp4` full (`audio/ogg` converted via `ffmpeg` to `.m4a`); incoming tagged voice and converted to `.ogg` if `ffmpeg` | `audio/webm; codecs=opus` and `audio/mp4` (`.m4a`) full (`audio/ogg` partial via `ffmpeg`), max 300s; incoming `slack_audio` has waveform and duration |
| Voice-note played receipts | Not bridged (tracked on this Mac only) | Not bridged (tracked on this Mac only) | Not bridged (tracked on this Mac only) | Not bridged (tracked on this Mac only) | Not bridged (tracked on this Mac only) |
| Generic files and PDFs | `*/*` full (100 MiB cap), caption full | `*/*` full (100 MiB), caption full | `*/*` full (2 GiB / 4 GiB Premium), caption full | `application/*`, `text/*` full (100 MiB RCS) | `*/*` full (100 MiB cap), caption full |
| GIFs | MP4 (`GifPlayback`) full, `image/gif` transcoded via `ffmpeg` | `image/gif` and MP4 full | MP4 full, `image/gif` partial | `image/gif` full | `image/gif` full |
| Stickers | WebP full, PNG/JPEG/Lottie partial; no caption | PNG, APNG full, WebP partial, GIF partial if `ffmpeg`; no caption | WebP, Lottie, WebM full, JPEG/PNG partial | Not supported | Not in bridge capabilities (outgoing `m.sticker` converted to `m.image`) |
| View-once media | Outgoing not supported; incoming bridged as normal media when `DisableViewOnce` is false | Outgoing not supported; incoming sets a 5-minute after-read disappearing timer when `DisappearViewOnce` is true | Outgoing not supported; incoming sets a 15-second after-read disappearing timer | Not supported | Not supported |
| Location messages | Full both ways (`geo:<lat>,<long>`) | Partial (incoming location; outgoing `geo:` formatted as a text URL) | Full both ways (`geo:<lat>,<long>`) | Not supported | Rejected |
| Link previews | Full incoming and outgoing; empty preview list suppresses preview | Full incoming and outgoing (with uploaded image) | Incoming webpage to preview; outgoing empty preview list sets `NoWebpage: true` | Not supported | Incoming attachments to preview; outgoing empty preview list disables link unfurling |
| BlurHash on attachments | Field in shared `FileInfo`; not computed by bridge | Preserved incoming and outgoing (`Blurhash` / `AnoaBlurhash`) | Field in shared `FileInfo`; not computed by bridge | Field in shared `FileInfo`; not computed by bridge | Field in shared `FileInfo`; not computed by bridge |

- [ ] Each cell above holds on the real network. Check at least sending a photo, video, voice note, PDF and link on every network you have.
- [ ] On WhatsApp, sending a voice note requires `audio/ogg; codecs=opus` (Courier converts recorded `.m4a` voice notes via `ffmpeg` when installed on this Mac at `/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg`, or `/opt/local/bin/ffmpeg`; if `ffmpeg` is missing, Courier shows `"Sending voice notes on WhatsApp needs ffmpeg. Install it with Homebrew (brew install ffmpeg), then try again."`).
- [ ] On Google Messages, RCS sends an image caption as a separate text message, and link previews, stickers, view-once media and location messages are not supported by the bridge.
- [ ] On Signal, outgoing location messages are formatted by the bridge as a text URL, and BlurHash placeholders are preserved both ways.
- [ ] None of the five bridges send or receive voice-note played receipts, so the blue unplayed dot and "Played" mark on voice notes are tracked on this Mac only.

### Keys

- [ ] `hotkey` Chat: Send File: ⌘O opens the file picker ("Choose files to send", "Attach") to attach files in the message box (Message ▸ Attach Files…).
- [ ] `hotkey` Download Attachments: ⌘D downloads the attachments on the selected message (or the item open in the lightbox) to your Downloads location, or asks where to save when "Always ask where to save files before downloading" is on (Message ▸ Download Attachments).
- [ ] `hotkey` Message: Record Audio: ⌘⇧A starts recording a voice note in the message box, and sends it when pressed again while recording or reviewing (Message ▸ Record Voice Note).

### Settings

- [ ] `setting:appearance` Disable link previews in outgoing messages: Settings ▸ Messages ▸ Messages, "Disable link previews in outgoing messages", on out of the box. When on, Courier never fetches a web address you send and tells the network not to add a preview. When off, Courier fetches the first `https` link on send to attach a preview.
- [ ] `setting:appearance` Load external embeds automatically: Settings ▸ Messages ▸ Messages, "Load external embeds automatically", off out of the box. When off, YouTube, Vimeo, Spotify and Loom links show "Load embed from <host>" until you click "Load Embed".
- [ ] `setting:general` Automatically play the next voice note: Settings ▸ Messages ▸ Messages, "Automatically play the next voice note", on out of the box. When on, finishing one voice note marks it played and starts the next consecutive voice note in the chat.
- [ ] `setting:general` Microphone: Settings ▸ Messages ▸ Messages, "Microphone", choosing "System Default" or any connected audio input device for recording voice notes.
- [ ] `setting:general` Downloads location <path>: Settings ▸ Messages ▸ Downloads, "Downloads location", showing the folder path (`~/Downloads` by default) with a "Choose…" button ("Choose a folder for downloaded attachments").
- [ ] `setting:general` Always ask where to save files before downloading: Settings ▸ Messages ▸ Downloads, "Always ask where to save files before downloading", off out of the box. When on, ⌘D and Download open a Save panel every time.

### Menus

- [ ] `menu:File` Open…: File ▸ Open… opens the file picker to attach files to the open chat’s message box. Message ▸ Attach Files… keeps ⌘O, alongside Message ▸ Download Attachments (⌘D) and Message ▸ Record Voice Note (⌘⇧A).

### Components

**Photos, galleries, BlurHash and view-once media**

- [ ] `component` EnhancedImg.tsx: Inline photos and stickers render at their aspect ratio (clamped between 120×80 and 360×320) with a decoded BlurHash placeholder while loading, animated GIF and WebP playback, an automatic "GIF" badge on looping GIF videos, and single-click opening in the lightbox.
- [ ] `component` LoadingAttachment.tsx: While an attachment is loading, its frame shows a decoded BlurHash image (when present) and a translucent placeholder card with a spinner.
- [ ] `component` FileRowSpinner.tsx: File and media attachment rows show a small progress spinner while the attachment is loading or being prepared.
- [ ] `component` ImageError.tsx: When an image file is missing or cannot be decoded, the bubble shows a muted broken-image card with the filename and "Image unavailable".
- [ ] `component` TranscodedAttachment.tsx: Attachments that the bridge transcoded (`fi.mau.gif` MP4 GIFs or voice notes transcoded to `.ogg` / `.m4a`) show a subtle "Transcoded" badge when applicable and play inline.
- [ ] `component` GalleryGrouper.tsx: Two or more consecutive image or video attachments from the same sender (or multiple image/video attachments on one message, excluding view-once items) group into a 1, 2, 3 or 4+ tile grid with a "+N" badge on the fourth tile when there are more than four.
- [ ] `component` GalleryVideoPoster.tsx: Video tiles in a gallery grid show their poster frame (or first frame), a centered play badge, and a bottom-right duration pill (`m:ss`).
- [ ] `component` ViewLimitedMediaViewer.tsx: View-once photos, videos and voice notes render in the timeline as a locked pill ("View-once Photo", "View-once Video" or "View-once Voice Note", "Tap to view once on this Mac"). Clicking an unopened pill opens the "View-once from <Sender>" sheet ("Close"), which blocks window screenshots where macOS allows it ("Screenshots and screen recordings of this window are blocked where macOS allows it. A camera pointed at the screen can’t be stopped."). Once closed, the pill shows "Opened" ("View-once media expired on this Mac") and the sheet says "This view-once media was already opened and is gone on this Mac."

**Inline video and Picture in Picture**

- [ ] `component` BrandVideo.tsx: Video attachments play inline with Play/Pause, a draggable timeline scrubber, elapsed/duration time (`m:ss`), a Mute/Unmute button, a playback speed menu (`0.5×`, `1×`, `1.5×`, `2×`), a Picture in Picture button, and a Fullscreen (lightbox) button. Looping GIF videos (`is_gif`) auto-play muted without transport chrome and show a "GIF" badge.
- [ ] `component` PictureInPictureBrowserWindow.tsx: Clicking the Picture in Picture button on an inline video opens a floating "Picture in Picture" panel that stays on top when you switch chats, with Play/Pause, "Return to Chat" and Close controls.

**Voice notes, floating audio player and recording**

- [ ] `component` Audio.tsx: Voice notes and audio attachments show a Play/Pause button, a 28-bar interactive waveform scrubber, elapsed/duration time (`m:ss`), a speed pill that cycles `0.5×` → `1×` → `1.5×` → `2×`, and an unplayed blue dot that clears when playback finishes (or when you click "Mark Played" / "Mark Unplayed").
- [ ] `component` GlobalAudioPlayer.tsx: When you switch to another chat while a voice note or audio file is playing, a floating audio bar docks at the top of the window showing the sender and chat title, Play/Pause, a mini scrubber, elapsed time, the speed pill, "Jump to Message", and Close.
- [ ] `component` BrandStopButton.tsx: Pressing the microphone button ("Record Voice Note (⌘⇧A)") or ⌘⇧A in the message box starts recording a voice note with a live elapsed timer (`0:00`), live 36-bar waveform, a "Cancel recording" button, a red stop button ("Stop recording" / "Stop recording to review"), and a "Send voice note" button; stopping shows "Voice note ready" ("Discard recording", "Send") so you can review before sending, and pressing ⌘⇧A again sends it.

**PDFs, files, drag-and-drop and pending attachments**

- [ ] `component` PDF.tsx: PDF attachments render an inline page preview using macOS PDFKit without spawning a helper process.
- [ ] `component` PDFAttachment.tsx: Each inline PDF card has a header bar with the filename, file size, "Previous Page" and "Next Page" buttons around "Page X of Y" on multi-page PDFs, an "Open" button, and a "Download" ("Download (⌘D)") button.
- [ ] `component` FileAttachment.tsx: Non-inline files show a file card with a category icon, filename, human-readable byte size (`1.4 MB`), "Quick Look (Space)", "Open", and "Download (⌘D)" buttons (plus "Download Attachment" in the right-click menu and ⌘D).
- [ ] `component` FilePlaceholder.tsx: File cards show distinct icons and labels for Audio, PDF, Text, Archive and Document attachments.
- [ ] `component` PendingAttachments.tsx: Attached, pasted or dropped files sit in a horizontal strip above the message box with a thumbnail or icon, filename, size, an orange warning ("Exceeds <Network> <limit> limit") when a file is over the chat network’s size limit, and a "Remove attachment" ("Remove <filename>") button.
- [ ] `component` FileDropOverlay.tsx: Dragging files over the chat shows a drop target reading "Drop files to attach to your message" with "Hold ⇧ Shift to send immediately" (or, when Shift is held, "Release to send immediately").

**Locations, link previews and external embeds**

- [ ] `component` Location.tsx: Location messages (`geo:<lat>,<lon>`) show an offline coordinate grid with a pin badge, label, formatted latitude and longitude, and three action buttons: "Open in Apple Maps", "Open in Google Maps" and "Copy Location" ("Copied").
- [ ] `component` MessageIFrame.tsx: Incoming link previews show the site domain, title, description and local thumbnail (when the bridge supplied one). When a link matches YouTube, Vimeo, Spotify or Loom and "Load external embeds automatically" is off, the card shows "Load embed from <host>" ("External embed from <host> is blocked to protect your IP address") with "Load Embed" and "Open in Browser", loading a sandboxed web view only after you click "Load Embed".

**Attachment lightbox and Media Viewer window**

- [ ] `component` AttachmentCarousel.tsx: Clicking an inline photo or gallery tile opens the full-window lightbox with Previous/Next navigation (`←`/`→`), "Go to Message", "React", "Reply", "Copy Image" (`⌘C`), "Quick Look" (`Space`), "Download" (`⌘D`), "Close" (`Esc`), "Zoom Out" (`-`), "Reset Zoom" (`0`), "Zoom In" (`+`), "Rotate 90°" (`R`), "Flip Horizontally", "Flip Vertically", and a bottom thumbnail strip.
- [ ] `component` MediaViewerBrowserWindow.tsx: Clicking "See All" in Chat Info’s Shared Media, Files or Links section (or running "Media viewer") opens the "Media Viewer" window with "Media", "Links" and "Docs" tabs, a "Sent By" filter ("All", "You", "Others"), a "Sort" picker ("Newest", "Oldest"), a "Search captions, links, or filenames…" field, and multi-select "Download Selected", "Delete Selected" ("Delete for Me", "Unsend for Everyone"), "Go to Message" and "Clear Selection".
- [ ] `component` MediaWithSender.tsx: Each tile or row in the Media Viewer shows the sender’s name, date, caption or filename, and a "Go to Message" button that jumps the main window to that message in the chat.

### Commands

These are registered in Courier for the command bar (⌘J), which part 4.7 builds. They have no tick box here: they are "registered; shown in ⌘J by 4.7". The ones with a menu item or key above are checked there.

- `command` Media viewer: registered as "Media viewer" in `CommandSet.chatInfo` and opened from "See All" in Chat Info’s Shared Media, Files and Links sections.
- Courier also registers "Attach file" (⌘O), "Download attachments" (⌘D) and "Record voice note" (⌘⇧A) in `CommandSet.messaging`.

### How it behaves

Not failures. Do not report these as bugs.

- ⌘O is Message ▸ Attach Files… (and File ▸ Open… also attaches files to the open chat). ⌘D is Message ▸ Download Attachments. ⌘⇧A starts recording a voice note, and pressing ⌘⇧A again while recording or reviewing sends it.
- "Disable link previews in outgoing messages" is on out of the box so typing or sending a link never contacts the destination website unless you turn that setting off. When you turn it off, Courier fetches only the first `https` link on send (up to 3 seconds) to attach a preview card.
- "Load external embeds automatically" is off out of the box so YouTube, Vimeo, Spotify and Loom links never contact the embed host or reveal your IP address until you click "Load Embed".
- Location cards draw an offline coordinate grid on this Mac and never download map tiles; clicking "Open in Apple Maps" or "Open in Google Maps" opens the coordinates in that app or browser.
- None of the five networks’ bridges send or receive voice-note played receipts. Marking a voice note played (automatically at the end of playback, or via "Mark Played" in the right-click menu) updates the blue dot on this Mac only.
- View-once enforcement is on this Mac: once you close the "View-once from <Sender>" sheet, Courier marks the item opened in its local database and refuses to return its file path again on this Mac. It also sets the window’s screen-capture sharing type to `.none` so macOS window screenshots and screen recordings omit the sheet, though a camera pointed at the screen cannot be stopped.
- Sending a voice note on WhatsApp requires `ffmpeg` on this Mac (`/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg`, or `/opt/local/bin/ffmpeg`) so Courier can convert the recorded `.m4a` into `audio/ogg; codecs=opus`. On Signal, Telegram, Google Messages and Slack, `.m4a` (`audio/mp4` / `audio/aac`) is sent directly without `ffmpeg`.

### Not ledger rows

The inventory has no row for these, but they are what this part was built to do.

**macOS privacy prompts and sandbox entitlements (#3915)**

- [ ] The signed `Courier.app` bundle carries `com.apple.security.device.audio-input`, `com.apple.security.personal-information.addressbook` and `com.apple.security.personal-information.calendars` in its entitlements, and `NSMicrophoneUsageDescription`, `NSContactsUsageDescription`, `NSCalendarsFullAccessUsageDescription` and `NSDownloadsFolderUsageDescription` in `Info.plist`.
- [ ] None of those four permissions are requested on app launch. Each prompts once on first use with Courier’s plain-English reason, and after "Don’t Allow" never prompts again.

**4.5a merged-chat selection and RPC guardrails**

- [ ] Selecting a merged chat highlights its row in the inbox and pinned strip (`AppModel.isOpen`), and no room-scoped engine RPC ever receives a `"merge:…"` identifier.

**Streaming large uploads and quarantined downloads**

- [ ] Sending a multi-hundred-megabyte or 1 GB+ video reads the file from disk by path without loading the whole file into JSON-RPC or app memory.
- [ ] Every file saved via ⌘D / Download or materialized for Quick Look (`OpenFileCache`) has `com.apple.quarantine` set and deduplicates filenames as `file (2).ext` so existing files are never overwritten.

### Carried to later parts

Not in 4.5b, and not expected to work yet:

- A reply-network shortcut (⌘L is Remind Me).
- Carried to part 4.5c (composer emoji, emoticons, stickers and GIFs — 10 ledger rows):
  - `component` Autocomplete.tsx: composer `:` emoji autocomplete popover.
  - `component` Emoji.tsx: composer plus-menu media and emoji items.
  - `component` EmojiItem.tsx: emoji picker cell.
  - `component` GifPicker.tsx: composer GIF picker UI (search provider stubbed in 4.7).
  - `component` StickerPicker.tsx: composer sticker picker.
  - `hotkey` Message: Send GIF: ⌘⇧G open GIF picker.
  - `hotkey` Message: Send Sticker: ⌘⌥⇧S open sticker picker.
  - `setting:general` Automatically send GIFs after selection: send picked GIF immediately vs attach to draft.
  - `setting:general` Disable automatic replacement of emoticons with emojis: toggle `:)` → `🙂` replacement in the composer.
  - `setting:general` Enable emoji autocomplete: toggle `:` emoji autocomplete in the composer.
- Deferred to later milestones or not planned in iteration 1 (14 ledger rows):
  - `command` Join a Matrix room: not planned in iteration 1 (Courier runs five non-Matrix bridges with no generic Matrix room join).
  - `command` Open space in new window: part 4.6 window management.
  - `command` Profile: not planned in iteration 1 (no Beeper cloud account profile pane).
  - `component` ChangeEmailBrowserWindow.tsx: not planned in iteration 1 (no Beeper cloud account email management).
  - `component` ChatThemeBrowserWindow.tsx: part 4.7 (Appearance, wallpapers and per-chat themes).
  - `component` ChatThemeWindow.tsx: part 4.7 (Appearance, wallpapers and per-chat themes).
  - `component` DeleteAccountModal.tsx: not planned in iteration 1 (no Beeper cloud account deletion).
  - `component` DeleteAccountPrompt.tsx: not planned in iteration 1 (no Beeper cloud account deletion).
  - `component` ThreadedRepliesBrowserWindow.tsx: thread replies open in the right-hand Thread Replies pane (4.3); detached thread windows are part 4.6 window management.
  - `hotkey` Message: Talk to Type: part 4.7 (`AIProvider` dictation stub).
  - `menu:File` Open Chat in New Window: part 4.6 window management (along with double-click chat "Open in New Window").
  - `setting:ai` Use OpenAI's Whisper model for Talk to Type and transcribing: part 4.7 (`AIProvider` voice-note transcription stub).
  - `setting:general` Show Telegram Topics as separate spaces: not planned in iteration 1 (`mautrix-telegram` does not expose forum topics as separate portal spaces).
  - `setting:general` Show WhatsApp Communities as separate spaces: not planned in iteration 1 (`mautrix-whatsapp` bridges community rooms directly without a separate space hierarchy).

## Part 4.5c: stickers, GIFs and composer emoji

Composer `:shortcode` emoji autocomplete (`EmojiAutocompletePicker.swift`, `EmojiCatalog.swift`, `ComposerModel.swift`), custom `:shortcode:` emoji import (`ComposerModel.importSticker` in `ComposerModel.swift`, `actions/stickers.go`), automatic emoticon-to-emoji replacement (`EmojiCatalog.trailingEmoticonReplacement` in `EmojiCatalog.swift`, `ComposerModel.applyEdit` in `ComposerModel.swift`), the sticker picker (`StickerPickerPopover.swift`, `actions/stickers.go`, `actions/actions.go`), the offline GIF picker (`GIFPickerPopover.swift`, `GIFProvider.swift`, `actions/actions.go`), the message box `+` menu and toolbar entry points (`ComposerView.swift`, `ConversationCommands.swift`, `CommandSet.swift`), the three composer settings in Settings ▸ Messages (`ComposerPreferences.swift`, `MessagesSettingsPane.swift`), and borderless sticker and looping GIF rendering in the timeline (`MessageBubble.swift`, `Timeline.swift`). What leaves this Mac for a network is:

- stickers (`message.sendSticker` via `actions.SendSticker` in `engine/internal/actions/actions.go`), GIFs (`message.sendGIF` via `actions.SendGIF` in `engine/internal/actions/actions.go`), and text messages containing replaced emoticons or completed `:shortcode:` text when you send them;
- syncing bridge sticker or emoji packs via `bridgev2.StickerImportingNetworkAPI` (`ListImagePacks` and `DownloadImagePack` in `engine/internal/actions/stickers.go`) only when you click "Sync Packs" (`stickers.list` with `refresh: true`; opening a chat calls `stickers.list` with `refresh: false` and never contacts the bridge).

Stays on this Mac: typing `:shortcode` in the message box and filtering standard and custom emoji candidates (`EmojiCatalog.search` in `EmojiCatalog.swift`, `EmojiAutocompletePicker` in `EmojiAutocompletePicker.swift`); automatic replacement of ASCII emoticons like `:)` → `🙂` while typing (`EmojiCatalog.trailingEmoticonReplacement` in `EmojiCatalog.swift`); importing local PNG, WebP, GIF or JPEG files into your sticker and custom emoji catalog (`stickers.import` via `actions.ImportSticker` and `actions.saveStickersCatalog` in `engine/internal/actions/stickers.go`); searching your recent GIFs or picking a `.gif` / `.mp4` loop from Finder in the GIF picker (`GIFPickerPopover` in `GIFPickerPopover.swift` and `StubGIFProvider` in `GIFProvider.swift` — online GIF search is disabled so no search query ever leaves your Mac); rendering borderless stickers and looping GIFs in the timeline (`StickerAttachmentView` and `GIFAttachmentView` in `MessageBubble.swift`); and pausing animated stickers and GIFs when macOS Reduce Motion is on (`StickerAttachmentView.shouldAnimate` and `GIFAttachmentView.shouldAnimate` in `MessageBubble.swift`).

### Before you start

- Install the build with `bazel run --config=macos-app //apps/desktop/courier/app:install`. Your chats and networks stay as they are.
- Out of the box in Settings ▸ Messages (⌘,) under **Composer** (`MessagesSettingsPane.swift`, `ComposerPreferences.swift`, verified by `ComposerPreferencesTests.testDefaultsMatchTheInventory` in `ComposerPreferencesTests.swift`): "Enable emoji autocomplete" (`enableEmojiAutocomplete`) is **on** (`true`), "Disable automatic replacement of emoticons with emojis" (`disableEmoticonReplacement`) is **off** (`false`), and "Automatically send GIFs after selection" (`autoSendGIFs`) is **off** (`false`).
- Online GIF search (`StubGIFProvider` in `GIFProvider.swift`, verified by `GIFProviderTests.testStubGIFProviderIsOfflineAndNeverTouchesNetwork` in `GIFProviderTests.swift`) is disabled (`isAvailable == false`) so nothing leaves your Mac when you open or type in the GIF picker.
- Do not open the same chat in another chat app while testing. It would send a read receipt.
- Never test on a real person’s chat. Use a chat with yourself or a test account. Never open a real chat in Courier (or another chat app) while testing.

### Check these first

All app checks are by hand on real accounts: there is no fake-network app mode, and views were checked as PNG snapshots (`ViewSnapshotTests.swift`). Look at these before anything else.

- [ ] Typing `:smi` in the message box opens `EmojiAutocompletePicker` (`EmojiAutocompletePicker.swift`) above the caret (`ComposerModel.shortcodeQuery` and `ComposerModel.pickEmoji` in `ComposerModel.swift`, verified by `ComposerModelTests.testEmojiShortcodeAutocompleteRespectsPreferenceAndPickReplacesToken` and `ComposerModelTests.testEmojiAutocompleteEscapeDismissesEvenOnRepeatedSelectionReport` in `ComposerModelTests.swift`); `↑`/`↓` moves the selection (`ComposerModel.moveEmojiSelection`), `Tab` or `Return` replaces `:smi` with the chosen emoji (`😄 ` for a Unicode candidate or `:shortcode: ` for a custom candidate), and `Escape` dismisses the popover (`ComposerModel.dismissEmojiAutocomplete`) without clearing your draft.
- [ ] Typing `:)` or `:-D` followed by a space or `Return` replaces the token with `🙂` or `😃` (`EmojiCatalog.trailingEmoticonReplacement` in `EmojiCatalog.swift` and `ComposerModel.applyEdit` in `ComposerModel.swift`, verified by `EmojiCatalogTests.testReplaceTrailingEmoticon` in `EmojiCatalogTests.swift` and `ComposerModelTests.testEmoticonReplacementRespectsPreferenceURLsAndCodeSpans` in `ComposerModelTests.swift`), while emoticons inside inline code (`TextEntity.Kind.code` or backticks `` `:)` ``), code blocks (`TextEntity.Kind.pre`), or URLs (`https://example.com/:)`) are not replaced, and turning "Disable automatic replacement of emoticons with emojis" (`ComposerPreferences.disableEmoticonReplacement`) on stops replacement.
- [ ] Pressing ⌘⌥⇧S (or Message ▸ Send Sticker…) opens `StickerPickerPopover` (`StickerPickerPopover.swift`, `ComposerModel.openStickerPicker` in `ComposerModel.swift`); clicking a sticker sends it immediately via `message.sendSticker` (`ComposerModel.sendSticker` in `ComposerModel.swift`, `actions.SendSticker` in `engine/internal/actions/actions.go`, verified by `ComposerModelTests.testSendStickerForwardsBridgedStickerHoldAndRespectsRoomCapability` and `TestSendStickerAndGIF` in `engine/internal/actions/send_test.go`), and both sent and received `m.sticker` events render borderless with no bubble background (`StickerAttachmentView` in `MessageBubble.swift`, `Timeline.describe` in `Timeline.swift`, verified by `MessagePresentationTests.testStickerEventProducesStickerAttachmentAndSuppressesBubbleBackgroundWhileKeepingReactionsTimestampAndReplyHeader` and `ViewSnapshotTests.testStickerAndGIFTimelineRenderingAndComposingSnapshots`).
- [ ] Pressing ⌘⇧G (or Message ▸ Send GIF…) opens `GIFPickerPopover` (`GIFPickerPopover.swift`, `ComposerModel.openGIFPicker` in `ComposerModel.swift`) with the offline privacy banner ("Online GIF search is disabled so nothing leaves your Mac. Choose a GIF file or pick a recent GIF below."); with `ComposerPreferences.autoSendGIFs` at its default (`false`), picking a GIF stages `ComposerModel.pendingGIF` (`PendingGIFPillView` in `ComposerView.swift`) so you can add an optional caption before pressing `Return`, and when `autoSendGIFs` is turned on (`true`), picking a GIF sends immediately (`ComposerModel.selectGIF` in `ComposerModel.swift`, verified by `ComposerModelTests.testSelectGIFAutoSendsOrStagesPendingGIFWithCaptionAndHold` in `ComposerModelTests.swift`).
- [ ] Turning on macOS System Settings ▸ Accessibility ▸ Display ▸ Reduce motion pauses animated stickers and looping GIFs in the timeline (`StickerAttachmentView.shouldAnimate` and `GIFAttachmentView.shouldAnimate` in `MessageBubble.swift`, verified by `ViewSnapshotTests.testStickerAndGIFReduceMotionAndFallbackAspectRatio` in `ViewSnapshotTests.swift`).
- Do the by-hand run on the installed build, once, start to end. Tick each step as you go (owner's by-hand day):
  - [ ] Open Settings ▸ Messages (⌘,) and check the three **Composer** toggles (`MessagesSettingsPane.swift`): "Enable emoji autocomplete" (on out of the box), "Disable automatic replacement of emoticons with emojis" (off out of the box), and "Automatically send GIFs after selection" (off out of the box).
  - [ ] In a test chat, type `let's go :smi`, navigate with `↑`/`↓`, and press `Return` to insert the emoji; then type `:party_parrot` and click "Add :party_parrot: to Custom Emoji" at the bottom of `EmojiAutocompletePicker`, choose a PNG/WebP/GIF/JPEG on your Mac in `StickerImportPicker`, type `:party_p` again, and pick the custom emoji from the list to check that `:party_parrot: ` is inserted into the draft.
  - [ ] Type `:)` and `<3` followed by a space and check they become `🙂 ` and `❤️ `; type `` `:)` `` and `https://example.com/:)` and check neither is replaced; toggle "Disable automatic replacement of emoticons with emojis" on in Settings ▸ Messages and check `:)` stays `:)` when followed by a space.
  - [ ] Press ⌘⌥⇧S (Message ▸ Send Sticker…), click "Import Sticker…" (`StickerImportPicker.run` in `StickerPickerPopover.swift`) to import a PNG, WebP, GIF, or JPEG image into the "Imported" tab, click "Sync Packs" to refresh bridge packs, search by name in "Search stickers", and click a sticker to send it on WhatsApp, Signal, and Telegram; check on your test chat and phone that the sticker delivers, renders in Courier without a bubble background, quotes "Sticker" when replied to, and shows the reply header above the borderless sticker when replying with a sticker.
  - [ ] Press ⌘⇧G (Message ▸ Send GIF…), click "Choose GIF from Mac…" (`GIFFilePicker.run` in `GIFPickerPopover.swift`) to pick a `.gif` or `.mp4` loop with "Automatically send GIFs after selection" at its default (off), check that `PendingGIFPillView` ("GIF") stages in the message box, type a caption, and press `Return` to send; then turn "Automatically send GIFs after selection" on in Settings ▸ Messages, open ⌘⇧G, pick the GIF from the recent grid, and check that it sends immediately and loops silently in a 12 pt rounded frame with a top-leading "GIF" badge on WhatsApp, Signal, Telegram, Google Messages, and Slack.
  - [ ] Click the `+` button in the message box (`ComposerView.plusMenu` in `ComposerView.swift`) and check "Add Emoji…" (opens the macOS character palette via `NSApp.orderFrontCharacterPalette`), "Add GIF…" and "Add Sticker…", plus the GIF (`"GIF"`), sticker (`sparkles.rectangle.stack`), and emoji (`face.smiling`) buttons on the right of the message box; switch to a Google Messages chat and a Slack chat and verify the sticker button and menu items are disabled with `"Send Sticker (Unavailable for Google Messages)"` / `"Add Sticker… (Unavailable for Google Messages)"` and `"Send Sticker (Unavailable for Slack)"` / `"Add Sticker… (Unavailable for Slack)"`.

### The five things to check

These are the five things this part was most worried about. Look at them before the rest.

- [ ] GIF picking and emoji autocomplete make zero network requests (`StubGIFProvider` in `GIFProvider.swift`, `GIFPickerPopover.swift`, `EmojiCatalog.swift`, verified by `GIFProviderTests.testStubGIFProviderIsOfflineAndNeverTouchesNetwork` in `GIFProviderTests.swift`). Opening `GIFPickerPopover` or typing in "Search recent GIFs" filters only `composer.recentGIFs` on this Mac and shows "Online GIF search is disabled so nothing leaves your Mac. Choose a GIF file or pick a recent GIF below." Emoji autocomplete and emoticon replacement run entirely from `EmojiCatalog.shared` and `composer.customEmojis`.
- [ ] Stickers and GIFs respect each network’s bridge capabilities (`actions.FeaturesOf` in `engine/internal/actions/features.go`, `actions.SendSticker` and `actions.SendGIF` in `engine/internal/actions/actions.go`, verified by `TestStickerAndGIFRoomFeatures` in `engine/internal/actions/features_test.go`, `TestSendGIFImageChecksImageCapabilityMaxSizeAndLeavesNoBlob`, and `TestSendStickerRejectsSpoofedMimeTypeAndLeavesNoBlob` in `engine/internal/actions/send_test.go`). Before decoding or writing a blob into `media.Store`, `SendSticker` and `SendGIF` sniff the actual file bytes and check the room’s `FileFeatureMap` support and `MaxSize` limit so disallowed, spoofed, or oversized files are rejected with `ErrUnsupportedFeature` or `ErrTooLarge` without leaving an orphan blob on disk. On Google Messages and Slack — where neither `mautrix-gmessages` nor `mautrix-slack` declares `event.CapMsgSticker` in `FileFeatures` — `FeaturesOf` sets `Sticker.Supported = false`, `SendSticker` refuses with `ErrUnsupportedFeature`, and `ComposerModel.canSendSticker` disables the sticker entry points.
- [ ] Imported stickers and custom emoji stay separated by usage (`actions.ImportSticker` and `actions.ListStickers` in `engine/internal/actions/stickers.go`, `store.ListRecentStickers` and `store.ListRecentGIFs` in `engine/internal/store/stickers.go`, `StickerPickerPopover.stickerItems(in:)` in `StickerPickerPopover.swift`, verified by `TestImportAndListStickers` in `engine/internal/actions/stickers_test.go`, `ComposerModelTests.testImportStickerValidatesFileAndUpdatesCatalog` in `ComposerModelTests.swift`, and `ViewSnapshotTests.testEmojiAutocompletePublicInterfaceThumbnailLoaderAndStickerEmoticonFilter` in `ViewSnapshotTests.swift`). Importing without a shortcode records `usage: ["sticker"]`; importing with a shortcode records `usage: ["emoticon", "sticker"]`; emoticon-only items (`usage: ["emoticon"]`, such as Slack workspace custom emoji synced via `StickerImportingNetworkAPI`) are populated in `composer.customEmojis` and filtered out of `StickerPickerPopover.stickerItems(in:)`.
- [ ] Stickers render borderless and GIFs loop silently with Reduce Motion support (`StickerAttachmentView` and `GIFAttachmentView` in `MessageBubble.swift`, `Timeline.describe` and `Timeline.build` in `Timeline.swift`, verified by `MessagePresentationTests.testStickerEventProducesStickerAttachmentAndSuppressesBubbleBackgroundWhileKeepingReactionsTimestampAndReplyHeader`, `MessagePresentationTests.testGIFEventProducesGIFAttachmentWithOptionalCaption` in `MessagePresentationTests.swift`, and `ViewSnapshotTests.testStickerAndGIFReduceMotionAndFallbackAspectRatio` in `ViewSnapshotTests.swift`). `TimelineMessage.suppressesBubbleBackground` is `true` for `m.sticker` (when not view-once) so `MessageRowView` draws no bubble background tint while keeping reactions, timestamp, "Sent" status and reply headers legible. GIFs (`m.image` or `m.video` with `info["fi.mau.gif"] == true`) render in a 12 pt rounded frame with a top-leading "GIF" badge and optional caption below, and both pause when macOS Reduce Motion is enabled. Redacted and view-once events keep `sticker == nil` and `gif == nil`.
- [ ] `Escape` and `Return` priority in the message box never loses a draft (`ComposerView.swift`, `ComposerModel.escape` and `ComposerModel.submit` in `ComposerModel.swift`, verified by `ComposerModelTests.testEmojiAutocompleteEscapeDismissesEvenOnRepeatedSelectionReport`, `ComposerModelTests.testOpenEmojiAutocompleteWithNoShortcodeDoesNotSwallowNextEscape`, and `ComposerModelTests.testSlashGifWhenUnsupportedKeepsTextAndShowsNoticeAndWhileGIFStagedDoesNotSendSlashGifAsCaption` in `ComposerModelTests.swift`). When `EmojiAutocompletePicker` is open, `↑`/`↓`, `Tab` and `Return` navigate or pick the highlighted candidate instead of moving focus or sending the draft, and pressing `Escape` dismisses the open emoji autocomplete, sticker picker, or GIF picker popover before cancelling an edit or clearing a reply banner.

### What to expect on each network

Courier reads these sticker and GIF rules from each network’s pinned bridge (`mautrix-whatsapp@v0.2609.0`, `mautrix-signal@v0.2609.0`, `mautrix-telegram@v0.2609.0`, `mautrix-gmessages@v0.2609.0`, `mautrix-slack@v0.2609.1`) via `actions.FeaturesOf` (`engine/internal/actions/features.go`, verified by `TestStickerAndGIFRoomFeatures` in `engine/internal/actions/features_test.go`).

| | WhatsApp | Signal | Telegram | Google Messages | Slack |
|---|---|---|---|---|---|
| Outgoing stickers (`message.sendSticker`, `actions.SendSticker`) | `CapMsgSticker`: `image/webp` full (`CapLevelFullySupported`), `image/png`, `image/jpeg`, `video/lottie+json` partial (`CapLevelPartialSupport`; bridge comment notes `video/lottie+json` is only accepted if imported from WhatsApp); `Caption: CapLevelDropped` (`captions: false`); bridge `MaxSize: WAMaxFileSize` (`2000 * 1024 * 1024` = 2000 MiB), capped to 100 MiB by `networkFileCeiling("whatsapp")` (`mautrix-whatsapp@v0.2609.0/pkg/connector/capabilities.go:58,126-136`) | `CapMsgSticker`: `image/png`, `image/apng` full (`CapLevelFullySupported`), `image/webp` partial (`CapLevelPartialSupport`), `image/gif` via `supportedIfFFmpeg()` (`CapLevelPartialSupport` if `ffmpeg.Supported()`, else `CapLevelRejected`); `Caption: CapLevelDropped` (`captions: false`); `MaxSize: MaxFileSize` (`100 * 1024 * 1024` = 100 MiB) (`mautrix-signal@v0.2609.0/pkg/connector/capabilities.go:33-38,48,115-125`) | `CapMsgSticker`: `image/webp`, `video/lottie+json`, `video/webm` full (`CapLevelFullySupported`), `image/jpeg`, `image/png` partial (`CapLevelPartialSupport`, converted to webp by bridge); `Caption` unset (`captions: false`); `MaxSize` unset (`0` on `CapMsgSticker`, so `SendSticker` falls back to `MsgImage.MaxSize` = 10 MiB for image MIME types or `MaxFileBytes` = 90 MiB otherwise) (`mautrix-telegram@v0.2609.0/pkg/connector/capabilities.go:100-110,146-155`) | `CapMsgSticker` omitted in both `rcsCaps.File` and `smsCaps.File` (`mautrix-gmessages@v0.2609.0/pkg/connector/capabilities.go:125-150,162-192`); `Sticker.Supported == false`, `canSendSticker == false`, menu shows `"Send Sticker (Unavailable for Google Messages)"` | `CapMsgSticker` omitted in `roomCaps.File` (`mautrix-slack@v0.2609.1/pkg/connector/capabilities.go:115-175`); `Sticker.Supported == false`, `canSendSticker == false`, menu shows `"Send Sticker (Unavailable for Slack)"` |
| Outgoing GIFs (`message.sendGIF`, `actions.SendGIF`) | `CapMsgGIF`: `video/mp4` full (`CapLevelFullySupported`, sent as `m.video` with `info["fi.mau.gif"] = true`), `image/gif` via `supportedIfFFmpeg()` (`CapLevelPartialSupport` if `ffmpeg.Supported()`, else `CapLevelRejected`, sent as `m.image` with `info["fi.mau.gif"] = true`); `Caption: CapLevelFullySupported` (`MaxCaptionLength: MaxTextLength` = `65536`); bridge `MaxSize: WAMaxFileSize` (`2000 * 1024 * 1024` = 2000 MiB), capped to 100 MiB by `networkFileCeiling("whatsapp")` (`mautrix-whatsapp@v0.2609.0/pkg/connector/capabilities.go:58-67,96-106,137-145`) | `CapMsgGIF`: `image/gif` (`m.image`) and `video/mp4` (`m.video`) full (`CapLevelFullySupported`) with `info["fi.mau.gif"] = true`; `Caption: CapLevelFullySupported` (`MaxCaptionLength` unset/`0` on `CapMsgGIF`; room `MaxTextLength` = `2000`); `MaxSize: MaxFileSize` (`100 * 1024 * 1024` = 100 MiB) (`mautrix-signal@v0.2609.0/pkg/connector/capabilities.go:48-49,135-142`) | `CapMsgGIF`: `video/mp4` (`m.video`) full (`CapLevelFullySupported`) and `image/gif` (`m.image`) partial (`CapLevelPartialSupport`) with `info["fi.mau.gif"] = true`; `Caption: CapLevelFullySupported` (`MaxCaptionLength: 1024`, or `2048` in `premiumFileCaps`); `CapMsgGIF.MaxSize: MaxFileSize` (`2 * 1024 * 1024 * 1024` = 2 GiB, while `image/gif` sent as `m.image` is also checked against `MsgImage.MaxSize` = `10 * 1024 * 1024` = 10 MiB) (`mautrix-telegram@v0.2609.0/pkg/connector/capabilities.go:72-74,100-110,137-145,167-179`) | `CapMsgGIF`: `gifMimes` has only `image/gif` full (`CapLevelFullySupported`, sent as `m.image` with `info["fi.mau.gif"] = true`; `video/mp4` is not in `gifMimes`); `Caption` is unset (`captions: false`) in `rcsCaps` (`146-149`) and `CapLevelFullySupported` (`captions: true`, `MaxCaptionLength` unset/`0`) in `smsCaps` (`187-191`); `MaxSize: MaxFileSize` (`100 * 1024 * 1024` = 100 MiB on both RCS and SMS) (`mautrix-gmessages@v0.2609.0/pkg/connector/capabilities.go:67,119-121,146-149,187-191`) | `CapMsgGIF`: `image/gif` full (`CapLevelFullySupported`, sent as `m.image` with `info["fi.mau.gif"] = true`; `video/mp4` is not in `CapMsgGIF`); `Caption: CapLevelFullySupported` (`MaxCaptionLength: MaxTextLength` = `40000`); bridge `MaxSize: MaxFileSize` (`1 * 1000 * 1000 * 1000` = 1 GB), capped to 100 MiB by `networkFileCeiling("slack")` (`mautrix-slack@v0.2609.1/pkg/connector/capabilities.go:91-92,156-163`) |
| Bridge sticker / emoji pack sync (`stickers.list` with `refresh: true` in `actions/stickers.go:361-403`) | `WhatsAppClient` implements `StickerImportingNetworkAPI` (`mautrix-whatsapp@v0.2609.0/pkg/connector/client.go:494-501`), with `ListImagePacks` returning `nil, nil` (`// TODO`); `stickers.list` returns locally imported stickers and stickers/GIFs seen in recent timeline events (`store.ListRecentStickers` and `store.ListRecentGIFs` in `store/stickers.go:36-44`) | `SignalClient` implements `StickerImportingNetworkAPI` (`mautrix-signal@v0.2609.0/pkg/connector/client.go:81-87`), with `ListImagePacks` returning `[]*event.ImagePackMetadata{}`; `stickers.list` returns locally imported stickers and stickers/GIFs seen in recent timeline events (`store.ListRecentStickers` and `store.ListRecentGIFs` in `store/stickers.go:36-44`) | Bridge implements `bridgev2.StickerImportingNetworkAPI` (`ListImagePacks` / `DownloadImagePack` in `mautrix-telegram@v0.2609.0/pkg/connector/imagepack.go:479,526`) plus local cache | Not supported for stickers; recent GIFs from timeline events (`store.ListRecentGIFs` in `store/stickers.go:41-44`) | Bridge implements `bridgev2.StickerImportingNetworkAPI` (`ListImagePacks` / `DownloadImagePack` in `mautrix-slack@v0.2609.1/pkg/connector/emoji.go:36,40,85`, syncing custom workspace emoji with `Usage: [ImagePackUsageEmoji]`) |

### Keys

- [ ] `hotkey` Message: Send GIF: ⌘⇧G opens or closes `GIFPickerPopover` in the open chat’s message box (`ConversationCommands.swift:79-83`, `CommandSet.sendGIF` in `CommandSet.swift:345-356`, verified by `CommandSetTests.testSendGIFAndSendStickerCommandsRegisteredUnderMessageCategory` in `CommandSetTests.swift`).
- [ ] `hotkey` Message: Send Sticker: ⌘⌥⇧S opens or closes `StickerPickerPopover` in the open chat’s message box (`ConversationCommands.swift:84-88`, `CommandSet.sendSticker` in `CommandSet.swift:361-372`, verified by `CommandSetTests.testSendGIFAndSendStickerCommandsRegisteredUnderMessageCategory` in `CommandSetTests.swift`).

### Settings

- [ ] `setting:general` Enable emoji autocomplete: Settings ▸ Messages ▸ Composer, "Enable emoji autocomplete", on (`true`) out of the box (`ComposerPreferences.enableEmojiAutocomplete` in `ComposerPreferences.swift:72,152`, `MessagesSettingsPane.swift:186-187`, verified by `ComposerPreferencesTests.testDefaultsMatchTheInventory` in `ComposerPreferencesTests.swift` and `ComposerModelTests.testSlashGifRequiresOpenChatAndDisablingEmojiAutocompleteDismissesImmediately` in `ComposerModelTests.swift`). When on, typing `:` followed by 2+ characters in the message box opens `EmojiAutocompletePicker`.
- [ ] `setting:general` Disable automatic replacement of emoticons with emojis: Settings ▸ Messages ▸ Composer, "Disable automatic replacement of emoticons with emojis", off (`false`) out of the box (`ComposerPreferences.disableEmoticonReplacement` in `ComposerPreferences.swift:76,153`, `MessagesSettingsPane.swift:188-192`, verified by `ComposerPreferencesTests.testDefaultsMatchTheInventory` in `ComposerPreferencesTests.swift` and `ComposerModelTests.testEmoticonReplacementRespectsPreferenceURLsAndCodeSpans` in `ComposerModelTests.swift`). When off, typing emoticons like `:)` followed by a space or `Return` replaces them with `🙂`. When on, emoticons stay as typed.
- [ ] `setting:general` Automatically send GIFs after selection: Settings ▸ Messages ▸ Composer, "Automatically send GIFs after selection", off (`false`) out of the box (`ComposerPreferences.autoSendGIFs` in `ComposerPreferences.swift:80,154`, `MessagesSettingsPane.swift:193-197`, verified by `ComposerPreferencesTests.testDefaultsMatchTheInventory` in `ComposerPreferencesTests.swift` and `ComposerModelTests.testSelectGIFAutoSendsOrStagesPendingGIFWithCaptionAndHold` in `ComposerModelTests.swift`). When off, picking a GIF stages `ComposerModel.pendingGIF` (`PendingGIFPillView` in `ComposerView.swift`) so you can type an optional caption before pressing `Return`. When on, picking a GIF in `GIFPickerPopover` sends it immediately.

### Menus

- [ ] Message ▸ Send GIF… (⌘⇧G) and Message ▸ Send Sticker… (⌘⌥⇧S) sit in the Message menu (`ConversationCommands.swift:79-88`) and in the message box `+` menu (`ComposerView.plusMenu` in `ComposerView.swift:302-313`), using `ComposerModel.sendGIFMenuTitle`, `ComposerModel.sendStickerMenuTitle`, `ComposerModel.addGIFMenuTitle`, and `ComposerModel.addStickerMenuTitle` (`ComposerModel.swift:1664-1697`) so unsupported networks show `"Send Sticker (Unavailable for <Network>)"` and `"Add Sticker… (Unavailable for <Network>)"`.

### Components

**Composer emoji autocomplete and emoticon replacement (completes the 4.3 composer item from `m4-acceptance.md:590` and 3 carried ledger rows from `m4-acceptance.md:960,963,964`)**

- [ ] `component` Autocomplete.tsx: Typing `:` followed by 2+ shortcode characters in the message box opens `EmojiAutocompletePicker` (`EmojiAutocompletePicker.swift`) above the caret with up to 8 ranked standard and custom emoji matches (`EmojiCatalog.search` in `EmojiCatalog.swift`, verified by `EmojiCatalogTests.testSearchOrdersPrefixMatchesAheadOfSubstringAndKeywordsAndMergesCustomEmoji` in `EmojiCatalogTests.swift`), keyboard navigation (`↑`, `↓`, `Tab`, `Return`, `Escape`), and an `"Add :shortcode: to Custom Emoji"` footer button (`ViewSnapshotTests.testEmojiAutocompletePickerSnapshotsAndKeyboardRouting` and `ViewSnapshotTests.testStickerAndGIFTimelineRenderingAndComposingSnapshots` in `ViewSnapshotTests.swift`).
- [ ] `component` Emoji.tsx: Clicking `+` in the message box (`ComposerView.plusMenu` in `ComposerView.swift:294-313`) offers `"Add Emoji…"` (opening `EmojiAutocompletePicker` when a `:shortcode` token is at the caret or `NSApp.orderFrontCharacterPalette` otherwise), `"Add GIF…"` and `"Add Sticker…"`, alongside the dedicated GIF (`"GIF"`), sticker (`sparkles.rectangle.stack`), and emoji (`face.smiling`) buttons on the trailing side of the message box (`ComposerView.swift:162-210`, verified by `ViewSnapshotTests.testComposerToolbarAndPlusMenuStickerGIFAndEmojiEntryPoints` in `ViewSnapshotTests.swift`).
- [ ] `component` EmojiItem.tsx: Each row in `EmojiAutocompletePicker` (`EmojiItemRow` in `EmojiAutocompletePicker.swift:8-70`) renders a 20×20 pt Unicode glyph or local custom emoji thumbnail (loaded asynchronously via `ThumbnailLoader.resolveMediaPath` and `ThumbnailLoader.thumbnail(atPath:)` in `ThumbnailLoader.swift`), the `:shortcode:` label, and a `"Custom"` badge for imported or bridge custom emoji (`ViewSnapshotTests.testEmojiAutocompletePickerSnapshotsAndKeyboardRouting` in `ViewSnapshotTests.swift`).

**Sticker picker and GIF picker (completes the remaining carried ledger rows from `m4-acceptance.md:972,984,991,992,997,998,1000`)**

- [ ] `component` StickerPicker.tsx: `StickerPickerPopover` (`StickerPickerPopover.swift:30-260`) shows pack tabs (`"Recent"`, `"Imported"`, and synced bridge packs with network badges), a `"Search stickers"` filter field, a 4-column 64×64 pt thumbnail grid that excludes emoticon-only items (`StickerPickerPopover.stickerItems(in:)` in `StickerPickerPopover.swift:47-49`), an `"Import Sticker…"` button (`StickerImportPicker.run` in `StickerPickerPopover.swift:12-24` using `NSOpenPanel` with `[.png, .webP, .gif, .jpeg]`), and a `"Sync Packs"` button (`ViewSnapshotTests.testStickerPickerPopoverEmptyAndPopulatedSnapshots` in `ViewSnapshotTests.swift`).
- [ ] `component` GifPicker.tsx: `GIFPickerPopover` (`GIFPickerPopover.swift:27-193`) shows a `"Search recent GIFs"` field, the offline privacy banner when `composer.gifProvider.isAvailable == false` (`"Online GIF search is disabled so nothing leaves your Mac. Choose a GIF file or pick a recent GIF below."`), a 2-column grid of recent local GIFs with `"GIF"` badges, and a `"Choose GIF from Mac…"` button (`GIFFilePicker.run` in `GIFPickerPopover.swift:11-23` using `NSOpenPanel` with `[.gif, .mpeg4Movie]`, verified by `ViewSnapshotTests.testGIFPickerPopoverAndPendingGIFSnapshots` and `ViewSnapshotTests.testStickerAndGIFTimelineRenderingAndComposingSnapshots` in `ViewSnapshotTests.swift`).

### Commands

These are registered in Courier for the command bar (⌘J), which part 4.7 builds. They have no tick box here: they are "registered; shown in ⌘J by 4.7". The ones with a menu item or key above are checked there.

- Courier registers `"Send GIF"` (⌘⇧G, `id: "message.sendGIF"`) and `"Send Sticker"` (⌘⌥⇧S, `id: "message.sendSticker"`) in `CommandSet.sendGIF`, `CommandSet.sendSticker`, and `CommandSet.composerMedia` (`CommandSet.swift:345-379`, verified by `CommandSetTests.testSendGIFAndSendStickerCommandsRegisteredUnderMessageCategory` in `CommandSetTests.swift`).

### How it behaves

Not failures. Do not report these as bugs.

- Online GIF search (`GIFProvider` in `GIFProvider.swift`) is an offline stub in 4.5c (`StubGIFProvider`, `isAvailable == false`): typing in `GIFPickerPopover` filters only the recent GIFs already stored on this Mac (`composer.recentGIFs`) and never contacts Tenor, Giphy or any other server. Part 4.7 tracks the online provider stub alongside the other external service stubs.
- When you pick a custom emoji (`candidate.glyph == nil`) from `:shortcode` autocomplete (`ComposerModel.pickEmoji` in `ComposerModel.swift:956-972`), Courier inserts `:shortcode: ` into the message draft text; to send an imported custom emoji image as a graphical sticker on networks that support `m.sticker`, pick it from `StickerPickerPopover` (⌘⌥⇧S).
- On Google Messages and Slack, neither `mautrix-gmessages` nor `mautrix-slack` declares `event.CapMsgSticker` in its `FileFeatures` map; `ComposerModel.canSendSticker` is `false` on both networks, and the Message and `+` menus show `"Send Sticker (Unavailable for Google Messages)"` / `"Add Sticker… (Unavailable for Google Messages)"` and `"Send Sticker (Unavailable for Slack)"` / `"Add Sticker… (Unavailable for Slack)"`.

### Not ledger rows

The inventory has no row for these, but they are what this part was built to do.

**Borderless stickers and looping GIFs in the timeline (`MessageBubble.swift`, `Timeline.swift`, `MessagePresentationTests.swift`, `ViewSnapshotTests.swift`)**

- [ ] `Timeline.describe` and `Timeline.build` (`Timeline.swift:574-649,1076-1231`) populate `StickerAttachment` on `m.sticker` events (reading `emoji` from `info["fi.mau.bridged_sticker"]["emoji"]`, matching `actions.SendSticker` in `engine/internal/actions/actions.go:1314-1325`) and `GIFAttachment` on `m.image` / `m.video` events with `info["fi.mau.gif"] == true` (while keeping redacted and view-once events empty), and exclude GIFs (`!message.isGIF && message.gif == nil`) from photo/video gallery grouping (`Timeline.swift:727-728`, verified by `MessagePresentationTests.testStickerEventProducesStickerAttachmentAndSuppressesBubbleBackgroundWhileKeepingReactionsTimestampAndReplyHeader` and `MessagePresentationTests.testGIFEventProducesGIFAttachmentWithOptionalCaption` in `MessagePresentationTests.swift`).
- [ ] `StickerAttachmentView` (`MessageBubble.swift:1017-1147`) renders stickers up to 160×160 pt with no bubble background (`TimelineMessage.suppressesBubbleBackground == true` in `Timeline.swift:501-503`), preserving reactions, timestamp, "Sent" status and reply quote headers in both light and dark modes (`sticker-received`, `sticker-sent`, `sticker-in-reply` PNG snapshots in `ViewSnapshotTests.testStickerAndGIFTimelineRenderingAndComposingSnapshots` and `ViewSnapshotTests.testStickerAndGIFViewsLoadAsynchronouslyInTaskNotBody`).
- [ ] `GIFAttachmentView` (`MessageBubble.swift:1152-1302`) renders looping GIFs inside a 12 pt rounded frame with a top-leading `"GIF"` badge, proportional scaling (`.scaleProportionallyUpOrDown`), and optional caption below (`gif-looping`, `gif-with-caption` PNG snapshots in `ViewSnapshotTests.testStickerAndGIFTimelineRenderingAndComposingSnapshots`), and pauses when macOS Reduce Motion is on (`ViewSnapshotTests.testStickerAndGIFReduceMotionAndFallbackAspectRatio` and `ViewSnapshotTests.testStickerAndGIFViewsLoadAsynchronouslyInTaskNotBody`).

### Carried to later parts

All 10 ledger rows carried from 4.5b to 4.5c (`Autocomplete.tsx`, `Emoji.tsx`, `EmojiItem.tsx`, `GifPicker.tsx`, `StickerPicker.tsx`, `Message: Send GIF`, `Message: Send Sticker`, `Automatically send GIFs after selection`, `Disable automatic replacement of emoticons with emojis`, `Enable emoji autocomplete`) and the 4.3 composer `:shortcode` / emoticon / sticker / GIF item (`m4-acceptance.md:590`) are delivered in 4.5c above. Still deferred to later parts:

- A reply-network shortcut (⌘L is Remind Me).
- Deferred to later milestones or not planned in iteration 1 (14 ledger rows, unchanged from 4.5b):
  - `command` Join a Matrix room: not planned in iteration 1 (Courier runs five non-Matrix bridges with no generic Matrix room join).
  - `command` Open space in new window: part 4.6 window management.
  - `command` Profile: not planned in iteration 1 (no cloud account profile pane).
  - `component` ChangeEmailBrowserWindow.tsx: not planned in iteration 1 (no cloud account email management).
  - `component` ChatThemeBrowserWindow.tsx: part 4.7 (Appearance, wallpapers and per-chat themes).
  - `component` ChatThemeWindow.tsx: part 4.7 (Appearance, wallpapers and per-chat themes).
  - `component` DeleteAccountModal.tsx: not planned in iteration 1 (no cloud account deletion).
  - `component` DeleteAccountPrompt.tsx: not planned in iteration 1 (no cloud account deletion).
  - `component` ThreadedRepliesBrowserWindow.tsx: thread replies open in the right-hand Thread Replies pane (4.3); detached thread windows are part 4.6 window management.
  - `hotkey` Message: Talk to Type: part 4.7 (`AIProvider` dictation stub).
  - `menu:File` Open Chat in New Window: part 4.6 window management (along with double-click chat "Open in New Window").
  - `setting:ai` Use OpenAI's Whisper model for Talk to Type and transcribing: part 4.7 (`AIProvider` voice-note transcription stub).
  - `setting:general` Show Telegram Topics as separate spaces: not planned in iteration 1 (`mautrix-telegram` does not expose forum topics as separate portal spaces).
  - `setting:general` Show WhatsApp Communities as separate spaces: not planned in iteration 1 (`mautrix-whatsapp` bridges community rooms directly without a separate space hierarchy).

## Part 4.6: settings, notifications and the Bridges pane

The two-column Settings window (`SettingsWindow.swift`, `SettingsSearchModel.swift`, `GeneralSettingsPane.swift`, `NotificationsSettingsPane.swift`, `AccountsSettingsPane.swift`, `BridgesSettingsPane.swift`, `HotkeysSettingsPane.swift`, `QuickRepliesSettingsPane.swift`, `AboutSettingsPane.swift`), desktop notifications (`NotificationCoordinator.swift`, `Notifier.swift`, `NotificationPolicy.swift`, `OTPDetector`, `SoundEffectPlayer`), menu bar tray and Dock menus (`DockAndTrayModel.swift`, `MenuBar.swift`, `AppDelegate.swift`), login item and Touch ID app lock (`SystemLifecycleModel.swift`, `AppLockOverlay.swift`, `Protocol.swift`, `EngineClient.swift`), detached chat, space and thread windows (`DetachedWindowModel.swift`, `DetachedWindows.swift`), keyboard shortcut registry and `⌘/` sheet (`HotkeyRegistry.swift`, `KeyboardShortcutsSheet.swift`, `InboxCommands.swift`, `ConversationCommands.swift`, `MainWindow.swift`), Accounts and Bridges lifecycle (`AccountsAndBridgesModel.swift`, `engine/internal/engine/engine.go`, `engine/internal/store/accounts.go`), and local scrubbed problem reports (`ProblemReportModel.swift`, `ProblemReportSheet.swift`, `engine/internal/logscrub/stack.go`). What leaves this Mac for a network is:

- removing an account (`accounts.remove` via `Engine.RemoveAccount` in `engine/internal/engine/engine.go:693-741`) when `"Also sign out / unlink on <Network>"` (`logout_remote: true`) is checked, which calls `UserLogin.Delete` (`mautrix@v0.31.0/bridgev2/userlogin.go:289-305`) and invokes `LogoutRemote` on that network’s bridge client to unlink the device or sign out the session;
- reconnecting an existing bridge session when you click `"Restart Bridge"` (`bridges.restart` via `Engine.RestartNetwork` in `engine/internal/engine/engine.go:621-689`), which disconnects the in-process client (`UserLogin.Disconnect` in `mautrix@v0.31.0/bridgev2/userlogin.go:539-572`) and reloads its stored login (`Bridge.Network.LoadUserLogin` and `ConnectBackground()` in `mautrix@v0.31.0/bridgev2/bridge.go:175`).

Stays on this Mac: searching or changing any setting across the eight Settings panes (`SettingsWindow.swift`, `SettingsNavigationModel` in `SettingsSearchModel.swift`); delaying notifications (`NotificationPreferences.delaySeconds`), repeating unread alerts (`NotificationPreferences.repeatUnreadMinutes`), extracting and copying OTP/2FA codes (`OTPDetector.extractCode` in `NotificationPolicy.swift`), playing send/receive sound effects (`SoundEffectPlayer` in `Notifier.swift`), and applying per-account notification overrides (`NotificationCoordinator.swift`); updating the Dock badge, Dock right-click menu, or menu bar tray icon (`DockAndTrayModel.swift`, `MenuBar.swift`); registering or unregistering `"Open Courier at login"` with macOS (`MACLoginItemService` in `SystemLifecycleModel.swift`); locking and unlocking Courier with Touch ID or your macOS password (`AppLockGate` and `SystemLifecycleModel` in `SystemLifecycleModel.swift`, `EngineClient.call` and `ProtocolMethods.classifications` in `Protocol.swift:4919-5013`, `AppLockOverlay.swift`); opening detached chat, space, or thread windows (`DetachedWindowRegistry` in `DetachedWindowModel.swift`, `DetachedWindows.swift`); recording or resetting keyboard shortcuts (`HotkeyRegistry` in `HotkeyRegistry.swift`, `HotkeysSettingsPane.swift`, `KeyboardShortcutsSheet.swift`); discovering or toggling sub-account spaces and bots (`Engine.RefreshSubAccounts` in `engine/internal/engine/engine.go:745-855`, `Store.SubAccounts` in `engine/internal/store/accounts.go:404-439`) and unpinning duplicate official chat apps from the macOS Dock (`MACDockTileService` in `AccountsAndBridgesModel.swift:19-103`); and saving a scrubbed diagnostic bundle in `"Report a Problem…"` (`ProblemReportModel.writeBundle` and `ProblemReportModel.saveBundle` in `ProblemReportModel.swift`, `logscrub.ScrubStderrExport` in `engine/internal/logscrub/stack.go:165-175`), which writes only to a file or folder you choose in `NSSavePanel` and never uploads anything over the network.

### Before you start

- Install the build with `bazel run --config=macos-app //apps/desktop/courier/app:install -- --allow-missing`. Your chats and networks stay as they are; the engine upgrades local SQLite schema 9 to schema 10 (`store.SchemaVersion = 10` in `engine/internal/store/schema.go:18`, `engine/internal/store/testdata/m10.sql`) and speaks JSON-RPC protocol 9 (`rpc.Protocol = 9` in `engine/internal/rpc/server.go:60`, `CourierProtocol.version = 9` in `Protocol.swift:19`).
- Out of the box (`NotificationPolicy.swift`, `DockAndTrayModel.swift`, `SystemLifecycleModel.swift`, `InboxPreferences.swift`, `ComposerPreferences.swift`):
  - `"Message notifications"` (`messageNotificationsEnabled`), `"Group notifications"` (`groupNotificationsEnabled`), `"Notify me about message requests"` (`requestNotificationsEnabled`), and `"Notify on reactions"` (`notifyOnReaction`) are **on** (`true`); `"Notify when someone starts typing"` (`typingNotificationsEnabled`), `"Notify even when chat is in focus"` (`notifyWhenInFocus`), and `"Auto copy OTP/2FA codes"` (`autoCopyOTP`) are **off** (`false`); `"Delay notifications for"` (`delaySeconds`) is `0` (`"Off (immediately)"`), `"Repeat unread notifications"` (`repeatUnreadMinutes`) is `0` (`"Never"`), `"Play sound effects"` (`soundEffectsMode`) is `.none` (`"Off"`), and `"Sound effects volume"` (`soundEffectsVolume`) is `0.8` (`80%`).
  - `"Show menu bar icon"` (`DockAndTrayPreferences.showMenuBarIcon`) is **on** (`true`), `"Dock badge count"` (`DockAndTrayPreferences.badgeMode`) is `.unreadChatsUnmuted` (`"Unread chats (unmuted)"`), `"Open Courier at login"` (`openAtLogin`) is **off** (`false`), `"Keep Courier minimized on launch"` (`startMinimized`) is **off** (`false`), `"Quit Courier when closing the main window"` (`quitOnMainWindowClose`) is **off** (`false`), `"Require Touch ID authentication on launch"` (`requireTouchIDOnLaunch`) is **off** (`false`), and `"Lock Courier after"` (`lockTimeout`) is `.never` (`"Never"`).
- Do not open the same chat in another chat app while testing. It would send a read receipt.
- Never test on a real person’s chat. Use a chat with yourself or a test account. Never open a real chat in Courier (or another chat app) while testing.

### Check these first

All app checks are by hand on real accounts: there is no fake-network app mode, and views were checked as light and dark PNG snapshots (`ViewSnapshotTests.swift`). Look at these before anything else.

- [ ] Pressing `⌘,` opens the two-column `SettingsWindow` (`SettingsWindow.swift:5-226`, `SettingsNavigationModel` in `SettingsSearchModel.swift:262-358`, verified by `SettingsSearchModelTests` in `SettingsSearchModelTests.swift`, `ViewSnapshotTests.testSettingsWindowGeneralAndSearchSnapshots`, and `ViewSnapshotTests.testSettingsWindowAppearanceAndNotificationsSnapshots` in `ViewSnapshotTests.swift`) with a left sidebar (`"Search Settings"`, `General`, `Appearance`, `Notifications`, `Accounts` with connected-account count pill, `Hotkeys`, `Quick Replies`, `Bridges`, `About`) and a scrollable right detail pane; typing in `"Search Settings"` opens `SearchSuggestions` (`SettingsWindow.swift:127-169`) matching titles, subtitles, section titles and keywords across all eight panes, and picking a suggestion switches to that pane, scrolls to the setting anchor (`SettingAnchorModifier` in `GeneralSettingsPane.swift:562-575`), and highlights the control with a coral outline.
- [ ] Incoming message, reaction, message-request, and typing alerts pass through `NotificationCoordinator` (`NotificationCoordinator.swift:141-804`) and `Notifier` (`Notifier.swift:83-453`, verified by `NotificationCoordinatorTests` in `NotificationCoordinatorTests.swift` and `NotificationPolicyTests` in `NotificationPolicyTests.swift`): `"Delay notifications for"` waits the configured delay (`delaySeconds`) and cancels the alert if the room turns read first; `"Repeat unread notifications"` re-schedules up to 3 reminders (`maxRepeatCount = 3`) while the message stays unread; `"Auto copy OTP/2FA codes"` (`OTPDetector.extractCode` in `NotificationPolicy.swift:212-304`) copies 4–8 digit verification codes to the clipboard on arrival and attaches a `"Copy Code"` notification action; per-account overrides (`AccountNotificationOverride` in `NotificationPolicy.swift:115-145`) override global alert, sound, and preview settings for that account; and when `AppLockGate.isLocked` is `true`, `NotificationCoordinator` forces `includePreview = false` (`"New message"`) and suppresses OTP auto-copy, while `SystemLifecycleModel.lockNow()` calls `Notifier.clearAll()` (`Notifier.swift:245-248`) to remove delivered banners and pending notification requests.
- [ ] Settings ▸ Accounts (`AccountsSettingsPane.swift:6-515`) and Settings ▸ Bridges (`BridgesSettingsPane.swift:6-318`, backed by `AccountsAndBridgesModel` in `AccountsAndBridgesModel.swift:146-470` and `Engine.Bridges`, `Engine.RestartNetwork`, `Engine.RemoveAccount`, `Engine.RefreshSubAccounts` in `engine/internal/engine/engine.go:487-855`, verified by `AccountsAndBridgesModelTests` in `AccountsAndBridgesModelTests.swift`, `TestRestartNetworkAndBridgesReport` and `TestRemoveAccountLogoutAndDeleteChats` in `engine/internal/engine/engine_test.go`, `ViewSnapshotTests.testAccountsAndAccountDetailPaneSnapshots`, and `ViewSnapshotTests.testBridgesSettingsPaneSnapshots` in `ViewSnapshotTests.swift`) show plain-English status badges (`"Connected"`, `"Reconnecting…"`, `"Signed out — reconnect"`, `"Disconnected"`), non-destructive `"Restart Bridge"` (preserving every SQLite room and message), `"Copy Account ID"`, `"Copy Bridge ID"`, `"Copy Info as JSON"`, `"Remove Account…"` (`RemoveAccountConfirmationSheet` in `AccountsSettingsPane.swift:440-514` with `"Delete local chat history on this Mac"` off by default and `"Also sign out / unlink on <Network>"` on by default except off on Slack), sub-account `"Spaces"` and `"Bots"` toggles, and `"Remove <App> from macOS Dock"` when the official desktop client is pinned in the Dock.
- [ ] Locking Courier via Courier ▸ Lock Courier (`⌘⌃L`, `AppMenuCoordinator.lockOrUnlockApp` in `DockAndTrayModel.swift:329-332`), on launch (`requireTouchIDOnLaunch`), or after idle/sleep (`lockTimeout` in `SystemLifecycleModel.swift:114-149`) activates `AppLockGate` (`SystemLifecycleModel.swift:201-355`, `EngineClient.call` in `EngineClient.swift:158-167`, `ProtocolMethods.classifications` in `Protocol.swift:4919-5013`, verified by `SystemLifecycleModelTests` in `SystemLifecycleModelTests.swift`, `EngineClientTests.testEveryProtocolMethodIsClassifiedAndMutatingMethodsAreRefusedWhileLocked` in `EngineClientTests.swift`, `HotkeyRegistryTests.testEveryHotkeyShortcutIsNoOpWhileLockedAndRespectsEntitlements` in `HotkeyRegistryTests.swift`, and `ViewSnapshotTests.testWindowTitlesMenuItemTitlesAndNotifierClearAllWhileLocked` in `ViewSnapshotTests.swift`): every open main, Settings, and detached window is covered by `LockableWindowContent` and `AppLockOverlay` (`AppLockOverlay.swift:8-159`, `LockEnforcerNSView` setting `window.sharingType = .none` and clearing first responder), window titles scrub to `"Courier"`, Dock and tray chat titles scrub to `"Courier Locked"`, `EngineClient` blocks every non-read-only RPC method with `AppLockGateError.locked`, `HotkeyDispatcher` and `GlobalHotkeyMonitor` refuse every shortcut, and unlocking requires `LAContextBiometricService.authenticate` (`SystemLifecycleModel.swift:72-110`).
- [ ] Choosing Help ▸ Report a Problem… (`⌘⇧P`) or clicking `"Report a Problem… (⌘⇧P)"` in Settings ▸ About opens `ProblemReportSheet` (`ProblemReportSheet.swift:6-225`, `ProblemReportModel` in `ProblemReportModel.swift:92-360`, `logscrub.ScrubStderrExport` in `engine/internal/logscrub/stack.go:165-175`, verified by `ProblemReportModelTests` in `ProblemReportModelTests.swift`, `TestScrubPathAndStartupError`, `TestScrubPathReplacesUserHomeDirAndRealpath`, `TestScrubStderrExport`, and `TestRollingFileBoundsAt256KB` in `engine/internal/logscrub/stack_test.go`, and `ViewSnapshotTests.testProblemReportSheetAndAppLockOverlaySnapshots` in `ViewSnapshotTests.swift`), showing a live `"Scrubbed Diagnostic Preview"` and saving a local `.zip` or folder bundle (`report.json`, `bridges.json`, `stderr-scrubbed.log`, and optional attachments) to the location chosen in `NSSavePanel` with home paths (`/Users/<name>` → `~`), Go stack frame arguments (`(...)`), tokens, phone numbers, emails, and Matrix body fields scrubbed and zero network calls.
- Do the by-hand run on the installed build, once, start to end. Tick each step as you go (owner's by-hand day):
  - [ ] Press `⌘,` to open `SettingsWindow`, verify the left sidebar lists `General`, `Appearance`, `Notifications`, `Accounts`, `Hotkeys`, `Quick Replies`, `Bridges`, and `About`, type `"Touch ID"`, `"OTP"`, and `"Dock"` in `"Search Settings"`, and click each suggestion to verify it switches panes, scrolls to the target row, and highlights it.
  - [ ] In Settings ▸ General ▸ Startup & Security, toggle `"Open Courier at login"` on and check macOS System Settings ▸ General ▸ Login Items & Extensions to verify Courier appears under `"Open at Login"`, then toggle it off and verify it is removed; toggle `"Keep Courier minimized on launch"` and `"Quit Courier when closing the main window"` to verify window close (`⌘W`) hides vs quits Courier.
  - [ ] In Settings ▸ General ▸ Startup & Security, toggle `"Require Touch ID authentication on launch"` on and set `"Lock Courier after"` to `"1 minute"`, then press `⌘⌃L` (Courier ▸ Lock Courier) to check that `AppLockOverlay` covers the main window, Settings window, and any open detached windows, clears delivered Notification Center banners, hides Dock and menu bar chat names, and prompts Touch ID / Apple Watch / macOS password when you click `"Unlock with Touch ID…"`.
  - [ ] In Settings ▸ Notifications, check `"Open Notifications in System Settings"` (opens macOS System Settings ▸ Notifications) and `"Restart Notification Center"`; send yourself a test message and check sound effects (`"Sent and received messages"` and volume slider), `"Delay notifications for"` (`"15 seconds"` — read the chat on another device before 15 seconds to verify no banner fires), `"Repeat unread notifications"`, `"Auto copy OTP/2FA codes"` with `"Your verification code is 482910"` (verifying `482910` is copied to the clipboard and the notification banner shows `"Copy Code"`), and per-account overrides.
  - [ ] Right-click the Courier icon in the macOS Dock and click the Courier icon in the right-hand menu bar tray to check `"New Message…"`, `"Unread Chats (N)"`, `"Pinned Chats"`, `"Show / Hide Courier"`, `"Lock Courier"`, `"Snooze Notifications"` (`"30 minutes"`, `"1 hour"`, `"2 hours"`, `"Until tomorrow (9:00 AM)"`, `"Resume Notifications"`), `"Settings…"`, and `"Quit Courier"`, and switch `"Dock badge count"` in Settings ▸ Appearance ▸ System between `"Off"`, `"Unread messages"`, `"Unread chats (unmuted)"`, and `"Unread chats (all)"`.
  - [ ] Right-click a chat in the inbox and choose `"Open in New Window"` (or File ▸ Open Chat in New Window), right-click a space in the space bar and choose `"Open in New Window"`, and click the `"Open in New Window"` button in a thread header to verify detached chat, space, and thread windows open independently, reuse an existing window when opened twice for the same target, and lock/unlock in step with the main window.
  - [ ] Press `⌘/` (or Help ▸ Keyboard Shortcuts) to inspect `KeyboardShortcutsSheet`, click `"Customize Shortcuts…"` to jump to Settings ▸ Hotkeys, click `"Record Shortcut"` on `"Search in Chat"`, try pressing a single letter (verifying the modifier warning) and `⌘K` (verifying `"⌘K is already used by Search"`), record a valid chord, test `"Switch to Texts.app keybindings"` and `"Revert all"`, and toggle `"Global"` on `"Focus Courier"` to check that macOS prompts for Accessibility permission if not yet granted and brings Courier forward from another app.
  - [ ] In Settings ▸ Accounts and Settings ▸ Bridges, expand a bridge row to check its `mautrix-*` module version, creation timestamp, and connected account list; click `"Restart Bridge"` and verify the account reconnects without losing any chats or messages; click `"Refresh List"` under `"Sub-Accounts"` on a Telegram or Slack account and toggle a folder or bot to verify its space pill appears in the space bar; if an official app (`WhatsApp`, `Signal`, `Telegram`, `Slack`) is pinned in your macOS Dock, click `"Remove <App> from macOS Dock"` and check that the Dock refreshes without that duplicate icon; and on a test account, click `"Remove Account…"` to check the confirmation sheet checkboxes before cancelling or unlinking.
  - [ ] Press `⌘⇧P` (Help ▸ Report a Problem…), type a note, toggle `"Include Message Details"` on and off while inspecting `"Scrubbed Diagnostic Preview"` to verify no message bodies, names, phone numbers, tokens, or `/Users/<name>` paths appear, and click `"Save Problem Report…"` to save a `.zip` bundle to your Mac and inspect `report.json`, `bridges.json`, and `stderr-scrubbed.log`.

### The five things to check

These are the five things this part was most worried about. Look at them before the rest.

- [ ] App lock is enforced at both `AppLockGate` and the `EngineClient` RPC chokepoint (`AppLockGate` in `SystemLifecycleModel.swift:201-355`, `EngineClient.call` in `EngineClient.swift:158-167`, `ProtocolMethods.classifications` in `Protocol.swift:4919-5013`, `AppLockOverlay.swift:8-159`, `HotkeyDispatcher` and `GlobalHotkeyMonitor` in `HotkeyRegistry.swift:662-842`, verified by `EngineClientTests.testEveryProtocolMethodIsClassifiedAndMutatingMethodsAreRefusedWhileLocked` in `EngineClientTests.swift`, `SystemLifecycleModelTests.testTurningOffAutoLockWhileLockedRequiresAuthenticationAndCannotBypassLock` in `SystemLifecycleModelTests.swift`, `HotkeyRegistryTests.testEveryHotkeyShortcutIsNoOpWhileLockedAndRespectsEntitlements` in `HotkeyRegistryTests.swift`, and `ViewSnapshotTests.testWindowTitlesMenuItemTitlesAndNotifierClearAllWhileLocked` in `ViewSnapshotTests.swift`). Every one of the 60 JSON-RPC methods in `Protocol.swift` is classified in `ProtocolMethods.classifications`: only the 6 read-only status methods (`app.info`, `engine.ping`, `accounts.list`, `bridges.list`, `spaces.list`, `labels.list`) may run while locked, while all 54 content-reading or mutating methods (`inbox.list`, `room.open`, `room.timeline`, `message.sendText`, `search.messages`, `accounts.remove`, `bridges.restart`, etc.) throw `AppLockGateError.locked` before reaching the Unix socket. Every window wraps its root view in `LockableWindowContent`, which replaces the view hierarchy with `AppLockOverlay`, sets `window.sharingType = .none` (`LockEnforcerNSView`), resigns first responder, scrubs window and Dock/tray titles, and clears all Notification Center banners (`Notifier.clearAll()`).
- [ ] Notifications hide content and clear when locked, and OTP auto-copy only triggers on real verification phrases (`NotificationCoordinator.swift:141-804`, `Notifier.swift:83-453`, `OTPDetector.extractCode` in `NotificationPolicy.swift:212-304`, verified by `NotificationCoordinatorTests.testLockedAppRedactsImmediateDelayedRepeatTypingAndReminderNotifications`, `NotificationCoordinatorTests.testNotificationBannerActionsAndAutoCopyOTPDoNothingWhileLocked`, `NotificationCoordinatorTests.testDeliveredNotificationsAreRemovedFromNotificationCenterOnLock`, `NotificationCoordinatorTests.testDelayBatchingHoldsNormalMessageCancelsOnReadAndDeliversWhenUnread`, `NotificationCoordinatorTests.testRepeatUnreadRePostsAtIntervalWhenUnreadAndCancelsWhenRead`, and `NotificationCoordinatorTests.testOTPMessageBypassesDelayAndAutoCopiesOnlyWhenEnabledEvenInMutedChat` in `NotificationCoordinatorTests.swift`). When `AppLockGate.isLocked` is `true`, incoming notifications never include sender names or message bodies (`includePreview = false`, body `"New message"`) and never copy OTP codes to the pasteboard. When unlocked and `"Auto copy OTP/2FA codes"` is on, `OTPDetector.extractCode` requires a context keyword (`code`, `otp`, `2fa`, `verification`, `passcode`, `pin`, `security`, `login`, `confirm`) alongside a 4–8 digit token (ignoring years like `2026`, prices, and plain numbers) before copying to `PasteboardClipboardSink` and attaching the `"Copy Code"` action (`Notifier.copyCodeActionID`).
- [ ] `"Restart Bridge"` is non-destructive and `"Remove Account…"` separates remote sign-out from local room deletion (`Engine.Bridges`, `Engine.RestartNetwork`, `Engine.RemoveAccount`, and `Engine.RefreshSubAccounts` in `engine/internal/engine/engine.go:487-855`, `Store.RemoveAccountData`, `Store.SubAccounts`, `Store.UpdateSubAccount`, and `Store.SyncBotSubAccounts` in `engine/internal/store/accounts.go:346-520`, `AccountsAndBridgesModel.swift:146-470`, verified by `TestRestartNetworkAndBridgesReport`, `TestRemoveAccountLogoutAndDeleteChats`, and `TestRefreshSubAccountsFromBridgeDB` in `engine/internal/engine/engine_test.go`, `TestSubAccountFilteringAndBotSync` and `TestRemoveAccountDataSingleAndMultiAccount` in `engine/internal/store/accounts_test.go`, and `AccountsAndBridgesModelTests` in `AccountsAndBridgesModelTests.swift`). `bridges.restart` calls `UserLogin.Disconnect` and reloads the login via `Bridge.Network.LoadUserLogin` and `ConnectBackground()` without touching `rooms`, `events`, or `media`. `accounts.remove` defaults `delete_chats` to `false` (leaving local SQLite rooms and messages intact on this Mac unless `"Delete local chat history on this Mac"` is checked) and defaults `logout_remote` to `true` on WhatsApp, Signal, Telegram, and Google Messages and `false` on Slack (because `SlackClient.LogoutRemote` calls `SendAuthSignoutContext()`, which invalidates a browser session token shared with the user’s browser).
- [ ] `"Report a Problem…"` builds a local scrubbed bundle and never uploads anything (`ProblemReportModel.swift:14-360`, `ProblemReportSheet.swift:6-225`, `logscrub.ScrubPath`, `logscrub.ScrubStartupError`, `logscrub.ScrubExportLine`, `logscrub.ScrubStderrExport`, and `logscrub.RollingFile` in `engine/internal/logscrub/stack.go:60-226`, verified by `ProblemReportModelTests` in `ProblemReportModelTests.swift` and `TestScrubPathAndStartupError`, `TestScrubPathReplacesUserHomeDirAndRealpath`, `TestScrubStderrExport`, `TestRollingFileBoundsAt256KB` in `engine/internal/logscrub/stack_test.go`). The engine redirects stderr through a 5 MiB bounded `logscrub.RollingFile` (`MaxStderrLogBytes = 5 * 1024 * 1024`) and scrubs panic stack arguments (`(...)`) and home paths (`/Users/<name>` → `~`) before writing `stderr.log` or `startup-error.txt`. When exporting a problem report, `StderrExportFilter.scrub` and `logscrub.ScrubStderrExport` strip structured zerolog PII fields (`body`, `text`, `sender_name`, `display_name`, `phone`, `email`, `token`, `secret`, `password`, `cookie`, `session`, `auth`, `qr`, `code`) and scrub Bearer tokens, Slack `xox*` tokens, URL query secrets, emails, phone numbers, and `/Users/<name>` paths, and `"Include Message Details"` includes only scrubbed room ID, event ID, network, timestamp, and delivery status — never message text or sender names.
- [ ] All shortcut entry points share `HotkeyRegistry` and respect lock state and entitlements (`HotkeyRegistry.swift:14-842`, `HotkeysSettingsPane.swift:6-360`, `KeyboardShortcutsSheet.swift:6-190`, `InboxCommands.swift`, `ConversationCommands.swift`, `MainWindow.swift`, verified by `HotkeyRegistryTests` in `HotkeyRegistryTests.swift` and `ViewSnapshotTests.testHotkeysPaneAndShortcutsSheetSnapshots` in `ViewSnapshotTests.swift`). `HotkeyRegistry` is the single source of truth for all 45 shortcuts across the macOS menu bar, `MainWindow.alternateShortcuts`, `KeyboardShortcutsSheet` (`⌘/`), and `HotkeysSettingsPane`. Recording a shortcut rejects bare unmodified keys (`HotkeyConflictError.missingModifier`), reserved macOS chords (`⌘Q`, `⌘H`, `⌘M`, `⌘⇥`), and chords already bound to another enabled action (`HotkeyConflictError.conflict`), and every shortcut routed through `HotkeyDispatcher` or `GlobalHotkeyMonitor` is a no-op while `AppLockGate.isLocked` is `true`.

### What to expect on each network

Courier manages account removal (`accounts.remove`, `Engine.RemoveAccount` in `engine/internal/engine/engine.go:693-741`), bridge restarts (`bridges.restart`, `Engine.RestartNetwork` in `engine/internal/engine/engine.go:621-689`), sub-account spaces and bots (`accounts.subAccounts`, `Engine.RefreshSubAccounts` in `engine/internal/engine/engine.go:745-855`), and official macOS Dock cleanup (`AccountsAndBridgesModel.officialDockBundleID` in `AccountsAndBridgesModel.swift:200-217`) across the five pinned bridges (`mautrix-whatsapp@v0.2609.0`, `mautrix-signal@v0.2609.0`, `mautrix-telegram@v0.2609.0`, `mautrix-gmessages@v0.2609.0`, `mautrix-slack@v0.2609.1`).

| | WhatsApp | Signal | Telegram | Google Messages | Slack |
|---|---|---|---|---|---|
| Remove Account (`accounts.remove`, `Engine.RemoveAccount` in `engine/internal/engine/engine.go:693-741`, `UserLogin.Delete` in `mautrix@v0.31.0/bridgev2/userlogin.go:289-344`) | `logout_remote` defaults to `true` (`RemoveAccountConfirmation.defaultLogoutRemote(for: "whatsapp") == true` in `AccountsAndBridgesModel.swift:129-133`). When `true`, `WhatsAppClient.LogoutRemote` calls `cli.Logout(ctx)` to unlink the companion device on WhatsApp, disconnects, and deletes `Conversation` history-sync rows (`mautrix-whatsapp@v0.2609.0/pkg/connector/client.go:388-401`); when `false`, `WhatsAppClient.Disconnect` closes the socket locally (`client.go:381-386`) | `logout_remote` defaults to `true`. When `true`, `SignalClient.LogoutRemote` stops chat sync, calls `s.Client.Unlink(ctx)` to unlink the linked device from the primary phone, stops receive loops, and calls `DeleteDevice()` on the signalmeow store (`mautrix-signal@v0.2609.0/pkg/connector/client.go:89-106`); when `false`, `SignalClient.Disconnect` stops loops locally (`client.go:287-297`) | `logout_remote` defaults to `true`. When `true`, `TelegramClient.LogoutRemote` calls `tc.client.API().AuthLogOut(ctx)` (with a 5 s timeout) to terminate the MTProto session on Telegram’s servers and disconnects (`mautrix-telegram@v0.2609.0/pkg/connector/client.go:585-604`); when `false`, `TelegramClient.Disconnect` cancels the local client context (`client.go:563-576`) | `logout_remote` defaults to `true`. When `true`, `GMClient.LogoutRemote` calls `cli.Unpair(ctx)` to unpair the browser session from the phone in Google Messages, disconnects, and clears `gc.Meta.Session` (`mautrix-gmessages@v0.2609.0/pkg/connector/client.go:236-246`); when `false`, `GMClient.Disconnect` disconnects long-polling locally (`client.go:195-205`) | `logout_remote` defaults to `false` (`RemoveAccountConfirmation.defaultLogoutRemote(for: "slack") == false` in `AccountsAndBridgesModel.swift:129-133`) with the warning `"On Slack, remote sign-out invalidates the session token, which may also sign out your browser if you connected with a browser token."` When `false`, `SlackClient.Disconnect` closes the local RTM/Socket Mode connection (`mautrix-slack@v0.2609.1/pkg/connector/client.go:618-634`); when `true`, `SlackClient.LogoutRemote` calls `cli.SendAuthSignoutContext(ctx)` when `IsRealUser()` is true and zeroes the stored tokens (`client.go:640-655`) |
| Restart Bridge (`bridges.restart`, `Engine.RestartNetwork` in `engine/internal/engine/engine.go:621-689`) | Calls `UserLogin.Disconnect` (`mautrix@v0.31.0/bridgev2/userlogin.go:539-572` → `WhatsAppClient.Disconnect` at `client.go:381`), then `Bridge.Network.LoadUserLogin` and `ConnectBackground()` (`mautrix@v0.31.0/bridgev2/bridge.go:175`) for each login on `whatsapp`; all SQLite rooms and messages stay intact | Calls `UserLogin.Disconnect` (`SignalClient.Disconnect` at `client.go:287`), then `Bridge.Network.LoadUserLogin` and `ConnectBackground()` for each login on `signal`; all SQLite rooms and messages stay intact | Calls `UserLogin.Disconnect` (`TelegramClient.Disconnect` at `client.go:563`), then `Bridge.Network.LoadUserLogin` and `ConnectBackground()` for each login on `telegram`; all SQLite rooms and messages stay intact | Calls `UserLogin.Disconnect` (`GMClient.Disconnect` at `client.go:195`), then `Bridge.Network.LoadUserLogin` and `ConnectBackground()` for each login on `gmessages`; all SQLite rooms and messages stay intact | Calls `UserLogin.Disconnect` (`SlackClient.Disconnect` at `client.go:618`), then `Bridge.Network.LoadUserLogin` and `ConnectBackground()` for each login on `slack`; all SQLite rooms and messages stay intact |
| Sub-Account Spaces & Bots (`accounts.subAccounts` & `accounts.setSubAccount`, `Engine.RefreshSubAccounts` in `engine/internal/engine/engine.go:745-855`) | Community / parent space portals in `bridgev2` `portal` table (`room_type = 'space'`) discovered as `kind: "space"`; bot DM portals (`Store.SyncBotSubAccounts`) discovered as `kind: "bot"` | No remote folder/bot hierarchy in `mautrix-signal`; returns `[]` (`"No spaces or bots found for this account."`) | Dialog folders (`portal` rows with `room_type = 'space'`) discovered as `kind: "space"`; Telegram bot DM portals and ghosts (`is_bot` metadata) discovered as `kind: "bot"` | No remote folder/bot hierarchy in `mautrix-gmessages`; returns `[]` (`"No spaces or bots found for this account."`) | Workspace channels/sections (`room_type = 'space'`) discovered as `kind: "space"`; Slack app/bot DM portals (`is_bot` metadata) discovered as `kind: "bot"` |
| Official macOS Dock Icon Cleanup (`AccountsAndBridgesModel.officialDockBundleID` in `AccountsAndBridgesModel.swift:200-217`) | Detects `net.whatsapp.WhatsApp` (`"WhatsApp"`) in `com.apple.dock` `persistent-apps` and offers `"Remove WhatsApp from macOS Dock"` | Detects `org.whispersystems.signal-desktop` (`"Signal"`) in `com.apple.dock` `persistent-apps` and offers `"Remove Signal from macOS Dock"` | Detects `ru.keepcoder.Telegram` and `org.telegram.desktop` (`"Telegram"`) in `com.apple.dock` `persistent-apps` and offers `"Remove Telegram from macOS Dock"` | No standalone macOS desktop bundle (`officialDockBundleID(for: "gmessages") == nil`); Dock card is hidden for Google Messages | Detects `com.tinyspeck.slackmacgap` (`"Slack"`) in `com.apple.dock` `persistent-apps` and offers `"Remove Slack from macOS Dock"` |

### Keys

- [ ] `hotkey` Settings: `⌘,` opens `SettingsWindow` (`InboxCommands.swift`, `HotkeyRegistry.allDefinitions` in `HotkeyRegistry.swift`, verified by `HotkeyRegistryTests.testEveryHotkeyDefinitionResolvesToWiredCommandHandler` in `HotkeyRegistryTests.swift`).
- [ ] `hotkey` Keyboard Shortcuts: `⌘/` opens `KeyboardShortcutsSheet` (`InboxCommands.swift`, `KeyboardShortcutsSheet.swift`, `CommandSet.showKeyboardShortcuts` in `CommandSet.swift`).
- [ ] `hotkey` Report a Problem: `⌘⇧P` opens `ProblemReportSheet` (`InboxCommands.swift`, `ProblemReportSheet.swift`, `CommandSet.reportProblem` in `CommandSet.swift`).
- [ ] `hotkey` Minimize To Menu Bar: `⌘⌥Q` hides all Courier windows to the menu bar tray (`InboxCommands.swift`, `AppMenuCoordinator.minimizeToMenuBar` in `DockAndTrayModel.swift:320-324`).
- [ ] `hotkey` Quit App: `⌘Q` quits Courier cleanly (`AppMenuCoordinator.quitApp` in `DockAndTrayModel.swift:326-328`).
- [ ] `hotkey` Focus App / `hotkey` Focus App and Command Bar: Configurable global shortcuts in Settings ▸ Hotkeys (`HotkeysSettingsPane.swift`, `GlobalHotkeyMonitor` in `HotkeyRegistry.swift:724-842`, unbound by default) that bring Courier to the front from any macOS app (and open the command bar for `"Focus Courier and Command Bar"`).
- [ ] `hotkey` Switch to First 9 Spaces Modifier (`⌘1`–`⌘9` by default, configurable between `⌘` and `⌃` via `HotkeyRegistry.allDefinitions` and `HotkeyRegistry.applyTextsAppPreset`) and `hotkey` Switch to First 9 Chats Modifier (`⌃1`–`⌃9` by default): Switch between the first 9 spaces or the first 9 chats in the open list (`HotkeyRegistry.swift:324-335`, `MainWindow.swift`, verified by `HotkeyRegistryTests.testFunctionKeysModifierOnlyAndPresetZeroConflicts` in `HotkeyRegistryTests.swift`).

### Settings

**General (`GeneralSettingsPane.swift`, `InboxPreferences.swift`, `ComposerPreferences.swift`, `NotificationPolicy.swift`, `SystemLifecycleModel.swift`)**

- [ ] `setting:general` Privacy section (`GeneralSettingsPane.swift:31-67`): `"Incognito mode"`, `"Show recipients I'm typing"`, and `"Show the incognito mark in the message box"` (`PrivacyPreferences.swift`).
- [ ] `setting:general` Reminders section (`GeneralSettingsPane.swift:71-145`): `"Remind me"` (`"If no reply"` / `"Always"`), `"Archive a chat when I set a reminder on it"`, and `"Time suggestions"` chip editor with `"Reset"` and natural-language `"Add"` (`InboxPreferences.swift`).
- [ ] `setting:general` Archiving section (`GeneralSettingsPane.swift:149-227`): `"Mark chats read when I archive them"`, `"After archiving the open chat"`, `"After marking the open chat read or unread"`, `"Archive chats by themselves"`, `"Wait"`, and timed auto-archive (`InboxPreferences.swift`).
- [ ] `setting:general` Messages & Composer section (`GeneralSettingsPane.swift:231-355`): `"On double-clicking a message"`, `"Allow undo send (⌘Z) for"`, `"Click pending messages to undo send"`, `"Default for send later"`, `"Press ↑ in the composer to"`, `"Include timestamps when copying messages with ⌘C"`, `"Enable emoji autocomplete"`, `"Disable automatic replacement of emoticons with emojis"`, `"Automatically send GIFs after selection"`, `"Automatically play the next voice note"`, `"Microphone"`, and `"Auto copy OTP/2FA codes"` (`ComposerPreferences.swift`, `NotificationPreferences.autoCopyOTP`).
- [ ] `setting:general` Downloads section (`GeneralSettingsPane.swift:359-400`): `"Downloads location"` (`~/Downloads` with `"Choose…"`) and `"Always ask where to save files before downloading"` (`ComposerPreferences.swift`).
- [ ] `setting:general` Startup & Security section (`GeneralSettingsPane.swift:404-496`, `SystemLifecycleModel.swift:360-807`, verified by `SystemLifecycleModelTests` in `SystemLifecycleModelTests.swift`):
  - `"Open Courier at login"` (`SystemLifecycleModel.openAtLogin`, backed by `MACLoginItemService` / `SMAppService.mainApp`), off out of the box.
  - `"Keep Courier minimized on launch"` (`SystemLifecycleModel.startMinimized`), off out of the box.
  - `"Quit Courier when closing the main window"` (`SystemLifecycleModel.quitOnMainWindowClose`), off out of the box.
  - `"Require Touch ID authentication on launch"` (`SystemLifecycleModel.requireTouchIDOnLaunch`), off out of the box.
  - `"Lock Courier after"` (`SystemLifecycleModel.lockTimeout`: `"Never"`, `"1 minute"`, `"5 minutes"`, `"15 minutes"`, `"30 minutes"`, `"1 hour"`, `"When Mac sleeps or screen locks"`), `"Never"` out of the box, plus `"Lock Courier Now"` button when biometrics or timeout is enabled.

**Appearance (`AppearanceSettingsPane` in `GeneralSettingsPane.swift:591-784`, `InboxPreferences.swift`, `ComposerPreferences.swift`, `DockAndTrayModel.swift`)**

- [ ] `setting:appearance` Chat list section (`GeneralSettingsPane.swift:606-677`): `"Show the space bar"`, `"Use regular style for pinned chats"`, `"Show number of unread messages"`, `"Show message previews"`, `"Compact chat list"`, `"Show network icons"`, `"Colorize network icons"`, `"Button on a chat you point at"`, and `"On double-clicking a chat"` (`DoubleClickAction`: `"Does nothing"`, `"Archives the chat"`, `"Marks the chat unread"`, `"Minimizes the window"`, `"Opens it in a new window"` in `InboxPreferences.swift:39-57`).
- [ ] `setting:appearance` Conversation and Composer sections (`GeneralSettingsPane.swift:680-748`): `"Show message timestamps"`, `"Hide deleted messages"`, `"Show membership events"`, `"Load external embeds automatically"`, `"Quick reaction emoji"`, `"Enable spellcheck"`, `"Show formatting menu"`, `"Disable link previews in outgoing messages"`, `"Primary composer button"`, and `"Secondary composer button"`.
- [ ] `setting:appearance` System section (`GeneralSettingsPane.swift:750-783`, `DockAndTrayPreferences` in `DockAndTrayModel.swift:127-212`, verified by `DockAndTrayModelTests` in `DockAndTrayModelTests.swift`):
  - `"Show menu bar icon"` (`DockAndTrayPreferences.showMenuBarIcon`), on (`true`) out of the box.
  - `"Dock badge count"` (`DockAndTrayPreferences.badgeMode`: `"Off"`, `"Unread messages"`, `"Unread chats (unmuted)"`, `"Unread chats (all)"`), `"Unread chats (unmuted)"` out of the box.

**Notifications (`NotificationsSettingsPane.swift:6-312`, `NotificationPolicy.swift`, `NotificationCoordinator.swift`)**

- [ ] `setting:notifications` Alert Types section (`NotificationsSettingsPane.swift:33-118`): `"Message notifications"` and `"Direct message sound"`, `"Group notifications"` and `"Group chat sound"`, `"Notify me about message requests"`, `"Notify on reactions"`, `"Notify when someone starts typing"` (`Labs` badge), and `"Notify even when chat is in focus"`.
- [ ] `setting:notifications` Timing & Verification Codes section (`NotificationsSettingsPane.swift:122-167`): `"Delay notifications for"` (`Labs` badge: `"Off (immediately)"`, `"5 seconds"`, `"15 seconds"`, `"30 seconds"`, `"1 minute"`), `"Repeat unread notifications"` (`"Never"`, `"After 1 minute"`, `"After 5 minutes"`, `"After 15 minutes"`, `"After 30 minutes"`), and `"Auto copy OTP/2FA codes"`.
- [ ] `setting:notifications` Sound Effects section (`NotificationsSettingsPane.swift:171-212`): `"Play sound effects"` (`"Off"`, `"Sent messages only"`, `"Received messages only"`, `"Sent and received messages"`) and `"Sound effects volume"` slider (`0%`–`100%`, `SoundEffectPlayer` in `Notifier.swift`).
- [ ] `setting:notifications` Per-Account Overrides section (`NotificationsSettingsPane.swift:216-277`): Per-account `"Alerts"` toggle, sound picker, and `"Previews"` checkbox for each connected account (`NotificationPreferences.accountOverrides`).
- [ ] `setting:notifications` System Notification Center section (`NotificationsSettingsPane.swift:281-310`): `"Open Notifications in System Settings"` (`NotificationCoordinator.openSystemNotificationSettings`) and `"Restart Notification Center"` (`NotificationCoordinator.restartNotificationCenter`).

**Accounts, Bridges, Hotkeys, Quick Replies, and About (`AccountsSettingsPane.swift`, `BridgesSettingsPane.swift`, `HotkeysSettingsPane.swift`, `QuickRepliesSettingsPane.swift`, `AboutSettingsPane.swift`)**

- [ ] `setting:accounts` Per-account detail pane (`AccountsSettingsPane.swift:100-436`): `"Show in Space Bar"`, `"Show in Inbox"` (`"All Messages"`, `"Only DMs"`, `"None"`), `"Mute Account Space"`, `"Auto-Archive…"`, `"Notifications for this Account"` (`"Override global notification settings"`, `"Desktop notifications"`, `"Sound"`, `"Include message preview"`), `"Sub-Accounts"` (`"Spaces"` and `"Bots"` with `"Refresh List"`), `"macOS Dock"` (`"Remove <App> from macOS Dock"`), and `"Developer"` (`"Copy Account ID"`, `"Copy Bridge ID"`, `"Copy Info as JSON"`, `"Restart Bridge"`).
- [ ] `setting:hotkeys` Shortcut customization (`HotkeysSettingsPane.swift:6-360`): `"Search hotkeys..."` filter, `"Switch to Texts.app keybindings"` preset, `"Revert all"` button, per-shortcut enable/disable toggle, `"Global"` checkbox on `"Focus Courier"` and `"Focus Courier and Command Bar"`, and `"Record Shortcut"` capture with conflict and modifier validation.
- [ ] `setting:quick-replies` Quick Replies pane (`QuickRepliesSettingsPane.swift:1-92`, verified by `ViewSnapshotTests.testQuickRepliesAndAboutPanesSnapshots` in `ViewSnapshotTests.swift`): `"Saved quick replies"` list with `"Add Quick Reply…"`, `"Edit…"`, `"Delete"`, and `"Template variables"` reference (`{first_name}`, `{last_name}`, `{full_name}`, `{username}`, `{phone_number}`, `{email}`).
- [ ] `setting:about` About pane (`AboutSettingsPane.swift:6-275`, verified by `ViewSnapshotTests.testQuickRepliesAndAboutPanesSnapshots` in `ViewSnapshotTests.swift`): app icon, version, protocol and build number, expandable `"View Changelog"`, `"Diagnostics & Reference"` (`"Report a Problem… (⌘⇧P)"`, `"Keyboard Shortcuts (⌘/)"`), expandable `"On-Device Architecture & Data Privacy"`, and expandable `"Open-Source Licenses (MIT / MPL-2.0 / AGPL-3.0)"` listing `Courier Desktop & Engine`, `mautrix-go (bridgev2)`, `mautrix-whatsapp`, `mautrix-signal`, `mautrix-telegram`, `mautrix-slack`, `mautrix-gmessages`, and `SQLite & FTS5`.

### Menus

- [ ] `menu:Courier` Settings… (`⌘,`), Lock Courier (`⌘⌃L`), Minimize to Menu Bar (`⌘⌥Q`), and Quit Courier (`⌘Q`) (`InboxCommands.swift`, `AppMenuCoordinator` in `DockAndTrayModel.swift:217-370`, `SystemLifecycleModel.swift`).
- [ ] `menu:File` Open Chat in New Window (`InboxCommands.swift:72-78`, `AppMenuCoordinator.openChatInNewWindow` in `DockAndTrayModel.swift:318-323`, wired in `AppDelegate.swift`): opens the active chat in `DetachedChatWindowView` (`DetachedWindows.swift`).
- [ ] `menu:Help` Report a Problem… (`⌘⇧P`) and Keyboard Shortcuts (`⌘/`) (`InboxCommands.swift:120-135`, `AppMenuCoordinator.openSettings` in `DockAndTrayModel.swift:232-253`).
- [ ] `menu:Dock` Right-clicking the Courier Dock icon (`AppDelegate.applicationDockMenu` in `AppDelegate.swift`, `DockMenuModel` in `DockAndTrayModel.swift:37-122`, verified by `DockAndTrayModelTests.testDockMenuModelPopulatesTop5UnreadAndTop5RecentTruncatesTitlesAndRedactsWhenLocked` in `DockAndTrayModelTests.swift`) shows `"New Message…"`, `"Unread Chats (N)"` (up to 5 unread chats), `"Pinned Chats"` (up to 5 pinned chats), `"Lock Courier"`, and `"Snooze Notifications"`.
- [ ] `menu:Tray` Clicking the menu bar tray icon (`MenuBarIcon` and `MenuBarMenu` in `MenuBar.swift:8-152`, `AppMenuCoordinator` in `DockAndTrayModel.swift`, verified by `DockAndTrayModelTests.testMenuBarIconPreferenceAndDockBadgeModes` and `DockAndTrayModelTests.testExternalMenuUnlockAndTwinMenuActionsShareOneModelAction` in `DockAndTrayModelTests.swift`) shows `"Show / Hide Courier"`, `"New Message…"`, unread and pinned quick-jump items (hidden when locked), `"Snooze Notifications"` (`"30 minutes"`, `"1 hour"`, `"2 hours"`, `"Until tomorrow (9:00 AM)"`, `"Resume Notifications"`), `"Lock Courier"`, `"Settings…"` (`⌘,`), and `"Quit Courier"` (`⌘Q`).
- [ ] `ctx:chat` Open in New Window (`ChatContextMenu.swift`) and `ctx:space-account` / `ctx:space-builtin` Open in New Window (`SpaceBar.swift`): right-clicking a chat in `InboxList` or `PinnedStrip`, or right-clicking a space in `SpaceBar`, offers `"Open in New Window"`.

### Components

**Settings window, search, and panes**

- [ ] `component` PrefsSidebarView.tsx / `component` PrefsContainerView.tsx / `component` SettingsSearch.tsx: `SettingsWindow` (`SettingsWindow.swift:5-226`) and `SettingsNavigationModel` (`SettingsSearchModel.swift:262-358`, verified by `SettingsSearchModelTests` in `SettingsSearchModelTests.swift` and `ViewSnapshotTests.testSettingsWindowGeneralAndSearchSnapshots` in `ViewSnapshotTests.swift`) render the two-column Settings window, live `"Search Settings"` field with `SearchSuggestions` dropdown (`SettingsWindow.swift:127-169`), deep-link scroll anchors (`SettingAnchorTracker` and `SettingAnchorModifier` in `GeneralSettingsPane.swift:542-575`), and `SettingBadgeView` (`"Labs"` / `"New"` pills in `GeneralSettingsPane.swift:578-589`).
- [ ] `component` GeneralPrefsSubView.tsx / `component` AppearancePrefsSubView.tsx / `component` NotificationsPrefsSubView.tsx: `GeneralSettingsPane` (`GeneralSettingsPane.swift:6-539`), `AppearanceSettingsPane` (`GeneralSettingsPane.swift:591-784`), and `NotificationsSettingsPane` (`NotificationsSettingsPane.swift:6-312`, verified by `ViewSnapshotTests.testSettingsWindowGeneralAndSearchSnapshots` and `ViewSnapshotTests.testSettingsWindowAppearanceAndNotificationsSnapshots` in `ViewSnapshotTests.swift`).
- [ ] `component` NetworksPrefsSubView.tsx / `component` AccountSettingsView.tsx / `component` RemoveAccountModal.tsx: `AccountsSettingsPane` (`AccountsSettingsPane.swift:6-438`) and `RemoveAccountConfirmationSheet` (`AccountsSettingsPane.swift:440-514`, verified by `AccountsAndBridgesModelTests` in `AccountsAndBridgesModelTests.swift` and `ViewSnapshotTests.testAccountsAndAccountDetailPaneSnapshots` in `ViewSnapshotTests.swift`).
- [ ] `component` BridgesPrefsSubView.tsx: `BridgesSettingsPane` (`BridgesSettingsPane.swift:6-318`, verified by `AccountsAndBridgesModelTests` in `AccountsAndBridgesModelTests.swift` and `ViewSnapshotTests.testBridgesSettingsPaneSnapshots` in `ViewSnapshotTests.swift`).
- [ ] `component` HotkeysPrefsSubView.tsx / `component` Key.tsx / `component` KeyboardShortcutsModal.tsx: `HotkeysSettingsPane` (`HotkeysSettingsPane.swift:6-360`), `KeyView` and `KeyboardShortcutsSheet` (`KeyboardShortcutsSheet.swift:6-190`, verified by `HotkeyRegistryTests` in `HotkeyRegistryTests.swift` and `ViewSnapshotTests.testHotkeysPaneAndShortcutsSheetSnapshots` in `ViewSnapshotTests.swift`).
- [ ] `component` QuickRepliesPrefsSubView.tsx / `component` AboutPrefsSubView.tsx: `QuickRepliesSettingsPane` (`QuickRepliesSettingsPane.swift:1-92`) and `AboutSettingsPane` (`AboutSettingsPane.swift:6-275`, verified by `ViewSnapshotTests.testQuickRepliesAndAboutPanesSnapshots` in `ViewSnapshotTests.swift`).

**Detached chat, space, and thread windows**

- [ ] `screen` Detached Chat Window / `component` DetachedChatBrowserWindow.tsx: `DetachedChatWindowView` (`DetachedWindows.swift:10-122`), `DetachedWindowRegistry`, and `DetachedWindowSession` (`DetachedWindowModel.swift:41-255`, verified by `DetachedWindowModelTests.testDetachedWindowRegistryDeduplicatesAndManagesChatSpaceAndThreadWindows`, `DetachedWindowModelTests.testOpeningSameRoomTwiceFocusesExistingWindowWithoutDuplicating`, `DetachedWindowModelTests.testClosingDetachedWindowReleasesItsConversationModel`, and `ViewSnapshotTests.testDetachedChatWindowLightAndDarkAndLockOverlay`) open a standalone chat window with its own `ConversationModel`, focus an existing window instead of duplicating when opened twice for the same room, release the `ConversationModel` on close, and cover the window with `AppLockOverlay` when locked.
- [ ] `screen` Detached Space Window / `component` DetachedSpaceBrowserWindow.tsx: `DetachedSpaceWindowView` (`DetachedWindows.swift:126-248`, verified by `DetachedWindowModelTests` in `DetachedWindowModelTests.swift`) opens a standalone window scoped to a space with its own `InboxModel` and `ConversationModel`.
- [ ] `screen` Detached Thread Window / `component` DetachedThreadBrowserWindow.tsx: `DetachedThreadWindowView` and `ThreadedRepliesBrowserWindow.tsx` (`DetachedWindows.swift:252-360`, `ThreadPane.swift`, verified by `DetachedWindowModelTests` in `DetachedWindowModelTests.swift`) open a standalone thread window with its own `ConversationModel` and `ThreadModel`.

**App lock overlay and local problem report sheet**

- [ ] `component` AppLockScreen.tsx: `AppLockOverlay` and `LockableWindowContent` (`AppLockOverlay.swift:8-159`, verified by `SystemLifecycleModelTests` in `SystemLifecycleModelTests.swift`, `ViewSnapshotTests.testProblemReportSheetAndAppLockOverlaySnapshots`, and `ViewSnapshotTests.testWindowTitlesMenuItemTitlesAndNotifierClearAllWhileLocked` in `ViewSnapshotTests.swift`) replace window content while locked, block screenshots via `LockEnforcerNSView` (`window.sharingType = .none`), and trigger `SystemLifecycleModel.unlockWithTouchID()`.
- [ ] `component` ReportProblemModal.tsx: `ProblemReportSheet` (`ProblemReportSheet.swift:6-225`) and `ProblemReportModel` (`ProblemReportModel.swift:92-360`, verified by `ProblemReportModelTests` in `ProblemReportModelTests.swift` and `ViewSnapshotTests.testProblemReportSheetAndAppLockOverlaySnapshots` in `ViewSnapshotTests.swift`) build and save a scrubbed local diagnostic bundle via `NSSavePanel` with `"Copy Diagnostic Data"` and `"Save Problem Report…"`.

### Commands

These are registered in Courier for the command bar (`⌘J`), which part 4.7 builds. They have no tick box here: they are "registered; shown in `⌘J` by 4.7". The ones with a menu item or key above are checked there.

- `command` Settings (`CommandSet.settings` in `CommandSet.swift`), `command` Account (`CommandSet.account` and `CommandSet.accounts`), `command` Appearance (`CommandSet.appearance`), `command` General (`CommandSet.general`), `command` Hotkeys (`CommandSet.hotkeys`), `command` Notifications (`CommandSet.notifications`), `command` Quick Replies (`CommandSet.quickReplies`), `command` Bridges (`CommandSet.bridges`), `command` About (`CommandSet.about`), and `command` Help (`CommandSet.help` in `CommandSet.swift:436-534`, verified by `SettingsSearchModelTests.testSharedSettingsNavigationModelSelectsAccountAndEverySettingHasMatchingHighlightTarget` in `SettingsSearchModelTests.swift`).
- `command` Show keyboard shortcuts (`CommandSet.showKeyboardShortcuts` in `CommandSet.swift:403-417`), `command` Report a problem (`CommandSet.reportProblem`), `command` Lock app (`CommandSet.lockApp`), `command` Open space in new window (`CommandSet.openSpaceInNewWindow`), `command` Restart Notification Center (`CommandSet.restartNotificationCenter`), and `CommandSet.settingsAndSystem` (`CommandSet.swift:537-615`).

### How it behaves

Not failures. Do not report these as bugs.

- `"Report a Problem…"` (`⌘⇧P`) never uploads logs or diagnostics to any server: clicking `"Save Problem Report…"` writes `report.json`, `bridges.json`, `stderr-scrubbed.log`, and any attached screenshots or videos only to the local `.zip` or folder you pick in `NSSavePanel`.
- On Slack, `"Also sign out / unlink on Slack"` in `"Remove Account…"` is unchecked (`false`) by default (`RemoveAccountConfirmation.defaultLogoutRemote(for: "slack") == false` in `AccountsAndBridgesModel.swift:129-133`), because `SlackClient.LogoutRemote` calls `SendAuthSignoutContext()` (`mautrix-slack@v0.2609.1/pkg/connector/client.go:644`), which revokes a browser `xoxc-` session token that is shared with your web browser. On WhatsApp, Signal, Telegram, and Google Messages, each bridge links its own dedicated companion device session, so `"Also sign out / unlink on <Network>"` is checked (`true`) by default.
- In `"Remove Account…"`, `"Delete local chat history on this Mac"` (`deleteChats`) is unchecked (`false`) by default on all five networks so removing or relinking an account keeps your existing local SQLite rooms, messages, and media unless you explicitly check that box.
- `"Restart Bridge"` disconnects and reconnects the in-process `bridgev2` network client (`Engine.RestartNetwork` in `engine/internal/engine/engine.go:621-689`) without deleting any portal rooms, messages, or media on this Mac.
- While Courier is locked (`AppLockGate.isLocked == true`), incoming notifications still alert you with `"New message"` (`includePreview = false`) so you know a message arrived without exposing the sender’s name, message body, or OTP code on a locked screen.
- Global shortcuts (`"Focus Courier"` and `"Focus Courier and Command Bar"`) use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` (`GlobalHotkeyMonitor` in `HotkeyRegistry.swift:724-842`), which requires macOS Accessibility permission (`AXIsProcessTrusted()`) to receive keystrokes while another application is active; when Accessibility permission has not been granted, Courier falls back to local monitoring without crashing.

### Not ledger rows

The inventory has no row for these, but they are what this part was built to do.

**Protocol 9 and SQLite schema 10 (`Protocol.swift`, `engine/internal/rpc/server.go`, `engine/internal/store/schema.go`)**

- [ ] `CourierProtocol.version` (`Protocol.swift:19`) and `rpc.Protocol` (`engine/internal/rpc/server.go:60`) are `9`, and `store.SchemaVersion` (`engine/internal/store/schema.go:18`, `engine/internal/store/testdata/m10.sql`, verified by `TestFreshDatabaseIsAtLatestVersion` in `engine/internal/store/inbox_test.go` and `ProtocolConformanceTests` in `ProtocolConformanceTests.swift`) is `10`, adding the `sub_accounts` table for bridge space/bot discovery and `accounts.remove`, `accounts.subAccounts`, `accounts.setSubAccount`, `bridges.list`, and `bridges.restart`.

**Bounded rolling `stderr.log` and panic / path scrubbing (`engine/internal/logscrub/stack.go`)**

- [ ] `logscrub.OpenRollingFile` (`engine/internal/logscrub/stack.go:180-226`, verified by `TestRollingFileBoundsAt256KB`, `TestScrubPathAndStartupError`, `TestScrubPathReplacesUserHomeDirAndRealpath`, and `TestScrubStderrExport` in `engine/internal/logscrub/stack_test.go`) caps `stderr.log` at 5 MiB (`MaxStderrLogBytes`), scrubs panic frame arguments (`(...)`) and `/Users/<name>` paths in `startup-error.txt` (`logscrub.ScrubStartupError`), and scrubs tokens, phone numbers, emails, and message fields in `logscrub.ScrubStderrExport`.

**EngineClient lock-gate RPC classification (`Protocol.swift`, `EngineClient.swift`, `EngineClientTests.swift`)**

- [ ] `ProtocolMethods.classifications` (`Protocol.swift:4919-5013`, verified by `EngineClientTests.testEveryProtocolMethodIsClassifiedAndMutatingMethodsAreRefusedWhileLocked` in `EngineClientTests.swift`) classifies all 60 JSON-RPC methods and enforces at `EngineClient.call` (`EngineClient.swift:158-167`) that only `app.info`, `engine.ping`, `accounts.list`, `bridges.list`, `spaces.list`, and `labels.list` are allowed while `AppLockGate.isLocked` is `true`.

### Carried to later parts

All items carried to 4.6 from earlier parts — the two-column Settings window (`⌘,`) with search (`SearchSuggestions`) and deep-link commands, notifications (`Delay notifications for`, `Repeat unread notifications`, `Auto copy OTP/2FA codes`, sound effects, per-account overrides), Dock badge modes, Dock right-click menu and menu bar tray (`⌘⌥Q`), Login Item (`SMAppService.mainApp`), Touch ID app lock (`AppLockGate`, `AppLockOverlay`), detached chat/space/thread windows (`DetachedChatBrowserWindow.tsx`, `DetachedSpaceBrowserWindow.tsx`, `ThreadedRepliesBrowserWindow.tsx`, `menu:File` Open Chat in New Window, `command` Open space in new window, and double-click chat `"Opens it in a new window"`), `HotkeyRegistry` and `KeyboardShortcutsSheet` (`⌘/`), Accounts & Bridges lifecycle (`bridges.list`, `bridges.restart`, `accounts.remove`, `accounts.subAccounts`, `"Remove <App> from macOS Dock"`), and local `"Report a Problem…"` (`⌘⇧P`) — are delivered in 4.6 above. Still deferred to later parts:

- A reply-network shortcut (`⌘L` is Remind Me).
- Deferred to part 4.7 or not planned in iteration 1 (11 ledger rows remaining after 4.6 delivered `Open space in new window`, `ThreadedRepliesBrowserWindow.tsx`, and `menu:File` Open Chat in New Window):
  - `command` Join a Matrix room: not planned in iteration 1 (Courier runs five non-Matrix bridges with no generic Matrix room join).
  - `command` Profile: not planned in iteration 1 (no cloud account profile pane).
  - `component` ChangeEmailBrowserWindow.tsx: not planned in iteration 1 (no cloud account email management).
  - `component` ChatThemeBrowserWindow.tsx: part 4.7 (Appearance, wallpapers and per-chat themes).
  - `component` ChatThemeWindow.tsx: part 4.7 (Appearance, wallpapers and per-chat themes).
  - `component` DeleteAccountModal.tsx: not planned in iteration 1 (no cloud account deletion).
  - `component` DeleteAccountPrompt.tsx: not planned in iteration 1 (no cloud account deletion).
  - `hotkey` Message: Talk to Type: part 4.7 (dictation stub).
  - `setting:ai` Use OpenAI's Whisper model for Talk to Type and transcribing: part 4.7 (voice-note transcription stub).
  - `setting:general` Show Telegram Topics as separate spaces: not planned in iteration 1 (`mautrix-telegram` does not expose forum topics as separate portal spaces).
  - `setting:general` Show WhatsApp Communities as separate spaces: not planned in iteration 1 (`mautrix-whatsapp` bridges community rooms directly without a separate space hierarchy).

---

## Google Chat (`gchat` — Network 6: Rust `gchat_ffi` crate + Go `bridgev2` connector)

### Automated verification (synthetic fixtures and loopback fake server only; no `*.google.com` network calls)

- **Rust crate & C-ABI FFI (`apps/desktop/courier/gchat/src/lib.rs`, `apps/desktop/courier/gchat/src/ffi.rs`, `apps/desktop/courier/gchat/include/gchat.h`)**:
  - `decode_pblite_dynamic` and `encode_pblite_dynamic` (`apps/desktop/courier/gchat/src/pblite.rs:23`, `apps/desktop/courier/gchat/src/pblite.rs:265`, verified by `fuzz_pblite_event_never_panics_on_deep_and_malformed_json` in `apps/desktop/courier/gchat/src/fuzz_tests.rs:243`).
  - `ChunkParser` (`apps/desktop/courier/gchat/src/channel.rs:165`, verified by `fuzz_chunk_parser_never_panics_on_adversarial_and_random_inputs` in `apps/desktop/courier/gchat/src/fuzz_tests.rs:219`).
  - `DomainCookieJar` (`apps/desktop/courier/gchat/src/cookies.rs:52`, verified by `fuzz_cookies_never_panics_on_arbitrary_headers_and_maps` in `apps/desktop/courier/gchat/src/fuzz_tests.rs:289`) requires the five verified cookies `COMPASS` and `OSID` on `chat.google.com` (`REQUIRED_CHAT_COOKIES` in `apps/desktop/courier/gchat/src/cookies.rs:12`) plus `SID`, `HSID`, and `SSID` on `.google.com` (`REQUIRED_GOOGLE_COOKIES` in `apps/desktop/courier/gchat/src/cookies.rs:13`), while keeping optional cookies (`OPTIONAL_GOOGLE_COOKIES` in `apps/desktop/courier/gchat/src/cookies.rs:14`) when present.
  - `annotations_to_matrix_html` (`apps/desktop/courier/gchat/src/fmt/inbound.rs:314`) and `matrix_html_to_annotations` (`apps/desktop/courier/gchat/src/fmt/outbound.rs:742`, verified by `test_inbound_uninvite_mention_does_not_set_mention_all` in `apps/desktop/courier/gchat/src/fmt/inbound.rs:1012` and `fuzz_fmt_annotations_never_splits_surrogate_pairs_or_panics` in `apps/desktop/courier/gchat/src/fuzz_tests.rs:267`).
  - `validate_url_for_role` (`apps/desktop/courier/gchat/src/netguard.rs:47`, verified by `TestProductionLibraryRejectsLoopbackAndNeverAttachesCookies` in `apps/desktop/courier/engine/internal/networks/gchat_link_test.go:23`) rejects loopback and private IP ranges in production while allowing loopback only under the `test-loopback` test build (`apps/desktop/courier/engine/internal/gchat/loopback_test.go:13`).
- **Go `bridgev2` connector (`apps/desktop/courier/engine/internal/gchat/connector.go`, `apps/desktop/courier/engine/internal/gchat/rooms.go`, `apps/desktop/courier/engine/internal/gchat/pb/helpers.go`)**:
  - Cookie login and session validation (`Connector.CreateLogin` and `CookieLogin.SubmitCookies` in `apps/desktop/courier/engine/internal/gchat/connector.go:258`, `apps/desktop/courier/engine/internal/gchat/connector.go:306`, verified by `TestGChatCookieLoginFlowCreatesUserLogin` in `apps/desktop/courier/engine/internal/gchat/gchat_test.go:68`).
  - Initial `paginated_world` sync, `catch_up_user` / `catch_up_group`, and `list_topics` / `list_messages` backfill (`Client.syncWorld`, `Client.FetchMessages`, `Client.catchUpAfterReconnect`, and `Client.catchUpGroup` in `apps/desktop/courier/engine/internal/gchat/sync.go:178`, `apps/desktop/courier/engine/internal/gchat/sync.go:457`, `apps/desktop/courier/engine/internal/gchat/sync.go:603`, `apps/desktop/courier/engine/internal/gchat/sync.go:665`, verified by `TestPaginatedWorldSyncsDMsAndSpacesWithThreadedMetadata`, `TestBackfillUsesListTopicsForSpacesAndListMessagesForDMs`, `TestCatchUpUserAdvancesUserRevisionWithoutOverwritingGroupRevision`, and `TestEndToEndConnectSyncStreamReconnectCatchUpAndBadCredentials` in `apps/desktop/courier/engine/internal/gchat/gchat_test.go:278`, `apps/desktop/courier/engine/internal/gchat/gchat_test.go:419`, `apps/desktop/courier/engine/internal/gchat/gchat_test.go:502`, `apps/desktop/courier/engine/internal/gchat/gchat_test.go:804`).
  - Outbound and inbound messages, threaded vs flat Spaces, edits, unsend, reactions, typing, and read receipts (`Client.HandleMatrixMessage`, `Client.HandleMatrixEdit`, `Client.HandleMatrixMessageRemove`, `Client.HandleMatrixReaction`, `Client.HandleMatrixTyping`, `Client.HandleMatrixReadReceipt` in `apps/desktop/courier/engine/internal/gchat/send.go:173`, verified by `TestSendNewTopicInThreadedSpaceAndCreateMessageInThreadOrDM`, `TestSendEditUnsendReactionReceiptAndTyping`, and `TestAdvertisedCapabilitiesAllHaveWorkingHandlers` in `apps/desktop/courier/engine/internal/gchat/gchat_test.go:1180`, `apps/desktop/courier/engine/internal/gchat/gchat_test.go:1459`, `apps/desktop/courier/engine/internal/gchat/gchat_test.go:2200`).
  - Media upload and authenticated download (`Client.uploadMedia` and `Client.downloadAttachment` in `apps/desktop/courier/engine/internal/gchat/media.go:42`, `apps/desktop/courier/engine/internal/gchat/media.go:56`, verified by `TestMultiAttachmentInboundUsesZeroPaddedPartIDsAndOutboundUploadsViaScotty` and `TestInboundAttachmentFailureAndHTMLBecomePlaceholdersWithoutAbortingBatchAndExtractsField15AndAvatar` in `apps/desktop/courier/engine/internal/gchat/gchat_test.go:2774`, `apps/desktop/courier/engine/internal/gchat/gchat_test.go:3102`).
  - DM creation by Gaia ID or email (`Client.ResolveIdentifier`, `Client.CreateChatWithGhost`, and `Client.createDM` in `apps/desktop/courier/engine/internal/gchat/rooms.go:48`, `apps/desktop/courier/engine/internal/gchat/rooms.go:89`, `apps/desktop/courier/engine/internal/gchat/rooms.go:104`, plus `Actions.CanLookupEmail` in `apps/desktop/courier/engine/internal/actions/chatstate.go:122`, verified by `TestResolveIdentifierAndCreateDMByGaiaIDOrEmail` and `TestStartDMByEmailEndToEndThroughRPCActionsAndFakeServer` in `apps/desktop/courier/engine/internal/gchat/gchat_test.go:3302`, `apps/desktop/courier/engine/internal/gchat/gchat_test.go:4100`, `TestCanLookupEmailFollowsConnectorAndClient` in `apps/desktop/courier/engine/internal/actions/chatstate_test.go:291`, and `InboxModelTests.testStartNewChatByEmailEndToEndFromAppModelThroughEngineToFakeServerAndInbox` in `apps/desktop/courier/app/Tests/CourierCoreTests/InboxModelTests.swift:1316`), while Space creation (`can_create_group`) remains unadvertised per spec §13.
  - Space rename and description update preserving `guidelines` (`Client.HandleMatrixRoomName` and `Client.HandleMatrixRoomTopic` in `apps/desktop/courier/engine/internal/gchat/rooms.go:275`, `apps/desktop/courier/engine/internal/gchat/rooms.go:308`, verified by `TestSetChatNameAndSetChatTopicPreservesSpaceGuidelines` in `apps/desktop/courier/engine/internal/gchat/gchat_test.go:3449`).
  - Permanent mute/unmute sync (timed mute refused), invite accept/decline, Space membership (`create_membership` / `remove_memberships`), and DM hide (`hide_group`) (`Client.HandleMute`, `Client.HandleMatrixMembership`, `Client.HandleMatrixDeleteChat` in `apps/desktop/courier/engine/internal/gchat/rooms.go:380`, `apps/desktop/courier/engine/internal/gchat/rooms.go:422`, `apps/desktop/courier/engine/internal/gchat/rooms.go:521`, verified by `TestMuteSyncAndMembershipAndHideGroup` in `apps/desktop/courier/engine/internal/gchat/gchat_test.go:3604` and `TestGroupAndChatManagementTableMatchesTheBridges` in `apps/desktop/courier/engine/internal/networks/networks_test.go:724`).
  - Log scrubbing (`logscrub.Redact` in `apps/desktop/courier/engine/internal/logscrub/logscrub.go:280-287`, verified by `TestLogscrubRedactsGoogleChatCookiesTokensGaiaIDsAndWebChannelURLs` in `apps/desktop/courier/engine/internal/logscrub/bridge_test.go:179`).
- **Swift macOS UI & capabilities (`apps/desktop/courier/app/Sources/CourierCore/LoginFlowModel.swift`, `apps/desktop/courier/app/Sources/CourierCore/ChatFeatures.swift`, `apps/desktop/courier/app/Sources/CourierCore/InboxModel.swift`, `apps/desktop/courier/app/Sources/Courier/SignInWindow.swift`)**:
  - `NetworkNames.displayName` (`ChatFeatures.swift:22`), `NetworkAppearance.of` (`InboxPresentation.swift:145`), `StartNewChatDraft.isEmailAddress` (`InboxModel.swift:2149`), and `LoginFlowModel.offeredFlows` (`LoginFlowModel.swift:275`, `LoginFlowModel.swift:319`, verified by `ChatFeaturesTests`, `CookieCollectorTests`, `LoginFlowModelTests`, `InboxModelTests`, and `ViewSnapshotTests.testGoogleChatSignInWindowAndChatSnapshotsLightAndDark` in `ViewSnapshotTests.swift:4594`).

### Owner's by-hand verification day (`apps/desktop/courier/engine/docs/gchat-by-hand.md`)

Because automated tests never contact `*.google.com`, verify these 11 live-account checks by hand following `apps/desktop/courier/engine/docs/gchat-by-hand.md`:

- [ ] **Build and Install**: Run `bazel run --config=macos-app //apps/desktop/courier/app:install` and launch `/Applications/Courier.app`.
- [ ] **Cookie Sign-In & Keychain Persistence**: Link Google Chat in `AddNetworkView` / `SignInWindowController`; verify `COMPASS`, `OSID`, `SID`, `HSID`, and `SSID` are collected, the window closes automatically, and the account displays as `Name (email)` and reconnects across app relaunch.
- [ ] **Initial Sync (`paginated_world`)**: Confirm existing DMs and named Spaces populate with names, avatars, and unread state.
- [ ] **Single-Page Backfill (`list_messages` & `list_topics`)**: Open a DM and a threaded Space and scroll up to verify single-page backfill.
- [ ] **Rich Text, UTF-16 Annotations, Replies & `local_id` Deduplication**: Send and receive formatted text, `@user` and `@all` mentions, inline quote-replies, and Space thread replies; verify `local_id` deduplication prevents duplicate bubbles.
- [ ] **Reactions, Edits & Unsend**: Add and remove emoji reactions (including `"❤️"` with `U+FE0F` normalization), edit a sent message, and unsend a message in both directions.
- [ ] **Media Upload & Download via Scotty**: Upload and download an image, a voice note/audio file, and a general file attachment via Scotty.
- [ ] **Read Receipts & Typing Indicators**: Verify read receipts and the 6-second typing indicator in both directions.
- [ ] **Mute/Unmute, Space Rename & Description, and Start DM by Email**: Toggle mute/unmute, rename a Space, update a Space description (verifying Space `guidelines` remain intact), and start a new DM by email address.
- [ ] **Mac Sleep/Wake (>2 Minutes) Reconnect & Catch-Up Sync**: Put the Mac to sleep for >2 minutes, wake it, and verify WebChannel reconnects and runs `catch_up_user` / `catch_up_group` without missing messages sent while asleep.
- [ ] **Scrubbed Log Inspection (`~/Library/Logs/Courier/`)**: Inspect `~/Library/Logs/Courier/` and `ProblemReportSheet` export and confirm zero cookie values, XSRF tokens, Gaia IDs, emails, or message bodies appear.
