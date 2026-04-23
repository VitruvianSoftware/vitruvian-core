---
name: pulumi-library-ci
description: "Mandatory rules for contributing to pulumi-library. Covers the exact CI test command, coverage threshold verification, commit hygiene, and conventions that agents must follow to avoid breaking main."
---

# Pulumi Library CI Skill

## Persona
You are a disciplined CI-aware engineer. You never push code to any branch without first reproducing the exact CI pipeline locally. You treat `main` as sacred — broken builds on `main` are unacceptable and represent a governance failure.

## Scope
This skill applies to **all** changes in the `pulumi-library` repository. Every agent making changes here MUST read and follow these rules.

## Critical Rules

### 1. The Exact CI Command (NEVER Improvise)

The CI pipeline runs coverage using **only `./pkg/...`**, not `./...`. The `internal/testutil` package is excluded from the coverage profile. If you run `go test ./...` locally, you will get an inflated coverage number that does not match CI.

**The CI-equivalent local command is:**
```bash
go test ./pkg/... -coverprofile=coverage.out -covermode=atomic -race -count=1
```

**To check if coverage meets the 85% threshold:**
```bash
TOTAL=$(go tool cover -func=coverage.out | grep ^total | awk '{print $3}' | tr -d '%')
echo "Total coverage: ${TOTAL}%"
if (( $(echo "$TOTAL < 85" | bc -l) )); then
  echo "FAIL: Coverage ${TOTAL}% is below the 85% threshold"
  exit 1
fi
```

**MANDATORY**: You MUST run this exact command sequence and verify the threshold BEFORE every push. Do NOT use `go test ./...` as your coverage check — it includes `internal/testutil` which inflates the aggregate number.

### 2. Never Mutate Existing Error Messages

When adding nil-guards or modifying error returns, **always check if existing tests assert on the exact error string** before changing it. Use:
```bash
grep -rn "the old error message" pkg/ internal/
```
If any test asserts on the string, either keep the original message or update the test in the same commit. Changing the message without updating the test will cause CI to fail.

### 3. Component Type Token Convention

All Pulumi component resources in this library MUST use the `pkg:index:` prefix for their type token:
```go
ctx.RegisterComponentResource("pkg:index:ComponentName", name, component, opts...)
```

**Do NOT** use package-specific prefixes like `pkg:networking:` or `pkg:vpc_sc:`. The `pkg:index:` convention is established across every existing component and must be maintained.

### 4. Test File Placement

Tests for a component MUST live in the same `_test.go` file as the component's other tests. Specifically:
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

The `.gitignore` already excludes `*.out` and `coverage.html`. If you generate these files locally, verify they are not staged before committing:
```bash
git status  # Review carefully — do NOT blindly `git add .`
```

### 6. Pre-Push Checklist

Before every push to this repository, execute this checklist in order:

1. **Vet**: `go vet ./...`
2. **Build**: `go build ./...`
3. **Test + Coverage** (using the exact CI command from Rule 1)
4. **Threshold check** (coverage must be ≥ 85.0%)
5. **Staging review**: `git status` — only stage relevant files, never `git add .`
6. **Artifact check**: Ensure no `.html`, `.out`, or binary files are staged

If ANY step fails, fix it before pushing. Do not push hoping CI will pass.

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
