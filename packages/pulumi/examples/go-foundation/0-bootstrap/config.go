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

// Mirrors: 0-bootstrap/variables.tf in the TF foundation — the stage's input
// surface. In the Pulumi port, variables are Pulumi stack config values loaded
// into the Config struct below (see Pulumi.production.yaml.example for the
// tfvars equivalent).

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Config holds all configuration for the bootstrap stage, mirroring the
// Terraform foundation's variables.tf for full feature parity.
type Config struct {
	OrgID                 string
	BillingAccount        string
	ProjectPrefix         string
	FolderPrefix          string
	BucketPrefix          string
	DefaultRegion         string
	DefaultRegion2        string
	DefaultRegionGCS      string
	DefaultRegionKMS      string // Dedicated KMS region (default: "us"), matches upstream
	KMSKeyProtectionLevel string // "SOFTWARE" or "HSM" — matches upstream key_protection_level
	Parent                string // Full parent path: "organizations/123" or "folders/456"
	ParentFolder          string // Raw folder ID, empty if deploying at org root
	ParentType            string // "organization" or "folder"
	ParentID              string // The numeric ID for parent-level IAM bindings
	OrgPolicyAdminRole    bool
	// EnforceOrgBillingCreator gates the authoritative org-level
	// roles/billing.creator binding. Defaults true (upstream behavior); set false
	// for a co-tenant foundation so it does not clobber another foundation's
	// org-wide billing.creator members.
	EnforceOrgBillingCreator     bool
	BucketForceDestroy           bool
	BucketTFStateKMSForceDestroy bool   // When deleting a bucket, this boolean option will delete the KMS keys
	RandomSuffix                 bool   // Append random hex suffix to project IDs (default: true)
	ProjectDeletionPolicy        string // "PREVENT" or "DELETE" (default: "PREVENT")
	FolderDeletionProtection     bool   // Prevent Terraform from destroying the folder (default: true)

	// Groups — required for org admin and billing workflows
	GroupOrgAdmins     string
	GroupBillingAdmins string
	BillingDataUsers   string
	AuditDataUsers     string

	// Optional groups — governance groups consumed by 1-org for IAM bindings.
	// These match the upstream Terraform foundation's optional_groups object.
	GCPSecurityReviewer   string
	GCPNetworkViewer      string
	GCPSCCAdmin           string
	GCPGlobalSecretsAdmin string
	GCPKMSAdmin           string

	// Group creation — when true, the bootstrap stage creates the groups
	// via Cloud Identity instead of assuming they pre-exist.
	// Mirrors: var.groups.create_required_groups / create_optional_groups
	CreateRequiredGroups bool
	CreateOptionalGroups bool
	InitialGroupConfig   string // "WITH_INITIAL_OWNER", "EMPTY", etc.
	// GroupsBillingProject is a pre-existing project that provides the quota for
	// Cloud Identity API calls during group creation (mirrors upstream's
	// var.groups.billing_project). Required when CreateRequiredGroups or
	// CreateOptionalGroups is true.
	GroupsBillingProject string

	// GitHub Actions CI/CD — default CI/CD provider.
	// Set github_owner to enable Workload Identity Federation.
	GitHubOwner           string
	GitHubRepoBootstrap   string
	GitHubRepoOrg         string
	GitHubRepoEnv         string
	GitHubRepoNet         string
	GitHubRepoProj        string
	WIFAttributeCondition string // Optional: override the default WIF attribute condition
}

func loadConfig(ctx *pulumi.Context) *Config {
	conf := config.New(ctx, "")
	c := &Config{
		OrgID:                 conf.Require("org_id"),
		BillingAccount:        conf.Require("billing_account"),
		ProjectPrefix:         conf.Get("project_prefix"),
		FolderPrefix:          conf.Get("folder_prefix"),
		BucketPrefix:          conf.Get("bucket_prefix"),
		DefaultRegion:         conf.Get("default_region"),
		DefaultRegion2:        conf.Get("default_region_2"),
		DefaultRegionGCS:      conf.Get("default_region_gcs"),
		DefaultRegionKMS:      conf.Get("default_region_kms"),
		KMSKeyProtectionLevel: conf.Get("kms_key_protection_level"),
		ProjectDeletionPolicy: conf.Get("project_deletion_policy"),
		ParentFolder:          conf.Get("parent_folder"),
		GroupOrgAdmins:        conf.Require("group_org_admins"),
		GroupBillingAdmins:    conf.Require("group_billing_admins"),
		BillingDataUsers:      conf.Require("billing_data_users"),
		AuditDataUsers:        conf.Require("audit_data_users"),
		// Optional groups — empty string means not configured
		GCPSecurityReviewer:   conf.Get("gcp_security_reviewer"),
		GCPNetworkViewer:      conf.Get("gcp_network_viewer"),
		GCPSCCAdmin:           conf.Get("gcp_scc_admin"),
		GCPGlobalSecretsAdmin: conf.Get("gcp_global_secrets_admin"),
		GCPKMSAdmin:           conf.Get("gcp_kms_admin"),
		// GitHub Actions CI/CD
		GitHubOwner:           conf.Get("github_owner"),
		GitHubRepoBootstrap:   conf.Get("github_repo_bootstrap"),
		GitHubRepoOrg:         conf.Get("github_repo_org"),
		GitHubRepoEnv:         conf.Get("github_repo_env"),
		GitHubRepoNet:         conf.Get("github_repo_net"),
		GitHubRepoProj:        conf.Get("github_repo_proj"),
		WIFAttributeCondition: conf.Get("wif_attribute_condition"),
	}

	c.OrgPolicyAdminRole = conf.Get("org_policy_admin_role") == "true"
	// Default true (upstream behavior); set "false" for a co-tenant foundation.
	c.EnforceOrgBillingCreator = conf.Get("enforce_org_billing_creator") != "false"
	c.BucketForceDestroy = conf.Get("bucket_force_destroy") == "true"
	c.BucketTFStateKMSForceDestroy = conf.Get("bucket_tfstate_kms_force_destroy") == "true"
	c.FolderDeletionProtection = conf.Get("folder_deletion_protection") != "false"
	c.CreateRequiredGroups = conf.Get("create_required_groups") == "true"
	c.CreateOptionalGroups = conf.Get("create_optional_groups") == "true"
	c.GroupsBillingProject = conf.Get("groups_billing_project")
	c.InitialGroupConfig = conf.Get("initial_group_config")
	if c.InitialGroupConfig == "" {
		c.InitialGroupConfig = "WITH_INITIAL_OWNER"
	}

	// Random suffix defaults to true, matching upstream Terraform foundation.
	// Set to "false" to use deterministic project IDs.
	randomSuffix := conf.Get("random_suffix")
	c.RandomSuffix = randomSuffix != "false"

	// Apply defaults matching the Terraform foundation
	if c.ProjectPrefix == "" {
		c.ProjectPrefix = "prj"
	}
	if c.FolderPrefix == "" {
		c.FolderPrefix = "fldr"
	}
	if c.BucketPrefix == "" {
		c.BucketPrefix = "bkt"
	}
	if c.ProjectDeletionPolicy == "" {
		c.ProjectDeletionPolicy = "PREVENT"
	}
	if c.DefaultRegion == "" {
		c.DefaultRegion = "us-central1"
	}
	if c.DefaultRegion2 == "" {
		c.DefaultRegion2 = "us-west1"
	}
	if c.DefaultRegionGCS == "" {
		c.DefaultRegionGCS = "US"
	}
	if c.DefaultRegionKMS == "" {
		c.DefaultRegionKMS = "us"
	}
	if c.KMSKeyProtectionLevel == "" {
		c.KMSKeyProtectionLevel = "SOFTWARE"
	}

	// Determine parent: either a specific folder or the org root.
	// This controls where top-level folders and parent-level IAM are applied.
	if c.ParentFolder != "" {
		c.Parent = "folders/" + c.ParentFolder
		c.ParentType = "folder"
		c.ParentID = c.ParentFolder
	} else {
		c.Parent = "organizations/" + c.OrgID
		c.ParentType = "organization"
		c.ParentID = c.OrgID
	}

	return c
}
