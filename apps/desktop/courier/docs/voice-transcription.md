# Talk to Type and voice-note transcription

Status: design, 2026-11-10. Builds on [ai-providers.md](ai-providers.md).

## What the person gets

- **Talk to Type** (`⌘⇧D`, the composer's + menu, or the command bar): speak and the words go into the
  message box where the cursor is. It never sends anything.
- **Transcribe** on a voice note (its context menu, and a small "Transcribe" button next to the
  waveform): the text appears under the note.
- **Automatically transcribe incoming voice notes** (Settings, off by default): notes that someone else
  sent are transcribed when they show on screen.

## Where the speech is turned into text

Speech has its own engine, separate from the chat provider chosen in Settings ▸ AI. Speech works even
when the chat provider is Off, because the default engine never leaves the Mac.

| Setting | Engine | Leaves the Mac? |
|---|---|---|
| Whisper toggle off (default) | Apple speech recognition, on-device only | No |
| Whisper toggle on | OpenAI `POST /v1/audio/transcriptions`, model `whisper-1`, the OpenAI key from Settings ▸ AI | Yes, the audio goes to OpenAI |

- **Apple, on this Mac.** On macOS 26 and later use `SpeechAnalyzer` + `SpeechTranscriber` (download
  the language model through `AssetInventory` when needed, showing "Downloading speech model…").
  On macOS 14–25 use `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. If on-device
  recognition is not supported for the language, say so ("Speech recognition for <language> isn't
  available on this Mac.") and stop: never fall back to Apple's servers.
- **Whisper.** The toggle can only be turned on when an OpenAI key is saved; without one it is disabled
  with "Add an OpenAI key in the Cloud section to use Whisper." The key goes only in the
  `Authorization` header, never in a URL or log. The audio is sent as multipart form data.
- **Language.** "Auto-Detect" means: Apple uses the Mac's current language; Whisper gets no `language`
  field. A named language maps to a locale (Apple) or ISO-639-1 code (Whisper).

## Talk to Type, step by step

```
idle ──⌘⇧D──▶ asking permission ──granted──▶ listening ──⌘⇧D / Stop──▶ finishing ──▶ idle (text inserted)
                     │ denied                    │ Esc                     │ error
                     ▼                           ▼                         ▼
              notice + Open Settings        idle (nothing inserted)   notice, draft unchanged
```

- **Listening** shows a strip above the composer, in the same style as the AI result strip: a pulsing
  mic, a live level meter, "Listening…" (Apple shows the words so far, greyed), and a Stop button.
  "On this Mac" or "Sent to OpenAI" sits on the right.
- **Finishing**: Apple finalises; Whisper shows "Transcribing…" while it uploads.
- The final text is **inserted at the cursor**, with a space added if the character before it is not
  whitespace. The existing draft is never replaced or lost. A failure leaves the draft as it was.
- Switching chats while listening cancels it and inserts nothing.
- Permissions: microphone always; speech recognition for the Apple engine where macOS asks for it.
  Denied → calm notice "Courier needs microphone access for Talk to Type." with an
  "Open System Settings" action. Recording stops after 5 minutes with the text so far.

## Voice-note transcription

- Uses the note's local file (the same `mediaPath` playback uses). If the file isn't downloaded yet,
  say "Download the voice note first." Never fetch it just to transcribe.
- While working the note shows "Transcribing…"; then the text sits under the waveform, collapsible,
  with Copy and a provenance line "Transcribed on this Mac" or "Transcribed by OpenAI".
- Results are cached by event ID for the session, so scrolling back doesn't redo the work.
- Auto-transcribe only does notes from other people that are on screen, one at a time.

## Settings ▸ AI ▸ Talk to Type & Voice Transcription

Replace "Voice transcription isn't wired up yet" with a status line for the active engine:
"On this Mac · Ready", "On this Mac · Speech model will download on first use",
"On this Mac · Not available for <language>", or "OpenAI Whisper · audio is sent to OpenAI".

## Code shape

- `CourierCore/AI/Speech/`: `SpeechEngine` protocol (`transcribe(file:language:)` and
  `startLive(language:) -> AsyncThrowingStream<SpeechUpdate>` + `stop()`/`cancel()`),
  `AppleSpeechEngine`, `WhisperClient` (uses the existing `HTTPTransport`), `SpeechEngineFactory`
  (chooses from preferences + key store), `TalkToTypeModel` (the state machine above, owned by the
  composer), `VoiceNoteTranscriptStore` (cache + in-flight dedupe + auto-transcribe queue).
- Remove `transcribeVoiceNote` and `startTalkToType` from `AIProvider` and its conformers; speech no
  longer goes through the chat provider.
- Add `NSSpeechRecognitionUsageDescription` to `Info.plist`.

## Acceptance criteria

1. With the chat provider Off and Whisper off, `⌘⇧D` listens, shows the strip, and on Stop puts the
   spoken words into the box at the cursor without touching the rest of the draft. No audio leaves the Mac (on macOS 26 the
   one-time download of Apple's speech model is the only network use).
2. Esc while listening inserts nothing. Switching chat while listening inserts nothing.
3. Microphone denied: a calm notice with Open System Settings; the draft is unchanged.
4. The Whisper toggle is disabled until an OpenAI key is saved; with it on, the strip says
   "Sent to OpenAI" and the request carries the key only in the header.
5. Transcribe on a downloaded voice note shows its text under the note with Copy and provenance; a
   note that isn't downloaded says so and makes no request.
6. With auto-transcribe on, incoming notes on screen get transcribed once; my own notes don't.
7. Settings shows the engine status line instead of "isn't wired up yet".
8. README "AI providers" section explains both features and where audio goes.
