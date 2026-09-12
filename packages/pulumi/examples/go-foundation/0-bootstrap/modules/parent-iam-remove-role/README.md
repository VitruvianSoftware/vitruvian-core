# parent-iam-remove-role

Pulumi Go port of the upstream terraform-example-foundation
[`0-bootstrap/modules/parent-iam-remove-role`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/0-bootstrap/modules/parent-iam-remove-role)
module: authoritative empty IAM bindings that remove ALL members from the
given roles at project, folder or organization scope (used to strip
`roles/editor` from the bootstrap projects for least privilege).

The file layout mirrors upstream's file-per-concern split: `main.go`
(`main.tf`), `variables.go` (`variables.tf`). Upstream has no `outputs.tf`
for this module; the component exposes no outputs. `versions.tf` has no
per-module Go analog — provider pins live in the stage's `go.mod` (engine
adaptation).

## Usage

```go
_, err := parentiamremoverole.NewParentIamRemoveRole(ctx, "remove-editor-seed", &parentiamremoverole.ParentIamRemoveRoleArgs{
	ParentType: "project",
	ParentId:   seedProjectID,
	Roles:      []string{"roles/editor"},
})
```

## Inputs (`ParentIamRemoveRoleArgs`)

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| ParentType | One of `"project"`, `"folder"` or `"organization"` | `string` | n/a | yes |
| ParentId | ID of the parent resource the roles are removed from | `pulumi.StringInput` | n/a | yes |
| Roles | Roles whose members are removed (authoritative empty bindings) | `[]string` | n/a | yes |

## Outputs

None (matches upstream, which declares no outputs for this module).
