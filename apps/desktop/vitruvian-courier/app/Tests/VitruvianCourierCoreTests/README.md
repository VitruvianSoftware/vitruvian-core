# VitruvianCourierCoreTests

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/app/Tests/VitruvianCourierCoreTests`.

## Interface
- `[AIProvidersTests.swift:AIProvidersTests]`
- `[AccountsAndBridgesModelTests.swift:AccountsAndBridgesModelTests]`
- `[AppearancePreferencesTests.swift:AppearancePreferencesTests]`
- `[AttachmentDownloaderTests.swift:AttachmentDownloaderTests]`
- `[AttentionTests.swift:AttentionTests]`
- `[AudioPlayerModelTests.swift:AudioPlayerModelTests]`
- `[BlurHashDecoderTests.swift:BlurHashDecoderTests]`
- `[CalendarBridgeTests.swift:CalendarBridgeTests]`
- `[CallNoteTests.swift:CallNoteTests]`
- `[ChatFeaturesTests.swift:ChatFeaturesTests]`
- `[CommandBarModelTests.swift:CommandBarModelTests]`
- `[CommandSetTests.swift:CommandSetTests]`
- `[ComposerModelTests.swift:ComposerModelTests]`
- `[ComposerModelTests.swift:MovableClock]`
- `[ComposerModelTests.swift:FakeSender]`
- `[ComposerModelTests.swift:CallGate]`
- `[ComposerPreferencesTests.swift:ComposerPreferencesTests]`
- `[ContactsBridgeTests.swift:ContactsBridgeTests]`
- `[ConversationModelTests.swift:ConversationModelTests]`
- `[ConversationModelTests.swift:ConversationScript]`

## Invariants
- [CommandBarModelTests.swift:251]: `XCTAssertNotNil(cmd.confirmation, "\(id) must require confirmation")`
- [EngineSupervisorTests.swift:69]: `// Seven crashes in a row (a panic exits 2, which reads as a crash too); the ...`
- [EngineSupervisorTests.swift:71]: `process.printError("panic: example")`
- [EngineSupervisorTests.swift:85]: `XCTAssertEqual(supervisor.recentErrorOutput.suffix(1), ["panic: example"])`
- [ProblemReportModelTests.swift:43]: `#"panic: failed to parse "+15550100101: Alice Example" with token xoxc-123-45...`
- [ProblemReportModelTests.swift:151]: `XCTAssertTrue(joinedSupervisor.contains("panic: [redacted]"))`
- [ProblemReportModelTests.swift:172]: `#"panic: token xoxc-123-456 for "Alice Example" at /Users/alice/secret (+1555...`
- [ProtocolConformanceTests.swift:467]: `scrubbedStderr: ["panic: [redacted]"],`

## Side Effects
- [AIProvidersTests.swift:60]: `XCTAssertEqual(AIProviderKind.ollama.defaultBaseURL?.absoluteString, "http://...`
- [AIProvidersTests.swift:61]: `XCTAssertEqual(AIProviderKind.lmStudio.defaultBaseURL?.absoluteString, "http:...`
- [AIProvidersTests.swift:163]: `XCTAssertNil(listReq.url?.query, "Gemini URL must have no query parameters")`
- [AccountsAndBridgesModelTests.swift:9]: `var dockBundles: Set<String> = ["net.whatsapp.WhatsApp", "ru.keepcoder.Telegr...`
- [AudioPlayerModelTests.swift:116]: `XCTAssertNil(AudioPlayerModel.localMediaURL(for: "http://example.test/remote....`
- [CalendarBridgeTests.swift:53]: `XCTAssertNil(CalendarBridge.extractMeetingURL(from: "Insecure http://meet.goo...`
- [CalendarBridgeTests.swift:54]: `XCTAssertNil(CalendarBridge.extractMeetingURL(from: "http://zoom.us/j/12345"))`
- [CommandBarModelTests.swift:64]: `model.query = "archive"`
- [CommandBarModelTests.swift:69]: `model.query = "settings"`
- [CommandBarModelTests.swift:75]: `// Re-opening with an empty query boosts recent commands to the top of displa...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/app/Tests/VitruvianCourierCoreTests/...`
