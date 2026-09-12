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

// Package cloud_dns provides a reusable DnsZone component for creating
// Cloud DNS managed zones with support for private, peering, forwarding,
// public, reverse_lookup, and service_directory zone types.
// Mirrors: terraform-google-modules/cloud-dns/google
package cloud_dns

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/dns"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// RecordSet defines a DNS record set for use with private zones.
type RecordSet struct {
	Name    string
	Type    string
	TTL     int
	Records []string
}

// DnsZoneArgs is the input for the DNS zone component.
type DnsZoneArgs struct {
	ProjectID                 pulumi.StringInput
	Name                      string
	Domain                    string
	Description               string
	Type                      string // "private", "peering", "forwarding", "public", "reverse_lookup"
	NetworkSelfLink           pulumi.StringInput
	TargetNetworkSelfLink     pulumi.StringInput
	TargetNameServerAddresses []string
	ForwardingPath            string
	Recordsets                []RecordSet
	EnableDnssec              bool
	DnssecState               string
	Labels                    map[string]string
}

// DnsZone is a Pulumi ComponentResource that creates a GCP Cloud DNS managed zone.
type DnsZone struct {
	pulumi.ResourceState
	ManagedZone *dns.ManagedZone
	RecordSets  []*dns.RecordSet
}

// NewDnsZone creates a new Cloud DNS managed zone component.
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
		description = "Managed DNS zone"
	}

	zoneArgs := &dns.ManagedZoneArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String(args.Name),
		DnsName:     pulumi.String(args.Domain),
		Description: pulumi.String(description),
	}

	if len(args.Labels) > 0 {
		labels := pulumi.StringMap{}
		for k, v := range args.Labels {
			labels[k] = pulumi.String(v)
		}
		zoneArgs.Labels = labels
	}

	privateVisConfig := func() *dns.ManagedZonePrivateVisibilityConfigArgs {
		if args.NetworkSelfLink == nil {
			return nil
		}
		return &dns.ManagedZonePrivateVisibilityConfigArgs{
			Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
				&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{
					NetworkUrl: args.NetworkSelfLink,
				},
			},
		}
	}

	switch args.Type {
	case "private":
		zoneArgs.Visibility = pulumi.String("private")
		zoneArgs.PrivateVisibilityConfig = privateVisConfig()
	case "forwarding":
		zoneArgs.Visibility = pulumi.String("private")
		zoneArgs.PrivateVisibilityConfig = privateVisConfig()
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
		zoneArgs.PrivateVisibilityConfig = privateVisConfig()
		zoneArgs.PeeringConfig = &dns.ManagedZonePeeringConfigArgs{
			TargetNetwork: &dns.ManagedZonePeeringConfigTargetNetworkArgs{
				NetworkUrl: args.TargetNetworkSelfLink,
			},
		}
	case "public":
		zoneArgs.Visibility = pulumi.String("public")
	case "reverse_lookup":
		zoneArgs.Visibility = pulumi.String("private")
		zoneArgs.PrivateVisibilityConfig = privateVisConfig()
		zoneArgs.ReverseLookup = pulumi.Bool(true)
	}

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

	for i, rs := range args.Recordsets {
		recordName := rs.Name
		if recordName == "" {
			recordName = args.Domain
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
