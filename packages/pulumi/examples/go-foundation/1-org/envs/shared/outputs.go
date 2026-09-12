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
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-1-org/modules/cai_monitoring"
	"foundation-1-org/modules/centralized_logging"
)

// exportOrgOutputs registers every stack export for the 1-org shared stage.
// This mirrors the Terraform foundation's 1-org/envs/shared/outputs.tf — the
// export names match the upstream output names one-for-one so downstream
// stages (2-environments, 3-networks, 4-projects) can consume them via
// StackReference exactly as upstream consumes terraform_remote_state.
func exportOrgOutputs(
	ctx *pulumi.Context,
	cfg *OrgConfig,
	folders *Folders,
	proj *OrgProjects,
	logOutputs *centralized_logging.Result,
	caiOutputs *cai_monitoring.Result,
	tagOutputs pulumi.MapOutput,
	accessContextManagerPolicyID pulumi.StringOutput,
) {
	// Org/parent metadata
	ctx.Export("org_id", pulumi.String(cfg.OrgID))
	ctx.Export("parent_resource_id", pulumi.String(cfg.ParentID))
	ctx.Export("parent_resource_type", pulumi.String(cfg.ParentType))

	// Folders
	ctx.Export("common_folder_name", folders.Common.Name)
	ctx.Export("common_folder_id", folders.Common.ID())
	ctx.Export("network_folder_name", folders.Network.Name)
	ctx.Export("network_folder_id", folders.Network.ID())

	// Projects
	ctx.Export("org_audit_logs_project_id", proj.AuditLogsProjectID)
	ctx.Export("org_billing_export_project_id", proj.BillingExportProjectID)
	ctx.Export("scc_notifications_project_id", proj.SCCProjectID)
	ctx.Export("common_kms_project_id", proj.OrgKMSProjectID)
	ctx.Export("org_secrets_project_id", proj.OrgSecretsProjectID)
	ctx.Export("interconnect_project_id", proj.InterconnectProjectID)
	ctx.Export("interconnect_project_number", proj.InterconnectProjectNumber)
	if cfg.EnableHubAndSpoke {
		ctx.Export("net_hub_project_id", proj.NetHubProjectID)
		ctx.Export("net_hub_project_number", proj.NetHubProjectNumber)
	}
	for env, id := range proj.NetworkProjectIDs {
		ctx.Export(fmt.Sprintf("%s_network_project_id", env), id)
	}
	for env, number := range proj.NetworkProjectNumbers {
		ctx.Export(fmt.Sprintf("%s_network_project_number", env), number)
	}

	// Shared VPC projects grouped by environment (upstream: shared_vpc_projects)
	sharedVPCMap := pulumi.Map{}
	for env, id := range proj.NetworkProjectIDs {
		sharedVPCMap[env] = id
	}
	ctx.Export("shared_vpc_projects", sharedVPCMap.ToMapOutput())

	// Logging
	ctx.Export("logs_export_storage_bucket_name", logOutputs.StorageBucketName)
	ctx.Export("logs_export_pubsub_topic", logOutputs.PubSubTopicName)
	ctx.Export("logs_export_project_logbucket_name", logOutputs.LogBucketName)
	ctx.Export("logs_export_project_linked_dataset_name", logOutputs.LinkedDatasetName)

	// SCC
	ctx.Export("scc_notification_name", pulumi.String(cfg.SCCNotificationName))

	// CAI Monitoring
	if caiOutputs != nil {
		ctx.Export("cai_monitoring_artifact_registry", caiOutputs.ArtifactRegistryName)
		ctx.Export("cai_monitoring_asset_feed", caiOutputs.AssetFeedName)
		ctx.Export("cai_monitoring_bucket", caiOutputs.BucketName)
		ctx.Export("cai_monitoring_topic", caiOutputs.TopicName)
	}

	// Tags
	ctx.Export("tags", tagOutputs)

	// Config passthrough
	ctx.Export("domains_to_allow", pulumi.ToStringArray(cfg.DomainsToAllow))

	// ACM policy — mirrors TS port (available from VPC-SC module or org policy)
	ctx.Export("access_context_manager_policy_id", accessContextManagerPolicyID)

	// Billing sink names — dynamically resolved from centralized logging component
	// Mirrors TF: module.logs_export.billing_sink_names
	billingSinkMap := pulumi.Map{}
	for k, v := range logOutputs.BillingSinkNames {
		billingSinkMap[k] = v
	}
	ctx.Export("billing_sink_names", billingSinkMap)
}
