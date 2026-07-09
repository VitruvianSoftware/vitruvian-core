/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadEnvConfig(ctx)

		// Stack Reference to 1-org for tag values.
		//
		// Note: The upstream TF foundation reads org_id, billing_account, etc.
		// from bootstrap's common_config via terraform_remote_state, which
		// blocks during plan/apply. In Pulumi, StackReference.GetOutput returns
		// an async Output — you cannot extract its value as a synchronous Go
		// string. Since deployEnvBaseline consumes these as plain strings
		// (e.g. pulumi.String(cfg.Parent)), they must come from Pulumi config,
		// not stack references. Tags work because they flow as pulumi.Output
		// into resource args that accept pulumi.StringInput.
		orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.OrgStackName),
		})
		if err != nil {
			return err
		}

		// Resolve tag values from the 1-org stage for folder tag bindings.
		// The 1-org stage exports a "tags" map with keys like "environment_development".
		tagsOutput := orgStack.GetOutput(pulumi.String("tags"))

		// Deploy baseline for this environment.
		// Each Pulumi stack (development, nonproduction, production) deploys
		// exactly one environment. The env and env_code are read from stack
		// config, enabling sequential promotion via GitHub Environment gates.
		outputs, err := deployEnvBaseline(ctx, cfg, cfg.Env, cfg.EnvCode, tagsOutput)
		if err != nil {
			return err
		}

		// Exports — matches upstream TF 2-environments/envs/{env}/outputs.tf exactly.
		// Since each stack deploys a single environment, outputs are un-prefixed
		// (matching the TF convention where each env has its own state file).
		ctx.Export("env_folder", outputs.FolderName)
		ctx.Export("env_kms_project_id", outputs.KMSProjectID)
		ctx.Export("env_kms_project_number", outputs.KMSProjectNumber)
		ctx.Export("env_secrets_project_id", outputs.SecretsProjectID)

		// Export Assured Workload outputs when configured.
		// Matches TF's assured_workload_id and assured_workload_resources outputs.
		if outputs.AssuredWorkloadID != (pulumi.StringOutput{}) {
			ctx.Export("assured_workload_id", outputs.AssuredWorkloadID)
			ctx.Export("assured_workload_resources", outputs.AssuredWorkloadResources)
		}

		return nil
	})
}

// PerProjectBudget holds the budget configuration for a single project.
type PerProjectBudget struct {
	Amount             float64
	AlertSpentPercents []float64
	AlertPubSubTopic   string
	AlertSpendBasis    string
}

// EnvProjectBudgetConfig mirrors the upstream project_budget variable for 2-environments.
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

// EnvConfig holds all configuration for the environments stage.
// This mirrors all variables from the upstream Terraform foundation's
// 2-environments/modules/env_baseline/variables.tf and remote.tf.
//
// Core identifiers (org_id, billing_account, project_prefix, folder_prefix)
// are set via Pulumi config rather than inherited from bootstrap stack
// references. This is because Pulumi stack references return async Outputs,
// but these values are consumed as synchronous Go strings in resource args.
//
// In the monorepo promotion model, each Pulumi stack (development,
// nonproduction, production) deploys exactly one environment. The Env and
// EnvCode fields are read from the per-stack config file.
type EnvConfig struct {
	// Environment identity (from per-stack config)
	Env     string // e.g. "development", "nonproduction", "production"
	EnvCode string // e.g. "d", "n", "p"

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

	// Budgets
	ProjectBudget *EnvProjectBudgetConfig

	// Assured Workloads
	AssuredWorkload AssuredWorkloadConfig
}

func loadEnvConfig(ctx *pulumi.Context) *EnvConfig {
	conf := config.New(ctx, "")
	c := &EnvConfig{
		Env:            conf.Require("env"),
		EnvCode:        conf.Require("env_code"),
		OrgID:          conf.Require("org_id"),
		BillingAccount: conf.Require("billing_account"),
		ProjectPrefix:  conf.Get("project_prefix"),
		FolderPrefix:   conf.Get("folder_prefix"),
		OrgStackName:   conf.Require("org_stack_name"),

		// Project settings
		ProjectDeletionPolicy: conf.Get("project_deletion_policy"),
		DefaultServiceAccount: conf.Get("default_service_account"),
	}

	// Boolean config with defaults
	c.FolderDeletionProtection = conf.Get("folder_deletion_protection") != "false"
	randomSuffix := conf.Get("random_suffix")
	c.RandomSuffix = randomSuffix != "false"

	// Parse structured config for ProjectBudget
	var pb EnvProjectBudgetConfig
	if err := conf.GetObject("project_budget", &pb); err == nil {
		c.ProjectBudget = &pb
	} else {
		// Default budget values matching upstream tf variables.tf
		c.ProjectBudget = &EnvProjectBudgetConfig{
			SharedNetwork: PerProjectBudget{
				Amount:             1000,
				AlertSpentPercents: []float64{1.2},
				AlertSpendBasis:    "FORECASTED_SPEND",
			},
			KMS: PerProjectBudget{
				Amount:             1000,
				AlertSpentPercents: []float64{1.2},
				AlertSpendBasis:    "FORECASTED_SPEND",
			},
			Secret: PerProjectBudget{
				Amount:             1000,
				AlertSpentPercents: []float64{1.2},
				AlertSpendBasis:    "FORECASTED_SPEND",
			},
		}
	}

	// Parse Assured Workload configuration
	c.AssuredWorkload = AssuredWorkloadConfig{
		Enabled:          conf.Get("assured_workload_enabled") == "true",
		Location:         conf.Get("assured_workload_location"),
		DisplayName:      conf.Get("assured_workload_display_name"),
		ComplianceRegime: conf.Get("assured_workload_compliance_regime"),
		ResourceType:     conf.Get("assured_workload_resource_type"),
	}

	// Apply defaults matching the upstream Terraform foundation
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

	// Determine parent path
	parentFolder := conf.Get("parent_folder")
	if parentFolder != "" {
		c.Parent = "folders/" + parentFolder
	} else {
		c.Parent = "organizations/" + c.OrgID
	}

	return c
}
