# Part A: Beeper Desktop 4.3.209 (macOS): settings, keyboard shortcuts and menus (static)

Clean-room feature inventory, built from static reading of the shipped renderer and main-process bundles plus the English UI-string catalogue. Behaviour is described in our own words. Short UI labels are quoted only so each item can be identified.

**Evidence key.** **O** = Observed: read directly in the shipped bundle (labels, defaults, option lists, wiring). **I** = Inferred: deduced from surrounding code or from framework defaults, and not directly confirmed.

**Gating key** (used in the "Shown when" columns):
- *Hidden*: shown only when the local config flag "show hidden features" is on.
- *Internal*: shown only to Beeper staff accounts.
- *Nightly*: shown to staff or nightly-channel users.
- *Flag X*: shown only when a server-side feature flag allows it.
- *Plus*: needs a paid plan. The setting is shown, but using it opens an upgrade prompt.

**Three storage scopes** (O). A rebuild needs all three:
1. **Synced prefs.** Stored in the user's server-side account data, so they follow the user to every desktop install. Most settings live here.
2. **Device prefs.** Kept in local key-value storage on this machine only. Marked *(device)* below.
3. **App config file.** A JSON config file next to the app data. It is read at launch, and many of its keys need a relaunch to take effect. Marked *(config)* below. Custom keyboard shortcuts are stored here too.

Some items are stored on the server as separate account-data records rather than as prefs. Marked *(account-data)*.

---

## 1. Settings

### 1.1 Settings window structure (O)

- Settings opens in its own window (⌘,). It has a left list of panes, a right content area and a **"Search Settings"** box.
- The search box matches every setting by label, description and hidden keywords. It also matches networks you can add as accounts.
  - Picking a result opens that pane and highlights the setting.
  - Keys: ↑/↓ move, Enter opens, Escape clears.
  - With the box empty, it suggests: "Add an Account", "Incognito Mode", "Show Recipients I'm Typing", "Group Message Notifications", and "Subscribe to Beeper Plus" / "…Plus Plus" (the last depends on plan).
  - ⌘F (the "Search: Room" key) moves focus to the box.
- Every pane and every individual setting also appears as a command-bar command, titled "Pane → Setting" (see §2.6).

Left-pane order. Most panes are conditional:

| # | Pane | Shown when | Evidence |
|---|---|---|---|
| 1 | Profile (avatar + name + plan badge) | always | O |
| 2 | "Accounts" (badge shows account count) | always | O |
| 3 | "General" | at least 1 account | O |
| 4 | "Appearance" | at least 1 account | O |
| 5 | "Notifications" | at least 1 account | O |
| 6 | "Hotkeys" | at least 1 account | O |
| 7 | "Devices" | at least 1 account | O |
| 8 | "AI" | at least 1 account | O |
| 9 | "Beeper Plus" | user can subscribe | O |
| 10 | "Quick Replies" | Flag quick-replies, and at least 1 account | O |
| 11 | "Bridges" | a bridge-visibility condition (not resolved) | O / I |
| 12 | "Integrations" (Desktop API / MCP) | Flag desktop:labs-beeper-connect | O |
| 13 | "Storage" | always | O |
| 14 | "Help" (opens in-app help hub, no pane) | always | O |
| 15 | "About" | always | O |
| extra | "Hotkey Tutorial" (replays keyboard onboarding) | Hidden | O |
| extra | "Browser Extension" | Hidden + Flag browser-extension | O |
| extra | "Mobile Apps" (iOS/Android install links/QR) | Hidden + Internal | O |
| off-list | "Secret" (debug), "Debug Preferences", "Add Account", single "Account" | reached from other UI or typed commands | O |

### 1.2 General

Banner at the top: these settings apply to Beeper only and are not synced to the messaging networks (O).

| Setting (label) | Type | Options | Default | What it changes | Shown when | Ev. |
|---|---|---|---|---|---|---|
| "Incognito mode" | toggle (action) | on/off | off (unset) | Stops sending read receipts until you reply; footer explains it | Flag incognito | O |
| "Show recipients I'm typing" | toggle | on/off | on | Sends typing indicators to others | Flag incognito | O |
| "Show people I'm online when Beeper is focused" | toggle | on/off | on | Sends online presence while the window is focused, on networks that support it | Hidden | O |
| "App language" *(device)* | select | System, English, German, Spanish, French, Japanese, Portuguese (Brazil), each in its own language | System | UI language; shows a "relaunch" toast | locale list non-empty | O (codes) / I (exact label text) |
| "Default for remind later" | select | "If no reply", "Always" | If no reply | Default condition used by the Remind Me picker | Flag remind-later | O |
| "Archive after setting reminder on chat" *(account-data)* | toggle | on/off | off | Setting a reminder also archives the chat | Flag remind-later | O |
| "Sync chat archive state with native platform" | toggle | on/off | unset (off) | Mirrors archive state to networks that support it; footer lists them | Flag sync-archive | O / I default |
| "Mark unread chats as read on archive" *(account-data)* | toggle | on/off | not determined | Archiving an unread chat marks it read | Flag archive-as-unread | O |
| "Auto-archive" (rule) *(account-data)* | select | Never, "After I reply", "After I read" | Never | Archives chats automatically after the chosen event | Internal or Nightly | O |
| …"Delay" | select | Immediately, 1, 5, 10, 30 min, 1, 4, 24 h, 7 days | 10 min | How long after the event to archive | rule is not Never | O |
| …"Archive matching chats" | button | shows "Archive N chats" | — | Applies the rule to the current inbox now | rule is not Never | O |
| "After archive" | select | Select next chat, Select previous chat, Close chat, Do nothing | Select next chat | What gets selected after archiving | always | O |
| Archive-all tool: "Archive [all/read] chats older than [duration]" | 2 selects + button | type: all, read. Age: 3, 7, 14, 28 days, 3 months, 1 year | all, 3 days | One-off bulk archive. Button shows the match count | always | O |
| "After mark as read/unread" | select | same 4 as "After archive" | Select next chat | Selection after toggling read state | always | O |
| "On double-clicking a message" | select | Do nothing, Open the reaction picker, Reply, Forward, Show menu, React with… | Reply | Message double-click behaviour | always | O |
| "Quick reaction emoji" | emoji picker | any emoji | ❤️ | Emoji used by "React with…" | double-click is "React with…" | O |
| "Allow undo send (⌘Z) for" | select | 0 ms (disabled), 750 ms, 1, 2, 3, 5, 10 s | 0 (off) | Holds outgoing messages so they can be undone. ⌘⇧Z sends at once | Flag undo-send | O |
| "Click pending messages to undo send" | toggle | on/off | off | Clicking a held message cancels it | Flag undo-send | O |
| "Include timestamps when copying messages with ⌘C" | toggle | on/off | unset (off) | ⌘C copies with timestamps. Swaps which copy menu item owns ⌘C | always | O |
| "Enable emoji autocomplete" | toggle | on/off | on | Typing ":" suggests emoji | always | O |
| "Automatically send GIFs after selection" | toggle | on/off | off | Picking a GIF sends it at once instead of attaching it | always | O |
| "Automatically play the next voice note" | toggle | on/off | on | Plays voice notes one after another | always | O |
| "Microphone" *(device)* | select | "Same as system (…)", then each audio input device | Same as system | Recording input device | always | O |
| "Disable automatic replacement of emoticons with emojis" | toggle | on/off | unset (off) | Turns off the :) → 🙂 style swaps (list in §2.5) | always | O |
| "Auto copy OTP/2FA codes" | toggle | on/off | on | Copies one-time codes from incoming messages to the clipboard. Footer: you are notified even if the chat is muted | always | O |
| "Press ↑ in the composer to:" | select | "Move focus to the message list", "Edit your last message" | Move focus | ↑ in an empty composer | always | O |
| "Time suggestions" | editable list | free text such as "7am Tomorrow" or "In 3 weeks". Drag to reorder. Max 8, min 1 | In an Hour, In Two Hours, This Evening, Tomorrow, This Weekend, Next Week | Preset times in Remind Me and Send Later menus | always | O |
| "Downloads location" *(device)* | button "Change" | folder picker | OS Downloads folder | Where files are saved | always | O / I default |
| "Always ask where to save files before downloading" | toggle | on/off | unset (off) | Shows a save dialog for each download | always | O |
| "Get early adopter updates" *(device)* | toggle | on/off | off | Beta update channel | Hidden | O |
| "Open Beeper at login" | toggle | on/off | reads the OS login-item state | Adds or removes the macOS login item | platform supports it | O |
| "Keep Beeper minimized on launch" *(config)* | toggle | on/off | off | Starts hidden | always | O |
| "Quit Beeper when closing the main window" *(config)* | toggle | on/off | off | Closing the window quits the app (relaunch needed) | always | O |
| "Default for send later" | select | "If no reply", "Regardless" | If no reply | Default condition for scheduled messages | Flag schedule-message | O |
| "Show WhatsApp Communities as separate spaces" *(account-data)* | toggle | on/off | off | Each community becomes a sidebar space | always | O |
| "Show Telegram Topics as separate spaces" *(account-data)* | toggle | on/off | off | Same idea for Telegram topics | always | O |
| "Require Touch ID authentication on launch" *(device)* | toggle | on/off | off | App lock on start | Touch ID available | O |
| "Run with Safari renderer" *(config)* | toggle | on/off | off | Alternative lighter rendering engine (relaunch) | Hidden + platform flag | O |
| "Hardware acceleration" *(config)* | toggle | on/off | on | GPU acceleration (relaunch) | Hidden | O |
| "Debug logging" *(config)* | toggle | on/off | off | Verbose logs (relaunch) | Hidden | O |
| "Show hidden events in timeline" *(config)* | toggle | on/off | off | Shows normally hidden events (relaunch) | always | O |
| "Automatically check for updates" *(config)* | toggle | on/off | on | Auto-update (relaunch) | staging builds only | O |
| "Enable hidden features" *(config)* | toggle | on/off | off | Unlocks every *Hidden* item | Internal | O |
| "Show cloud/local prefix" *(config)* | toggle | on/off | off | Labels accounts as cloud or on-device | Internal or Nightly | O |
| "Include Matrix results in Start New Chat" | toggle | on/off | off | Adds Matrix user search to new chat | Internal | O |
| "Time Format" *(device)* | select | 12-hour, 24-hour | follows the OS setting passed in at launch | Timestamp format | always | O / I default |
| "Share Analytics" | toggle | on/off | reflects the server-side account flag | Anonymous product analytics on/off (server-side setting) | always | O |

### 1.3 AI

| Setting | Type | Options | Default | What it changes | Shown when | Ev. |
|---|---|---|---|---|---|---|
| "Engine for text-based AI features" | select | GPT 5 mini, GPT 5 nano, GPT 4.1 mini | GPT 4.1 mini | Model used for AI actions | Flag ai-llm usable | O |
| "Language for AI responses and translations" | select | 58 languages plus "Pirate English" | English | Output language of AI features | Flag ai-llm | O |
| "Enable contextual AI" *(device)* | toggle | on/off | off | Background extraction of facts such as recommendations and reminders from received messages. Has a privacy note | Internal | O |
| "Translation Languages" (Labs tag) | multi-select | same language list | en, es, fr, de, it, pt, ru, zh, ja, ar | Languages offered in the message "Translate" submenu | Flag ai-in-beeper-chats | O |
| "Show reply suggestions with /a slash command" | toggle | on/off | unset (off) | AI reply suggestions in the composer. Has a privacy note | Flag ai-composer-autocomplete | O (pref) / I (trigger not traced) |
| "Use OpenAI's Whisper model for Talk to Type and transcribing voice notes" | toggle | on/off | unset (off) | Turns on server-side transcription | Flag talk-to-type | O |
| "Automatically transcribe voice notes when they are received" | toggle | on/off | unset (off) | Auto transcription | Whisper toggle on | O |
| "Default language" (transcription) | select | "Auto-detect" plus 57 languages | Auto-detect | Spoken language hint | Whisper toggle on | O |
| "Mention an AI to get answers and help in chat" | toggle | on/off | unset. The mention list treats unset as on | @-mention AI models in any chat. Sends the 20 most recent messages | Flag ai-in-beeper-chats | O |
| "Your preferred AI for mentions" *(device)* | select | OpenAI, Apple Intelligence (greyed out if unavailable; needs macOS 26+) | OpenAI | Provider for @AI | mention toggle on | O |
| "Custom System Prompt" | multiline text + Save/Cancel/Reset | free text | empty (built-in prompt) | Overrides the prompt used for @AI mentions | mention toggle on; Plus to edit | O |
| "AI Chats" section | per-AI-account picker + "Show in Inbox" select | All Messages / None / Only DMs (per account) | per account | Whether AI-chat accounts appear in the inbox | an AI account exists | O |

### 1.4 Appearance

| Setting | Type | Options | Default | What it changes | Shown when | Ev. |
|---|---|---|---|---|---|---|
| **Chat List** "Show sidebar" | toggle | on/off | on | Shows the space bar or sidebar (same pref as View → Show/Hide Space Bar) | always | O |
| "Use regular style for pinned chats" | toggle | on/off | off | Pinned chats shown as normal rows instead of a compact strip | always | O |
| "Reduce transparency" | toggle | on/off | unset (off) | Drops vibrancy effects | macOS | O |
| "Show number of unread messages" | toggle | on/off | on | Unread counts on rows | always | O |
| "Show message previews" | toggle | on/off | on | Last-message preview text on rows | always | O |
| "Compact chat list" | toggle | on/off | unset (off) | Denser rows | Flag desktop-labs | O |
| "Show network icons" | toggle | on/off | on | Network badge on avatars | always | O |
| "Colorize network icons" | toggle | on/off | on | Brand-coloured badges (disabled when icons are off) | always | O |
| "Chat action button (on hover) should" | select | Archive, Mark Read/Unread, Open Context Menu, Do Nothing | Archive | Hover button on chat rows | always | O |
| "On double-clicking a chat" | select | Open in New Window, Archive, Mark Read/Unread, Mute/Unmute, Normal/Low Priority, Do Nothing | Open in New Window | Row double-click | always | O |
| **Empty Chat List** background | picker | none or images (not enumerated) | none | Art shown when the list is empty | Internal | O / I |
| **App Icon** | icon gallery + upload | built-in icons plus custom PNG/JPG/ICNS (1024² suggested). Offers "Relaunch Dock" | default Beeper icon | Dock/app icon | Flag custom-app-icon (Plus) | O |
| **Conversation View** "Enable Honeycomb" *(device)* | toggle | on/off | on | An experimental view (not resolved further) | Internal or Nightly | O / I |
| "Threaded replies" | toggle | on/off | off | Shows threads in a side panel (Slack-style, and Matrix threads) | Internal or Nightly | O |
| "Avatar read receipts" | toggle | on/off | off | Read receipts as small avatars | Internal or Nightly | O |
| "Show message timestamps" | toggle | on/off | on | Per-message times | always | O |
| "Hide deleted messages" | toggle | on/off | off | Removes "deleted" placeholders | always | O |
| "Enable nudges" | toggle | on/off | on | Shake animation when someone nudges you | Flag nudge | O |
| "Enable message animations" | toggle | on/off | on | Bubble animations | always | O |
| "Balance message text" | toggle | on/off | off (on for internal users) | Even line breaks in bubbles | always | O |
| "Load external embeds automatically" | toggle | on/off | on | Auto-loads iframes and embeds | always | O |
| "Show incognito mode indicator" | toggle | on/off | on | Indicator while incognito is on (disabled if incognito is off) | Flag incognito | O |
| "Show quick reactions" | toggle + radio | "Use my most frequent emoji" / "Custom" (editable emoji slots) | on, frequent | Quick-reaction bar on messages | always | O |
| "Quick reaction emoji" | emoji picker | any | ❤️ | Emoji for the ⌘⇧R quick-react shortcut (same pref as in General) | always | O |
| "Show reactions when a message is selected" | toggle | on/off | off | Shows who reacted when a message is selected | always | O |
| "Show feedback widget" | toggle | on/off | on | In-chat feedback button | always | O |
| "Show membership events" *(device)* | toggle | on/off | on | Join/leave events in the timeline | always | O |
| **Composer** "Enable spellcheck" *(config)* | toggle | on/off | on | Spellcheck (relaunch) | always | O |
| "Show formatting menu" | toggle | on/off | on | Floating bold/italic toolbar on selection | always | O |
| "Open emoji picker on hover" | toggle | on/off | on | Emoji button opens on hover | always | O |
| "Disable link previews in outgoing messages" | toggle | on/off | unset (off) | Sends links without previews | always | O |
| "Primary composer button" | select | Emoji Picker, Talk to Type, Record Audio, GIF Picker, Add Attachment, Send Later, (Sticker Picker: Hidden), None | Emoji Picker | Composer button 1 (cannot be the same as button 2) | always | O |
| "Secondary composer button" | select | same list | Record Audio | Composer button 2 | always | O |
| "Show menu bar icon" *(config)* | toggle | on/off | on | Menu-bar status item (§3.3) | always | O |
| "Use pointer cursor for interactive elements" | toggle | on/off | unset (off) | Hand cursor on clickable items | always | O |
| "Dock badge count" | select | none, all chats, unread chats | unread chats | Number on the Dock icon | always | O |
| **UI Experiments** "Distinct bubble color for each participant in groups" | toggle | on/off | off | Per-sender colours | Hidden | O |
| **Theme** selector | 3 picture buttons | Light, Dark, System | System | App light/dark mode (also sets the OS-level theme source for the app) | always | O |
| "Theme color" (Labs) | swatches | Reset, Red, Green, Blue, Purple (single hue), Rich Red, Rich Green, Rich Blue, Rich Purple, Rich Grey (gradients) | unset | Accent tint | Flag desktop-labs | O |
| **Chat Appearance** "Default chat theme" | wallpaper + bubble colour | Wallpaper: None, built-in images (default, desert, lavender, meadow, mountains, sea, sky, sunset; names from asset files), "Photo…". Bubble colour: palette or default | none, default bubble | Default look of conversations. Only you see it. Each chat can override it | always | O (labels) / I (image list from asset names) |
| **Custom CSS** | 4 buttons | "Open CSS file in editor", "Show CSS file", "Reload CSS", "Reset CSS". Hidden extra: auto-reload toggle (marked broken) | empty file | User stylesheet injected into all windows | always | O |
| **Zoom** | 9-step slider | −4 … +4 | middle (100%) | Window zoom. Hint mentions ⌘= and ⌘- | always | O (I: roughly 10% per step) |
| **Font Size** "Font size" | select | 9–36 | 13 | Base text size in all windows | always | O |

### 1.5 Notifications

| Setting | Type | Options | Default | What it changes | Shown when | Ev. |
|---|---|---|---|---|---|---|
| "Sound effects" | select | Never, Only for sent messages, Only for received messages, Always | Never | In-app send/receive sounds | always | O |
| "Sound effect volume" | slider | 0–1, step 0.1 | 0.5 | Volume of in-app sounds | always | O |
| "Message notifications" | toggle | on/off | on | System notifications for direct messages | always | O |
| "Sound" (notification sound) | select | Default, None. Beeper sounds: Double, Dreams, Not Marimba, Rain Harp, Record, Spirit. System sounds: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink | Default | Plays a preview on change | always | O |
| "Group message notifications" | toggle | on/off | on | Notifications for group chats | always | O |
| "Message request notifications" | toggle | on/off | on | Notifications for requests from unknown senders | always | O |
| Group "Sound" | select | same list | Default | Sound for group notifications | always | O |
| "Notify when app is in focus" | toggle | on/off | on | Notify even while Beeper is frontmost | always | O |
| "Notify when someone reacts to a message" | toggle | on/off | on | Reaction notifications | always | O |
| "Notify when someone starts typing (supported platforms only)" | toggle | on/off | unset (off) | Typing notifications | always | O |
| "Delay notifications for" | select | 0 s (disabled), 10 s, 30 s, 1, 2, 5 min | 0 | Batches bursts from one sender. OTP codes are always immediate | always | O |
| "Repeat notification if still unread after" | select | Never, 2, 5, 10 min | Never | Re-sends a notification once if still unread | always | O |
| "macOS Notifications" | 2 buttons | "Open Notifications in System Preferences", "Restart Notification Center" | — | Shortcuts to OS settings or a repair action | macOS | O |
| **Accounts** section, per account: "Enable notifications", "Show message previews", "Sound" | toggle, toggle, select | sound list as above | on, on, Default | Per-account notification overrides | Hidden, and at least 1 account | O |

### 1.6 Hotkeys

| Control | Type | Behaviour | Ev. |
|---|---|---|---|
| "Search hotkeys..." | text filter | Filters bindings by name | O |
| One row per reassignable shortcut, grouped (App, Chats, Messages, Composer) | recorder | Click "Record Shortcut", press keys, then Save, Cancel or Revert. A binding can also be disabled. Global bindings get a "Global" tag and tooltip | O |
| Validation | rule | Modifier-only bindings must be modifiers alone. Other bindings need at least one modifier plus one key. Single Enter (and single keys where allowed) are accepted. A clash shows "X is already used by Y" | O |
| "Revert all" | button | Wipes custom bindings and relaunches | O |
| "Switch to Texts.app keybindings" | button | Preset: edit = ⌘I, italics disabled, prev/next chat also ⌃⇧Tab/⌃Tab, toggle read = ⌘U, archive = ⌘E or ⌘⇧E, chat switching on ⌘1-9, spaces on ⌃1-9, history = ⌃⌥←/→, archive-all-read disabled | O |
| After any change | toast | Says a relaunch is needed for all changes to apply, with a "Relaunch app" button | O |

Bindings marked "cannot reassign", flagged off, or disabled are not listed (O). Bindings are stored as `keybindings` in the config file (O).

### 1.7 Other panes

| Pane | Controls / content | Ev. |
|---|---|---|
| **Profile** | Avatar upload. Editable Name, Email, Username, with Save/Discard and an unsaved-changes prompt. "Sign-In Methods": link or unlink Apple and Google sign-in (email must be verified first). "Show Recovery Key". "Logout". "Delete account". Subscription: "Upgrade to Beeper Plus" / "…Plus Plus" or "Manage … Subscription", plus a tip to switch to annual billing | O |
| **Accounts** | List of connected chat accounts with status and an add-account flow (network picker opens a login window). Each row opens the Account pane. Has a right-click menu (§3.4.4) | O |
| **Account** (one account) | Enabled/Disabled state. Error banner with Reconnect. "Settings": "Show in Inbox" (All Messages / Only DMs / None). Network-specific toggles supplied by the network. Notification overrides (enable, previews, sound). "Dock": remove the official app for that network from the Dock. "Sub-Accounts" list with on/off toggles, per-sub-account inbox visibility and "Refresh List". Device list for on-device bridges. Tooltips explain cloud vs on-device | O (network toggle list is dynamic, so not enumerable statically) |
| **Devices** | Current, Verified and Unverified devices with "Last seen". Log out a device, with a confirm saying it disconnects that device's chat accounts | O |
| **Quick Replies** | Create, edit and delete saved replies: title, text, optional attachments. "How to use" lists template variables {username}, {first_name}, {last_name}, {full_name}, {phone_number}, {email}. Used with ";" in the composer | O |
| **Storage** | Usage chart by type (images, videos, files, voice, messages, cache). "Storage by Chat" list with a clear button per chat. "Clear storage older than" segmented control 0/30/90/120 days, then "Clear Storage..." with confirm. "Clear All Cache" (previews, drafts, temp files) | O |
| **Integrations** (Beeper Desktop API) | "Allow connections" toggle. "Approved connections" list (client, created, expiry, sensitive-actions flag) with "Revoke". "Install to..." picker: Claude Desktop (downloads an extension file), Cursor, VS Code, Raycast (deep links), Claude Code, Codex (copy a terminal command), with transport choice "Streamable HTTP" or "stdio". "Join Developer Community chat". **Advanced**: OpenAPI spec endpoint, MCP endpoint (copyable), "Remote Access" toggle with a confirm dialog (exposes the API publicly, takes effect after relaunch) | O |
| Integrations approval dialog | When a third-party app requests access: "Approve connection", "Allow sensitive actions" toggle, "Expires in" (1 hour, 1 day, 1 week, 30 days, Never), Decline / Approve | O |
| **Beeper Plus** | Plan comparison and features (Unlimited Labels, Incognito Mode, AI Voice Note Transcription, Chat Reminders, Send Later, Custom App Icon, unlimited merged chats and accounts, Priority Support) with trial or upgrade buttons | O |
| **About** | Version and update status: check, download, relaunch, or manual download. "View changelog", "Report a problem", "Privacy", "Legal Notices" | O |
| **Bridges** | "Cloud Bridges" and "Self-hosted Bridges" lists | O (list fields not traced) |
| **Browser Extension** | Install link; explains it adds "open in Beeper" shortcuts on Twitter, Messenger, Instagram, LinkedIn, Telegram, Discord and WhatsApp | O |
| **Secret** (debug) | Debug switches: SDK feature flags, "Report errors to Sentry", "Disable contacts enrichment", "Run in browser tab", "Idle Timeout". Buttons: relaunch, show worker log, show app or SDK database. Per-account error counts | O |
| **Debug Preferences** | Internal plan/entitlement overview | O / I |

---

## 2. Keyboard

### 2.1 How bindings work (O)

- The macOS build writes "mod" as ⌘.
- Each binding can hold several alternatives, separated by commas (for example "⌘[ or ⌘⌥↑").
- Users can override any reassignable binding (§1.6). A shortcut is shown to users by converting its keys to Mac symbols (⌘ ⇧ ⌥ ^ ↑ ↓ ← →, Escape, Tab, Enter).
- The in-app **"Keyboard Shortcuts"** modal (⌘/) lists the same registry.

### 2.2 Shortcut registry (75 entries)

"Fixed" means the binding cannot be reassigned. "—" means no default key (unbound until the user sets one).

| Name (as shown) | Default (macOS) | Group | Action | Ev. |
|---|---|---|---|---|
| "Focus App" | — (global) | App | **System-wide**: brings the main window forward | O |
| "Focus App and Command Bar" | — (global) | App | **System-wide**: brings the app forward and opens the command bar | O |
| "Command Bar" | ⌘J | App | Opens the command bar in command mode | O |
| "Search" | ⌘K | App | Opens command bar search across chats and messages | O |
| "Search: Room" | ⌘F | App | Searches inside the current chat. In Settings, focuses the settings search | O |
| "Toggle Sidebar" | ⌘⌥S | App | Shows or hides the chat-list sidebar | O |
| "Toggle Incognito Mode" | — | App | Incognito on/off (Flag incognito) | O |
| "Toggle Space Bar" | ⌘S | App | Shows or hides the spaces strip | O |
| "Keyboard Shortcuts" | ⌘/ | App | Opens or closes the shortcuts modal | O |
| "Settings" | ⌘, | App | Opens the Settings window | O |
| "Cycle Filters" | ⌥Tab | App | Steps through Unread, Drafts, Unanswered, DMs, Groups, then All | O |
| "Filter: All" | — | App | Clears chat-list filters | O |
| "Filter: Unread" | ⌘⇧Y | App | Toggles the Unread filter | O |
| "Filter: Drafts" / "Filter: Unanswered" / "Filter: DMs" / "Filter: Groups" | — (4 entries) | App | Toggle each filter | O |
| "Filter By Account" | ⌘⌥A | App | Opens the account filter picker in the command bar | O |
| "Reload App" | ⌘⇧⌥R | App | Reloads all windows | O |
| "Zoom In" / "Zoom Out" / "Reset Zoom" | ⌘= / ⌘- / ⌘0 | App | Window zoom | O |
| "Send Feedback" | ⌘⌥/ | App | Toggles the feedback widget (when a chat is open) | O |
| "Minimize To Menu Bar" | ⌘⌥Q | App | Hides all windows to the menu-bar icon | O |
| "Quit App" | ⌘Q | App | Quits | O |
| "Switch First 9 Spaces Modifier" | ⌘ (so ⌘1–⌘9) | App | Jumps to sidebar space 1–9 (modifier-only binding) | O |
| "Select First 9 Commands Modifier" | ⌘ | App | Picks command 1–9 in the command bar (Hidden; fixed) | O |
| "Select Next Account" / "Select Previous Account" | ⌘⇧] / ⌘⇧[ | App | Next or previous space/account | O |
| "Report a Problem" | ⌘⇧P | App | Opens the problem-report dialog | O |
| "Toggle Chat Info" | ⌘⇧I | Chats | Shows or hides the chat info pane | O |
| "Scroll to the bottom of a chat" | ⌘↓ | Chats | Jumps to the newest message | O |
| "Unselect Chat / Select First Chat" | Escape (fixed) | Chats | Closes the chat and puts the cursor on the list (full Escape behaviour in §2.3) | O |
| "Select Previous Chat" | ⌘[ or ⌘⌥↑ | Chats | Previous chat in the list | O |
| "Select Next Chat" | ⌘] or ⌘⌥↓ | Chats | Next chat in the list | O |
| "Select Next Unread Chat" | ⌘U | Chats | Next unread chat | O |
| "Chat: Toggle Mark As Read" | ⌘⇧U | Chats | Read/unread on the selected or pointed chat | O |
| "Chat: Toggle Mute" | ⌘⇧M | Chats | Mute/unmute | O |
| "Chat: Toggle Pin" | ⌘P | Chats | Pin/unpin | O |
| "Chat: Toggle Archive" | ⌘E, or plain E | Chats | Archive/unarchive. Plain E works only when no chat is open and focus is not in a text field | O |
| "Chat: Archive All Read" | ⌘⇧E | Chats | Archives all read chats, after a confirm | O |
| "Chat: Delete" | — | Chats | Delete chat, after a confirm (Hidden) | O |
| "Remind Later" | ⌘L | Chats | Opens the Remind Me picker (Flag remind-later) | O |
| "Chat: Send File" | ⌘O | Chats | Opens a file picker to attach | O |
| "Chat: Start New" | ⌘N | Chats | New chat mode in the command bar | O |
| "Chat: Create New Group" | ⌘⇧N | Chats | New group mode (registry marks it disabled) | O |
| "Open User Profile" | ⌘⇧O | Chats | Opens the contact's profile on the native network | O |
| "History: Previous Chat" / "History: Next Chat" | ⌃⌥← / ⌃⌥→ | Chats | Back and forward through recently viewed chats | O |
| "Cycle Chats (hold shift to reverse)" | ⌃Tab (⌃⇧Tab reverses) | Chats | Switcher-style cycling through history while ⌃ is held. Committed on release | O |
| "Switch First 9 Chats Modifier" | ⌃ (so ⌃1–⌃9) | Chats | Opens chat 1–9 in the list | O |
| "Message: Quote & Reply" | ⌘R | Messages | Replies to the selected messages | O |
| "Message: Quote or Edit Selected Message" | Enter | Messages | With one message selected: edits it if it is yours (and the composer is empty), otherwise quotes it | O |
| "Message: Open First Link" | ⌘⇧H | Messages | Opens the first link in the selected message | O |
| "Message: React" | → (fixed) | Messages | Opens the reaction picker for the selected message | O |
| "Message: Quick React" | ⌘⇧R | Messages | Reacts with the quick-reaction emoji | O |
| "Download Attachments" | ⌘D | Messages | Downloads attachments of the selected messages | O |
| "Message: Forward" | ⌘⇧F | Messages | Opens the forward picker (needs a selection, otherwise shows a toast) | O |
| "Message: Edit" | ⌘T | Messages | Edits the selected message, or your last text message | O |
| "Select Previous Message" / "Select Next Message" | ↑ / ↓ (fixed) | Messages | Moves message selection. ↓ past the last message returns to the composer | O |
| "Multi Select Previous/Next Message" | ⇧↑ / ⇧↓ (fixed) | Messages | Extends the selection | O |
| "Show Replies" | ⌘↓ | Messages | Opens the reply thread or threaded replies of the selected message | O |
| "Message: Record Audio" | ⌘⇧A | Messages | Voice-note recorder | O |
| "Message: Talk to Type" | ⌘⇧T | Messages | Dictation (Flag voice-transcription) | O |
| "Message: Send GIF" | ⌘⇧G | Messages | GIF picker | O |
| "Message: Send Sticker" | ⌘⌥⇧S | Messages | Sticker picker | O |
| "Message: Send Later" | ⌘⇧L | Messages | Schedule picker (Flag schedule-message) | O |
| "Message: Send Message and Archive" | ⌘Enter | Messages | Sends, then archives the chat | O |
| Copy message (no display name) | ⌘C | Messages | Copies the selected messages (with timestamps if that pref is on) | O |
| "Send Message" | Enter | Composer | Sends | O |
| "Undo Pending Send" | — (single keys allowed) | Composer | Cancels a held message (Flag undo-send) | O |
| "Insert New Line" | ⌥Enter, ⌃Enter, ⇧Enter | Composer | Newline | O |
| "Bold Text Selection" | ⌘B (fixed) | Composer | Bold | O |
| "Italicize Text Selection" | ⌘I (fixed) | Composer | Italic | O |
| "Strikethrough Text Selection" | ⌘⇧X (fixed) | Composer | Strikethrough | O |
| "Format Text Selection as Inline Code" | ` (fixed) | Composer | Inline code | O |

### 2.3 Unmodified navigation keys (vim-style) (O)

These are not in the registry, so they cannot be changed. They apply when focus is not in a text field.

| Context | Key | Action |
|---|---|---|
| Chat list, no chat open | j or ↓ / k or ↑ | Moves the list cursor down / up |
| Chat list, no chat open | ⇧ + j/k/↓/↑ | Starts multi-select and extends it |
| Chat list | x | Enters chat-selection mode, toggling the pointed chat |
| Chat list | Enter | Opens the pointed chat |
| Any | ⌘A | Selects all messages if a chat is open, otherwise selects all chats (enters selection mode) |
| Selection mode | ↑/k, ↓/j, ⌘⇧[ / ⌘⇧] | Moves or extends the chat selection. ⌘A selects all |
| Chat open, message selected | Space | Quick Look the attachment (macOS), or open the media carousel |
| Chat open | ↑ / ↓ (⇧ extends) | Selects messages |
| Anywhere outside inputs | any printable key | Focuses the composer and types that character |
| Any | ⌘Z | Undoes the last undoable toast action, otherwise system undo. Also cancels a held send |
| Any | ⌘⇧Z | Sends held (undo-able) messages immediately |
| Escape (cascade, first match wins) | — | Closes the command bar → leaves selection mode → closes the shortcut, report or recovery modal → clears the quote → cancels editing → closes threaded replies → unselects the chat. In Settings it blurs the field, then closes the window. In other views it leaves the unread view, the draft chat, the requests inbox and the side pane, dismisses a toast, or finally points the cursor at the first chat |

### 2.4 Composer keys (O)

- **Enter** sends. If Enter is mapped to newline instead, it inserts a newline. With nothing typed but a draft-chat open, Enter sends that draft or broadcast.
- **↑ in an empty composer** (or with the caret at the very start) selects the last message. If the pref is "Edit your last message", it opens your last editable message for editing.
- **↓ in an empty composer** selects messages.
- **Backspace** on an empty composer, or **←/↑** at the start, moves focus to pending attachments.
- **Escape** runs the cascade in §2.3.

### 2.5 Composer trigger characters and slash commands (O)

| Trigger | What it offers |
|---|---|
| "@" | Mentions: participants (matched by name, username or email), "@room" (if the network supports it), and AI models such as "@OpenAI" when AI mentions are on |
| ":" | Emoji autocomplete, including custom emoji (off when the pref is off) |
| ";" | Quick Replies by title. Inserts the text with template variables filled from the first participant, and attaches saved files |
| "/" | **Slash commands**. Work only when the "/" is the first character of a one-line draft, not while editing, not in AI chats, and only with Flag slash-commands-available. Commands: **/gif** "Search and send a GIF" (if the chat accepts GIFs), **/voice** "Record a voice message" (if the chat accepts voice), **/nudge** "Shake the chat to get their attention" (if the chat supports nudges). Matching is by prefix |
| "/a" | AI reply suggestions, when the AI pref is on (I: trigger code not located; the pref label states it) |
| Emoticons | Auto-replaced unless disabled: :) and :-) and :-D → 🙂; :D and :d → 😃; :( and :-( → 🙁; ;) and ;-) → 😉; :P :p :-P :-p → 😛; :o :O → 😮; :* → 😘 |

### 2.6 Command bar (⌘J commands, ⌘K search)

**How it works (O)**
- A searchable list of commands grouped by category. Commands can open sub-pickers.
- The list adapts to context: selected messages, open chat, chat type, network capabilities, flags.
- The Touch Bar has a single "⌘K" button that toggles it.
- Some developer commands appear only when the typed query contains a keyword (for example "debug", "reindex", "secret p", "show brid").

**Top-level commands (O).** Count: 128 distinct entries (paired toggles counted once). That is 101 user-facing, 27 developer or debug, plus every Settings item mirrored as "Pane → Setting".

| Category | Commands |
|---|---|
| Message (when messages are selected) | "React with X" or "Remove X reaction" for each allowed reaction; react with a typed emoji; hint "Type any emoji to react with it"; "Edit"; "Unsend"; "Delete for me" (Hidden); "Delete for everyone"; a disabled notice when delete is not supported; "Forward" (sub-picker); "Copy"; "Copy with timestamps"; "Download attachments"; "Open link" (picker if there are several); "Unselect"; "Reply" or "Quote reply N messages"; "Reply in thread"; "Reply privately"; "Summarize selected messages with AI"; "Translate selected messages to <lang> with AI"; "Translate selected messages with AI" (language picker); "Debug" |
| User (one-to-one chat) | "Copy name: …", "Copy username: …", "Copy phone number: …", "Copy email: …", "Call …", "FaceTime", "FaceTime Audio", "Open <user> on <network>" (⌘⇧O), "Notify anyway" (if Do Not Disturb is active), "Message on <other network>" (same contact on another account) |
| Chat (open chat) | "Change message expiry timer" (picker), "Add members" (multi-select picker), "Remove member from group", "Leave chat", "Make group admin", "Dismiss group admin", "Edit group", "Show chat info" / "Hide chat info", "Edit contact", "Refresh chat", "Send file", "Send contact" (contact picker), "Send GIF", "Send Sticker", "Export all loaded messages to .txt file", "Summarize the last N messages with AI" (up to 15), "Clear the AI pane conversation" |
| Account | "Mute account: …" / "Unmute account: …", "Message yourself" |
| Message (composer) | "Send later" (schedule picker) |
| Chat / N Chats (applies to the selection if several) | "Remind me later" (picker), "Move to Low Priority" / "Move to Inbox", "Mark as read" / "Mark as unread", "Pin" / "Unpin", "Mute" / "Unmute", "Archive" / "Unarchive", "Hide" / "Unhide", "Draft response with AI", "Edit draft response with AI" (instruction picker), "Translate draft response with AI" (language picker), "Move to inbox" (from requests), "Delete", "Edit Labels" (label picker), "Report as spam", "Open in new window" |
| Chats | "Archive all chats", "Archive all chats older than a week", "Archive all read chats", "Mark all chats as read" (confirm) |
| Update Available | "Relaunch app to update", "View changelog" |
| UI | "Set theme to match system" / "Set theme to light mode" / "Set theme to dark mode" (the current one is omitted), "Toggle chat selection mode", "Confetti", "Redact names and pictures" / "Unredact …" |
| Navigation and global | "Search chats", "Merge chats", "Select next: …", "Select previous: …", "Open recently viewed chats" (history picker), "Create new chat", "Create new group", "Join a Matrix room", "Start a new AI chat" (one per AI account), "Search messages in all chats", "Search messages in current chat", "Show message requests" / "Show default inbox", "Create quick reply from draft" (prompts for a title), "Show keyboard shortcuts", "Toggle sidebar", "Toggle space bar", "Edit spaces" |
| Filter Chats | "Filter by folder type", "Filter by type", "Filter by account"; also "Enable/disable account" (flag-gated) and "View accounts onboarding" (typed) |
| Window / View | "Media viewer", "Open space in new window", "Maximize/unmaximize", "Zoom in", "Zoom out", "Reset zoom" |
| Settings | "Show settings", "Turn on incognito mode" / "Turn off …", plus one command per settings pane and per individual setting |
| Misc | "Email feedback", "Open custom CSS file in editor" (Internal), "Reload custom CSS" (Internal), "Logout of your Beeper account (…)", "View subscription details / billing history / edit payment methods", "Show secret prefs" (typed), "Show bridges" (typed), "Install browser extension" (flag), "Lock app" (Touch ID), "Report a problem" |
| Developer (always listed; some need a typed keyword) | Copy current chat ID, Copy invite link, Copy current chat as JSON, Copy loaded messages as JSON, Copy selected messages as JSON, Copy chat deep link, Open platform directory, Reload app, Relaunch app, Cleanup, Reindex DB, Send notification for last message, Restart macOS Notification Center, Uninstall helper tool, Open console, Crash main process, Crash renderer process, Open iMessage on-device connection settings, Open Data Explorer, Open Facts Flow Tester (Internal), Send custom event; per chat: Copy chat archive log, Re-fetch and fix room state, Debug |
| Subscription | Commands supplied by the subscription store, prepended to the list (**not resolved**) |

**Sub-pickers (O).** 19 in total:

| Picker | Heading | Behaviour |
|---|---|---|
| Add members | "Add members to chat" | Multi-select user search |
| Remove member | "Remove member from group" | Single pick |
| Chat folders | "Filter chat folders" | Folder filter |
| Chat type | "Filter chats" | Type filter |
| Account filter | "Filter account" | Account filter |
| Enable/disable account | "Enable/disable account" | Tick list |
| Make admin | "Make group admin" | User pick |
| Dismiss admin | "Dismiss group admin" | User pick |
| Expiry timer | "Set message expiry timer" | Duration list |
| Send later | "Send Later" / "Reschedule message" | Natural-language time ("Monday morning"), condition selector "If no reply" / "Regardless", and a footer: Beeper must be running for it to send |
| Forward | "Forward message" | Multi-select chats, with a note that native apps show no attribution |
| Add to contact | "Add to existing contact" | Contact pick |
| Share contact | "Select contact to share" | Contact pick |
| Translate messages | "Translate selected messages to" | Language list |
| Edit draft | "Edit draft" | Presets "Make more confident", "…professional", "…friendly", "…verbose", "…concise", "Fix grammar/spelling", or typed text |
| Translate draft | "Translate draft to" | Language list |
| History | "Recently viewed chats" | History list, with history keys shown |
| Labels | "Edit Labels" | Tick list plus "Create New Label" |
| Remind me | "Remind Me" | Natural-language time, condition "If no reply" / "Always", and a footer explaining the chat is marked new at that time |

Also: a generic text prompt picker, and "open link" (a list of the links found).

---

## 3. Menus

### 3.1 macOS menu bar (O, built in the renderer and installed via the main process)

| Menu | Items, in order |
|---|---|
| **Beeper** | "About Beeper" (opens Settings → About); "Check for Updates…" (label becomes update progress while updating); — ; when signed in: "Accounts…", "Preferences" (⌘,; opens the Settings window), — , "Command Bar…" (⌘J), "Search..." (⌘K); — ; "Close Window" (⌘W, hidden); Services ▸; — ; Hide Beeper, Hide Others, Show All; — ; "Lock App" (only with Touch ID); "Logout of Beeper..."; "Quit Beeper" (⌘Q) |
| **File** | "Open..." (⌘O, attach a file); "New Chat" (⌘N); — ; Close (standard); "Open Chat in New Window" |
| **Edit** | Standard Electron macOS edit menu. Assumed contents: Undo, Redo, Cut, Copy, Paste, Paste and Match Style, Delete, Select All, Speech ▸ (I: role-based, not enumerated in the bundle) |
| **View** | "Show Space Bar" / "Hide Space Bar" (⌘S); "Show Sidebar" / "Hide Sidebar" (⌘⌥S) |
| **Window** | Toggle Full Screen, Zoom, Minimize, Bring All to Front (standard roles) |
| **Help** | Toggle Developer Tools (hidden); "Report a Problem" (⌘⇧P); "Open Beeper Help"; — ; "Open Beeper.com"; "Follow @Beeper on X"; — ; "Changelog"; "Privacy & Security"; "Keyboard Shortcuts" (⌘/); when signed in: — , "Logout of Beeper..." |

Menu accelerators come from the shortcut registry, so they follow user customisation (O).

### 3.2 Dock menu (O)

Rebuilt about 0.5 s after relevant changes. Empty when signed out or when the app is locked. It has two sections, each with a disabled header:
- **"Unread Chats"**: up to 5 unread chats, newest first. Excludes low-priority chats, chats hidden from the inbox, and chats merged into another.
- **"Recent Chats"**: up to 5 from viewing history. Excludes the current chat, chats already listed above, and hidden chats.

Titles are cut to 40 characters. Clicking one shows the window and opens that chat. macOS adds its standard Dock items (I).

### 3.3 Menu-bar (tray) icon (O)

- Template icon with tooltip "Beeper". It can be turned off ("Show menu bar icon").
- Left-click:
  - Window not focused or hidden → shows all windows.
  - Window visible and focused, or ⌃-click → pops up the menu.
- Right-click → pops up the menu.
- Menu while the window is visible: "Minimize to Menu Bar" (⌘⌥Q; hides all windows), "Quit Beeper" (⌘Q).
- Menu while minimized or hidden: "Quit Beeper" only. "Show Window" exists but only on Linux.
- An unread-variant icon exists, but it is used on non-macOS builds only.

### 3.4 Context menus

All menus below are built in the renderer and shown as native menus (O). "—" is a separator.

#### 3.4.1 Chat-list item (also the chat header menu and the info-panel menu)

The same builder is used in all three places (O). Items, top to bottom. Most are conditional:
1. "Accept message request" / "Accept group invitation"; "Decline …" (requests only)
2. — ; when several chats are selected: heading "N chats selected"
3. "Move to Inbox" (for requests, on networks that support it)
4. "Archive" / "Unarchive" (⌘E; disabled if pinned and not archived)
5. "Mute" / "Unmute" (⌘⇧M), plus a disabled reason line such as "Muted by Label X" or "Muted by <account>"
6. "Mark as Read" / "Mark as Unread" (⌘⇧U); with multi-select: "Mark All as Read" / "Mark All as Unread"
7. "Pin" / "Unpin" (⌘P)
8. "Follow All Threads" / "Stop Following All Threads" (threaded networks)
9. "Edit Group..."
10. "Copy" ▸ "Chat Link" (a beeper:// deep link), "Matrix Link" (Internal, Matrix chats)
11. — ; "Search…" (⌘F); "Message Expiry…" (outside the list, where supported)
12. — ; "Hide" / "Unhide" (Hidden)
13. "Move to Low Priority" / "Move to Inbox"
14. "Label" ▸ one tick per label, — , "New Label…" (Plus-gated: opens upgrade instead)
15. "Remind Me" ▸ upgrade item (if not entitled), "Last Used <date>", time-suggestion presets, — , "Custom…", — , "Dismiss Reminder"
16. — ; "Unmerge" (merged chat) **or** "Delete Chat" (flag delete-chats; confirm)
17. "Report as Spam…" (supported networks)
18. — ; "Open in New Window"; "Begin Selecting"
19. — ; "Report a Problem" (⌘⇧P); "Debug Room" (debug tools only)

A **selection-mode action bar** replaces this when several chats are selected: Archive/Unarchive, Mark Read/Unread, Mute/Unmute, Low Priority / Move to Inbox, Remind Me, More (O).

#### 3.4.2 Message (right-click or "Show menu" double-click action) (O)

1. Detected-data items, shown when right-clicking on detected data:
   - **phone**: number header, "Call", "Copy"
   - **address**: header, "Open in Google Maps", "Open in Apple Maps", "Copy"
   - **date**: header, "Add to Calendar", "Copy"
   - **flight**: header, "Track Flight", "Copy"
2. **Email address**: "Copy <addr>", "Email <addr>…", "Add <addr> to <name>'s Contact"
3. **Link**: "Summarize link with AI" (AI flag), "Copy Link"
4. Unloaded media: "Load Media" / "Try Loading Media Again"
5. "Edit…" (⌘T), "Reply…" (⌘R), "Reply in thread…" (⌘↓), "Follow Thread" / "Unfollow Thread", "Quote reply N messages…", "Reply Privately…"
6. "React…", "Translate" ▸ configured languages (each one becomes "Remove X" once translated)
7. "Bookmark" / "Remove Bookmark" (supported networks)
8. "Mark as Read" (if unread), "Mark as Unread" (from here), "End Poll" (your open poll), "Jump to Message" (from a reply or thread view)
9. Voice/audio only: "Playback Speed" ▸ 0.25×–2× (I: list shared with the video player), "Transcription Language" ▸ Auto-detect plus languages
10. Deletion by network mode: "Unsend", "Delete for Me…" (Hidden), "Delete for Everyone…" (confirm)
11. — ; "Copy" / "Copy Entire Message" (⌘C), "Copy with Timestamp" / "Copy Entire Message with Timestamp"
12. "Add :name: to Custom Emoji" (when right-clicking a custom emoji or reaction image); "Copy Image" (image)
13. "Forward…" (⌘⇧F); "Download Attachment(s)" / "Download Image(s)" with size (⌘D); "Quick Look"; "Preview in Carousel"
14. Bot or message buttons (each becomes an item)
15. Disabled info rows: "Sent at …" / "Received at …", disappearing-timer text
16. — ; "Report a Problem"; "Debug Message", "Debug Room" (debug tools only)

**Gallery or album variant**: "Reactions", "Download All" (⌘D), "Forward All…" (⌘⇧F), plus the audio items (O).

#### 3.4.3 Image, video and attachment views (O)

- **Inline video player menu**: "Show in Chat", "Fullscreen", "Open in PiP", "Download", "Mute" / "Unmute", "Playback Speed" ▸ Normal plus multiples (0.25×–2×).
- **Attachment carousel keys**: Escape closes; ← / → previous or next; D downloads; R rotates 90°; F fullscreen (video). Buttons include React and Close.
- **Media viewer window**: caption search (Escape clears, then closes); per-item Delete.

#### 3.4.4 Account / space (sidebar space icon, Accounts pane, Edit Spaces) (O)

1. "Enable" / "Disable" (legacy flag)
2. "Show in Inbox" ▸ All Messages / Only DMs / None (ticked)
3. "Mute Space" / "Unmute Space"
4. "Open in New Window"
5. — ; "Edit Spaces…"
6. "Remove Account…" **or** "Add/Remove Accounts…"
7. — ; "Account Settings…"
8. "Connect" (if not configured on this device)
9. "Retry" and "Reconnect" (errored or needs re-auth)
10. "Developer" ▸ "Copy Account ID", "Copy Bridge ID", "Copy Info as JSON", "Restart Bridge" (confirm), "Delete Bridge" (confirm). Internal or dev only

Variants:
- **Remote-device account** menu: "Remove Account" (+ Developer ▸ Copy Account ID).
- **Built-in space** (Inbox, Archive, Reminders, Requests, Low Priority, Send Later): "Open in New Window", "Add/Remove Accounts…" (⌘,), "Edit Spaces…", "Show/Hide Space Bar" (⌘S), "Settings" (⌘,).

#### 3.4.5 Label space (O)

"Show in Inbox" ▸ (label visibility), "Mute" / "Unmute", "Edit Label…", "Delete Label" (confirm: removes the label from all chats).

#### 3.4.6 Native fallback context menu (main process; text fields and anywhere the renderer does not supply a menu) (O)

These labels are hard-coded English and are not in the translation table.

1. Spelling suggestions, or a disabled "No Guesses Found"
2. "Clear Formatting" (Beeper addition, when the selection in the composer has formatting)
3. "Learn Spelling"
4. "Look Up “<selection>”"
5. "Search with Google"
6. Cut / Copy / Paste
7. "Save Image" / "Copy Image" (image)
8. "Save Video" (video)
9. "Copy Link" (link)
10. "Inspect Element" (development builds only)

Image-address, video-address, "Save Link", "Select All" and "Services" items exist but are off with the shipped options.

---

## 4. Counts and open items

| Area | Count | Notes |
|---|---|---|
| Settings | **152** individual controls | General 47, AI 12, Appearance 43, Notifications 16 (13 global + 3 per-account), Hotkeys 3 controls (plus about 70 per-binding recorders), plus about 31 across Profile, Account, Devices, Quick Replies, Storage, Integrations, About and Beeper Plus. 21 panes or sub-panes in total |
| Keyboard shortcuts | **75** registry entries (69 table rows; a few rows bundle 2–4 entries) + 2 system-wide (both unbound by default) + 14 unmodified navigation keys + composer keys + 6 carousel keys | 2 are modifier-only (⌘1–9, ⌃1–9) |
| Menu items | **about 130** | Menu bar about 33 (Edit menu assumed), Dock 2 sections × 5, Tray 2–3, chat item about 30, message about 45, account/space about 15, label 4, video 6, native fallback about 13 |
| Command-bar commands | **128** top-level (101 user-facing + 27 developer) + **19** sub-pickers + 6 AI edit presets | Plus every settings item mirrored as a command |
| Slash commands | **3** (/gif, /voice, /nudge) + "/a" (pref only) | Also @, :, ; triggers |

**Could not resolve statically:**
- The commands supplied by the subscription store at the top of the command bar.
- The exact display text of the app-language options (only the locale codes were confirmed).
- The network-specific toggles on each Account pane, which come from each network's own definition at run time.
- When the Bridges pane is shown, and the columns of its list.
- The Edit menu contents (assumed from Electron defaults).
- The code that triggers "/a" AI reply suggestions.
- The exact zoom percentage per slider step.
- The built-in wallpaper names (taken from asset filenames).
- The defaults for "Mark unread chats as read on archive" and for the notification-sound "Default".
- Settings with no explicit default are recorded as "unset (off)". Treat that as Inferred.

---

# Part B: live walk-through (observed in the running app, 2026-10-15)

Captured over a loopback-only remote-debugging connection and macOS accessibility. Values shown are the current values on the test machine, **not necessarily the factory defaults**. Where this part and Part A above disagree, trust this part: it is what the running app actually showed.

## Settings (observed live, all panes)

Settings opens in its own window. A left column lists the panes, with a search box at the top that searches every individual setting. Every setting is also reachable from the command bar as "Pane → Setting".

Paid features carry a "+ Plus" badge. Experimental ones carry a "🧪 Labs" badge.

### Profile (top of the list)
Shows your avatar, name and plan ("Free"). Opens the profile editor.

### Accounts
- Lists every connected network account, showing the network and the account identifier (phone number, email or username).
- An "On Other Devices" section with a Connect action, for adding accounts that live on another device.
- The count of connected accounts shows as a badge on the pane name.

### General
| Setting | Control | Options / notes |
|---|---|---|
| Incognito mode (Plus) | toggle | Keeps chats unread when opened and sends no read receipts. Respond or press ⌘⇧U to mark read. |
| Show recipients I'm typing (Plus) | toggle | |
| App language | select | System, English, Deutsch, Español, Français, 日本語, Português do Brasil |
| Default for remind later (Plus) | select | If no reply / Always |
| Archive after setting reminder on chat (Plus) | toggle | |
| Mark unread chats as read on archive | toggle | default on |
| After archive | select | Select next chat / Select previous chat / Close chat / Do nothing |
| Archive [all / all read] chats older than [3 days … 1 year] | two selects + button | Button shows the live count, e.g. "Archive N chats" |
| After mark as read/unread | select | same four options as After archive |
| On double-clicking a message | select | Do nothing / Open the reaction picker / Reply / Forward / Show menu / React with… |
| Allow undo send (⌘Z) for (Plus) | select | 0 ms (disabled), 750 ms, 1, 2, 3, 5, 10 seconds |
| Click pending messages to undo send (Plus) | toggle | |
| Include timestamps when copying messages with ⌘C | toggle | |
| Enable emoji autocomplete | toggle | |
| Automatically send GIFs after selection | toggle | |
| Automatically play the next voice note | toggle | |
| Microphone | select | "Same as system" plus every input device |
| Disable automatic replacement of emoticons with emojis | toggle | |
| Auto copy OTP/2FA codes | toggle | Still notifies even if the chat is muted |
| Press ↑ in the composer to | select | Move focus to the message list / Edit your last message |
| Time suggestions | editable list | Presets used by remind-later and send-later: In an Hour, In Two Hours, This Evening, Tomorrow, This Weekend, Next Week. Each can be removed. Add and Reset buttons. |
| Downloads location | path + Change | |
| Always ask where to save files before downloading | toggle | |
| Open Beeper at login | toggle | |
| Keep Beeper minimized on launch | toggle | |
| Quit Beeper when closing the main window | toggle | |
| Default for send later (Plus) | select | If no reply / Regardless |
| Show WhatsApp Communities as separate spaces | toggle | |
| Show Telegram Topics as separate spaces | toggle | |
| Require Touch ID authentication on launch | toggle | |
| Show hidden events in timeline | toggle | |
| Time Format | select | 12-hour / 24-hour |
| Share Analytics | toggle | anonymous analytics |

### Appearance
**Chat list:** Show sidebar; Use regular style for pinned chats; Reduce transparency; Show number of unread messages; Show message previews; Compact chat list (Labs); Show network icons; Colorize network icons.
- Chat action button on hover: Archive / Mark Read/Unread / Open Context Menu / Do Nothing.
- On double-clicking a chat: Open in New Window / Archive / Mark Read/Unread / Mute/Unmute / Normal/Low Priority / Do Nothing.

**App icon:** a picker of alternative dock icons.

**Conversation view:** Show message timestamps; Hide deleted messages; Enable message animations; Balance message text; Load external embeds automatically; Show incognito mode indicator (Plus).
- Show quick reactions: either "use my most frequent emoji" or a custom set (default 👍 ❤️ 😂).
- Also: Quick reaction emoji (default ❤️); Show reactions when a message is selected; Show feedback widget; Show membership events.

**Composer:** Enable spellcheck; Show formatting menu; Open emoji picker on hover; Disable link previews in outgoing messages.
- Primary composer button: Emoji Picker / Talk to Type / GIF Picker / Add Attachment / Send Later / None.
- Secondary composer button: Talk to Type / Record Audio / GIF Picker / Add Attachment / Send Later / None.

**System:** Show menu bar icon; Use pointer cursor for interactive elements; Dock badge count (none / all chats / unread chats).

**Theme:** Light / Dark / System, with a Reset. Accent themes: Red, Green, Blue, Purple, and "Rich" variants of Red, Green, Blue, Purple and Grey.

**Chat appearance:**
- Default bubble colour: Blue, Indigo, Purple, Pink, Red, Orange, Green, Teal, Slate.
- Wallpaper: none, choose your own photo, or one of 21 named presets (Mist Blue, Seafoam, Sage, Frost Teal, Lagoon, Skywash, Mint, Meadow, Moss, Sand, Oat, Butter, Linen, Petal, Pearl, Orchid, Bloom, Haze, Violet Night, Apricot, Amber).
- Per-chat themes are set from a separate Chat Theme window.

**Custom CSS:** Open the CSS file in an editor, Show it in Finder, Reload, Reset.

**Zoom and font size:** font size select from 9 to 35 px.

### Notifications
- Sound effects: Never / Only for sent messages / Only for received messages / Always, plus a volume control.
- Message notifications: on/off with a sound choice (Default, None, Beeper, Sounds, Double, Dreams, Not, Marimba, Rain, Harp, Record, Spirit, System sounds…).
- Group message notifications: on/off with its own sound choice.
- Message request notifications; Notify when app is in focus; Notify when someone reacts; Notify when someone starts typing (supported platforms only).
- Delay notifications for: 0 (disabled), 10 s, 30 s, 1 min, 2 min, 5 min.
- Repeat notification if still unread after: Never, 2, 5, 10 minutes.
- Buttons: Open Notifications in System Settings; Restart Notification Center.

### Hotkeys
- Every shortcut can be turned on or off and rebound.
- There's a search box, a "Revert all" button, and a "Switch to Texts.app keybindings" preset.
- Two shortcuts can be made global (system-wide): Focus App, and Focus App and Command Bar.
- The full table is in the Keyboard section below.

### Devices
"Take Beeper with you": get the mobile app, or send a download link to your phone number. Also includes Logout.

### AI (all Plus)
- Translation languages (Labs): Arabic, Chinese, English, French, German, Italian, Japanese, Portuguese, Russian, Spanish.
- Voice transcription: use OpenAI's Whisper model for Talk to Type and for transcribing voice notes. Audio is sent to OpenAI through Beeper's servers.
- AI mentions: mention an AI in a chat to get answers. It sends the 20 most recent messages as context.

### Beeper Plus
Upsell page headed "All Your Chats and More", with a "Go Unlimited" plan and a 7-day free trial.

### Integrations
- Beeper Desktop API: an "Allow connections" switch lets approved third-party apps (Claude Desktop, Raycast) talk to Beeper.
- MCP install buttons for Claude Desktop (an extension download), Cursor, VS Code and Raycast.
- An "Install to…" selector (Claude Code, Codex, Streamable HTTP, stdio) with a Copy Command button.
- An approved-connections list with Revoke.
- Advanced → Remote Access: exposes the API and MCP on the public internet after relaunch.

### Storage
- Auto-delete media after 0 / 30 / 90 / 120 days, chosen separately for Images, Videos, Other Files and Audio.
- Clear Storage.
- Storage by chat: each chat with its file count, message count and size, with a per-chat Clear.

### Help / About
- About shows the version and links to View changelog, Report a problem, Privacy, and Legal Notices.
- Help opens external help. In the walk-through the pane didn't switch (unresolved).

### Settings visible only through the command bar (not in the sidebar)
Secret, Browser Extension, Mobile Apps, Quick Replies, Bridges, Profile, Debug Preferences. These were seen as command-bar entries but not opened.

## Keyboard (observed live, defaults)

| Action | Default keys |
|---|---|
| Chat: Archive all read | ⌘⇧E |
| Chat: Send file | ⌘O |
| Chat: Start new | ⌘N |
| Chat: Toggle archive | ⌘E, or E |
| Chat: Toggle mark as read | ⌘⇧U |
| Chat: Toggle mute | ⌘⇧M |
| Chat: Toggle pin | ⌘P |
| Cycle chats (Shift reverses) | ⌃Tab |
| History: next / previous chat | ⌃⌥→ / ⌃⌥← |
| Open user profile | ⌘⇧O |
| Remind later | ⌘L |
| Scroll to bottom of chat | ⌘↓ |
| Select next / previous chat | ⌘] or ⌘⌥↓ / ⌘[ or ⌘⌥↑ |
| Select next unread chat | ⌘U |
| Switch to chat 1–9 | ⌃ + number |
| Toggle chat info | ⌘⇧I |
| Command bar | ⌘J |
| Cycle filters | ⌥Tab |
| Filter by account | ⌘⌥A |
| Filter: Unread | ⌘⇧Y (All, DMs, Drafts, Groups, Unanswered exist, unbound by default) |
| Focus app / Focus app and command bar | global, unbound by default |
| Keyboard shortcuts sheet | ⌘/ |
| Minimize to menu bar | ⌘⌥Q |
| Quit | ⌘Q |
| Reload app | ⌘⇧⌥R |
| Report a problem | ⌘⇧P |
| Zoom in / out / reset | ⌘+ / ⌘- / ⌘0 |
| Search (all chats and messages) | ⌘K |
| Search in this chat | ⌘F |
| Next / previous account | ⌘⇧] / ⌘⇧[ |
| Send feedback | ⌘⌥/ |
| Settings | ⌘, |
| Switch to space 1–9 | ⌘ + number |
| Toggle sidebar | ⌘⌥S |
| Toggle space bar | ⌘S |
| Download attachments | ⌘D |
| Message: Edit | ⌘T |
| Message: Forward | ⌘⇧F |
| Message: Open first link | ⌘⇧H |
| Message: Quick react | ⌘⇧R |
| Message: Quote & reply | ⌘R |
| Message: Quote or edit the selected message | Enter |
| Message: Record audio | ⌘⇧A |
| Message: Send GIF | ⌘⇧G |
| Message: Send later | ⌘⇧L |
| Message: Send and archive | ⌘Enter |
| Message: Send sticker | ⌘⌥⇧S |
| Message: Talk to type | ⌘⇧T |
| Show replies | ⌘↓ |
| Composer: new line | ⌥Enter, ⌃Enter, ⇧Enter |
| Composer: send | Enter |
| Composer: undo pending send | unbound by default (⌘Z while the undo window is open) |

## Command bar (⌘J, observed live)

A searchable list grouped into sections. Each entry shows its shortcut when it has one.

- **Chats:** Search chats; Merge chats; Open recently viewed chats; Archive all chats; Archive all chats older than a week; Archive all read chats; Mark all chats as read; Next chat (shows the target chat).
- **Commands:** Create new chat; Create new group; Join a Matrix room; Search messages in all chats; Show message requests; Show settings; Show keyboard shortcuts; Toggle sidebar; Toggle space bar; Edit spaces; Email feedback; Logout; View subscription / billing; Lock app; Report a problem.
- **Filter chats:** Filter by folder type; Filter by type; Filter by account.
- **Settings:** every pane and every individual setting, listed as "Pane → Setting".
- **Accounts:** a jump entry per network: WhatsApp, X, Telegram, Slack, Discord, Facebook, Instagram, LinkedIn, Google Messages, Signal, Google Chat, LINE, Google Voice, Tumblr, Viber, iMessage. Also "Turn on incognito mode".
- **Window:** Media viewer; Open space in new window; Maximize/unmaximize.
- **View:** Zoom in / out / reset.
- **UI:** Set theme to light / dark; Toggle chat selection mode; Confetti; Redact names and pictures (a privacy mode for screenshots).
- **Developer:** Reload app; Relaunch app; Cleanup; Restart macOS Notification Center; Uninstall helper tool; Open console; Open Data Explorer.
- **Recent chats:** the most recently opened chats, with their phone number or username.

## Search (⌘K, observed live)
- One search box across chats and messages, with filter chips for Accounts, Message type, Time period and Media.
- Shows recent chats with a "Show more" link.
- A "Commands ⌘J" hint switches over to the command bar.

## Main window layout (observed live)
1. **Space bar** (far left, a narrow column of icons). From the top:
   - Inbox, Archive, and further built-in views. Their tooltips showed only ⌘1–⌘6, so the names come from static analysis.
   - One space per connected network (Signal, WhatsApp, Telegram, Google Messages, Beeper in the walk-through), on ⌘7–⌘9 and beyond.
   - Create Label, an overflow "…" button, Media, Settings (⌘,), and your avatar at the bottom.
2. **Chat list.**
   - Header: an account/inbox switcher ("Inbox ⌄"), Filter, Search Chats and New Chat.
   - Filter toggles a filter bar along the bottom ("No filters applied ×").
   - Each row: avatar with a small network badge, name, last-message preview and timestamp. Groups show stacked avatars.
3. **Thread pane:** the open conversation. Not opened in the walk-through, to avoid sending read receipts.

## Native menu bar (observed live)
- **Beeper:** About Beeper; Check for Updates…; Accounts…; Preferences (⌘,); Command Bar… (⌘J); Search… (⌘K); Services; Hide (⌘H) / Hide Others / Show All; Lock App; Logout of Beeper…; Quit (⌘Q).
- **File:** Open… (⌘O); New Chat (⌘N); Close Window; Close All; Open Chat in New Window.
- **Edit:** the standard macOS Edit menu (undo, clipboard, substitutions, speech, AutoFill, dictation, emoji).
- **View:** Hide Space Bar (⌘S); Hide Sidebar (⌘⌥S).
- **Window:** the standard macOS window menu.
- **Help:** Report a Problem (⌘⇧P); Open Beeper Help; Open Beeper.com; Follow @Beeper on X; Changelog; Privacy & Security; Keyboard Shortcuts (⌘/); Logout of Beeper…
