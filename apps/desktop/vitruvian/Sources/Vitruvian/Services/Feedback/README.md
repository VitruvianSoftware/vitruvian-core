# Feedback

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/Feedback`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [FeedbackService.swift:79]: `private let session: URLSession`
- [FeedbackService.swift:91]: `session = URLSession(configuration: configuration)`
- [FeedbackService.swift:123]: `guard data.count <= 16 * 1_024, let http = response as? HTTPURLResponse else {`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/Feedback/...`
