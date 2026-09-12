# cloud_run

A Cloud Run v2 service component for the Vitruvian pulumi-library.

Wraps a single `cloudrunv2.Service` with sensible defaults (autoscaling, CPU/memory
limits, ingress) and first-class support for secret-backed environment variables
sourced from Secret Manager. IAM (e.g. the public `allUsers` invoker binding) is
left to the caller so the primitive stays composable — the same split as
[`cloud_functions`](../cloud_functions).

## Usage

```go
import "github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_run"

cr, err := cloud_run.NewCloudRun(ctx, "app", &cloud_run.CloudRunArgs{
    ProjectID:           pulumi.String(projectID),
    Region:              "us-west1",
    Name:                "oauth-user-inspector",
    Image:               digest, // <region>-docker.pkg.dev/<proj>/<repo>/<img>@sha256:...
    ServiceAccountEmail: runtimeSA,
    Env:                 map[string]string{"SECRET_PREFIX": "OAUTH_USER_INSPECTOR_"},
    SecretEnv: []cloud_run.SecretEnv{
        {Name: "GITHUB_APP_OAUTH_CLIENT_ID", SecretName: pulumi.String("oui-github-oauth-client-id")},
    },
    MaxInstances: 3,
})
```
