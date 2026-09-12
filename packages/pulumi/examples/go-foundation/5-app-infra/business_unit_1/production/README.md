# 5-app-infra: business_unit_1/production

Thin environment leaf for `business_unit_1` in the **production** environment,
mirroring upstream
`terraform-example-foundation/5-app-infra/business_unit_1/production`.

The environment identity (`production` / `p`) is **pinned in `main.go`**
(matching upstream's hardcoded `locals`), not read from stack configuration.
All resource logic lives in the shared [`../../modules`](../../modules)
packages (`env_base`, `confidential_space`, `serverless_space`); this leaf
only resolves cross-stage inputs from the 4-projects leaves and wires them in.

See the [stage README](../../README.md) for prerequisites, usage, the full
configuration reference, and outputs.

## File structure (upstream mapping)

| File                             | Mirrors upstream               | Purpose                                                            |
| -------------------------------- | ------------------------------ | ------------------------------------------------------------------ |
| `main.go`                        | `main.tf`                      | Orchestration: pinned environment consts + shared-module calls     |
| `config.go`                      | `variables.tf`                 | Stack configuration (`AppInfraConfig`)                             |
| `remote.go`                      | `remote.tf`                    | Stack References into the BU's 4-projects env + shared leaves      |
| `outputs.go`                     | `outputs.tf`                   | Stack exports (`project_id`, `region`, `serverless_service_uri`)   |
| `Pulumi.yaml`, `go.mod`          | `backend.tf`, `versions.tf`    | Engine adaptation: Pulumi project/backend + Go module pins         |
| `Pulumi.production.yaml.example` | `common.auto.tfvars`           | Engine adaptation: example stack configuration                     |
| `config_test.go`                 | —                              | Regression guard for the pinned identity + stack-reference defaults |
