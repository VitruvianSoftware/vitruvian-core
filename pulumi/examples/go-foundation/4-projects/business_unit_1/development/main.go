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

// Foundation stage 4 (projects) — thin business-unit leaf for the development
// environment, mirroring upstream terraform-example-foundation
// 4-projects/business_unit_1/development. This leaf pins the environment
// identity (development/d), creates the BU folder under the development env
// folder, and calls the shared modules/base_env for the per-env business-unit
// project set. The BU's shared infra-pipeline project lives in the sibling
// business_unit_1/shared leaf (upstream's `shared` workspace).
package main

import (
	"fmt"
	"foundation-4-projects/modules/base_env"
	"strings"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Environment pinned by this leaf project — upstream
// 4-projects/business_unit_1/development hardcodes env = "development" in its
// main.tf; the leaf dir is the pin, not per-stack config.
const (
	pinnedEnv     = "development"
	pinnedEnvCode = "d"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadProjectsConfig(ctx)

		emptyStr := pulumi.String("").ToStringOutput()

		// 1. Environment StackReference (Stage 2) — always required: it provides
		// the environment folder (BU-folder parent) and the per-env KMS project.
		envStack, err := pulumi.NewStackReference(ctx, "environment", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.EnvStackName),
		})
		if err != nil {
			return err
		}
		// The 2-environments leaf stack for this environment exports bare
		// "env_folder" / "env_kms_project_id" keys (upstream reads
		// env_folder_name from the single 2-environments remote state; our
		// per-env leaf stacks scope the state per environment instead).
		folderID := envStack.GetStringOutput(pulumi.String("env_folder"))
		kmsProjectID := envStack.GetStringOutput(pulumi.String("env_kms_project_id"))

		// 1b. Organization StackReference (Stage 1) — only when a project type
		// that consumes its outputs is enabled (SVPC host, peering-to-host, or
		// confidential space). The common-folder infra pipeline moved to the
		// business_unit_1/shared leaf, which keeps its own org reference.
		networkProjectID := emptyStr
		acmPolicyID := emptyStr
		if cfg.SVPCProjectEnabled || cfg.PeeringProjectEnabled || cfg.ConfidentialSpaceEnabled {
			orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
				Name: pulumi.String(cfg.OrgStackName),
			})
			if err != nil {
				return err
			}
			networkProjectID = orgStack.GetStringOutput(pulumi.String(fmt.Sprintf("%s_network_project_id", cfg.Env)))
			acmPolicyID = orgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id"))
		}

		// 1c. Network StackReference (Stage 3) — only when a project attaches to
		// the VPC-SC perimeter (SVPC-attached or confidential-space projects).
		perimeterName := emptyStr
		if cfg.SVPCProjectEnabled || cfg.ConfidentialSpaceEnabled {
			netStack, err := pulumi.NewStackReference(ctx, "network", &pulumi.StackReferenceArgs{
				Name: pulumi.String(cfg.NetworkStackName),
			})
			if err != nil {
				return err
			}
			perimeterName = netStack.GetStringOutput(pulumi.String("service_perimeter_name"))
		}

		// 2. Create the Business Unit folder under the environment folder
		buFolder, err := organizations.NewFolder(ctx, "bu-folder", &organizations.FolderArgs{
			DisplayName: folderID.ApplyT(func(_ string) string {
				return fmt.Sprintf("%s-%s-%s", cfg.FolderPrefix, cfg.Env, cfg.BusinessCode)
			}).(pulumi.StringOutput),
			// env_folder is exported as envFolder.Name, which GCP already
			// formats as "folders/{id}"; use it directly (prefixing would double it).
			Parent:             folderID,
			DeletionProtection: pulumi.Bool(cfg.FolderDeletionProtection),
		})
		if err != nil {
			return err
		}

		// 3. Deploy Business Unit Projects (each type internally toggle-gated)
		buFolderID := buFolder.ID().ApplyT(func(id pulumi.ID) string {
			return string(id)
		}).(pulumi.StringOutput)

		// base_env.Args carries the subset of cfg the module needs plus the
		// cross-stage StackReference outputs. Labels/Budget are supplied from the
		// leaf's tested helpers so label/budget behaviour is preserved exactly.
		beArgs := &base_env.Args{
			ProjectPrefix:  cfg.ProjectPrefix,
			EnvCode:        cfg.EnvCode,
			BusinessCode:   cfg.BusinessCode,
			BillingAccount: cfg.BillingAccount,
			RandomSuffix:   cfg.RandomSuffix,

			SVPCProjectEnabled:     cfg.SVPCProjectEnabled,
			FloatingProjectEnabled: cfg.FloatingProjectEnabled,
			PeeringProjectEnabled:  cfg.PeeringProjectEnabled,

			EnforceVpcSc:   cfg.EnforceVpcSc,
			CMEKEnabled:    cfg.CMEKEnabled,
			PeeringEnabled: cfg.PeeringEnabled,

			ApiPropagationSeconds: cfg.ApiPropagationSeconds,

			SubnetRegion:           cfg.SubnetRegion,
			SubnetIPRange:          cfg.SubnetIPRange,
			PeeringIAPFWEnabled:    cfg.PeeringIAPFWEnabled,
			FirewallEnableLogging:  cfg.FirewallEnableLogging,
			WindowsActivation:      cfg.WindowsActivation,
			OptionalFWRulesEnabled: cfg.OptionalFWRulesEnabled,

			KeyringName:         cfg.KeyringName,
			KMSLocation:         cfg.KMSLocation,
			KeyName:             cfg.KeyName,
			KeyRotationPeriod:   cfg.KeyRotationPeriod,
			GCSBucketPrefix:     cfg.GCSBucketPrefix,
			GCSLocation:         cfg.GCSLocation,
			GCSPlacementRegions: cfg.GCSPlacementRegions,

			FolderID:         buFolderID,
			NetworkProjectID: networkProjectID,
			PerimeterName:    perimeterName,
			KMSProjectID:     kmsProjectID,
			ACMPolicyID:      acmPolicyID,

			Labels: func(suffix, vpc string) pulumi.StringMap {
				return projectLabels(cfg, suffix, vpc)
			},
			Budget: budgetConfig(cfg),
		}
		projects, err := base_env.New(ctx, beArgs)
		if err != nil {
			return err
		}

		// 4. Deploy Confidential Space Project (optional, toggle-gated)
		if cfg.ConfidentialSpaceEnabled {
			confResult, err := base_env.DeployConfidentialSpaceProject(ctx, beArgs)
			if err != nil {
				return err
			}
			projects.ConfSpaceProjectID = &confResult.ProjectID
			projects.ConfSpaceProjectNumber = &confResult.ProjectNumber
			projects.ConfSpaceWorkloadSA = &confResult.WorkloadSAEmail
		}

		// 5. Exports — matching TF 4-projects/business_unit_1/{env}/outputs.tf.
		// The BU's infra_pipeline_project_id is exported by the sibling
		// business_unit_1/shared leaf (upstream's shared workspace), not here.
		ctx.Export("shared_vpc_project", projects.SVPCProjectID)
		ctx.Export("shared_vpc_project_number", projects.SVPCProjectNumber)
		ctx.Export("floating_project", projects.FloatingProjectID)
		ctx.Export("peering_project", projects.PeeringProjectID)
		ctx.Export("peering_network", projects.PeeringNetworkSelfLink)
		ctx.Export("peering_subnetwork_self_link", projects.PeeringSubnetSelfLink)
		ctx.Export("iap_firewall_tags", projects.IAPFirewallTags)
		if projects.CMEKBucket != nil {
			ctx.Export("bucket", *projects.CMEKBucket)
			ctx.Export("keyring", *projects.CMEKKeyring)
		}
		if projects.CMEKKeys != nil {
			ctx.Export("keys", *projects.CMEKKeys)
		} else {
			ctx.Export("keys", pulumi.ToStringArray([]string{}))
		}
		if projects.ConfSpaceProjectID != nil {
			ctx.Export("confidential_space_project", *projects.ConfSpaceProjectID)
			ctx.Export("confidential_space_project_number", *projects.ConfSpaceProjectNumber)
			ctx.Export("confidential_space_workload_sa", *projects.ConfSpaceWorkloadSA)
		}
		ctx.Export("default_region", pulumi.String(cfg.Region))
		ctx.Export("subnets_self_links", projects.SubnetsSelfLinks)
		ctx.Export("restricted_enabled_apis", pulumi.ToStringArray(projects.RestrictedEnabledApis))
		ctx.Export("vpc_service_control_perimeter_name", projects.VPCSCPerimeterName)
		ctx.Export("peering_complete", projects.PeeringComplete)
		ctx.Export("access_context_manager_policy_id", projects.AccessContextManagerPolicyID)

		return nil
	})
}

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
