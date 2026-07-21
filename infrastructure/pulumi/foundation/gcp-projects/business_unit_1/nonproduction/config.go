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

// Stack configuration for this leaf — the Pulumi analogue of upstream
// 4-projects/business_unit_1/nonproduction/variables.tf (with the *.auto.tfvars
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
	SVPCProjectEnabled        bool
	FloatingProjectEnabled    bool
	OSSFloatingProjectEnabled bool

	// Apps whose PLATFORM-ISSUED deploy identity this leaf mints on the env's
	// oss-floating project. Upstream seeds its app-infra pipeline SAs here too
	// (modules/single_project sa_roles) — one stage ABOVE the 5-app-infra
	// workloads they deploy, so the identity cannot edit its own grants.
	Apps []AppIdentityConfig

	// BootstrapStackName is the gcp-bootstrap stack providing the shared WIF
	// pool. Required only when Apps is non-empty.
	BootstrapStackName    string
	PeeringProjectEnabled bool

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
		OrgStackName:     conf.Get("org_stack_name"),
		NetworkStackName: conf.Get("network_stack_name"),
		EnvStackName:     conf.Get("env_stack_name"),
	}
	// Cross-stage references default to the live Pulumi Cloud stacks (ipv1337
	// org) under the upstream-layout leaf names: the environment and network
	// stages are per-env LEAF projects with a single production stack, and the
	// org stage root is envs/shared. Only the environment reference is always
	// consumed; the org/network references are used only when a project type
	// that needs them is enabled (see main()), so org_stack_name is optional here.
	if c.EnvStackName == "" {
		c.EnvStackName = fmt.Sprintf("ipv1337/foundation-environments-%s/production", c.Env)
	}
	if c.OrgStackName == "" {
		c.OrgStackName = "ipv1337/foundation-org-shared/production"
	}
	if c.NetworkStackName == "" {
		c.NetworkStackName = fmt.Sprintf("ipv1337/foundation-networks-%s/production", c.Env)
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
	// Defaults false: the OSS floating project is a monorepo-specific addition
	// (a home for open-source apps like oauth-user-inspector), not part of the
	// upstream reference set, so the example stays unchanged unless opted in.
	c.OSSFloatingProjectEnabled = conf.Get("oss_floating_project_enabled") == "true"

	c.BootstrapStackName = conf.Get("bootstrap_stack_name")

	// Per-app deploy identities. Declared as a comma-separated list so adding
	// an app is a one-line config change.
	for _, name := range splitAppList(conf.Get("apps")) {
		app := AppIdentityConfig{
			Name:            name,
			DeployAccountID: conf.Get(name + "_deploy_account_id"),
			DeployRoles:     splitAppList(conf.Get(name + "_deploy_roles")),
		}
		if len(app.DeployRoles) == 0 {
			app.DeployRoles = defaultAppDeployRoles
		}
		c.Apps = append(c.Apps, app)
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

// AppIdentityConfig is one application's platform-issued deploy identity.
type AppIdentityConfig struct {
	Name            string
	DeployAccountID string
	DeployRoles     []string
}

// GitHubEnvironment is the per-env GitHub Environment permitted to impersonate
// this app's deploy SA, e.g. "oauth-user-inspector-development". The WIF
// provider already pins the repository, so the environment is the isolation
// layer.
func (a AppIdentityConfig) GitHubEnvironment(env string) string {
	return a.Name + "-" + env
}

// defaultAppDeployRoles is replicated EXACTLY from the app-side stack this
// identity was adopted from (oauth-user-inspector/infra/identity) — adoption
// must be permission-neutral.
// defaultAppInfraPipelineRoles are what the BU's app-infra pipeline SA needs to
// apply stage-5 workloads: manage Cloud Run services, act as the runtime SA it
// sets on them, and read its own project's service usage. Deliberately the same
// shape as a per-app deploy SA — the pipeline applies the same class of
// resource, just for the whole BU leaf rather than one app.
var defaultAppInfraPipelineRoles = []string{
	"roles/run.admin",
	"roles/iam.serviceAccountUser",
	"roles/serviceusage.serviceUsageConsumer",
	"roles/logging.viewer",
}

var defaultAppDeployRoles = []string{
	"roles/run.admin",
	"roles/iam.serviceAccountUser",
	"roles/serviceusage.serviceUsageConsumer",
	"roles/logging.viewer",
}

// splitAppList parses a comma-separated config list, trimming blanks.
func splitAppList(v string) []string {
	var out []string
	for _, p := range strings.Split(v, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
