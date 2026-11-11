# Vitruviantoolclitests

## Overview
Component package providing implementation for `packages/vitruvian-sdk/Tests/VitruvianToolCLITests`.

## Interface
- `[DeskTests.swift:DeskTests]`
- `[FolderCheckTests.swift:FolderCheckTests]`
- `[FolderExamples.swift:Scratch]`
- `[FolderExamples.swift:PackageFiles]`
- `[FolderExamples.swift:FolderExample]`
- `[NewToolTests.swift:NewToolTests]`
- `[RunTests.swift:RunTests]`
- `[VersionTests.swift:VersionTests]`

## Invariants
- [NewToolTests.swift:278]: `? "require github.com/VitruvianSoftware/vitruvian-sdk/go v\(NewToolWriter.sdk...`

## Side Effects
- [DeskTests.swift:38]: `"runtime":{"kind":"external","exec":"bin/tool"}}`
- [FolderCheckTests.swift:59]: `"uses":["camera"],"runtime":{"kind":"external","exec":"bin/tool"}}`
- [NewToolTests.swift:203]: `XCTAssertEqual(try manifest(at: new.folder.appendingPathComponent("tool/vitru...`
- [NewToolTests.swift:224]: `XCTAssertEqual([written.id, written.name.english, written.runtime.exec], ["co...`
- [RunTests.swift:119]: `"runtime":{"kind":"external","exec":"bin/tool"}}`
- [RunTests.swift:128]: `"runtime":{"kind":"external","exec":"bin/tool"}}`

## Verification
- Run: `bazel test //packages/vitruvian-sdk/Tests/VitruvianToolCLITests/...`
