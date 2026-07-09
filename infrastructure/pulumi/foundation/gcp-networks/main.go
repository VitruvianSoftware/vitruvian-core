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

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/dns"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumiverse/pulumi-time/sdk/go/time"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network"
	vpc_sc "github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls"
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

		// =================================================================
		// HUB NETWORK (deployed once by the development stack)
		//
		// The hub VPC is shared infrastructure — it only needs to be created
		// once. The development stack deploys it because it runs first in the
		// promotion chain (dev → nonprod → prod). Subsequent stacks (nonprod,
		// prod) only deploy their spoke VPCs and peer to the hub.
		// =================================================================
		var hubVpc *networking.Networking
		var hubDependsOn pulumi.ResourceOption

		if cfg.Env == "development" {
			var err error
			hubVpc, err = deployHubNetwork(ctx, cfg, orgStack)
			if err != nil {
				return err
			}
			hubDependsOn = pulumi.DependsOn([]pulumi.Resource{hubVpc.VPC})
		}

		// =================================================================
		// SPOKE NETWORK (deployed per-environment)
		// =================================================================
		var spokeOutputs *networking.Networking
		hubProjectID := orgStack.GetStringOutput(pulumi.String("net_hub_project_id"))
		if hubDependsOn != nil {
			spokeOutputs, err = deploySpokeNetwork(ctx, cfg, orgStack, spokeProjectID, hubProjectID, hubDependsOn)
		} else {
			spokeOutputs, err = deploySpokeNetwork(ctx, cfg, orgStack, spokeProjectID, hubProjectID)
		}
		if err != nil {
			return err
		}

		// =================================================================
		// Exports — matches upstream TF 3-networks-hub-and-spoke/envs/{env}/outputs.tf
		// =================================================================
		ctx.Export("shared_vpc_host_project_id", spokeProjectID)
		ctx.Export("network_name", spokeOutputs.VPC.Name)
		ctx.Export("network_self_link", spokeOutputs.VPC.SelfLink)

		// Subnet exports as arrays (matching TF subnets_names/ips/self_links)
		var subnetNames, subnetIPs, subnetSelfLinks pulumi.StringArray
		for _, subnet := range spokeOutputs.Subnets {
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
		secondaryRangeInputs := make([]interface{}, 0, len(spokeOutputs.Subnets))
		for _, subnet := range spokeOutputs.Subnets {
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

// deployHubNetwork creates the central hub VPC and all shared network resources.
// This runs only in the development stack (first in the promotion chain).
func deployHubNetwork(ctx *pulumi.Context, cfg *NetConfig, orgStack *pulumi.StackReference) (*networking.Networking, error) {
	hubProjectID := orgStack.GetStringOutput(pulumi.String("net_hub_project_id"))

	// Enable Shared VPC Host for the Hub project
	_, err := compute.NewSharedVPCHostProject(ctx, "org-net-hub-svpc-host", &compute.SharedVPCHostProjectArgs{
		Project: hubProjectID,
	})
	if err != nil {
		return nil, err
	}

	// 1. Hierarchical Firewall Policy (org/folder level)
	// Matching upstream: associate with 6 folders (common, network, bootstrap, dev, prod, nonprod)
	associations := cfg.HierarchicalFwAssociations
	if len(associations) == 0 {
		associations = []string{cfg.ParentID}
	}
	_, err = networking.NewHierarchicalFirewallPolicy(ctx, "hierarchical-fw", &networking.HierarchicalFirewallPolicyArgs{
		ParentID:      pulumi.String(cfg.ParentID),
		ShortName:     "fw-hub-svpc-hierarchical",
		Description:   "Hierarchical firewall rules for hub-and-spoke foundation",
		Associations:  associations,
		EnableLogging: cfg.FirewallPoliciesEnableLogging,
	})
	if err != nil {
		return nil, err
	}

	// 2. Hub VPC & Subnets — hub has NO secondary ranges (matching upstream)
	hubVpcName := "vpc-c-svpc-hub"
	hubNetOpts := &networking.NetworkingArgs{
		ProjectID: hubProjectID,
		VPCName:   pulumi.String(hubVpcName),
		EnablePSA: true,
		Subnets: []networking.SubnetArgs{
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
		},
	}

	hubVpc, err := networking.NewNetworking(ctx, "hub", hubNetOpts)
	if err != nil {
		return nil, err
	}

	// Hub Egress internet route (tag-based, for NAT egress)
	hubRoute, err := compute.NewRoute(ctx, "hub-egress-internet", &compute.RouteArgs{
		Project:        hubProjectID,
		Name:           pulumi.String("rt-c-hub-1000-egress-internet-default"),
		Network:        hubVpc.VPC.ID(),
		DestRange:      pulumi.String("0.0.0.0/0"),
		NextHopGateway: pulumi.String("default-internet-gateway"),
		Priority:       pulumi.Int(1000),
		Tags:           pulumi.StringArray{pulumi.String("egress-internet")},
	}, pulumi.DependsOn([]pulumi.Resource{hubVpc.VPC}))
	if err != nil {
		return nil, err
	}

	// Windows KMS route (conditional, matching upstream windows_activation_enabled)
	if cfg.WindowsActivationEnabled {
		_, err = compute.NewRoute(ctx, "hub-windows-kms", &compute.RouteArgs{
			Project:        hubProjectID,
			Name:           pulumi.String("rt-c-svpc-hub-1000-all-default-windows-kms"),
			Network:        hubVpc.VPC.ID(),
			DestRange:      pulumi.String("35.190.247.13/32"),
			NextHopGateway: pulumi.String("default-internet-gateway"),
			Priority:       pulumi.Int(1000),
		}, pulumi.DependsOn([]pulumi.Resource{hubVpc.VPC}))
		if err != nil {
			return nil, err
		}
	}

	// 3. Hub VPC-Level Firewall
	hubFw, err := networking.NewNetworkFirewallPolicy(ctx, "hub-vpc-fw", &networking.NetworkFirewallPolicyArgs{
		ProjectID:  hubProjectID,
		PolicyName: "fp-c-hub-firewalls",
		TargetVPCs: []pulumi.StringInput{
			pulumi.Sprintf("projects/%s/global/networks/%s", hubProjectID, hubVpc.VPC.Name),
		},
		Rules: networking.BuildFoundationRules("c", cfg.FirewallPoliciesEnableLogging, cfg.PscIP+"/32", []string{cfg.HubSubnet1Cidr, cfg.HubSubnet2Cidr}, false),
	}, pulumi.DependsOn([]pulumi.Resource{hubVpc.VPC}))
	if err != nil {
		return nil, err
	}

	// 4. PSC on hub
	_, err = networking.NewPrivateServiceConnect(ctx, "hub-psc", &networking.PrivateServiceConnectArgs{
		ProjectID:            hubProjectID,
		NetworkSelfLink:      hubVpc.VPC.SelfLink,
		DnsCode:              "dz-c-hub",
		IPAddress:            cfg.PscIP,
		ForwardingRuleTarget: "vpc-sc",
	}, pulumi.DependsOn([]pulumi.Resource{hubVpc.VPC}))
	if err != nil {
		return nil, err
	}

	// 5. DNS Policy on hub
	hubDnsPolicy, err := dns.NewPolicy(ctx, "hub-dns-policy", &dns.PolicyArgs{
		Project:                 hubProjectID,
		Name:                    pulumi.String("dp-c-hub-default-policy"),
		EnableInboundForwarding: pulumi.Bool(true),
		EnableLogging:           pulumi.Bool(cfg.DnsEnableLogging),
		Networks: dns.PolicyNetworkArray{
			&dns.PolicyNetworkArgs{
				NetworkUrl: hubVpc.VPC.SelfLink,
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{hubVpc.VPC}))
	if err != nil {
		return nil, err
	}

	// 6. DNS forwarding zone on hub
	if len(cfg.TargetNameServers) > 0 {
		_, err = networking.NewDnsZone(ctx, "dns-forwarding", &networking.DnsZoneArgs{
			ProjectID:                 hubProjectID,
			Name:                      "fz-dns-hub",
			Domain:                    cfg.Domain,
			Type:                      "forwarding",
			NetworkSelfLink:           hubVpc.VPC.SelfLink,
			TargetNameServerAddresses: cfg.TargetNameServers,
		})
		if err != nil {
			return nil, err
		}
	}

	// 7. Transitivity Appliance — conditional (default false, matching upstream)
	if cfg.EnableHubAndSpokeTransitivity {
		_, err = networking.NewTransitivityAppliance(ctx, "transitivity", &networking.TransitivityApplianceArgs{
			ProjectID:   hubProjectID,
			Regions:     []string{cfg.Region1, cfg.Region2},
			Network:     hubVpc.VPC.SelfLink,
			NetworkName: hubVpcName,
			Subnetworks: map[string]pulumi.StringInput{
				cfg.Region1: hubVpc.Subnets[fmt.Sprintf("sb-c-svpc-hub-%s", cfg.Region1)].SelfLink,
				cfg.Region2: hubVpc.Subnets[fmt.Sprintf("sb-c-svpc-hub-%s", cfg.Region2)].SelfLink,
			},
			RegionalAggregates: map[string][]string{
				cfg.Region1: {"10.0.0.0/16", "10.8.0.0/16", "100.64.0.0/18"},
				cfg.Region2: {"10.1.0.0/16", "10.9.0.0/16", "100.66.0.0/18"},
			},
			FirewallPolicy: hubFw.Policy.Name,
		}, pulumi.DependsOn([]pulumi.Resource{hubVpc.VPC}))
		if err != nil {
			return nil, err
		}

		// Health Check Firewall for Transitivity ILBs
		_, err = compute.NewFirewall(ctx, "fw-hub-allow-health-checks", &compute.FirewallArgs{
			Project: hubProjectID,
			Name:    pulumi.String("fw-c-hub-allow-health-checks"),
			Network: hubVpc.VPC.SelfLink,
			Allows: compute.FirewallAllowArray{
				&compute.FirewallAllowArgs{
					Protocol: pulumi.String("tcp"),
					Ports:    pulumi.StringArray{pulumi.String("22")},
				},
			},
			SourceRanges: pulumi.StringArray{
				pulumi.String("130.211.0.0/22"),
				pulumi.String("35.191.0.0/16"),
			},
			TargetTags: pulumi.StringArray{
				pulumi.String("allow-transitivity"),
			},
		}, pulumi.DependsOn([]pulumi.Resource{hubVpc.VPC}))
		if err != nil {
			return nil, err
		}
	}

	// 8. Hub BGP Routers — 4 total (2 per region)
	// We chain these route-modifying resources to avoid "route operation in progress" races
	var routeDependency pulumi.Resource = hubRoute
	advertisedRanges := []networking.AdvertisedIPRange{
		{Range: "35.199.192.0/19", Description: "Google DNS Forwarding Source"},
		{Range: cfg.PscIP + "/32", Description: "PSC Endpoint"},
	}
	for _, reg := range []string{cfg.Region1, cfg.Region2} {
		for _, crIdx := range []string{"5", "6"} {
			cr, err := networking.NewCloudRouter(ctx, fmt.Sprintf("hub-cr-%s-cr%s", reg, crIdx), &networking.RouterArgs{
				ProjectID:          hubProjectID,
				Region:             reg,
				Network:            hubVpc.VPC.SelfLink,
				BgpAsn:             cfg.BgpAsn,
				AdvertisedGroups:   []string{"ALL_SUBNETS"},
				AdvertisedIpRanges: advertisedRanges,
				EnableNat:          false,
			}, pulumi.DependsOn([]pulumi.Resource{routeDependency}))
			if err != nil {
				return nil, err
			}
			routeDependency = cr.Router
		}
	}

	// 9. Separate NAT routers on hub (conditional, matching upstream hub_nat_enabled default false)
	if cfg.HubNatEnabled {
		for _, reg := range []string{cfg.Region1, cfg.Region2} {
			natRouter, err := networking.NewCloudRouter(ctx, fmt.Sprintf("hub-nat-%s", reg), &networking.RouterArgs{
				ProjectID:       hubProjectID,
				Region:          reg,
				Network:         hubVpc.VPC.SelfLink,
				BgpAsn:          cfg.NatBgpAsn,
				EnableNat:       true,
				NatNumAddresses: cfg.NatNumAddresses,
			}, pulumi.DependsOn([]pulumi.Resource{routeDependency}))
			if err != nil {
				return nil, err
			}
			routeDependency = natRouter.Router
		}
	}

	// 10. VPC-SC on hub — perimeter for the hub project
	var hubPolicyID pulumi.StringInput
	if cfg.PolicyID != "" {
		hubPolicyID = pulumi.String(cfg.PolicyID)
	} else {
		hubPolicyID = orgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id"))
	}

	_, err = vpc_sc.NewVpcServiceControls(ctx, "hub-vpc-sc-perimeter", &vpc_sc.VpcServiceControlsArgs{
		PolicyID:           hubPolicyID,
		Prefix:             "c_hub",
		Members:            cfg.VpcScMembers,
		MembersDryRun:      cfg.VpcScMembers,
		ProjectNumbers:     pulumi.StringArray{orgStack.GetStringOutput(pulumi.String("net_hub_project_number"))},
		RestrictedServices: cfg.VpcScRestrictedServices,
		Enforce:            cfg.EnforceVpcSc,
	})
	if err != nil {
		return nil, err
	}

	// Hub exports
	ctx.Export("hub_network_name", hubVpc.VPC.Name)
	ctx.Export("hub_network_self_link", hubVpc.VPC.SelfLink)
	ctx.Export("dns_policy", hubDnsPolicy.ID())

	return hubVpc, nil
}

// deploySpokeNetwork creates the per-environment spoke VPC and peers it to the hub.
func deploySpokeNetwork(ctx *pulumi.Context, cfg *NetConfig, orgStack *pulumi.StackReference, spokeProjectID pulumi.StringOutput, hubProjectID pulumi.StringOutput, opts ...pulumi.ResourceOption) (*networking.Networking, error) {
	// Enable Shared VPC Host for the Spoke project
	_, err := compute.NewSharedVPCHostProject(ctx, fmt.Sprintf("org-net-spoke-%s-svpc-host", cfg.EnvCode), &compute.SharedVPCHostProjectArgs{
		Project: spokeProjectID,
	})
	if err != nil {
		return nil, err
	}

	// 1. Spoke VPC & Subnets — secondary ranges only on R1 (matching upstream)
	spokeVpcName := fmt.Sprintf("vpc-%s-svpc-spoke", cfg.EnvCode)
	spokeNetOpts := &networking.NetworkingArgs{
		ProjectID: spokeProjectID,
		VPCName:   pulumi.String(spokeVpcName),
		EnablePSA: true,
		Subnets: []networking.SubnetArgs{
			{
				Name:   fmt.Sprintf("sb-%s-svpc-spoke-%s", cfg.EnvCode, cfg.Region1),
				Region: cfg.Region1,
				CIDR:   cfg.SpokeSubnet1Cidr,
				SecondaryRanges: []networking.SecondaryRangeArgs{
					{RangeName: fmt.Sprintf("rn-%s-spoke-%s-gke-pod", cfg.EnvCode, cfg.Region1), CIDR: cfg.SpokeGkePod1Cidr},
					{RangeName: fmt.Sprintf("rn-%s-spoke-%s-gke-svc", cfg.EnvCode, cfg.Region1), CIDR: cfg.SpokeGkeSvc1Cidr},
				},
				FlowLogs:         true,
				FlowLogsInterval: cfg.VpcFlowLogs.AggregationInterval,
				FlowLogsSampling: cfg.VpcFlowLogs.FlowSampling,
				FlowLogsMetadata: cfg.VpcFlowLogs.Metadata,
			},
			{
				Name:   fmt.Sprintf("sb-%s-svpc-spoke-%s", cfg.EnvCode, cfg.Region2),
				Region: cfg.Region2,
				CIDR:   cfg.SpokeSubnet2Cidr,
				// No secondary ranges on R2 (matching upstream)
				FlowLogs:         true,
				FlowLogsInterval: cfg.VpcFlowLogs.AggregationInterval,
				FlowLogsSampling: cfg.VpcFlowLogs.FlowSampling,
				FlowLogsMetadata: cfg.VpcFlowLogs.Metadata,
			},
			{
				Name:    fmt.Sprintf("sb-%s-svpc-spoke-%s-proxy", cfg.EnvCode, cfg.Region1),
				Region:  cfg.Region1,
				CIDR:    cfg.SpokeProxy1Cidr,
				Role:    "ACTIVE",
				Purpose: "REGIONAL_MANAGED_PROXY",
			},
			{
				Name:    fmt.Sprintf("sb-%s-svpc-spoke-%s-proxy", cfg.EnvCode, cfg.Region2),
				Region:  cfg.Region2,
				CIDR:    cfg.SpokeProxy2Cidr,
				Role:    "ACTIVE",
				Purpose: "REGIONAL_MANAGED_PROXY",
			},
		},
	}

	spokeVpc, err := networking.NewNetworking(ctx, "spoke", spokeNetOpts)
	if err != nil {
		return nil, err
	}

	// 2. Bi-Directional VPC Peering (Spoke <-> Hub)
	// Matching upstream: spoke does NOT export custom routes to hub,
	// hub exports custom routes to spoke (via export_peer_custom_routes=true on the module).
	hubVpcRef := pulumi.Sprintf("projects/%s/global/networks/vpc-c-svpc-hub", hubProjectID)

	spokeToHub, err := compute.NewNetworkPeering(ctx, "spoke-to-hub", &compute.NetworkPeeringArgs{
		Network:            spokeVpc.VPC.SelfLink,
		PeerNetwork:        hubVpcRef,
		Name:               pulumi.String(fmt.Sprintf("np-%s-svpc-spoke-vpc-c-svpc-hub", cfg.EnvCode)),
		ExportCustomRoutes: pulumi.Bool(false), // Spoke does NOT export to hub (matching upstream)
		ImportCustomRoutes: pulumi.Bool(true),  // Import hub's custom routes
	}, append(opts, pulumi.DependsOn([]pulumi.Resource{spokeVpc.VPC}))...)
	if err != nil {
		return nil, err
	}

	hubToSpoke, err := compute.NewNetworkPeering(ctx, "hub-to-spoke", &compute.NetworkPeeringArgs{
		Network:            hubVpcRef,
		PeerNetwork:        spokeVpc.VPC.SelfLink,
		Name:               pulumi.String(fmt.Sprintf("np-vpc-c-svpc-hub-%s-svpc-spoke", cfg.EnvCode)),
		ExportCustomRoutes: pulumi.Bool(true), // Export hub's custom routes to spoke
		ImportCustomRoutes: pulumi.Bool(false),
	}, append(opts, pulumi.DependsOn([]pulumi.Resource{spokeToHub}))...) // Must create after spoke-to-hub
	if err != nil {
		return nil, err
	}

	// Spoke Egress internet route (tag-based)
	spokeRoute, err := compute.NewRoute(ctx, "spoke-egress-internet", &compute.RouteArgs{
		Project:        spokeProjectID,
		Name:           pulumi.String(fmt.Sprintf("rt-%s-spoke-1000-egress-internet-default", cfg.EnvCode)),
		Network:        spokeVpc.VPC.ID(),
		DestRange:      pulumi.String("0.0.0.0/0"),
		NextHopGateway: pulumi.String("default-internet-gateway"),
		Priority:       pulumi.Int(1000),
		Tags:           pulumi.StringArray{pulumi.String("egress-internet")},
	}, pulumi.DependsOn([]pulumi.Resource{hubToSpoke}))
	if err != nil {
		return nil, err
	}
	var routeDependency pulumi.Resource = spokeRoute

	// Windows KMS route (conditional, matching upstream)
	if cfg.WindowsActivationEnabled {
		_, err = compute.NewRoute(ctx, "spoke-windows-kms", &compute.RouteArgs{
			Project:        spokeProjectID,
			Name:           pulumi.String(fmt.Sprintf("rt-%s-svpc-spoke-1000-all-default-windows-kms", cfg.EnvCode)),
			Network:        spokeVpc.VPC.ID(),
			DestRange:      pulumi.String("35.190.247.13/32"),
			NextHopGateway: pulumi.String("default-internet-gateway"),
			Priority:       pulumi.Int(1000),
		}, pulumi.DependsOn([]pulumi.Resource{spokeVpc.VPC}))
		if err != nil {
			return nil, err
		}
	}

	// 3. Spoke VPC-Level Firewall
	_, err = networking.NewNetworkFirewallPolicy(ctx, "spoke-vpc-fw", &networking.NetworkFirewallPolicyArgs{
		ProjectID:  spokeProjectID,
		PolicyName: fmt.Sprintf("fp-%s-spoke-firewalls", cfg.EnvCode),
		TargetVPCs: []pulumi.StringInput{
			pulumi.Sprintf("projects/%s/global/networks/%s", spokeProjectID, spokeVpc.VPC.Name),
		},
		Rules: networking.BuildFoundationRules(cfg.EnvCode, cfg.FirewallPoliciesEnableLogging, cfg.PscIP+"/32", []string{cfg.SpokeSubnet1Cidr, cfg.SpokeSubnet2Cidr}, false),
	}, pulumi.DependsOn([]pulumi.Resource{spokeVpc.VPC}))
	if err != nil {
		return nil, err
	}

	// 4. PSC on spoke
	_, err = networking.NewPrivateServiceConnect(ctx, "spoke-psc", &networking.PrivateServiceConnectArgs{
		ProjectID:            spokeProjectID,
		NetworkSelfLink:      spokeVpc.VPC.SelfLink,
		DnsCode:              fmt.Sprintf("dz-%s-spoke", cfg.EnvCode),
		IPAddress:            cfg.PscIP,
		ForwardingRuleTarget: "vpc-sc",
	}, pulumi.DependsOn([]pulumi.Resource{spokeVpc.VPC}))
	if err != nil {
		return nil, err
	}

	// 5. DNS Policy on spoke
	_, err = dns.NewPolicy(ctx, "spoke-dns-policy", &dns.PolicyArgs{
		Project:                 spokeProjectID,
		Name:                    pulumi.String(fmt.Sprintf("dp-%s-spoke-default-policy", cfg.EnvCode)),
		EnableInboundForwarding: pulumi.Bool(true),
		EnableLogging:           pulumi.Bool(cfg.DnsEnableLogging),
		Networks: dns.PolicyNetworkArray{
			&dns.PolicyNetworkArgs{
				NetworkUrl: spokeVpc.VPC.SelfLink,
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{spokeVpc.VPC}))
	if err != nil {
		return nil, err
	}

	// 6. DNS peering from spoke to hub
	_, err = networking.NewDnsZone(ctx, "dns-peering", &networking.DnsZoneArgs{
		ProjectID:             spokeProjectID,
		Name:                  fmt.Sprintf("dz-%s-svpc-spoke-to-dns-hub", cfg.EnvCode),
		Domain:                cfg.Domain,
		Type:                  "peering",
		NetworkSelfLink:       spokeVpc.VPC.SelfLink,
		TargetNetworkSelfLink: hubVpcRef,
	}, opts...)
	if err != nil {
		return nil, err
	}

	// 7. NAT routers on spoke (conditional, matching upstream nat_enabled default false)
	// Spokes don't get BGP routers in hub-and-spoke architecture.
	if cfg.NatEnabled {
		for _, reg := range []string{cfg.Region1, cfg.Region2} {
			natRouter, err := networking.NewCloudRouter(ctx, fmt.Sprintf("spoke-nat-%s", reg), &networking.RouterArgs{
				ProjectID:       spokeProjectID,
				Region:          reg,
				Network:         spokeVpc.VPC.SelfLink,
				BgpAsn:          cfg.NatBgpAsn,
				EnableNat:       true,
				NatNumAddresses: cfg.NatNumAddresses,
			}, pulumi.DependsOn([]pulumi.Resource{routeDependency}))
			if err != nil {
				return nil, err
			}
			routeDependency = natRouter.Router
		}
	}

	// 8. VPC-SC on spoke — access levels, regular perimeter, and bridge perimeter
	var policyID pulumi.StringInput
	if cfg.PolicyID != "" {
		policyID = pulumi.String(cfg.PolicyID)
	} else {
		policyID = orgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id"))
	}
	acmPolicyID := orgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id"))

	// Spoke project number for VPC-SC perimeter
	spokeProjectNumber := orgStack.GetStringOutput(pulumi.String(fmt.Sprintf("%s_network_project_number", cfg.Env)))
	hubProjectNumber := orgStack.GetStringOutput(pulumi.String("net_hub_project_number"))

	perimeter, err := vpc_sc.NewVpcServiceControls(ctx, "vpc-sc-perimeter", &vpc_sc.VpcServiceControlsArgs{
		PolicyID:           policyID,
		Prefix:             fmt.Sprintf("%s_spoke", cfg.EnvCode),
		Members:            cfg.VpcScMembers,
		MembersDryRun:      cfg.VpcScMembers,
		ProjectNumbers:     pulumi.StringArray{spokeProjectNumber},
		RestrictedServices: cfg.VpcScRestrictedServices,
		Enforce:            cfg.EnforceVpcSc,
	})
	if err != nil {
		return nil, err
	}

	// VPC-SC propagation wait — matching upstream time_sleep 60s create + 60s destroy
	vpcScSleep, err := time.NewSleep(ctx, "vpc-sc-propagation-wait", &time.SleepArgs{
		CreateDuration:  pulumi.String("60s"),
		DestroyDuration: pulumi.String("60s"),
	}, pulumi.DependsOn([]pulumi.Resource{
		perimeter.Perimeter,
		spokeVpc.VPC,
	}))
	if err != nil {
		return nil, err
	}

	// Bridge perimeter from spoke to hub (required for VPC-SC across peered VPCs)
	// Matching upstream PERIMETER_TYPE_BRIDGE — only created on spoke, not hub
	bridgeName := fmt.Sprintf("spb_c_to_%s_spoke_bridge", cfg.EnvCode)
	_, err = accesscontextmanager.NewServicePerimeter(ctx, "vpc-sc-bridge", &accesscontextmanager.ServicePerimeterArgs{
		PerimeterType:         pulumi.String("PERIMETER_TYPE_BRIDGE"),
		Parent:                pulumi.Sprintf("accessPolicies/%s", policyID),
		Name:                  pulumi.Sprintf("accessPolicies/%s/servicePerimeters/%s", policyID, bridgeName),
		Title:                 pulumi.String(bridgeName),
		UseExplicitDryRunSpec: pulumi.Bool(!cfg.EnforceVpcSc),
		Status: &accesscontextmanager.ServicePerimeterStatusArgs{
			Resources: pulumi.StringArray{
				pulumi.Sprintf("projects/%s", spokeProjectNumber),
				pulumi.Sprintf("projects/%s", hubProjectNumber),
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{vpcScSleep}))
	if err != nil {
		return nil, err
	}

	// VPC-SC exports
	perimeterName := pulumi.All(vpcScSleep.ID(), perimeter.Perimeter.Name).ApplyT(func(args []interface{}) string {
		return args[1].(string)
	}).(pulumi.StringOutput)

	ctx.Export("access_context_manager_policy_id", acmPolicyID)
	ctx.Export("enforce_vpcsc", pulumi.Bool(cfg.EnforceVpcSc))
	ctx.Export("service_perimeter_name", perimeterName)
	ctx.Export("access_level_name", perimeter.AccessLevel.Name)
	ctx.Export("access_level_name_dry_run", perimeter.AccessLevelDryRun.Name)

	return spokeVpc, nil
}
