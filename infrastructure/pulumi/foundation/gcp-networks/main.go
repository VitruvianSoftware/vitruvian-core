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

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"

	"foundation-networks/modules/base_env"
	"foundation-networks/modules/hierarchical_firewall_policy"
	"foundation-networks/modules/shared_vpc"
	"foundation-networks/modules/transitivity"
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
		spokeProjectID := orgStack.GetStringOutput(pulumi.String(fmt.Sprintf("%s_network_project_id", cfg.Env)))
		hubProjectID := orgStack.GetStringOutput(pulumi.String("net_hub_project_id"))

		// =================================================================
		// HUB NETWORK (deployed once by the development stack)
		//
		// The hub VPC is shared infrastructure — it only needs to be created
		// once. The development stack deploys it because it runs first in the
		// promotion chain (dev → nonprod → prod). Subsequent stacks (nonprod,
		// prod) only deploy their spoke VPCs and peer to the hub.
		// =================================================================
		var hubDependsOn pulumi.ResourceOption

		if cfg.Env == "development" {
			hubRes, err := deployHub(ctx, cfg, orgStack, hubProjectID)
			if err != nil {
				return err
			}
			hubDependsOn = pulumi.DependsOn([]pulumi.Resource{hubRes.Networking.VPC})
		}

		// =================================================================
		// SPOKE NETWORK (deployed per-environment)
		// =================================================================
		var spokeOpts []pulumi.ResourceOption
		if hubDependsOn != nil {
			spokeOpts = append(spokeOpts, hubDependsOn)
		}
		spokeOutputs, err := base_env.New(ctx, &base_env.Args{
			Env:     cfg.Env,
			EnvCode: cfg.EnvCode,

			ProjectID:    spokeProjectID,
			HubProjectID: hubProjectID,
			OrgStack:     orgStack,

			Region1: cfg.Region1,
			Region2: cfg.Region2,

			Subnet1Cidr: cfg.SpokeSubnet1Cidr,
			Subnet2Cidr: cfg.SpokeSubnet2Cidr,
			Proxy1Cidr:  cfg.SpokeProxy1Cidr,
			Proxy2Cidr:  cfg.SpokeProxy2Cidr,
			GkePod1Cidr: cfg.SpokeGkePod1Cidr,
			GkeSvc1Cidr: cfg.SpokeGkeSvc1Cidr,

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
		}, spokeOpts...)
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

// deployHub creates the central hub Shared VPC plus the hierarchical firewall
// policy and (when enabled) the transitivity appliance. It runs only in the
// development stack (first in the promotion chain). The hub topology dispatch is
// kept here in the stage root; the resource bodies live in the stage modules.
func deployHub(ctx *pulumi.Context, cfg *NetConfig, orgStack *pulumi.StackReference, hubProjectID pulumi.StringOutput) (*shared_vpc.Result, error) {
	// Hub VPC & Subnets — hub has NO secondary ranges (matching upstream).
	hubVpcName := "vpc-c-svpc-hub"
	hubSubnets := []networking.SubnetArgs{
		{
			Name:             fmt.Sprintf("sb-c-svpc-hub-%s", cfg.Region1),
			Region:           cfg.Region1,
			CIDR:             cfg.HubSubnet1Cidr,
			FlowLogs:         true,
			FlowLogsInterval: cfg.VpcFlowLogs.AggregationInterval,
			FlowLogsSampling: cfg.VpcFlowLogs.FlowSampling,
			FlowLogsMetadata: cfg.VpcFlowLogs.Metadata,
			// No secondary ranges on hub (matching upstream: secondary_ranges = {})
		},
		{
			Name:             fmt.Sprintf("sb-c-svpc-hub-%s", cfg.Region2),
			Region:           cfg.Region2,
			CIDR:             cfg.HubSubnet2Cidr,
			FlowLogs:         true,
			FlowLogsInterval: cfg.VpcFlowLogs.AggregationInterval,
			FlowLogsSampling: cfg.VpcFlowLogs.FlowSampling,
			FlowLogsMetadata: cfg.VpcFlowLogs.Metadata,
		},
		// Hub proxy-only subnets — matching upstream REGIONAL_MANAGED_PROXY
		{
			Name:    fmt.Sprintf("sb-c-svpc-hub-%s-proxy", cfg.Region1),
			Region:  cfg.Region1,
			CIDR:    cfg.HubProxy1Cidr,
			Role:    "ACTIVE",
			Purpose: "REGIONAL_MANAGED_PROXY",
		},
		{
			Name:    fmt.Sprintf("sb-c-svpc-hub-%s-proxy", cfg.Region2),
			Region:  cfg.Region2,
			CIDR:    cfg.HubProxy2Cidr,
			Role:    "ACTIVE",
			Purpose: "REGIONAL_MANAGED_PROXY",
		},
	}

	hubRes, err := shared_vpc.New(ctx, &shared_vpc.Args{
		Mode: "hub",
		Code: "c",

		ProjectID: hubProjectID,
		OrgStack:  orgStack,

		VPCName:             hubVpcName,
		Subnets:             hubSubnets,
		FirewallSubnetCidrs: []string{cfg.HubSubnet1Cidr, cfg.HubSubnet2Cidr},

		Region1: cfg.Region1,
		Region2: cfg.Region2,

		PscIP: cfg.PscIP,

		FirewallPoliciesEnableLogging: cfg.FirewallPoliciesEnableLogging,
		DnsEnableLogging:              cfg.DnsEnableLogging,

		Domain:            cfg.Domain,
		TargetNameServers: cfg.TargetNameServers,

		WindowsActivationEnabled: cfg.WindowsActivationEnabled,

		NatEnabled:      cfg.HubNatEnabled,
		NatBgpAsn:       cfg.NatBgpAsn,
		NatNumAddresses: cfg.NatNumAddresses,

		BgpAsn: cfg.BgpAsn,

		PolicyID:                cfg.PolicyID,
		VpcScMembers:            cfg.VpcScMembers,
		VpcScRestrictedServices: cfg.VpcScRestrictedServices,
		EnforceVpcSc:            cfg.EnforceVpcSc,
	})
	if err != nil {
		return nil, err
	}

	// Hierarchical Firewall Policy (org/folder level) — hub only.
	// Matching upstream: associate with 6 folders (common, network, bootstrap,
	// dev, prod, nonprod).
	if err := hierarchical_firewall_policy.New(ctx, &hierarchical_firewall_policy.Args{
		ParentID:      cfg.ParentID,
		Associations:  cfg.HierarchicalFwAssociations,
		EnableLogging: cfg.FirewallPoliciesEnableLogging,
	}); err != nil {
		return nil, err
	}

	// Transitivity Appliance — conditional (default false, matching upstream).
	if cfg.EnableHubAndSpokeTransitivity {
		if err := transitivity.New(ctx, &transitivity.Args{
			ProjectID:   hubProjectID,
			Region1:     cfg.Region1,
			Region2:     cfg.Region2,
			Network:     hubRes.Networking.VPC.SelfLink,
			NetworkName: hubVpcName,
			Subnetworks: map[string]pulumi.StringInput{
				cfg.Region1: hubRes.Networking.Subnets[fmt.Sprintf("sb-c-svpc-hub-%s", cfg.Region1)].SelfLink,
				cfg.Region2: hubRes.Networking.Subnets[fmt.Sprintf("sb-c-svpc-hub-%s", cfg.Region2)].SelfLink,
			},
			FirewallPolicy: hubRes.Firewall.Policy.Name,
			VPC:            hubRes.Networking.VPC,
		}); err != nil {
			return nil, err
		}
	}

	return hubRes, nil
}
