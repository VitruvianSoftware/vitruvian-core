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

// Foundation stage 2 (environments) — thin env root for the production environment.
//
// Faithful to upstream terraform-example-foundation 2-environments/envs/production:
// this leaf pins the environment identity (production/p), reads the core
// identifiers from stack config and a StackReference to 1-org (for tag values),
// then calls the shared env_baseline module. All resource creation lives in
// ../../modules/env_baseline; the sibling envs/ leaves deploy the other
// environments.
package main

import (
	"foundation-2-environments/modules/env_baseline"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Environment pinned by this leaf project — upstream 2-environments/envs/production
// hardcodes env = "production" in its main.tf; the leaf dir is the pin, not
// per-stack config.
const (
	pinnedEnv     = "production"
	pinnedEnvCode = "p"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadEnvConfig(ctx)

		// StackReference to 1-org for tag values. Core identifiers (org_id,
		// billing_account, prefixes) come from Pulumi config, not remote state,
		// because StackReference outputs are async and env_baseline consumes some
		// as synchronous strings; tags flow as a pulumi.Output into resource args.
		orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.OrgStackName),
		})
		if err != nil {
			return err
		}
		tagsOutput := orgStack.GetOutput(pulumi.String("tags"))

		res, err := env_baseline.Deploy(ctx, &env_baseline.Args{
			Env:                      cfg.Env,
			EnvCode:                  cfg.EnvCode,
			Parent:                   cfg.Parent,
			OrgID:                    cfg.OrgID,
			BillingAccount:           cfg.BillingAccount,
			ProjectPrefix:            cfg.ProjectPrefix,
			FolderPrefix:             cfg.FolderPrefix,
			RandomSuffix:             cfg.RandomSuffix,
			DefaultServiceAccount:    cfg.DefaultServiceAccount,
			ProjectDeletionPolicy:    cfg.ProjectDeletionPolicy,
			FolderDeletionProtection: cfg.FolderDeletionProtection,
			ApiPropagationSeconds:    cfg.ApiPropagationSeconds,
			ProjectBudget:            cfg.ProjectBudget,
			AssuredWorkload:          cfg.AssuredWorkload,
			Tags:                     tagsOutput,
		})
		if err != nil {
			return err
		}

		// Exports — mirror upstream 2-environments/envs/<env>/outputs.tf. Each
		// stack deploys a single environment, so outputs are un-prefixed.
		ctx.Export("env_folder", res.FolderName)
		ctx.Export("env_kms_project_id", res.KMSProjectID)
		ctx.Export("env_kms_project_number", res.KMSProjectNumber)
		ctx.Export("env_secrets_project_id", res.SecretsProjectID)
		if res.AssuredWorkloadID != (pulumi.StringOutput{}) {
			ctx.Export("assured_workload_id", res.AssuredWorkloadID)
			ctx.Export("assured_workload_resources", res.AssuredWorkloadResources)
		}

		return nil
	})
}

// EnvConfig holds the stage-root configuration (the Pulumi analog of upstream's
// per-env root variables.tf + the remote.tf locals). The structured budget /
// assured-workload types live in the env_baseline module (its inputs).
type EnvConfig struct {
	// Environment identity (pinned by this leaf project)
	Env     string // "development" | "nonproduction" | "production"
	EnvCode string // "d" | "n" | "p"

	// Core identifiers (from Pulumi config)
	OrgID          string
	BillingAccount string
	ProjectPrefix  string
	FolderPrefix   string
	Parent         string // "organizations/<id>" or "folders/<id>"

	// Stack references
	OrgStackName string

	// Project settings
	RandomSuffix             bool
	ProjectDeletionPolicy    string
	FolderDeletionProtection bool
	DefaultServiceAccount    string
	// ApiPropagationSeconds: cold-deploy propagation wait for freshly-enabled
	// project APIs (see env_baseline.Args.ApiPropagationSeconds). Default 120.
	ApiPropagationSeconds int

	// Module inputs
	ProjectBudget   *env_baseline.EnvProjectBudgetConfig
	AssuredWorkload env_baseline.AssuredWorkloadConfig
}

func loadEnvConfig(ctx *pulumi.Context) *EnvConfig {
	conf := config.New(ctx, "")
	c := &EnvConfig{
		Env:            pinnedEnv,
		EnvCode:        pinnedEnvCode,
		OrgID:          conf.Require("org_id"),
		BillingAccount: conf.Require("billing_account"),
		ProjectPrefix:  conf.Get("project_prefix"),
		FolderPrefix:   conf.Get("folder_prefix"),
		OrgStackName:   conf.Require("org_stack_name"),

		ProjectDeletionPolicy: conf.Get("project_deletion_policy"),
		DefaultServiceAccount: conf.Get("default_service_account"),
	}

	c.FolderDeletionProtection = conf.Get("folder_deletion_protection") != "false"
	c.RandomSuffix = conf.Get("random_suffix") != "false"

	var pb env_baseline.EnvProjectBudgetConfig
	if err := conf.GetObject("project_budget", &pb); err == nil {
		c.ProjectBudget = &pb
	} else {
		// Default budgets matching upstream variables.tf.
		defaultBudget := env_baseline.PerProjectBudget{
			Amount:             1000,
			AlertSpentPercents: []float64{1.2},
			AlertSpendBasis:    "FORECASTED_SPEND",
		}
		c.ProjectBudget = &env_baseline.EnvProjectBudgetConfig{
			SharedNetwork: defaultBudget,
			KMS:           defaultBudget,
			Secret:        defaultBudget,
		}
	}

	c.AssuredWorkload = env_baseline.AssuredWorkloadConfig{
		Enabled:          conf.Get("assured_workload_enabled") == "true",
		Location:         conf.Get("assured_workload_location"),
		DisplayName:      conf.Get("assured_workload_display_name"),
		ComplianceRegime: conf.Get("assured_workload_compliance_regime"),
		ResourceType:     conf.Get("assured_workload_resource_type"),
	}

	// Defaults matching upstream.
	if c.ProjectPrefix == "" {
		c.ProjectPrefix = "prj"
	}
	if c.FolderPrefix == "" {
		c.FolderPrefix = "fldr"
	}
	if c.ProjectDeletionPolicy == "" {
		c.ProjectDeletionPolicy = "PREVENT"
	}
	if c.DefaultServiceAccount == "" {
		c.DefaultServiceAccount = "deprivilege"
	}
	// Cold-deploy race fix: freshly-enabled APIs (billingbudgets, iam) are not
	// immediately usable; default a 120s propagation wait, overridable per-stack.
	c.ApiPropagationSeconds = 120
	if v, err := conf.TryInt("api_propagation_seconds"); err == nil {
		c.ApiPropagationSeconds = v
	}
	if c.AssuredWorkload.Location == "" {
		c.AssuredWorkload.Location = "us-central1"
	}
	if c.AssuredWorkload.DisplayName == "" {
		c.AssuredWorkload.DisplayName = "FEDRAMP-MODERATE"
	}
	if c.AssuredWorkload.ComplianceRegime == "" {
		c.AssuredWorkload.ComplianceRegime = "FEDRAMP_MODERATE"
	}
	if c.AssuredWorkload.ResourceType == "" {
		c.AssuredWorkload.ResourceType = "CONSUMER_FOLDER"
	}

	parentFolder := conf.Get("parent_folder")
	if parentFolder != "" {
		c.Parent = "folders/" + parentFolder
	} else {
		c.Parent = "organizations/" + c.OrgID
	}

	return c
}
