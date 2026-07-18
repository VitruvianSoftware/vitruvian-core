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
// This preserves the PSA-before-peering serialization that the pre-split
// single-stack layout enforced with an explicit DependsOn on the hub
// PSAConnection. The spoke's own PSA-vs-peering serialization lives in
// modules/shared_vpc (createPeering).
package main

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"

	"foundation-networks/modules/hierarchical_firewall_policy"
	"foundation-networks/modules/shared_vpc"
	"foundation-networks/modules/transitivity"
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

		// Stack Reference to 1-org for project IDs and ACM policy.
		orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.OrgStackName),
		})
		if err != nil {
			return err
		}

		// Hub host project (created by 1-org when enable_hub_and_spoke=true).
		hubProjectID := orgStack.GetStringOutput(pulumi.String("net_hub_project_id"))

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
			return err
		}

		// Hierarchical Firewall Policy (org/folder level) — hub only.
		// Matching upstream: associate with 6 folders (common, network, bootstrap,
		// dev, prod, nonprod).
		if err := hierarchical_firewall_policy.New(ctx, &hierarchical_firewall_policy.Args{
			ParentID:      cfg.ParentID,
			Associations:  cfg.HierarchicalFwAssociations,
			EnableLogging: cfg.FirewallPoliciesEnableLogging,
		}); err != nil {
			return err
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
