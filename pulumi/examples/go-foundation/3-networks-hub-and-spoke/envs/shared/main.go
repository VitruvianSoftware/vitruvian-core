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

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"

	"foundation-3-networks-hub-and-spoke/modules/base_env"
	"foundation-3-networks-hub-and-spoke/modules/hierarchical_firewall_policy"
	"foundation-3-networks-hub-and-spoke/modules/shared_vpc"
	"foundation-3-networks-hub-and-spoke/modules/transitivity"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)

		// ====================================================================
		// Resolve the hub host project ID. The shared/hub stack uses the
		// configured value directly; spoke stacks read it from the 1-org
		// stack reference.
		// ====================================================================
		var hubProjectID pulumi.StringOutput
		if cfg.Env == "shared" {
			hubProjectID = pulumi.String(cfg.HubProjectID).ToStringOutput()
		} else {
			netHubOrgStack, err := pulumi.NewStackReference(ctx, "org", &pulumi.StackReferenceArgs{
				Name: pulumi.String(cfg.OrgStackName),
			})
			if err != nil {
				return err
			}
			hubProjectID = netHubOrgStack.GetStringOutput(pulumi.String("net_hub_project_id"))
		}

		// ====================================================================
		// HUB ENVIRONMENT (deployed in "shared" / env_code "c")
		// ====================================================================
		if cfg.Env == "shared" {
			return deployHub(ctx, cfg, hubProjectID)
		}

		// ====================================================================
		// SPOKE ENVIRONMENT (dev, nonprod, prod)
		// ====================================================================
		spokeOutputs, err := base_env.New(ctx, &base_env.Args{
			Env:     cfg.Env,
			EnvCode: cfg.EnvCode,

			ProjectID:    pulumi.String(cfg.SpokeProjectID),
			HubProjectID: hubProjectID,
			OrgStackName: cfg.OrgStackName,

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

			PolicyID:                   cfg.PolicyID,
			VpcScMembers:               cfg.VpcScMembers,
			VpcScProjects:              cfg.VpcScProjects,
			VpcScRestrictedServices:    cfg.VpcScRestrictedServices,
			EnforceVpcSc:               cfg.EnforceVpcSc,
			VpcScIngressPolicies:       cfg.VpcScIngressPolicies,
			VpcScEgressPolicies:        cfg.VpcScEgressPolicies,
			VpcScIngressPoliciesDryRun: cfg.VpcScIngressPoliciesDryRun,
			VpcScEgressPoliciesDryRun:  cfg.VpcScEgressPoliciesDryRun,
		})
		if err != nil {
			return err
		}

		spokeVpc := spokeOutputs.Networking

		// Exports — matching TF 3-networks-hub-and-spoke/envs/{env}/outputs.tf.
		// The VPC-SC exports (access_context_manager_policy_id, enforce_vpcsc,
		// service_perimeter_name, access_level_name, access_level_name_dry_run)
		// are emitted by the shared_vpc spoke service-control path.
		ctx.Export("shared_vpc_host_project_id", pulumi.String(cfg.SpokeProjectID))
		ctx.Export("network_name", spokeVpc.VPC.Name)
		ctx.Export("network_self_link", spokeVpc.VPC.SelfLink)

		// Subnet exports as arrays (matching TF subnets_names/ips/self_links/secondary_ranges)
		var subnetNames, subnetIPs, subnetSelfLinks pulumi.StringArray
		for _, subnet := range spokeVpc.Subnets {
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
		for _, subnet := range spokeVpc.Subnets {
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

		return nil
	})
}

// deployHub creates the central hub Shared VPC plus the hierarchical firewall
// policy and (when enabled) the transitivity appliance. It runs only in the
// shared stack (env_code "c"). The hub topology dispatch is kept here in the
// stage root; the resource bodies live in the stage modules.
func deployHub(ctx *pulumi.Context, cfg *NetConfig, hubProjectID pulumi.StringOutput) error {
	// Hierarchical Firewall Policy (org/folder level) — hub only.
	if err := hierarchical_firewall_policy.New(ctx, &hierarchical_firewall_policy.Args{
		ParentID:      cfg.ParentID,
		Env:           cfg.Env,
		Associations:  cfg.FirewallAssociations,
		EnableLogging: cfg.FirewallPoliciesEnableLogging,
	}); err != nil {
		return err
	}

	// Hub VPC & Subnets — hub has NO secondary ranges and no proxy subnets
	// (matching the example's envs/shared).
	hubVpcName := fmt.Sprintf("vpc-%s-svpc-hub", cfg.EnvCode)
	hubSubnets := []networking.SubnetArgs{
		{
			Name:             fmt.Sprintf("sb-%s-svpc-hub-%s", cfg.EnvCode, cfg.Region1),
			Region:           cfg.Region1,
			CIDR:             cfg.HubSubnet1Cidr,
			FlowLogs:         true,
			FlowLogsInterval: cfg.VpcFlowLogs.AggregationInterval,
			FlowLogsSampling: cfg.VpcFlowLogs.FlowSampling,
			FlowLogsMetadata: cfg.VpcFlowLogs.Metadata,
		},
		{
			Name:             fmt.Sprintf("sb-%s-svpc-hub-%s", cfg.EnvCode, cfg.Region2),
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
		Code: cfg.EnvCode,

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
		return err
	}

	// Transitivity Appliance — conditional (default false, matching upstream).
	if cfg.EnableHubAndSpokeTransitivity {
		if err := transitivity.New(ctx, &transitivity.Args{
			ProjectID:   hubProjectID,
			EnvCode:     cfg.EnvCode,
			Region1:     cfg.Region1,
			Region2:     cfg.Region2,
			Network:     hubRes.Networking.VPC.SelfLink,
			NetworkName: hubVpcName,
			Subnetworks: map[string]pulumi.StringInput{
				cfg.Region1: hubRes.Networking.Subnets[fmt.Sprintf("sb-%s-svpc-hub-%s", cfg.EnvCode, cfg.Region1)].SelfLink,
				cfg.Region2: hubRes.Networking.Subnets[fmt.Sprintf("sb-%s-svpc-hub-%s", cfg.EnvCode, cfg.Region2)].SelfLink,
			},
			FirewallPolicy: hubRes.Firewall.Policy.Name,
			VPC:            hubRes.Networking.VPC,
		}); err != nil {
			return err
		}
	}

	return nil
}
