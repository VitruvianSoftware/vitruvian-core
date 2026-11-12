# Diskimageinstaller

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/DiskImageInstaller`.

## Interface
- Internal implementation components

## Invariants
- [DiskImageInstallerService.swift:83]: `precondition(Thread.isMainThread)`
- [DiskImageInstallerSupport.swift:69]: `// Search-path URLs do not require the directory to exist or create it.`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/DiskImageInstaller/...`
