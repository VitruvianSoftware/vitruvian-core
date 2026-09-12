# serverless_space

Deploys a serverless (Cloud Run) workload into an environment project: a
runtime service account, a Cloud Run service pinned to a promoted image
digest (with optional blue-green revision/traffic control), a per-app
`SECRET_PREFIX` partition, and an optional public (`allUsers`) invoker
binding.

> **No upstream counterpart.** `serverless_space` is **our addition** to the
> upstream `terraform-example-foundation/5-app-infra` module set — upstream
> ships only `env_base` and `confidential_space`. It is the serverless peer
> to those modules; there is no upstream Terraform module to reference. The
> file layout (`main.go`/`variables.go`/`outputs.go`) follows the same
> per-concern convention as the upstream-mirrored modules for consistency.

## Notes

- The public invoker binding depends on the environment project carrying a
  Domain Restricted Sharing override
  (`constraints/iam.allowedPolicyMemberDomains` AllowAll) so that `allUsers`
  may be granted `run.invoker` — see the gcp-org stage.
- The workload is digest-gated by the calling leaf: it is only deployed when
  a promoted image digest is configured, so the reference stack stays
  applyable without a build.

## File structure

| File           | Purpose                                        |
| -------------- | ----------------------------------------------- |
| `main.go`      | Resource logic (`DeployServerlessSpace`)        |
| `variables.go` | Input surface (`ServerlessSpaceArgs`)           |
| `outputs.go`   | Output surface (`ServerlessSpaceResult`)        |

## Inputs (`ServerlessSpaceArgs`)

| Name                         | Description                                                                       | Required | Default                  |
| ---------------------------- | ---------------------------------------------------------------------------------- | :------: | ------------------------ |
| `Env`                        | The environment the workload belongs to                                            |   yes    | n/a                      |
| `BusinessUnit`               | The business unit code (e.g. `bu1`)                                                |   yes    | n/a                      |
| `ProjectID`                  | Target project (resolved from the 4-projects Stack Reference)                      |   yes    | n/a                      |
| `Region`                     | Region to deploy into                                                              |   yes    | n/a                      |
| `ServiceName`                | Cloud Run service name                                                             |          | `"serverless-space"`     |
| `ImageDigest`                | Promoted container image digest to deploy                                          |   yes    | n/a                      |
| `RuntimeServiceAccountEmail` | Existing runtime SA; when unset a per-service SA (`sa-<ServiceName>`) is created   |          | created                  |
| `SecretPrefix`               | Per-app secret env-var name partition, surfaced as `SECRET_PREFIX`                 |          | —                        |
| `EnvVars`                    | Plain environment variables                                                        |          | —                        |
| `SecretEnv`                  | Secret-backed environment variables                                                |          | —                        |
| `PublicInvoker`              | Grant `allUsers` `run.invoker` (requires the DRS override)                         |          | `false`                  |
| `MinInstances`/`MaxInstances`| Autoscaling bounds                                                                 |          | `0`                      |
| `RevisionSuffix`             | Blue-green: names the new revision `<ServiceName>-<Env>-<RevisionSuffix>`          |          | — (100%-to-latest)       |
| `StableRevision`             | Blue-green: revision keeping 100% traffic until promotion                          |          | —                        |
| `Promote`                    | Blue-green: route 100% traffic to the new revision                                 |          | `false`                  |

## Outputs (`ServerlessSpaceResult`)

| Name             | Description                       |
| ---------------- | --------------------------------- |
| `ServiceName`    | Cloud Run service name            |
| `ServiceUri`     | Cloud Run service URI             |
| `RuntimeSAEmail` | Runtime service account email     |
