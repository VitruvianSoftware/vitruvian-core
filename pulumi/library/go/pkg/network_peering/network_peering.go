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

// Package network_peering provides a VPC network peering component.
// Mirrors: terraform-google-modules/network/google//modules/network-peering
package network_peering

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type NetworkPeeringArgs struct {
	LocalNetwork                         pulumi.StringInput
	PeerNetwork                          pulumi.StringInput
	ExportCustomRoutes                   bool
	ImportCustomRoutes                   bool
	ExportSubnetRoutesWithPublicIp       bool
	ImportSubnetRoutesWithPublicIp       bool
	StackType                            string
}

type NetworkPeering struct {
	pulumi.ResourceState
	LocalPeering *compute.NetworkPeering
	PeerPeering  *compute.NetworkPeering
}

func NewNetworkPeering(ctx *pulumi.Context, name string, args *NetworkPeeringArgs, opts ...pulumi.ResourceOption) (*NetworkPeering, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &NetworkPeering{}
	err := ctx.RegisterComponentResource("pkg:index:NetworkPeering", name, component, opts...)
	if err != nil {
		return nil, err
	}

	stackType := args.StackType
	if stackType == "" {
		stackType = "IPV4_ONLY"
	}

	local, err := compute.NewNetworkPeering(ctx, name+"-local", &compute.NetworkPeeringArgs{
		Name:                             pulumi.String(fmt.Sprintf("%s-local", name)),
		Network:                          args.LocalNetwork,
		PeerNetwork:                      args.PeerNetwork,
		ExportCustomRoutes:               pulumi.Bool(args.ExportCustomRoutes),
		ImportCustomRoutes:               pulumi.Bool(args.ImportCustomRoutes),
		ExportSubnetRoutesWithPublicIp:   pulumi.Bool(args.ExportSubnetRoutesWithPublicIp),
		ImportSubnetRoutesWithPublicIp:   pulumi.Bool(args.ImportSubnetRoutesWithPublicIp),
		StackType:                        pulumi.String(stackType),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.LocalPeering = local

	peer, err := compute.NewNetworkPeering(ctx, name+"-peer", &compute.NetworkPeeringArgs{
		Name:                             pulumi.String(fmt.Sprintf("%s-peer", name)),
		Network:                          args.PeerNetwork,
		PeerNetwork:                      args.LocalNetwork,
		ExportCustomRoutes:               pulumi.Bool(args.ImportCustomRoutes),
		ImportCustomRoutes:               pulumi.Bool(args.ExportCustomRoutes),
		ExportSubnetRoutesWithPublicIp:   pulumi.Bool(args.ImportSubnetRoutesWithPublicIp),
		ImportSubnetRoutesWithPublicIp:   pulumi.Bool(args.ExportSubnetRoutesWithPublicIp),
		StackType:                        pulumi.String(stackType),
	}, pulumi.Parent(component), pulumi.DependsOn([]pulumi.Resource{local}))
	if err != nil {
		return nil, err
	}
	component.PeerPeering = peer

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}
