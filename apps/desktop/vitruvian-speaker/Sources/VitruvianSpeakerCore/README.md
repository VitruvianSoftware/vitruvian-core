# Vitruvianspeakercore

## Overview
Component package providing implementation for `apps/desktop/vitruvian-speaker/Sources/VitruvianSpeakerCore`.

## Interface
- `[AgentHooks.swift:AntigravityHook]`
- `[AgentHooks.swift:OpenCodeHook]`
- `[AgentIntegration.swift:CodingAgent]`
- `[AgentIntegration.swift:AgentIntegration]`
- `[AgentIntegration.swift:LoginItem]`
- `[AgentPlugins.swift:AgentPlugins]`
- `[AnnouncementStylist.swift:AnnouncementStyling]`
- `[AnnouncementStylist.swift:StyleRewriting]`
- `[AnnouncementStylist.swift:StyleRewriteError]`
- `[AnnouncementStylist.swift:AnnouncementStylist]`
- `[AnnouncementStylist.swift:GeminiStyleRewriter]`
- `[AnnouncementStylist.swift:GeminiAPI]`
- `[AnnouncementStylist.swift:GeminiAPIError]`
- `[AnnouncementStylist.swift:AppleStyleRewriter]`
- `[Announcer.swift:OutputStatus]`
- `[Announcer.swift:AnnounceOutcome]`
- `[Announcer.swift:HomeBroadcasting]`
- `[Announcer.swift:LocalSpeaking]`
- `[Announcer.swift:MediaPausing]`
- `[Announcer.swift:SharedMediaPause]`

## Invariants
- [MainThreadLoop.swift:36]: `precondition(Thread.isMainThread, "MainThreadLoop.run() must be called on the...`

## Side Effects
- [AgentPlugins.swift:102]: `import { spawn } from "node:child_process"`
- [AgentPlugins.swift:123]: `const child = spawn(PROGRAM, ["\(OpenCodeHook.argument)"], {`
- [AnnouncementStylist.swift:216]: `public init(send: @escaping Send = { try await URLSession.shared.data(for: $0...`
- [AnnouncementStylist.swift:265]: `guard let http = response as? HTTPURLResponse else { return }`
- [AnnouncementStylist.swift:266]: `guard (200..<300).contains(http.statusCode) else {`
- [Announcer.swift:143]: `session === URLSession.shared ? AnnouncementTiming.seconds(for: text, extra: ...`
- [CastSpeaker.swift:34]: `//   3. serve the WAV from memory on a one-off HTTP URL on this Mac, at the`
- [CastSpeaker.swift:454]: `/// A one-off HTTP server for one WAV, at one unguessable path, on every`
- [CastSpeaker.swift:459]: `private let queue = DispatchQueue(label: "com.vitruviansoftware.speaker.c...`
- [ChatApp.swift:48]: `/// App Transport Security refuses plain HTTP to an address written as`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-speaker/Sources/VitruvianSpeakerCore/...`
