# Google Chat Live-Account Verification Checklist (`gchat`)

Because automated tests never touch `*.google.com`, run this 11-step checklist from Task 12 Step 3 (`.superpowers/sdd/2026-10-30-courier-google-chat/task-12-brief.md:34-45`) against a live Google account when changing `apps/desktop/courier/gchat/` or `apps/desktop/courier/engine/internal/gchat/`:

1. **Build and Install**:
   > "1. Build and install Courier (`bazel run --config=macos-app //apps/desktop/courier/app:install`)." (`task-12-brief.md:35`)
   - Run `bazel run --config=macos-app //apps/desktop/courier/app:install` (`apps/desktop/courier/app/BUILD:173`) and launch `/Applications/Courier.app`.
2. **Cookie Sign-In & Keychain Persistence**:
   > "2. Add Network ▸ **Google Chat** ▸ verify `WKWebView` opens `https://chat.google.com/`, completes Google sign-in + 2FA, captures `COMPASS`, `OSID`, `SID`, `HSID`, `SSID`, closes automatically, and displays account as `Name (email)`." (`task-12-brief.md:36`)
   - Open Courier ▸ Add Network ▸ **Google Chat** (`apps/desktop/courier/app/Sources/Courier/SignInWindow.swift:26`, `apps/desktop/courier/engine/internal/gchat/connector.go:281`).
   - Complete Google sign-in + 2FA at `https://chat.google.com/` inside the non-persistent `WKWebView` sign-in window (`apps/desktop/courier/app/Sources/Courier/SignInWindow.swift:71`).
   - Verify the five required cookies (`COMPASS` and `OSID` scoped to `chat.google.com`; `SSID`, `SID`, and `HSID` scoped to `.google.com`) are captured (`apps/desktop/courier/gchat/src/cookies.rs:12-13`, `apps/desktop/courier/engine/internal/gchat/connector.go:290-295`), the window closes automatically (`apps/desktop/courier/app/Sources/CourierCore/CookieCollector.swift:56`), and the account displays as `Name (email)` (`apps/desktop/courier/engine/internal/gchat/connector.go:331`).
   - Quit and relaunch Courier; verify the session reconnects from the encrypted SQLite store without re-prompting.
3. **Initial Sync (`paginated_world`)**:
   > "3. Verify initial conversation list sync (`paginated_world`) populates DMs and named spaces with avatars and unread state." (`task-12-brief.md:37`)
   - Verify existing Direct Messages and named Spaces populate in the sidebar with accurate names, avatars, unread counts, and recent messages via `paginated_world` (`apps/desktop/courier/engine/internal/gchat/sync.go:178`).
4. **Single-Page Backfill (`list_messages` & `list_topics`)**:
   > "4. Open a DM and a threaded space; scroll up to verify single-page backfill (`list_messages` and `list_topics`)." (`task-12-brief.md:38`)
   - Open a DM and scroll up; verify older messages load via `/u/0/api/list_messages` (`apps/desktop/courier/engine/internal/gchat/sync.go:457-479`).
   - Open a Space and scroll up; verify older topics and replies load via `/u/0/api/list_topics` (`apps/desktop/courier/engine/internal/gchat/sync.go:525-541`).
5. **Rich Text, UTF-16 Annotations, Replies & `local_id` Deduplication**:
   > "5. Send and receive plain text, bold/italic/strikethrough/code/pre/bullet/link formatting, `@user` and `@all` mentions, inline quote-replies, and space thread replies; verify `local_id` deduplication prevents duplicate bubbles." (`task-12-brief.md:39`)
   - Send and receive plain text, **bold**, *italic*, ~~strikethrough~~, `inline code`, fenced code blocks, bulleted lists, links, `@user` and `@all` mentions (`apps/desktop/courier/gchat/src/fmt/inbound.rs:322`, `apps/desktop/courier/gchat/src/fmt/outbound.rs:346`), inline quote-replies (`apps/desktop/courier/engine/internal/gchat/media.go:79`), and space thread replies (`apps/desktop/courier/engine/internal/gchat/send.go:223`, `apps/desktop/courier/engine/internal/gchat/send.go:325`).
   - Verify formatting spans align after multi-codepoint emojis (`👋🏼`, `👨‍👩‍👧‍👦`) and `local_id` deduplication (`apps/desktop/courier/engine/internal/gchat/send.go:44`, `apps/desktop/courier/engine/internal/gchat/client.go:195`) prevents duplicate message bubbles when WebChannel echoes outbound sends.
6. **Reactions, Edits & Unsend**:
   > "6. Add and remove emoji reactions (including `\"❤️\"` with `U+FE0F` normalization), edit a sent message, and unsend a message in both directions." (`task-12-brief.md:40`)
   - Add and remove emoji reactions including `"❤️"` (`U+FE0F` variation-selector normalization in `apps/desktop/courier/engine/internal/gchat/send.go:554`, `apps/desktop/courier/engine/internal/gchat/send.go:608`, and `apps/desktop/courier/engine/internal/gchat/sync.go:749`), edit a sent message (`edit_message` in `apps/desktop/courier/engine/internal/gchat/send.go:434`), and unsend a message (`remove_message` in `apps/desktop/courier/engine/internal/gchat/send.go:503`) in both directions.
7. **Media Upload & Download via Scotty**:
   > "7. Upload and download an image, a voice note/audio file, and a general file attachment via Scotty." (`task-12-brief.md:41`)
   - Upload and download a PNG/JPEG image, a voice note/audio file, and a PDF/general file attachment via the Scotty resumable upload protocol (`apps/desktop/courier/gchat/src/media.rs:187`, `apps/desktop/courier/engine/internal/gchat/media.go:42`) and authenticated attachment download (`apps/desktop/courier/gchat/src/media.rs:380`, `apps/desktop/courier/engine/internal/gchat/media.go:56`).
8. **Read Receipts & Typing Indicators**:
   > "8. Verify read receipts and 6-second typing indicator in both directions." (`task-12-brief.md:42`)
   - Verify read watermarks (`mark_group_readstate` in `apps/desktop/courier/engine/internal/gchat/send.go:656`) and the typing indicator (`send_typing_state` in `apps/desktop/courier/engine/internal/gchat/send.go:689`) sync in both directions.
9. **Mute/Unmute, Space Rename & Description (Preserving Guidelines), and Start DM by Email**:
   > "9. Toggle mute/unmute on a chat, rename a space, update a space description (verifying existing space guidelines remain intact in the Google Chat web client), and start a new DM by email address." (`task-12-brief.md:43`)
   - Toggle mute and unmute on a chat (`update_group_notification_settings` in `apps/desktop/courier/engine/internal/gchat/rooms.go:380`).
   - Rename a Space (`update_group` in `apps/desktop/courier/engine/internal/gchat/rooms.go:275`) and update a Space description (`get_group` followed by `update_group` in `apps/desktop/courier/engine/internal/gchat/rooms.go:308`), verifying in the Google Chat web client that existing Space `guidelines` remain intact.
   - Start a new DM from Courier's New Message sheet by entering a contact's email address (`StartNewChatDraft` in `apps/desktop/courier/app/Sources/CourierCore/InboxModel.swift:2148` ▸ `people.resolve` ▸ `/u/0/api/create_dm` with `Invitees` in `apps/desktop/courier/engine/internal/gchat/rooms.go:104`).
10. **Mac Sleep/Wake (>2 Minutes) Reconnect & Catch-Up Sync**:
    > "10. Put the Mac to sleep for >2 minutes, wake it, and verify WebChannel reconnects and runs `catch_up_user` / `catch_up_group` without missing messages sent while asleep." (`task-12-brief.md:44`)
    - Put the Mac to sleep for more than 2 minutes, send messages to a DM and a Space from another device while asleep, wake the Mac, and verify the WebChannel stream reconnects (`apps/desktop/courier/gchat/src/channel.rs:378`, `apps/desktop/courier/gchat/src/channel.rs:995`) and `catch_up_user` / `catch_up_group` (`apps/desktop/courier/engine/internal/gchat/sync.go:603`, `apps/desktop/courier/engine/internal/gchat/sync.go:665`) replays the missed messages without gaps.
11. **Scrubbed Log Inspection (`~/Library/Logs/Courier/`)**:
    > "11. Inspect `~/Library/Logs/Courier/` and confirm zero cookie values, XSRF tokens, Gaia IDs, emails, or message bodies appear in the scrubbed logs." (`task-12-brief.md:45`)
    - Inspect `~/Library/Logs/Courier/` and export diagnostics after steps 1–10; confirm `logscrub` (`apps/desktop/courier/engine/internal/logscrub/logscrub.go:280-287`) redacts all cookie values (`COMPASS`, `OSID`, `SID`, `HSID`, `SSID`, `APISID`, `SAPISID`, `__Secure-1PSID`, `__Secure-3PSID`), XSRF tokens (`AF1Qip...`), WebChannel `gsessionid`/`SID` query strings, 21-digit Gaia IDs, email addresses, and message bodies.
