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

// Foundation stage 4 (projects) — the business unit's SHARED leaf, mirroring
// upstream terraform-example-foundation 4-projects/business_unit_1/shared:
// the once-per-BU, environment-independent resources — the app-infra pipeline
// project under the 1-org COMMON folder (environment=common/env_code=c). The
// per-env business-unit project sets live in the sibling
// business_unit_1/{development,nonproduction,production} leaves.
//
// Upstream's shared workspace deploys the pipeline via modules/single_project +
// modules/infra_pipelines (Cloud Build). Our port calls modules/infra_pipelines
// directly — under the GitHub-Actions-WIF deploy model it owns the pipeline
// project itself; see the module doc for the engine-difference note.
package main

import (
	"foundation-4-projects/modules/infra_pipelines"
	"strings"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Environment identity pinned by this leaf — upstream's shared workspace
// labels its projects environment=common / env_code=c.
const (
	pinnedEnv     = "common"
	pinnedEnvCode = "c"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadSharedConfig(ctx)

		// Organization StackReference (Stage 1) — provides the COMMON folder the
		// infra-pipeline project is parented under.
		orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.OrgStackName),
		})
		if err != nil {
			return err
		}
		commonFolderID := orgStack.GetStringOutput(pulumi.String("common_folder_id"))

		// Deploy the shared app-infra pipeline project (toggle-gated like
		// upstream's enable_cloudbuild_deploy; default true — deploying this leaf
		// means you want the BU's pipeline home).
		if cfg.InfraPipelineEnabled {
			res, err := infra_pipelines.Deploy(ctx, &infra_pipelines.Args{
				ProjectPrefix:         cfg.ProjectPrefix,
				BusinessCode:          cfg.BusinessCode,
				BillingAccount:        cfg.BillingAccount,
				RandomSuffix:          cfg.RandomSuffix,
				CommonFolderID:        commonFolderID,
				Labels:                commonProjectLabels(cfg, "app-infra-pipelines"),
				Budget:                budgetConfig(cfg),
				ApiPropagationSeconds: cfg.ApiPropagationSeconds,
			})
			if err != nil {
				return err
			}
			// Upstream shared/outputs.tf exports cloudbuild_project_id; our WIF
			// port keeps the established export name (Stage 5 consumes it as the
			// shared build/artifact home).
			ctx.Export("infra_pipeline_project_id", res.ProjectID)
		}

		ctx.Export("default_region", pulumi.String(cfg.Region))

		return nil
	})
}

// SharedConfig holds configuration for the shared (common) leaf of the
// projects stage.
type SharedConfig struct {
	Env            string
	EnvCode        string
	BusinessCode   string
	BillingAccount string
	ProjectPrefix  string
	OrgStackName   string
	RandomSuffix   bool

	// Metadata (upstream labels applied to every project)
	BillingCode      string
	PrimaryContact   string
	SecondaryContact string

	// Budget
	BudgetAmount        float64
	BudgetAlertPercents []float64
	BudgetSpendBasis    string

	// InfraPipelineEnabled gates the app-infra pipeline project, mirroring
	// upstream's enable_cloudbuild_deploy toggle on the shared workspace.
	// Default true.
	InfraPipelineEnabled bool

	// ApiPropagationSeconds is passed to the project factory. When >0 the
	// factory gates its ApisReady handle on a `sleep N` that depends on all
	// enabled Services, so consumers don't race freshly-enabled APIs on a cold
	// deploy. Mirrors upstream project-factory's time_sleep. 0 disables the wait.
	ApiPropagationSeconds int

	// Region — exported as default_region (upstream shared/outputs.tf).
	Region string
}

func loadSharedConfig(ctx *pulumi.Context) *SharedConfig {
	conf := config.New(ctx, "")
	c := &SharedConfig{
		Env:            pinnedEnv,
		EnvCode:        pinnedEnvCode,
		BusinessCode:   conf.Require("business_code"),
		BillingAccount: conf.Require("billing_account"),
		ProjectPrefix:  conf.Get("project_prefix"),
		OrgStackName:   conf.Require("org_stack_name"),
	}
	if c.ProjectPrefix == "" {
		c.ProjectPrefix = "prj"
	}

	randomSuffix := conf.Get("random_suffix")
	c.RandomSuffix = randomSuffix != "false"

	// Metadata — upstream applies these as project labels
	c.BillingCode = conf.Get("billing_code")
	if c.BillingCode == "" {
		c.BillingCode = "1234"
	}
	c.PrimaryContact = conf.Get("primary_contact")
	if c.PrimaryContact == "" {
		c.PrimaryContact = "example@example.com"
	}
	c.SecondaryContact = conf.Get("secondary_contact")
	if c.SecondaryContact == "" {
		c.SecondaryContact = "example2@example.com"
	}

	// Budget — matches upstream project_budget variable defaults
	if val, err := conf.TryFloat64("budget_amount"); err == nil {
		c.BudgetAmount = val
	} else {
		c.BudgetAmount = 1000
	}
	conf.GetObject("budget_alert_percents", &c.BudgetAlertPercents)
	if len(c.BudgetAlertPercents) == 0 {
		c.BudgetAlertPercents = []float64{1.2}
	}
	c.BudgetSpendBasis = conf.Get("budget_spend_basis")
	if c.BudgetSpendBasis == "" {
		c.BudgetSpendBasis = "FORECASTED_SPEND"
	}

	// Infra pipeline toggle — default true (the leaf exists to deploy it).
	if val, err := conf.TryBool("infra_pipeline_enabled"); err == nil {
		c.InfraPipelineEnabled = val
	} else {
		c.InfraPipelineEnabled = true
	}

	// API propagation wait — default 120s (the upstream foundation waits 60–180s
	// after enabling APIs; 120 is the middle of that band). Set to 0 to disable.
	if v, err := conf.TryInt("api_propagation_seconds"); err == nil {
		c.ApiPropagationSeconds = v
	} else {
		c.ApiPropagationSeconds = 120
	}

	// Region
	c.Region = conf.Get("region")
	if c.Region == "" {
		c.Region = "us-central1"
	}

	return c
}

// budgetConfig returns the standard budget configuration used for every
// project, matching the upstream TF project_budget variable.
func budgetConfig(cfg *SharedConfig) *project.BudgetConfig {
	return &project.BudgetConfig{
		Amount:             cfg.BudgetAmount,
		AlertSpentPercents: cfg.BudgetAlertPercents,
		AlertSpendBasis:    cfg.BudgetSpendBasis,
	}
}

// commonProjectLabels returns the label set for a project that lives in the
// COMMON folder (environment-independent) — e.g. the shared infra-pipeline
// project. Upstream labels these `environment = "common"`, `env_code = "c"`,
// and passes application_name RAW (not BU-prefixed), unlike the per-env
// projects. applicationName is used verbatim.
func commonProjectLabels(cfg *SharedConfig, applicationName string) pulumi.StringMap {
	return pulumi.StringMap{
		"environment":       pulumi.String(cfg.Env),
		"application_name":  pulumi.String(applicationName),
		"billing_code":      pulumi.String(cfg.BillingCode),
		"primary_contact":   pulumi.String(strings.Split(cfg.PrimaryContact, "@")[0]),
		"secondary_contact": pulumi.String(strings.Split(cfg.SecondaryContact, "@")[0]),
		"business_code":     pulumi.String(cfg.BusinessCode),
		"env_code":          pulumi.String(cfg.EnvCode),
		"vpc":               pulumi.String("none"),
	}
}
