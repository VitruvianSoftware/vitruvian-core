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
| `speak_local` | bool | `false` | Also speak them on this Mac. |
| `local_voice` | string | `com.apple.ttsbundle.siri_Aaron_en-US_premium` ("Aaron (Enhanced)") | `AVSpeechSynthesisVoice` identifier for the Mac. |

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

## Phone (Vitruvian Remote → Apps → HomeSpeaker)

Two switches, "Home speakers" and "This Mac", plus the Mac's voice name. The Mac agent reads and
writes the three keys above in the same file, the same way it already writes `enabled`,
`pause_media` and the volume (see `apps/mobile/android-remote/macagent/homespeaker.go`).
