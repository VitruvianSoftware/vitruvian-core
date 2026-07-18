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

// Package shared_vpc is the Pulumi port of upstream terraform-example-foundation
// 3-networks-hub-and-spoke/modules/shared_vpc. It creates one Shared VPC host
// network (VPC, subnets, routes, peering, routers, firewall, PSC, DNS, NAT, and
// the VPC-SC perimeter) and branches on Mode ("hub" or "spoke") for the portion
// that differs between the central hub and the per-environment spokes. Callers
// (the hub dispatch in main.go and the base_env spoke orchestrator) build the
// subnet args + VPC name and invoke New.
//
// The module is a plain composition (NOT a ComponentResource) so that every
// child keeps its original stack-root URN — this is a behaviour-preserving
// extraction of the example's monolith.
package shared_vpc

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// Args are the inputs to the shared_vpc module. Fields common to both hub and
// spoke are always populated; the caller sets Mode/Code to select the naming
// scheme and the mode-specific resources (peering + bridge on spoke, BGP routers
// + forwarding zone on hub).
type Args struct {
	Mode string // "hub" or "spoke"
	Code string // env_code ("c" for hub, "d"/"n"/"p" for spoke)

	// Projects & cross-stage references.
	ProjectID    pulumi.StringInput  // host project (hub or spoke)
	HubProjectID pulumi.StringOutput // hub host project — used by spoke peering ref
	OrgStackName string              // 1-org stack name (VPC-SC stack references)

	// VPC + subnets (built by the caller).
	VPCName             string
	Subnets             []networking.SubnetArgs
	FirewallSubnetCidrs []string // primary subnet CIDRs, for the foundation firewall rules

	// Regions (router loops).
	Region1 string
	Region2 string

	// Private Service Connect.
	PscIP string

	// Logging toggles.
	FirewallPoliciesEnableLogging bool
	DnsEnableLogging              bool

	// DNS.
	Domain            string
	TargetNameServers []string // hub forwarding zone only

	// Routes.
	WindowsActivationEnabled bool

	// NAT (caller passes HubNatEnabled for hub, NatEnabled for spoke).
	NatEnabled      bool
	NatBgpAsn       int
	NatNumAddresses int

	// BGP (hub only).
	BgpAsn int

	// VPC Service Controls.
	PolicyID                   string
	VpcScMembers               []string
	VpcScProjects              []string
	VpcScRestrictedServices    []string
	EnforceVpcSc               bool
	VpcScIngressPolicies       accesscontextmanager.ServicePerimeterStatusIngressPolicyArray
	VpcScEgressPolicies        accesscontextmanager.ServicePerimeterStatusEgressPolicyArray
	VpcScIngressPoliciesDryRun accesscontextmanager.ServicePerimeterSpecIngressPolicyArray
	VpcScEgressPoliciesDryRun  accesscontextmanager.ServicePerimeterSpecEgressPolicyArray
}

// Result holds the outputs of a single shared VPC deployment.
type Result struct {
	Networking *networking.Networking
	Firewall   *networking.NetworkFirewallPolicy
}

// New creates the Shared VPC host network and all attached resources. opts is
// threaded through the spoke-only resources (peering + DNS peering zone) so a
// caller can serialise them behind the hub VPC when both are created in one run.
func New(ctx *pulumi.Context, args *Args, opts ...pulumi.ResourceOption) (*Result, error) {
	isHub := args.Mode == "hub"

	// Enable Shared VPC Host for the host project.
	hostName := "spoke-svpc-host"
	if isHub {
		hostName = "hub-svpc-host"
	}
	if _, err := compute.NewSharedVPCHostProject(ctx, hostName, &compute.SharedVPCHostProjectArgs{
		Project: args.ProjectID,
	}); err != nil {
		return nil, err
	}

	// VPC & Subnets.
	vpc, err := networking.NewNetworking(ctx, args.Mode, &networking.NetworkingArgs{
		ProjectID: args.ProjectID,
		VPCName:   pulumi.String(args.VPCName),
		EnablePSA: true,
		Subnets:   args.Subnets,
	})
	if err != nil {
		return nil, err
	}

	// Egress-route dependency: the hub route serialises behind its own VPC; the
	// spoke route serialises behind the hub<->spoke peering (created first).
	var egressDep pulumi.Resource = vpc.VPC
	if !isHub {
		hubToSpoke, err := createPeering(ctx, args, vpc, opts...)
		if err != nil {
			return nil, err
		}
		egressDep = hubToSpoke
	}

	// Egress internet route (tag-based, for NAT egress).
	egressRoute, err := createEgressRoute(ctx, args, vpc, egressDep)
	if err != nil {
		return nil, err
	}
	var routeDependency pulumi.Resource = egressRoute

	// Windows KMS route (spoke only, conditional on windows_activation_enabled).
	if !isHub && args.WindowsActivationEnabled {
		if err := createWindowsKmsRoute(ctx, args, vpc); err != nil {
			return nil, err
		}
	}

	// VPC-level firewall.
	fw, err := createFirewall(ctx, args, vpc)
	if err != nil {
		return nil, err
	}

	// Private Service Connect.
	if err := createPSC(ctx, args, vpc); err != nil {
		return nil, err
	}

	// DNS policy.
	dnsPolicy, err := createDNSPolicy(ctx, args, vpc)
	if err != nil {
		return nil, err
	}

	if isHub {
		// DNS forwarding zone.
		if err := createDNSForwardingZone(ctx, args, vpc); err != nil {
			return nil, err
		}

		// Hub BGP routers — 4 total (2 per region). We chain these
		// route-modifying resources to avoid "route operation in progress"
		// races.
		routeDependency, err = createHubBgpRouters(ctx, args, vpc, routeDependency)
		if err != nil {
			return nil, err
		}
	} else {
		// DNS peering from spoke to hub.
		if err := createDNSPeeringZone(ctx, args, vpc); err != nil {
			return nil, err
		}
	}

	// NAT routers (conditional).
	if args.NatEnabled {
		routeDependency, err = createNAT(ctx, args, vpc, routeDependency)
		if err != nil {
			return nil, err
		}
	}
	_ = routeDependency

	// VPC Service Controls.
	if isHub {
		if err := createHubServiceControl(ctx, args); err != nil {
			return nil, err
		}

		// Hub exports — matching the example's envs/shared outputs.
		ctx.Export("shared_vpc_host_project_id", args.ProjectID)
		ctx.Export("network_name", vpc.VPC.Name)
		ctx.Export("dns_policy", dnsPolicy.ID())
	} else {
		if err := createSpokeServiceControl(ctx, args); err != nil {
			return nil, err
		}
	}

	return &Result{Networking: vpc, Firewall: fw}, nil
}

// createPeering wires bi-directional VPC peering (spoke <-> hub) and returns the
// hub-to-spoke peering, which downstream spoke resources serialise behind.
func createPeering(ctx *pulumi.Context, args *Args, vpc *networking.Networking, opts ...pulumi.ResourceOption) (pulumi.Resource, error) {
	hubVpcRef := pulumi.Sprintf("projects/%s/global/networks/vpc-c-svpc-hub", args.HubProjectID)

	// Serialize the spoke peering behind the spoke's PSA servicenetworking
	// connection: GCP allows only one peering-mutating operation at a time per
	// VPC, and both the PSA connection and this peering mutate the spoke VPC's
	// peering set. Upstream terraform orders peering-before-PSA (via module
	// depends_on); we order PSA-before-peering, which is equally deadlock-free
	// — only the direction of the serialization differs, per the repo's
	// replicate-upstream-behaviour-with-documented-workaround convention.
	peeringDeps := []pulumi.Resource{vpc.VPC}
	if vpc.PSAConnection != nil {
		peeringDeps = append(peeringDeps, vpc.PSAConnection)
	}
	spokeToHub, err := compute.NewNetworkPeering(ctx, "spoke-to-hub", &compute.NetworkPeeringArgs{
		Network:            vpc.VPC.SelfLink,
		PeerNetwork:        hubVpcRef,
		Name:               pulumi.String(fmt.Sprintf("np-%s-svpc-spoke-vpc-c-svpc-hub", args.Code)),
		ExportCustomRoutes: pulumi.Bool(false),
		ImportCustomRoutes: pulumi.Bool(true), // Import hub's custom routes
	}, append(opts, pulumi.DependsOn(peeringDeps))...)
	if err != nil {
		return nil, err
	}

	hubToSpoke, err := compute.NewNetworkPeering(ctx, "hub-to-spoke", &compute.NetworkPeeringArgs{
		Network:            hubVpcRef,
		PeerNetwork:        vpc.VPC.SelfLink,
		Name:               pulumi.String(fmt.Sprintf("np-vpc-c-svpc-hub-%s-svpc-spoke", args.Code)),
		ExportCustomRoutes: pulumi.Bool(true), // Export hub's custom routes to spoke
		ImportCustomRoutes: pulumi.Bool(false),
	}, append(opts, pulumi.DependsOn([]pulumi.Resource{spokeToHub}))...) // Must create after spoke-to-hub
	if err != nil {
		return nil, err
	}

	return hubToSpoke, nil
}

// createEgressRoute creates the tag-based egress-to-internet route.
func createEgressRoute(ctx *pulumi.Context, args *Args, vpc *networking.Networking, dependsOn pulumi.Resource) (pulumi.Resource, error) {
	resourceName := fmt.Sprintf("%s-egress-internet", args.Mode)
	route, err := compute.NewRoute(ctx, resourceName, &compute.RouteArgs{
		Project:        args.ProjectID,
		Name:           pulumi.String(fmt.Sprintf("rt-%s-%s-1000-egress-internet-default", args.Code, args.Mode)),
		Network:        vpc.VPC.ID(),
		DestRange:      pulumi.String("0.0.0.0/0"),
		NextHopGateway: pulumi.String("default-internet-gateway"),
		Priority:       pulumi.Int(1000),
		Tags:           pulumi.StringArray{pulumi.String("egress-internet")},
	}, pulumi.DependsOn([]pulumi.Resource{dependsOn}))
	if err != nil {
		return nil, err
	}
	return route, nil
}

// createWindowsKmsRoute creates the conditional Windows KMS route (spoke only).
func createWindowsKmsRoute(ctx *pulumi.Context, args *Args, vpc *networking.Networking) error {
	_, err := compute.NewRoute(ctx, "windows-kms", &compute.RouteArgs{
		Project:        args.ProjectID,
		Name:           pulumi.String(fmt.Sprintf("rt-%s-svpc-spoke-1000-all-default-windows-kms", args.Code)),
		Network:        vpc.VPC.ID(),
		DestRange:      pulumi.String("35.190.247.13/32"),
		NextHopGateway: pulumi.String("default-internet-gateway"),
		Priority:       pulumi.Int(1000),
	}, pulumi.DependsOn([]pulumi.Resource{vpc.VPC}))
	return err
}

// createHubBgpRouters creates the 4 hub Cloud Routers (2 per region), chaining
// each behind the previous route-modifying resource to serialise route ops.
func createHubBgpRouters(ctx *pulumi.Context, args *Args, vpc *networking.Networking, routeDependency pulumi.Resource) (pulumi.Resource, error) {
	advertisedRanges := []networking.AdvertisedIPRange{
		{Range: "35.199.192.0/19", Description: "Google DNS Forwarding Source"},
		{Range: args.PscIP + "/32", Description: "PSC Endpoint"},
	}
	for _, reg := range []string{args.Region1, args.Region2} {
		for _, crIdx := range []string{"5", "6"} {
			cr, err := networking.NewCloudRouter(ctx, fmt.Sprintf("hub-cr-%s-cr%s", reg, crIdx), &networking.RouterArgs{
				ProjectID:          args.ProjectID,
				Region:             reg,
				Network:            vpc.VPC.SelfLink,
				BgpAsn:             args.BgpAsn,
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
	return routeDependency, nil
}
