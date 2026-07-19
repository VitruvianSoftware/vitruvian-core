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
	"foundation-3-networks-svpc/modules/base_env"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// exportOutputs emits the per-environment stack exports, mirroring upstream
// 3-networks-svpc/envs/development/outputs.tf.
func exportOutputs(ctx *pulumi.Context, cfg *NetConfig, res *base_env.Result) {
	vpcModule := res.Networking

	// Exports — matching TF 3-networks-svpc/envs/{env}/outputs.tf
	// target_name_server_addresses — pass-through from config (mirrors TF exactly)
	ctx.Export("target_name_server_addresses", pulumi.ToStringArray(cfg.TargetNameServers))
	ctx.Export("access_context_manager_policy_id", res.AcmPolicyID)
	ctx.Export("shared_vpc_host_project_id", pulumi.String(cfg.ProjectID))
	ctx.Export("network_name", vpcModule.VPC.Name)
	ctx.Export("network_self_link", vpcModule.VPC.SelfLink)
	ctx.Export("enforce_vpcsc", pulumi.Bool(cfg.EnforceVpcSc))
	ctx.Export("service_perimeter_name", res.PerimeterName)
	ctx.Export("access_level_name", res.AccessLevelName)
	ctx.Export("access_level_name_dry_run", res.AccessLevelDryRunName)

	// Subnet exports as arrays (matching TF subnets_names/ips/self_links/secondary_ranges)
	var subnetNames, subnetIPs, subnetSelfLinks pulumi.StringArray
	for _, subnet := range vpcModule.Subnets {
		subnetNames = append(subnetNames, subnet.Name)
		subnetIPs = append(subnetIPs, subnet.IpCidrRange)
		subnetSelfLinks = append(subnetSelfLinks, subnet.SelfLink)
	}
	ctx.Export("subnets_names", subnetNames)
	ctx.Export("subnets_ips", subnetIPs)
	ctx.Export("subnets_self_links", subnetSelfLinks)

	// subnets_secondary_ranges — dynamically resolved from subnet resources
	// Mirrors TF: module.base_env.subnets_secondary_ranges
	secondaryRangesMap := pulumi.Map{}
	for subnetName, subnet := range vpcModule.Subnets {
		secondaryRangesMap[subnetName] = subnet.SecondaryIpRanges
	}
	ctx.Export("subnets_secondary_ranges", secondaryRangesMap)
}
