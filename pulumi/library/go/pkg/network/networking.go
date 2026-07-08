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

package network

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/servicenetworking"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// splitCIDR splits a CIDR string like "10.16.56.0/21" into its network address
// ("10.16.56.0") and prefix length (21). Used to reserve an explicit Private
// Service Access range instead of auto-allocating one.
func splitCIDR(cidr string) (string, int, error) {
	addr, prefixStr, ok := strings.Cut(cidr, "/")
	if !ok {
		return "", 0, fmt.Errorf("missing prefix length")
	}
	prefix, err := strconv.Atoi(prefixStr)
	if err != nil {
		return "", 0, fmt.Errorf("invalid prefix length %q", prefixStr)
	}
	return addr, prefix, nil
}

type SecondaryRangeArgs struct {
	RangeName string
	CIDR      string
}

type SubnetArgs struct {
	Name             string
	Region           string
	CIDR             string
	SecondaryRanges  []SecondaryRangeArgs
	Role             string
	Purpose          string
	FlowLogs         bool
	FlowLogsInterval string
	FlowLogsSampling float64
	FlowLogsMetadata string
}

type NetworkingArgs struct {
	ProjectID pulumi.StringInput
	VPCName   pulumi.StringInput
	Subnets   []SubnetArgs
	EnablePSA bool
	// PrivateServiceCidr, when set (e.g. "10.16.56.0/21"), reserves that exact
	// CIDR for Private Service Access instead of auto-allocating a /16. Mirrors
	// the upstream per-environment private_service_cidr.
	PrivateServiceCidr          string
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
			Project:     args.ProjectID,
			Name:        pulumi.String(s.Name),
			Region:      pulumi.String(s.Region),
			Network:     vpc.ID(),
			IpCidrRange: pulumi.String(s.CIDR),
		}

		if s.Purpose != "REGIONAL_MANAGED_PROXY" {
			subArgs.PrivateIpGoogleAccess = pulumi.Bool(true) // Standard for enterprise
		}

		if s.Purpose != "" {
			subArgs.Purpose = pulumi.String(s.Purpose)
		}
		if s.Role != "" {
			subArgs.Role = pulumi.String(s.Role)
		}

		if s.FlowLogs {
			interval := "INTERVAL_5_SEC"
			if s.FlowLogsInterval != "" {
				interval = s.FlowLogsInterval
			}
			sampling := 0.5
			if s.FlowLogsSampling != 0 {
				sampling = s.FlowLogsSampling
			}
			metadata := "INCLUDE_ALL_METADATA"
			if s.FlowLogsMetadata != "" {
				metadata = s.FlowLogsMetadata
			}
			subArgs.LogConfig = &compute.SubnetworkLogConfigArgs{
				AggregationInterval: pulumi.String(interval),
				FlowSampling:        pulumi.Float64(sampling),
				Metadata:            pulumi.String(metadata),
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
		gaArgs := &compute.GlobalAddressArgs{
			Project:     args.ProjectID,
			Name:        pulumi.String(fmt.Sprintf("%s-psa-range", name)),
			Purpose:     pulumi.String("VPC_PEERING"),
			AddressType: pulumi.String("INTERNAL"),
			Network:     vpc.ID(),
		}
		// If an explicit private_service_cidr was supplied, reserve that exact
		// address+prefix (upstream fidelity); otherwise auto-allocate a /16.
		if args.PrivateServiceCidr != "" {
			addr, prefix, err := splitCIDR(args.PrivateServiceCidr)
			if err != nil {
				return nil, fmt.Errorf("invalid PrivateServiceCidr %q: %w", args.PrivateServiceCidr, err)
			}
			gaArgs.Address = pulumi.String(addr)
			gaArgs.PrefixLength = pulumi.Int(prefix)
		} else {
			gaArgs.PrefixLength = pulumi.Int(16)
		}
		reservedIP, err := compute.NewGlobalAddress(ctx, name+"-psa-ip", gaArgs, pulumi.Parent(vpc))
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
