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

// Package cloud_router provides a reusable CloudRouter component for creating
// Cloud Routers with optional BGP configuration and Cloud NAT.
// Mirrors: terraform-google-modules/cloud-router/google
package cloud_router

import (
	"fmt"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// AdvertisedIPRange defines a custom IP range to advertise via BGP.
type AdvertisedIPRange struct {
	Range       string
	Description string
}

// CloudRouterArgs defines the arguments for creating a CloudRouter component.
type CloudRouterArgs struct {
	ProjectID          pulumi.StringInput
	Region             string
	Network            pulumi.StringInput
	BgpAsn             int
	Description        string
	AdvertisedGroups   []string
	AdvertisedIpRanges []AdvertisedIPRange
	KeepaliveInterval  int
	EnableNat          bool
	NatNumAddresses    int
}

// CloudRouter is a Pulumi ComponentResource that creates a GCP Cloud Router
// with optional NAT and BGP advertisement configuration.
type CloudRouter struct {
	pulumi.ResourceState
	Router    *compute.Router
	Addresses []*compute.Address
	NAT       *compute.RouterNat
}

// NewCloudRouter creates a new CloudRouter component resource.
func NewCloudRouter(ctx *pulumi.Context, name string, args *CloudRouterArgs, opts ...pulumi.ResourceOption) (*CloudRouter, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &CloudRouter{}
	err := ctx.RegisterComponentResource("pkg:index:CloudRouter", name, component, opts...)
	if err != nil {
		return nil, err
	}

	bgpArgs := &compute.RouterBgpArgs{
		Asn: pulumi.Int(args.BgpAsn),
	}

	if len(args.AdvertisedGroups) > 0 || len(args.AdvertisedIpRanges) > 0 {
		bgpArgs.AdvertiseMode = pulumi.String("CUSTOM")
	}

	if args.KeepaliveInterval > 0 {
		bgpArgs.KeepaliveInterval = pulumi.Int(args.KeepaliveInterval)
	}

	if len(args.AdvertisedGroups) > 0 {
		var groups pulumi.StringArray
		for _, g := range args.AdvertisedGroups {
			groups = append(groups, pulumi.String(g))
		}
		bgpArgs.AdvertisedGroups = groups
	}

	if len(args.AdvertisedIpRanges) > 0 {
		var ranges compute.RouterBgpAdvertisedIpRangeArray
		for _, r := range args.AdvertisedIpRanges {
			ranges = append(ranges, &compute.RouterBgpAdvertisedIpRangeArgs{
				Range:       pulumi.String(r.Range),
				Description: pulumi.String(r.Description),
			})
		}
		bgpArgs.AdvertisedIpRanges = ranges
	}

	router, err := compute.NewRouter(ctx, name, &compute.RouterArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String(name),
		Region:      pulumi.String(args.Region),
		Network:     args.Network,
		Description: pulumi.String(args.Description),
		Bgp:         bgpArgs,
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Router = router

	if args.EnableNat {
		var natIPs pulumi.StringArray
		for i := 0; i < args.NatNumAddresses; i++ {
			addr, err := compute.NewAddress(ctx, fmt.Sprintf("%s-ip-%d", name, i), &compute.AddressArgs{
				Project: args.ProjectID,
				Name:    pulumi.String(fmt.Sprintf("%s-ip-%d", name, i)),
				Region:  pulumi.String(args.Region),
			}, pulumi.Parent(router))
			if err != nil {
				return nil, err
			}
			component.Addresses = append(component.Addresses, addr)
			natIPs = append(natIPs, addr.SelfLink)
		}

		natAllocOption := "AUTO_ONLY"
		if len(natIPs) > 0 {
			natAllocOption = "MANUAL_ONLY"
		}

		nat, err := compute.NewRouterNat(ctx, fmt.Sprintf("%s-nat", name), &compute.RouterNatArgs{
			Project:                       args.ProjectID,
			Router:                        router.Name,
			Region:                        pulumi.String(args.Region),
			Name:                          pulumi.String(fmt.Sprintf("%s-egress", name)),
			NatIpAllocateOption:           pulumi.String(natAllocOption),
			NatIps:                        natIPs,
			SourceSubnetworkIpRangesToNat: pulumi.String("ALL_SUBNETWORKS_ALL_IP_RANGES"),
			LogConfig: &compute.RouterNatLogConfigArgs{
				Enable: pulumi.Bool(true),
				Filter: pulumi.String("TRANSLATIONS_ONLY"),
			},
		}, pulumi.Parent(router))
		if err != nil {
			return nil, err
		}
		component.NAT = nat
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"routerName": router.Name,
	})

	return component, nil
}
