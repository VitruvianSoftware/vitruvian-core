# Home Speaker Shared Rulebook Test Cases

These JSON files capture the single rulebook for Home Speaker's settings catalog, choice lists, numeric limits, visibility rules, quiet hours, speaker ordering, active outputs summary, and chat monitor status belief rules.

## Who reads these files

- **Swift engine tests (now):** `//apps/desktop/home-speaker:HomeSpeakerTests` (`Tests/HomeSpeakerTests/SharedRulebookCasesTests.swift`) loads every `.json` file in this directory and checks `HomeSpeakerCore` (`SettingsCatalog`, `SpeakerConfig`, `SpeakerDevice`, `ChatMonitorConfig`, `ChatMonitorStatus`) against it.
- **Android remote tests (follow-up PRs):**
  - Rust Mac helper tests: `//apps/mobile/android-remote/macagent:macagent_test`
  - Kotlin state & derivation tests: `//apps/mobile/android-remote:derive_test` and `//apps/mobile/android-remote:wire_test`

## Files

- `choices.json` — Every choice setting's key, label, default value, and `(value, label)` options (speech length, announcement style, style model, voice engine, Gemini voices including cloned and custom active voice, chat announce mode, and Google Chat source).
- `limits.json` — Numeric limits, steps, defaults, and clamping cases for speaker volume, announcement volume, media pause margin, and chat poll interval.
- `visibility.json` — `SpeakerConfig` visibility flags (`showsHomeControls`, `showsHomeCastVoice`, `showsVoiceEngine`, `usesVoiceEngine`, `geminiSpeaks`, `showsGeminiVoice`, `showsAnnouncementStyle`, `showsStyleGeminiKey`) and `SettingsCatalog` entry visibility across configurations.
- `quiet_hours.json` — `HH:mm` parsing, same-day and overnight window evaluation, and the 48 half-hour picker options with off-grid saved times kept first.
- `speakers.json` — `SpeakerDevice.displayLine`, `SpeakerConfig.uniqueTargets()` deduplication and name sorting, and `SpeakerConfig.removeTarget(_:)` picking the next speaker by name.
- `outputs_label.json` — `SpeakerConfig.activeOutputsLabel` across output combinations and the phone's `"Your phone"` → `"This phone"` substitution.
- `chat_monitor_status.json` — `ChatMonitorStatus.believed(ownerRunning:)` clearing `isRunning` and `lastError` when the owning process is no longer running.
- `oauth_client_override.json` — Google sign-in client override rule: a blank secret with an unchanged client ID keeps the stored secret; a blank secret with a changed client ID clears it; a blank client ID clears both.
