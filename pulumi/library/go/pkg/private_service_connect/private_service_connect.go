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

// Package private_service_connect provides a PSC endpoint component with
// DNS zone configuration for googleapis.com, gcr.io, and pkg.dev.
// Mirrors: terraform-google-modules/network/google//modules/private-service-connect
package private_service_connect

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/dns"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type PrivateServiceConnectArgs struct {
	ProjectID            pulumi.StringInput
	NetworkSelfLink      pulumi.StringInput
	DnsCode              string
	IPAddress            string
	ForwardingRuleTarget string // "vpc-sc" or "all-apis"
	PscGlobalAccess      bool
}

type PrivateServiceConnect struct {
	pulumi.ResourceState
	GlobalAddress  *compute.GlobalAddress
	ForwardingRule *compute.GlobalForwardingRule
}

func NewPrivateServiceConnect(ctx *pulumi.Context, name string, args *PrivateServiceConnectArgs, opts ...pulumi.ResourceOption) (*PrivateServiceConnect, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &PrivateServiceConnect{}
	err := ctx.RegisterComponentResource("pkg:index:PrivateServiceConnect", name, component, opts...)
	if err != nil {
		return nil, err
	}

	googleapisURL := "private.googleapis.com."
	if args.ForwardingRuleTarget == "vpc-sc" {
		googleapisURL = "restricted.googleapis.com."
	}
	recordsetsName := strings.Split(googleapisURL, ".")[0]

	dnsCode := args.DnsCode
	if dnsCode != "" {
		dnsCode = dnsCode + "-"
	}

	address, err := compute.NewGlobalAddress(ctx, name+"-ip", &compute.GlobalAddressArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String(fmt.Sprintf("%s-address", name)),
		AddressType: pulumi.String("INTERNAL"),
		Purpose:     pulumi.String("PRIVATE_SERVICE_CONNECT"),
		Network:     args.NetworkSelfLink,
		Address:     pulumi.String(args.IPAddress),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.GlobalAddress = address

	rule, err := compute.NewGlobalForwardingRule(ctx, name+"-fwd", &compute.GlobalForwardingRuleArgs{
		Project:              args.ProjectID,
		Name:                 pulumi.String(fmt.Sprintf("%s-%s", name, args.ForwardingRuleTarget)),
		Target:               pulumi.String(args.ForwardingRuleTarget),
		Network:              args.NetworkSelfLink,
		IpAddress:            address.Address,
		LoadBalancingScheme:  pulumi.String(""),
		NoAutomateDnsZone:    pulumi.Bool(true),
		AllowPscGlobalAccess: pulumi.Bool(args.PscGlobalAccess),
	}, pulumi.Parent(address))
	if err != nil {
		return nil, err
	}
	component.ForwardingRule = rule

	// Create DNS zones for googleapis, gcr.io, pkg.dev
	for _, zoneInfo := range []struct{ prefix, domain string }{
		{"apis", "googleapis.com."},
		{"gcr", "gcr.io."},
		{"pkg-dev", "pkg.dev."},
	} {
		zone, err := dns.NewManagedZone(ctx, fmt.Sprintf("%s-%s-zone", name, zoneInfo.prefix), &dns.ManagedZoneArgs{
			Project:     args.ProjectID,
			Name:        pulumi.String(fmt.Sprintf("%s%s", dnsCode, zoneInfo.prefix)),
			DnsName:     pulumi.String(zoneInfo.domain),
			Visibility:  pulumi.String("private"),
			Description: pulumi.String(fmt.Sprintf("Private DNS zone for %s", zoneInfo.domain)),
			PrivateVisibilityConfig: &dns.ManagedZonePrivateVisibilityConfigArgs{
				Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
					&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{NetworkUrl: args.NetworkSelfLink},
				},
			},
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}

		cnameTarget := zoneInfo.domain
		if zoneInfo.prefix == "apis" {
			cnameTarget = googleapisURL
		}

		_, err = dns.NewRecordSet(ctx, fmt.Sprintf("%s-%s-cname", name, zoneInfo.prefix), &dns.RecordSetArgs{
			Project: args.ProjectID, Name: pulumi.String("*." + zoneInfo.domain),
			ManagedZone: zone.Name, Type: pulumi.String("CNAME"), Ttl: pulumi.Int(300),
			Rrdatas: pulumi.StringArray{pulumi.String(cnameTarget)},
		}, pulumi.Parent(zone))
		if err != nil {
			return nil, err
		}

		aRecordName := zoneInfo.domain
		if zoneInfo.prefix == "apis" {
			aRecordName = fmt.Sprintf("%s.googleapis.com.", recordsetsName)
		}

		_, err = dns.NewRecordSet(ctx, fmt.Sprintf("%s-%s-a", name, zoneInfo.prefix), &dns.RecordSetArgs{
			Project: args.ProjectID, Name: pulumi.String(aRecordName),
			ManagedZone: zone.Name, Type: pulumi.String("A"), Ttl: pulumi.Int(300),
			Rrdatas: pulumi.StringArray{address.Address},
		}, pulumi.Parent(zone))
		if err != nil {
			return nil, err
		}
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{"ipAddress": address.Address})
	return component, nil
}
