// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Package env_baseline is the reusable per-environment baseline module, the
// faithful Pulumi port of upstream terraform-example-foundation
// 2-environments/modules/env_baseline. The thin stage root (main.go) reads the
// environment identity + core identifiers from stack config and calls Deploy;
// all resource creation lives here (env folder + tag binding, KMS project,
// Secrets project, optional Assured Workload).
package env_baseline

import (
	"fmt"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/assuredworkloads"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/tags"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// PerProjectBudget holds the budget configuration for a single project.
type PerProjectBudget struct {
	Amount             float64
	AlertSpentPercents []float64
	AlertPubSubTopic   string
	AlertSpendBasis    string
}

// EnvProjectBudgetConfig mirrors the upstream project_budget variable.
// SharedNetwork is retained for config-schema parity with upstream variables.tf
// but is a no-op here: env_baseline creates only the KMS + Secrets projects (the
// network project belongs to stage 3).
type EnvProjectBudgetConfig struct {
	SharedNetwork PerProjectBudget
	KMS           PerProjectBudget
	Secret        PerProjectBudget
}

// AssuredWorkloadConfig mirrors the upstream assured_workload_configuration variable.
type AssuredWorkloadConfig struct {
	Enabled          bool
	Location         string
	DisplayName      string
	ComplianceRegime string
	ResourceType     string
}

// Args are the inputs to the env_baseline module — the 6 upstream module inputs
// plus the values our port resolves from Pulumi config / a stack reference
// instead of terraform_remote_state (org_id, billing, prefixes, parent, tags).
type Args struct {
	Env                      string // upstream env
	EnvCode                  string // upstream environment_code
	Parent                   string // remote.tf local.parent
	OrgID                    string
	BillingAccount           string
	ProjectPrefix            string
	FolderPrefix             string
	RandomSuffix             bool
	DefaultServiceAccount    string
	ProjectDeletionPolicy    string
	FolderDeletionProtection bool
	ProjectBudget            *EnvProjectBudgetConfig
	// ApiPropagationSeconds gates project children (Budget, default-SA
	// deprivilege) on a post-enablement wait: on a cold deploy a
	// freshly-enabled API (billingbudgets, iam, ...) is not immediately
	// usable, so dependents race it without this propagation delay.
	ApiPropagationSeconds int
	AssuredWorkload       AssuredWorkloadConfig
	Tags                  pulumi.Output // 1-org "tags" map (StackReference output); may be nil
}

// Result holds the outputs of a single environment's baseline deployment.
type Result struct {
	FolderName               pulumi.StringOutput
	FolderID                 pulumi.IDOutput
	KMSProjectID             pulumi.StringOutput
	KMSProjectNumber         pulumi.StringOutput
	SecretsProjectID         pulumi.StringOutput
	AssuredWorkloadID        pulumi.StringOutput
	AssuredWorkloadResources assuredworkloads.WorkloadResourceArrayOutput
}

// Deploy creates all per-environment baseline resources. Mirrors upstream
// 2-environments/modules/env_baseline (folders.tf, kms.tf, secrets.tf,
// assured_workload.tf).
func Deploy(ctx *pulumi.Context, args *Args) (*Result, error) {
	env := args.Env
	envCode := args.EnvCode
	res := &Result{}

	// ========================================================================
	// 1. Environment Folder — folders.tf google_folder.env
	// ========================================================================
	var folderOpts []pulumi.ResourceOption
	if args.FolderDeletionProtection {
		folderOpts = append(folderOpts, pulumi.Protect(true))
	}

	envFolder, err := organizations.NewFolder(ctx, fmt.Sprintf("env-folder-%s", env), &organizations.FolderArgs{
		DisplayName:        pulumi.String(fmt.Sprintf("%s-%s", args.FolderPrefix, env)),
		Parent:             pulumi.String(args.Parent),
		DeletionProtection: pulumi.Bool(args.FolderDeletionProtection),
	}, folderOpts...)
	if err != nil {
		return nil, err
	}
	res.FolderName = envFolder.Name
	res.FolderID = envFolder.ID()

	folderID := envFolder.ID().ApplyT(func(id pulumi.ID) string {
		return string(id)
	}).(pulumi.StringOutput)

	// ========================================================================
	// 2. Folder Tag Binding — folders.tf google_tags_tag_binding.folder_env
	// Binds the environment_{env} tag value from the 1-org stage to this folder.
	// Upstream parity: TF's time_sleep.wait_60_seconds is a destroy-only delay;
	// Pulumi handles destroy ordering via its dependency graph (DependsOn).
	// ========================================================================
	if args.Tags != nil {
		tagValueID := args.Tags.ApplyT(func(v interface{}) string {
			if m, ok := v.(map[string]interface{}); ok {
				key := fmt.Sprintf("environment_%s", env)
				if val, exists := m[key]; exists {
					return val.(string)
				}
			}
			return ""
		}).(pulumi.StringOutput)

		if _, err := tags.NewTagBinding(ctx, fmt.Sprintf("tag-binding-%s", env), &tags.TagBindingArgs{
			Parent: envFolder.Name.ApplyT(func(name string) string {
				return fmt.Sprintf("//cloudresourcemanager.googleapis.com/%s", name)
			}).(pulumi.StringOutput),
			TagValue: tagValueID,
		}, pulumi.DependsOn([]pulumi.Resource{envFolder})); err != nil {
			return nil, err
		}
	}

	// ========================================================================
	// 3. KMS Project — kms.tf module "env_kms"
	// ========================================================================
	kmsProject, err := project.NewProject(ctx, fmt.Sprintf("env-kms-%s", env), &project.ProjectArgs{
		ProjectID:             pulumi.String(fmt.Sprintf("%s-%s-kms", args.ProjectPrefix, envCode)),
		Name:                  pulumi.String(fmt.Sprintf("%s-%s-kms", args.ProjectPrefix, envCode)),
		FolderID:              folderID,
		BillingAccount:        pulumi.String(args.BillingAccount),
		RandomProjectID:       args.RandomSuffix,
		DeletionPolicy:        pulumi.String(args.ProjectDeletionPolicy),
		DefaultServiceAccount: args.DefaultServiceAccount,
		// Cold-deploy race fix: wait for freshly-enabled APIs to propagate
		// before dependents (Budget, default-SA deprivilege) use them.
		ApiPropagationSeconds: args.ApiPropagationSeconds,
		ActivateApis: []string{
			"logging.googleapis.com",
			"cloudkms.googleapis.com",
			"billingbudgets.googleapis.com",
		},
		Labels: pulumi.StringMap{
			"environment":       pulumi.String(env),
			"application_name":  pulumi.String("env-kms"),
			"billing_code":      pulumi.String("1234"),
			"primary_contact":   pulumi.String("example1"),
			"secondary_contact": pulumi.String("example2"),
			"business_code":     pulumi.String("shared"),
			"env_code":          pulumi.String(envCode),
			"vpc":               pulumi.String("none"),
		},
		Budget: budgetFor(getEnvProjectBudget(args.ProjectBudget, "kms")),
	}, pulumi.DependsOn([]pulumi.Resource{envFolder}))
	if err != nil {
		return nil, err
	}
	res.KMSProjectID = kmsProject.Project.ProjectId
	res.KMSProjectNumber = kmsProject.Project.Number

	// ========================================================================
	// 4. Secrets Project — secrets.tf module "env_secrets"
	// ========================================================================
	secretsProject, err := project.NewProject(ctx, fmt.Sprintf("env-secrets-%s", env), &project.ProjectArgs{
		ProjectID:             pulumi.String(fmt.Sprintf("%s-%s-secrets", args.ProjectPrefix, envCode)),
		Name:                  pulumi.String(fmt.Sprintf("%s-%s-secrets", args.ProjectPrefix, envCode)),
		FolderID:              folderID,
		BillingAccount:        pulumi.String(args.BillingAccount),
		RandomProjectID:       args.RandomSuffix,
		DeletionPolicy:        pulumi.String(args.ProjectDeletionPolicy),
		DefaultServiceAccount: args.DefaultServiceAccount,
		// Cold-deploy race fix: wait for freshly-enabled APIs to propagate
		// before dependents (Budget, default-SA deprivilege) use them.
		ApiPropagationSeconds: args.ApiPropagationSeconds,
		ActivateApis: []string{
			"logging.googleapis.com",
			"secretmanager.googleapis.com",
		},
		Labels: pulumi.StringMap{
			"environment":       pulumi.String(env),
			"application_name":  pulumi.String("env-secrets"),
			"billing_code":      pulumi.String("1234"),
			"primary_contact":   pulumi.String("example1"),
			"secondary_contact": pulumi.String("example2"),
			"business_code":     pulumi.String("shared"),
			"env_code":          pulumi.String(envCode),
			"vpc":               pulumi.String("none"),
		},
		Budget: budgetFor(getEnvProjectBudget(args.ProjectBudget, "secret")),
	}, pulumi.DependsOn([]pulumi.Resource{envFolder}))
	if err != nil {
		return nil, err
	}
	res.SecretsProjectID = secretsProject.Project.ProjectId

	// ========================================================================
	// 5. Assured Workload (optional) — assured_workload.tf
	// ========================================================================
	if args.AssuredWorkload.Enabled {
		workload, err := assuredworkloads.NewWorkload(ctx, fmt.Sprintf("assured-workload-%s", env), &assuredworkloads.WorkloadArgs{
			Organization:   pulumi.String(args.OrgID),
			BillingAccount: pulumi.String(fmt.Sprintf("billingAccounts/%s", args.BillingAccount)),
			ProvisionedResourcesParent: envFolder.ID().ApplyT(func(id pulumi.ID) string {
				return string(id)
			}).(pulumi.StringOutput),
			ComplianceRegime: pulumi.String(args.AssuredWorkload.ComplianceRegime),
			DisplayName:      pulumi.String(args.AssuredWorkload.DisplayName),
			Location:         pulumi.String(args.AssuredWorkload.Location),
			ResourceSettings: assuredworkloads.WorkloadResourceSettingArray{
				&assuredworkloads.WorkloadResourceSettingArgs{
					ResourceType: pulumi.String(args.AssuredWorkload.ResourceType),
				},
			},
		}, pulumi.DependsOn([]pulumi.Resource{envFolder}))
		if err != nil {
			return nil, err
		}
		res.AssuredWorkloadID = workload.ID().ApplyT(func(id pulumi.ID) string {
			return string(id)
		}).(pulumi.StringOutput)
		res.AssuredWorkloadResources = workload.Resources
	}

	return res, nil
}

func budgetFor(pb *PerProjectBudget) *project.BudgetConfig {
	if pb == nil {
		return nil
	}
	amount := pb.Amount
	if amount == 0 {
		amount = 1000 // upstream default
	}
	alertPercents := pb.AlertSpentPercents
	if len(alertPercents) == 0 {
		alertPercents = []float64{1.2} // upstream default
	}
	spendBasis := pb.AlertSpendBasis
	if spendBasis == "" {
		spendBasis = "FORECASTED_SPEND" // upstream default
	}
	return &project.BudgetConfig{
		Amount:             amount,
		AlertSpentPercents: alertPercents,
		AlertPubSubTopic:   pb.AlertPubSubTopic,
		AlertSpendBasis:    spendBasis,
	}
}

// getEnvProjectBudget returns the per-project budget for the named project type.
func getEnvProjectBudget(pb *EnvProjectBudgetConfig, projectType string) *PerProjectBudget {
	if pb == nil {
		return nil
	}
	switch projectType {
	case "shared_network":
		return &pb.SharedNetwork
	case "kms":
		return &pb.KMS
	case "secret":
		return &pb.Secret
	default:
		return nil
	}
}
