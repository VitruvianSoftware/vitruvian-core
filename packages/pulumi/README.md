# Pulumi

## What it gives you

Reusable [ComponentResource](https://www.pulumi.com/docs/concepts/resources/components/) building blocks for Google Cloud Platform infrastructure in Go and TypeScript (`library/`), paired with complete multi-stage enterprise GCP reference architectures (`examples/go-foundation` and `examples/ts-foundation`).

## When to use it

- Provisioning standardized, security-hardened GCP foundations, projects, VPC networks, IAM bindings, Cloud Run services, BigQuery datasets, or WIF CI/CD pipelines with Pulumi in `infrastructure/pulumi/`.

## When not to use it

- Homelab Kubernetes / k3s manifests or cluster resources; use [`//gitops`](../../gitops/README.md) (Argo CD) or `infrastructure/pulumi/platform/dev-local` instead.
- Raw one-off GCP CLI provisioning outside IaC.

## Example

From `infrastructure/pulumi/foundation/gcp-org/envs/shared/projects.go:26-63`:

```go
	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
// …
func createProject(ctx *pulumi.Context, name, projectID string, folderID pulumi.StringOutput, cfg *OrgConfig, apis []string, labels map[string]string, budget *project.BudgetConfig, billingAccount string) (pulumi.StringOutput, pulumi.StringOutput, pulumi.Resource, error) {
	// Convert labels to Pulumi StringMap
	pulumiLabels := pulumi.StringMap{}
	for k, v := range labels {
		pulumiLabels[k] = pulumi.String(v)
	}
```

## Depend on it

- Go Bazel packages: `//packages/pulumi/library/go/pkg/<component>` (e.g. `//packages/pulumi/library/go/pkg/app`, `//packages/pulumi/library/go/pkg/bootstrap`, `//packages/pulumi/library/go/pkg/project_factory`)
- TypeScript Bazel package: `//packages/pulumi/library/ts:pkg` (`@vitruviansoftware/foundation-library`)

## Constraints

- `library/` and `examples/` are Apache-2.0 licensed (mirroring to standalone public repositories via Copybara) and are exempt from the monorepo's MIT header check.
- `packages/pulumi` Go modules (`./packages/pulumi/library/go` and its 27 `pkg/*` sub-modules) are listed in the root `go.work` on purpose so `MODULE.bazel`'s `go_deps.from_file(go_work = ...)` resolves them together; the `AGENTS.md` keep-out rule applies only to `infrastructure/pulumi` Go modules.

## Subdirectories & Boundaries
- [examples](./examples/README.md): Subsystem blueprint grouping child modules under packages/pulumi/examples.
- [library](./library/README.md): Contract for packages/pulumi/library

