# Richtext

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/richtext`.

## Interface
- `[richtext.go:Kind]`
- `[richtext.go:Kinds]`
- `[richtext.go:Entity]`
- `[richtext.go:MaxEntities]`
- `[richtext.go:RoomMention]`
- `[richtext.go:ErrBadEntity]`
- `[richtext.go:Check]`
- `[richtext.go:Rendered]`
- `[richtext.go:Render]`

## Invariants
- None

## Side Effects
- [richtext.go:12]: `// Every character of the text is escaped, an attribute is only ever an escap...`
- [richtext.go:57]: `URL    string `json:"url,omitempty"`     // link: http, https or mailto only`
- [richtext.go:71]: `// pair; an unknown kind; a link whose address isn't http, https or mailto, o...`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/richtext/...`
