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

// Stack exports for this leaf — the Pulumi analogue of upstream
// 4-projects/business_unit_1/production/outputs.tf.

package main

import (
	"foundation-projects/modules/base_env"

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
	ctx.Export("oss_floating_project", projects.OSSFloatingProjectID)
	ctx.Export("oss_floating_project_number", projects.OSSFloatingProjectNumber)
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
