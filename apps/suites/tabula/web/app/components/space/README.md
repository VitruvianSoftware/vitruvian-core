# Space

## Overview
Component package providing implementation for `apps/suites/tabula/web/app/components/space`.

## Interface
- `[EditableSpace.tsx:EditableSpace]`
- `[SpaceView.tsx:SpaceView]`

## Invariants
- None

## Side Effects
- [SpaceView.tsx:148]: `// Non-http(s) URL: render inert so a javascript:/data: URL cannot run.`

## Verification
- Run: `bazel test //apps/suites/tabula/web/app/components/space/...`
