# Media

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/media`.

## Interface
- `[blurhash.go:EncodeBlurHash]`
- `[inspect.go:MaxInspectBytes]`
- `[inspect.go:Metadata]`
- `[inspect.go:InspectImage]`
- `[media.go:ErrMissing]`
- `[media.go:ErrInvalidHash]`
- `[media.go:DefaultMaxMemoryBytes]`
- `[media.go:Store]`
- `[media.go:Path]`
- `[media.go:Put]`
- `[media.go:PutStream]`
- `[media.go:Read]`
- `[media.go:DeleteUnlessPutSince]`
- `[media.go:Delete]`

## Invariants
- [media.go:45]: `// refused, so a hostile name can neither panic nor escape Dir.`

## Side Effects
- [media.go:68]: `defer os.Remove(tmp.Name())`
- [media.go:117]: `if errors.Is(err, fs.ErrNotExist) {`
- [media.go:127]: `if errors.Is(err, fs.ErrNotExist) {`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/media/...`
