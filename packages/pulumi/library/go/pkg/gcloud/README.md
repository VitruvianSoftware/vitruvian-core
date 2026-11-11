# gcloud

A Pulumi component for executing `gcloud` CLI commands as local commands during Pulumi operations.

**Upstream Reference:** [terraform-google-modules/gcloud/google](https://registry.terraform.io/modules/terraform-google-modules/gcloud/google)

## Overview

Wraps `gcloud` CLI commands using `@pulumi/command` for scenarios where a native Pulumi resource doesn't exist. Supports:

- Multiple commands executed sequentially
- Custom environment variables
- Single `createCmdBody` shorthand

## API Reference

### GcloudArgs

| Field           | Type                | Required | Description                                     |
| :-------------- | :------------------ | :------- | :---------------------------------------------- |
| `Commands`      | `[]string`          |          | List of gcloud commands to execute              |
| `CreateCmdBody` | `string`            |          | Single command body (alternative to `Commands`) |
| `Environment`   | `map[string]string` |          | Environment variables for command execution     |

> **Note:** Exactly one of `Commands` or `CreateCmdBody` should be provided.

### Outputs

| Field      | Type                 | Description                    |
| :--------- | :------------------- | :----------------------------- |
| `Commands` | `[]*command.Command` | The executed command resources |

## Usage

```go
cmd, err := gcloud.NewGcloud(ctx, "enable-apis", &gcloud.GcloudArgs{
    Commands: []string{
        "gcloud services enable compute.googleapis.com --project my-project",
        "gcloud services enable dns.googleapis.com --project my-project",
    },
    Environment: map[string]string{
        "CLOUDSDK_CORE_PROJECT": "my-project",
    },
})
```

## Interface
- `[gcloud.go:GcloudArgs]`
- `[gcloud.go:Gcloud]`
- `[gcloud.go:NewGcloud]`

## Invariants
- None

## Side Effects
- [gcloud.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [gcloud.go:18]: `// Mirrors: terraform-google-modules/gcloud/google (local-exec provisioner pa...`
- [gcloud.go:19]: `// In Pulumi, this uses the Command resource instead of local-exec.`

## Verification
- Run: `bazel test //packages/pulumi/library/go/pkg/gcloud/...`
