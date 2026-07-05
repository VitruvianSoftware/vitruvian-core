# pkg/app — Cloud Run v2 Service Deployment

Deploys [Cloud Run v2](https://cloud.google.com/run/docs/overview/what-is-cloud-run) services with environment variables, custom service accounts, and configurable ingress.

## Overview

The `CloudRunApp` component wraps [`cloudrunv2.Service`](https://www.pulumi.com/registry/packages/gcp/api-docs/cloudrunv2/service/) to deploy containerized applications. It uses the Cloud Run **v2** API (not the legacy v1 API) for access to the latest features.

### Defaults

- **Ingress** defaults to `INGRESS_TRAFFIC_ALL` (accepts traffic from all sources)
- **Service Account** is optional; if not provided, the default Compute Engine service account is used (not recommended for production)

## API Reference

### `CloudRunAppArgs`

| Field | Type | Required | Default | Description |
|-------|------|:--------:|---------|-------------|
| `ProjectID` | `pulumi.StringInput` | ✅ | — | The GCP project ID |
| `Name` | `pulumi.StringInput` | ✅ | — | The Cloud Run service name |
| `Image` | `pulumi.StringInput` | ✅ | — | Container image URI |
| `Region` | `pulumi.StringInput` | ✅ | — | GCP region to deploy in |
| `ServiceAccount` | `pulumi.StringPtrInput` | | Compute default | Custom service account email |
| `Ingress` | `pulumi.StringPtrInput` | | `INGRESS_TRAFFIC_ALL` | Ingress setting |
| `EnvVars` | `map[string]pulumi.StringInput` | | `nil` | Environment variables |

#### Ingress Options

| Value | Description |
|-------|-------------|
| `INGRESS_TRAFFIC_ALL` | Accept connections from all sources (default) |
| `INGRESS_TRAFFIC_INTERNAL_ONLY` | Accept connections from VPC and Cloud Interconnect only |
| `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` | Accept connections from Google Cloud Load Balancing only |

### `CloudRunApp` (Output)

| Field | Type | Description |
|-------|------|-------------|
| `Service` | `*cloudrunv2.Service` | The underlying Cloud Run v2 service resource |

### Constructor

```go
func NewCloudRunApp(ctx *pulumi.Context, name string, args *CloudRunAppArgs, opts ...pulumi.ResourceOption) (*CloudRunApp, error)
```

## Examples

### Basic Deployment

```go
app, err := app.NewCloudRunApp(ctx, "hello", &app.CloudRunAppArgs{
    ProjectID: pulumi.String("my-project"),
    Name:      pulumi.String("hello-world"),
    Image:     pulumi.String("us-docker.pkg.dev/cloudrun/container/hello"),
    Region:    pulumi.String("us-central1"),
})
```

### With Custom Service Account and Environment Variables

```go
app, err := app.NewCloudRunApp(ctx, "api", &app.CloudRunAppArgs{
    ProjectID:      projectID,
    Name:           pulumi.String("my-api"),
    Image:          pulumi.String("us-docker.pkg.dev/my-project/my-repo/api:v1.2.3"),
    Region:         pulumi.String("us-central1"),
    ServiceAccount: sa.Email,
    Ingress:        pulumi.StringPtr("INGRESS_TRAFFIC_INTERNAL_ONLY"),
    EnvVars: map[string]pulumi.StringInput{
        "PROJECT_ID": projectID,
        "LOG_LEVEL":  pulumi.String("info"),
        "DB_HOST":    dbInstance.ConnectionName,
    },
})

ctx.Export("service_url", app.Service.Uri)
```

## Resource Graph

```
pkg:index:CloudRunApp ("api")
└── gcp:cloudrunv2:Service ("api")
```
