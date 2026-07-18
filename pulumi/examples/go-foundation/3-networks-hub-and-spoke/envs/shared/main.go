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

// Foundation stage 3 (networks, hub-and-spoke) — thin shared root for the hub
// network, mirroring upstream terraform-example-foundation
// 3-networks-hub-and-spoke/envs/shared. This leaf pins the shared identity
// (shared/c) and deploys the shared/global network resources: the central hub
// Shared VPC (with its DNS hub forwarding zone and BGP routers), the
// org/folder-level hierarchical firewall policy, and (when enabled) the
// transitivity appliance. The per-environment spoke VPCs live in the sibling
// envs/{development,nonproduction,production} leaves.
//
// Cross-stack peering serialization: GCP allows only one peering-mutating
// operation at a time per VPC. Within this stack the hub's PSA
// servicenetworking connection is the only mutation of the hub VPC's peering
// set; the spoke stacks' hub-to-spoke peerings only run after this stack has
// fully applied (deploy order shared → development → nonproduction →
// production, matching upstream's envs/shared-before-envs/<env> ordering).
// The spoke's own PSA-vs-peering serialization lives in modules/shared_vpc
// (createPeering).
package main

import (
	"fmt"
	"foundation-3-networks-hub-and-spoke/modules/hierarchical_firewall_policy"
	"foundation-3-networks-hub-and-spoke/modules/shared_vpc"
	"foundation-3-networks-hub-and-spoke/modules/transitivity"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// Shared/hub identity pinned by this leaf project — upstream
// 3-networks-hub-and-spoke/envs/shared hardcodes the "shared" environment with
// the "c" (common) code in its main.tf; the leaf dir is the pin, not per-stack
// config.
const (
	pinnedEnv     = "shared"
	pinnedEnvCode = "c"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadNetSharedConfig(ctx)

		// The shared/hub stack uses the configured hub host project directly.
		hubProjectID := pulumi.String(cfg.HubProjectID).ToStringOutput()

		// Hierarchical Firewall Policy (org/folder level) — hub only.
		if err := hierarchical_firewall_policy.New(ctx, &hierarchical_firewall_policy.Args{
			ParentID:      cfg.ParentID,
			Env:           pinnedEnv,
			Associations:  cfg.FirewallAssociations,
			EnableLogging: cfg.FirewallPoliciesEnableLogging,
		}); err != nil {
			return err
		}

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
			return err
		}

		// Transitivity Appliance — conditional (default false, matching upstream).
		if cfg.EnableHubAndSpokeTransitivity {
			if err := transitivity.New(ctx, &transitivity.Args{
				ProjectID:   hubProjectID,
				EnvCode:     pinnedEnvCode,
				Region1:     cfg.Region1,
				Region2:     cfg.Region2,
				Network:     hubRes.Networking.VPC.SelfLink,
				NetworkName: hubVpcName,
				Subnetworks: map[string]pulumi.StringInput{
					cfg.Region1: hubRes.Networking.Subnets[fmt.Sprintf("sb-%s-svpc-hub-%s", pinnedEnvCode, cfg.Region1)].SelfLink,
					cfg.Region2: hubRes.Networking.Subnets[fmt.Sprintf("sb-%s-svpc-hub-%s", pinnedEnvCode, cfg.Region2)].SelfLink,
				},
				FirewallPolicy: hubRes.Firewall.Policy.Name,
				VPC:            hubRes.Networking.VPC,
			}); err != nil {
				return err
			}
		}

		// Exports — the hub outputs (hub_network_name, hub_network_self_link,
		// dns_policy) are emitted by the shared_vpc module in hub mode, matching
		// upstream TF 3-networks-hub-and-spoke/envs/shared/outputs.tf.
		return nil
	})
}
