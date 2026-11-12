# Read aloud and per-chat announcements (Vitruvian Speaker)

Status: design, 2026-11-11.

Vitruvian Speaker already reads new Courier messages aloud (it polls Courier's local API with a token and skips muted and
low-priority chats). Courier could not control it. This adds two things.

## 1. Read Aloud

- **Where:** a message's context menu ("Read Aloud"), and a "Read aloud" button beside Copy on an AI summary in the
  AI pane, and beside Copy on a voice-note transcript.
- **What is said:** other people's message: "<Sender> says: <text>"; my own: "You said: <text>"; a voice note with a
  transcript: its transcript with the same prefix; a summary: the summary text. Trimmed to 1,000 characters. Messages
  with no text (a photo without caption, a sticker) don't offer Read Aloud.
- **How:** if Vitruvian Speaker is installed — the Vitruvian extension's
  `~/Library/Application Support/com.vitruviansoftware.atrium/Tools/dev.vitruvian.speaker/bin/tool` first, else
  `Vitruvian Speaker.app` (bundle id `com.vitruviansoftware.speaker`) in `/Applications` or `~/Applications`, never a copy
  elsewhere such as a development build — run it as `--say "<text>"` with an argument array (never a shell), off the main thread,
  with a 60-second timeout. Vitruvian Speaker speaks on whichever outputs the person turned on there (Home speakers, this
  Mac, their phone) and honours its quiet hours and snooze. Exit 1 → notice "Vitruvian Speaker couldn’t read it aloud." with
  Vitruvian Speaker's own error text when it gives one.
  If Vitruvian Speaker is not installed, speak on this Mac with the system voice (`AVSpeechSynthesizer`); a second Read
  Aloud while speaking stops the first.
- While Vitruvian Speaker is working the menu item reads "Reading Aloud…" and is disabled; nothing else blocks.

## 2. Read this chat aloud (per chat)

- **Where:** the chat's ⓘ menu and the chat info pane: "Read Aloud on Vitruvian Speaker" with three choices:
  **Default** (follow Vitruvian Speaker's settings), **Every Message**, **Never**. Shown only when Vitruvian Speaker is installed.
- **Stored** in the engine, per chat, as a new `room_prefs.read_aloud` column (`''`, `'always'`, `'never'`), with a
  migration; set through a new engine command, like low priority.
- **Exposed** on Courier's local API chat object as `"readAloud": "always" | "never"`, omitted for Default, so older
  VitruvianSpeakers ignore it.
- **Vitruvian Speaker** (`ChatAppClient.shouldAnnounce`): `never` → skip the chat; `always` → announce every message in it even
  when its Courier setting is "Direct messages and mentions". Muted chats stay silent (Courier's API doesn't return them
  to Vitruvian Speaker), and "Skip messages I sent", quiet hours and snooze still apply. The pane says: "Muted chats are
  never read aloud."
- Muting is unchanged: it still silences notifications and Vitruvian Speaker together. "Never" silences only Vitruvian Speaker.

## 3. Settings ▸ Integrations ▸ Vitruvian Speaker

A row replacing nothing: "Vitruvian Speaker" with status "Installed · reads Courier messages aloud" /
"Installed · not reading Courier (turn it on in Vitruvian Speaker)" (from `VitruvianSpeaker --state --json`, the
`courier_enabled` setting) / "Not installed · Read Aloud uses this Mac’s voice", and an "Open Vitruvian Speaker" button
when installed. `--state` is read when the pane opens, off the main thread; a failure shows "Installed".

## Acceptance criteria

1. Read Aloud on a text message with Vitruvian Speaker installed runs `--say` with "<Sender> says: <text>"; nothing else is
   sent anywhere by Courier.
2. Without Vitruvian Speaker, Read Aloud speaks on this Mac; a second one stops the first.
3. A Vitruvian Speaker failure shows a calm notice and changes nothing else.
4. A summary and a voice-note transcript have a Read aloud button.
5. A chat set to Never is skipped by Vitruvian Speaker; a chat set to Every Message is read even when Vitruvian Speaker's Courier
   setting is "Direct messages and mentions". Default behaves as before.
6. The per-chat choice survives a restart and appears in the local API only when not Default.
7. Settings ▸ Integrations shows the Vitruvian Speaker row with the right status.
