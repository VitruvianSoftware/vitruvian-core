# Vitruviantoolprotocoltests

## Overview
Component package providing implementation for `packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests`.

## Interface
- `[EnvelopeTests.swift:EnvelopeTests]`
- `[FramingTests.swift:FramingTests]`
- `[ManifestFileTests.swift:ManifestFileTests]`
- `[ProtocolExamplesTests.swift:ProtocolExamplesTests]`
- `[ProtocolFiles.swift:ProtocolFiles]`

## Invariants
- None

## Side Effects
- [ManifestFileTests.swift:126]: `XCTAssertEqual(panel?["entry"]?["pattern"], schema["$defs"]?["runtime"]?["pro...`
- [ManifestFileTests.swift:197]: `XCTAssertEqual(problem(["runtime": .object(["kind": .string("external")])]), ...`
- [ManifestFileTests.swift:204]: `"runtime": .object(["kind": .string("bundled"), "exec": .string("../x")]),`

## Verification
- Run: `bazel test //packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/...`
