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

// Package networking provides Pulumi components for GCP networking.
//
// The DnsZone component matches the upstream
// terraform-google-modules/cloud-dns/google module.
// It supports private, peering, forwarding, public, reverse_lookup,
// and service_directory zone types.
package networking

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/dns"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// RecordSet defines a DNS record set for use with private zones.
type RecordSet struct {
	Name    string   // e.g. "*", "restricted", "" (apex)
	Type    string   // e.g. "A", "CNAME", "MX"
	TTL     int      // e.g. 300
	Records []string // e.g. ["10.0.0.1"] or ["restricted.googleapis.com."]
}

// DnsZoneArgs is the input for the DNS zone component.
// Supports: "private", "peering", "forwarding", "public", "reverse_lookup", "service_directory".
type DnsZoneArgs struct {
	ProjectID   pulumi.StringInput
	Name        string
	Domain      string
	Description string
	// Type: "private", "peering", "forwarding", "public", "reverse_lookup", "service_directory"
	Type            string
	NetworkSelfLink pulumi.StringInput
	// For peering zones
	TargetNetworkSelfLink pulumi.StringInput
	// For forwarding zones
	TargetNameServerAddresses []string
	ForwardingPath            string // "default" or "private" — upstream supports this
	// For private zones with records
	Recordsets []RecordSet
	// DNSSEC config (for public zones)
	EnableDnssec bool
	DnssecState  string // "on", "off", "transfer"
	// Labels
	Labels map[string]string
}

type DnsZone struct {
	pulumi.ResourceState
	ManagedZone *dns.ManagedZone
	RecordSets  []*dns.RecordSet
}

func NewDnsZone(ctx *pulumi.Context, name string, args *DnsZoneArgs, opts ...pulumi.ResourceOption) (*DnsZone, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &DnsZone{}
	err := ctx.RegisterComponentResource("pkg:index:DnsZone", name, component, opts...)
	if err != nil {
		return nil, err
	}

	description := args.Description
	if description == "" {
		description = "Private DNS zone"
	}

	// Base zone args
	zoneArgs := &dns.ManagedZoneArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String(args.Name),
		DnsName:     pulumi.String(args.Domain),
		Description: pulumi.String(description),
	}

	// Labels
	if len(args.Labels) > 0 {
		labels := pulumi.StringMap{}
		for k, v := range args.Labels {
			labels[k] = pulumi.String(v)
		}
		zoneArgs.Labels = labels
	}

	// Zone type determines visibility and config
	switch args.Type {
	case "private":
		zoneArgs.Visibility = pulumi.String("private")
		if args.NetworkSelfLink != nil {
			zoneArgs.PrivateVisibilityConfig = &dns.ManagedZonePrivateVisibilityConfigArgs{
				Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
					&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{
						NetworkUrl: args.NetworkSelfLink,
					},
				},
			}
		}

	case "forwarding":
		zoneArgs.Visibility = pulumi.String("private")
		if args.NetworkSelfLink != nil {
			zoneArgs.PrivateVisibilityConfig = &dns.ManagedZonePrivateVisibilityConfigArgs{
				Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
					&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{
						NetworkUrl: args.NetworkSelfLink,
					},
				},
			}
		}
		var servers dns.ManagedZoneForwardingConfigTargetNameServerArray
		for _, s := range args.TargetNameServerAddresses {
			serverArgs := &dns.ManagedZoneForwardingConfigTargetNameServerArgs{
				Ipv4Address: pulumi.String(s),
			}
			if args.ForwardingPath != "" {
				serverArgs.ForwardingPath = pulumi.String(args.ForwardingPath)
			}
			servers = append(servers, serverArgs)
		}
		zoneArgs.ForwardingConfig = &dns.ManagedZoneForwardingConfigArgs{
			TargetNameServers: servers,
		}

	case "peering":
		zoneArgs.Visibility = pulumi.String("private")
		if args.NetworkSelfLink != nil {
			zoneArgs.PrivateVisibilityConfig = &dns.ManagedZonePrivateVisibilityConfigArgs{
				Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
					&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{
						NetworkUrl: args.NetworkSelfLink,
					},
				},
			}
		}
		zoneArgs.PeeringConfig = &dns.ManagedZonePeeringConfigArgs{
			TargetNetwork: &dns.ManagedZonePeeringConfigTargetNetworkArgs{
				NetworkUrl: args.TargetNetworkSelfLink,
			},
		}

	case "public":
		zoneArgs.Visibility = pulumi.String("public")

	case "reverse_lookup":
		zoneArgs.Visibility = pulumi.String("private")
		if args.NetworkSelfLink != nil {
			zoneArgs.PrivateVisibilityConfig = &dns.ManagedZonePrivateVisibilityConfigArgs{
				Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
					&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{
						NetworkUrl: args.NetworkSelfLink,
					},
				},
			}
		}
		zoneArgs.ReverseLookup = pulumi.Bool(true)

	case "service_directory":
		zoneArgs.Visibility = pulumi.String("private")
		// Service directory zones require additional config — caller provides via NetworkSelfLink
		if args.NetworkSelfLink != nil {
			zoneArgs.PrivateVisibilityConfig = &dns.ManagedZonePrivateVisibilityConfigArgs{
				Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
					&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{
						NetworkUrl: args.NetworkSelfLink,
					},
				},
			}
		}
	}

	// DNSSEC (primarily for public zones)
	if args.EnableDnssec {
		state := "on"
		if args.DnssecState != "" {
			state = args.DnssecState
		}
		zoneArgs.DnssecConfig = &dns.ManagedZoneDnssecConfigArgs{
			State: pulumi.String(state),
		}
	}

	zone, err := dns.NewManagedZone(ctx, name, zoneArgs, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.ManagedZone = zone

	// Create record sets if provided (for private zones)
	for i, rs := range args.Recordsets {
		recordName := rs.Name
		if recordName == "" {
			recordName = args.Domain // apex — use the zone domain
		} else {
			recordName = fmt.Sprintf("%s.%s", rs.Name, args.Domain)
		}

		var rrdatas pulumi.StringArray
		for _, r := range rs.Records {
			rrdatas = append(rrdatas, pulumi.String(r))
		}

		ttl := rs.TTL
		if ttl == 0 {
			ttl = 300
		}

		record, err := dns.NewRecordSet(ctx, fmt.Sprintf("%s-rs-%d", name, i), &dns.RecordSetArgs{
			Project:     args.ProjectID,
			Name:        pulumi.String(recordName),
			ManagedZone: zone.Name,
			Type:        pulumi.String(rs.Type),
			Ttl:         pulumi.Int(ttl),
			Rrdatas:     rrdatas,
		}, pulumi.Parent(zone))
		if err != nil {
			return nil, err
		}
		component.RecordSets = append(component.RecordSets, record)
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"zoneName": zone.Name,
	})

	return component, nil
}
