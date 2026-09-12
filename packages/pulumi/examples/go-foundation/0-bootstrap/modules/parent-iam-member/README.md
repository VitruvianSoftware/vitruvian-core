# parent-iam-member

Pulumi Go port of the upstream terraform-example-foundation
[`0-bootstrap/modules/parent-iam-member`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/0-bootstrap/modules/parent-iam-member)
module: additive IAM member grants for a single member across a list of
roles, at project, folder or organization scope.

The file layout mirrors upstream's file-per-concern split: `main.go`
(`main.tf`), `variables.go` (`variables.tf`). Upstream has no `outputs.tf`
for this module; the component exposes no outputs. `versions.tf` has no
per-module Go analog — provider pins live in the stage's `go.mod` (engine
adaptation).

## Usage

```go
_, err := parentiammember.NewParentIamMember(ctx, "parent-iam-bootstrap", &parentiammember.ParentIamMemberArgs{
	ParentType: "organization",
	ParentId:   pulumi.String(orgID),
	Member:     pulumi.Sprintf("serviceAccount:%s", saEmail),
	Roles:      []string{"roles/resourcemanager.folderAdmin"},
})
```

## Inputs (`ParentIamMemberArgs`)

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| Member | IAM member the roles are granted to (e.g. `serviceAccount:...`, `group:...`) | `pulumi.StringInput` | n/a | yes |
| ParentType | One of `"project"`, `"folder"` or `"organization"` | `string` | n/a | yes |
| ParentId | ID of the parent resource the roles are granted on | `pulumi.StringInput` | n/a | yes |
| Roles | Roles granted to the member on the parent | `[]string` | n/a | yes |

## Outputs

None (matches upstream, which declares no outputs for this module).
