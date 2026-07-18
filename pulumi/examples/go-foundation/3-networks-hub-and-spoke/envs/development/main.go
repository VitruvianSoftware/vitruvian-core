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

// Foundation stage 3 (networks, hub-and-spoke) — thin env root for the
// development spoke, mirroring upstream terraform-example-foundation
// 3-networks-hub-and-spoke/envs/development. This leaf pins the environment
// identity (development/d) and its spoke CIDR plan, then calls the shared
// base_env module. All resource creation lives in ../../modules; the hub
// network lives in the sibling envs/shared leaf.
//
// Cross-stack peering serialization: the hub VPC (and its PSA
// servicenetworking connection) is created by the envs/shared stack, which is
// fully applied before this stack runs (deploy order shared → development →
// nonproduction → production). GCP allows only one peering-mutating operation
// at a time per VPC, so that ordering serializes the hub-side peering
// mutations; the spoke's own PSA-vs-peering serialization (spoke peering
// DependsOn the spoke PSAConnection) lives in modules/shared_vpc
// (createPeering).
package main

import (
	"foundation-3-networks-hub-and-spoke/modules/base_env"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Environment identity and spoke CIDR plan pinned by this leaf project —
// upstream 3-networks-hub-and-spoke/envs/development hardcodes them in its
// main.tf; the leaf dir is the pin, not per-stack config. CIDRs derive from
// the upstream reference architecture (no overlaps across envs; secondary
// ranges only on R1, matching upstream).
const (
	pinnedEnv     = "development"
	pinnedEnvCode = "d"

	spokeSubnet1Cidr = "10.8.64.0/18"
	spokeSubnet2Cidr = "10.9.64.0/18"
	spokeProxy1Cidr  = "10.26.2.0/23"
	spokeProxy2Cidr  = "10.27.2.0/23"
	spokeGkePod1Cidr = "100.72.64.0/18"
	spokeGkeSvc1Cidr = "100.73.64.0/18"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)

		// Spoke stacks read the hub host project from the 1-org stack reference.
		netHubOrgStack, err := pulumi.NewStackReference(ctx, "org", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.OrgStackName),
		})
		if err != nil {
			return err
		}
		hubProjectID := netHubOrgStack.GetStringOutput(pulumi.String("net_hub_project_id"))

		// ====================================================================
		// SPOKE ENVIRONMENT (this environment)
		// ====================================================================
		spokeOutputs, err := base_env.New(ctx, &base_env.Args{
			Env:     pinnedEnv,
			EnvCode: pinnedEnvCode,

			ProjectID:    pulumi.String(cfg.SpokeProjectID),
			HubProjectID: hubProjectID,
			OrgStackName: cfg.OrgStackName,

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
