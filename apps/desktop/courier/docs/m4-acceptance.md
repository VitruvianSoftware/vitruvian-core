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
- Part of a word of one letter, in messages. A message search needs at least two letters. Chats and people search from the first letter. A single Chinese, Japanese, Korean or Thai character does count.
- Messages a network never sent Courier. Courier can only search the history it has on this Mac. Older history appears as each network sends it.

### Before you start

- Install the build with `bazel run --config=macos-app //apps/desktop/courier/app:install`. Your chats and networks stay as they are.
- The first time Courier opens after this update, it adds your older messages to search in the background. Search works at once, and new messages are found straight away. Until the older ones are in, a line at the top of the results says "Still adding older messages to search. Some results may be missing."
- Do not open the same chat in the other chat app while you test. It would send a read receipt.

### Check these first

Nobody has seen these on screen yet, because the Mac's screen was locked while the app was being built. The tests cover the logic behind each one. Look at these before anything else.

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

- [ ] Deleted and edited words go away. Delete a message, then search for a word only it had: it does not come back. Edit a message to different words: search finds the new words and not the old ones, even if the edit reached Courier before the message did. A chat that is gone leaves none of its words or its name in search.
- [ ] Anything you type is safe. Try quotes, `*`, `-`, `(`, the words AND, OR and NOT, `NEAR(`, a single `"`, a colon, a very long paste, and emoji on their own. None gives an error or freezes the app. Each is searched as ordinary words, and emoji alone shows the calm line "Search for a word or a name. Emoji and punctuation aren’t searched." Words in double quotes find that exact run of words.
- [ ] Accents, capitals, width and scripts do not get in the way. "cafe" and "CAFE" both find "café". Full-width letters find the same word in normal letters. A word in Chinese, Japanese, Korean or Thai is found by part of it as well as the whole of it. A Hindi word is found whole, and is not cut in two. (Only try the scripts you have messages in.)
- [ ] A big history stays quick after the update. With a very large chat history, Courier opens as fast as before. New messages can be searched at once, older ones fill in behind, and quitting halfway through carries on where it stopped when you open Courier again. With thousands of chats, each search still answers quickly.
- [ ] Jumping to an old message is steady. Open a message from last year: the chat opens at it, tinted, not at the bottom. New messages arriving meanwhile do not move the view. "Jump to latest" and sending a message both go back to the newest. (This is the same as the jump lines in the first list.)

**The sections, in order**

- [ ] Before you type: Recent, Last archived, then Recent searches. The chat you are in is left out of Recent and Last archived. Inside one chat, home shows only recent searches.
- [ ] As you type: Chats, In groups, Media, then Messages. A section with nothing in it is left out. Inside one chat there are only Media and Messages.
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
- [ ] "Show partial matches" lists, after every full match, messages that have some of the words but not all. They sit under a "Partial matches" divider.

**What the panel says**

| When | What it shows |
|---|---|
| Home, nothing recent | Find any chat, person or message on this Mac. |
| Waiting more than a third of a second | Searching… |
| No results | No matches for “…” and, under it, Check the spelling, or try fewer words. |
| No results, with filters on | Nothing matches these filters. and a Clear Filters button |
| One letter, for messages | Under Chats: Type one more letter to search messages. |
| Only emoji or punctuation | Search for a word or a name. Emoji and punctuation aren’t searched. |
| Older messages still being added | Still adding older messages to search. Some results may be missing. |
| Search broke | Search isn’t working right now. and a Try Again button |

- [ ] Each line above shows in its place, word for word.
- [ ] Results do not change by themselves. If a new message arrives while search is open, the rows stay as they are. The next key you type, or the next filter you change, searches again.

**The chat menu**

- [ ] Right-click a chat ▸ Search…: opens search with "In: <chat> ×" in the field and "Search this chat" as the hint. The chat menu's order is now Pin, Search…, Hide.

### Carried to later parts

Not in 4.2, and not expected to work yet:

- The Bookmarks section of search: part 4.3, with bookmarks.
- Search suggestions, and searching inside Settings: part 4.6.
- "Open recently viewed chats", and the Commands ⌘J switch inside the panel: part 4.7. The three search commands above are registered and wait for it.
- Starting a direct chat with someone from "In groups": part 4.5.
- Searching the words in a photo's caption from the media viewer: part 4.5.
- Search tools for other programs (MCP): milestone 5.
- The "find a chat" page of the hotkey tutorial (ThreadSearchPage): not planned.
