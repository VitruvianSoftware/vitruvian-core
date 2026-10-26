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

Not in 4.5a, and not expected to work in 4.5a:

- A reply-network shortcut (⌘L is Remind Me).
- Carried from 4.5a to part 4.5b below (rich media playback, capture, previews and media viewer — 35 ledger rows) and part 4.5c (emoji, emoticons, stickers and GIFs — 10 ledger rows).
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
- [ ] A 1 GB+ video sends on WhatsApp without the app’s memory jumping (streamed from disk).
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
- [ ] Large files stream from disk without spiking memory and respect each network’s file size ceiling. Attaching a file larger than the chat network’s limit shows an orange warning on the chip ("Exceeds <Network> <limit> limit"). Sending a 1 GB+ video on WhatsApp or Telegram streams the file from disk through the media store and bridge upload without buffering the whole file in memory.
- [ ] Downloaded and opened attachments keep macOS quarantine metadata and never overwrite existing files. Pressing ⌘D or clicking Download saves to your configured Downloads location (or opens a Save panel when "Always ask where to save files before downloading" is on), suffixes duplicates as `file (2).ext`, and stamps `com.apple.quarantine` on every saved or Quick Look temp file so macOS Gatekeeper checks executables.

### What to expect on each network

Courier reads these limits and formats from each network’s pinned bridge capabilities (`mautrix-whatsapp`, `mautrix-signal`, `mautrix-telegram`, `mautrix-gmessages`, `mautrix-slack`).

| | WhatsApp | Signal | Telegram | Google Messages | Slack |
|---|---|---|---|---|---|
| Max file size | 2000 MiB | 100 MiB | 2 GiB (4 GiB Premium; 10 MiB photo) | 100 MiB RCS (1 MiB MMS) | 1 GB |
| Images and captions | JPEG full, PNG/WebP partial, GIF partial if `ffmpeg`; caption up to 65536 | GIF, PNG, JPEG, WebP, BMP, AVIF full (4096×4096); caption up to 2000 | JPEG full, WebP/PNG/GIF partial (10 MiB photo, larger sent as document); caption 1024 (2048 Premium) | PNG, JPEG, GIF, BMP, WBMP, WebP full; RCS sends caption as a separate text message | JPEG, PNG, GIF, WebP full; caption up to 40000 |
| Videos | MP4, 3GPP full; WebM, QuickTime partial if `ffmpeg`; caption full | MP4, OGG, WebM full; caption full | MP4 full (2 GiB / 4 GiB Premium); caption full | MP4, 3GPP, WebM full (100 MiB RCS) | MP4, WebM full (1 GB); caption full |
| Audio files | MPEG, MP4, OGG, AAC, AMR full; caption dropped | AAC, MPEG, MP3, FLAC full; caption unsupported | MPEG, MP4 full; caption full | AAC, AMR, MPEG, MP4, MP4-LATM, 3GPP, OGG full | MPEG, WebM, WAV full; caption full |
| Voice notes and waveform | `audio/ogg; codecs=opus` full (`audio/ogg` rewritten); waveform 0–100 and duration both ways | Outgoing `audio/aac` full (`audio/ogg` converted via `ffmpeg`), max 3600s; incoming converted to `.ogg` opus if `ffmpeg`, waveform not bridged | `audio/ogg`, `audio/mpeg`, `audio/mp4` full; 5-bit packed waveform and duration both ways | Outgoing `audio/mp4` full (`audio/ogg` converted via `ffmpeg` to `.m4a`); incoming tagged voice and converted to `.ogg` if `ffmpeg` | `audio/webm; codecs=opus` and `audio/mp4` (`.m4a`) full (`audio/ogg` partial via `ffmpeg`), max 300s; incoming `slack_audio` has waveform and duration |
| Voice-note played receipts | Not bridged (tracked on this Mac only) | Not bridged (tracked on this Mac only) | Not bridged (tracked on this Mac only) | Not bridged (tracked on this Mac only) | Not bridged (tracked on this Mac only) |
| Generic files and PDFs | `*/*` full (2000 MiB), caption full | `*/*` full (100 MiB), caption full | `*/*` full (2 GiB / 4 GiB Premium), caption full | `application/*`, `text/*` full (100 MiB RCS) | `*/*` full (1 GB), caption full |
| GIFs | MP4 (`GifPlayback`) full, `image/gif` transcoded via `ffmpeg` | `image/gif` and MP4 full | MP4 full, `image/gif` partial | `image/gif` full | `image/gif` full |
| Stickers | WebP full, PNG/JPEG/Lottie partial; no caption | PNG, APNG full, WebP partial, GIF partial if `ffmpeg`; no caption | WebP, Lottie, WebM full, JPEG/PNG partial | Not supported | Not in bridge capabilities (outgoing `m.sticker` converted to `m.image`) |
| View-once media | Outgoing not supported; incoming bridged as normal media when `DisableViewOnce` is false | Outgoing not supported; incoming sets a 5-minute after-read disappearing timer when `DisappearViewOnce` is true | Outgoing not supported; incoming sets a 15-second after-read disappearing timer | Not supported | Not supported |
| Location messages | Full both ways (`geo:<lat>,<long>`) | Partial (incoming location; outgoing `geo:` formatted as a text URL) | Full both ways (`geo:<lat>,<long>`) | Not supported | Rejected |
| Link previews | Full incoming and outgoing; empty preview list suppresses preview | Full incoming and outgoing (with uploaded image) | Incoming webpage to preview; outgoing empty preview list sets `NoWebpage: true` | Not supported | Incoming attachments to preview; outgoing empty preview list disables link unfurling |
| BlurHash on attachments | Field in shared `FileInfo`; not computed by bridge | Preserved incoming and outgoing (`Blurhash` / `AnoaBlurhash`) | Field in shared `FileInfo`; not computed by bridge | Field in shared `FileInfo`; not computed by bridge | Field in shared `FileInfo`; not computed by bridge |

- [ ] Each cell above holds on the real network. Check at least sending a photo, video, voice note, PDF and link on every network you have.
- [ ] On WhatsApp, sending a voice note requires `audio/ogg; codecs=opus` (Courier converts recorded `.m4a` voice notes via `ffmpeg` when installed on this Mac; if `ffmpeg` is missing, Courier shows an error explaining that `ffmpeg` is needed for WhatsApp voice notes).
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
- Sending a voice note on WhatsApp requires `ffmpeg` on this Mac (`/opt/homebrew/bin/ffmpeg` or `/usr/local/bin/ffmpeg`) so Courier can convert the recorded `.m4a` into `audio/ogg; codecs=opus`. On Signal, Telegram, Google Messages and Slack, `.m4a` (`audio/mp4` / `audio/aac`) is sent directly without `ffmpeg`.

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

