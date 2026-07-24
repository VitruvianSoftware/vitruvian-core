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
	"sort"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// exportSpokeOutputs emits the spoke stack exports, mirroring upstream
// 3-networks-hub-and-spoke/envs/nonproduction/outputs.tf. The VPC-SC exports
// (access_context_manager_policy_id, enforce_vpcsc, service_perimeter_name,
// access_level_name, access_level_name_dry_run) are emitted by the shared_vpc
// spoke service-control path.
func exportSpokeOutputs(ctx *pulumi.Context, spokeProjectID pulumi.StringOutput, net *networking.Networking) {
	ctx.Export("shared_vpc_host_project_id", spokeProjectID)
	ctx.Export("network_name", net.VPC.Name)
	ctx.Export("network_self_link", net.VPC.SelfLink)

	// net.Subnets is a Go map, whose range order is randomized on every run.
	// Ranging it directly makes the exported arrays reshuffle between previews
	// (spurious diffs with zero real changes) and lets any consumer that reads an
	// export by index bind to a different subnet each run. Iterate a name-sorted
	// order instead: the subnet name (the map key) is a synchronous, plan-time
	// string, so sorting needs no Output resolution. Mirrors Terraform, which
	// emits map-derived outputs in sorted-key order.
	subnetOrder := make([]string, 0, len(net.Subnets))
	for name := range net.Subnets {
		subnetOrder = append(subnetOrder, name)
	}
	sort.Strings(subnetOrder)

	// Subnet exports as arrays (matching TF subnets_names/ips/self_links)
	var subnetNames, subnetIPs, subnetSelfLinks pulumi.StringArray
	for _, name := range subnetOrder {
		subnet := net.Subnets[name]
		subnetNames = append(subnetNames, subnet.Name)
		subnetIPs = append(subnetIPs, subnet.IpCidrRange)
		subnetSelfLinks = append(subnetSelfLinks, subnet.SelfLink)
	}
	ctx.Export("subnets_names", subnetNames)
	ctx.Export("subnets_ips", subnetIPs)
	ctx.Export("subnets_self_links", subnetSelfLinks)

	// Secondary ranges export — flatten every subnet's secondary ranges into one
	// list. NB: seeding the accumulator with a zero-value pulumi.ArrayOutput{}
	// (nil OutputState) and passing it to pulumi.All on the first iteration
	// panics with a nil-pointer deref, so gather the per-subnet inputs and
	// combine them in a single pulumi.All instead of an N-deep ApplyT chain.
	secondaryRangeInputs := make([]interface{}, 0, len(subnetOrder))
	for _, name := range subnetOrder {
		secondaryRangeInputs = append(secondaryRangeInputs, net.Subnets[name].SecondaryIpRanges)
	}
	if len(secondaryRangeInputs) == 0 {
		ctx.Export("subnets_secondary_ranges", pulumi.ToStringArray([]string{}))
	} else {
		ctx.Export("subnets_secondary_ranges", pulumi.All(secondaryRangeInputs...).ApplyT(func(args []interface{}) []interface{} {
			flattened := []interface{}{}
			for _, r := range args {
				if ranges, ok := r.([]interface{}); ok {
					flattened = append(flattened, ranges...)
				}
			}
			return flattened
		}).(pulumi.ArrayOutput))
	}
}
