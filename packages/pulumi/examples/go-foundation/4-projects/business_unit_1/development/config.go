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

// Stack configuration for this leaf — the Pulumi analogue of upstream
// 4-projects/business_unit_1/development/variables.tf (with the *.auto.tfvars
// values supplied via Pulumi.<stack>.yaml config instead), plus the
// label/budget helpers derived from that configuration.

package main

import (
	"fmt"
	"strings"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// ProjectsConfig holds configuration for this environment leaf of the projects
// stage. The environment identity is pinned by the leaf (pinnedEnv /
// pinnedEnvCode), not read from config.
type ProjectsConfig struct {
	Env              string
	EnvCode          string
	BusinessCode     string
	BillingAccount   string
	ProjectPrefix    string
	FolderPrefix     string
	OrgStackName     string
	NetworkStackName string
	EnvStackName     string
	RandomSuffix     bool

	// Metadata (upstream labels applied to every project)
	ApplicationName  string
	BillingCode      string
	PrimaryContact   string
	SecondaryContact string

	// Budget
	BudgetAmount        float64
	BudgetAlertPercents []float64
	BudgetSpendBasis    string

	// Project-type enablement (all default true → upstream behavior: every BU
	// gets an SVPC-attached, a floating, and a peering project). Set
	// individually to false to deploy only the project types a given go-live
	// needs (e.g. floating-only). Gating these also lets the stack skip the
	// org/network StackReferences whose outputs are only consumed by the
	// disabled types. The BU's common infra-pipeline project is owned by the
	// business_unit_1/shared leaf, not the env leaves.
	SVPCProjectEnabled     bool
	FloatingProjectEnabled bool
	PeeringProjectEnabled  bool

	// ApiPropagationSeconds is passed to every project_factory project. When >0
	// the factory gates its ApisReady handle on a `sleep N` that depends on all
	// enabled Services, so consumers that DependsOn(ApisReady) (or read a gated
	// project id) don't race freshly-enabled APIs on a cold deploy. Mirrors
	// upstream project-factory's time_sleep. 0 disables the wait.
	ApiPropagationSeconds int

	// VPC-SC
	EnforceVpcSc bool

	// Peering
	PeeringEnabled         bool
	PeeringIAPFWEnabled    bool
	SubnetRegion           string
	SubnetIPRange          string
	FirewallEnableLogging  bool
	WindowsActivation      bool
	OptionalFWRulesEnabled bool

	// Confidential Space
	ConfidentialSpaceEnabled bool

	// CMEK
	CMEKEnabled         bool
	KMSLocation         string
	GCSLocation         string
	KeyringName         string
	KeyName             string
	KeyRotationPeriod   string
	GCSBucketPrefix     string
	GCSPlacementRegions []string

	// Regions
	Region  string
	Region2 string

	// Folder
	FolderDeletionProtection bool
}

func loadProjectsConfig(ctx *pulumi.Context) *ProjectsConfig {
	conf := config.New(ctx, "")
	c := &ProjectsConfig{
		Env:              pinnedEnv,
		EnvCode:          pinnedEnvCode,
		BusinessCode:     conf.Require("business_code"),
		BillingAccount:   conf.Require("billing_account"),
		ProjectPrefix:    conf.Get("project_prefix"),
		FolderPrefix:     conf.Get("folder_prefix"),
		OrgStackName:     conf.Require("org_stack_name"),
		NetworkStackName: conf.Get("network_stack_name"),
		EnvStackName:     conf.Require("env_stack_name"),
	}
	// The env reference targets this environment's 2-environments leaf stack
	// (e.g. organization/<org>/foundation-environments-{env}/production). The
	// network reference defaults to the matching 3-networks-svpc leaf, derived
	// by name substitution; hub-and-spoke consumers set network_stack_name
	// explicitly.
	if c.NetworkStackName == "" {
		c.NetworkStackName = strings.Replace(c.EnvStackName, "foundation-environments-", "foundation-3-networks-svpc-", 1)
	}
	if c.ProjectPrefix == "" {
		c.ProjectPrefix = "prj"
	}
	if c.FolderPrefix == "" {
		c.FolderPrefix = "fldr"
	}

	randomSuffix := conf.Get("random_suffix")
	c.RandomSuffix = randomSuffix != "false"

	// Metadata — upstream applies these as project labels
	c.ApplicationName = conf.Get("application_name")
	if c.ApplicationName == "" {
		c.ApplicationName = fmt.Sprintf("%s-sample-application", c.BusinessCode)
	}
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

	// Project-type enablement — default true to preserve upstream behavior
	// (all three BU project types are created).
	if val, err := conf.TryBool("svpc_project_enabled"); err == nil {
		c.SVPCProjectEnabled = val
	} else {
		c.SVPCProjectEnabled = true
	}
	if val, err := conf.TryBool("floating_project_enabled"); err == nil {
		c.FloatingProjectEnabled = val
	} else {
		c.FloatingProjectEnabled = true
	}
	if val, err := conf.TryBool("peering_project_enabled"); err == nil {
		c.PeeringProjectEnabled = val
	} else {
		c.PeeringProjectEnabled = true
	}

	// API propagation wait — default 120s (the upstream foundation waits 60–180s
	// after enabling APIs; 120 is the middle of that band). Set to 0 to disable.
	if v, err := conf.TryInt("api_propagation_seconds"); err == nil {
		c.ApiPropagationSeconds = v
	} else {
		c.ApiPropagationSeconds = 120
	}

	// VPC-SC
	if val, err := conf.TryBool("enforce_vpcsc"); err == nil {
		c.EnforceVpcSc = val
	} else {
		c.EnforceVpcSc = true
	}

	// Peering
	if val, err := conf.TryBool("peering_enabled"); err == nil {
		c.PeeringEnabled = val
	} else {
		c.PeeringEnabled = true
	}
	if val, err := conf.TryBool("peering_iap_fw_rules_enabled"); err == nil {
		c.PeeringIAPFWEnabled = val
	} else {
		c.PeeringIAPFWEnabled = true
	}
	c.SubnetRegion = conf.Get("subnet_region")
	c.SubnetIPRange = conf.Get("subnet_ip_range")
	if c.SubnetRegion == "" {
		c.SubnetRegion = "us-central1"
	}
	if c.SubnetIPRange == "" {
		c.SubnetIPRange = "10.3.64.0/21"
	}
	if val, err := conf.TryBool("firewall_enable_logging"); err == nil {
		c.FirewallEnableLogging = val
	} else {
		c.FirewallEnableLogging = true
	}
	if val, err := conf.TryBool("windows_activation_enabled"); err == nil {
		c.WindowsActivation = val
	}
	if val, err := conf.TryBool("optional_fw_rules_enabled"); err == nil {
		c.OptionalFWRulesEnabled = val
	}

	// Confidential Space
	if val, err := conf.TryBool("confidential_space_enabled"); err == nil {
		c.ConfidentialSpaceEnabled = val
	}

	// CMEK
	if val, err := conf.TryBool("cmek_enabled"); err == nil {
		c.CMEKEnabled = val
	} else {
		c.CMEKEnabled = true
	}
	c.KMSLocation = conf.Get("location_kms")
	c.GCSLocation = conf.Get("location_gcs")
	if c.KMSLocation == "" {
		c.KMSLocation = c.SubnetRegion
	}
	if c.GCSLocation == "" {
		c.GCSLocation = "US"
	}
	c.KeyringName = conf.Get("keyring_name")
	if c.KeyringName == "" {
		c.KeyringName = fmt.Sprintf("%s-sample-keyring", c.BusinessCode)
	}
	c.KeyName = conf.Get("key_name")
	if c.KeyName == "" {
		c.KeyName = "crypto-key-example"
	}
	c.KeyRotationPeriod = conf.Get("key_rotation_period")
	if c.KeyRotationPeriod == "" {
		c.KeyRotationPeriod = "7776000s"
	}
	c.GCSBucketPrefix = conf.Get("gcs_bucket_prefix")
	if c.GCSBucketPrefix == "" {
		c.GCSBucketPrefix = "bkt"
	}
	conf.GetObject("gcs_placement_regions", &c.GCSPlacementRegions)

	// Regions
	c.Region = conf.Get("region")
	if c.Region == "" {
		c.Region = "us-central1"
	}
	c.Region2 = conf.Get("region2")
	if c.Region2 == "" {
		c.Region2 = "us-west1"
	}

	// Folder deletion protection
	if val, err := conf.TryBool("folder_deletion_protection"); err == nil {
		c.FolderDeletionProtection = val
	} else {
		c.FolderDeletionProtection = true
	}

	return c
}

// budgetConfig returns the standard budget configuration used for every
// project, matching the upstream TF project_budget variable.
func budgetConfig(cfg *ProjectsConfig) *project.BudgetConfig {
	return &project.BudgetConfig{
		Amount:             cfg.BudgetAmount,
		AlertSpentPercents: cfg.BudgetAlertPercents,
		AlertSpendBasis:    cfg.BudgetSpendBasis,
	}
}

// projectLabels returns the standard set of labels that upstream applies to
// every project, matching the TF single_project module's labels block.
func projectLabels(cfg *ProjectsConfig, suffix, vpc string) pulumi.StringMap {
	return pulumi.StringMap{
		"environment":       pulumi.String(cfg.Env),
		"application_name":  pulumi.String(fmt.Sprintf("%s-%s", cfg.BusinessCode, suffix)),
		"billing_code":      pulumi.String(cfg.BillingCode),
		"primary_contact":   pulumi.String(strings.Split(cfg.PrimaryContact, "@")[0]),
		"secondary_contact": pulumi.String(strings.Split(cfg.SecondaryContact, "@")[0]),
		"business_code":     pulumi.String(cfg.BusinessCode),
		"env_code":          pulumi.String(cfg.EnvCode),
		"vpc":               pulumi.String(vpc),
	}
}
