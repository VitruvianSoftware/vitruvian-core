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

// Mirrors: 0-bootstrap/modules/cb-private-pool/vpn_ha.tf in the TF
// foundation — the optional HA VPN to on-prem. Ported from the
// terraform-google-modules/vpn//modules/vpn_ha wrapper as raw resources:
// HA VPN gateway + external peer gateway (two-interface redundancy) + BGP
// router with custom advertisement of the peered private pool range + two
// IKEv2 tunnels with interfaces/peers.

package cbprivatepool

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/secretmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployVPNHA provisions the optional HA VPN to on-prem, mirroring upstream
// vpn_ha.tf. It is a no-op when vpn.EnableVPN is false.
func deployVPNHA(ctx *pulumi.Context, name string, resource *CbPrivatePool, args *CbPrivatePoolArgs, pw PrivateWorkerPoolConfig, vpn VPNConfiguration, net *networkResources) error {
	if !vpn.EnableVPN {
		return nil
	}

	// Mirrors: data.google_secret_manager_secret_version.psk (chomp-ed).
	psk := secretmanager.LookupSecretVersionOutput(ctx, secretmanager.LookupSecretVersionOutputArgs{
		Project: pulumi.String(vpn.PSKSecretProjectID),
		Secret:  pulumi.String(vpn.PSKSecretName),
	}).SecretData().ApplyT(func(s string) string {
		return strings.TrimRight(s, "\n")
	}).(pulumi.StringOutput)

	vpnName := fmt.Sprintf("vpn-b-%s-cb-on-prem", pw.Region)

	haGateway, err := compute.NewHaVpnGateway(ctx, fmt.Sprintf("%s-ha-gateway", name), &compute.HaVpnGatewayArgs{
		Project: args.ProjectID,
		Name:    pulumi.String(vpnName),
		Region:  pulumi.String(pw.Region),
		Network: net.peeredNetworkID,
	}, pulumi.Parent(resource))
	if err != nil {
		return err
	}

	externalGateway, err := compute.NewExternalVpnGateway(ctx, fmt.Sprintf("%s-external-gateway", name), &compute.ExternalVpnGatewayArgs{
		Project:        args.ProjectID,
		Name:           pulumi.Sprintf("%s-external", vpnName),
		RedundancyType: pulumi.String("TWO_IPS_REDUNDANCY"),
		Interfaces: compute.ExternalVpnGatewayInterfaceArray{
			&compute.ExternalVpnGatewayInterfaceArgs{
				Id:        pulumi.Int(0),
				IpAddress: pulumi.String(vpn.OnPremPublicIPAddress0),
			},
			&compute.ExternalVpnGatewayInterfaceArgs{
				Id:        pulumi.Int(1),
				IpAddress: pulumi.String(vpn.OnPremPublicIPAddress1),
			},
		},
	}, pulumi.Parent(resource))
	if err != nil {
		return err
	}

	// Mirrors: router_advertise_config — CUSTOM mode advertising the
	// peered private pool IP range in addition to all subnets.
	router, err := compute.NewRouter(ctx, fmt.Sprintf("%s-vpn-router", name), &compute.RouterArgs{
		Project: args.ProjectID,
		Name:    pulumi.Sprintf("cr-%s", vpnName),
		Region:  pulumi.String(pw.Region),
		Network: net.peeredNetworkName,
		Bgp: &compute.RouterBgpArgs{
			Asn:              pulumi.Int(vpn.RouterASN),
			AdvertiseMode:    pulumi.String("CUSTOM"),
			AdvertisedGroups: pulumi.StringArray{pulumi.String("ALL_SUBNETS")},
			AdvertisedIpRanges: compute.RouterBgpAdvertisedIpRangeArray{
				&compute.RouterBgpAdvertisedIpRangeArgs{
					Range:       net.peeredIPRange,
					Description: pulumi.String("Peered private pool IP range."),
				},
			},
		},
	}, pulumi.Parent(resource))
	if err != nil {
		return err
	}

	tunnels := []struct {
		bgpPeerAddress   string
		bgpSessionRange  string
		gatewayInterface int
	}{
		{vpn.Tunnel0BGPPeerAddress, vpn.Tunnel0BGPSessionRange, 0},
		{vpn.Tunnel1BGPPeerAddress, vpn.Tunnel1BGPSessionRange, 1},
	}
	for i, t := range tunnels {
		tunnel, err := compute.NewVPNTunnel(ctx, fmt.Sprintf("%s-tunnel-remote-%d", name, i), &compute.VPNTunnelArgs{
			Project:                      args.ProjectID,
			Name:                         pulumi.Sprintf("%s-tunnel-%d", vpnName, i),
			Region:                       pulumi.String(pw.Region),
			VpnGateway:                   haGateway.ID(),
			PeerExternalGateway:          externalGateway.ID(),
			PeerExternalGatewayInterface: pulumi.Int(t.gatewayInterface),
			VpnGatewayInterface:          pulumi.Int(t.gatewayInterface),
			IkeVersion:                   pulumi.Int(2),
			Router:                       router.ID(),
			SharedSecret:                 psk,
		}, pulumi.Parent(resource))
		if err != nil {
			return err
		}

		routerInterface, err := compute.NewRouterInterface(ctx, fmt.Sprintf("%s-interface-remote-%d", name, i), &compute.RouterInterfaceArgs{
			Project:   args.ProjectID,
			Name:      pulumi.Sprintf("%s-interface-%d", vpnName, i),
			Region:    pulumi.String(pw.Region),
			Router:    router.Name,
			IpRange:   pulumi.String(t.bgpSessionRange),
			VpnTunnel: tunnel.Name,
		}, pulumi.Parent(resource))
		if err != nil {
			return err
		}

		_, err = compute.NewRouterPeer(ctx, fmt.Sprintf("%s-peer-remote-%d", name, i), &compute.RouterPeerArgs{
			Project:       args.ProjectID,
			Name:          pulumi.Sprintf("%s-peer-%d", vpnName, i),
			Region:        pulumi.String(pw.Region),
			Router:        router.Name,
			PeerIpAddress: pulumi.String(t.bgpPeerAddress),
			PeerAsn:       pulumi.Int(vpn.BGPPeerASN),
			Interface:     routerInterface.Name,
		}, pulumi.Parent(resource))
		if err != nil {
			return err
		}
	}

	return nil
}
