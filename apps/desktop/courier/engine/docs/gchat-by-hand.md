# Google Chat Live-Account Verification Checklist (`gchat`)

Because automated tests never touch `*.google.com`, run this 10-step checklist against a live Google account when changing `apps/desktop/courier/gchat/` or `apps/desktop/courier/engine/internal/gchat/`:

1. **Cookie Sign-In & Keychain Persistence**:
   - Open Courier -> Add Account -> Google Chat.
   - Sign in at `https://chat.google.com/` inside the ephemeral `WKWebView` sign-in sheet.
   - Verify the five required cookies (`COMPASS`, `SSID`, `SID`, `OSID`, `HSID`) are captured (`COMPASS` and `OSID` on `chat.google.com`; `SSID`, `SID`, `HSID` on `.google.com`) and the account transitions to `Connected` with your Google email/name.
   - Quit and relaunch Courier; verify the session reconnects from Keychain without re-prompting.
2. **Initial Sync (`paginated_world`)**:
   - Verify existing Direct Messages and Spaces populate in the sidebar with accurate names, avatars, unread counts, and recent messages.
3. **WebChannel Real-Time Push**:
   - Send a message from Google Chat web/mobile in both a DM and a Space.
   - Verify the message arrives in Courier within 1-2 seconds over the WebChannel stream.
4. **Rich Text & UTF-16 Annotations (Inbound & Outbound)**:
   - Send a message containing multi-codepoint emojis (`👋🏼`, `👨‍👩‍👧‍👦`), **bold**, *italic*, ~~strikethrough~~, `inline code`, a fenced code block, and an `@mention` in both directions.
   - Verify formatting spans align on the exact characters without shifting after emojis.
5. **Threaded vs Flat Spaces & Replies**:
   - In a threaded Space (`THREADING_ENABLED`), reply to a thread and start a new thread; verify `reply_in_thread` and `start_thread` route to the right `topic_id`.
   - In a DM or flat Space, quote-reply to a message and verify the quoted prefix renders cleanly.
6. **Edits, Unsend & Reactions**:
   - Edit a sent message, react with a Unicode emoji (`👍`), remove the reaction, and delete a sent message; repeat from Google Chat web/mobile and verify both directions sync.
7. **Attachments (Upload & Download)**:
   - Send a PNG image and a PDF from Courier; verify they appear in Google Chat.
   - Send an image and a file from Google Chat web/mobile; verify Courier downloads and displays them via authenticated media fetch.
8. **Typing, Read Receipts & Mute**:
   - Verify typing indicators and read watermarks (`mark_group_readstate`) sync in both directions.
   - Mute and unmute a Space in Courier; verify the mute state reflects in Google Chat.
9. **Create DM by Email & Space Metadata**:
   - Start a new DM by entering a contact's email address (`FindUsers` -> `create_dm`).
   - Rename a Space and update its description; verify existing Space `guidelines` are preserved.
10. **Diagnostics Log Scrubbing Check**:
    - Export diagnostics / inspect `courier-engine` logs after steps 1-9 and confirm zero raw cookie values (`OSID`, `COMPASS`, `SID`, `HSID`, `SSID`, `__Secure-1PSID`, `__Secure-3PSID`, `SAPISID`), XSRF tokens (`AF1Qip...`), WebChannel `gsessionid` parameters, or 21-digit Gaia IDs appear.
