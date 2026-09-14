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
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type VpnHaTunnelConfig struct {
	BgpSessionRange     string
	PeerBgpSessionRange string
	PeerAsn             int
	SharedSecret        string
	VpnGatewayInterface int
	IkeVersion          *int
}

type RouterAdvertiseConfig struct {
	Mode     *string
	Groups   []string
	IpRanges []RouterAdvertiseIpRange
}

type RouterAdvertiseIpRange struct {
	Range       string
	Description *string
}

type VpnHaArgs struct {
	ProjectID             pulumi.StringInput
	Region                pulumi.StringInput
	Network               pulumi.StringInput
	Name                  string
	RouterAsn             int
	RouterAdvertiseConfig *RouterAdvertiseConfig
	PeerGcpGateway        pulumi.StringPtrInput
	PeerExternalGateway   *ExternalVpnGatewayConfig
	Tunnels               []VpnHaTunnelConfig
}

type ExternalVpnGatewayConfig struct {
	Name           string
	RedundancyType *string
	Interfaces     []ExternalVpnGatewayInterface
}

type ExternalVpnGatewayInterface struct {
	Id        int
	IpAddress string
}

type VpnHa struct {
	pulumi.ResourceState
	Gateway *compute.HaVpnGateway
	Router  *compute.Router
}

func NewVpnHa(ctx *pulumi.Context, name string, args *VpnHaArgs, opts ...pulumi.ResourceOption) (*VpnHa, error) {
	component := &VpnHa{}
	err := ctx.RegisterComponentResource("pkg:index:VpnHa", name, component, opts...)
	if err != nil {
		return nil, err
	}

	gateway, err := compute.NewHaVpnGateway(ctx, fmt.Sprintf("%s-gateway", name), &compute.HaVpnGatewayArgs{
		Name:    pulumi.String(args.Name),
		Project: args.ProjectID,
		Region:  args.Region,
		Network: args.Network,
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Gateway = gateway

	var bgpConfig *compute.RouterBgpArgs
	if args.RouterAsn != 0 || args.RouterAdvertiseConfig != nil {
		bgpConfig = &compute.RouterBgpArgs{
			Asn: pulumi.Int(args.RouterAsn),
		}
		if args.RouterAdvertiseConfig != nil {
			if args.RouterAdvertiseConfig.Mode != nil {
				bgpConfig.AdvertiseMode = pulumi.String(*args.RouterAdvertiseConfig.Mode)
			}
			if len(args.RouterAdvertiseConfig.Groups) > 0 {
				groups := pulumi.StringArray{}
				for _, g := range args.RouterAdvertiseConfig.Groups {
					groups = append(groups, pulumi.String(g))
				}
				bgpConfig.AdvertisedGroups = groups
			}
			if len(args.RouterAdvertiseConfig.IpRanges) > 0 {
				var ranges compute.RouterBgpAdvertisedIpRangeArray
				for _, r := range args.RouterAdvertiseConfig.IpRanges {
					var desc pulumi.StringPtrInput
					if r.Description != nil {
						desc = pulumi.String(*r.Description)
					}
					ranges = append(ranges, &compute.RouterBgpAdvertisedIpRangeArgs{
						Range:       pulumi.String(r.Range),
						Description: desc,
					})
				}
				bgpConfig.AdvertisedIpRanges = ranges
			}
		}
	}

	router, err := compute.NewRouter(ctx, fmt.Sprintf("%s-router", name), &compute.RouterArgs{
		Name:    pulumi.String(fmt.Sprintf("cr-%s", args.Name)),
		Project: args.ProjectID,
		Region:  args.Region,
		Network: args.Network,
		Bgp:     bgpConfig,
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Router = router

	var peerExternalGateway *compute.ExternalVpnGateway
	if args.PeerExternalGateway != nil {
		redundancy := "TWO_IPS_REDUNDANCY"
		if args.PeerExternalGateway.RedundancyType != nil {
			redundancy = *args.PeerExternalGateway.RedundancyType
		}

		var interfaces compute.ExternalVpnGatewayInterfaceArray
		for _, i := range args.PeerExternalGateway.Interfaces {
			interfaces = append(interfaces, &compute.ExternalVpnGatewayInterfaceArgs{
				Id:        pulumi.Int(i.Id),
				IpAddress: pulumi.String(i.IpAddress),
			})
		}

		gw, err := compute.NewExternalVpnGateway(ctx, fmt.Sprintf("%s-peer-gw", name), &compute.ExternalVpnGatewayArgs{
			Name:           pulumi.String(args.PeerExternalGateway.Name),
			Project:        args.ProjectID,
			RedundancyType: pulumi.String(redundancy),
			Interfaces:     interfaces,
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}
		peerExternalGateway = gw
	}

	for i, tCfg := range args.Tunnels {
		ikeVersion := 2
		if tCfg.IkeVersion != nil {
			ikeVersion = *tCfg.IkeVersion
		}

		tunnelArgs := &compute.VPNTunnelArgs{
			Name:                pulumi.String(fmt.Sprintf("%s-tunnel-%d", args.Name, i)),
			Project:             args.ProjectID,
			Region:              args.Region,
			VpnGateway:          gateway.ID(),
			VpnGatewayInterface: pulumi.Int(tCfg.VpnGatewayInterface),
			SharedSecret:        pulumi.String(tCfg.SharedSecret),
			Router:              router.ID(),
			IkeVersion:          pulumi.Int(ikeVersion),
		}

		if args.PeerGcpGateway != nil {
			tunnelArgs.PeerGcpGateway = args.PeerGcpGateway
		} else if peerExternalGateway != nil {
			tunnelArgs.PeerExternalGateway = peerExternalGateway.ID()
			tunnelArgs.PeerExternalGatewayInterface = pulumi.Int(tCfg.VpnGatewayInterface)
		}

		tunnel, err := compute.NewVPNTunnel(ctx, fmt.Sprintf("%s-tunnel-%d", name, i), tunnelArgs, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}

		iface, err := compute.NewRouterInterface(ctx, fmt.Sprintf("%s-iface-%d", name, i), &compute.RouterInterfaceArgs{
			Name:      pulumi.String(fmt.Sprintf("%s-iface-%d", args.Name, i)),
			Project:   args.ProjectID,
			Region:    args.Region,
			Router:    router.Name,
			IpRange:   pulumi.String(tCfg.BgpSessionRange),
			VpnTunnel: tunnel.Name,
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}

		peerIp := strings.Split(tCfg.PeerBgpSessionRange, "/")[0]
		_, err = compute.NewRouterPeer(ctx, fmt.Sprintf("%s-peer-%d", name, i), &compute.RouterPeerArgs{
			Name:          pulumi.String(fmt.Sprintf("%s-peer-%d", args.Name, i)),
			Project:       args.ProjectID,
			Region:        args.Region,
			Router:        router.Name,
			PeerAsn:       pulumi.Int(tCfg.PeerAsn),
			PeerIpAddress: pulumi.String(peerIp),
			Interface:     iface.Name,
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"gatewayId": gateway.ID(),
		"routerId":  router.ID(),
	})

	return component, nil
}
