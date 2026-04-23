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

package networking

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/servicenetworking"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type SecondaryRangeArgs struct {
	RangeName string
	CIDR      string
}

type SubnetArgs struct {
	Name            string
	Region          string
	CIDR            string
	SecondaryRanges []SecondaryRangeArgs
	Role            string
	Purpose         string
	FlowLogs        bool
}

type NetworkingArgs struct {
	ProjectID                   pulumi.StringInput
	VPCName                     pulumi.StringInput
	Subnets                     []SubnetArgs
	EnablePSA                   bool
	DeleteDefaultRoutesOnCreate *bool
	RoutingMode                 string // "GLOBAL" or "REGIONAL"
}

type Networking struct {
	pulumi.ResourceState
	VPC     *compute.Network
	Subnets map[string]*compute.Subnetwork
}

func NewNetworking(ctx *pulumi.Context, name string, args *NetworkingArgs, opts ...pulumi.ResourceOption) (*Networking, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &Networking{
		Subnets: make(map[string]*compute.Subnetwork),
	}
	err := ctx.RegisterComponentResource("pkg:index:Networking", name, component, opts...)
	if err != nil {
		return nil, err
	}

	deleteRoutes := true
	if args.DeleteDefaultRoutesOnCreate != nil {
		deleteRoutes = *args.DeleteDefaultRoutesOnCreate
	}

	routingMode := "GLOBAL"
	if args.RoutingMode != "" {
		routingMode = args.RoutingMode
	}

	// 1. VPC
	vpc, err := compute.NewNetwork(ctx, name+"-vpc", &compute.NetworkArgs{
		Project:                     args.ProjectID,
		Name:                        args.VPCName,
		AutoCreateSubnetworks:       pulumi.Bool(false),
		DeleteDefaultRoutesOnCreate: pulumi.Bool(deleteRoutes),
		RoutingMode:                 pulumi.String(routingMode),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.VPC = vpc

	// 2. Subnets
	for _, s := range args.Subnets {
		subArgs := &compute.SubnetworkArgs{
			Project:               args.ProjectID,
			Name:                  pulumi.String(s.Name),
			Region:                pulumi.String(s.Region),
			Network:               vpc.ID(),
			IpCidrRange:           pulumi.String(s.CIDR),
			PrivateIpGoogleAccess: pulumi.Bool(true), // Standard for enterprise
		}

		if s.Purpose != "" {
			subArgs.Purpose = pulumi.String(s.Purpose)
		}
		if s.Role != "" {
			subArgs.Role = pulumi.String(s.Role)
		}

		if s.FlowLogs {
			subArgs.LogConfig = &compute.SubnetworkLogConfigArgs{
				AggregationInterval: pulumi.String("INTERVAL_5_SEC"),
				FlowSampling:        pulumi.Float64(0.5),
				Metadata:            pulumi.String("INCLUDE_ALL_METADATA"),
			}
		}

		if len(s.SecondaryRanges) > 0 {
			var secRanges []compute.SubnetworkSecondaryIpRangeInput
			for _, sr := range s.SecondaryRanges {
				secRanges = append(secRanges, &compute.SubnetworkSecondaryIpRangeArgs{
					RangeName:   pulumi.String(sr.RangeName),
					IpCidrRange: pulumi.String(sr.CIDR),
				})
			}
			subArgs.SecondaryIpRanges = compute.SubnetworkSecondaryIpRangeArray(secRanges)
		}

		sub, err := compute.NewSubnetwork(ctx, name+"-"+s.Name, subArgs, pulumi.Parent(vpc))
		if err != nil {
			return nil, err
		}
		component.Subnets[s.Name] = sub
	}

	// 3. Private Service Access
	if args.EnablePSA {
		reservedIP, err := compute.NewGlobalAddress(ctx, name+"-psa-ip", &compute.GlobalAddressArgs{
			Project:      args.ProjectID,
			Name:         pulumi.String(fmt.Sprintf("%s-psa-range", name)),
			Purpose:      pulumi.String("VPC_PEERING"),
			AddressType:  pulumi.String("INTERNAL"),
			PrefixLength: pulumi.Int(16),
			Network:      vpc.ID(),
		}, pulumi.Parent(vpc))
		if err != nil {
			return nil, err
		}

		_, err = servicenetworking.NewConnection(ctx, name+"-psa-conn", &servicenetworking.ConnectionArgs{
			Network:               vpc.ID(),
			Service:               pulumi.String("servicenetworking.googleapis.com"),
			ReservedPeeringRanges: pulumi.StringArray{reservedIP.Name},
		}, pulumi.Parent(vpc))
		if err != nil {
			return nil, err
		}
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"vpcId": vpc.ID(),
	})

	return component, nil
}
