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

// Stack configuration for the shared leaf — the Pulumi analogue of upstream
// 4-projects/business_unit_1/shared/variables.tf (with the *.auto.tfvars
// values supplied via Pulumi.<stack>.yaml config instead), plus the
// label/budget helpers derived from that configuration.

package main

import (
	"strings"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

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
