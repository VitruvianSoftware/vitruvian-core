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
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/dns"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type PrivateServiceConnectArgs struct {
	ProjectID                 pulumi.StringInput
	NetworkSelfLink           pulumi.StringInput
	DnsCode                   string
	IPAddress                 string
	ForwardingRuleTarget      string // "vpc-sc" or "all-apis"
	ServiceDirectoryNamespace string // Optional: SD namespace to register under
	ServiceDirectoryRegion    string // Optional: SD region (e.g. "us-central1")
	PscGlobalAccess           bool   // If true, PSC endpoint accessible from other regions
}

type PrivateServiceConnect struct {
	pulumi.ResourceState
	GlobalAddress  *compute.GlobalAddress
	ForwardingRule *compute.GlobalForwardingRule
	// DNS zones for googleapis, gcr.io, and pkg.dev
	GoogleapisZone *dns.ManagedZone
	GcrZone        *dns.ManagedZone
	PkgDevZone     *dns.ManagedZone
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

	// Determine the googleapis URL based on the forwarding rule target
	googleapisURL := "private.googleapis.com."
	if args.ForwardingRuleTarget == "vpc-sc" {
		googleapisURL = "restricted.googleapis.com."
	}
	recordsetsName := strings.Split(googleapisURL, ".")[0] // "restricted" or "private"

	dnsCode := args.DnsCode
	if dnsCode != "" {
		dnsCode = dnsCode + "-"
	}

	// 1. PSC Global Address with correct Purpose
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

	// 2. PSC Forwarding Rule
	fwdArgs := &compute.GlobalForwardingRuleArgs{
		Project:              args.ProjectID,
		Name:                 pulumi.String(fmt.Sprintf("%s-%s", name, args.ForwardingRuleTarget)),
		Target:               pulumi.String(args.ForwardingRuleTarget),
		Network:              args.NetworkSelfLink,
		IpAddress:            address.Address,
		LoadBalancingScheme:  pulumi.String(""),
		NoAutomateDnsZone:    pulumi.Bool(true),
		AllowPscGlobalAccess: pulumi.Bool(args.PscGlobalAccess),
	}

	// Service Directory registration (matches upstream dynamic block)
	if args.ServiceDirectoryNamespace != "" || args.ServiceDirectoryRegion != "" {
		sdArgs := &compute.GlobalForwardingRuleServiceDirectoryRegistrationsArgs{}
		if args.ServiceDirectoryNamespace != "" {
			sdArgs.Namespace = pulumi.String(args.ServiceDirectoryNamespace)
		}
		if args.ServiceDirectoryRegion != "" {
			sdArgs.ServiceDirectoryRegion = pulumi.String(args.ServiceDirectoryRegion)
		}
		fwdArgs.ServiceDirectoryRegistrations = sdArgs
	}

	rule, err := compute.NewGlobalForwardingRule(ctx, name+"-fwd", fwdArgs, pulumi.Parent(address))
	if err != nil {
		return nil, err
	}
	component.ForwardingRule = rule

	// 3. googleapis.com DNS Zone — CNAME wildcard + A record (matches upstream PSC module)
	apisZone, err := dns.NewManagedZone(ctx, name+"-apis-zone", &dns.ManagedZoneArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String(fmt.Sprintf("%sapis", dnsCode)),
		DnsName:     pulumi.String("googleapis.com."),
		Visibility:  pulumi.String("private"),
		Description: pulumi.String(fmt.Sprintf("Private DNS zone to configure %s", googleapisURL)),
		PrivateVisibilityConfig: &dns.ManagedZonePrivateVisibilityConfigArgs{
			Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
				&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{
					NetworkUrl: args.NetworkSelfLink,
				},
			},
		},
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.GoogleapisZone = apisZone

	// CNAME: *.googleapis.com → restricted.googleapis.com. (or private.googleapis.com.)
	_, err = dns.NewRecordSet(ctx, name+"-apis-cname", &dns.RecordSetArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String("*.googleapis.com."),
		ManagedZone: apisZone.Name,
		Type:        pulumi.String("CNAME"),
		Ttl:         pulumi.Int(300),
		Rrdatas:     pulumi.StringArray{pulumi.String(googleapisURL)},
	}, pulumi.Parent(apisZone))
	if err != nil {
		return nil, err
	}

	// A: restricted.googleapis.com → PSC IP
	_, err = dns.NewRecordSet(ctx, name+"-apis-a", &dns.RecordSetArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String(fmt.Sprintf("%s.googleapis.com.", recordsetsName)),
		ManagedZone: apisZone.Name,
		Type:        pulumi.String("A"),
		Ttl:         pulumi.Int(300),
		Rrdatas:     pulumi.StringArray{address.Address},
	}, pulumi.Parent(apisZone))
	if err != nil {
		return nil, err
	}

	// 4. gcr.io DNS Zone — CNAME wildcard + A apex
	gcrZone, err := dns.NewManagedZone(ctx, name+"-gcr-zone", &dns.ManagedZoneArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String(fmt.Sprintf("%sgcr", dnsCode)),
		DnsName:     pulumi.String("gcr.io."),
		Visibility:  pulumi.String("private"),
		Description: pulumi.String("Private DNS zone to configure gcr.io"),
		PrivateVisibilityConfig: &dns.ManagedZonePrivateVisibilityConfigArgs{
			Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
				&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{
					NetworkUrl: args.NetworkSelfLink,
				},
			},
		},
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.GcrZone = gcrZone

	_, err = dns.NewRecordSet(ctx, name+"-gcr-cname", &dns.RecordSetArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String("*.gcr.io."),
		ManagedZone: gcrZone.Name,
		Type:        pulumi.String("CNAME"),
		Ttl:         pulumi.Int(300),
		Rrdatas:     pulumi.StringArray{pulumi.String("gcr.io.")},
	}, pulumi.Parent(gcrZone))
	if err != nil {
		return nil, err
	}

	_, err = dns.NewRecordSet(ctx, name+"-gcr-a", &dns.RecordSetArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String("gcr.io."),
		ManagedZone: gcrZone.Name,
		Type:        pulumi.String("A"),
		Ttl:         pulumi.Int(300),
		Rrdatas:     pulumi.StringArray{address.Address},
	}, pulumi.Parent(gcrZone))
	if err != nil {
		return nil, err
	}

	// 5. pkg.dev DNS Zone — CNAME wildcard + A apex
	pkgDevZone, err := dns.NewManagedZone(ctx, name+"-pkg-zone", &dns.ManagedZoneArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String(fmt.Sprintf("%spkg-dev", dnsCode)),
		DnsName:     pulumi.String("pkg.dev."),
		Visibility:  pulumi.String("private"),
		Description: pulumi.String("Private DNS zone to configure pkg.dev"),
		PrivateVisibilityConfig: &dns.ManagedZonePrivateVisibilityConfigArgs{
			Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
				&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{
					NetworkUrl: args.NetworkSelfLink,
				},
			},
		},
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.PkgDevZone = pkgDevZone

	_, err = dns.NewRecordSet(ctx, name+"-pkg-cname", &dns.RecordSetArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String("*.pkg.dev."),
		ManagedZone: pkgDevZone.Name,
		Type:        pulumi.String("CNAME"),
		Ttl:         pulumi.Int(300),
		Rrdatas:     pulumi.StringArray{pulumi.String("pkg.dev.")},
	}, pulumi.Parent(pkgDevZone))
	if err != nil {
		return nil, err
	}

	_, err = dns.NewRecordSet(ctx, name+"-pkg-a", &dns.RecordSetArgs{
		Project:     args.ProjectID,
		Name:        pulumi.String("pkg.dev."),
		ManagedZone: pkgDevZone.Name,
		Type:        pulumi.String("A"),
		Ttl:         pulumi.Int(300),
		Rrdatas:     pulumi.StringArray{address.Address},
	}, pulumi.Parent(pkgDevZone))
	if err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"ipAddress":          address.Address,
		"forwardingRuleName": rule.Name,
	})

	return component, nil
}
