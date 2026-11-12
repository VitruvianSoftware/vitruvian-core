# Quicktools

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/QuickTools`.

## Interface
- Internal implementation components

## Invariants
- [MicMuteService.swift:85]: `/// sweep is still running must re-assert the request in flight, never the`
- [MicMuteService.swift:101]: `/// thread this arrives on, so it only asks the main thread to re-assert`
- [ScreenCaptureService.swift:27]: `precondition(availableTools.contains(selectedTool))`

## Side Effects
- [ScreenshotShareService.swift:24]: `private let session: URLSession`
- [ScreenshotShareService.swift:51]: `session = URLSession(configuration: configuration)`
- [ScreenshotShareService.swift:127]: `guard let http = response as? HTTPURLResponse else {`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/QuickTools/...`
