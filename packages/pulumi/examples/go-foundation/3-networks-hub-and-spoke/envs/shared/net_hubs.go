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
	"foundation-3-networks-hub-and-spoke/modules/shared_vpc"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// deployNetHubs provisions the central hub Shared VPC (subnets, routers, DNS
// hub, firewall, PSC, VPC-SC), mirroring upstream
// 3-networks-hub-and-spoke/envs/shared/net-hubs.tf. It returns the shared_vpc
// result plus the hub VPC name for the transitivity wiring.
func deployNetHubs(ctx *pulumi.Context, cfg *NetSharedConfig, hubProjectID pulumi.StringOutput) (*shared_vpc.Result, string, error) {
	// Hub VPC & Subnets — hub has NO secondary ranges and no proxy subnets
	// (matching the example's envs/shared).
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
	}

	hubRes, err := shared_vpc.New(ctx, &shared_vpc.Args{
		Mode: "hub",
		Code: pinnedEnvCode,

		ProjectID:    hubProjectID,
		OrgStackName: cfg.OrgStackName,

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
