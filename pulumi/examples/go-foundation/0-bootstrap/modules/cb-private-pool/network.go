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

// Mirrors: 0-bootstrap/modules/cb-private-pool/network.tf in the TF
// foundation — the optional peered network for the private worker pool: the
// VPC + subnet + DNS policy, the reserved peering range, the Service
// Networking connection, peering routes and the service-networking firewall.

package cbprivatepool

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/dns"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/servicenetworking"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const (
	// networkName mirrors upstream local.network_name.
	networkName = "vpc-b-cbpools"
)

// networkResources carries the peering values produced by deployNetwork and
// consumed by the worker pool (main.go) and the HA VPN (vpn_ha.go).
type networkResources struct {
	peeredNetworkID   pulumi.StringInput
	peeredNetworkName pulumi.StringOutput
	peeredIPRange     pulumi.StringOutput
	workerRangeID     pulumi.StringOutput
	poolDependencies  []pulumi.Resource
}

// deployNetwork provisions the optional peered network and Private Service
// Access peering for the private worker pool, mirroring upstream network.tf.
func deployNetwork(ctx *pulumi.Context, name string, resource *CbPrivatePool, args *CbPrivatePoolArgs, pw PrivateWorkerPoolConfig, fl VPCFlowLogsConfig) (*networkResources, error) {
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
			}, pulumi.Parent(resource))
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
			}, pulumi.Parent(resource))
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
			}, pulumi.Parent(resource))
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
		workerPoolRange, err := compute.NewGlobalAddress(ctx, fmt.Sprintf("%s-worker-pool-range", name), addressArgs, pulumi.Parent(resource))
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
		}, pulumi.Parent(resource))
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
		}, pulumi.Parent(resource))
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
		}, pulumi.Parent(resource))
		if err != nil {
			return nil, err
		}

		poolDependencies = append(poolDependencies, workerPoolRange, workerPoolConn)
	}

	return &networkResources{
		peeredNetworkID:   peeredNetworkID,
		peeredNetworkName: peeredNetworkName,
		peeredIPRange:     peeredIPRange,
		workerRangeID:     workerRangeID,
		poolDependencies:  poolDependencies,
	}, nil
}
