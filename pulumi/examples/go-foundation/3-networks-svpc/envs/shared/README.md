# 3-networks-svpc / envs / shared

Pulumi (Go) port of upstream terraform-example-foundation
[`3-networks-svpc/envs/shared`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-svpc/envs/shared)
— the shared root of the networks stage. It pins the shared identity and
deploys the shared/global network resources: the org/folder-level
hierarchical firewall policy. The per-environment Shared VPCs live in the
sibling `envs/{development,nonproduction,production}` leaves.

## File map (upstream → this port)

| Upstream | Here | Notes |
|---|---|---|
| — | `main.go` | Go program entrypoint (engine adaptation; upstream has no `main.tf` here) |
| `hierarchical_firewall.tf` | `hierarchical_firewall.go` | org/folder hierarchical firewall policy |
| `variables.tf` | `config.go` | stack config (engine adaptation: tfvars → `Pulumi.<stack>.yaml`) |
| `outputs.tf` | `outputs.go` | no exports declared in this port (documented there) |
| `remote.tf` | `remote.go` | parent taken from stack config (documented there) |
| `backend.tf`, `providers.tf`, `versions.tf` | `Pulumi.yaml`, `go.mod` | engine adaptation |
