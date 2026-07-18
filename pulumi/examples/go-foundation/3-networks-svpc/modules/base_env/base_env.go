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

// Package base_env orchestrates the per-environment Shared VPC and router
// setup. Mirrors: terraform-example-foundation/3-networks-svpc/modules/base_env.
//
// Pulumi-port note: upstream base_env composes a separate shared_vpc module;
// this port keeps the Shared VPC resource composition inline here (a single
// per-environment orchestrator) — a documented structural divergence that
// preserves the original flat port's resource logical names byte-for-byte so
// the envs/ split stays a preview no-op.
package base_env

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/dns"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumiverse/pulumi-time/sdk/go/time"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
	vpc_sc "github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls"
)

// Args are the inputs to the base_env module — the per-environment identity
// plus the network/DNS/NAT/VPC-SC settings from the leaf's stack config.
type Args struct {
	Env     string // "development" | "nonproduction" | "production"
	EnvCode string // "d" | "n" | "p"

	// Shared VPC host project for this environment.
	ProjectID string

	// Regions.
	Region1 string
	Region2 string

	// DNS.
	Domain       string
	DNSProjectID string // DNS hub project (peering target for non-prod envs)

	// Cross-stage references.
	OrgStackName string

	// VPC Service Controls.
	PolicyID                   string
	VpcScMembers               []string
	VpcScProjects              []string
	VpcScRestrictedServices    []string
	VpcScIngressPolicies       accesscontextmanager.ServicePerimeterStatusIngressPolicyArray
	VpcScEgressPolicies        accesscontextmanager.ServicePerimeterStatusEgressPolicyArray
	VpcScIngressPoliciesDryRun accesscontextmanager.ServicePerimeterSpecIngressPolicyArray
	VpcScEgressPoliciesDryRun  accesscontextmanager.ServicePerimeterSpecEgressPolicyArray
	EnforceVpcSc               bool

	// PSC.
	PscIP string

	// BGP / NAT.
	BgpAsn          int
	NatBgpAsn       int
	NatNumAddresses int
	NatEnabled      bool

	// DNS / firewall logging toggles.
	TargetNameServers             []string
	FirewallPoliciesEnableLogging bool
	DnsEnableLogging              bool

	// Routes.
	WindowsActivationEnabled bool

	// VPC flow logs.
	FlowLogsInterval string
	FlowLogsSampling float64
	FlowLogsMetadata string
}

// Result holds the per-environment outputs consumed by the leaf root exports.
type Result struct {
	Networking            *networking.Networking
	AcmPolicyID           pulumi.StringOutput
	PerimeterName         pulumi.StringOutput
	AccessLevelName       pulumi.StringOutput
	AccessLevelDryRunName pulumi.StringOutput
}

// New deploys the per-environment Shared VPC: host designation, VPC + subnets
// with GKE secondary ranges, VPC-level firewall, PSC, DNS policy and zones,
// tag-based egress routing, BGP routers, optional NAT, and the VPC-SC
// perimeter.
func New(ctx *pulumi.Context, args *Args) (*Result, error) {
	// Compute environment-specific advertised IP ranges
	// Production advertises the Google DNS forwarding source range + PSC endpoint
	// Other environments only advertise the PSC endpoint
	advertisedRanges := []networking.AdvertisedIPRange{
		{Range: args.PscIP + "/32", Description: "PSC Endpoint"},
	}
	if args.Env == "production" {
		advertisedRanges = append([]networking.AdvertisedIPRange{
			{Range: "35.199.192.0/19", Description: "Google DNS Forwarding Source"},
		}, advertisedRanges...)
	}

	// 1. Shared VPC Host
	if _, err := compute.NewSharedVPCHostProject(ctx, "svpc-host", &compute.SharedVPCHostProjectArgs{
		Project: pulumi.String(args.ProjectID),
	}); err != nil {
		return nil, err
	}

	// 2. VPC & Subnets (delete_default_routes_on_create = true)
	netName := fmt.Sprintf("vpc-%s-svpc", args.EnvCode)
	netOpts := &networking.NetworkingArgs{
		ProjectID: pulumi.String(args.ProjectID),
		VPCName:   pulumi.String(netName),
		EnablePSA: true,
		Subnets: []networking.SubnetArgs{
			{
				Name:   fmt.Sprintf("sb-%s-svpc-%s", args.EnvCode, args.Region1),
				Region: args.Region1,
				CIDR:   "10.8.64.0/18",
				SecondaryRanges: []networking.SecondaryRangeArgs{
					{RangeName: fmt.Sprintf("rn-%s-svpc-%s-gke-pod", args.EnvCode, args.Region1), CIDR: "100.72.64.0/18"},
					{RangeName: fmt.Sprintf("rn-%s-svpc-%s-gke-svc", args.EnvCode, args.Region1), CIDR: "100.73.64.0/18"},
				},
				FlowLogs:         true,
				FlowLogsInterval: args.FlowLogsInterval,
				FlowLogsSampling: args.FlowLogsSampling,
				FlowLogsMetadata: args.FlowLogsMetadata,
			},
			{
				Name:             fmt.Sprintf("sb-%s-svpc-%s", args.EnvCode, args.Region2),
				Region:           args.Region2,
				CIDR:             "10.9.64.0/18",
				FlowLogs:         true,
				FlowLogsInterval: args.FlowLogsInterval,
				FlowLogsSampling: args.FlowLogsSampling,
				FlowLogsMetadata: args.FlowLogsMetadata,
			},
			{ // Proxy-only subnets for ILB
				Name:    fmt.Sprintf("sb-%s-svpc-%s-proxy", args.EnvCode, args.Region1),
				Region:  args.Region1,
				CIDR:    "10.26.2.0/23",
				Role:    "ACTIVE",
				Purpose: "REGIONAL_MANAGED_PROXY",
			},
			{
				Name:    fmt.Sprintf("sb-%s-svpc-%s-proxy", args.EnvCode, args.Region2),
				Region:  args.Region2,
				CIDR:    "10.27.2.0/23",
				Role:    "ACTIVE",
				Purpose: "REGIONAL_MANAGED_PROXY",
			},
		},
	}

	vpcModule, err := networking.NewNetworking(ctx, "svpc", netOpts)
	if err != nil {
		return nil, err
	}

	// 3. VPC-Level Firewall Policy (Default Deny Egress) — data-driven rules
	_, err = networking.NewNetworkFirewallPolicy(ctx, "vpc-fw", &networking.NetworkFirewallPolicyArgs{
		ProjectID:  pulumi.String(args.ProjectID),
		PolicyName: fmt.Sprintf("fp-%s-svpc-firewalls", args.EnvCode),
		TargetVPCs: []pulumi.StringInput{
			pulumi.Sprintf("projects/%s/global/networks/%s", args.ProjectID, vpcModule.VPC.Name),
		},
		Rules: networking.BuildFoundationRules(args.EnvCode, args.FirewallPoliciesEnableLogging, args.PscIP+"/32", []string{"10.8.64.0/18", "10.9.64.0/18"}, false),
	}, pulumi.DependsOn([]pulumi.Resource{vpcModule.VPC}))
	if err != nil {
		return nil, err
	}

	// 4. Private Service Connect (PSC) — googleapis + gcr.io + pkg.dev DNS
	_, err = networking.NewPrivateServiceConnect(ctx, "psc", &networking.PrivateServiceConnectArgs{
		ProjectID:            pulumi.String(args.ProjectID),
		NetworkSelfLink:      vpcModule.VPC.SelfLink,
		DnsCode:              fmt.Sprintf("dz-%s-svpc", args.EnvCode),
		IPAddress:            args.PscIP,
		ForwardingRuleTarget: "vpc-sc",
	}, pulumi.DependsOn([]pulumi.Resource{vpcModule.VPC}))
	if err != nil {
		return nil, err
	}

	// 5. DNS Policy (inbound forwarding + logging)
	_, err = dns.NewPolicy(ctx, "dns-default-policy", &dns.PolicyArgs{
		Project:                 pulumi.String(args.ProjectID),
		Name:                    pulumi.String(fmt.Sprintf("dp-%s-svpc-default-policy", args.EnvCode)),
		EnableInboundForwarding: pulumi.Bool(true),
		EnableLogging:           pulumi.Bool(args.DnsEnableLogging),
		Networks: dns.PolicyNetworkArray{
			&dns.PolicyNetworkArgs{
				NetworkUrl: vpcModule.VPC.SelfLink,
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{vpcModule.VPC}))
	if err != nil {
		return nil, err
	}

	// 6. Egress internet route (tag-based, only when NAT is enabled)
	svpcRoute, err := compute.NewRoute(ctx, "egress-internet", &compute.RouteArgs{
		Project:        pulumi.String(args.ProjectID),
		Name:           pulumi.String(fmt.Sprintf("rt-%s-svpc-1000-egress-internet-default", args.EnvCode)),
		Network:        vpcModule.VPC.ID(),
		DestRange:      pulumi.String("0.0.0.0/0"),
		NextHopGateway: pulumi.String("default-internet-gateway"),
		Priority:       pulumi.Int(1000),
		Tags:           pulumi.StringArray{pulumi.String("egress-internet")},
	}, pulumi.DependsOn([]pulumi.Resource{vpcModule.VPC}))
	if err != nil {
		return nil, err
	}

	// 7. DNS Peering / Forwarding Zones
	if args.EnvCode == "p" {
		_, err = networking.NewDnsZone(ctx, "dns-forwarding", &networking.DnsZoneArgs{
			ProjectID:                 pulumi.String(args.ProjectID),
			Name:                      "fz-dns-hub",
			Domain:                    args.Domain,
			Type:                      "forwarding",
			NetworkSelfLink:           vpcModule.VPC.SelfLink,
			TargetNameServerAddresses: args.TargetNameServers,
		})
		if err != nil {
			return nil, err
		}
	} else {
		_, err = networking.NewDnsZone(ctx, "dns-peering", &networking.DnsZoneArgs{
			ProjectID:             pulumi.String(args.ProjectID),
			Name:                  fmt.Sprintf("dz-%s-svpc-to-dns-hub", args.EnvCode),
			Domain:                args.Domain,
			Type:                  "peering",
			NetworkSelfLink:       vpcModule.VPC.SelfLink,
			TargetNetworkSelfLink: pulumi.String(fmt.Sprintf("projects/%s/global/networks/vpc-p-svpc", args.DNSProjectID)),
		})
		if err != nil {
			return nil, err
		}
	}

	var routeDependency pulumi.Resource = svpcRoute

	// Windows activation KMS route (conditional)
	if args.WindowsActivationEnabled {
		_, err = compute.NewRoute(ctx, "windows-kms", &compute.RouteArgs{
			Project:        pulumi.String(args.ProjectID),
			Name:           pulumi.String(fmt.Sprintf("rt-%s-svpc-svpc-1000-all-default-windows-kms", args.EnvCode)),
			Network:        vpcModule.VPC.ID(),
			DestRange:      pulumi.String("35.190.247.13/32"),
			NextHopGateway: pulumi.String("default-internet-gateway"),
			Priority:       pulumi.Int(1000),
		}, pulumi.DependsOn([]pulumi.Resource{vpcModule.VPC}))
		if err != nil {
			return nil, err
		}
	}
	// 8. BGP Cloud Routers — 4 total (2 per region), matching upstream
	for _, reg := range []string{args.Region1, args.Region2} {
		for _, crIdx := range []string{"5", "6"} {
			cr, err := networking.NewCloudRouter(ctx, fmt.Sprintf("cr-%s-cr%s", reg, crIdx), &networking.RouterArgs{
				ProjectID:          pulumi.String(args.ProjectID),
				Region:             reg,
				Network:            vpcModule.VPC.SelfLink,
				BgpAsn:             args.BgpAsn,
				AdvertisedGroups:   []string{"ALL_SUBNETS"},
				AdvertisedIpRanges: advertisedRanges,
				EnableNat:          false, // BGP routers don't have NAT
			}, pulumi.DependsOn([]pulumi.Resource{routeDependency}))
			if err != nil {
				return nil, err
			}
			routeDependency = cr.Router
		}
	}

	// 9. Separate NAT Routers — 1 per region with static IPs (matches upstream nat.tf)
	if args.NatEnabled {
		for _, reg := range []string{args.Region1, args.Region2} {
			natRouter, err := networking.NewCloudRouter(ctx, fmt.Sprintf("nat-router-%s", reg), &networking.RouterArgs{
				ProjectID:       pulumi.String(args.ProjectID),
				Region:          reg,
				Network:         vpcModule.VPC.SelfLink,
				BgpAsn:          args.NatBgpAsn,
				EnableNat:       true,
				NatNumAddresses: args.NatNumAddresses,
			}, pulumi.DependsOn([]pulumi.Resource{routeDependency}))
			if err != nil {
				return nil, err
			}
			routeDependency = natRouter.Router
		}
	}

	// Resolve the ACM policy from the org stack (for the exports and, when no
	// local override is configured, the perimeter).
	var acmPolicyID pulumi.StringOutput
	if args.OrgStackName != "" {
		orgStack, err := pulumi.NewStackReference(ctx, "org", &pulumi.StackReferenceArgs{
			Name: pulumi.String(args.OrgStackName),
		})
		if err != nil {
			return nil, err
		}
		acmPolicyID = orgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id"))
	} else {
		acmPolicyID = pulumi.String("").ToStringOutput()
	}

	// 10. VPC Service Controls Perimeter
	var perimeterName pulumi.StringOutput
	var accessLevelName pulumi.StringOutput
	var accessLevelDryRunName pulumi.StringOutput
	// Resolve the policy from local config or the org stack (TF always creates the perimeter).
	var finalPolicyID pulumi.StringInput = acmPolicyID
	if args.PolicyID != "" {
		finalPolicyID = pulumi.String(args.PolicyID)
	}
	if args.PolicyID != "" || args.OrgStackName != "" {
		perimeter, err := vpc_sc.NewVpcServiceControls(ctx, "vpc-sc-perimeter", &vpc_sc.VpcServiceControlsArgs{
			PolicyID:              finalPolicyID,
			Prefix:                fmt.Sprintf("%s_svpc", args.EnvCode),
			Members:               args.VpcScMembers,
			MembersDryRun:         args.VpcScMembers,
			ProjectNumbers:        pulumi.ToStringArray(args.VpcScProjects),
			RestrictedServices:    args.VpcScRestrictedServices,
			Enforce:               args.EnforceVpcSc,
			IngressPolicies:       args.VpcScIngressPolicies,
			EgressPolicies:        args.VpcScEgressPolicies,
			IngressPoliciesDryRun: args.VpcScIngressPoliciesDryRun,
			EgressPoliciesDryRun:  args.VpcScEgressPoliciesDryRun,
		})
		if err != nil {
			return nil, err
		}

		vpcScSleep, err := time.NewSleep(ctx, "vpc-sc-propagation-wait", &time.SleepArgs{
			CreateDuration:  pulumi.String("60s"),
			DestroyDuration: pulumi.String("60s"),
		}, pulumi.DependsOn([]pulumi.Resource{perimeter.Perimeter}))
		if err != nil {
			return nil, err
		}

		perimeterName = pulumi.All(vpcScSleep.ID(), perimeter.Perimeter.Name).ApplyT(func(args []interface{}) string {
			return args[1].(string)
		}).(pulumi.StringOutput)

		accessLevelName = perimeter.AccessLevel.Name
		accessLevelDryRunName = perimeter.AccessLevelDryRun.Name
	} else {
		perimeterName = pulumi.String("").ToStringOutput()
	}

	return &Result{
		Networking:            vpcModule,
		AcmPolicyID:           acmPolicyID,
		PerimeterName:         perimeterName,
		AccessLevelName:       accessLevelName,
		AccessLevelDryRunName: accessLevelDryRunName,
	}, nil
}
