# OSS Application Stage — Phase 2 (shared modules) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the reusable serverless building blocks the OSS application stage needs — a published `pkg/cloud_run` library primitive and a `serverless_space` example module (faithful peer to `env_base`/`confidential_space`) — with zero live GCP applies.

**Architecture:** Mirror the existing library-primitive + example-module split. `pkg/cloud_run` wraps `cloudrunv2.Service` as a component resource (pattern-identical to `pkg/cloud_functions`). `serverless_space` composes cloud_run + a runtime SA + secret-backed env + an optional public invoker binding, exposing `DeployServerlessSpace(ctx, name, args) (*ServerlessSpaceResult, error)` — the same contract shape as `DeployEnvBase`/`DeployConfidentialSpace`. The example's `5-app-infra` consumes the module via an in-tree `replace`; copybara rewrites that to a published pin on export.

**Tech Stack:** Go 1.26, `pulumi-gcp/sdk/v9` (`cloudrunv2`, `serviceaccount`), Pulumi component resources, Bazel + gazelle, release-please + copybara publish pipeline.

## Global Constraints

- Apache-2.0 header on every library `.go` file; MIT header on live-tree files (n/a here — all files are under `pulumi/library` or `pulumi/examples`, which use the Apache header like their siblings).
- `pulumi-gcp` **sdk v9** (`v9.29.0`), matching the rest of the library. Never sdk v7.
- The example (`pulumi/examples/go-foundation/**`) consumes library pkgs via `replace => ../../../library/go/pkg/<pkg>` (in-tree); the published pin lives only in the copybara `_GO_EXAMPLE_LIB_VERSIONS` map, applied on export.
- Every new/added/moved `.go` file requires `bazel run //:gazelle` before push (stale BUILD fails CI even when local `go test` passes).
- All builds run with `GOWORK=off`.
- Component URN class strings follow the existing convention: `pkg:index:CloudRun`.
- No live applies in this phase. Verification is build + `go test` + gazelle + example `go build`/preview-compile only.

---

## Task 1: `pkg/cloud_run` library primitive

**Files:**
- Create: `pulumi/library/go/pkg/cloud_run/cloud_run.go`
- Create: `pulumi/library/go/pkg/cloud_run/cloud_run_test.go`
- Create: `pulumi/library/go/pkg/cloud_run/BUILD`
- Create: `pulumi/library/go/pkg/cloud_run/go.mod`, `go.sum`
- Create: `pulumi/library/go/pkg/cloud_run/README.md`, `CHANGELOG.md`
- Create: `pulumi/library/go/pkg/cloud_run/release-please-config.json`

**Interfaces:**
- Produces: `cloud_run.CloudRunArgs`, `cloud_run.CloudRun{ Service *cloudrunv2.Service }`, `cloud_run.NewCloudRun(ctx, name, *CloudRunArgs, ...opts) (*CloudRun, error)`. Consumed by Task 2.

Mirror `pkg/cloud_functions` exactly (same component pattern, same file set). API:

```go
package cloud_run

type SecretEnv struct {
	Name       string            // container env var name
	SecretName pulumi.StringInput // Secret Manager secret id (short name, same project)
	Version    string            // "latest" if empty
}

type CloudRunArgs struct {
	ProjectID           pulumi.StringInput
	Region              string
	Name                string
	Image               pulumi.StringInput // digest ref: <region>-docker.pkg.dev/<proj>/<repo>/<img>@sha256:...
	ServiceAccountEmail pulumi.StringInput
	Env                 map[string]string  // plain env vars
	SecretEnv           []SecretEnv        // secret-backed env vars
	Ingress             string             // default "INGRESS_TRAFFIC_ALL"
	Port                int                // default 8080
	MinInstances        int                // default 0
	MaxInstances        int                // default 2
	CpuLimit            string             // default "1"
	MemoryLimit         string             // default "512Mi"
	Labels              map[string]string
}

type CloudRun struct {
	pulumi.ResourceState
	Service *cloudrunv2.Service
}

func NewCloudRun(ctx *pulumi.Context, name string, args *CloudRunArgs, opts ...pulumi.ResourceOption) (*CloudRun, error)
```

Implementation notes (faithful to `cloud_functions.go`):
- `RegisterComponentResource("pkg:index:CloudRun", name, component, opts...)`; underlying `cloudrunv2.NewService(ctx, name, svcArgs, pulumi.Parent(component))`.
- Build `ServiceTemplateContainerEnvArray` from `Env` (Value) and `SecretEnv` (`ValueSource.SecretKeyRef` = `ServiceTemplateContainerEnvValueSourceSecretKeyRefArgs{Secret: SecretName, Version: version}`).
- `Template.ServiceAccount = args.ServiceAccountEmail`, `Template.Scaling = {MinInstanceCount, MaxInstanceCount}`, container `Ports = [{ContainerPort: port}]`, `Resources.Limits = {"cpu": cpu, "memory": mem}`.
- `Ingress` default `INGRESS_TRAFFIC_ALL`.
- `RegisterResourceOutputs(component, pulumi.Map{"serviceName": svc.Name, "serviceUri": svc.Uri})`.
- Do NOT create IAM here (invoker binding is the module's job — matches cloud_functions leaving IAM out).

- [ ] **Step 1: Write `cloud_run_test.go`** — mirror `cloud_functions_test.go` (uses `//pulumi/library/go/internal/testutil` + `pulumi.RunErr` with mocks). Assert `NewCloudRun` returns non-nil `.Service`, applies the digest image, min/max scaling defaults, and one secret env var.

```go
package cloud_run

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewCloudRun(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cr, err := NewCloudRun(ctx, "app", &CloudRunArgs{
			ProjectID:           pulumi.String("prj-d-bu1-oss-floating-2ad6"),
			Region:              "us-west1",
			Name:                "oauth-user-inspector",
			Image:               pulumi.String("us-west1-docker.pkg.dev/p/r/app@sha256:abc"),
			ServiceAccountEmail: pulumi.String("rt@prj.iam.gserviceaccount.com"),
			Env:                 map[string]string{"SECRET_PREFIX": "OAUTH_USER_INSPECTOR_"},
			SecretEnv:           []SecretEnv{{Name: "X", SecretName: pulumi.String("s"), Version: "latest"}},
		})
		require.NoError(t, err)
		require.NotNil(t, cr.Service)
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.Mocks(0)))
	require.NoError(t, err)
}
```

- [ ] **Step 2: Run it, expect FAIL** (package doesn't compile — `NewCloudRun` undefined).
  Run: `cd pulumi/library/go/pkg/cloud_run && GOWORK=off go test ./...` → FAIL.
- [ ] **Step 3: Write `cloud_run.go`** per the API + notes above (Apache header).
- [ ] **Step 4: Create metadata files** — copy `cloud_functions/{go.mod,go.sum}` and `s/cloud_functions/cloud_run/` on the `module` line; `release-please-config.json` with `"component": "go-cloud-run"`; `README.md` + `CHANGELOG.md` (seed `## 0.1.0`); `BUILD` mirroring cloud_functions with `deps = ["@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/cloudrunv2", "@com_github_pulumi_pulumi_sdk_v3//go/pulumi"]` and the gazelle prefix comment.
- [ ] **Step 5: `GOWORK=off go mod tidy` then test** — Run: `cd pulumi/library/go/pkg/cloud_run && GOWORK=off go mod tidy && GOWORK=off go test ./... && gofmt -l .` → PASS, no gofmt output.
- [ ] **Step 6: Commit** — `feat(cloud_run): Cloud Run v2 library primitive`.

## Task 2: `serverless_space` example module

**Files:**
- Create: `pulumi/examples/go-foundation/5-app-infra/modules/serverless_space/serverless_space.go`

**Interfaces:**
- Consumes: `cloud_run.NewCloudRun` (Task 1).
- Produces: `serverless_space.ServerlessSpaceArgs`, `serverless_space.ServerlessSpaceResult{ ServiceName, ServiceUri, RuntimeSAEmail pulumi.StringOutput }`, `serverless_space.DeployServerlessSpace(ctx, name, *ServerlessSpaceArgs) (*ServerlessSpaceResult, error)`. Consumed by Task 3.

Contract mirrors `DeployConfidentialSpace`. It composes:
1. A runtime `serviceaccount.NewAccount` (`sa-<name>`, `CreateIgnoreAlreadyExists: true`) — unless `RuntimeServiceAccountEmail` is supplied (then use it, skip creation).
2. `cloud_run.NewCloudRun` with the digest image, runtime SA, `Env` (incl. the caller's `SecretPrefix` → `SECRET_PREFIX` env) and `SecretEnv`.
3. An optional `cloudrunv2.NewServiceIamMember` granting `roles/run.invoker` to `allUsers` when `PublicInvoker` is true (this is why the gcp-org DRS override / Phase-1 Task D exists).

```go
type ServerlessSpaceArgs struct {
	Env                       string
	BusinessUnit              string
	ProjectID                 pulumi.StringInput
	Region                    pulumi.StringInput // resolved to string for cloud_run.Region via Apply if needed; module takes a concrete Region string too
	RegionStr                 string
	ServiceName               string
	ImageDigest               pulumi.StringInput
	RuntimeServiceAccountEmail pulumi.StringInput // optional; created if empty
	SecretPrefix              string             // per-app partition, e.g. "OAUTH_USER_INSPECTOR_"
	Env                       map[string]string
	SecretEnv                 []cloud_run.SecretEnv
	PublicInvoker             bool
	MinInstances              int
	MaxInstances              int
}

type ServerlessSpaceResult struct {
	ServiceName    pulumi.StringOutput
	ServiceUri     pulumi.StringOutput
	RuntimeSAEmail pulumi.StringOutput
}
```

> Note the field-name collision: rename the map field to `EnvVars` (not `Env`, which is already the environment string). Use `EnvVars map[string]string`.

- [ ] **Step 1: Write `serverless_space.go`** (Apache header) implementing the composition above. Merge `SecretPrefix` into `EnvVars` as `SECRET_PREFIX` before passing to cloud_run. Guard the SA creation on `RuntimeServiceAccountEmail == nil`.
- [ ] **Step 2: Build** — Run: `cd pulumi/examples/go-foundation/5-app-infra && GOWORK=off go build ./modules/serverless_space/...`. Expect it to fail resolving `cloud_run` until Task 3 adds the require+replace; if so, proceed to Task 3 then return. (Order Task 3 Step 1 before this build.)

## Task 3: wire the example `5-app-infra`

**Files:**
- Modify: `pulumi/examples/go-foundation/5-app-infra/go.mod` (add `cloud_run` require + replace)
- Modify: `pulumi/examples/go-foundation/5-app-infra/main.go` (consume serverless_space + config field)
- Modify: `pulumi/examples/go-foundation/5-app-infra/config_test.go` (assert the new config default)
- Modify: `pulumi/examples/go-foundation/5-app-infra/Pulumi.*.yaml.example` (document `serverless_image_digest`)

- [ ] **Step 1: go.mod require + replace** — add
  `github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_run v0.1.0` to `require` and
  `replace github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_run => ../../../library/go/pkg/cloud_run`.
  Run `GOWORK=off go mod tidy`.
- [ ] **Step 2: main.go** — add `ServerlessImageDigest string` to `AppInfraConfig` (`conf.Get("serverless_image_digest")`), and after the confidential_space block add a `serverless_space.DeployServerlessSpace(ctx, "serverless-space", ...)` call, passing `appProjectID`, `appRegion`→`RegionStr` (resolve via `cfg.Region` fallback), `ImageDigest: pulumi.String(cfg.ServerlessImageDigest)`, `SecretPrefix: "EXAMPLE_APP_"`, `PublicInvoker: true`, `ServiceName: cfg.EnvCode + "-serverless-space"`. Only deploy when `cfg.ServerlessImageDigest != ""` (empty in the committed examples so the reference stack stays applyable without an image).
- [ ] **Step 3: config_test.go** — assert `cfg.ServerlessImageDigest == ""` by default.
- [ ] **Step 4: Build + test** — Run: `cd pulumi/examples/go-foundation/5-app-infra && GOWORK=off go build ./... && GOWORK=off go test ./...` → PASS.
- [ ] **Step 5: Commit** — `feat(5-app-infra): serverless_space module (peer to env_base/confidential_space)`.

## Task 4: publish + build wiring

**Files:**
- Modify: `tools/copybara/copy.bara.sky` (`_GO_EXAMPLE_LIB_VERSIONS`: add `"cloud_run": "0.1.0"`)
- Modify: top-level library `release-please-config.json` + `.release-please-manifest.json` (register `pulumi/library/go/pkg/cloud_run` → `go-cloud-run`, seed `0.1.0`) — match how `cloud_functions` is registered.
- Run: `bazel run //:gazelle` (generates/updates BUILD for the new pkg + module)

- [ ] **Step 1: Inspect how `cloud_functions` is registered** — Run: `grep -rn "cloud_functions\|go-cloud-functions" pulumi/library/go/release-please-config.json pulumi/library/go/.release-please-manifest.json tools/copybara/copy.bara.sky`. Mirror every occurrence for `cloud_run`.
- [ ] **Step 2: Add the entries** for `cloud_run` (pin map `"cloud_run": "0.1.0"`; release-please package + manifest seed `0.1.0`).
- [ ] **Step 3: gazelle** — Run: `bazel run //:gazelle`. Confirm `pulumi/library/go/pkg/cloud_run/BUILD` + the serverless_space module BUILD are generated/consistent.
- [ ] **Step 4: Full build/test** — Run:
  `bazel build //pulumi/library/go/pkg/cloud_run/... //pulumi/examples/go-foundation/5-app-infra/...` and
  `bazel test //pulumi/library/go/pkg/cloud_run/...`. Expect PASS.
- [ ] **Step 5: tidy-check parity** — Run the repo's tidy target (`bazel run //:tidy` or the documented equivalent) so `go.mod`/`go.sum` match CI's `tidy-check`.
- [ ] **Step 6: Commit + PR** — `git add` the library pkg, the module, the example wiring, copybara + release-please, BUILD files.
  PR title: `feat(oss-stage): pkg/cloud_run primitive + serverless_space module (Phase 2)`.
  Merge triggers release-please (`go-cloud-run` 0.1.0) → copybara export → mirror tag `go/pkg/cloud_run/v0.1.0`. **Gate: James (merge).** Phase 3's live app stacks pin the published `cloud_run` version.

## Self-Review

- **Spec coverage:** §3 (env_base + serverless_space peer) → Tasks 2–3; §6/§8 (digest + secret env + public invoker + SECRET_PREFIX) → Tasks 1–2; `pkg/cloud_run` (§4 item 9) → Task 1; `serverless_space` (§4 item 10) → Task 2; publish loop (dogfood pins) → Task 4.
- **Placeholder scan:** none — actual API + code notes given.
- **Type consistency:** `cloud_run.SecretEnv` used identically in Tasks 1–2; `ServerlessSpaceResult` fields (`ServiceUri`, `RuntimeSAEmail`) consumed by Task 3’s exports. Field-name collision (`Env` string vs env map) resolved by `EnvVars`.
- **Ordering caveat:** Task 3 Step 1 (go.mod replace) must precede Task 2 Step 2's build — noted inline.
