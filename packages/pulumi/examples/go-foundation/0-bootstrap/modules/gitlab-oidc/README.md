# gitlab-oidc

Pulumi Go port of the upstream terraform-example-foundation
[`0-bootstrap/modules/gitlab-oidc`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/0-bootstrap/modules/gitlab-oidc)
module: a Workload Identity Federation pool + OIDC provider for GitLab CI/CD,
plus per-service-account `roles/iam.workloadIdentityUser` bindings so GitLab
pipelines can impersonate the foundation stage service accounts.

The file layout mirrors upstream's file-per-concern split: `main.go`
(`main.tf`), `variables.go` (`variables.tf`), `outputs.go` (`outputs.tf`).
`versions.tf` has no per-module Go analog — provider pins live in the stage's
`go.mod` (engine adaptation).

## Usage

```go
oidc, err := gitlaboidc.NewGitlabOidc(ctx, "gitlab-oidc", &gitlaboidc.GitlabOidcArgs{
	ProjectID:  cicdProjectID,
	PoolID:     "foundation-pool",
	ProviderID: "foundation-gl-provider",
	SAMapping: map[string]gitlaboidc.SAMappingEntry{
		"bootstrap": {
			SAName:    bootstrapSA.Name,
			Attribute: "attribute.project_path/my-group/my-bootstrap-repo",
		},
	},
})
```

## Inputs (`GitlabOidcArgs`)

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| ProjectID | Project in which to create the Workload Identity Pool | `pulumi.StringInput` | n/a | yes |
| ServiceList | Google Cloud APIs required on the project | `[]string` | iam, cloudresourcemanager, sts, iamcredentials | no |
| PoolID | Workload Identity Pool ID | `string` | n/a | yes |
| PoolDisplayName | Optional pool display name | `string` | `""` | no |
| PoolDescription | Pool description | `string` | `"Workload Identity Pool managed by Pulumi"` | no |
| ProviderID | Workload Identity Pool Provider ID | `string` | n/a | yes |
| IssuerURI | OIDC issuer | `string` | `"https://gitlab.com"` | no |
| ProviderDisplayName | Optional provider display name | `string` | `""` | no |
| ProviderDescription | Provider description | `string` | `"Workload Identity Pool Provider managed by Pulumi"` | no |
| AttributeCondition | Optional provider attribute condition expression | `pulumi.StringInput` | — | no |
| AttributeMapping | Claim mapping | `map[string]string` | GitLab standard + custom claims | no |
| AllowedAudiences | Optional provider allowed audiences | `[]string` | `[]` | no |
| SAMapping | Map of service accounts + provider attributes granted `workloadIdentityUser` | `map[string]SAMappingEntry` | `{}` | no |

## Outputs (`GitlabOidc`)

| Name | Description |
|------|-------------|
| PoolName | Pool name (upstream `pool_name`) |
| ProviderName | Provider name (upstream `provider_name`) |
