# Notch

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/Notch`.

## Interface
- Internal implementation components

## Invariants
- [NotchMenuBarSpace.swift:44]: `// AX may describe only another display's menu bar. Require an item on`

## Side Effects
- [NotchAccessoryService.swift:13]: `/// Who connects and disconnects. Every Bluetooth query runs on the`
- [NotchBrowserArtwork.swift:35]: `private var downloadSession: URLSession?`
- [NotchBrowserArtwork.swift:66]: `var previous: URLSession?`
- [NotchBrowserArtwork.swift:93]: `let previous = lock.withLock { () -> URLSession? in`
- [NotchBrowserArtworkSupport.swift:60]: `"net.waterfox.waterfox": "Waterfox/Profiles",`
- [NotchBrowserArtworkSupport.swift:237]: `guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),`
- [NotchLyricsService.swift:485]: `completion: @escaping @Sendable (NotchLyricsDownloadResult) -> Void) -> URLSe...`
- [NotchLyricsService.swift:500]: `let session = URLSession(configuration: configuration, delegate: delegate, de...`
- [NotchLyricsSupport.swift:186]: `/// exact query. Accept those cosmetic differences without relaxing its album`
- [NotchLyricsSupport.swift:336]: `/// One broader query, only after precise searches have no eligible result.`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/Notch/...`
