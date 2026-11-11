# Testutil

## Overview
Component package providing implementation for `packages/pulumi/library/go/internal/testutil`.

## Interface
- `[mocks.go:TrackedResource]`
- `[mocks.go:ResourceTracker]`
- `[mocks.go:NewTracker]`
- `[mocks.go:PropMap]`
- `[mocks.go:NewResource]`
- `[mocks.go:Call]`
- `[mocks.go:All]`
- `[mocks.go:ByType]`
- `[mocks.go:ByName]`
- `[mocks.go:TypeCount]`
- `[mocks.go:RequireType]`
- `[mocks.go:AssertInputEquals]`
- `[mocks.go:AssertInputBool]`
- `[mocks.go:Dump]`

## Invariants
- [mocks.go:20]: `// pulumi.WithMocks test run and exposes query helpers to assert on resource`
- [mocks.go:30]: `"github.com/stretchr/testify/assert"`
- [mocks.go:31]: `"github.com/stretchr/testify/require"`

## Side Effects
- [mocks.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [mocks.go:20]: `// pulumi.WithMocks test run and exposes query helpers to assert on resource`
- [mocks.go:108]: `// ---------- Query helpers ----------`

## Verification
- Run: `bazel test //packages/pulumi/library/go/internal/testutil/...`
