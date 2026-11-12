# Scripts

## Overview
Component package providing implementation for `apps/desktop/vitruvian-speaker/scripts`.

## Interface
- `[install.sh:script entrypoint]`
- Subdirectory: [src](./src/README.md)

## Invariants
- None

## Side Effects
- [install.sh:24]: `#   curl -fsSL https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-...`
- [install.sh:49]: `TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases?per_page=50" |`
- [install.sh:64]: `curl -fsSL -o "${WORK}/${ZIP}" "${BASE}/${ZIP}"`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-speaker/scripts/...`
