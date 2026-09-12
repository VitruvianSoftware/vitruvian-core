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
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// exportSpokeOutputs emits the spoke stack exports, mirroring upstream
// 3-networks-hub-and-spoke/envs/development/outputs.tf. The VPC-SC exports
// (access_context_manager_policy_id, enforce_vpcsc, service_perimeter_name,
// access_level_name, access_level_name_dry_run) are emitted by the shared_vpc
// spoke service-control path.
func exportSpokeOutputs(ctx *pulumi.Context, cfg *NetConfig, spokeVpc *networking.Networking) {
	ctx.Export("shared_vpc_host_project_id", pulumi.String(cfg.SpokeProjectID))
	ctx.Export("network_name", spokeVpc.VPC.Name)
	ctx.Export("network_self_link", spokeVpc.VPC.SelfLink)

	// OrderedSubnets() returns the subnetworks in a deterministic, name-sorted
	// order. spokeVpc.Subnets is a Go map with randomized range order, so ranging
	// it directly would make these exported arrays reshuffle between previews
	// (spurious diffs) and let index-based consumers bind to the wrong subnet;
	// see the helper's godoc for the full rationale.
	orderedSubnets := spokeVpc.OrderedSubnets()

	// Subnet exports as arrays (matching TF subnets_names/ips/self_links/secondary_ranges)
	var subnetNames, subnetIPs, subnetSelfLinks pulumi.StringArray
	for _, subnet := range orderedSubnets {
		subnetNames = append(subnetNames, subnet.Name)
		subnetIPs = append(subnetIPs, subnet.IpCidrRange)
		subnetSelfLinks = append(subnetSelfLinks, subnet.SelfLink)
	}
	ctx.Export("subnets_names", subnetNames)
	ctx.Export("subnets_ips", subnetIPs)
	ctx.Export("subnets_self_links", subnetSelfLinks)
	// Secondary ranges: build a list from each subnet's secondary_ip_ranges.
	// TF outputs this as a list of objects with range_name and ip_cidr_range.
	var secondaryRangesList pulumi.ArrayOutput
	for _, subnet := range orderedSubnets {
		secondaryRangesList = pulumi.All(secondaryRangesList, subnet.SecondaryIpRanges).ApplyT(func(args []interface{}) []interface{} {
			existing, _ := args[0].([]interface{})
			ranges, _ := args[1].([]interface{})
			return append(existing, ranges...)
		}).(pulumi.ArrayOutput)
	}
	if secondaryRangesList == (pulumi.ArrayOutput{}) {
		ctx.Export("subnets_secondary_ranges", pulumi.ToStringArray([]string{}))
	} else {
		ctx.Export("subnets_secondary_ranges", secondaryRangesList)
	}
}
