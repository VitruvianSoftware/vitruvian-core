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

// Package cbprivatepool mirrors the upstream terraform-example-foundation
// 0-bootstrap/modules/cb-private-pool module: a Cloud Build private worker
// pool, optionally peered (via Private Service Access) to a VPC network that
// this module can create, and optionally connected to on-prem through HA VPN.
package cbprivatepool

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudbuild"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/dns"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/secretmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/servicenetworking"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const (
	// networkName mirrors upstream local.network_name.
	networkName = "vpc-b-cbpools"
)

// PrivateWorkerPoolConfig mirrors upstream var.private_worker_pool.
type PrivateWorkerPoolConfig struct {
	// Name of the worker pool. A name with a random suffix is generated if not set.
	Name string
	// Region of the private worker pool. Defaults to "us-central1".
	Region string
	// DiskSizeGb of the disk attached to the worker. Defaults to 100.
	DiskSizeGb int
	// MachineType of a worker. Defaults to "e2-medium".
	MachineType string
	// NoExternalIP creates workers without any public address when true.
	NoExternalIP bool
	// EnableNetworkPeering enables configuration of network peering for the
	// private worker pool.
	EnableNetworkPeering bool
	// CreatePeeredNetwork creates a network to establish the network peering.
	CreatePeeredNetwork bool
	// PeeredNetworkID is the ID of the existing network to configure peering
	// for when CreatePeeredNetwork is false. The project containing the
	// network must have the Service Networking API enabled.
	PeeredNetworkID string
	// PeeredNetworkSubnetIP is the IP range for the subnet created in the
	// peered network when CreatePeeredNetwork is true.
	PeeredNetworkSubnetIP string
	// PeeringAddress optionally reserves a specific peering address (or the
	// beginning of the range). Leave empty to let GCP choose a valid one.
	PeeringAddress string
	// PeeringPrefixLength is the prefix length of the IP peering range.
	// Defaults to 24.
	PeeringPrefixLength int
}

// VPNConfiguration mirrors upstream var.vpn_configuration (HA VPN to on-prem).
type VPNConfiguration struct {
	EnableVPN              bool
	OnPremPublicIPAddress0 string
	OnPremPublicIPAddress1 string
	// RouterASN defaults to 64515.
	RouterASN int
	// BGPPeerASN defaults to 64513.
	BGPPeerASN             int
	PSKSecretProjectID     string
	PSKSecretName          string
	Tunnel0BGPPeerAddress  string
	Tunnel0BGPSessionRange string
	Tunnel1BGPPeerAddress  string
	Tunnel1BGPSessionRange string
}

// VPCFlowLogsConfig mirrors upstream var.vpc_flow_logs.
type VPCFlowLogsConfig struct {
	// AggregationInterval defaults to "INTERVAL_5_SEC".
	AggregationInterval string
	// FlowSampling defaults to "0.5".
	FlowSampling string
	// Metadata defaults to "INCLUDE_ALL_METADATA".
	Metadata string
	// MetadataFields can only be specified when Metadata is CUSTOM_METADATA.
	MetadataFields []string
	// FilterExpr defaults to "true".
	FilterExpr string
}

// CbPrivatePoolArgs mirrors upstream variables.tf.
type CbPrivatePoolArgs struct {
	// ProjectID is the project where the private pool will be created.
	ProjectID pulumi.StringInput
	// PrivateWorkerPool mirrors var.private_worker_pool.
	PrivateWorkerPool PrivateWorkerPoolConfig
	// VPNConfiguration mirrors var.vpn_configuration.
	VPNConfiguration VPNConfiguration
	// VPCFlowLogs mirrors var.vpc_flow_logs.
	VPCFlowLogs VPCFlowLogsConfig
}

// CbPrivatePool is the component resource mirroring upstream
// 0-bootstrap/modules/cb-private-pool.
type CbPrivatePool struct {
	pulumi.ResourceState

	// PrivateWorkerPoolID mirrors upstream output "private_worker_pool_id".
	PrivateWorkerPoolID pulumi.StringOutput
	// WorkerRangeID mirrors upstream output "worker_range_id" ("" when
	// peering is disabled).
	WorkerRangeID pulumi.StringOutput
	// WorkerPeeredIPRange mirrors upstream output "worker_peered_ip_range".
	WorkerPeeredIPRange pulumi.StringOutput
	// PeeredNetworkID mirrors upstream output "peered_network_id".
	PeeredNetworkID pulumi.StringOutput
}

// NewCbPrivatePool provisions the Cloud Build private worker pool and its
// optional peered network / HA VPN, mirroring upstream main.tf, network.tf
// and vpn_ha.tf.
func NewCbPrivatePool(ctx *pulumi.Context, name string, args *CbPrivatePoolArgs, opts ...pulumi.ResourceOption) (*CbPrivatePool, error) {
	pw := args.PrivateWorkerPool
	vpn := args.VPNConfiguration
	fl := args.VPCFlowLogs

	// Defaults mirroring upstream optional() defaults.
	if pw.Region == "" {
		pw.Region = "us-central1"
	}
	if pw.DiskSizeGb == 0 {
		pw.DiskSizeGb = 100
	}
	if pw.MachineType == "" {
		pw.MachineType = "e2-medium"
	}
	if pw.PeeringPrefixLength == 0 {
		pw.PeeringPrefixLength = 24
	}
	if vpn.RouterASN == 0 {
		vpn.RouterASN = 64515
	}
	if vpn.BGPPeerASN == 0 {
		vpn.BGPPeerASN = 64513
	}
	if fl.AggregationInterval == "" {
		fl.AggregationInterval = "INTERVAL_5_SEC"
	}
	if fl.FlowSampling == "" {
		fl.FlowSampling = "0.5"
	}
	if fl.Metadata == "" {
		fl.Metadata = "INCLUDE_ALL_METADATA"
	}
	if fl.FilterExpr == "" {
		fl.FilterExpr = "true"
	}

	// Mirrors upstream var.private_worker_pool validation.
	if pw.EnableNetworkPeering &&
		!(pw.CreatePeeredNetwork && pw.PeeredNetworkSubnetIP != "") &&
		!(!pw.CreatePeeredNetwork && pw.PeeredNetworkID != "") {
		return nil, fmt.Errorf("if network peering is enabled, the peered network must be created by the module using the provided peered network subnet ip or a valid network ID is required")
	}
	// Mirrors upstream var.vpn_configuration validation.
	if vpn.EnableVPN &&
		(vpn.OnPremPublicIPAddress0 == "" || vpn.OnPremPublicIPAddress1 == "" ||
			vpn.PSKSecretProjectID == "" || vpn.PSKSecretName == "" ||
			vpn.Tunnel0BGPPeerAddress == "" || vpn.Tunnel0BGPSessionRange == "" ||
			vpn.Tunnel1BGPPeerAddress == "" || vpn.Tunnel1BGPSessionRange == "") {
		return nil, fmt.Errorf("if VPN configuration is enabled, all values are required")
	}

	var resource CbPrivatePool
	err := ctx.RegisterComponentResource("modules:cb-private-pool:CbPrivatePool", name, &resource, opts...)
	if err != nil {
		return nil, err
	}

	// Mirrors: random_string.suffix.
	suffix, err := random.NewRandomString(ctx, fmt.Sprintf("%s-suffix", name), &random.RandomStringArgs{
		Length:  pulumi.Int(4),
		Special: pulumi.Bool(false),
		Upper:   pulumi.Bool(false),
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	// Mirrors: local.private_pool_name.
	var poolName pulumi.StringInput
	if pw.Name != "" {
		poolName = pulumi.String(pw.Name)
	} else {
		poolName = pulumi.Sprintf("private-pool-%s", suffix.Result)
	}

	// ------------------------------------------------------------------
	// network.tf — optional peered network
	// ------------------------------------------------------------------
	var peeredNetworkID pulumi.StringInput = pulumi.String("")
	if pw.EnableNetworkPeering {
		if pw.PeeredNetworkID != "" {
			peeredNetworkID = pulumi.String(pw.PeeredNetworkID)
		} else {
			// Mirrors: module.peered_network (terraform-google-modules/network),
			// ported here as raw resources: a VPC without default internet
			// gateway routes plus one flow-logged, private-access subnet.
			flowSampling, parseErr := strconv.ParseFloat(fl.FlowSampling, 64)
			if parseErr != nil {
				return nil, fmt.Errorf("invalid vpc_flow_logs.flow_sampling %q: %w", fl.FlowSampling, parseErr)
			}
			network, err := compute.NewNetwork(ctx, fmt.Sprintf("%s-peered-network", name), &compute.NetworkArgs{
				Project:                     args.ProjectID,
				Name:                        pulumi.String(networkName),
				AutoCreateSubnetworks:       pulumi.Bool(false),
				DeleteDefaultRoutesOnCreate: pulumi.Bool(true),
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}
			metadataFields := pulumi.StringArray{}
			for _, f := range fl.MetadataFields {
				metadataFields = append(metadataFields, pulumi.String(f))
			}
			_, err = compute.NewSubnetwork(ctx, fmt.Sprintf("%s-peered-subnet", name), &compute.SubnetworkArgs{
				Project:               args.ProjectID,
				Name:                  pulumi.Sprintf("sb-b-cbpools-%s", pw.Region),
				Description:           pulumi.String("Peered subnet for Cloud Build private pool"),
				IpCidrRange:           pulumi.String(pw.PeeredNetworkSubnetIP),
				Region:                pulumi.String(pw.Region),
				Network:               network.ID(),
				PrivateIpGoogleAccess: pulumi.Bool(true),
				LogConfig: &compute.SubnetworkLogConfigArgs{
					AggregationInterval: pulumi.String(fl.AggregationInterval),
					FlowSampling:        pulumi.Float64(flowSampling),
					Metadata:            pulumi.String(fl.Metadata),
					MetadataFields:      metadataFields,
					FilterExpr:          pulumi.String(fl.FilterExpr),
				},
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}

			// Mirrors: google_dns_policy.default_policy.
			_, err = dns.NewPolicy(ctx, fmt.Sprintf("%s-default-policy", name), &dns.PolicyArgs{
				Project:                 args.ProjectID,
				Name:                    pulumi.String("dp-b-cbpools-default-policy"),
				EnableInboundForwarding: pulumi.Bool(true),
				EnableLogging:           pulumi.Bool(true),
				Networks: dns.PolicyNetworkArray{
					&dns.PolicyNetworkArgs{NetworkUrl: network.SelfLink},
				},
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}

			peeredNetworkID = network.ID()
		}
	}

	// Mirrors: local.peered_network_name — the network name segment of the ID.
	peeredNetworkName := pulumi.ToOutput(peeredNetworkID).ApplyT(func(id interface{}) string {
		s, _ := id.(string)
		parts := strings.Split(s, "/")
		for i, p := range parts {
			if p == "networks" && i+1 < len(parts) {
				return parts[i+1]
			}
		}
		return s
	}).(pulumi.StringOutput)

	peeredIPRange := pulumi.String("").ToStringOutput()
	workerRangeID := pulumi.String("").ToStringOutput()
	poolDependencies := []pulumi.Resource{}
	if pw.EnableNetworkPeering {
		// Mirrors: google_compute_global_address.worker_pool_range.
		addressArgs := &compute.GlobalAddressArgs{
			Project:      args.ProjectID,
			Name:         pulumi.String("ga-b-cbpools-worker-pool-range"),
			Purpose:      pulumi.String("VPC_PEERING"),
			AddressType:  pulumi.String("INTERNAL"),
			PrefixLength: pulumi.Int(pw.PeeringPrefixLength),
			Network:      peeredNetworkID,
		}
		if pw.PeeringAddress != "" {
			addressArgs.Address = pulumi.String(pw.PeeringAddress)
		}
		workerPoolRange, err := compute.NewGlobalAddress(ctx, fmt.Sprintf("%s-worker-pool-range", name), addressArgs, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}

		// Mirrors: local.peered_ip_range.
		peeredIPRange = pulumi.Sprintf("%s/%d", workerPoolRange.Address, workerPoolRange.PrefixLength)
		workerRangeID = workerPoolRange.ID().ToStringOutput().ApplyT(func(id string) string { return id }).(pulumi.StringOutput)

		// Mirrors: google_service_networking_connection.worker_pool_conn.
		// NOTE (cold-deploy): ordered after the reserved range via the
		// resource reference; the Service Networking API must already be
		// enabled on the project (upstream assumes the same).
		workerPoolConn, err := servicenetworking.NewConnection(ctx, fmt.Sprintf("%s-worker-pool-conn", name), &servicenetworking.ConnectionArgs{
			Network:               peeredNetworkID,
			Service:               pulumi.String("servicenetworking.googleapis.com"),
			ReservedPeeringRanges: pulumi.StringArray{workerPoolRange.Name},
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}

		// Mirrors: google_compute_network_peering_routes_config.peering_routes.
		_, err = compute.NewNetworkPeeringRoutesConfig(ctx, fmt.Sprintf("%s-peering-routes", name), &compute.NetworkPeeringRoutesConfigArgs{
			Project:            args.ProjectID,
			Peering:            workerPoolConn.Peering,
			Network:            peeredNetworkName,
			ImportCustomRoutes: pulumi.Bool(true),
			ExportCustomRoutes: pulumi.Bool(true),
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}

		// Mirrors: module.firewall_rules — allow ingress from the IPs
		// configured for service networking.
		_, err = compute.NewFirewall(ctx, fmt.Sprintf("%s-service-networking-fw", name), &compute.FirewallArgs{
			Project:     args.ProjectID,
			Name:        pulumi.String("fw-b-cbpools-100-i-a-all-all-all-service-networking"),
			Description: pulumi.String("allow ingres from the IPs configured for service networking"),
			Network:     peeredNetworkID,
			Direction:   pulumi.String("INGRESS"),
			Priority:    pulumi.Int(100),
			SourceRanges: pulumi.StringArray{
				peeredIPRange,
			},
			Allows: compute.FirewallAllowArray{
				&compute.FirewallAllowArgs{Protocol: pulumi.String("all")},
			},
			LogConfig: &compute.FirewallLogConfigArgs{
				Metadata: pulumi.String("INCLUDE_ALL_METADATA"),
			},
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}

		poolDependencies = append(poolDependencies, workerPoolRange, workerPoolConn)
	}

	// ------------------------------------------------------------------
	// main.tf — the Cloud Build private worker pool
	// ------------------------------------------------------------------
	workerPoolArgs := &cloudbuild.WorkerPoolArgs{
		Project:  args.ProjectID,
		Name:     poolName,
		Location: pulumi.String(pw.Region),
		WorkerConfig: &cloudbuild.WorkerPoolWorkerConfigArgs{
			DiskSizeGb:   pulumi.Int(pw.DiskSizeGb),
			MachineType:  pulumi.String(pw.MachineType),
			NoExternalIp: pulumi.Bool(pw.NoExternalIP),
		},
	}
	if pw.EnableNetworkPeering {
		workerPoolArgs.NetworkConfig = &cloudbuild.WorkerPoolNetworkConfigArgs{
			PeeredNetwork: peeredNetworkID,
		}
	}
	privatePool, err := cloudbuild.NewWorkerPool(ctx, fmt.Sprintf("%s-private-pool", name), workerPoolArgs,
		pulumi.Parent(&resource), pulumi.DependsOn(poolDependencies))
	if err != nil {
		return nil, err
	}

	// ------------------------------------------------------------------
	// vpn_ha.tf — optional HA VPN to on-prem
	// Ported from the terraform-google-modules/vpn//modules/vpn_ha wrapper as
	// raw resources: HA VPN gateway + external peer gateway (two-interface
	// redundancy) + BGP router with custom advertisement of the peered
	// private pool range + two IKEv2 tunnels with interfaces/peers.
	// ------------------------------------------------------------------
	if vpn.EnableVPN {
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
			Network: peeredNetworkID,
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
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
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}

		// Mirrors: router_advertise_config — CUSTOM mode advertising the
		// peered private pool IP range in addition to all subnets.
		router, err := compute.NewRouter(ctx, fmt.Sprintf("%s-vpn-router", name), &compute.RouterArgs{
			Project: args.ProjectID,
			Name:    pulumi.Sprintf("cr-%s", vpnName),
			Region:  pulumi.String(pw.Region),
			Network: peeredNetworkName,
			Bgp: &compute.RouterBgpArgs{
				Asn:              pulumi.Int(vpn.RouterASN),
				AdvertiseMode:    pulumi.String("CUSTOM"),
				AdvertisedGroups: pulumi.StringArray{pulumi.String("ALL_SUBNETS")},
				AdvertisedIpRanges: compute.RouterBgpAdvertisedIpRangeArray{
					&compute.RouterBgpAdvertisedIpRangeArgs{
						Range:       peeredIPRange,
						Description: pulumi.String("Peered private pool IP range."),
					},
				},
			},
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
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
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}

			routerInterface, err := compute.NewRouterInterface(ctx, fmt.Sprintf("%s-interface-remote-%d", name, i), &compute.RouterInterfaceArgs{
				Project:   args.ProjectID,
				Name:      pulumi.Sprintf("%s-interface-%d", vpnName, i),
				Region:    pulumi.String(pw.Region),
				Router:    router.Name,
				IpRange:   pulumi.String(t.bgpSessionRange),
				VpnTunnel: tunnel.Name,
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}

			_, err = compute.NewRouterPeer(ctx, fmt.Sprintf("%s-peer-remote-%d", name, i), &compute.RouterPeerArgs{
				Project:       args.ProjectID,
				Name:          pulumi.Sprintf("%s-peer-%d", vpnName, i),
				Region:        pulumi.String(pw.Region),
				Router:        router.Name,
				PeerIpAddress: pulumi.String(t.bgpPeerAddress),
				PeerAsn:       pulumi.Int(vpn.BGPPeerASN),
				Interface:     routerInterface.Name,
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}
		}
	}

	resource.PrivateWorkerPoolID = privatePool.ID().ToStringOutput().ApplyT(func(id string) string { return id }).(pulumi.StringOutput)
	resource.WorkerRangeID = workerRangeID
	resource.WorkerPeeredIPRange = peeredIPRange
	resource.PeeredNetworkID = pulumi.ToOutput(peeredNetworkID).ApplyT(func(id interface{}) string {
		s, _ := id.(string)
		return s
	}).(pulumi.StringOutput)

	return &resource, nil
}
