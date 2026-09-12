# Monorepo Restructuring & Taxonomy Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the monorepo from an organically grown root with 38 disparate directories into a strictly partitioned 4-layer architecture (`apps/`, `packages/`, `infrastructure/`, `tools/`), fixing the compile-time inter-app boundary firewall and optimizing developer ergonomics and build isolation for large engineering teams.

**Architecture:** 
The repository is segmented into four rigid architectural layers:
- **Layer 3 (`apps/`)**: All runnable and deployable applications categorized by runtime target (`web/`, `services/`, `mcp/`, `mobile/`, `desktop/`, `cli/`, `embedded/`).
- **Layer 2 (`packages/`)**: Non-deployable shared libraries and SDKs (`ui/`, `ts/`, `pulumi/`).
- **Layer 1 (`infrastructure/`, `gitops/`)**: Cloud infrastructure as code (Pulumi), identity mappings, and Kubernetes cluster GitOps (ArgoCD).
- **Layer 0 (`tools/`)**: Monorepo build, CI, linting, code generation, and developer tooling.
A compile-time Bazel aspect patrols the layer boundary (downward-only dependencies) and an inter-app firewall strictly blocks cross-application dependencies.

**Tech Stack:** Bazel 8, rules_js, rules_go, Gazelle, TypeScript, Go 1.26, pnpm workspaces, Starlark, Copybara.

## Global Constraints

- **No Breakage of Live Mirroring:** Subtree paths in `tools/copybara/copy.bara.sky` must be updated in tandem with any component relocation to preserve one-way synchronization to standalone GitHub mirrors.
- **One Version Rule:** All package moves must preserve shared `catalog:` references in `pnpm-workspace.yaml` and module references in `go.work`.
- **Identity Isolation:** The GCP identity mapping in `infrastructure/gcp-identities.tsv` must remain authoritative and correctly keyed for all Pulumi stacks.
- **Clean Git History:** All directory moves must use `git mv` to preserve commit history.
- **Conventional Commits:** Every task must conclude with an isolated Conventional Commit.

---

### Task 1: Fix Inter-App Boundary Aspect & Package Groups

**Files:**
- Modify: `tools/lint/boundaries.bzl:24-57`
- Modify: `tools/boundaries/package_groups.bzl:23-33`
- Create: `tools/boundaries/test_boundaries.py`

**Interfaces:**
- Consumes: `tools/boundaries/package_groups.bzl` layer constants (`LAYER_APPS`, `LAYER_INFRA`, `LAYER_SHARED_PACKAGES`, `LAYER_PLATFORM_TOOLS`).
- Produces: `_get_app_name(pkg_path)` supporting multi-level `apps/<category>/<app>` paths, correctly isolating nested applications in the inter-app firewall.

- [ ] **Step 1: Write boundary test verifying nested app isolation**

Create `tools/boundaries/test_boundaries.py`:
```python
#!/usr/bin/env python3
def get_app_name(pkg_path):
    parts = pkg_path.strip("/").split("/")
    if len(parts) >= 3 and parts[0] == "apps":
        return f"{parts[1]}/{parts[2]}"
    elif len(parts) >= 2 and parts[0] == "apps":
        return parts[1]
    elif len(parts) > 0 and parts[0]:
        return parts[0]
    return ""

assert get_app_name("apps/web/gods-eye-view") == "web/gods-eye-view", "failed web app"
assert get_app_name("apps/services/tabula-api") == "services/tabula-api", "failed service app"
assert get_app_name("apps/mcp/slack") == "mcp/slack", "failed mcp app"
assert get_app_name("tabula") == "tabula", "failed top-level app"
assert get_app_name("apps/web/gods-eye-view") != get_app_name("apps/web/analytics"), "firewall collision detected"
print("Boundary app name resolution test passed.")
```

- [ ] **Step 2: Run test to verify it passes logic requirements**

Run: `python3 tools/boundaries/test_boundaries.py`
Expected: `Boundary app name resolution test passed.`

- [ ] **Step 3: Update `tools/lint/boundaries.bzl` and `tools/boundaries/package_groups.bzl`**

In `tools/lint/boundaries.bzl`:
Replace `_get_app_name`:
```python
def _get_app_name(pkg_path):
    """Extracts application name from package path (e.g. 'apps/web/gods-eye-view' -> 'web/gods-eye-view')."""
    parts = pkg_path.strip("/").split("/")
    if len(parts) >= 3 and parts[0] == "apps":
        return parts[1] + "/" + parts[2]
    elif len(parts) >= 2 and parts[0] == "apps":
        return parts[1]
    elif len(parts) > 0 and parts[0]:
        return parts[0]
    return ""
```

In `tools/boundaries/package_groups.bzl`:
Update `APPLICATION_PACKAGES`:
```python
APPLICATION_PACKAGES = [
    "//apps/...",
    "//backstage/...",
    "//devx/...",
    "//homelab/...",
    "//mcp-slack/...",
    "//mobile/...",
    "//nexus-agent/...",
    "//oauth-user-inspector/...",
    "//tabula/...",
    "//iot/...",
]
```

- [ ] **Step 4: Verify aspect compilation via Bazel**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel build //tools/boundaries/...`
Expected: exit 0

- [ ] **Step 5: Commit**

```bash
git add tools/lint/boundaries.bzl tools/boundaries/package_groups.bzl tools/boundaries/test_boundaries.py
git commit -m "fix(boundaries): support multi-segment app paths in inter-app firewall"
```

---

### Task 2: Harden OWNERS Engine Discovery Against Ephemeral Worktrees

**Files:**
- Modify: `tools/owners/engine.go:58-68`
- Test: `tools/owners/engine_test.go`

**Interfaces:**
- Consumes: `tools/owners/engine.go` directory traversal.
- Produces: Exclusion of `.claude`, `.worktrees`, `.pytest_cache`, `.ruff_cache` from OWNERS hierarchy compilation.

- [ ] **Step 1: Write unit test verifying ignored directories in OWNERS engine**

In `tools/owners/engine_test.go`:
Add test function `TestIgnoredDirectories`:
```go
func TestIgnoredDirectories(t *testing.T) {
	ignored := []string{".claude", ".worktrees", ".agents", "node_modules", "bazel-bin", "dist"}
	engine := NewEngine(".")
	for _, dir := range ignored {
		if !engine.isIgnored(dir) {
			t.Errorf("expected directory %q to be ignored", dir)
		}
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./tools/owners/... -run TestIgnoredDirectories`
Expected: FAIL with `isIgnored undefined` or missing `.claude` / `.worktrees`.

- [ ] **Step 3: Update `tools/owners/engine.go`**

In `tools/owners/engine.go`, update `ignoredDirs`:
```go
var ignoredDirs = map[string]bool{
	".git":           true,
	".agents":        true,
	".claude":        true,
	".worktrees":     true,
	".pytest_cache":  true,
	".ruff_cache":    true,
	"node_modules":   true,
	"bazel-bin":      true,
	"bazel-out":      true,
	"bazel-testlogs": true,
	"dist":           true,
	"bin":            true,
}

func (e *Engine) isIgnored(name string) bool {
	return ignoredDirs[name] || strings.HasPrefix(name, "bazel-")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./tools/owners/...`
Expected: PASS

- [ ] **Step 5: Verify CODEOWNERS clean check**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel run //tools/owners -- --check`
Expected: `.github/CODEOWNERS is up to date.`

- [ ] **Step 6: Commit**

```bash
git add tools/owners/engine.go tools/owners/engine_test.go
git commit -m "fix(owners): ignore ephemeral agent worktrees and test caches during discovery"
```

---

### Task 3: Adopt Wildcard Package Discovery in Workspaces

**Files:**
- Modify: `pnpm-workspace.yaml:22-46`

**Interfaces:**
- Consumes: Monorepo pnpm packages.
- Produces: Automatic discovery of all present and future packages under `apps/**/*` and `packages/**/*`.

- [ ] **Step 1: Update `pnpm-workspace.yaml` package patterns**

In `pnpm-workspace.yaml`, add wildcard discovery globs while keeping existing specific paths:
```yaml
packages:
  - packages/*
  - packages/**/*
  - apps/*
  - apps/**/*
  - tools
  - mcp-slack
  - nexus-agent
  - oauth-user-inspector
  - backstage/packages/*
  - tabula/shared
  - tabula/api
  - tabula/extension
  - tabula/web
  - tabula/cli
  - pulumi/library/ts
  - pulumi/library/ts/packages/*
  - pulumi/examples/ts-foundation
```

- [ ] **Step 2: Validate pnpm workspace resolution**

Run: `pnpm install --lockfile-only`
Expected: Lockfile clean without errors.

- [ ] **Step 3: Run conformance check**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel run //tools/conformance:check`
Expected: exit code 0.

- [ ] **Step 4: Commit**

```bash
git add pnpm-workspace.yaml
git commit -m "chore(pnpm): enable recursive wildcard package discovery across apps and packages"
```

---

### Task 4: Relocate Reusable Pulumi Libraries to `packages/pulumi/`

**Files:**
- Move: `pulumi/library/` -> `packages/pulumi/library/`
- Move: `pulumi/examples/` -> `packages/pulumi/examples/`
- Move: `pulumi/catalog-info.yaml` -> `packages/pulumi/catalog-info.yaml`
- Move: `pulumi/OWNERS` -> `packages/pulumi/OWNERS`
- Modify: `go.work`
- Modify: `pnpm-workspace.yaml`
- Modify: `tools/copybara/copy.bara.sky`
- Modify: `tools/boundaries/package_groups.bzl`

**Interfaces:**
- Consumes: Reusable Pulumi modules in Go and TypeScript.
- Produces: Consolidation under `packages/pulumi/` and elimination of root `pulumi/`.

- [ ] **Step 1: Relocate directories using git mv**

```bash
mkdir -p packages/pulumi
git mv pulumi/library packages/pulumi/library
git mv pulumi/examples packages/pulumi/examples
git mv pulumi/catalog-info.yaml packages/pulumi/catalog-info.yaml
git mv pulumi/OWNERS packages/pulumi/OWNERS
```

- [ ] **Step 2: Update `go.work` paths**

In `go.work`:
Replace `./pulumi/library/...` with `./packages/pulumi/library/...`.

- [ ] **Step 3: Update `pnpm-workspace.yaml` paths**

In `pnpm-workspace.yaml`:
Replace:
```yaml
  - pulumi/library/ts
  - pulumi/library/ts/packages/*
  - pulumi/examples/ts-foundation
```
With:
```yaml
  - packages/pulumi/library/ts
  - packages/pulumi/library/ts/packages/*
  - packages/pulumi/examples/ts-foundation
```

- [ ] **Step 4: Update `tools/copybara/copy.bara.sky` subtree paths**

In `tools/copybara/copy.bara.sky`:
Update `pulumi-library` and example entries to use `subtree = "packages/pulumi/library"` and `subtree = "packages/pulumi/examples/..."`.

- [ ] **Step 5: Verify Go and TypeScript builds**

Run: `go build ./packages/pulumi/library/go/...`
Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel build //packages/pulumi/...`
Expected: exit code 0.

- [ ] **Step 6: Remove empty `pulumi/` root directory**

```bash
rm -rf pulumi
[ ! -d "pulumi" ]
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(pulumi): relocate reusable libraries and examples to packages/pulumi and eliminate root pulumi/"
```

---

### Task 5: Relocate MCP and AI Agent Services to `apps/mcp/`

**Files:**
- Move: `mcp-slack/` -> `apps/mcp/slack/`
- Modify: `tools/copybara/copy.bara.sky`
- Modify: `pnpm-workspace.yaml`
- Modify: `tools/boundaries/package_groups.bzl`
- Modify: `.github/workflows/` (if referencing `mcp-slack/**`)

**Interfaces:**
- Consumes: Slack MCP server source and configurations.
- Produces: Standardized service location under `apps/mcp/slack`.

- [ ] **Step 1: Move `mcp-slack` to `apps/mcp/slack`**

```bash
mkdir -p apps/mcp
git mv mcp-slack apps/mcp/slack
```

- [ ] **Step 2: Update `copy.bara.sky`**

In `tools/copybara/copy.bara.sky`:
Update the `mcp-slack` entry in `COMPONENTS` to specify:
```python
"subtree": "apps/mcp/slack",
"repo": "mcp-slack",
```

- [ ] **Step 3: Update `apps/mcp/slack/BUILD` package name and labels**

Ensure all relative Bazel labels in `apps/mcp/slack/BUILD` resolve cleanly.

- [ ] **Step 4: Verify Bazel build and tests**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel test //apps/mcp/slack/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(apps): move mcp-slack to apps/mcp/slack and update copybara subtree"
```

---

### Task 6: Relocate Developer CLIs to `apps/cli/`

**Files:**
- Move: `devx/` -> `apps/cli/devx/`
- Move: `homelab/` -> `apps/cli/homelab/`
- Modify: `go.work`
- Modify: `tools/copybara/copy.bara.sky`
- Modify: `.github/workflows/` (workflows triggering on `devx/**` and `homelab/**`)

**Interfaces:**
- Consumes: Go CLI source trees.
- Produces: Standardized CLI category location under `apps/cli/devx` and `apps/cli/homelab`.

- [ ] **Step 1: Move `devx` and `homelab`**

```bash
mkdir -p apps/cli
git mv devx apps/cli/devx
git mv homelab apps/cli/homelab
```

- [ ] **Step 2: Update `go.work`**

In `go.work`, update module paths:
```go
use (
	.
	./apps/cli/devx
	./apps/cli/homelab
)
```

- [ ] **Step 3: Update `tools/copybara/copy.bara.sky`**

Update `devx` and `homelab` component records to set:
`subtree = "apps/cli/devx"` and `subtree = "apps/cli/homelab"`.

- [ ] **Step 4: Verify Go build and Gazelle sync**

Run: `go build ./apps/cli/devx/...`
Run: `go build ./apps/cli/homelab/...`
Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel run //:gazelle`
Expected: clean exit 0.

- [ ] **Step 5: Run tests**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel test //apps/cli/devx/... //apps/cli/homelab/...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(apps): move devx and homelab to apps/cli/ and update workspace"
```

---

### Task 7: Relocate Mobile and Embedded IoT to `apps/mobile/` and `apps/embedded/`

**Files:**
- Move: `mobile/android/remote` -> `apps/mobile/android-remote`
- Move: `iot/esp32-s3` -> `apps/embedded/esp32-s3`
- Modify: BUILD files and pipeline unit declarations
- Remove: empty `mobile/` and `iot/` root directories

**Interfaces:**
- Consumes: Android application and ESP32-S3 firmware.
- Produces: Standardized locations under `apps/mobile/` and `apps/embedded/`.

- [ ] **Step 1: Relocate directories**

```bash
mkdir -p apps/mobile apps/embedded
git mv mobile/android/remote apps/mobile/android-remote
git mv iot/esp32-s3 apps/embedded/esp32-s3
rm -rf mobile iot
```

- [ ] **Step 2: Re-run Gazelle for Bazel BUILD reconciliation**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel run //:gazelle`
Expected: clean exit 0.

- [ ] **Step 3: Verify build targets**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel build //apps/mobile/android-remote/... //apps/embedded/esp32-s3/...`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(apps): move mobile and iot applications into apps/mobile and apps/embedded"
```

---

### Task 8: Relocate Web Applications & Portals to `apps/web/`

**Files:**
- Move: `backstage/` -> `apps/web/backstage/`
- Move: `oauth-user-inspector/` -> `apps/web/oauth-user-inspector/`
- Modify: `pnpm-workspace.yaml`
- Modify: `tools/copybara/copy.bara.sky`
- Modify: `tools/boundaries/package_groups.bzl`

**Interfaces:**
- Consumes: Backstage developer portal and OAuth User Inspector.
- Produces: Clean web tier under `apps/web/`.

- [ ] **Step 1: Relocate directories**

```bash
git mv backstage apps/web/backstage
git mv oauth-user-inspector apps/web/oauth-user-inspector
```

- [ ] **Step 2: Update `pnpm-workspace.yaml` and `copy.bara.sky`**

Update `oauth-user-inspector` subtree in `copy.bara.sky` to `apps/web/oauth-user-inspector`.

- [ ] **Step 3: Verify Bazel builds and tests**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel test //apps/web/backstage/... //apps/web/oauth-user-inspector/...`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(apps): move backstage and oauth-user-inspector to apps/web/"
```

---

### Task 9: Relocate Nexus Agent to `apps/desktop/` and `apps/mcp/`

**Files:**
- Move: `nexus-agent/macos` -> `apps/desktop/nexus-agent`
- Move: `nexus-agent/src` -> `apps/mcp/nexus-agent`
- Move: `nexus-agent/` config & governance -> `apps/desktop/nexus-agent/`
- Modify: `tools/copybara/copy.bara.sky`
- Remove: root `nexus-agent/`

**Interfaces:**
- Consumes: Nexus Agent Swift desktop client and Node agent core.
- Produces: Separation of desktop client and MCP server.

- [ ] **Step 1: Relocate directories**

```bash
mkdir -p apps/desktop
git mv nexus-agent/macos apps/desktop/nexus-agent
git mv nexus-agent/src apps/mcp/nexus-agent-core
git mv nexus-agent/* apps/desktop/nexus-agent/ 2>/dev/null || true
rm -rf nexus-agent
```

- [ ] **Step 2: Update copybara and pnpm configurations**

Update `copy.bara.sky` subtree for `nexus-agent`.

- [ ] **Step 3: Verify build**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel build //apps/desktop/nexus-agent/...`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(apps): move nexus-agent components to apps/desktop and apps/mcp"
```

---

### Task 10: Enforce Root Directory Guard & Governance Locking

**Files:**
- Modify: `tools/conformance/check.sh`
- Regenerate: `.github/CODEOWNERS`
- Regenerate: `.github/workflows/presubmit.yaml`

**Interfaces:**
- Consumes: Restructured directory hierarchy.
- Produces: Automated CI check forbidding unregistered root folders, refreshed CODEOWNERS, and passing presubmits.

- [ ] **Step 1: Add root directory conformance rule to `tools/conformance/check.sh`**

In `tools/conformance/check.sh`, add a check function `check_root_directories`:
```bash
check_root_directories() {
    echo "conformance: verifying root directory governance..."
    local allowed=("apps" "packages" "infrastructure" "gitops" "tools" "docs" "architecture" "node_modules")
    local violations=()
    for dir in */ ; do
        dir="${dir%/}"
        local match=false
        for a in "${allowed[@]}"; do
            if [ "$dir" = "$a" ]; then
                match=true
                break
            fi
        done
        if [ "$match" = false ]; then
            violations+=("$dir")
        fi
    done
    if [ ${#violations[@]} -gt 0 ]; then
        echo "ERROR: Disallowed root directory detected: ${violations[*]}" >&2
        echo "All applications must live under apps/, libraries under packages/, infra under infrastructure/." >&2
        return 1
    fi
}
```

- [ ] **Step 2: Regenerate CODEOWNERS**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel run //tools/owners -- --out .github/CODEOWNERS`
Expected: `.github/CODEOWNERS` updated cleanly.

- [ ] **Step 3: Regenerate Pipeline Presubmit Matrix**

Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel run //tools/pipeline:gen`
Expected: `.github/workflows/presubmit.yaml` updated cleanly.

- [ ] **Step 4: Run full repository conformance and validation sweep**

Run: `bash tools/ci/gitops-validate.sh`
Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel run //tools/conformance:check`
Run: `export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1 && bazel run //tools/license:check`
Expected: ALL pass with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(governance): lock root directory layout in conformance check and regenerate CODEOWNERS and pipeline DAG"
```
