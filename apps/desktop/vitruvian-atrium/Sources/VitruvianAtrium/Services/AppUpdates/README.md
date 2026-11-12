# Appupdates

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/AppUpdates`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [AppUpdateFeedLoader.swift:36]: `let session = URLSession(configuration: configuration, delegate: delegate, de...`
- [AppUpdateFeedLoader.swift:41]: `package func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,`
- [AppUpdateFeedLoader.swift:43]: `completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {`
- [AppUpdatesService.swift:97]: `package let catalogSession: URLSession`
- [AppUpdatesService.swift:101]: `package init(now: @escaping @Sendable () -> Date, catalogSession: URLSession,...`
- [AppUpdatesService.swift:112]: `return Network(now: { Date() }, catalogSession: URLSession(configuration: con...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/AppUpdates/...`
