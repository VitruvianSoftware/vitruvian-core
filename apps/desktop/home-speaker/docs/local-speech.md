<!--
  Copyright (c) 2026 VitruvianSoftware
  SPDX-License-Identifier: MIT
-->

# Speaking on this Mac

HomeSpeaker can speak an announcement on the Mac it runs on, in a natural Siri voice, as well as
(or instead of) the Google Home speakers.

## Settings (`~/.gemini/speaker_broadcast.json`)

| Key | Type | Absent means | Meaning |
|---|---|---|---|
| `speak_home` | bool | `true` | Send announcements to the Google Home target, as today. |
| `home_cast_voice` | bool | `false` | When `speak_home` is on and `local_engine` is `gemini`, cast synthesized Gemini TTS (prebuilt or custom cloned voice) directly to the target speaker over local CastV2 + Bonjour (`_googlecast._tcp`), falling back to Google Home's native broadcast voice for `Whole Home` or if local casting is unreachable. |
| `speak_local` | bool | `false` | Also speak them on this Mac. |
| `speak_phone` | bool | `false` | Also speak them on the paired Android phone through Vitruvian Remote's Mac agent bridge. |
| `phone_pause_media` | bool | `false` | Pause media playing on the phone during a phone announcement. |
| `phone_headphones_only` | bool | `false` | Only speak on the phone when wired or Bluetooth headphones are connected. |
| `local_voice` | string | `com.apple.ttsbundle.siri_Aaron_en-US_premium` ("Aaron (Enhanced)") | `AVSpeechSynthesisVoice` identifier for the Mac. |
| `local_engine` | `apple` / `gemini` | `apple` | What speaks on this Mac (and on the phone / Cast-enabled Home speakers): a system voice, or Gemini's speech model (`gemini-3.8-flash-tts`). |
| `gemini_voice` | string | `Kore` | The Gemini prebuilt voice name (`Kore`, `Puck`, `Aoede`, `Charon`, `Zephyr`, `Fenrir`, `Leda`, `Orus`) or the ID of a custom cloned voice (`voice_…`). |
| `custom_voices` | array | `[]` | Custom cloned voices (`{id, name, created_at}`), whose audio clips live in `voices/<id>/` alongside `secrets.json`. |
| `announcement_style` | `verbatim` / `plain` / `briefing` / `casual` / `custom` | `verbatim` | How a coding agent's reply is worded. Anything but `verbatim` has a model say it in a sentence or two. |
| `custom_style_prompt` | string | empty | The instruction for `custom`; empty reads the reply as written. |
| `style_model` | `apple` / `gemini` | `apple` | Which model rewords: Apple's on-device model, or Gemini (`gemini-3.5-flash`). |

The Gemini API key is not a setting: it lives in `secrets.json` as `geminiApiKey` (0600, beside
the Slack and Beeper tokens), saved from Settings or with
`bazel run //apps/desktop/home-speaker:sync-secrets -- --gemini [--extension]`.

Absent keys keep today's behaviour exactly (home only), so an older config or an older phone app
changes nothing.

## Getting the voice

Download **Aaron (Enhanced)** once: System Settings → Accessibility → **Read & Speak** → System
voice → ⓘ → Voice → English (United States) → Aaron (Enhanced) → download (about 130 MB). The
Siri voices listed as "Voice 1…" (`com.apple.siri.natural.*`) are reserved for Apple-signed
processes and are invisible to HomeSpeaker; the "(Enhanced)" bundles are the same voices made
available to apps.

## Rules, in order

1. `enabled` false → nothing is spoken anywhere (unchanged).
2. Quiet hours → nothing is spoken anywhere, home or Mac (unchanged rule, now covering both).
3. Neither `speak_home` nor `speak_local` → nothing is spoken; the CLI prints
   "No outputs selected (home speakers and this Mac are both off)" and exits 0.
4. `pause_media` applies once when ANY output speaks: media pauses before, resumes after the
   longer of the two.
5. `announce_volume` applies to the home speakers only. The Mac speaks at the Mac's current volume.
6. Both on → both speak, started together. One failing never stops the other; the result reports
   each.
7. `speech_length` (full / summary …) and the speech-cleaning rules apply to both outputs.
8. Voice: `local_voice`; if that voice is not installed, the best installed `en-US` voice by
   quality (premium > enhanced > default), and the choice is logged. Never silence because a
   voice is missing.
9. The HomeSpeaker process started by `speaker-broadcast` must not exit before the Mac has
   finished speaking.
10. `local_engine: gemini`: the announcement is sent to Gemini and the audio it returns plays from
    memory. No key, an error, or no answer within 12 s → the `local_voice` rule above speaks it
    instead, and why is logged. A paused-media hold is kept alive while Gemini answers, then held
    for the audio's exact length.
11. `announcement_style` rewords coding agents' replies only (the Stop hook's `--announce`); chat
    messages, Quick Announce and `--say` are read as written. Gemini (with a key) is tried first
    when chosen, then Apple's model, each for at most 4 s, then the reply as written. Whatever
    comes back is cleaned for speech again. With a style on, the Stop hook always hands the whole
    reply to a detached `--announce`, since rewording can outlast Claude Code's 10 s hook limit.

## Phone (Vitruvian Remote → Apps → HomeSpeaker)

Two switches, "Home speakers" and "This Mac", plus the Mac's voice name. The Mac agent reads and
writes the three keys above in the same file, the same way it already writes `enabled`,
`pause_media` and the volume (see `apps/mobile/android-remote/macagent/homespeaker.go`).
