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

// Mirrors: 0-bootstrap/outputs.tf in the TF foundation — the common stage
// outputs consumed by downstream stages via Stack References. Builder-specific
// outputs live in outputs_github.go / outputs_*.go.example, mirroring
// upstream's outputs_cb.tf / outputs_*.tf.example split.

package main

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// exportOutputs wires the common stage exports, matching TF outputs.tf.
func exportOutputs(
	ctx *pulumi.Context,
	cfg *Config,
	bootstrapFolder *organizations.Folder,
	seed *SeedProject,
	cicd *CICDProject,
	sas map[string]*serviceaccount.Account,
	buildOutputs *CICDBuildOutputs,
) {
	// 1. Project + state outputs — matching TF outputs.tf
	ctx.Export("seed_project_id", seed.ProjectID)
	ctx.Export("cloudbuild_project_id", cicd.ProjectID)
	ctx.Export("gcs_bucket_tfstate", seed.StateBucketName)
	ctx.Export("projects_gcs_bucket_tfstate", seed.ProjectsStateBucketName)
	ctx.Export("state_bucket_kms_key_id", seed.KMSKeyID)
	saOutputNames := map[string]string{
		"bootstrap": "bootstrap",
		"org":       "organization",
		"env":       "environment",
		"net":       "networks",
		"proj":      "projects",
	}
	for key, sa := range sas {
		prefix, ok := saOutputNames[key]
		if !ok {
			prefix = key
		}
		ctx.Export(prefix+"_step_terraform_service_account_email", sa.Email)
	}

	// 2. Common config — composite output consumed by all downstream
	// stages via Stack References. Mirrors Terraform's common_config output.
	ctx.Export("common_config", pulumi.Map{
		"org_id":                pulumi.String(cfg.OrgID),
		"parent_folder":         pulumi.String(cfg.ParentFolder),
		"billing_account":       pulumi.String(cfg.BillingAccount),
		"default_region":        pulumi.String(cfg.DefaultRegion),
		"default_region_2":      pulumi.String(cfg.DefaultRegion2),
		"default_region_gcs":    pulumi.String(cfg.DefaultRegionGCS),
		"default_region_kms":    pulumi.String(cfg.DefaultRegionKMS),
		"project_prefix":        pulumi.String(cfg.ProjectPrefix),
		"folder_prefix":         pulumi.String(cfg.FolderPrefix),
		"parent_id":             pulumi.String(cfg.Parent),
		"bootstrap_folder_name": bootstrapFolder.Name,
	})

	// 3. Group outputs — consumed by 1-org for IAM bindings.
	ctx.Export("required_groups", pulumi.Map{
		"group_org_admins":     pulumi.String(cfg.GroupOrgAdmins),
		"group_billing_admins": pulumi.String(cfg.GroupBillingAdmins),
		"billing_data_users":   pulumi.String(cfg.BillingDataUsers),
		"audit_data_users":     pulumi.String(cfg.AuditDataUsers),
	})
	ctx.Export("optional_groups", pulumi.Map{
		"gcp_security_reviewer":    pulumi.String(cfg.GCPSecurityReviewer),
		"gcp_network_viewer":       pulumi.String(cfg.GCPNetworkViewer),
		"gcp_scc_admin":            pulumi.String(cfg.GCPSCCAdmin),
		"gcp_global_secrets_admin": pulumi.String(cfg.GCPGlobalSecretsAdmin),
		"gcp_kms_admin":            pulumi.String(cfg.GCPKMSAdmin),
	})

	// 4. CI/CD build outputs (WIF)
	if cfg.GitHubOwner != "" {
		ctx.Export("wif_pool_name", buildOutputs.WIFPoolName)
		ctx.Export("wif_provider_name", buildOutputs.WIFProviderName)
	}
}
