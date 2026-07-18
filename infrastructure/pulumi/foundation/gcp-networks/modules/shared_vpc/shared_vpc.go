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

// Package shared_vpc is the unified Pulumi port of upstream
// terraform-example-foundation 3-networks-hub-and-spoke/modules/shared_vpc. It
// creates one Shared VPC host network (VPC, subnets, routes, peering, routers,
// firewall, PSC, DNS, NAT, and the VPC-SC perimeter) and branches on Mode
// ("hub" or "spoke") for the ~30% that differs between the central hub and the
// per-environment spokes. Callers (the hub dispatch in main.go and the base_env
// spoke orchestrator) build the subnet args + VPC name and invoke New.
//
// The module is a plain composition (NOT a ComponentResource) so that every
// child keeps its original stack-root URN — this is a behaviour-preserving
// extraction, so the resource logical-name strings are byte-identical to the
// pre-refactor monolith and a pulumi preview is a no-op.
package shared_vpc

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// Args are the inputs to the shared_vpc module. Fields common to both hub and
// spoke are always populated; the caller sets Mode/Code to select the naming
// scheme and the mode-specific resources (peering + bridge on spoke, BGP
// routers + forwarding zone on hub).
type Args struct {
	Mode string // "hub" or "spoke"
	Code string // "c" for hub, environment code ("d"/"n"/"p") for spoke

	// Projects & cross-stage references.
	ProjectID    pulumi.StringInput     // host project (hub or spoke)
	HubProjectID pulumi.StringOutput    // hub host project — used by spoke peering ref + bridge
	OrgStack     *pulumi.StackReference // 1-org exports (project numbers, ACM policy)
	Env          string                 // full env name, for spoke stack-output keys

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
	PolicyID                string
	VpcScMembers            []string
	VpcScRestrictedServices []string
	EnforceVpcSc            bool
}

// Result holds the outputs of a single shared VPC deployment.
type Result struct {
	Networking *networking.Networking
	Firewall   *networking.NetworkFirewallPolicy
}

// New creates the Shared VPC host network and all attached resources. opts is
// threaded through the spoke-only resources (peering + DNS peering zone) so the
// caller can serialise them behind the hub VPC when the hub and spoke are
// created in the same run.
func New(ctx *pulumi.Context, args *Args, opts ...pulumi.ResourceOption) (*Result, error) {
	isHub := args.Mode == "hub"

	// Enable Shared VPC Host for the host project.
	hostName := fmt.Sprintf("org-net-spoke-%s-svpc-host", args.Code)
	if isHub {
		hostName = "org-net-hub-svpc-host"
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

	// Windows KMS route (conditional, matching upstream windows_activation_enabled).
	if args.WindowsActivationEnabled {
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
		// DNS forwarding zone (conditional, matching upstream).
		if len(args.TargetNameServers) > 0 {
			if err := createDNSForwardingZone(ctx, args, vpc); err != nil {
				return nil, err
			}
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
		if err := createDNSPeeringZone(ctx, args, vpc, opts...); err != nil {
			return nil, err
		}
	}

	// NAT routers (conditional, matching upstream nat_enabled default false).
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

		// Hub exports.
		ctx.Export("hub_network_name", vpc.VPC.Name)
		ctx.Export("hub_network_self_link", vpc.VPC.SelfLink)
		ctx.Export("dns_policy", dnsPolicy.ID())
	} else {
		if err := createSpokeServiceControl(ctx, args, vpc); err != nil {
			return nil, err
		}
	}

	return &Result{Networking: vpc, Firewall: fw}, nil
}

// createPeering wires bi-directional VPC peering (spoke <-> hub) and returns the
// hub-to-spoke peering, which downstream spoke resources serialise behind.
//
// Matching upstream: spoke does NOT export custom routes to hub, hub exports
// custom routes to spoke (via export_peer_custom_routes=true on the module).
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
		ExportCustomRoutes: pulumi.Bool(false), // Spoke does NOT export to hub (matching upstream)
		ImportCustomRoutes: pulumi.Bool(true),  // Import hub's custom routes
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

// createWindowsKmsRoute creates the conditional Windows KMS route.
func createWindowsKmsRoute(ctx *pulumi.Context, args *Args, vpc *networking.Networking) error {
	resourceName := fmt.Sprintf("%s-windows-kms", args.Mode)
	_, err := compute.NewRoute(ctx, resourceName, &compute.RouteArgs{
		Project:        args.ProjectID,
		Name:           pulumi.String(fmt.Sprintf("rt-%s-svpc-%s-1000-all-default-windows-kms", args.Code, args.Mode)),
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
