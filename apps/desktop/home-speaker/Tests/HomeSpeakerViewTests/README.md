# Homespeakerviewtests

## Overview
Component package providing implementation for `apps/desktop/home-speaker/Tests/HomeSpeakerViewTests`.

## Interface
- `[ChatAppSectionSnapshotTests.swift:Snapshot]`
- `[ChatAppSectionSnapshotTests.swift:SnapshotError]`
- `[ChatAppSectionSnapshotTests.swift:ChatAppSectionSnapshotTests]`

## Invariants
- None

## Side Effects
- [ChatAppSectionSnapshotTests.swift:157]: `section(.courier, isOn: true, hasToken: true, address: "http://example.com:23...`

## Verification
- Run: `bazel test //apps/desktop/home-speaker/Tests/HomeSpeakerViewTests/...`
