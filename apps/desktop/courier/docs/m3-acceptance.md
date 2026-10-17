<!--
Copyright 2026 VitruvianSoftware
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Courier milestone 3: acceptance list

This is the checklist for the day you use Courier instead of your other chat app. Read and reply in Courier all day, and tick a line when you have seen that thing work. Write down anything wrong, with no names, numbers or message text.

Each line is one row of the inventory (`docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/ledger.tsv`), kept under its row name so you can look it up there. The text after the dash says, in plain words, what Courier does now. A tick means "I saw this work", not "the code exists".

Milestone 3 is the first usable app: inbox, reading, replying, files, adding a network, notifications. Rows the plan leaves for Milestone 4 are at the end, so nothing is dropped quietly.

One rule for the day: do not open the same chat in the other chat app while testing Courier. It would send a read receipt. Courier's own read receipts are real.

## Before you start

- Install Courier with `bazel run --config=macos-app //apps/desktop/courier/app:install`. It puts Courier in /Applications with Courier's own Telegram app ID built in, so there is nothing to set up for Telegram: Add a Network, then Telegram, goes straight to its QR code. If the install says "this Courier has no Telegram app ID built in", run `bazel run //tools/sync-env-secrets:bw-pull` and install again (`app/README.md` says where the ID lives). A Courier without it asks for an api_id and api_hash from my.telegram.org when you pick Telegram, once, and carries on by itself.
- Link all five networks again, from the app (Add a Network). The links made with the command-line tool in Milestone 1 are separate and are not used here.
- On your phones, unlink the old Courier Milestone 1 devices (WhatsApp and Signal: Settings, Linked devices). Leaving them linked can bring every message in twice.
- Linking Google Messages here signs out any other web session of Google Messages, in any browser.

## Before the list: four things the plan was most worried about

These are not inventory rows. They are what the milestone was built to get right, so look at them first.

- [ ] First start does not shout. After linking a network, the first sync pulls in recent history. You should get no burst of notifications for old messages.
- [ ] A message that was pending when the engine restarted is still there afterwards, once. If the engine stopped before the network answered, it says "May have been sent", with Retry and Delete; Courier never sends it again by itself. It is never lost or doubled.
- [ ] Closing the sign-in window half way (Slack or Google Messages) leaves nothing half-linked. Courier says calmly what happened, and you can start again.
- [ ] A big inbox and a long chat stay quick: opening the app and scrolling back through a long chat do not freeze it.

## Keys

- [ ] `hotkey` Select Next Chat: ⌘] or ⌘⌥↓ moves to the next chat in the list. The selection stays on that chat when new messages arrive.
- [ ] `hotkey` Select Previous Chat: ⌘[ or ⌘⌥↑ moves to the previous chat.
- [ ] `hotkey` Select Next Unread Chat: ⌘U jumps to the next chat with unread messages, and wraps round to the first one.
- [ ] `hotkey` Chat: Toggle Mark As Read: ⌘⇧U marks the selected chat read. With nothing unread it does nothing (marking a chat unread is Milestone 4).
- [ ] `hotkey` Chat: Toggle Mute: ⌘⇧M mutes the selected chat; the menu item then reads Unmute Chat, and the row shows a muted bell.
- [ ] `hotkey` Scroll to the bottom of a chat: ⌘↓ jumps to the newest message, including while typing in the box.
- [ ] `hotkey` Chat: Send File: ⌘O opens a file picker; the chosen files show as chips above the box.
- [ ] `hotkey` Message: Quote & Reply: Select a message and press ⌘R: a reply chip appears above the box. Esc clears it.
- [ ] `hotkey` Send Message: Enter sends. An empty or all-spaces box sends nothing.
- [ ] `hotkey` Insert New Line: ⇧Enter, ⌥Enter and ⌃Enter each put a new line in the box.
- [ ] `hotkey` Quit App: ⌘Q quits Courier and stops its engine. The Add a Network sheet being open must not stop it.

## Notifications

- [ ] `setting:notifications` Message notifications: A new message in a chat that is not muted raises a macOS notification: chat name as the title, the text (or a type label) as the body. Clicking it opens that chat. There is no switch for it yet; it is always on.
- [ ] `setting:notifications` Group message notifications: A message in a group chat notifies too, and who wrote it is shown under the chat name. No separate switch yet.
- [ ] `setting:notifications` Notify when app is in focus: With Courier in front, a message in a chat other than the open one still notifies. The chat you are looking at does not. "Looking" means the window is in front, the screen is unlocked and awake, and you touched the Mac in the last three minutes: lock the screen or walk away and the open chat notifies too, and stays unread until you are back. No switch yet.
- [ ] `setting:notifications` Sound: The notification plays the default system sound. Choosing a sound is Milestone 4.

Also part of this, not an inventory row of its own: the Dock icon's badge counts unread chats that are not muted and clears at zero, and the menu-bar icon fills in while anything is unread. The notification itself has Mark as Read and a Reply box.

## Menus

- [ ] `menu:File` Close Window: File ▸ Close (⌘W) closes the window. Courier keeps running, with its Dock icon and menu-bar icon, and Open Courier in the menu-bar menu brings the window back.
- [ ] `menu:File` Close All: File ▸ Close All is there and closes every Courier window, the same way.
- [ ] `menu:Beeper` Hide Beeper: Courier ▸ Hide Courier (⌘H) hides the app.
- [ ] `menu:Beeper` Hide Others: Courier ▸ Hide Others hides every other app.
- [ ] `menu:Beeper` Show All: Courier ▸ Show All brings them back.
- [ ] `menu:Beeper` Quit Beeper: Courier ▸ Quit Courier (and the menu-bar icon's Quit Courier) stops the engine, then exits. Nothing is left running.

## Inbox (§3)

- [ ] `component` ThreadsList.tsx: The chat list: newest chat first, one row per chat, with the selection kept across refreshes.
- [ ] `component` ThreadAvatar.tsx: A chat's picture shows in its row and in the conversation header when the network provides one.
- [ ] `component` DefaultAvatar.tsx: With no picture, a coloured circle with initials; the same name always gets the same colour.
- [ ] `component` ThreadListReadIcon.tsx: The unread count on the row (grey when the chat is muted); it clears when you open the chat.
- [ ] `component` ThreadPreviewTag.tsx: A non-text last message shows a label in italics: Image, Video, Voice note, File.
- [ ] `component` message-preview.tsx: The preview line shows the latest message, with You: in front when it is yours.
- [ ] `component` BrandEmptyStateMessage.tsx: The empty states read sensibly: Add a network with nothing linked, No chats yet, Select a chat.

## Conversation (§5)

- [ ] `component` MessageList.tsx: Opening a chat shows the newest messages at the bottom; scrolling to the top loads older ones (Load older messages).
- [ ] `component` SubComponents.tsx: Day separators (Today, Yesterday, then dates), and a New divider where the unread messages start.
- [ ] `component` ScrollToBottom.tsx: Scrolled up, a button jumps to the newest message and counts the new ones that arrived.
- [ ] `component` MessageContent.tsx: Message bodies show text; a deleted message reads This message was deleted; one not yet decryptable says it is waiting.
- [ ] `component` MessageText.tsx: Text keeps its line breaks and wraps in the bubble.
- [ ] `component` linkify.tsx: Web and mail addresses in a message are links that open in the browser or mail app.
- [ ] `component` MessageReactions.tsx: Reactions show as chips under the message with counts; the ones you made are highlighted.
- [ ] `component` MessageReactButtons.tsx: Hovering a message offers quick reactions and Reply; clicking one reacts.
- [ ] `component` MessageErrorTooltip.tsx: A message that failed says Not sent, with Retry and Delete; hovering gives the network's reason. A reply that timed out says it may have gone.
- [ ] `component` BrandReplyLineSegment.tsx: A reply shows the message it quotes above its text (or Original message not loaded).
- [ ] `component` icons-toolbar.tsx: Your messages carry a status in words: Sending…, Sent, or Not sent.

## Composer (§6)

- [ ] `component` ComposeMessage.tsx: The box under the conversation: Enter sends, new-line keys add lines, and a draft is kept for each chat while the app runs.
- [ ] `component` BrandSendButton.tsx: The send button sends the same as Enter.
- [ ] `component` PendingAttachments.tsx: Chosen files show as chips before sending, each with a remove button. Over 90 MB in total is refused with a plain message.
- [ ] `component` FileAttachment.tsx: A file chip shows the name and size.
- [ ] `component` FileDropOverlay.tsx: Dragging files over the chat shows Drop files here to attach; dropping adds them.
- [ ] `component` Emoji.tsx: The emoji button opens the macOS emoji picker (⌃⌘Space).
- [ ] `component` TooltipButton.tsx: Hovering the composer's buttons says what they do and the key.

## Message actions (§7)

- [ ] `component` PopupMenu.tsx: Right-clicking a message gives Reply, React and Copy.

## Media and files (§8)

- [ ] `component` EnhancedImg.tsx: Images show inline in the chat, sized to fit.
- [ ] `component` FilePlaceholder.tsx: Other files, voice notes and videos show as a chip with name and size; clicking opens the file in its own app. One not downloaded yet says so.
- [ ] `component` ImageError.tsx: An image that cannot be shown says Image can't be shown.

## Onboarding (§15)

- [ ] `component` Onboarding.tsx: A first run with nothing linked shows Add a network and its button; there is no account to create.

## Adding a network (§16)

- [ ] `component` AddAccountsBrowserWindow.tsx: File ▸ Add a Network… (or the first-run button) opens the picker listing the five networks.
- [ ] `component` auth.tsx: Each sign-in step shows in the sheet, one after another, ending in Linked as <name>.
- [ ] `component` BridgeV2AuthComponent.tsx: Steps that ask for typed values show one field each: secret ones hidden, patterns checked as you type, choices as a menu.
- [ ] `component` BridgeV2Instructions.tsx: Each step says in words what to do (scan, enter the code on your phone, sign in).
- [ ] `component` LoginQRCode.tsx: A QR step shows the code to scan from your phone, and waits.
- [ ] `component` QRCode.tsx: The QR code is drawn sharp and large enough to scan.
- [ ] `component` AuthComponents.tsx: A web sign-in step (Slack, Google Messages) says to sign in in the window that opened.
- [ ] `component` LoginBrowserWindow.tsx: The sign-in window opens the real site, shows the address it is really on, and closing it cancels the sign-in with a calm message.
- [ ] `component` BrandNetworkIcon.tsx: Each network has its own small icon and colour in rows, the account strip and the header.

## Milestone 4

Left for the next milestone. These have no tick box: they are not expected to work yet. Row names are as written in the inventory.

### Keys

**Chats: archive, pin, history, spaces**

- `hotkey` Chat: Archive All Read
- `hotkey` Chat: Start New
- `hotkey` Chat: Toggle Archive
- `hotkey` Chat: Toggle Pin
- `hotkey` Cycle Chats (hold shift to reverse)
- `hotkey` History: Next Chat
- `hotkey` History: Previous Chat
- `hotkey` Switch First 9 Chats Modifier
- `hotkey` Switch First 9 Spaces Modifier
- `hotkey` Toggle Space Bar
- `hotkey` Toggle Chat Info
- `hotkey` Open User Profile
- `hotkey` Remind Later

**Search, the command bar, filters and accounts**

- `hotkey` Command Bar
- `hotkey` Cycle Filters
- `hotkey` Filter By Account
- `hotkey` Filter: Unread
- `hotkey` Search
- `hotkey` Search: Room
- `hotkey` Select Next Account
- `hotkey` Select Previous Account
- `hotkey` Focus App and Command Bar

**Messages: edit, forward, send later, media, reactions**

- `hotkey` Download Attachments
- `hotkey` Message: Edit
- `hotkey` Message: Forward
- `hotkey` Message: Open First Link
- `hotkey` Message: Quick React
- `hotkey` Message: Quote or Edit Selected Message
- `hotkey` Message: Record Audio
- `hotkey` Message: Send GIF
- `hotkey` Message: Send Later
- `hotkey` Message: Send Message and Archive
- `hotkey` Message: Send Sticker
- `hotkey` Message: Talk to Type
- `hotkey` Show Replies

**The app: settings, zoom, sidebar, help**

- `hotkey` Focus App
- `hotkey` Keyboard Shortcuts
- `hotkey` Minimize To Menu Bar
- `hotkey` Reload App
- `hotkey` Report a Problem
- `hotkey` Reset Zoom
- `hotkey` Send Feedback
- `hotkey` Settings
- `hotkey` Toggle Sidebar
- `hotkey` Zoom In
- `hotkey` Zoom Out

### Notifications

Settings for these (and the Settings window itself) are Milestone 4; Milestone 3 uses the defaults above.

- `setting:notifications` Sound effects
- `setting:notifications` Message request notifications
- `setting:notifications` Notify when someone reacts to a message
- `setting:notifications` Notify when someone starts typing (supported platforms only)
- `setting:notifications` Delay notifications for
- `setting:notifications` Repeat notification if still unread after

### Menus

Courier has a few menu items of its own meanwhile (File ▸ Add a Network…, the Chat and Message menus); the rows below are the ones it does not have yet, or has only as the standard macOS item.

- `menu:Beeper` About Beeper
- `menu:Beeper` Check for Updates…
- `menu:Beeper` Accounts…
- `menu:Beeper` Preferences
- `menu:Beeper` Command Bar…
- `menu:Beeper` Search…
- `menu:Beeper` Services
- `menu:Beeper` Lock App
- `menu:Beeper` Logout of Beeper…
- `menu:File` Open…
- `menu:File` New Chat
- `menu:File` Open Chat in New Window
- `menu:View` Hide Space Bar
- `menu:View` Hide Sidebar
- `menu:Help` Report a Problem
- `menu:Help` Open Beeper Help
- `menu:Help` Open Beeper.com
- `menu:Help` Follow @Beeper on X
- `menu:Help` Changelog
- `menu:Help` Privacy & Security
- `menu:Help` Keyboard Shortcuts
- `menu:Help` Logout of Beeper…

### Inbox (§3)

- `component` BrandTypingIndicator.tsx
- `component` ContactItem.tsx
- `component` DraftChatAvatar.tsx
- `component` GroupAvatar.tsx
- `component` PinnedThreadListItem.tsx
- `component` SelectionModeActions.tsx
- `component` SelectionModeHeader.tsx
- `component` Skeleton.tsx
- `component` StackedAvatars.tsx
- `component` ThreadPreviewMedia.tsx
- `component` TypingIndicator.tsx
- `component` UnknownAvatar.tsx
- `component` UnreadMentionIndicator.tsx

### Conversation (§5)

- `component` BrandUserHoverCard.tsx
- `component` BrandVideo.tsx
- `component` Code.tsx
- `component` DisappearedMessagesGrouper.tsx
- `component` Email.tsx
- `component` GalleryGrouper.tsx
- `component` HoverCard.context.tsx
- `component` HoverCard.tsx
- `component` JumpToMessage.tsx
- `component` MembershipGrouper.tsx
- `component` MessageEditHistory.tsx
- `component` MessageIFrame.tsx
- `component` MessageMention.tsx
- `component` MessageTranslationRow.tsx
- `component` MessageTranslations.tsx
- `component` PhoneNumber.tsx
- `component` ScheduledMessageDate.tsx
- `component` ScheduledMessages.tsx
- `component` Spoiler.tsx
- `component` TimelineNote.tsx
- `component` ToggleScheduledMessages.tsx
- `component` entry-preview.tsx
- `component` message-info.tsx

### Composer (§6)

- `component` Autocomplete.tsx
- `component` BrandStopButton.tsx
- `component` Bubble.tsx
- `component` Button.tsx
- `component` EmojiItem.tsx
- `component` FreebieNudge.tsx
- `component` GifPicker.tsx
- `component` LinkDialog.tsx
- `component` PollCreator.tsx
- `component` QuickReplyItem.tsx
- `component` StickerPicker.tsx
- `component` TextAreaAutocomplete.tsx
- `component` createMentionTriggerSettings.tsx
- `component` createSlashCommandTriggerSettings.tsx
- `component` icons-compose.tsx

### Message actions (§7)

- `component` BrandPopover.tsx
- `component` SelectMessageCommand.tsx

### Media and files (§8)

- `component` AttachmentCarousel.tsx
- `component` Audio.tsx
- `component` FileRowSpinner.tsx
- `component` GalleryVideoPoster.tsx
- `component` GlobalAudioPlayer.tsx
- `component` LoadingAttachment.tsx
- `component` Location.tsx
- `component` MediaViewerBrowserWindow.tsx
- `component` MediaWithSender.tsx
- `component` PDF.tsx
- `component` PDFAttachment.tsx
- `component` PictureInPictureBrowserWindow.tsx
- `component` TranscodedAttachment.tsx
- `component` ViewLimitedMediaViewer.tsx
- `component` index.tsx

### Onboarding (§15): Needs a Beeper account or Beeper's own tour; no Courier equivalent is planned

- `component` AwaitCredentials.tsx
- `component` AwaitEmailCode.tsx
- `component` AwaitInboxExperience.tsx
- `component` AwaitLeadRegistration.tsx
- `component` AwaitNetworkConnection.tsx
- `component` AwaitRecoveryCode.tsx
- `component` AwaitVerification.tsx
- `component` BaseConnectModal.tsx
- `component` BrandCompositeIllustration.tsx
- `component` ClippableRecoveryCode.tsx
- `component` CmdBarPage.tsx
- `component` DevicesTooltip.tsx
- `component` DownloadMobileApps.tsx
- `component` Floating.tsx
- `component` Key.tsx
- `component` KeyboardFirstPage.tsx
- `component` Lottie.tsx
- `component` OnboardingFrame.tsx
- `component` ProgressCircle.tsx
- `component` RecoveryCodeInput.tsx
- `component` RecoveryCodePreamble.tsx
- `component` Slot.tsx
- `component` SplashScreen.tsx
- `component` TakeBeeperWithYou.tsx
- `component` ThreadSearchPage.tsx
- `component` UsernameInput.tsx

### Adding a network (§16)

**Later**

- `component` AddNewAccountIcon.tsx
- `component` BrowserSessionImportCard.tsx
- `component` DetachedAccountsOnboarding.tsx
- `component` NetworkAccountsMenu.tsx
- `component` Toggle.tsx

**Not planned: Beeper Cloud, device tabs and Beeper's own icons; Courier runs on this Mac only**

- `component` CloudIcon.tsx
- `component` ConnectionPicker.tsx
- `component` DesktopIcon.tsx
- `component` MobileIcon.tsx
- `component` TabList.tsx
- `component` TabletIcon.tsx
- `component` icons-networks.tsx

### Notifications (§19)

- `component` AccountNotificationPrefs.tsx
- `component` Toasts.tsx

### Not in this list

- All 74 `command` rows: the command bar (⌘J) is Milestone 4.
- The other 77 `setting:` rows (every settings pane except notifications): Settings beyond the basics is Milestone 4.
- Components from the inventory's other areas (spaces, chat info, threads, search, AI, calendar, settings and the rest): Milestone 4 or later. This list covers only areas 3, 5, 6, 7, 8, 15, 16 and 19.

