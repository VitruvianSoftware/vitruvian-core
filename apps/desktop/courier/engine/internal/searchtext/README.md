# Searchtext

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/searchtext`.

## Interface
- `[searchtext.go:MaxQueryRunes]`
- `[searchtext.go:MaxTerms]`
- `[searchtext.go:MaxIndexRunes]`
- `[searchtext.go:Normalize]`
- `[searchtext.go:Words]`
- `[searchtext.go:Term]`
- `[searchtext.go:Parse]`
- `[searchtext.go:ParseName]`
- `[searchtext.go:Letters]`
- `[searchtext.go:MatchAll]`
- `[searchtext.go:MatchAny]`
- `[searchtext.go:Range]`
- `[searchtext.go:Snippet]`

## Invariants
- [searchtext.go:283]: `panic("searchtext: bad column name " + column)`

## Side Effects
- [searchtext.go:4]: `// Package searchtext prepares text for the search index and turns what a per...`
- [searchtext.go:8]: `// queries both go through Normalize first. A query is never passed to FTS5 a...`
- [searchtext.go:23]: `// MaxQueryRunes is how much of a query is read; the rest of a longer query i...`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/searchtext/...`
