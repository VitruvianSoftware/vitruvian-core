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
	"foundation-networks/modules/shared_vpc"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// deployNetHubs provisions the central hub Shared VPC (subnets, routers, DNS
// hub, firewall, PSC, VPC-SC), mirroring upstream
// 3-networks-hub-and-spoke/envs/shared/net-hubs.tf. It returns the shared_vpc
// result plus the hub VPC name for the transitivity wiring.
func deployNetHubs(ctx *pulumi.Context, cfg *NetSharedConfig, orgStack *pulumi.StackReference, hubProjectID pulumi.StringOutput) (*shared_vpc.Result, string, error) {
	// Hub VPC & Subnets — hub has NO secondary ranges (matching upstream).
	hubVpcName := fmt.Sprintf("vpc-%s-svpc-hub", pinnedEnvCode)
	hubSubnets := []networking.SubnetArgs{
		{
			Name:             fmt.Sprintf("sb-%s-svpc-hub-%s", pinnedEnvCode, cfg.Region1),
			Region:           cfg.Region1,
			CIDR:             cfg.HubSubnet1Cidr,
			FlowLogs:         true,
			FlowLogsInterval: cfg.VpcFlowLogs.AggregationInterval,
			FlowLogsSampling: cfg.VpcFlowLogs.FlowSampling,
			FlowLogsMetadata: cfg.VpcFlowLogs.Metadata,
			// No secondary ranges on hub (matching upstream: secondary_ranges = {})
		},
		{
			Name:             fmt.Sprintf("sb-%s-svpc-hub-%s", pinnedEnvCode, cfg.Region2),
			Region:           cfg.Region2,
			CIDR:             cfg.HubSubnet2Cidr,
			FlowLogs:         true,
			FlowLogsInterval: cfg.VpcFlowLogs.AggregationInterval,
			FlowLogsSampling: cfg.VpcFlowLogs.FlowSampling,
			FlowLogsMetadata: cfg.VpcFlowLogs.Metadata,
		},
		// Hub proxy-only subnets — matching upstream REGIONAL_MANAGED_PROXY
		{
			Name:    fmt.Sprintf("sb-%s-svpc-hub-%s-proxy", pinnedEnvCode, cfg.Region1),
			Region:  cfg.Region1,
			CIDR:    cfg.HubProxy1Cidr,
			Role:    "ACTIVE",
			Purpose: "REGIONAL_MANAGED_PROXY",
		},
		{
			Name:    fmt.Sprintf("sb-%s-svpc-hub-%s-proxy", pinnedEnvCode, cfg.Region2),
			Region:  cfg.Region2,
			CIDR:    cfg.HubProxy2Cidr,
			Role:    "ACTIVE",
			Purpose: "REGIONAL_MANAGED_PROXY",
		},
	}

	hubRes, err := shared_vpc.New(ctx, &shared_vpc.Args{
		Mode: "hub",
		Code: pinnedEnvCode,

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
		return nil, "", err
	}
	return hubRes, hubVpcName, nil
}
