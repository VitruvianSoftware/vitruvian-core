# Vitruvianspeakertests

## Overview
Component package providing implementation for `apps/desktop/vitruvian-speaker/Tests/VitruvianSpeakerTests`.

## Interface
- `[CastSpeakerTests.swift:FakeCast]`
- `[ChatCredentialsTests.swift:GatedChatMonitor]`
- `[LocalSpeechTests.swift:EventLog]`
- `[LocalSpeechTests.swift:FakeHome]`
- `[LocalSpeechTests.swift:FakeLocal]`
- `[LocalSpeechTests.swift:FakeMedia]`
- `[LocalSpeechTests.swift:FakePhone]`
- `[LocalSpeechTests.swift:Boom]`
- `[LocalSpeechTests.swift:FakeSynth]`
- `[MediaPauseTests.swift:FakeRunner]`
- `[MediaPauseTests.swift:SlowTabs]`
- `[MediaPauseTests.swift:FakeNowPlaying]`
- `[SettingsActionsTests.swift:SettingsActionsTests]`
- `[SharedFoundationTests.swift:MemoryFiles]`
- `[SharedFoundationTests.swift:FakeChatMonitor]`
- `[SharedFoundationTests.swift:FakeAuth]`
- `[SharedFoundationTests.swift:FakeHomes]`
- `[SharedFoundationTests.swift:FakeLoginItem]`
- `[SharedFoundationTests.swift:Saved]`
- `[SharedFoundationTests.swift:Posted]`

## Invariants
- [AgentPluginTests.swift:486]: `let lease = try #require(SpeechLock.tryAcquire(at: speechLockURL))`
- [AnnouncementStyleTests.swift:106]: `let json = try #require(JSONSerialization.jsonObject(with: data) as? [String:...`
- [AnnouncementStyleTests.swift:198]: `let call = try #require(apple.calls.first)`
- [AnnouncementStyleTests.swift:205]: `let plain = try #require(AnnouncementStylist.instructions(for: styled(.plain)))`
- [AppRoleTests.swift:140]: `try #require(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the...`
- [AppRoleTests.swift:372]: `let profile = try #require(AppStartup.extensionProfile(record: rig.door.read()))`
- [AppRoleTests.swift:373]: `let lockURL = try #require(profile.liveLockURL)`
- [BeeperClientTests.swift:379]: `try #require(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the...`
- [BeeperClientTests.swift:382]: `try #require(standInBase.port != 23373 && ChatAppClient.isLoopback(standInBase))`
- [CastSpeakerTests.swift:113]: `let duration = try #require(GeminiSpeaker.duration(ofWAV: Data(fixed)))`

## Side Effects
- [AppRoleTests.swift:52]: `static var session: URLSession {`
- [AppRoleTests.swift:55]: `return URLSession(configuration: configuration)`
- [AppRoleTests.swift:78]: `let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersio...`
- [BeeperClientTests.swift:43]: `private let standInBase = URL(string: "http://localhost:47999")!`
- [BeeperClientTests.swift:112]: `let query: [String: String]`
- [BeeperClientTests.swift:162]: `var polls: [Request] { searches.filter { $0.query["cursor"] == nil } }`
- [CastSpeakerTests.swift:153]: `let ok = CastAudioServer.response(forRequest: "GET /announce-x.wav HTTP/1.1\r...`
- [CastSpeakerTests.swift:156]: `#expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))`
- [CastSpeakerTests.swift:162]: `let head = CastAudioServer.response(forRequest: "HEAD /announce-x.wav?x=1 HTT...`
- [ChatMonitorTests.swift:34]: `private let standInBeeperBase = URL(string: "http://localhost:47998")!`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-speaker/Tests/VitruvianSpeakerTests/...`
