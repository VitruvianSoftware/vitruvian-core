# Vitruvianspeakerviewtests

## Overview
Component package providing implementation for `apps/desktop/vitruvian-speaker/Tests/VitruvianSpeakerViewTests`.

## Interface
- `[ChatAppSectionSnapshotTests.swift:Snapshot]`
- `[ChatAppSectionSnapshotTests.swift:SnapshotError]`
- `[ChatAppSectionSnapshotTests.swift:ChatAppSectionSnapshotTests]`

## Invariants
- None

## Side Effects
- [ChatAppSectionSnapshotTests.swift:157]: `section(.courier, isOn: true, hasToken: true, address: "http://example.com:23...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-speaker/Tests/VitruvianSpeakerViewTests/...`
