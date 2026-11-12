# Metrics

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/Metrics`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [DiskSampler.swift:151]: `/// What every mounted volume is asked for in one fetch. Nothing here may`
- [DiskSampler.swift:208]: `let bsdName = withUnsafeBytes(of: fs.f_mntfromname) { rawBuffer -> String? in`
- [DiskSampler.swift:216]: `let fileSystemType = withUnsafeBytes(of: fs.f_fstypename) { rawBuffer -> Stri...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/Metrics/...`
