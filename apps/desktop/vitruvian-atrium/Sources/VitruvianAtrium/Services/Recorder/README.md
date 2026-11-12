# Recorder

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/Recorder`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [RecordingShareService.swift:24]: `private let session: URLSession`
- [RecordingShareService.swift:51]: `session = URLSession(configuration: configuration)`
- [RecordingShareService.swift:131]: `guard let http = response as? HTTPURLResponse else {`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/Recorder/...`
