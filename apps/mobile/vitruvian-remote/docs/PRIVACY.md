<!--
  Copyright (c) 2026 VitruvianSoftware
  SPDX-License-Identifier: MIT
-->

# Privacy

This phone talks to the Macs you add, and to Vitruvian Software's crash server if crash reports are on. It has no user account, no cloud dashboard, and no ad libraries. Crash reports are on by default and can be turned off in the app.

## The short version

- **No account and no ads.** You do not sign in, and no ad SDK is included in the app.
- **Crash reports are on by default.** If the app crashes, it sends a report to Vitruvian Software's crash server. You can switch this off in **Settings → About → Privacy**.
- **Your Macs stay yours.** Mac telemetry and control requests go only to the Macs you add, using the addresses and pairing tokens saved on your phone.
- **Bluetooth is for input.** Trackpad movement and key presses go directly to your paired Mac over Bluetooth.
- **Phone Bridge is off by default.** AI agents on your Mac cannot read texts, contacts, call history, location, notifications, or the screen until you turn Phone Bridge on and grant those permissions.
- **Alerts use your own ntfy server.** The phone does not contact ntfy; your Mac helper posts alerts only if you configure ntfy on the Mac.
- **Dictation uses your phone's speech service.** Tapping **Mic** hands audio to the system speech recognizer.
- **Donate and links open in your browser.** The app does not process payments or embed a payment SDK.

## What leaves the phone

1. **Crash reports (on by default).**
   If the app crashes, the Sentry Java SDK sends a crash report to Vitruvian Software's own crash server (`sentry-ingest.ipv1337.dev`), so we can fix it. The report sends the error and its stack trace (never other threads' stacks), the crash time, the app version, the Android version, the phone model, screen size in pixels and total memory, plus random report and trace IDs and the SDK version. Breadcrumbs, other threads, hostnames, default PII, user IP, and performance tracing are off, and reports never include your texts, contacts, files, what you type, or your Macs' addresses.

   You can turn crash reports off at any time under **Settings → About → Privacy** using the **Send crash reports** switch. Turning it off closes Sentry right away, deletes any unsent reports cached on your phone, and keeps Sentry from starting when the app opens.

2. **The Macs you add.**
   Mac telemetry, command, and Phone Bridge requests go only to the Macs you add. For each Mac you add, the phone stores its address and pairing token and connects over your local network or Tailscale.

3. **Wake on LAN.**
   When you tap **Wake on LAN** on an unreachable Mac (or when **Send Wake-on-LAN when your Mac stops answering** is enabled in **Settings**), the phone sends a Wake-on-LAN magic packet over UDP (port 9) on your local network.

4. **Bluetooth.**
   Trackpad gestures and key presses are sent to your paired Mac over Bluetooth HID, presenting the phone as a keyboard and mouse. Nothing else in the app uses Bluetooth for data.

5. **Phone Bridge (off until you turn it on).**
   Phone Bridge starts turned off. When you switch **Run Phone Bridge** on in **Settings → Phone Bridge**, the phone holds an outbound connection to your paired Mac helper so AI agents on your Mac can read texts, contacts, call history, and location, and use notifications and screen control, within the permissions you grant:
   - Reading tools (`phone.status`, `notifications.list`, `sms.list`, `contacts.search`, `calls.log`, `location.current`, `screen.screenshot`, `screen.tree`) run without an interactive prompt and are recorded in the call log.
   - Action tools (`apps.open`, `notifications.dismiss`, `screen.tap`, `screen.long_press`, `screen.swipe`, `screen.type`, `screen.key`) are refused unless you open the one-hour trust window (**Trust agents for 1 hour**).
   - Outbound tools (`sms.send`, `calls.dial`, `notifications.reply`) ask you to approve each request on the phone (waiting up to 60 seconds), unless the one-hour trust window is open.

   The Phone Bridge page displays the last 20 requests from the local audit log.

6. **Alerts through ntfy.**
   The phone does not contact any ntfy server. If you configure ntfy on your Mac (`--ntfy-url` and `--ntfy-topic`), the Mac helper sends alerts directly to that ntfy server.

7. **Dictation.**
   Tapping **Mic** opens your phone's built-in speech recognizer, the same service your keyboard uses. Vitruvian Remote does not request the microphone permission itself. Which speech app processes your voice, and whether it sends audio to a remote provider, depends on that app and your phone settings.

8. **Donate and external links.**
   Tapping **Donate** or any external link in **Settings** or **About** opens that web address in your phone's browser. Vitruvian Remote includes no payment SDK and does not handle payment details.

## What stays on the phone

Your saved Macs (addresses and pairing tokens), app preferences (theme, refresh interval, safety switches, crash-report setting, trackpad tuning, shown modules, hidden widgets, custom macros), up to 20 recent console commands, and up to 100 Phone Bridge audit entries (with text, message, body, and prompt arguments clipped to 40 characters and full summaries capped at 80 characters) are kept in the app's private storage on your phone.

## Changes to this document

This page describes how the current version of Vitruvian Remote behaves. When behavior affecting privacy changes, this document is updated alongside the code.

## Questions

If anything here is unclear, open an issue in [GitHub issues](https://github.com/VitruvianSoftware/vitruvian-remote/issues).
