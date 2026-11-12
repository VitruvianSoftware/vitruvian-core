# Search

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/search`.

## Interface
- `[backfill.go:BackfillBatch]`
- `[backfill.go:BackfillPause]`
- `[backfill.go:BackfillRetry]`
- `[backfill.go:RunBackfill]`
- `[search.go:Service]`
- `[search.go:New]`
- `[search.go:Section]`
- `[search.go:AllSections]`
- `[search.go:Filters]`
- `[search.go:Request]`
- `[search.go:Response]`
- `[search.go:MessagePage]`
- `[search.go:Hit]`
- `[search.go:ErrBadRequest]`
- `[search.go:BadRequestError]`
- `[search.go:Error]`
- `[search.go:Unwrap]`
- `[search.go:ErrNoSuchChat]`
- `[search.go:MaxLimit]`
- `[search.go:Query]`

## Invariants
- None

## Side Effects
- [search.go:20]: `// search.query and milestone 5's local API both call Query, and nothing here...`
- [search.go:72]: `// kinds are the message kinds a filter takes. A link is a text message holdi...`
- [search.go:101]: `// Cursor is the Next of a page of the same query, for the page after it. It ...`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/search/...`
