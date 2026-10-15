# Beeper Desktop 4.3.209 (macOS) — Static screen and feature inventory

Clean-room feature inventory of the visible app, built from the shipped renderer bundle
(`app/build/renderer/*.js`), the 434 component source-file names the bundle leaks through its
crash-reporting attributes (`components.txt`), and the 2,647-entry English UI-string table
(`ui-strings.json`). It describes behaviour in our own words. No code, CSS or assets are copied.
Short UI labels are quoted only to pin down what a control does.

## How to read this

- **[O] Observed**: the string, component name, window name or setting key appears directly in the bundle.
- **[I] Inferred**: a reasonable reading of what we observed (from where a string sits in the code,
  a component name, or several strings that belong together), but not confirmed by running the app.
- Each component file name appears in **bold monospace** at least once. Many files hold several
  React components, so the sub-component names shown in brackets are also observed.
- How components were matched to strings: every rendered element carries a
  "source file" attribute. Strings that sit between two of those markers were matched to the
  nearer file. Minified modules run into each other, so a string can sometimes belong to the file
  just before. Where that mattered we checked the raw code around it.
- Status colours are not used here. This is a reference document, not a dashboard.

### Overall layout at a glance

```
+----------+-------------------------+--------------------------------------+------------------+
| Space    | Chat list (inbox)       | Conversation                         | Right pane (one  |
| bar      |  filter / sort / select |  header: name, reminder, timer, info |  at a time):     |
| (spaces, |  pinned row             |  message timeline                    |  AI | Chat Info  |
|  labels, |  chat rows              |  composer                            |  | Calendar |    |
|  accounts|  banners / empty state  |                                      |  Threaded replies|
+----------+-------------------------+--------------------------------------+------------------+
  Overlays: Command Bar, Search, toasts, popovers, context menus, modals, lock screen
  Separate windows: Settings, Media viewer, Chat Info, Thread replies, Poll creator, Edit group,
  Labels, Edit spaces, Merged chat, Chat theme, Add accounts, Login, Help, Picture-in-Picture, Debug
```

[O] The right pane is a single slot with five states: none, AI, chat info, calendar, threaded
replies. Opening one closes the others.

---

## Window catalogue

These components each open as their own native window (their names end in "BrowserWindow"). [O]

| Window | File | Purpose |
|---|---|---|
| Add accounts | **`AddAccountsBrowserWindow.tsx`** | Hosts the add-a-chat-network modal outside the main window [O] |
| Network login | **`LoginBrowserWindow.tsx`** | Log in to one network: "Login with Browser", "Login with Password", "QR Code", "Download Chrome Extension", "Reconnect account" [O] |
| Change email | **`ChangeEmailBrowserWindow.tsx`** | Change the Beeper account email [O] |
| Chat theme | **`ChatThemeBrowserWindow.tsx`** | Pick a wallpaper and bubble colour for a chat [O] |
| Create / edit label | **`CreateLabelBrowserWindow.tsx`** | Label title, icon, colour [O] |
| Edit labels (per chat) | **`EditLabelsBrowserWindow.tsx`** | Choose which labels a chat belongs to [O] |
| Edit spaces | **`EditSidebarBrowserWindow.tsx`** | Reorder, hide and configure space-bar entries [O] |
| Merge chats | **`CreateMergedChatBrowserWindow.tsx`** | Build a merged (cross-network) chat [O] |
| Edit group | **`EditGroupBrowserWindow.tsx`** | Group name, photo, description, or a local-only rename ("Edit Chat for Me") [O] |
| Chat Info | **`ThreadInfoBrowserWindow.tsx`** | Chat info popped out; window title "%s — Chat Info" [O] |
| Thread replies | **`ThreadedRepliesBrowserWindow.tsx`** | Reply thread popped out; title "Thread in %s" [O] |
| Poll creator | **`PollCreatorBrowserWindow.tsx`** | Compose a poll [O] |
| Media viewer | **`MediaViewerBrowserWindow.tsx`** | Gallery of all media, links and files in a chat [O] |
| Picture-in-Picture | **`PictureInPictureBrowserWindow.tsx`** | Floating video player [O] |
| Help hub | **`HelpHubBrowserWindow.tsx`** | Built-in help centre; error state "Failed to load help. Please try again." [O] |
| Debug app | DebugApp chunk (see Debug tools) | Internal data explorers [O] |

---

## 1. App shell, global states and system banners

**Purpose.** The top-level frame. It loads the right panes, shows app-wide status, and
catches crashes.

**Components.** **`App.tsx`** (MainApp) [O]; **`RightPane.tsx`** (RightPanePrefsView: the
conversation area plus the right-pane slot, which also hosts settings when they are shown inline)
[O/I]; **`ErrorBoundary.tsx`** and **`ErrorRenderer.tsx`** (crash screen) [O];
**`lazy.tsx`** (LazyFallback, plus a lazy-loaded Popover wrapper) [O]; **`Toasts.tsx`**
(ToastsButton) [O]; **`AppStatus.tsx`** (connection status row per network) [O];
**`StatusPill.tsx`** (ConnectingStatusText) [O]; **`VisibilityMonitor.tsx`** (watches whether
the window is visible or fullscreen) [I]; **`SplashScreen.tsx`** (see Onboarding).

**What the user sees and does.**
- **Lock screen** [O]: "%s is Locked" with an "Unlock" button that asks for Touch ID. A setting
  turns this on: "Require Touch ID authentication on launch". "Lock App" is also in the app menu.
- **Crash screen** [O]: "Looks like an error occurred", buttons "Reload app" and "Error Info",
  and a request: "If you have more details, let us know so we can fix it faster."
- **Lazy-load failure** [O]: "Unable to load %s right now." This appears when a lazily loaded
  part of the app (picker, pane) fails to load.
- **Connection status** [O]: "Connecting...", "Connecting... (%s)", "Connecting... (%1$s & %2$s)",
  "Offline", "Syncing...". A per-network status row shows "Disconnected" with a nudge,
  "You haven't used %s in a while, let's get you onboarded", and "Dismiss".
- **System health banners** [O]: "%s may be consuming an unusual amount of memory" (Relaunch),
  "Low free disk space. %s will not work well until you make some space.",
  "A background process crashed. Relaunch app", "Connection with main process is unresponsive. Relaunch app".
- **Update states** [O]: "Update Available", "Relaunch app to update", "A new version of %s has
  been downloaded", "A newer %s version is available", "Build Expired",
  "The app version you're using has become outdated and you must update to continue."
  Also "You’re on the latest version - %s" and "Checking for updates...".
- **Recovery-key reminder pill** [O] ("If you lose your device...", "Save key now",
  "Save key in Passwords", "Save key manually") sits in the same status area. [I]
- **Toasts** [O] are short messages with optional buttons, for example "Undo",
  "Archived %d chat", "Copied to clipboard!" and "Sidebar updated". [I] They are scoped to one
  window, because each detached window renders its own toast host.
- **App menu** (menubar chunk) [O]: "About %s", "Check for Updates…", "Preferences", "Accounts…",
  "Command Bar…", "Search...", "New Chat", "Open Chat in New Window", "Show/Hide Sidebar",
  "Show/Hide Space Bar", "Lock App", "Keyboard Shortcuts", "Changelog", "Privacy && Security",
  "Follow %s on X", "Open %s Help", "Report a Problem", "Logout of %s...", "Close Window", "Quit %s".

### Relaunch prompt after a system timezone change (added from the UI-text check)

**What it does.** The app remembers the system timezone offset. When the system timezone changes,
it shows a toast that stays until you act on it. The toast says the app must be relaunched to use
the new timezone, and has a "Relaunch now" button. The toast shows again after each new change. [O]

**Evidence:** "%s must be relaunched to use your new timezone"

---

## 2. Space bar, spaces, labels and account filters

**Purpose.** A narrow vertical rail at the far left. Each entry is a "space" that filters the
chat list. [O] It can be hidden ("Hide Space Bar" / "Show Space Bar"; setting "Show sidebar").

**Built-in spaces** [O]: "Inbox", "Reminders", "Requests", "Low Priority", "Send Later",
"Archive". Each connected account is also a space, and so is each user label.
"Show WhatsApp Communities as separate spaces" and "Show Telegram Topics as separate spaces" add
more. An all-accounts icon (AllAccountsIcon in **`icons.tsx`**) represents the combined inbox. [O]
Counts appear next to entries: "%d Chat", "%d Reminder", "%d Request", "%d Low Priority Chat",
"%d Message". [O]

**Components.** **`EditSidebar.tsx`** (getSpaceIcon, HiddenDivider) [O];
**`EditSidebarBrowserWindow.tsx`** [O]; **`Drag.tsx`** and **`Drop.tsx`** (drag-and-drop sorting
over a virtual list or grid) [O]; **`CreateLabelBrowserWindow.tsx`** (CreateLabel) [O];
**`CreateLabelNudgeIcon.tsx`** (nudge icon for creating a label; its neighbouring strings are the
space and label context menus) [O]; **`EditLabelsBrowserWindow.tsx`** (EditLabels) [O];
**`IconColorPicker.tsx`** (a hover-card grid you can move through with the arrow keys) [O];
**`CheckboxPlus.tsx`** (a checkbox row with a network icon, used in label and space menus) [I];
**`Badge.tsx`** (count or status badge; its neighbouring strings are the account-filter menu
"All accounts" / "Filter by account") [I].

**Edit Spaces window** [O]: title "Edit Spaces". It has a "Search Spaces" field, a "Pinned"
section, and a "Hidden" divider: dragging an entry below the divider hides it, and the empty state
is "No Hidden Spaces". Entries reorder by drag-and-drop ("Reorder sidebar"), and the result shows
the toast "Sidebar updated". [O/I]

**Space and account context menu** [O]: "Open in New Window" ("Open space in new window"),
"Mute Space" / "Unmute Space", "Show in Inbox" with the options "All Messages" / "None" /
"Only DMs", "Edit Spaces…", "Add/Remove Accounts…", "Account Settings…", "Enable" / "Disable",
"Connect" / "Reconnect" / "Retry", "Remove Account…" (confirm text: "Disconnect and remove the
data from this account on Beeper"). A "Developer" submenu has "Copy Bridge ID", "Copy Info as
JSON", "Restart Bridge", "Delete Bridge" and "Copy Account ID". Restarting the server asks for an
all-caps confirmation. [O]

**Labels** [O]:
- The create/edit window explains: "Choose a title, icon, and/or color to customize your label.
  This is how it will appear throughout the app." Fields: "Title" and "Label color and icon"
  (pick a colour swatch "Color %d" and an icon "Icon %d").
- Empty prompt: "Add chats to a label to organize them and set rules".
- Label menu: "Mute Label" / "Unmute Label", "Edit Label…", "Delete Label". The delete confirm
  says "This will remove the label from all chats."
- Chat rows show "Muted by Label %s" or "Muted by %d Label" when a label mutes them. [O]
- Free plan has a limit. "Unlimited Labels" is listed as a paid perk. [O]
- **Auto-archive rules** on a label or space [O]: "Auto-archive chats based on a rule",
  "Archive __TYPE__ chats older than __DURATION__". When chats already match:
  "%d chat in your inbox already matches this auto-archive rule." with the button "Archive %d chat".

**Label and space icon library.** About 150 icon components named after Material Symbols, each
mapped to an SF Symbol name and a stable icon ID. [O] [I] They are the icon set the label/space
icon picker offers. See §22 for the full list.

**Notable UX.** Drag-and-drop reorder; hidden-divider pattern; spaces can pop out into their own
window; filter-by-account menu; the bar collapses entirely. [O/I]

---

## 3. Chat list (inbox)

**Purpose.** The scrolling list of chats for the selected space and filter.

**Components.** **`ThreadsList.tsx`** (LoadingThread, getLastParticipantName) [O];
**`PinnedThreadListItem.tsx`** (pinned chats, a compact avatar-only row unless "Use regular style
for pinned chats" is on) [O]; **`ThreadListReadIcon.tsx`** (read state, delivery tick, hover
action) [O]; **`ThreadPreviewMedia.tsx`** (thumbnail in the row) [O]; **`ThreadPreviewTag.tsx`**
and **`message-preview.tsx`** (the last-message preview line with type badges) [O];
**`ThreadAvatar.tsx`**, **`GroupAvatar.tsx`** (BubbleAvatar), **`DefaultAvatar.tsx`**,
**`UnknownAvatar.tsx`**, **`DraftChatAvatar.tsx`**, **`StackedAvatars.tsx`** (overlapping avatars
for merged chats) [O]; **`UnreadMentionIndicator.tsx`** (an "@" marker) [O];
**`TypingIndicator.tsx`**, **`BrandTypingIndicator.tsx`** (animated dots) [O];
**`ContactItem.tsx`** (contact row; its neighbouring strings are all the list empty states) [O];
**`BrandEmptyStateMessage.tsx`** [O]; **`SelectionModeActions.tsx`** and
**`SelectionModeHeader.tsx`** (multi-select) [O]; **`Skeleton.tsx`** (loading rows) [O].

**Row content** [O]: avatar, network icon ("Show network icons", "Colorize network icons"), name,
time, preview ("Show message previews"), unread count ("Show number of unread messages"),
"Draft:" prefix, and an expired-reminder badge ("Reminder"). Preview badges include "Image",
"Video", "GIF", "Sticker", "Voice Note" (or the transcription in quotes), "Audio File",
"Contact", "Poll", "Media", "CSV", "ZIP", "Document", "Encrypted", and call types. A compact
density option exists ("Compact chat list"). [O]

**Message requests and invitations** [O]: rows "Message Request", "Group Invitation",
"Invited by %s". Inline actions: "Accept message request" / "Decline message request" and
"Accept group invitation" / "Decline group invitation". Accept confirm:
"Accept message request from __INVITER__?".

**Filter and sort** [O]:
- "Filter Chats" options: "All", "Unread", "DMs", "Group", "Drafts", "Unanswered", "No reply",
  "From unknown numbers", "Muted", "Hidden", "Archived", "Low Priority", "Requests", "Reminders",
  "Send Later". There is "Clear all filters", and the label shows " (%d filter)". "Cycle Filters"
  is a hotkey.
- "Display Options" sort: "Order by Newest Message", "Order by Oldest Message",
  "Order by Least Time Remaining", "Order by Most Time Remaining". The last two are for reminders
  and send-later. [I]

**Row actions** [O]:
- Hover action button: "Chat action button (on hover) should" be either "Archive" or
  "Mark Read/Unread".
- Double-click: "Archive", "Mark Read/Unread" or "Mute/Unmute".
- Right-click menu: Pin/Unpin, Mute/Unmute, Archive/Unarchive, Mark as Read/Unread,
  Move to Inbox / Move to Low Priority, Hide/Unhide, "Remind Me", "Label" submenu, "Copy" submenu
  (including "Chat Link"), "Edit Group...", "Unmerge", "Report as Spam…", "Delete…",
  "Open in New Window".
- Rules: "Pinned chats can't be archived". Deleting offers "Delete for Me" or
  "Delete for Everyone" ("Choose to delete permanently for yourself only, or for all
  participants."). A platform that can't do an action shows "Deleting chats on %s is not
  supported", and similarly for moving and reporting.

**Multi-select** [O]: "Toggle Chat Selection Mode" or "Select Chats" puts a checkbox on each row.
The header shows "%d chat selected" and a cancel button. The action bar has "Mark as Read",
"Mark as Unread", "Move to Inbox", "Move to Low Priority", "Remind Me" (with "Custom…"),
"Dismiss Reminder", "Archive", "Unarchive" and "More Options". Bulk menu: "Mark All as Read",
"Mark All as Unread".

**Empty states** [O], each with a title and an explanation line:
- "You've hit inbox zero!" / "You’re all caught up"
- "No unread chats…"
- "No drafts…" — "Chats appear here when you start a message but don’t send it"
- "Everything’s been answered"
- "No DMs…", "No group chats…" (with links "Add more accounts" / "create one")
- "Nothing archived…" — "Archive chats to clear them from your inbox without losing them"
- "No requests…" — "Messages from people you haven’t chatted with before appear here"
- "Nothing in Low Priority…", "No muted chats…", "No chats awaiting reply…", "No unknown chats…",
  "No hidden chats…"
- "You don't have any Reminders set" — "Set one up by right-clicking a chat in the inbox and
  selecting Remind Me"
- "You don't have any Send Later messages"

Light humour appears in some of them: "No mysterious strangers in your inbox",
"Not even a spam bot. Brutal.", "Looks like nobody’s after you… today". [O]
An illustrated background appears behind empty lists (see §4). [O]

**Loading state** [O]: skeleton rows (LoadingThread).

**Notable UX** [O/I]: merged chats show stacked avatars; hover reveals one action; incognito
mode keeps chats unread ("Unread until you reply"); "Mark unread chats as read on archive" and
"After archive" / "After mark as read/unread" settings decide where focus goes next.

---

## 4. Home, empty state and "Honeycomb" featured cards

**Purpose.** What fills the conversation area when no chat is open: a decorative background plus
rotating "featured" cards built from your chats.

**Components.** **`FeaturedHoneycombCard.tsx`** [O]. Its sub-components are RecommendationCard,
EventCard, EventIcon, StatsCard, UnreadMediaPreview, SenderHeader, a compact composer
(HoneycombComposer), and status pills: StaticDraftPill, StaticReplyPill, StillSendingPill,
FailedToSendComposerPill, LocalThreadComposerPill. Also **`BrandExpandableSection.tsx`**
(segment control plus expandable sections, carrying the "Honeycomb options") [O];
**`EmptyStateBackground.tsx`** (GradientVariant, SkyVariant) [O];
**`EmptyStateBackgroundThumbnail.tsx`** (thumbnails for picking a background) [O];
**`UnreadThreadCard.tsx`** (announcement card "AI is now available on Beeper." with a
"New AI Chat" button) [O].

**Behaviour.**
- **Recommendation cards** [O]: an AI-extracted fact from a message, typed "Actor", "Album",
  "Article", "Artist", "Book", "Director", "Film", "Music", "Musician", "Repository",
  "Restaurant", "TV Show", "Post", "Song" or "Writer". [I] The card shows the source message.
- **Event cards** [O]: "Birthday", "Anniversary", "Deadline", "Event" or "Meeting", with
  "Add to Calendar". The success toast is "Added to calendar".
- **Stats card** [O]: "Message distribution", "@%s sends the most messages.",
  "*based on 30 days of messages". Time buckets: "Today", "Week", "Month", "Year", "All time".
- **Inline reply** [O]: "What do you want to do…" prompt, "Message on %s". States: "Sending…",
  "Still sending…", "Message failed to send" (Retry / Remove), "Draft", "Not sent".
- **Options** [O]: "Show Featured Chats", "Auto-Rotate", "Enable AI" ("When Enable AI is on,
  received messages are processed using remote AI servers."). Privacy note: "received message
  content may be processed in the background to find explicit facts like recommendations and
  reminders."
- **Background** [O]: setting "Empty chat list background". Image assets named sky, sea, desert,
  meadow, mountains, sunset, lavender, default. [I] These are the selectable backgrounds.

### Honeycomb chat cards for mentions, unread and quiet chats (added from the UI-text check)

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
The quiet card is a "get back in touch"
nudge, and it needs a rule for how long counts as quiet. [I] We did not find that rule.

**Evidence:** "%d unread mention", "Quiet", "It's been %s since you talked"

---

## 5. Conversation view: header, timeline and message rendering

**Purpose.** Shows one chat's messages. Mostly bubbles, with system notes inline.

**Header** [O/I]: avatar and name; network icon; reminder pill ("Set to remind at %s",
"Set to remind at %s if no reply", "Reminder: %s"); disappearing-message note
("Messages disappear after %s"); buttons for Chat Info, AI and calendar; "Open Chat List" when
the list is collapsed. **`BrandVideo.tsx`** sits next to the header buttons. [I] It is a small
inline video element used by header and empty-state art.

**Timeline components** [O]: **`MessageList.tsx`** (MessageListUnwrapped, a virtual list),
**`SubComponents.tsx`** (MessageDate separators, ThreadRepliesDivider, loading indicator),
**`ScrollToBottom.tsx`** ("New Message" jump button with a count), **`JumpToMessage.tsx`**,
**`MessageContent.tsx`** (HiddenMessage), **`MessageText.tsx`** (formatted text, detected data,
balanced line breaks), **`MessageMention.tsx`** (mention chip with user hover card),
**`linkify.tsx`**, **`Spoiler.tsx`**, **`Code.tsx`**, **`MessageIFrame.tsx`** (embedded content
in a sandboxed frame), **`MessageEditHistory.tsx`**, **`MessageErrorTooltip.tsx`**,
**`MessageReactions.tsx`** (ReactionSourceThumbnail), **`MessageReactButtons.tsx`**,
**`message-info.tsx`** (MessageInfoLine), **`MessageTranslationRow.tsx`**,
**`MessageTranslations.tsx`**, **`MembershipGrouper.tsx`**, **`DisappearedMessagesGrouper.tsx`**,
**`GalleryGrouper.tsx`**, **`TimelineNote.tsx`**, **`ScheduledMessages.tsx`**,
**`ScheduledMessageDate.tsx`**, **`ToggleScheduledMessages.tsx`**, **`BrandReplyLineSegment.tsx`**
(the quoted-reply line above a bubble), **`entry-preview.tsx`** (EntryTimestamp and reply
previews like "%d new replies"), **`BrandUserHoverCard.tsx`**, **`HoverCard.tsx`**,
**`HoverCard.context.tsx`**, **`PhoneNumber.tsx`**, **`Email.tsx`** (EmailAddress),
**`icons-toolbar.tsx`** (pending, sent, read and error ticks; unmute icon).

**Behaviour and states.**
- **Message status line** [O]: "Queued", "Sending...", "Still sending...", "Sent", "Delivered",
  "Seen", "Seen %s", "%1$s seen %2$s", "Seen by %1$s & %2$d other", "Edited",
  "Edited after %s", "Forwarded". With "Avatar read receipts" on, small avatars mark read
  positions. Timestamps can always show ("Show message timestamps").
- **Failed send** [O]: "Not sent" tooltip with the reason, and actions "Retry", "Remove",
  "Delete". "Sending message to %1$s (%2$s) is taking longer than expected".
- **Undo send** [O]: pending messages can be clicked to undo ("Click pending messages to undo
  send"; "Allow undo send (%s) for"). The toast reads "sent message undone".
- **Hidden and unknown events** [O]: "Hidden event", "Unknown Type",
  "This message was unrecognized and could not be displayed.",
  "This message is waiting for decryption.", "This message has been deleted". The setting
  "Hide deleted messages" replaces the placeholder. Hidden events show with the note
  "Shown because you enabled Settings > General > Show hidden events in timeline".
- **Grouping** [O]: runs of join/leave events collapse ("%d Membership Event", Expand/Collapse;
  setting "Show membership events"). Disappeared messages collapse ("%d message disappeared").
  Consecutive images become a gallery grid. Disappearing-timer changes show as notes
  ("%1$s set new messages to disappear after %2$s." with a "Change Setting" button).
- **Scheduled messages** [O]: a "%d Message to Send Later" toggle at the bottom of the timeline
  shows queued messages as notes. Each has a date ("MMM dd, yyyy, h:mm aa" style), "Send %s",
  "Edit scheduled message", "Reschedule", "Send Message Now", "Delete Without Sending" and
  "Options". A canceled one reads "Send Later message canceled by reply."
- **Translations** [O]: translated text shows under the original ("Show more" / "Show less",
  "Remove %s").
- **Voice transcription** [O]: "Transcribe", "Transcribing…", "Transcribing in %s…",
  "Error transcribing audio", "Try Transcribe", "%d free transcription left".
- **Read more** [O]: long messages truncate with "Show more" / "Show less".
- **Mute notice** [O]: "%s has notifications silenced" with "Notify Anyway".
- **Invitation banner** [O]: "__INVITER__ invited you on __PLATFORM__", with "View Profile".
- **Detected data** [O]: phone numbers, emails and flights become actionable ("Track Flight";
  "Call", "Copy", "FaceTime" / "FaceTime Audio"; "Could not load. Click to try again").
- **Embeds** [O]: "🔒 Load Embed" (click to load), unless "Load external embeds automatically" is on.
- **Link previews** [O]: link cards. Tweets render specially ("Tweet by %s", "Open X Post",
  "Open Tweet", "Open @%s Profile").
- **Unread divider** [O]: "New".
- **Nudges** [O]: the conversation shakes ("Shake the conversation when someone sends you a
  nudge"), and the app offers "You got nudged! Want to disable nudges?".
- **Animations** [O]: "Enable message animations" (send/receive effects), "Confetti".
- **Sounds** [O]: send, receive and push sounds plus six reaction sounds (like, dislike,
  emphasize, haha, heart, question), shipped as wav assets. [I] These follow iMessage-style tapbacks.

**User hover card** [O]: hovering a sender or mention shows a card with avatar, "Open in Mesh",
"Call %s", "FaceTime" and "FaceTime Audio".

### Per-message disappearing countdown and read-started timers (added from the UI-text check)

**What it does.** A disappearing message carries its own timer. The timer can be one of two kinds:
it starts when the message is sent, or it starts when the message is read. [O]

- **Before the timer starts** (read-started timers only), the message says when it will disappear:
  [O]
  - Your own message in a one-to-one chat: so long after the recipient reads it.
  - Your own message in a group: so long after someone in the group reads it.
  - A message you received: so long after you mark it read.
- **Once the timer is running**, the message shows a countdown ("Disappears in <time>"). [O]


**Evidence:** "Disappears %s after the recipient reads it", "Disappears %s after someone in the
group reads it", "Disappears %s after you mark it read", "Disappears in %s"

### Inline edit-history expander on edited messages (added from the UI-text check)

**What it does.** On an edited message, the "Edited" label can be a button. [O]

- **Opening it.** Clicking it opens the message's earlier versions right below the message. The
  button then reads "Hide Edits".
- **The tooltip.** It shows the original text ("Originally …").
- **When it is plain text.** When there is no history to show, "Edited" is plain text.
- **Thread replies.** A reply in a thread that was also posted to the main chat is marked as sent
  to the chat as well.


**Evidence:** "Edit history", "Hide Edits", "Originally %s"

---

## 6. Composer

In a merged chat, the composer also has a target switcher; see §9a "Merged-chat target switcher in the composer".

**Purpose.** The text box at the bottom of a chat, with formatting, attachments and extras.

**Components.** **`ComposeMessage.tsx`** (ThreadComposerDisabled, getSuspenseFallback) [O];
**`TextAreaAutocomplete.tsx`** (rich-text editor with an account avatar for "send as";
placeholder "Type something...") [O]; **`Autocomplete.tsx`** (popover for emoji and mentions:
"Add Emoji") [O]; **`createMentionTriggerSettings.tsx`** (the "@" picker, which also lists AI
models as mentionable) [O]; **`createSlashCommandTriggerSettings.tsx`** (the "/" commands:
"GIF", "Voice memo", "Nudge", plus "/a" AI reply suggestions) [O]; **`Bubble.tsx`** (BubbleMenu,
the selection formatting toolbar) [O]; **`LinkDialog.tsx`** (Text and URL fields, Save/Cancel,
Enter/Escape) [O]; **`TooltipButton.tsx`** [O]; **`PendingAttachments.tsx`** and
**`FileAttachment.tsx`** (attachment chips before sending) [O]; **`FileDropOverlay.tsx`**
("Drop files here to attach" / "Drop files here to send", "Hold Shift to send immediately") [O];
**`BrandSendButton.tsx`** [O]; **`BrandStopButton.tsx`** (stop recording or stop AI generation)
[I]; **`Emoji.tsx`** (the composer plus-menu items) [O]; **`EmojiItem.tsx`** [O];
**`StickerPicker.tsx`** [O]; **`GifPicker.tsx`** (carousel; "Search KLIPY...") [O];
**`FreebieNudge.tsx`** (free-trial nudges for send-later and incognito) [O];
**`PollCreator.tsx`** [O]; **`QuickReplyItem.tsx`** [O]; **`icons-compose.tsx`** [O].

**Elements and actions.**
- **Plus menu** [O]: "Add Attachment", "Add GIF", "Add Sticker", "Record Audio",
  "Talk to Type", "Send Later", "Create Poll", "Send a nudge". Items a network can't do are
  greyed with "%1$s (Unavailable for %2$s)" or upsold with "%s (Upgrade to Beeper Plus)".
- **Primary and secondary composer buttons** [O] are configurable ("Primary composer button",
  "Secondary composer button"; option "None").
- **Formatting** [O]: Bold, Italic, Strikethrough, Inline Code, Code Block, Blockquote,
  Bullet List, Numbered List, Add/Remove Link. Each has a hotkey. The floating menu can be
  turned off ("Show formatting menu").
- **Reply / quote / edit** [O]: a quoted message sits above the input ("Clear quoted message").
  Editing shows "Edit Message". The up arrow is configurable ("Press ↑ in the composer to:",
  e.g. "Edit your last message").
- **Link preview** [O]: an outgoing preview card with "Remove Preview". It can be turned off
  globally ("Disable link previews in outgoing messages").
- **Send options** [O]: a send-options button gives "Send Later" (date picker with typed natural
  language: "When? (try typing something like %s)"), "Message: Send Message and Archive", and
  "Hit %s to send instantly."
- **Voice** [O]: "Record a voice message". "Talk to Type" is speech-to-text, with the hint
  "Talk then press space" and "Cancel Talk to Type". Microphone choice: "Select a microphone",
  "Microphone permission required".
- **Quick replies** [O]: canned replies triggered by a key in the input. They support variables
  and an attachment.
- **Emoji** [O]: autocomplete (":" style), "Disable automatic replacement of emoticons with
  emojis", "Add :%s: to Custom Emoji".
- **Attachment limits** [O]: "Could not attach %s — total size would exceed 90MB.",
  "%s doesn't support sending files", "%1$s only supports sending %2$s files".
- **Disabled composer** [O] (ThreadComposerDisabled): "You don't have permissions to send a
  message", "Chat was upgraded." with "Click here to follow the conversation", and
  "Chat limit reached." with "Update your subscription".
- **Upsell nudges** [O]: "It's late… want to send this later?" / "Try Send Later" /
  "%d free Send Later message left"; "Want to read without being seen?" / "Try Incognito Mode" /
  "Your incognito trial is over" / "Upgrade to Plus to keep it".
- **Spellcheck** [O]: "Enable spellcheck".
- **Draft with AI** [O]: "Draft response with AI", "Edit draft response with AI",
  "Translate draft response with AI", and an AI rewrite menu (see §13).

**Polls** [O]: the creator window ("New Poll") has "Question" ("Ask a question…"), "Options"
("Add an option", "Remove option", "You can enter %d more option", "This option already exists",
"You have added the maximum number of options"), and toggles "Allow multiple answers" and
"Hide results until end of poll". Closing with content asks "Discard poll?" ("Your poll draft
will be deleted."). The rendered poll (Poll chunk) shows "%d vote", "Select one option" /
"Select one or more options", "Poll ended", "Results will be displayed when the poll ends" and
accessible vote labels.

---

## 7. Message actions, context menus and popovers

**Components.** **`PopupMenu.tsx`** (menus with submenus and a safe hover area) [O];
**`BrandPopover.tsx`** [O]; **`SelectMessageCommand.tsx`** (ClampingHighlighter; command-bar
entries for a selected message) [O]; keyboard handlers in their own chunk ("Only works when
messages are selected") [O].

**Message context menu** [O]: "Reply…", "Reply in thread…", "Reply Privately…", "React…",
"Edit…", "Forward…", "Copy", "Copy Entire Message", "Copy with Timestamp", "Copy Image",
"Copy Link", "Copy %s" (email), "Bookmark" / "Remove Bookmark", "Mark as Unread", "Translate",
"Share…", "Quick Look", "Load Media" / "Try Loading Media Again", "Unsend", "Delete for Me…" /
"Delete for Everyone…". Unsupported cases say "Delete message is not supported for %s yet".

**Reactions** [O]: quick-reaction strip on hover ("Show quick reactions", "Quick reaction emoji",
"Use my most frequent emoji"), "Type any emoji to react with it", "Remove %s reaction",
"Show reactions when a message is selected" ("Display who reacted to a message when you select
it"), and an emoji picker that can open on hover.

**Double-click on a message** [O]: "Reply" or "Forward" (setting "On double-clicking a message").

**Multi-message selection** [O]: "Multi Select Next/Previous Message". The selection actions are
"Quote reply %d message", "Forward", "Copy with timestamps", "Download attachments",
"Summarize selected messages with AI", "Translate selected messages to %s with AI" and "Unselect".

**Forward** [O]: "Forward message" picks a destination. Note shown: "Forwarding messages through
Beeper will not include any attribution on the native apps."

### Insert as Draft on received messages (added from the UI-text check)

**What it does.** Selected messages that someone else sent have an extra menu item, "Insert as
Draft", next to Copy. It puts the message's text into your composer and moves the cursor there, so
you can edit it and send it as your own. Your own messages don't have this item. [O]

**Evidence:** "Insert as Draft"

---

## 8. Media, attachments and viewers

**Components.** **`AttachmentCarousel.tsx`** (ZoomComponent; "Previous/Next Attachment",
"Fullscreen", "Rotate", "React", "Reply", "Download", "Copy", "Close") [O];
**`PDFAttachment.tsx`** and **`PDF.tsx`** (paged PDF view: "Previous Page" / "Next Page";
"Unable to load PDF. Download the file to view.") [O]; **`Audio.tsx`** (voice note waveform) [O];
**`GlobalAudioPlayer.tsx`** (a draggable mini player that keeps playing across chats: playback
speed, "Open %s", "Close audio player") [O]; **`TranscodedAttachment.tsx`** (converted audio and
images) [O]; **`LoadingAttachment.tsx`** [O]; **`FilePlaceholder.tsx`** (Audio/PDF/Text/Document
types) [O]; **`FileRowSpinner.tsx`** ("Load Attachment", "Not loaded") [O];
**`EnhancedImg.tsx`** [O]; **`ImageError.tsx`** ("Image failed to load") [O];
**`MediaWithSender.tsx`** (media tile with sender caption; its neighbouring strings are the
participant menu, see §9) [O]; **`GalleryVideoPoster.tsx`** [O];
**`MediaViewerBrowserWindow.tsx`** [O]; **`ViewLimitedMediaViewer.tsx`** (view-once media) [O];
**`Location.tsx`** (map with a pin; "Open in Apple Maps", "Open in Google Maps",
"Copy Location") [O]; **`index.tsx`** (one of several files with this name: the Video player
plus a TIFF image renderer) [O]; **`PictureInPictureBrowserWindow.tsx`** [O].

**Inline video player** [O]: play/pause, rewind / fast forward, "Playback Speed" ("Normal" and
others), "Fullscreen" / "Exit Fullscreen", "Open in PiP", mute, "Download". Error:
"Something went wrong displaying video". PiP has "Restore from Picture in Picture".

**Media viewer window** [O]: tabs "Media", "Links", "Docs" (the live app labels this tab "Docs", not "Files") (also "Images", "Videos", "Audio"),
grouped by "Today", "Yesterday", "This week", "Last week". Items can be multi-selected
("%d selected", "%1$d selected (%2$s)", "Select all"). Actions: "Go to Message", "Download",
"Copy Image", "Copy Link", "Delete…" (with "These messages can’t be deleted" and "Skipped %d
item that can’t be deleted"). Gallery menu: "Download All", "Forward All…", "Reactions".
Empty state: "Nothing here". Zoom: "You can use %1$s to zoom in and %2$s to zoom out.". [O]

**View-once media** [O]: pills "View photo", "View video", "View Snap", "Play voice note".
Opening it shows a full-screen overlay with a countdown/progress bar and mute. Error:
"Could not play this media.".

**Downloads** [O]: "Downloads location" ("Change"), "Always ask where to save files before
downloading", "%1$s %2$s has been downloaded", "Download failed: %s".

### Media viewer sender filter and sort order (added from the UI-text check)

**What it does.** The media viewer has a filter menu with two settings: [O]

- **"Sent By"**: All, You or Others.
- **"Sort by"**: Newest or Oldest.

Caption search waits a moment after you stop typing before it runs. The live tabs are labelled
Media, Links and **Docs** (not "Files"). [O]

**Evidence:** "Sent By", "Sort by"

### Voice-note played state and Mark as played (added from the UI-text check)

**What it does.** Audio attachments can carry a played or unplayed status that comes from the
network. [O]

- A played note is labelled "Played", or shows when it was played.
- An unplayed note has a "Mark as played" button. The button tells the network that the note was
  played, without playing it.

[I] This matches networks that show "played" receipts for voice notes, such as WhatsApp.

**Evidence:** "Played", "Played %s", "Played at %s", "Mark as played"

---

## 9. Chat Info pane and group management

**Purpose.** A right-pane panel (or detached window) with chat details, members, shared media
and settings.

**Components.** **`ThreadInfo.tsx`** (AuthorizeContactsPrompt) [O];
**`ThreadInfoBrowserWindow.tsx`** [O]; **`ThreadDescription.tsx`** (DescriptionHeader, contact
detail rows, merged-chat section) [O]; **`GroupParticipantItem.tsx`** (AddToContactsButton) [O];
**`AddContactForm.tsx`** (AddContactFormInner) [O]; **`BrandChatInfoPaneBookmarks.tsx`** [O];
**`EditGroupModal.tsx`** and **`EditGroupBrowserWindow.tsx`** [O]; **`CopyableField.tsx`** [O];
**`ProfileField.tsx`** [O].

**Content** [O]:
- Header with avatar, name and "Edit".
- Group description ("Add a description", "This description is public to the group").
- Contact details (for DMs): Phone, Email, Username, Location, Website, each copyable; plus
  "Open in Contacts", "Add to Contacts", "Edit Contact", "Open in Mesh".
- "Message Other Accounts" (the same person on other networks).
- "Labels" with "Add to a Label".
- Disappearing messages ("Select timer"; "For added privacy, new messages disappear after the
  set time.").
- "Bookmarks" with tabs Media / Images / Videos / Audio / Links / Files, "Jump to Message",
  "Remove Bookmark", and the empty state "Bookmarked messages will appear here.".
- Members list: "Group · %d Member", "Search %d group member".
- A prompt to authorize macOS Contacts ("Authorize Contacts to easily edit your contacts and add
  unsaved numbers").

**Member row menu** [O]: "Send Message", "Copy Phone Number", "Copy Email", "Copy Username",
"Copy Name", "Add to Contacts", "FaceTime", "Make Group Admin…" (with a confirm), "Remove from
Group…" (with a confirm). Status tags: "Admin", "Invited", "Exited", "(You)".

**Add to contacts** [O]: "Create New Contact" (First name, Last name) or "Add to Existing Contact".

**Edit group** [O]: drop or upload a photo ("Drop image here to upload", "Remove Photo"),
"Group Title", "Group Description". Local-only mode ("Edit Chat for Me", "Chat Name") notes
"This name and photo are only visible to you, on all your devices.". Errors include
"Failed to update group".

**Group commands** [O]: "Add members", "Leave chat" ("Are you sure you want to leave %s?"),
"Change message expiry timer", "Refresh chat", "Export all loaded messages to .txt file".

### 9a. Merged chats (one conversation across networks)

**Components.** **`MergedChatEditor.tsx`** (renderPickRow) [O];
**`CreateMergedChatBrowserWindow.tsx`** [O]; **`MergeSuggestionNetworkIcons.tsx`** [O];
**`StackedAvatars.tsx`** (also used in §3) [O].

**Behaviour** [O]:
- Pitch: "View chats with the same contacts, across different accounts, as one conversation.".
- Suggestions inside a chat: "View all your chats with %s as one conversation", with network
  icons, "Merge Chats" and "Dismiss". Merge options also appear as "%d chat on".
- The editor picks member chats ("Search contact") and a photo ("Upload photo",
  "Use initials", "Use %s's photo").
- The free plan merges a limited number ("Merge %d chat for free", "You’ve reached your merged
  chat limit").
- Manage menu: "Edit", "Unmerge" ("This will split this merged chat back into individual
  chats."), "Apply merged info to contacts".
- Afterwards: "You can now message %1$s across %2$d chats from one conversation.".

#### Merged-chat target switcher in the composer (added from the UI-text check)

**What it does.** In a merged chat (one conversation made of chats from several networks), the
composer shows an avatar for the chat that your message will go to. [O]

- **Switching.** Hovering the avatar opens a card headed "Switch chats". The card lists each chat
  in the merge, with a subtitle, and you pick the one to send through. [O]
- **Other uses.** Outside merged chats, the same control appears with the heading "Switch Chat".
  [I] It may also pick the sending account.
- **One-time hint.** The first time it is relevant, a small bubble says "Click the avatar to change
  chat.". The app records that the hint was shown, and dismissing it hides it for good. [O]
- **Default chat.** The merged-chat section in Chat Info marks one of the chats as the default. [O]


**Evidence:** "Click the avatar to change chat.", "Switch chats", "Switch Chat"

### 9b. Chat theme

**Components.** **`ChatThemeWindow.tsx`** and **`ChatThemeBrowserWindow.tsx`** [O].

**Behaviour** [O]: "Pick a wallpaper and bubble color". Options are "Wallpaper" ("No wallpaper",
"Choose photo" / "Photo…"), "Bubble color" ("Default bubble color"), "Use app default",
"Reset theme", "Only you see your chat theme". There are about 26 named colours, among them
Mist Blue, Seafoam, Sage, Frost Teal, Lagoon, Skywash, Mint, Meadow, Moss, Sand, Oat, Butter,
Linen, Petal, Pearl, Orchid, Bloom, Haze, Violet Night, Apricot, Amber, Blue, Indigo, Purple and
Pink. A global default exists ("Default chat theme"), and so does
"Distinct bubble color for each participant in groups".

---

## 10. Threaded replies

**Components.** **`ThreadedRepliesPane.tsx`** (a resizable right pane, dragged with a handle;
"Open in New Window") [O]; **`ThreadedRepliesHeader.tsx`** [O];
**`ThreadedRepliesBrowserWindow.tsx`** [O].

**Behaviour** [O]: "Show threads in a sidebar: every reply on thread-only networks such as
Slack, and threads alongside replies in Matrix rooms.". Reply counts on messages show "%d Reply"
or "%d unread reply" with avatars of who replied ("%1$s & %2$d other"). Composer placeholder:
"Reply in thread…". There is a file drop area and a close button. "Mark %d thread as read".

---

## 11. Start new chat, groups, Blasts and Matrix rooms

**Components.** **`StartNewChatView.tsx`** (LeadingActionRow, NewGroupRow, NewAIChatRow,
JoinMatrixRoomRow, NewBlastRow) [O]; **`new-chat-utils.tsx`** (NetworkSkeleton) [O];
**`GroupTitleBar.tsx`** (group title input with an avatar picker) [O]; **`CommandBarUser.tsx`**
(person result row, also used for search) [O].

**Behaviour** [O]:
- Search box: "Search name, @, number, or network". Results grouped "Frequently Contacted",
  "Recent Chats", "Suggested", "In your contacts".
- Leading rows: "New Group", "New AI Chat", "Join a Matrix room", "New Blast".
- Pick a network for the new chat ("Message on %s"). The draft-chat placeholder is
  "Write a message to compose %s thread", or for groups "Write a title to create %s group".
  Status: "Creating group chat...". When a network needs an invite first: "%s requires you to
  send an invite to start a new chat." / "Send invite". When messaging isn't possible:
  "You can't message %s on %s".
- **Blasts** [O]: "Send the same message to multiple chats at once." Pick many chats; one
  attachment allowed ("A Blast can include one attachment"). Per-chat compatibility: "%d chat
  can't receive this file and will get the text only", "will be skipped", "Text only",
  "Skipped". Confirm "Send to %1$d of %2$d chat?". Results: "Blast sent", "Couldn't send to %d
  chat", "Retry". Sent messages are tagged "Sent as a Blast".
- **Join Matrix room** [O]: field "Room address or Matrix link", "Join", "Joining...". It
  validates addresses (for example a string with both "#" and "!") and notes that spaces can't
  be opened yet ("This is a Matrix space. Beeper does not show spaces yet…").
- Option: "Include Matrix results in Start New Chat".
- Empty state: "Whoever you’re looking for hasn’t messaged" and "Start typing to search for
  people to add".

### Room-encryption choice when starting a Matrix group (added from the UI-text check)

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

## 12. Search and Command Bar

**Purpose.** A keyboard-driven overlay. One box searches chats, people, messages and every app
command.

**Components.** **`index.tsx`** (the CommandBar family: CommandBarContainer, CommandBarItem,
CommandBarCommands, CommandBarTextInput, ModeSwitchBadge, HotkeyKeys) [O];
**`GeneralSearch.tsx`** (keyboard hint, filters, results) [O]; **`GeneralSearchResults.tsx`**
(renderCommand) [O]; **`SelectRecentSearchCommand.tsx`** (SelectThreadCommand) [O];
**`SelectMessageCommand.tsx`** [O]; **`CommandBarUser.tsx`** [O]; **`SearchIcon.tsx`**,
**`OutlineSearch.tsx`** [O].

**Modes** [O]: "Chat" or "Commands" ("command bar mode switch"). Placeholders: "Search chats",
"Search this chat", "Search commands". "Searching...", "No results".

**Message search** [O]:
- "Search messages in all chats" and "Search messages in current chat".
- Filters: "Accounts", "Message type", "Sent" / "Received", "Direct message" / "Group",
  "Time period" ("Last hour", "Last week", "Last 30 days", "The last year"), "Media".
- "Show partial matches" / "Hide partial matches"; "Recent searches".
- Limits: "Only messages loaded in Beeper can be searched." and "For more results, scroll through
  older conversations.".
- Hints: "Press %s to search all of your conversations", "Are you trying to search for people?".
- Empty: "No messages matching those terms".

**Command categories** [O]: Chat, Chats, Commands, Media, Message, Messages, Settings, UI, User,
View, Window, plus Developer for internal users. Representative commands:
- Theme switch ("Set theme to dark mode")
- Zoom in/out/reset; "Maximize/unmaximize"
- "Toggle sidebar", "Toggle space bar", "Edit spaces"
- "Media viewer", "Open space in new window"
- "Create new chat", "Create new group", "Join a Matrix room"
- "Archive all read chats", "Archive all chats older than a week", "Mark all chats as read"
- "Create quick reply from draft"
- "Show keyboard shortcuts", "View changelog", "Lock app", "Report a problem", "Email feedback"
- "Redact names and pictures" (privacy screenshot mode)
- "Open custom CSS file in editor", "Reload custom CSS"
- "Logout of your %s account"
- Per-chat commands (pin, mute, archive, hide, low priority, labels, report as spam, open in new
  window, summarize last N messages with AI, clear AI pane)
- Per-user commands (copy name/username/phone/email, call, FaceTime, open profile)
- "Message yourself", "Send later", "Remind me later"

### Search home and result sections (added from the UI-text check)

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

## 13. AI features (AI pane, AI chats, AI tools in context)

**Components.** **`AIPane.tsx`** (AIPaneMessage) [O]; **`AIMessageContent.tsx`**
(renderTextBlock) [O]; **`AIMessageParts.tsx`** (AIStreamingMessageText, AIThinkingChainStep,
AIFinalActivityStep) [O]; **`AIToolCallsPanel.tsx`** (ToolMetaRow, FetchToolDetails, tabs for
tool payloads, ReasoningChainStep) [O]; **`AIMessageFooterActions.tsx`** (AIContextWarningButton,
CopyAIMessageButton, AIFinishReasonBadge) [O]; **`AIModelButton.tsx`** (model picker) [O];
**`AISpinnerVerb.tsx`** (animated "thinking" verb) [O]; **`UnreadThreadCard.tsx`** [O];
**`default.tsx`** (ChatGPTDotsDefault avatar) [O]; GrokBotDefault in **`icons.tsx`** [O].

**AI pane (right pane)** [O/I]: a mini chat with an assistant about the current chat. It greets
by time of day and first name and asks "How can I help you?". Before any message it offers
suggested actions, some of which open command-bar submenus. Each running answer can be stopped
("Stopped generating"). "Clear the AI pane conversation" resets it.

**AI chats (full conversations with an AI "network")** [O]:
- "New AI Chat" / "Start a new AI chat — %s" ("with" model name). Intro: "Ask questions, search
  the web, and get answers with cited sources — all without leaving your chats." Disclaimer:
  "AI can make mistakes, always check important information.". Example prompt:
  "What's the latest news?".
- "Select AI model", "All models", "Recently used AI models".
- Messages stream in. Expandable reasoning steps and a tool-call panel show the fetch/tool
  details with payload tabs. Footer: copy, a finish-reason badge, a context-limit warning, and
  "Start a new AI Chat".
- [O] Providers are set up through a login flow: Beeper AI, ChatGPT (device code), OpenAI Chat
  Completions, OpenAI Responses, OpenAI Codex Responses. Fields: Display name, Base URL,
  API key, Default model.

**AI in regular chats** [O]:
- "Mention an AI to get answers and help in chat" ("Your preferred AI for mentions",
  "AI Mentions System Prompt", "Custom System Prompt").
- "/a" reply suggestions.
- "Draft response with AI" with rewrite options "Fix grammar/spelling", "Make more concise",
  "Make more confident", "Make more friendly", "Make more professional", "Make more verbose"
  (states "Drafting response...", "Editing draft response...").
- "Translate response to %s"; "Summarize link with AI"; "Summarize selected messages with AI";
  "Translate selected messages".
- "Draft response" pills show in Honeycomb.

**AI settings** [O]: "Engine for text-based AI features" (including Apple Intelligence: "Apple
Intelligence is only available on macOS running macOS 26 or later."), "Language for AI responses
and translations", "Translation Languages", "Enable contextual AI", "AI Voice Note Transcription"
/ "Use OpenAI's Whisper model…", "Automatically transcribe voice notes when they are received",
"Transcription Language". Privacy notes: "Privacy: this will send your last n messages in a
conversation to OpenAI via our servers." and "Privacy: this will send audio clips to OpenAI via
our servers.".

---

## 14. Calendar pane

**Component.** **`CalendarPane.tsx`** (renderTodayButton) [O].

**Behaviour** [O]: a right-pane single-day time grid in 30-minute slots, with an all-day row and
a "now" line. It reads events from the system calendar for the visible range (title, start, end,
all-day). Controls: "Today", "Previous day", "Next day" (with tooltips), "Close". It is set up as
selectable and editable. [I] Drag-to-create or drag-to-move may be wired up, but we have not
confirmed it.

---

## 15. Onboarding and Beeper account sign-in

**Purpose.** First run. It creates or signs in to the Beeper account, sets up encryption, and
teaches the shortcuts.

**Components and steps** [O]:
1. **`SplashScreen.tsx`**: animated collage of network logos (**`BrandCompositeIllustration.tsx`**
   with BeeperCompositeIllustration; **`Floating.tsx`** for the drifting animation). Buttons:
   "Continue with Email", "Continue with %s" (social sign-in), "Already use Beeper? Sign in".
   Legal line: "By continuing, you agree to our %1$s and have read our %2$s.".
2. **`AwaitCredentials.tsx`**: "Enter your Email", or a username/password path
   ("Login with password"). A server-environment select is available on internal builds.
3. **`AwaitEmailCode.tsx`**: "Enter Code", "Check %(email)s for your login code", a six-digit
   OTP input (**`Slot.tsx`** handles paste, arrow keys and backspace across digits), "Open Email",
   "Didn't get a code?" / "Resend", and "Use magic code".
4. **`AwaitLeadRegistration.tsx`** + **`UsernameInput.tsx`**: "Pick a Username" (live check:
   "Username is not available. Try something else.").
5. **`AwaitVerification.tsx`** + **`DevicesTooltip.tsx`** + **`BaseConnectModal.tsx`**: verify
   this device from another signed-in device. Choices: "QR Verification" ("Scan the QR code with
   your device to verify your session.") or "Emoji Verification" ("Confirm the emojis above match
   the ones on %(deviceName)s", "They match" / "They don't match"). Warning: "Proceeding will give
   the other device full access to your Beeper account". Fallback: "Use your Recovery Key".
   **`QRCode.tsx`** renders codes.
6. **`AwaitRecoveryCode.tsx`** + **`RecoveryCodeInput.tsx`**: "Enter your Recovery Key",
   "Paste from Clipboard"; error "The Recovery Key you entered doesn't match…".
7. **`RecoveryCodePreamble.tsx`** + **`ClippableRecoveryCode.tsx`**: "Save Your Recovery Key",
   "Save Key in Password Manager" / "Backup Manually", "Confirm your Recovery Key",
   "WARNING: Beeper does not store your Recovery Key for you…".
8. **Reset recovery key**, near **`ProgressCircle.tsx`**: "Lost your recovery key?",
   "Reset your Recovery Key", "Only use this option if you no longer have access to your other
   devices…".
9. Sync screens ("Welcome to Beeper!", "Setting up encryption…", "Restoring encryption keys…",
   "We're syncing your chats. This may take a while...", "Synced %(processed)d of %(total)d
   chat.") with **`AwaitInboxExperience.tsx`** and **`AwaitNetworkConnection.tsx`**, which are
   wait states between steps. [I]
10. **`DownloadMobileApps.tsx`** and **`TakeBeeperWithYou.tsx`**: "Take Beeper with you",
    "Get the app", a QR code, and "Send a link to %s" (sends the install link to yourself
    through a connected network).

The shared frame is **`OnboardingFrame.tsx`**, with a top-right menu: "Report a Problem",
"Logout", "Start Over". Lottie animations come from **`Lottie.tsx`**. [O]

**Hotkey tutorial (second onboarding)** [O]: **`Onboarding.tsx`** (HotkeysOnboarding with a
progress bar and "Skip" / "Continue →"; skip confirm "Are you sure you want to skip?"),
**`KeyboardFirstPage.tsx`** ("%(appName)s is keyboard-first"), **`CmdBarPage.tsx`**
(Command Bar hotkey), **`ThreadSearchPage.tsx`** (find a chat by name), and **`Key.tsx`**
(on-screen key caps that light up when pressed). Success: "Nice work!" and
"🤩 Check out that fancy fingerwork!".

### Step-up re-authentication by emailed code (added from the UI-text check)

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

## 16. Adding and managing chat-network accounts

What each network loses in cloud versus on-device mode is listed in 03 §1.4, "Per-network connection-mode limitations list". Plan caps on accounts are in §17, "Plan limits".

**Purpose.** Connect WhatsApp, Signal, Telegram, Instagram/Messenger, Discord, LinkedIn, X,
Google Messages, Google Voice, Viber, WeChat, iMessage, Bluesky, Slack, Matrix and AI providers.
[O] These are visible as login flows or strings.

**Components.** **`AddAccountsBrowserWindow.tsx`** [O]; **`LoginBrowserWindow.tsx`** [O];
**`auth.tsx`** (AuthForm; per-network step-by-step instructions) [O];
**`BridgeV2AuthComponent.tsx`** (generic, server-driven login form: field validation, error box,
"Start Over") [O]; **`BridgeV2Instructions.tsx`** [O]; **`AuthComponents.tsx`** (AuthButton,
AuthText, AutofillOptions "Saved Passwords", DeepLinkLoginOption, BrowserImportLoginOption,
BrowserCookieLogin, PlatformRemoteStatus) [O]; **`TabList.tsx`** (device tabs in instructions:
phone vs tablet vs desktop) [O]; **`LoginQRCode.tsx`** ("Reload QR Code" plus old-session
cleanup) [O]; **`ConnectionPicker.tsx`** (On-Device vs Beeper Cloud, with LearnMoreLink and a
limitations list) [O]; **`CloudIcon.tsx`**, **`DesktopIcon.tsx`**, **`MobileIcon.tsx`**,
**`TabletIcon.tsx`** [O]; **`BrowserSessionImportCard.tsx`** [O]; **`NetworkAccountsMenu.tsx`**
(AddAnotherRow; browser-login import and Telegram Desktop import) [O];
**`AddNewAccountIcon.tsx`** (states Connect / Disabled / Error / Auth required) [O];
**`DetachedAccountsOnboarding.tsx`** (account onboarding hosted outside the main window) [O/I];
**`BrandNetworkIcon.tsx`** (Background) [O]; **`icons-networks.tsx`** (BeeperIcon, TwitterIcon)
[O]; **`Toggle.tsx`** [O].

**Login methods, per network** [O]:
- QR scan: WhatsApp, Signal, Telegram, Discord, Google Messages, Viber, WeChat.
- Pairing code: WhatsApp.
- Phone number + code + 2FA password: Telegram.
- Bot token: Telegram.
- Browser cookies: Instagram, Facebook, Messenger, LinkedIn, X, Google Voice, Discord.
- Google account + emoji tap: Google Messages.
- Approve on phone: WeChat.

Each flow gives a short instruction sequence ("Open WhatsApp on your <device/>", "Tap the menu
(⋮) in the top right", "Grant WhatsApp camera access if prompted", "Scan the QR code") and
specific errors (rate-limited, timed out, passcode locked, outdated bridge).

**On-Device vs Cloud** [O]:
- "These accounts run on your device. Your messages, contacts, and credentials will be stored
  locally with end-to-end encryption."
- versus "These accounts run in the cloud…".
- Rules: "Only one account per network can use Beeper Cloud." and "You’ve reached the on-device
  account limit for this network, so this one will run in Beeper Cloud.".
- A cloud or device indicator on each account row.
- "Encrypt Accounts on This Device" with a reconnect warning.

**Import logins from browsers and apps** [O]:
- "Beeper can use your browser logins to connect your accounts for you." with "Scan browsers",
  "Import selected", "Scan again".
- Per-app blockers: "Quit %s to continue", "These apps keep their logins open while running…".
- Safari needs permission ("Grant Access").
- After import, old-session cleanup: "Account connected, but the old session may still be
  active…", "Quit %s & retry cleanup", "Source session cleaned up.".
- Telegram Desktop import asks for the local passcode.
- Limits: "Importing this would take you over your account limit…".

**Account states and banners** [O]:
- "Account Disconnected" banner with "Reconnect".
- "Account Disabled" (plan limits) with "Manage Accounts" / "Renew Plus" / "Subscribe to Plus
  Plus".
- "This account is having a problem, please contact support.".
- "You are using a non-supported bridge." and "Connecting unofficial integrations may not work
  as expected.".
- "Experimental: Add an account". "Bluesky integration is still work in progress.".

**Account limits and upsell** [O]: "%d Free Account Remaining", "Infinite Accounts Remaining",
"You've reached the account limit…", "Upgrade to %1$s to connect another %2$s account",
"iMessage account doesn't count towards your limits".

### Challenge attachments in server-driven login forms (added from the UI-text check)

**What it does.** A bridge's login step can include attachments above the form fields, as well as
the fields themselves. [O]

- **Images** are shown inline. Their fallback description is "Captcha image".
- **Audio clips** get a small audio player.

So a bridge can ask you to solve a captcha, or listen to a code, as part of logging in. [I] We don't
know which networks use this in practice. The bridge sends the steps when you log in, so the bundle
doesn't show them.

**Evidence:** "Captcha image", "Your browser does not support the audio element."

---

## 17. Settings (Preferences)

**Purpose.** A two-column settings view: categories on the left, the selected pane on the right.
It has search with suggestions.

**Framework components** [O]: **`PrefsPanes.tsx`** (PrefsLeftPane, PrefsRightPane);
**`PrefOption.tsx`**; **`SearchSuggestions.tsx`** (search inside settings: "Search Settings");
**`PrefsControls.tsx`** (CheckBox, WrappedSwitch, ComboBox, PrefComboBox, LocalPrefComboBox,
AccountPrefComboBox; tag "Requires a paid subscription."); **`DynamicPreferencesRenderer.tsx`**
(renders checkbox, combo, multi-select, action-group and custom settings from data; toast
"Preference changed" / "Relaunch app"); **`preference-definitions.tsx`** (LoginItemCheckBox;
the data-driven settings tree); **`PreferenceTags.tsx`** (PreferenceTag and LabsTag:
"Labs" = "Experimental and subject to change", "Hidden", "Internal Only",
"Internal & Nightly Only"); **`PrefsActionPrompt.tsx`** (inline confirm block);
**`PlusPill.tsx`** ("Free" / "Plus" / "Plus Plus" plan pill); preference category icons in
**`icons.tsx`** (PrefGeneralIcon, PrefAIPreferencesIcon, PrefAppearanceIcon,
PrefNotificationsIcon, PrefKeyboardIcon, PrefDevicesIcon, PrefAboutIcon, PrefBeeperPlusIcon,
ZoomLevelIcon).

**Panes (observed setting-group IDs and labels)** [O]:

| Pane | Highlights |
|---|---|
| General | Incognito mode; "Show recipients I'm typing"; App language; reminder defaults; "Sync chat archive state with native platform"; auto-archive; after-archive and after-read behaviour; double-click actions; undo send; emoji autocomplete; auto-send GIFs; auto-play next voice note; "Auto copy OTP/2FA codes"; up-arrow action; time suggestions; downloads; "Get early adopter updates"; "Login Item" / "Open %s at login" / "Keep %s minimized on launch"; Touch ID lock; "Run with Safari renderer"; hardware acceleration; debug logging; hidden events; auto-update; Time Format (12/24-hour); Share Analytics |
| AI | See §13 |
| Appearance | Theme (System/Light/Dark) and theme colour; sidebar; pinned style; "Reduce transparency"; unread counts; previews; compact list; network icons; hover action; empty-list background; App Icon; Honeycomb; threaded replies; read-receipt avatars; timestamps; hide deleted; nudges; animations; "Balance message text"; embeds; incognito indicator; quick reactions; feedback widget; membership events; spellcheck; formatting menu; emoji-on-hover; link previews; composer buttons; pointer cursor; Dock badge count; per-participant bubble colours; default chat theme; Custom CSS (open, reload, reset, auto reload); zoom; Font size |
| Notifications | Sound effects and volume; message, group and request notifications with sounds; notify in focus; reactions; typing; "Delay notifications for" (batching: "OTP/2FA codes are always notified immediately"); "Repeat notification if still unread after"; macOS notification settings link; per-account notifications |
| Accounts / Account / Add Account | Account list, per-account settings, sub-accounts, sign-in methods |
| Profile | Name, username, email, "Sign-In Methods" (link/unlink social logins) |
| Devices | "Current Device", "Verified Devices", "Unverified Devices", "Last seen: %s", logout a device |
| Hotkeys | Rebind every shortcut; "Global" scope; conflict check |
| Quick Replies | List, create, edit, delete; variables; attachments |
| Storage | Usage chart, per-chat storage, clear by age, clear cache |
| Integrations (Beeper Connect) | Desktop API and MCP server; approved clients; tokens; remote access |
| Browser Extension | Chrome extension info |
| Mobile Apps | Install links |
| Bridges | Self-hosted and cloud bridges list ("Show bridges") |
| About / Help | Version, changelog, legal notices, support |
| Secret / Debug Preferences | Hidden flags, SDK features, "Report errors to Sentry" |

**Pane components** [O]:
- **`AccountPrefsSubView.tsx`** (AccountDisconnected, AccountDisabled; "Remove official %s app
  from Dock").
- **`AccountActions.tsx`** (AccountDeleteButton; per-account "Enable notifications", "Show
  message previews", "Show in Inbox", "Sub-Accounts", "Refresh List").
- **`AccountListItemPure.tsx`** (CloudIndicator, DeviceIndicator).
- **`AccountNotificationPrefs.tsx`** (NotificationSound; the neighbouring strings are the
  Sign-In Methods link/unlink flow).
- **`OtherAccounts.tsx`** ("On Other Devices": accounts that run on another of your devices).
- **`DeviceListItem.tsx`** and **`DeviceRow.tsx`** (device rows with phone, tablet and computer
  icons, "%s (This Device)").
- **`HotkeysPrefsSubView.tsx`** (HotkeyPref with ShortcutRecorder, "Record Shortcut"; conflict
  "%1$s is already used by %2$s"; modifier rules such as "You must use a modifier key like Ctrl,
  Shift or Option/Alt"; "Search hotkeys...", "Revert all", "Switch to Texts.app keybindings").
- **`QuickRepliesPrefsSubView.tsx`** (QuickReplyPrefItem with an auto-growing text area, attach
  and delete).
- **`StoragePrefsSubView.tsx`**, **`StorageByRoomList.tsx`** and **`StorageOverviewChart.tsx`**
  (category breakdown: Images, Videos, Audio, Other Files, Messages, Cache; "Clear storage older
  than %d day?"; "Clear All Cache"; "Calculating message storage... This may take a few
  minutes.").
- **`AppIconPrefsSubView.tsx`** (grid of icons plus a custom upload: "PNG, JPG, or ICNS •
  Recommended: 1024x1024 pixels"; Dock relaunch prompt).
- **`BrowserExtPrefsSubView.tsx`**.
- **`MobileAppsPrefsSubView.tsx`**.
- **`SecretPrefsSubView.tsx`** (Misc, SDKFeatures flags with defaults).
- **`DebugPreferencesIndex.tsx`**.
- **`DisableAnalyticsPreference.tsx`**: the Share Analytics checkbox. The Integrations pane's
  strings sit next to it: "Beeper Desktop API", "Allow connections", "Approved connections",
  "Create Access Token" with an expiry, "Revoke", "Remote Access" (with a public-internet
  warning), "MCP endpoint", "OpenAPI spec endpoint", installers ("Open in Cursor", "Open in
  Visual Studio Code", "Open in Raycast", "Copy Config", "Copy Command"), and
  "Join Developer Community chat".
- **`DeleteAccountModal.tsx`** and **`DeleteAccountPrompt.tsx`** (permanent delete; type your
  username to confirm).
- **`ChangeEmailBrowserWindow.tsx`** (current-email confirm, new email, code).
- **`ProfileField.tsx`**.
- **`CopyableField.tsx`**.

**Third-party access approval** [O]: "A third-party app <app/> wants to access your chats through
Beeper Desktop API.". Options: "Allow sensitive actions" ("Grant permission to send messages and
modify your account"), "Expires in" (1 hour, 1 day, 1 week, 30 days, Never), "Approve" /
"Decline". Note: "Only approve if you initiated this connection and trust the application.".
[I] This dialog lives next to DetachedAccountsOnboarding in the bundle.

**Subscription** [O] (**`SubscriptionExpiryBanners.tsx`**: SubscriptionActionButton,
ManageSubscriptionLink): "Your Plus subscription ends %s", "Your Plus subscription has ended",
"In 24 hours any accounts above the Free account limits may be disabled…", "Manage Subscription",
"Switch to annual billing to save %s", "Start Free %d-Day Trial".
**`CompactAccountsBanner.tsx`** covers Texts.app migration ("Your Texts account has been
converted into a Beeper Plus subscription…"). **`AccountsBanner.tsx`** and
**`AddMoreAccountsBanner.tsx`** (UpgradeButton) are prompts to add accounts or upgrade.
**`AccountDisconnectedBanner.tsx`** is reused in settings and the list.

### Plan limits, and what a lapsed plan takes away (added from the UI-text check)

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

**Evidence:** "%d Account Per Network", "Unlimited Accounts Per Network", "%d Total Account",
"Unlimited Total Accounts", "%d Merged Chat", "Unlimited Merged Chats", "In 24 hours any accounts
above the Free account limits may be disabled, in order of most recently added.", "Beeper has
reverted to the default app icon — renew your subscription to keep your custom app icon."

---

## 18. Reminders, Send Later, Low Priority, Incognito (cross-cutting chat-state features)

These have no dedicated component files beyond the ones already listed. They are described from
strings. [O]

- **Remind Me** [O]: "Remind Me marks this chat as new at the scheduled time, if there is no
  reply." Time suggestions are customizable ("Try %1$s, %2$s, %3$s"). The chat can archive
  after a reminder is set. Notification actions: "Remind in 1 Hour", "Remind in 8 Hours".
  "Dismiss All Reminders?" ("This will remove Reminders from all of your chats."). Reminders are
  a paid feature ("Reminders are available to Beeper Plus subscribers").
- **Send Later** [O]: "Send Later messages can only send if %s app is running (and your computer
  is awake)". Paid, with a free quota.
- **Low Priority** [O]: "Add chats to Low Priority to hide them from the inbox permanently".
- **Hide** [O]: "Hide a chat to remove it from your inbox without leaving it".
- **Incognito mode** [O]: "Incognito mode keeps chats unread even when you click on them and
  doesn't notify recipients you've read them." It asks whether to also hide typing. There is an
  indicator in the composer and a trial ("%d more day of free incognito mode").

### Archive, Low Priority and Hide have different return rules (added from the UI-text check)

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

## 19. Notifications UI

**Components.** **`AccountNotificationPrefs.tsx`** (see §17) and **`Toasts.tsx`** (in-app) [O].

**Behaviour** [O]:
- System notifications have actions "Mark as Read", "Remind in 1 Hour" and "Remind in 8 Hours",
  plus inline reply ("notification replied").
- Batching and repeat settings (see Notifications pane).
- "Restart Notification Center" (clears stuck notifications).
- "Open Notifications in System Preferences".
- Dock badge ("Badge count", option "none") and menu bar ("macOS status area").
- "If the chat is muted, you'll still be notified." and "Notify anyway" for pings that override
  a mute.

### Incoming-call notification overlay (added from the UI-text check)

**What it does.** Beeper can't take calls itself. When a call comes in on a connected network, an
overlay card appears. [O]

- **The card.** It shows a voice or video call icon, the caller's avatar and name, and a dismiss
  button.
- **If that network's own app is installed on the Mac,** the card has an "Open <app>" button. The
  button launches that app so you can answer, and closes the card.
- **If the app isn't installed,** the card says "Open <app> to answer".
- **Several calls** stack in the overlay, one card each.


**Evidence:** "Open %s to answer" (shown with the "Open %s" button, which is covered elsewhere)

---

## 20. Feedback, help and support

[O] Feedback widget ("Show feedback widget", "Feedback?", "Let the Beeper team know what you
think...", "Send Feedback", "We've received your feedback, thank you!"). Problem report ("Report
a Problem", "Describe the issue...", "Attach screenshot or video", "Send a Problem Report").
"Priority Support", "Contact Support", "Having issues? Contact __SUPPORT_EMAIL__".
The Help Hub window is listed in the window catalogue. No component files beyond
**`HelpHubBrowserWindow.tsx`**. [O]

### Problem report can attach the selected message details (added from the UI-text check)

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

## 21. Debug tools (internal)

**Components** [O], all in the DebugApp chunk:
- **`EventExplorer.tsx`** (ExpandableEvent): pick the current chat's room ("Main window is not
  focused on this chat"), tabs MobX / Database / Messages / Matrix, "Copy ID",
  "Re-sync room state from server".
- **`ObjectExplorer.tsx`** (ObjectNode): an expandable JSON tree with pinning, filtering
  ("Filter by type or content...", "Hide non-matching items") and remembered expanded paths.
- **`RoomStateExplorer.tsx`** (TabButton): Matrix room state with auto-expand toggles.
- **`FactsPromptTester.tsx`**: a dry-run tester for the AI fact extraction behind Honeycomb.
  It shows each stage (raw facts, normalized, gates, kept, enrichment, would-persist) and
  persists nothing.
- **`CopyableDataViewer.tsx`**: code view with Expand/Collapse/Copy/Clear.

Developer command-bar items [O]: copy chat ID or JSON, reindex DB, send a custom event,
crash main or renderer (native), uninstall helper tool, open the iMessage on-device connection
settings, "Open Data Explorer", "Open Facts Flow Tester", "Re-fetch and fix room state",
"See your usage stats (Dev environment only)", "UI Experiments", "Debug Preferences".

---

## 22. Shared UI primitives, icons and helpers

**Design-system primitives** [O]:
- Buttons and links: **`BrandButton.tsx`** (BrandButtonLoadingIndicator), **`BrandIconButton.tsx`**,
  **`BrandLink.tsx`**, **`Button.tsx`**, **`IconButton.tsx`**, **`TooltipButton.tsx`**.
- Text and lists: **`BrandHeading.tsx`**, **`BrandParagraph.tsx`**, **`BrandList.tsx`**.
- Inputs: **`BrandSegmentControl.tsx`**, **`BrandSelect.tsx`** (grouped options),
  **`SingleSelect.tsx`**, **`Checkbox.tsx`**, **`Toggle.tsx`**.
- Overlays and layout: **`BrandPopover.tsx`**, **`HoverCard.tsx`**, **`HoverCard.context.tsx`**,
  **`Floating.tsx`**.
- Misc: **`Skeleton.tsx`**, **`ProgressCircle.tsx`**, **`CopyableField.tsx`**, **`ExtLink.tsx`**
  (external link with an icon; its neighbouring strings are the edit-history and error actions),
  **`Slot.tsx`**.
- **`with-assets.tsx`** (AssetComponent, which loads named image assets; its neighbouring
  strings are the hotkey list).
- **`index.tsx`** (TextareaAutosize, BaseActionButton, HotkeyKeys; one of several files with
  this name, also used in §8 and §12).

**Hand-drawn icons** [O]: **`OutlineCheck.tsx`**, **`OutlineChevronDown.tsx`**,
**`OutlineChevronDownSmall.tsx`**, **`OutlineChevronRightSmall.tsx`**, **`OutlineClip.tsx`**,
**`OutlineClock.tsx`**, **`OutlineCompose.tsx`**, **`OutlineSearch.tsx`**,
**`OutlineSidebar.tsx`**, **`OutlineSpinner.tsx`**, **`OutlineTrash.tsx`**,
**`SolidCircleCheck.tsx`**, **`SolidMoon.tsx`** (incognito/quiet glyph [I]), **`PlusIcon.tsx`**,
**`SearchIcon.tsx`**, **`ErrorCircle.tsx`**, **`ConfettiIcon.tsx`**, **`icons-custom.tsx`**
(SpinnerIcon, DownloadIcon, ArrowLeft/Right), **`icons-general.tsx`** (Archive, Unarchive and
Bookmark icons; the archive/delete/report toasts and confirms sit next to them),
**`icons-toolbar.tsx`**, **`icons-networks.tsx`**, **`icons.tsx`** (network badges such as
Snapchat, Texts icons, verified badge, full-screen close, checkbox, preference icons),
**`default.tsx`** (ChatGPT dots avatar), **`drag_handle.tsx`** and **`drag_indicator.tsx`**
(grab handles for reordering).

**Label and space icon library (Material Symbols names)** [O]. These are each a single-glyph
component. The bundle maps them to SF Symbol names. [I] They are offered by the label and space
icon picker (§2). Some, such as close, check, search, settings and download, are probably also
used as general UI glyphs.

**`ac_unit.tsx`**, **`account_circle.tsx`**, **`add.tsx`**, **`air.tsx`**, **`archive.tsx`**,
**`assignment.tsx`**, **`asterisk.tsx`**, **`audio_file.tsx`**, **`auto_awesome.tsx`**,
**`background_replace.tsx`**, **`beach_access.tsx`**, **`bed.tsx`**, **`blur_on.tsx`**,
**`bolt.tsx`**, **`book_2.tsx`**, **`business_center.tsx`**, **`cake.tsx`**,
**`calendar_month.tsx`**, **`call.tsx`**, **`campaign.tsx`**, **`casino.tsx`**,
**`celebration.tsx`**, **`check.tsx`**, **`check_circle.tsx`**, **`chevron_forward.tsx`**,
**`chevron_right.tsx`**, **`clear_day.tsx`**, **`close.tsx`**, **`code.tsx`**,
**`content_copy.tsx`**, **`csv.tsx`**, **`deceased.tsx`**, **`directions_bike.tsx`**,
**`directions_boat.tsx`**, **`directions_car.tsx`**, **`directions_walk.tsx`**,
**`download.tsx`**, **`draft.tsx`**, **`edit_square.tsx`**, **`email.tsx`**,
**`error_outline.tsx`**, **`escalator_warning.tsx`**, **`expand_more.tsx`**, **`explore.tsx`**,
**`eyeglasses.tsx`**, **`family_restroom.tsx`**, **`favorite.tsx`**, **`filter_list.tsx`**,
**`fingerprint.tsx`**, **`fitness_center.tsx`**, **`folder_zip.tsx`**, **`footprint.tsx`**,
**`forward.tsx`**, **`function.tsx`**, **`group.tsx`**, **`hardware.tsx`**,
**`headset_mic.tsx`**, **`heat.tsx`**, **`hiking.tsx`**, **`home.tsx`**,
**`hourglass_bottom.tsx`**, **`image.tsx`**, **`inbox.tsx`**, **`joystick.tsx`**,
**`keep.tsx`**, **`key.tsx`**, **`kitchen.tsx`**, **`language.tsx`**, **`library_add.tsx`**,
**`link.tsx`**, **`local_cafe.tsx`**, **`location_city.tsx`**, **`looks.tsx`**,
**`low_priority_space.tsx`**, **`map.tsx`**, **`maps_ugc.tsx`**, **`mark_email_unread.tsx`**,
**`mode_comment.tsx`**, **`mood.tsx`**, **`moon_stars.tsx`**, **`moped.tsx`**,
**`more_horiz.tsx`**, **`motorcycle.tsx`**, **`movie.tsx`**, **`music_note.tsx`**,
**`nature.tsx`**, **`nest_eco_leaf.tsx`**, **`newspaper.tsx`**, **`notifications.tsx`**,
**`notifications_off.tsx`**, **`pentagon.tsx`**, **`person.tsx`**, **`pets.tsx`**,
**`photo_camera.tsx`**, **`photo_library.tsx`**, **`podcasts.tsx`**, **`pool.tsx`**,
**`rainy.tsx`**, **`reply.tsx`**, **`restaurant.tsx`**, **`reviews.tsx`**, **`road.tsx`**,
**`rowing.tsx`**, **`sailing.tsx`**, **`schedule.tsx`**, **`schedule_send.tsx`**,
**`school.tsx`**, **`search.tsx`**, **`self_improvement.tsx`**, **`settings.tsx`**,
**`shopping_cart.tsx`**, **`signature.tsx`**, **`signpost.tsx`**, **`skateboarding.tsx`**,
**`skillet_cooktop.tsx`**, **`sms.tsx`**, **`speaker.tsx`**, **`speed.tsx`**,
**`sports_basketball.tsx`**, **`sports_cricket.tsx`**, **`sports_football.tsx`**,
**`sports_gymnastics.tsx`**, **`sports_score.tsx`**, **`sports_soccer.tsx`**,
**`sports_tennis.tsx`**, **`stadia_controller.tsx`**, **`star.tsx`**, **`stethoscope.tsx`**,
**`stop.tsx`**, **`storefront.tsx`**, **`stroller.tsx`**, **`stylus_pencil.tsx`**,
**`surfing.tsx`**, **`sync.tsx`**, **`theater_comedy.tsx`**, **`train.tsx`**,
**`translate.tsx`**, **`travel.tsx`**, **`unfold_more.tsx`**, **`video_file.tsx`**,
**`videocam.tsx`**, **`view_sidebar.tsx`**, **`visibility.tsx`**, **`volume_up.tsx`**,
**`warning.tsx`**, **`watch.tsx`**, **`water_bottle.tsx`**, **`water_drop.tsx`**,
**`waves.tsx`**, **`weekend.tsx`**, **`wine_bar.tsx`**.

---

## 23. Non-visual: crash reporting

[O] **`./sentry/crash-reporter.ts`**, **`./sentry/init-sentry-electron.ts`** and
**`./sentry/init-sentry-nonbrowser.ts`** are not UI. They set up crash and error reporting, and
only appear in the main-process build. They connect to the visible app through the crash screen
(§1) and the "Report errors to Sentry" secret flag (§17). No keys are recorded here.

---

## Keyboard shortcuts (from the hotkey list) [O]

Navigation: "Next Chat" / "Previous Chat", "Select Next Unread Chat", "History: Previous/Next
Chat", "Cycle Chats (hold shift to reverse)", "Switch First 9 Chats Modifier", "Switch First 9
Spaces Modifier", "Select Next/Previous Account", "Move focus to the message list",
"Scroll to the bottom of a chat", "Unselect Chat / Select First Chat".

Chat: "Chat: Toggle Archive", "Chat: Toggle Pin", "Chat: Toggle Mute",
"Chat: Toggle Mark As Read", "Chat: Archive All Read", "Chat: Start New",
"Chat: Create New Group", "Chat: Send File", "Chat: Delete".

Message: "Message: Edit", "Message: Forward", "Message: React", "Message: Quick React",
"Message: Quote & Reply", "Message: Open First Link", "Message: Record Audio",
"Message: Talk to Type", "Message: Send GIF", "Message: Send Sticker", "Message: Send Later",
"Message: Send Message and Archive".

Composer: Send, "Insert New Line", "Undo Pending Send", bold, italic, strikethrough, code.

App: "Command Bar: Search Chats", "Toggle Incognito Mode", "Toggle Sidebar",
"Toggle Space Bar", "Toggle Chat Info", "Focus App and Command Bar" (global), "Minimize To %s",
"Quit App".

Global hotkeys work when the app is in the background ("Global hotkeys will work when any app is
active, as long as %s is running").

---

## Unassigned / unclear

Every one of the 434 component files is assigned above. The files below are assigned with low
confidence. Their placement is **[I]**, because the strings next to them in the bundle belong to
a neighbouring module:

- **`Badge.tsx`**: a generic badge. Nearby strings are the account filter and the Matrix join
  dialog.
- **`CreateLabelNudgeIcon.tsx`**: an icon. Nearby strings are the space and label menus.
- **`ErrorRenderer.tsx`**: the crash view. Nearby strings include the chat-theme colour names.
- **`ExtLink.tsx`**, **`DisableAnalyticsPreference.tsx`**, **`AccountNotificationPrefs.tsx`**,
  **`MediaWithSender.tsx`**, **`ContactItem.tsx`**, **`ProgressCircle.tsx`**,
  **`with-assets.tsx`**, **`icons-general.tsx`**, **`CloudIcon.tsx`**, **`StackedAvatars.tsx`**,
  **`BrandVideo.tsx`**, **`BrandLink.tsx`**, **`Emoji.tsx`**, **`Drag.tsx`**,
  **`GlobalAudioPlayer.tsx`**, **`IconButton.tsx`**, **`HotkeysPrefsSubView.tsx`**,
  **`MobileAppsPrefsSubView.tsx`**, **`DynamicPreferencesRenderer.tsx`**,
  **`SelectMessageCommand.tsx`**: all are placed by component name. The strings beside them came
  from a neighbouring feature, and we used those strings to describe that neighbouring feature
  instead.
- **`DetachedAccountsOnboarding.tsx`**: the name suggests account onboarding in a separate window.
  The Desktop-API approval dialog sits next to it in the bundle.
- **`AwaitInboxExperience.tsx`** and **`AwaitNetworkConnection.tsx`**: onboarding wait states
  with no strings of their own.
- **`index.tsx`**: the name is shared by several modules (video player, command bar, text-area
  autosize, hotkey keys, TIFF image).
