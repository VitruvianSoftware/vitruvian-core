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

// Stack exports for this leaf — the Pulumi analogue of upstream
// 4-projects/business_unit_1/development/outputs.tf.

package main

import (
	"foundation-4-projects/modules/base_env"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// exportStackOutputs registers the leaf's stack exports — matching TF
// 4-projects/business_unit_1/{env}/outputs.tf. The BU's
// infra_pipeline_project_id is exported by the sibling business_unit_1/shared
// leaf (upstream's shared workspace), not here.
func exportStackOutputs(ctx *pulumi.Context, cfg *ProjectsConfig, projects *base_env.BUProjects) {
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
}
