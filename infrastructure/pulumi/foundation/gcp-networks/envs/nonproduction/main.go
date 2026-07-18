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

// Foundation stage 3 (networks, hub-and-spoke) — thin env root for the
// nonproduction spoke, mirroring upstream terraform-example-foundation
// 3-networks-hub-and-spoke/envs/nonproduction. This leaf pins the environment
// identity (nonproduction/n) and its spoke CIDR plan, reads the host projects
// from a StackReference to 1-org, then calls the shared base_env module. All
// resource creation lives in ../../modules; the hub network lives in the
// sibling envs/shared leaf.
//
// Cross-stack peering serialization: the hub VPC (and its PSA
// servicenetworking connection) is created by the envs/shared stack, which is
// fully applied before this stack runs (deploy order shared → development →
// nonproduction → production). GCP allows only one peering-mutating operation
// at a time per VPC, so that ordering preserves the PSA-before-peering
// serialization the pre-split single-stack layout enforced with an explicit
// DependsOn on the hub PSAConnection. The spoke's own PSA-vs-peering
// serialization (spoke peering DependsOn the spoke PSAConnection) lives in
// modules/shared_vpc (createPeering).
package main

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-networks/modules/base_env"
)

// Environment identity and spoke CIDR plan pinned by this leaf project —
// upstream 3-networks-hub-and-spoke/envs/nonproduction hardcodes them in its
// main.tf; the leaf dir is the pin, not per-stack config. CIDRs derive from
// the upstream reference architecture (no overlaps across envs; secondary
// ranges only on R1, matching upstream).
const (
	pinnedEnv     = "nonproduction"
	pinnedEnvCode = "n"

	spokeSubnet1Cidr = "10.8.128.0/18"
	spokeSubnet2Cidr = "10.9.128.0/18"
	spokeProxy1Cidr  = "10.26.4.0/23"
	spokeProxy2Cidr  = "10.27.4.0/23"
	spokeGkePod1Cidr = "100.72.128.0/18"
	spokeGkeSvc1Cidr = "100.73.128.0/18"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)

		// Stack Reference to 1-org for project IDs and ACM policy.
		orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.OrgStackName),
		})
		if err != nil {
			return err
		}

		// Resolve the spoke project ID from the 1-org exports.
		// Each environment stack deploys to its own Shared VPC host project.
		spokeProjectID := orgStack.GetStringOutput(pulumi.String(fmt.Sprintf("%s_network_project_id", pinnedEnv)))
		hubProjectID := orgStack.GetStringOutput(pulumi.String("net_hub_project_id"))

		// =================================================================
		// SPOKE NETWORK (this environment)
		// =================================================================
		spokeOutputs, err := base_env.New(ctx, &base_env.Args{
			Env:     pinnedEnv,
			EnvCode: pinnedEnvCode,

			ProjectID:    spokeProjectID,
			HubProjectID: hubProjectID,
			OrgStack:     orgStack,

			Region1: cfg.Region1,
			Region2: cfg.Region2,

			Subnet1Cidr: spokeSubnet1Cidr,
			Subnet2Cidr: spokeSubnet2Cidr,
			Proxy1Cidr:  spokeProxy1Cidr,
			Proxy2Cidr:  spokeProxy2Cidr,
			GkePod1Cidr: spokeGkePod1Cidr,
			GkeSvc1Cidr: spokeGkeSvc1Cidr,

			FlowLogsInterval: cfg.VpcFlowLogs.AggregationInterval,
			FlowLogsSampling: cfg.VpcFlowLogs.FlowSampling,
			FlowLogsMetadata: cfg.VpcFlowLogs.Metadata,

			PscIP: cfg.PscIP,

			FirewallPoliciesEnableLogging: cfg.FirewallPoliciesEnableLogging,
			DnsEnableLogging:              cfg.DnsEnableLogging,

			Domain: cfg.Domain,

			WindowsActivationEnabled: cfg.WindowsActivationEnabled,
			NatEnabled:               cfg.NatEnabled,
			NatBgpAsn:                cfg.NatBgpAsn,
			NatNumAddresses:          cfg.NatNumAddresses,

			PolicyID:                cfg.PolicyID,
			VpcScMembers:            cfg.VpcScMembers,
			VpcScRestrictedServices: cfg.VpcScRestrictedServices,
			EnforceVpcSc:            cfg.EnforceVpcSc,
		})
		if err != nil {
			return err
		}

		// =================================================================
		// Exports — matches upstream TF 3-networks-hub-and-spoke/envs/{env}/outputs.tf
		// =================================================================
		ctx.Export("shared_vpc_host_project_id", spokeProjectID)
		ctx.Export("network_name", spokeOutputs.Networking.VPC.Name)
		ctx.Export("network_self_link", spokeOutputs.Networking.VPC.SelfLink)

		// Subnet exports as arrays (matching TF subnets_names/ips/self_links)
		var subnetNames, subnetIPs, subnetSelfLinks pulumi.StringArray
		for _, subnet := range spokeOutputs.Networking.Subnets {
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
		secondaryRangeInputs := make([]interface{}, 0, len(spokeOutputs.Networking.Subnets))
		for _, subnet := range spokeOutputs.Networking.Subnets {
			secondaryRangeInputs = append(secondaryRangeInputs, subnet.SecondaryIpRanges)
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

		return nil
	})
}
