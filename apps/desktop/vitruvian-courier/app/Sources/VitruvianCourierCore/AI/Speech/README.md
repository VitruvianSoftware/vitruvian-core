# Speech

## Overview
Component package providing implementation for `apps/desktop/courier/app/Sources/CourierCore/AI/Speech`.

## Interface
- `[AppleSpeechEngine.swift:AppleSpeechAvailability]`
- `[AppleSpeechEngine.swift:AppleSpeechEngine]`
- `[AppleSpeechEngine.swift:LegacySpeechTasking]`
- `[AppleSpeechEngine.swift:LegacySpeechRecognizing]`
- `[SpeechEngine.swift:SpeechProvenance]`
- `[SpeechEngine.swift:SpeechUpdate]`
- `[SpeechEngine.swift:SpeechError]`
- `[SpeechEngine.swift:SpeechEngine]`
- `[SpeechEngine.swift:SpeechPermissionChecking]`
- `[SpeechEngine.swift:SystemSpeechPermissionChecker]`
- `[SpeechEngineFactory.swift:SpeechEngineResolution]`
- `[SpeechEngineFactory.swift:SpeechEngineFactory]`
- `[SpeechLanguage.swift:SpeechLanguage]`
- `[TalkToTypeModel.swift:TalkToTypePermissionNotice]`
- `[TalkToTypeModel.swift:TalkToTypeModel]`
- `[VoiceNoteTranscriptStore.swift:VoiceNoteTranscriptStore]`
- `[WhisperClient.swift:WhisperClient]`

## Invariants
- None

## Side Effects
- [WhisperClient.swift:9]: `/// never in a URL, query parameter, log, or string description.`
- [WhisperClient.swift:128]: `String(localized: "OpenAI transcription failed (HTTP \(httpResponse.statusCod...`

## Verification
- Run: `bazel test //apps/desktop/courier/app/Sources/CourierCore/AI/Speech/...`
