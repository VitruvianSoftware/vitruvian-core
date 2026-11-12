# Update

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/Update`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [UpdateInstallerSupport.swift:136]: `elif /usr/sbin/spctl -a -t exec "$STAGE" >/dev/null 2>&1; then`
- [UpdateInstallerSupport.swift:225]: `/// every URLSession callback. The first known fraction always counts.`
- [UpdateService.swift:80]: `private var downloadSession: URLSession?`
- [UpdateService.swift:210]: `case let .status(code): return "HTTP \(code)"`
- [UpdateService.swift:331]: `?? .failed("HTTP \(status)")`
- [UpdateShowcaseMedia.swift:59]: `if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "htt...`
- [UpdateShowcaseMedia.swift:76]: `private var session: URLSession?`
- [UpdateShowcaseMedia.swift:102]: `/// session back; `load()` passes `startDownload` when there is a video to fe...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/Update/...`
