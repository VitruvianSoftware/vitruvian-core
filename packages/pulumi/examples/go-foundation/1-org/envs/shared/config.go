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

// Stack configuration for the 1-org shared environment.
// This mirrors the Terraform foundation's 1-org/envs/shared/variables.tf:
// every upstream variable maps to a Pulumi config key loaded here
// (tfvars → Pulumi.<stack>.yaml is the engine adaptation).

package main

import (
	"strings"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// RetentionPolicy configures data retention on the log export storage bucket.
// When IsLocked is true, the retention policy cannot be shortened or removed.
type RetentionPolicy struct {
	IsLocked            bool
	RetentionPeriodDays int
}

// PerProjectBudget holds the budget configuration for a single project.
// Each field matches the upstream TF per-project budget variables:
//   - Amount:             e.g. org_audit_logs_budget_amount (default 1000)
//   - AlertSpentPercents: e.g. org_audit_logs_alert_spent_percents (default [1.2])
//   - AlertPubSubTopic:   e.g. org_audit_logs_alert_pubsub_topic (default null)
//   - AlertSpendBasis:    e.g. org_audit_logs_budget_alert_spend_basis (default "FORECASTED_SPEND")
type PerProjectBudget struct {
	Amount             float64
	AlertSpentPercents []float64
	AlertPubSubTopic   string
	AlertSpendBasis    string
}

// ProjectBudgetConfig mirrors the TF foundation's project_budget variable (H2).
// Each project has independent budget controls matching the upstream per-project
// variable shape with amount, alert_spent_percents, alert_pubsub_topic, and
// budget_alert_spend_basis.
type ProjectBudgetConfig struct {
	OrgAuditLogs     PerProjectBudget
	OrgBillingExport PerProjectBudget
	SCC              PerProjectBudget
	CommonKMS        PerProjectBudget
	OrgSecrets       PerProjectBudget
	Interconnect     PerProjectBudget
	NetHub           PerProjectBudget
	SharedNetwork    PerProjectBudget
}

// OrgConfig holds all configuration for the organization stage.
// This mirrors all variables from the Terraform foundation's 1-org/envs/shared/variables.tf.
type OrgConfig struct {
	// Core identifiers
	OrgID          string
	BillingAccount string
	ProjectPrefix  string
	FolderPrefix   string
	DefaultRegion  string
	Parent         string
	ParentFolder   string
	ParentID       string // Numeric ID (folder or org)
	ParentType     string // "organization" or "folder"

	// Bootstrap cross-reference
	BootstrapStackName  string
	BootstrapFolderName string // Resolved from StackReference or config

	// Governance groups (from bootstrap required_groups/optional_groups)
	GroupOrgAdmins        string // email of org admins group
	GroupBillingAdmins    string // email of billing admins group
	AuditDataUsers        string
	BillingDataUsers      string
	GCPSecurityReviewer   string
	GCPNetworkViewer      string
	GCPSCCAdmin           string
	GCPGlobalSecretsAdmin string
	GCPKMSAdmin           string
	GCPAuditViewer        string // G7: separate audit viewer group

	// Domain restrictions
	DomainsToAllow           []string
	EssentialContactsDomains []string

	// SCC
	SCCNotificationName   string
	SCCNotificationFilter string
	EnableSCCResources    bool

	// Policies
	CreateAccessContextManagerPolicy bool
	EnforceAllowedWorkerPools        bool
	EnableHubAndSpoke                bool
	AllowedWorkerPoolID              string // G1: private worker pool for cloudbuild policy

	// Cross-stage references
	NetworksSAEmail string // G8: networks pipeline SA email for hub-and-spoke IAM

	// KMS
	EnableKMSKeyUsageTracking bool

	// Projects
	RandomSuffix             bool
	ProjectDeletionPolicy    string
	FolderDeletionProtection bool
	DefaultServiceAccount    string

	// Project Budgets (H2)
	ProjectBudget *ProjectBudgetConfig

	// Logging — storage options (H6, H7, H8)
	LogExportStorageLocation        string
	LogExportStorageForceDestroy    bool
	LogExportStorageVersioning      bool
	LogExportStorageRetentionPolicy *RetentionPolicy

	// Logging — billing account sink (matches upstream enable_billing_account_sink)
	EnableBillingAccountSink bool

	// Logging — billing export
	BillingExportDatasetLocation string

	// Essential Contacts (H9)
	EssentialContactsLanguage string

	// Tags (H14)
	CreateUniqueTagKey bool
}

func loadOrgConfig(ctx *pulumi.Context) *OrgConfig {
	conf := config.New(ctx, "")
	c := &OrgConfig{
		OrgID:              conf.Require("org_id"),
		BillingAccount:     conf.Require("billing_account"),
		ProjectPrefix:      conf.Get("project_prefix"),
		FolderPrefix:       conf.Get("folder_prefix"),
		DefaultRegion:      conf.Get("default_region"),
		BootstrapStackName: conf.Require("bootstrap_stack_name"),

		// Governance groups — pulled from bootstrap outputs or overridden locally
		GroupOrgAdmins:        conf.Get("group_org_admins"),
		GroupBillingAdmins:    conf.Get("group_billing_admins"),
		AuditDataUsers:        conf.Get("audit_data_users"),
		BillingDataUsers:      conf.Get("billing_data_users"),
		GCPSecurityReviewer:   conf.Get("gcp_security_reviewer"),
		GCPNetworkViewer:      conf.Get("gcp_network_viewer"),
		GCPSCCAdmin:           conf.Get("gcp_scc_admin"),
		GCPGlobalSecretsAdmin: conf.Get("gcp_global_secrets_admin"),
		GCPKMSAdmin:           conf.Get("gcp_kms_admin"),
		GCPAuditViewer:        conf.Get("gcp_audit_viewer"),

		// SCC
		SCCNotificationName:      conf.Get("scc_notification_name"),
		SCCNotificationFilter:    conf.Get("scc_notification_filter"),
		EnableSCCResources:       conf.Get("enable_scc_resources_in_pulumi") == "true",
		EnableBillingAccountSink: conf.Get("enable_billing_account_sink") != "false",

		// Policies
		// Defaults false, matching upstream variables.tf
		// (create_access_context_manager_access_policy = false). An org has a
		// single org-level Access Context Manager policy, so creating one is
		// opt-in: enable only when this stage should own that policy. Defaulting
		// it true (the prior behavior) silently created an org-level singleton on
		// every deployment — a footgun for co-tenant foundations sharing an org.
		CreateAccessContextManagerPolicy: conf.Get("create_access_context_manager_policy") == "true",
		EnforceAllowedWorkerPools:        conf.Get("enforce_allowed_worker_pools") == "true",
		EnableHubAndSpoke:                conf.Get("enable_hub_and_spoke") == "true",
		AllowedWorkerPoolID:              conf.Get("allowed_worker_pool_id"),

		// Cross-stage references
		NetworksSAEmail: conf.Get("networks_sa_email"),

		// KMS
		EnableKMSKeyUsageTracking: conf.Get("enable_kms_key_usage_tracking") != "false",

		// Projects
		ProjectDeletionPolicy:    conf.Get("project_deletion_policy"),
		FolderDeletionProtection: conf.Get("folder_deletion_protection") != "false",
		DefaultServiceAccount:    conf.Get("default_service_account"),

		// Logging storage options (H6, H7)
		LogExportStorageLocation:     conf.Get("log_export_storage_location"),
		LogExportStorageForceDestroy: conf.Get("log_export_storage_force_destroy") == "true",
		LogExportStorageVersioning:   conf.Get("log_export_storage_versioning") == "true",

		// Logging billing export
		BillingExportDatasetLocation: conf.Get("billing_export_dataset_location"),

		// Essential Contacts (H9)
		EssentialContactsLanguage: conf.Get("essential_contacts_language"),

		// Tags
		CreateUniqueTagKey: conf.Get("create_unique_tag_key") == "true",

		// Bootstrap
		BootstrapFolderName: conf.Get("bootstrap_folder_name"),
	}

	// Parse structured config for ProjectBudget
	var pb ProjectBudgetConfig
	if err := conf.GetObject("project_budget", &pb); err == nil {
		c.ProjectBudget = &pb
	}

	// Random suffix defaults to true, matching upstream Terraform foundation.
	randomSuffix := conf.Get("random_suffix")
	c.RandomSuffix = randomSuffix != "false"

	// Parse comma-separated domain lists
	if domainsStr := conf.Get("domains_to_allow"); domainsStr != "" {
		c.DomainsToAllow = strings.Split(domainsStr, ",")
	}
	if contactsDomains := conf.Get("essential_contacts_domains"); contactsDomains != "" {
		c.EssentialContactsDomains = strings.Split(contactsDomains, ",")
	}

	// Apply defaults
	if c.ProjectPrefix == "" {
		c.ProjectPrefix = "prj"
	}
	if c.FolderPrefix == "" {
		c.FolderPrefix = "fldr"
	}
	if c.DefaultRegion == "" {
		c.DefaultRegion = "us-central1"
	}
	if c.SCCNotificationFilter == "" {
		c.SCCNotificationFilter = `state = "ACTIVE"`
	}
	if c.SCCNotificationName == "" {
		c.SCCNotificationName = "scc-notify"
	}
	if c.ProjectDeletionPolicy == "" {
		c.ProjectDeletionPolicy = "PREVENT"
	}
	if c.DefaultServiceAccount == "" {
		c.DefaultServiceAccount = "deprivilege"
	}
	if c.EssentialContactsLanguage == "" {
		c.EssentialContactsLanguage = "en"
	}

	// Log storage retention policy (H8)
	if retentionDays := conf.GetInt("log_export_storage_retention_days"); retentionDays > 0 {
		c.LogExportStorageRetentionPolicy = &RetentionPolicy{
			IsLocked:            conf.Get("log_export_storage_retention_locked") == "true",
			RetentionPeriodDays: retentionDays,
		}
	}

	// Storage location defaults to DefaultRegion when not set
	if c.LogExportStorageLocation == "" {
		c.LogExportStorageLocation = c.DefaultRegion
	}
	if c.BillingExportDatasetLocation == "" {
		c.BillingExportDatasetLocation = c.DefaultRegion
	}

	parentFolder := conf.Get("parent_folder")
	if parentFolder != "" {
		c.Parent = "folders/" + parentFolder
		c.ParentFolder = parentFolder
		c.ParentID = parentFolder
		c.ParentType = "folder"
	} else {
		c.Parent = "organizations/" + c.OrgID
		c.ParentID = c.OrgID
		c.ParentType = "organization"
	}

	return c
}
