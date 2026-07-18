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

package main

import (
	"fmt"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-org/modules/network"
)

// OrgProjects holds outputs from all org-level project deployments.
type OrgProjects struct {
	AuditLogsProjectID        pulumi.StringOutput
	AuditLogsApisReady        pulumi.Resource // gates log-sink destinations that need Logging/BigQuery/Pub/Sub APIs on a cold deploy
	BillingExportProjectID    pulumi.StringOutput
	BillingExportApisReady    pulumi.Resource // gates resources that need BigQuery API on the billing-export project
	SCCProjectID              pulumi.StringOutput
	SCCApisReady              pulumi.Resource // gates SCC notification + CAI monitoring resources on freshly-enabled APIs
	OrgKMSProjectID           pulumi.StringOutput
	OrgSecretsProjectID       pulumi.StringOutput
	InterconnectProjectID     pulumi.StringOutput
	InterconnectProjectNumber pulumi.StringOutput // upstream: interconnect_project_number
	NetHubProjectID           pulumi.StringOutput
	NetHubProjectNumber       pulumi.StringOutput // upstream: net_hub_project_number
	NetworkProjectIDs         map[string]pulumi.StringOutput
	NetworkProjectNumbers     map[string]pulumi.StringOutput
}

// createProject is a helper that creates a standardized project using the
// shared Project component from the Vitruvian Pulumi Library.
// Labels mirror the Terraform foundation's project labeling convention (D3).
// Budget and DefaultServiceAccount are optional — pass nil/empty to skip.
// Returns both the project ID and project number for cross-stage exports.
func createProject(ctx *pulumi.Context, name, projectID string, folderID pulumi.StringOutput, cfg *OrgConfig, apis []string, labels map[string]string, budget *project.BudgetConfig) (pulumi.StringOutput, pulumi.StringOutput, pulumi.Resource, error) {
	// Convert labels to Pulumi StringMap
	pulumiLabels := pulumi.StringMap{}
	for k, v := range labels {
		pulumiLabels[k] = pulumi.String(v)
	}

	p, err := project.NewProject(ctx, name, &project.ProjectArgs{
		ProjectID:             pulumi.String(projectID),
		Name:                  pulumi.String(projectID),
		FolderID:              folderID,
		BillingAccount:        pulumi.String(cfg.BillingAccount),
		RandomProjectID:       cfg.RandomSuffix,
		ActivateApis:          apis,
		Labels:                pulumiLabels,
		DeletionPolicy:        pulumi.String(cfg.ProjectDeletionPolicy),
		Budget:                budget,
		DefaultServiceAccount: cfg.DefaultServiceAccount,
		// Cold-deploy fix: wait for freshly-enabled APIs to propagate before
		// ApisReady resolves; consumers gate on it via DependsOn.
		ApiPropagationSeconds: cfg.ApiPropagationSeconds,
	})
	if err != nil {
		return pulumi.StringOutput{}, pulumi.StringOutput{}, nil, err
	}
	return p.Project.ProjectId, p.Project.Number, p.ApisReady, nil
}

// budgetFor converts a PerProjectBudget to a BudgetConfig for the project
// library. Returns nil when pb is nil or the amount is 0.
// Matches upstream per-project budget variable shape where each project has
// independent amount, alert_spent_percents, alert_pubsub_topic, and
// budget_alert_spend_basis fields.
func budgetFor(pb *PerProjectBudget) *project.BudgetConfig {
	if pb == nil || pb.Amount == 0 {
		return nil
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
		Amount:             pb.Amount,
		AlertSpentPercents: alertPercents,
		AlertPubSubTopic:   pb.AlertPubSubTopic,
		AlertSpendBasis:    spendBasis,
	}
}

// getProjectBudget returns the per-project budget config for the named project.
// Returns nil when ProjectBudget is not configured.
func getProjectBudget(cfg *OrgConfig, name string) *PerProjectBudget {
	if cfg.ProjectBudget == nil {
		return nil
	}
	switch name {
	case "logging":
		return &cfg.ProjectBudget.OrgAuditLogs
	case "billing_export":
		return &cfg.ProjectBudget.OrgBillingExport
	case "scc":
		return &cfg.ProjectBudget.SCC
	case "kms":
		return &cfg.ProjectBudget.CommonKMS
	case "secrets":
		return &cfg.ProjectBudget.OrgSecrets
	case "interconnect":
		return &cfg.ProjectBudget.Interconnect
	case "net_hub":
		return &cfg.ProjectBudget.NetHub
	case "shared_network":
		return &cfg.ProjectBudget.SharedNetwork
	default:
		return nil
	}
}

// deployOrgProjects creates all organization-level projects under the Common
// and Network folders. This mirrors the Terraform foundation's 1-org projects.tf.
func deployOrgProjects(ctx *pulumi.Context, cfg *OrgConfig, folders *Folders) (*OrgProjects, error) {
	// Convert IDOutput to StringOutput for folder IDs
	commonFolderID := folders.Common.ID().ApplyT(func(id pulumi.ID) string {
		return string(id)
	}).(pulumi.StringOutput)
	networkFolderID := folders.Network.ID().ApplyT(func(id pulumi.ID) string {
		return string(id)
	}).(pulumi.StringOutput)

	// ========================================================================
	// Common Folder Projects
	// ========================================================================

	// Audit Logs — centralized logging destination
	// pubsub + storage-api are required on a cold deploy: the centralized
	// logging component creates a Pub/Sub topic and a GCS bucket here.
	auditLogsProjectID, _, auditLogsApisReady, err := createProject(
		ctx, "org-logging",
		fmt.Sprintf("%s-c-logging", cfg.ProjectPrefix),
		commonFolderID, cfg,
		[]string{"logging.googleapis.com", "bigquery.googleapis.com", "billingbudgets.googleapis.com", "pubsub.googleapis.com", "storage-api.googleapis.com"},
		map[string]string{
			"environment":       "common",
			"application_name":  "org-logging",
			"billing_code":      "1234",
			"primary_contact":   "james_nguyen",
			"secondary_contact": "christine_kim",
			"business_code":     "shared",
			"env_code":          "c",
			"vpc":               "none",
		},
		budgetFor(getProjectBudget(cfg, "logging")),
	)
	if err != nil {
		return nil, err
	}

	// Billing Export — BigQuery dataset for billing data
	billingExportProjectID, _, billingExportApisReady, err := createProject(
		ctx, "org-billing-export",
		fmt.Sprintf("%s-c-billing-export", cfg.ProjectPrefix),
		commonFolderID, cfg,
		[]string{"logging.googleapis.com", "bigquery.googleapis.com", "billingbudgets.googleapis.com"},
		map[string]string{
			"environment":       "common",
			"application_name":  "org-billing-export",
			"billing_code":      "1234",
			"primary_contact":   "james_nguyen",
			"secondary_contact": "christine_kim",
			"business_code":     "shared",
			"env_code":          "c",
			"vpc":               "none",
		},
		budgetFor(getProjectBudget(cfg, "billing_export")),
	)
	if err != nil {
		return nil, err
	}

	// Security Command Center — SCC notifications via Pub/Sub
	// The CAI monitoring pipeline (asset feed → Pub/Sub → Cloud Function v2)
	// also lives here, so on a cold deploy this project additionally needs:
	// cloudasset (org feed), cloudbuild/cloudfunctions/artifactregistry/run/
	// eventarc (Cloud Function v2 build + trigger), and storage-api (source
	// bucket). Without them the first apply hard-fails.
	sccProjectID, _, sccApisReady, err := createProject(
		ctx, "org-scc",
		fmt.Sprintf("%s-c-scc", cfg.ProjectPrefix),
		commonFolderID, cfg,
		[]string{
			"logging.googleapis.com",
			"securitycenter.googleapis.com",
			"pubsub.googleapis.com",
			"billingbudgets.googleapis.com",
			"cloudkms.googleapis.com",
			"cloudasset.googleapis.com",
			"cloudbuild.googleapis.com",
			"cloudfunctions.googleapis.com",
			"artifactregistry.googleapis.com",
			"run.googleapis.com",
			"eventarc.googleapis.com",
			"storage-api.googleapis.com",
		},
		map[string]string{
			"environment":       "common",
			"application_name":  "org-scc",
			"billing_code":      "1234",
			"primary_contact":   "james_nguyen",
			"secondary_contact": "christine_kim",
			"business_code":     "shared",
			"env_code":          "c",
			"vpc":               "none",
		},
		budgetFor(getProjectBudget(cfg, "scc")),
	)
	if err != nil {
		return nil, err
	}

	// KMS — org-level key management
	orgKMSProjectID, _, _, err := createProject(
		ctx, "org-kms",
		fmt.Sprintf("%s-c-kms", cfg.ProjectPrefix),
		commonFolderID, cfg,
		[]string{"logging.googleapis.com", "cloudkms.googleapis.com", "billingbudgets.googleapis.com"},
		map[string]string{
			"environment":       "common",
			"application_name":  "org-kms",
			"billing_code":      "1234",
			"primary_contact":   "james_nguyen",
			"secondary_contact": "christine_kim",
			"business_code":     "shared",
			"env_code":          "c",
			"vpc":               "none",
		},
		budgetFor(getProjectBudget(cfg, "kms")),
	)
	if err != nil {
		return nil, err
	}

	// Secrets — org-level secret storage
	orgSecretsProjectID, _, _, err := createProject(
		ctx, "org-secrets",
		fmt.Sprintf("%s-c-secrets", cfg.ProjectPrefix),
		commonFolderID, cfg,
		[]string{"logging.googleapis.com", "secretmanager.googleapis.com", "billingbudgets.googleapis.com"},
		map[string]string{
			"environment":       "common",
			"application_name":  "org-secrets",
			"billing_code":      "1234",
			"primary_contact":   "james_nguyen",
			"secondary_contact": "christine_kim",
			"business_code":     "shared",
			"env_code":          "c",
			"vpc":               "none",
		},
		budgetFor(getProjectBudget(cfg, "secrets")),
	)
	if err != nil {
		return nil, err
	}

	// ========================================================================
	// Network Folder Projects
	// ========================================================================

	// Interconnect — Dedicated/Partner Interconnect connections
	interconnectProjectID, interconnectProjectNumber, _, err := createProject(
		ctx, "org-interconnect",
		fmt.Sprintf("%s-net-interconnect", cfg.ProjectPrefix),
		networkFolderID, cfg,
		[]string{"billingbudgets.googleapis.com", "compute.googleapis.com"},
		map[string]string{
			"environment":       "network",
			"application_name":  "org-interconnect",
			"billing_code":      "1234",
			"primary_contact":   "james_nguyen",
			"secondary_contact": "christine_kim",
			"business_code":     "shared",
			"env_code":          "net",
			"vpc":               "none",
		},
		budgetFor(getProjectBudget(cfg, "interconnect")),
	)
	if err != nil {
		return nil, err
	}

	// Network Hub — conditional on hub-and-spoke architecture (D5)
	var netHubProjectID pulumi.StringOutput
	var netHubProjectNumber pulumi.StringOutput
	if cfg.EnableHubAndSpoke {
		netHubProjectID, netHubProjectNumber, _, err = createProject(
			ctx, "org-net-hub",
			fmt.Sprintf("%s-net-hub", cfg.ProjectPrefix),
			networkFolderID, cfg,
			[]string{
				"compute.googleapis.com",
				"dns.googleapis.com",
				"servicenetworking.googleapis.com",
				"logging.googleapis.com",
				"cloudresourcemanager.googleapis.com",
				"billingbudgets.googleapis.com",
			},
			map[string]string{
				"environment":       "network",
				"application_name":  "org-net-hub",
				"billing_code":      "1234",
				"primary_contact":   "james_nguyen",
				"secondary_contact": "christine_kim",
				"business_code":     "shared",
				"env_code":          "net",
				"vpc":               "svpc",
			},
			budgetFor(getProjectBudget(cfg, "net_hub")),
		)
		if err != nil {
			return nil, err
		}
	}

	// Per-environment Shared VPC host projects under the Network folder
	// Mirrors: module "environment_network" in upstream projects.tf. Each
	// project is created by the network module (modules/network).
	envCodes := map[string]string{"development": "d", "nonproduction": "n", "production": "p"}
	networkProjectIDs := make(map[string]pulumi.StringOutput)
	networkProjectNumbers := make(map[string]pulumi.StringOutput)
	for env, code := range envCodes {
		netRes, err := network.New(ctx, fmt.Sprintf("org-net-%s", env), &network.Args{
			Env:                   env,
			EnvCode:               code,
			ProjectPrefix:         cfg.ProjectPrefix,
			FolderID:              networkFolderID,
			BillingAccount:        cfg.BillingAccount,
			RandomSuffix:          cfg.RandomSuffix,
			ProjectDeletionPolicy: cfg.ProjectDeletionPolicy,
			DefaultServiceAccount: cfg.DefaultServiceAccount,
			Budget:                budgetFor(getProjectBudget(cfg, "shared_network")),
			ApiPropagationSeconds: cfg.ApiPropagationSeconds,
		})
		if err != nil {
			return nil, err
		}
		networkProjectIDs[env] = netRes.ProjectID
		networkProjectNumbers[env] = netRes.ProjectNumber
	}

	return &OrgProjects{
		AuditLogsProjectID:        auditLogsProjectID,
		AuditLogsApisReady:        auditLogsApisReady,
		BillingExportProjectID:    billingExportProjectID,
		BillingExportApisReady:    billingExportApisReady,
		SCCProjectID:              sccProjectID,
		SCCApisReady:              sccApisReady,
		OrgKMSProjectID:           orgKMSProjectID,
		OrgSecretsProjectID:       orgSecretsProjectID,
		InterconnectProjectID:     interconnectProjectID,
		InterconnectProjectNumber: interconnectProjectNumber,
		NetHubProjectID:           netHubProjectID,
		NetHubProjectNumber:       netHubProjectNumber,
		NetworkProjectIDs:         networkProjectIDs,
		NetworkProjectNumbers:     networkProjectNumbers,
	}, nil
}
