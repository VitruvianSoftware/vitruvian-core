# Vitruvian Speaker Shared Rulebook Test Cases

These JSON files capture the single rulebook for Vitruvian Speaker's settings catalog, choice lists, numeric limits, visibility rules, quiet hours, speaker ordering, active outputs summary, and chat monitor status belief rules.

## Who reads these files

- **Swift engine tests (now):** `//apps/desktop/vitruvian-speaker:VitruvianSpeakerTests` (`Tests/VitruvianSpeakerTests/SharedRulebookCasesTests.swift` and `Tests/VitruvianSpeakerTests/ControlsManifestTests.swift`) loads every `.json` file in this directory and checks `VitruvianSpeakerCore` (`SettingsCatalog`, `SpeakerConfig`, `SpeakerDevice`, `ChatMonitorConfig`, `ChatMonitorStatus`, `VitruvianSpeakerStateContract.supportedOperations`) against it.
- **Vitruvian Remote tests:**
  - Rust Mac helper tests: `//apps/mobile/vitruvian-remote/macagent:macagent_test` (reads `state_v1.json` and `controls.json`)
  - Kotlin state & derivation tests: `//apps/mobile/vitruvian-remote:derive_test` and `//apps/mobile/vitruvian-remote:wire_test` (read `state_v1.json` and `controls.json`)

## Files

- `choices.json` — Every choice setting's key, label, default value, and `(value, label)` options (speech length, announcement style, style model, voice engine, Gemini voices including cloned and custom active voice, chat announce mode, and Google Chat source).
- `limits.json` — Numeric limits, steps, defaults, and clamping cases for speaker volume, announcement volume, media pause margin, and chat poll interval.
- `visibility.json` — `SpeakerConfig` visibility flags (`showsHomeControls`, `showsHomeCastVoice`, `showsVoiceEngine`, `usesVoiceEngine`, `geminiSpeaks`, `showsGeminiVoice`, `showsAnnouncementStyle`, `showsStyleGeminiKey`) and `SettingsCatalog` entry visibility across configurations.
- `quiet_hours.json` — `HH:mm` parsing, same-day and overnight window evaluation, and the 48 half-hour picker options with off-grid saved times kept first.
- `speakers.json` — `SpeakerDevice.displayLine`, `SpeakerConfig.uniqueTargets()` deduplication and name sorting, and `SpeakerConfig.removeTarget(_:)` picking the next speaker by name.
- `outputs_label.json` — `SpeakerConfig.activeOutputsLabel` across output combinations and the phone's `"Your phone"` → `"This phone"` substitution.
- `chat_monitor_status.json` — `ChatMonitorStatus.believed(ownerRunning:)` clearing `isRunning` and `lastError` when the owning process is no longer running.
- `oauth_client_override.json` — Google sign-in client override rule: a blank secret with an unchanged client ID keeps the stored secret; a blank secret with a changed client ID clears it; a blank client ID clears both.
- `controls.json` — Non-catalog extension controls manifest (`id`, `label`, `via`: an `--apply` op, a CLI flag, or `helper:<name>` for something the Mac helper does itself (e.g. voice preview runs macOS `say`), `phone` `"supported"` | `"excluded"`, and `reason` when excluded). Checked by `ControlsManifestTests` in `VitruvianSpeakerTests` (every `VitruvianSpeakerStateContract.supportedOperations` name appears as `via`), `macagent_test` (every supported control is mapped by the Mac helper), and `derive_test` (every supported control has a phone control).
- `state_v1.json` — Golden `--state --json` contract v1 document produced from a fixed scratch configuration (multiple homes with one selected, multiple speakers, quiet hours, chat sources, Gemini voice engine, and installed Claude Code hook) with all secret values redacted.
