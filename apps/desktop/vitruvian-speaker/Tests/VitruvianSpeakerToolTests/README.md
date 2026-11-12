# Vitruvianspeakertooltests

## Overview
Component package providing implementation for `apps/desktop/vitruvian-speaker/Tests/VitruvianSpeakerToolTests`.

## Interface
- `[AccountTests.swift:AccountTests]`
- `[AgentsCloudTests.swift:AgentsCloudTests]`
- `[ChatSlackTests.swift:ChatSlackTests]`
- `[ChatSlackTests.swift:ChatCredentialsSeamTests]`
- `[ConfigTests.swift:ConfigTests]`
- `[CourierPagesTests.swift:CourierPagesTests]`
- `[DoorPagesTests.swift:DoorPagesTests]`
- `[DoorRoleTests.swift:DoorRoleTests]`
- `[DoorRoleTests.swift:ExtensionPartsTests]`
- `[DoorRoleTests.swift:ExtensionCommandLineTests]`
- `[DoorRoleTests.swift:ExtensionLocationTests]`
- `[DriverTests.swift:DriverTests]`
- `[EngineDriverTests.swift:EngineDriverTests]`
- `[VitruvianSpeakerToolTests.swift:VitruvianSpeakerToolTests]`
- `[IslandTests.swift:IslandTests]`
- `[MonitorRuntimeTests.swift:MonitorRuntimeTests]`
- `[OtherAppTests.swift:OtherAppTests]`
- `[PageIdsTests.swift:PageIdsTests]`
- `[PagesTests.swift:PagesTests]`
- `[SettingsTests.swift:SettingsTests]`

## Invariants
- None

## Side Effects
- [DoorRoleTests.swift:166]: `static var session: URLSession {`
- [DoorRoleTests.swift:169]: `return URLSession(configuration: configuration)`
- [DoorRoleTests.swift:189]: `url: url, statusCode: isChat ? 200 : 500, httpVersion: "HTTP/1.1",`
- [EngineDriverTests.swift:155]: `static var session: URLSession {`
- [EngineDriverTests.swift:158]: `return URLSession(configuration: configuration)`
- [EngineDriverTests.swift:169]: `url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-T...`
- [MonitorRuntimeTests.swift:296]: `let goodTree = event(tool, Pages.Block.beeperAddress, .submit, .string("http:...`
- [MonitorRuntimeTests.swift:297]: `XCTAssertEqual(store.config?.effectiveChatMonitor.beeperAddress, "http://127....`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-speaker/Tests/VitruvianSpeakerToolTests/...`
