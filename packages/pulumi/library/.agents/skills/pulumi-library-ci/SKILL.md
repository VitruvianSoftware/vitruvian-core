---
name: pulumi-library-ci
description: "Mandatory rules for contributing to packages/pulumi/library. Covers Bazel test commands across the multi-module go/ layout, component type token conventions, commit hygiene, and nil-guard standards."
---

# Pulumi Library CI Skill

## Persona

You are a disciplined CI-aware engineer. You verify builds and tests through the repository's Bazel targets before committing. You treat `main` as sacred — broken builds on `main` are unacceptable.

## Scope

This skill applies to **all** changes under `packages/pulumi/library/` (`go/` for Go component modules, `ts/` for TypeScript packages). Every agent making changes here MUST read and follow these rules.

## Critical Rules

### 1. Multi-Module `go/` Layout & Bazel Test Commands

The Go code lives under `go/` with 29 separate `go.mod` files (one per component under `go/pkg/*`, plus `go/` and `go/internal/testutil`), not a single root `go.mod`. In `vitruvian-core`, raw `go test` and raw `git push` are forbidden by agent-guard — run everything through Bazel:

```bash
# Run all Go component tests (and build)
bazel test //packages/pulumi/library/go/...

# Run a single component's tests (e.g. iam)
bazel test //packages/pulumi/library/go/pkg/iam:iam_test
```

TypeScript packages live under `ts/packages/` (`ts/`). Check `ts/vitest.config.ts` and `.github/workflows/release.yml` for release packaging details.

### 2. Never Mutate Existing Error Messages

When adding nil-guards or modifying error returns, **always check if existing tests assert on the exact error string** before changing it. Use:

```bash
grep -rn "the old error message" packages/pulumi/library/go/pkg/ packages/pulumi/library/go/internal/
```

If any test asserts on the string, either keep the original message or update the test in the same commit.

### 3. Component Type Token Convention

- General/single-component packages use `pkg:index:<ComponentName>`:

```go
ctx.RegisterComponentResource("pkg:index:ComponentName", name, component, opts...)
```

- Domain- or scope-isolated packages deliberately use per-type tokens for state isolation and blast-radius separation (see `go/pkg/iam/README.md` for why):
  - `pkg:iam:<Scope>IAM{Member,Binding}` (`go/pkg/iam/`)
  - `pkg:cicd:<Component>` (`go/pkg/cicd/`)
  - `pkg:logging:<Component>` (`go/pkg/centralized_logging/`)
  - `pkg:storage:<Component>` (`go/pkg/cloud_storage/`)
  - `vitruvian:security:CAIMonitoring` (`go/pkg/cai_monitoring/`)

Match the existing package's token prefix when adding or updating constructors within that package.

### 4. Test File Placement

Tests for a component MUST live in the same `_test.go` file as the component's other tests. Under `go/pkg/network/`, for example:

- Tests for `dns.go` go in `dns_test.go`
- Tests for `firewall.go` go in `firewall_test.go`
- Tests for `hierarchical_firewall.go` go in `hierarchical_firewall_test.go`
- Tests for `transitivity.go` go alongside existing transitivity tests (currently in `psc_test.go`)

**Do NOT** dump unrelated tests into `networking_test.go` just because it's in the same package. Each component's tests belong with that component's test file.

### 5. Never Commit Build Artifacts

The following files are generated artifacts and MUST NOT be committed:

- `coverage.html`
- `coverage.out`
- `*.test` binaries
- Any file matching `*.out`

### 6. Pre-Commit Checklist

Before committing and opening a PR:

1. **Build**: `bazel build //packages/pulumi/library/go/...`
2. **Test**: `bazel test //packages/pulumi/library/go/...`
3. **Format**: `bazel run //tools/format`
4. **Commit & Push**: Use `bazel run //tools/git:commit -- --agent <you> ...` and `bazel run //tools/git:push -- --agent <you>` (and review `git status` so no `.out`/`.html`/binary artifacts are staged)

### 7. Nil-Guard Standard

Every exported component constructor MUST have a nil-args guard as the first statement:

```go
func NewComponentName(ctx *pulumi.Context, name string, args *ComponentArgs, opts ...pulumi.ResourceOption) (*Component, error) {
    if args == nil {
        return nil, fmt.Errorf("args is required")
    }
    // ...
}
```

Every nil-guard MUST have a corresponding test:

```go
func TestNewComponentName_NilArgs(t *testing.T) {
    err := pulumi.RunErr(func(ctx *pulumi.Context) error {
        _, err := NewComponentName(ctx, "test", nil)
        require.Error(t, err)
        return nil
    }, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
    require.NoError(t, err)
}
```
