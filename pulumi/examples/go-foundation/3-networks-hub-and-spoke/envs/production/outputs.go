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
	"sort"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// exportSpokeOutputs emits the spoke stack exports, mirroring upstream
// 3-networks-hub-and-spoke/envs/production/outputs.tf. The VPC-SC exports
// (access_context_manager_policy_id, enforce_vpcsc, service_perimeter_name,
// access_level_name, access_level_name_dry_run) are emitted by the shared_vpc
// spoke service-control path.
func exportSpokeOutputs(ctx *pulumi.Context, cfg *NetConfig, spokeVpc *networking.Networking) {
	ctx.Export("shared_vpc_host_project_id", pulumi.String(cfg.SpokeProjectID))
	ctx.Export("network_name", spokeVpc.VPC.Name)
	ctx.Export("network_self_link", spokeVpc.VPC.SelfLink)

	// spokeVpc.Subnets is a Go map, whose range order is randomized on every
	// run. Ranging it directly makes the exported arrays reshuffle between
	// previews (spurious diffs with zero real changes) and lets any consumer that
	// reads an export by index bind to a different subnet each run. Iterate a
	// name-sorted order instead: the subnet name (the map key) is a synchronous,
	// plan-time string, so sorting needs no Output resolution. Mirrors Terraform,
	// which emits map-derived outputs in sorted-key order.
	subnetOrder := make([]string, 0, len(spokeVpc.Subnets))
	for name := range spokeVpc.Subnets {
		subnetOrder = append(subnetOrder, name)
	}
	sort.Strings(subnetOrder)

	// Subnet exports as arrays (matching TF subnets_names/ips/self_links/secondary_ranges)
	var subnetNames, subnetIPs, subnetSelfLinks pulumi.StringArray
	for _, name := range subnetOrder {
		subnet := spokeVpc.Subnets[name]
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
	for _, name := range subnetOrder {
		subnet := spokeVpc.Subnets[name]
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
