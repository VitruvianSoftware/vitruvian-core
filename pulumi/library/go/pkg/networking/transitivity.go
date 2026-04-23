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
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// TransitivityApplianceArgs matches the upstream terraform-google-modules transitivity module.
// It deploys a MIG+ILB per region with dedicated service account and routes.
type TransitivityApplianceArgs struct {
	ProjectID          pulumi.StringInput
	Regions            []string
	Network            pulumi.StringInput
	NetworkName        string                        // short VPC name for naming
	Subnetworks        map[string]pulumi.StringInput // region -> subnetwork self_link
	RegionalAggregates map[string][]string           // region -> []CIDR
	FirewallPolicy     pulumi.StringInput            // firewall policy name for targeted rules
	TargetSize         int                           // instances per MIG (default 3)
}

type TransitivityAppliance struct {
	pulumi.ResourceState
	ServiceAccount *serviceaccount.Account
	ILBs           map[string]*compute.ForwardingRule
	Routes         []*compute.Route
}

func NewTransitivityAppliance(ctx *pulumi.Context, name string, args *TransitivityApplianceArgs, opts ...pulumi.ResourceOption) (*TransitivityAppliance, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &TransitivityAppliance{
		ILBs: make(map[string]*compute.ForwardingRule),
	}
	err := ctx.RegisterComponentResource("pkg:index:TransitivityAppliance", name, component, opts...)
	if err != nil {
		return nil, err
	}

	targetSize := 3
	if args.TargetSize > 0 {
		targetSize = args.TargetSize
	}

	// Flatten all aggregates for iptables rules
	var allAggregates []string
	for _, cidrs := range args.RegionalAggregates {
		allAggregates = append(allAggregates, cidrs...)
	}

	// Build iptables FORWARD rules: one per src/dst pair
	var iptablesRules []string
	for _, src := range allAggregates {
		for _, dst := range allAggregates {
			if src != dst {
				iptablesRules = append(iptablesRules, fmt.Sprintf("sudo iptables -A FORWARD -s %s -d %s -j ACCEPT", src, dst))
			}
		}
	}

	startupScript := fmt.Sprintf(`#!/bin/bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -A INPUT -p icmp -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -j DROP
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
%s
sudo iptables -A FORWARD -j DROP
sudo iptables -t nat -A POSTROUTING -j MASQUERADE
`, strings.Join(iptablesRules, "\n"))

	// 1. Dedicated Service Account
	sa, err := serviceaccount.NewAccount(ctx, name+"-sa", &serviceaccount.AccountArgs{
		Project:     args.ProjectID,
		AccountId:   pulumi.String("transitivity-gw"),
		DisplayName: pulumi.String("Transitivity Gateway Service Account"),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.ServiceAccount = sa

	// Grant logging + monitoring roles
	for _, role := range []string{"roles/logging.logWriter", "roles/monitoring.metricWriter"} {
		_, err = projects.NewIAMMember(ctx, fmt.Sprintf("%s-iam-%s", name, role), &projects.IAMMemberArgs{
			Project: args.ProjectID,
			Role:    pulumi.String(role),
			Member:  sa.Email.ApplyT(func(e string) string { return "serviceAccount:" + e }).(pulumi.StringOutput),
		}, pulumi.Parent(sa))
		if err != nil {
			return nil, err
		}
	}

	// 2. Health Check (TCP on port 22)
	hc, err := compute.NewHealthCheck(ctx, name+"-hc", &compute.HealthCheckArgs{
		Project: args.ProjectID,
		Name:    pulumi.String(fmt.Sprintf("%s-tcp-22", name)),
		TcpHealthCheck: &compute.HealthCheckTcpHealthCheckArgs{
			Port: pulumi.Int(22),
		},
		CheckIntervalSec:   pulumi.Int(5),
		HealthyThreshold:   pulumi.Int(4),
		TimeoutSec:         pulumi.Int(1),
		UnhealthyThreshold: pulumi.Int(5),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}

	// 3. Per-Region: Instance Template → MIG → Backend Service → ILB
	for _, region := range args.Regions {
		regionSuffix := region

		// Instance Template
		it, err := compute.NewInstanceTemplate(ctx, fmt.Sprintf("%s-it-%s", name, regionSuffix), &compute.InstanceTemplateArgs{
			Project:      args.ProjectID,
			NamePrefix:   pulumi.String(fmt.Sprintf("transitivity-gw-%s-", regionSuffix)),
			Region:       pulumi.String(region),
			MachineType:  pulumi.String("e2-micro"),
			CanIpForward: pulumi.Bool(true),
			Disks: compute.InstanceTemplateDiskArray{
				&compute.InstanceTemplateDiskArgs{
					SourceImage: pulumi.String("debian-cloud/debian-12"),
					DiskSizeGb:  pulumi.Int(10),
					Boot:        pulumi.Bool(true),
					AutoDelete:  pulumi.Bool(true),
				},
			},
			NetworkInterfaces: compute.InstanceTemplateNetworkInterfaceArray{
				&compute.InstanceTemplateNetworkInterfaceArgs{
					Network:    args.Network,
					Subnetwork: args.Subnetworks[region],
				},
			},
			ServiceAccount: &compute.InstanceTemplateServiceAccountArgs{
				Email:  sa.Email,
				Scopes: pulumi.StringArray{pulumi.String("cloud-platform")},
			},
			Metadata: pulumi.StringMap{
				"startup-script":         pulumi.String(startupScript),
				"block-project-ssh-keys": pulumi.String("true"),
			},
			Tags: pulumi.StringArray{pulumi.String(fmt.Sprintf("allow-%s", name))},
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}

		// MIG
		mig, err := compute.NewRegionInstanceGroupManager(ctx, fmt.Sprintf("%s-mig-%s", name, regionSuffix), &compute.RegionInstanceGroupManagerArgs{
			Project:          args.ProjectID,
			Name:             pulumi.String(fmt.Sprintf("%s-mig-%s", name, regionSuffix)),
			Region:           pulumi.String(region),
			BaseInstanceName: pulumi.String("transitivity-gw"),
			TargetSize:       pulumi.Int(targetSize),
			Versions: compute.RegionInstanceGroupManagerVersionArray{
				&compute.RegionInstanceGroupManagerVersionArgs{
					InstanceTemplate: it.SelfLinkUnique,
				},
			},
			UpdatePolicy: &compute.RegionInstanceGroupManagerUpdatePolicyArgs{
				Type:                        pulumi.String("OPPORTUNISTIC"),
				MinimalAction:               pulumi.String("RESTART"),
				MaxSurgeFixed:               pulumi.Int(4),
				MaxUnavailableFixed:         pulumi.Int(4),
				InstanceRedistributionType:  pulumi.String("NONE"),
				ReplacementMethod:           pulumi.String("SUBSTITUTE"),
				MostDisruptiveAllowedAction: pulumi.String("REPLACE"),
			},
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}

		// Backend Service for ILB
		bs, err := compute.NewRegionBackendService(ctx, fmt.Sprintf("%s-bs-%s", name, regionSuffix), &compute.RegionBackendServiceArgs{
			Project:             args.ProjectID,
			Name:                pulumi.String(fmt.Sprintf("%s-%s", name, regionSuffix)),
			Region:              pulumi.String(region),
			Protocol:            pulumi.String("TCP"),
			LoadBalancingScheme: pulumi.String("INTERNAL"),
			HealthChecks:        hc.SelfLink,
			Backends: compute.RegionBackendServiceBackendArray{
				&compute.RegionBackendServiceBackendArgs{
					Group: mig.InstanceGroup,
				},
			},
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}

		// ILB Forwarding Rule
		ilb, err := compute.NewForwardingRule(ctx, fmt.Sprintf("%s-ilb-%s", name, regionSuffix), &compute.ForwardingRuleArgs{
			Project:             args.ProjectID,
			Name:                pulumi.String(regionSuffix),
			Region:              pulumi.String(region),
			LoadBalancingScheme: pulumi.String("INTERNAL"),
			BackendService:      bs.SelfLink,
			AllPorts:            pulumi.Bool(true),
			Network:             args.Network,
			Subnetwork:          args.Subnetworks[region],
			AllowGlobalAccess:   pulumi.Bool(true),
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}
		component.ILBs[region] = ilb

		// Routes: next_hop_ilb for each aggregate in this region
		for _, cidr := range args.RegionalAggregates[region] {
			routeName := fmt.Sprintf("ilb-%s-%s", region, strings.NewReplacer("/", "-", ".", "-").Replace(cidr))
			route, err := compute.NewRoute(ctx, fmt.Sprintf("%s-rt-%s", name, routeName), &compute.RouteArgs{
				Project:    args.ProjectID,
				Network:    args.Network,
				Name:       pulumi.String(routeName),
				DestRange:  pulumi.String(cidr),
				NextHopIlb: ilb.SelfLink,
			}, pulumi.Parent(component))
			if err != nil {
				return nil, err
			}
			component.Routes = append(component.Routes, route)
		}
	}

	// 4. Targeted firewall policy rules for the transitivity appliance
	if args.FirewallPolicy != nil {
		strippedVpc := strings.TrimPrefix(args.NetworkName, "vpc-")
		flatAggregates := pulumi.ToStringArray(allAggregates)

		_, err = compute.NewNetworkFirewallPolicyRule(ctx, name+"-fw-ingress", &compute.NetworkFirewallPolicyRuleArgs{
			Project:               args.ProjectID,
			FirewallPolicy:        args.FirewallPolicy,
			Priority:              pulumi.Int(20000),
			Direction:             pulumi.String("INGRESS"),
			Action:                pulumi.String("allow"),
			RuleName:              pulumi.String(fmt.Sprintf("fw-%s-20000-i-a-all-all-all-transitivity", strippedVpc)),
			TargetServiceAccounts: pulumi.StringArray{sa.Email},
			Description:           pulumi.String("Allow ingress from regional IP ranges."),
			Match: &compute.NetworkFirewallPolicyRuleMatchArgs{
				SrcIpRanges: flatAggregates,
				Layer4Configs: compute.NetworkFirewallPolicyRuleMatchLayer4ConfigArray{
					&compute.NetworkFirewallPolicyRuleMatchLayer4ConfigArgs{
						IpProtocol: pulumi.String("all"),
					},
				},
			},
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}

		_, err = compute.NewNetworkFirewallPolicyRule(ctx, name+"-fw-egress", &compute.NetworkFirewallPolicyRuleArgs{
			Project:               args.ProjectID,
			FirewallPolicy:        args.FirewallPolicy,
			Priority:              pulumi.Int(20001),
			Direction:             pulumi.String("EGRESS"),
			Action:                pulumi.String("allow"),
			RuleName:              pulumi.String(fmt.Sprintf("fw-%s-20001-e-a-all-all-all-transitivity", strippedVpc)),
			TargetServiceAccounts: pulumi.StringArray{sa.Email},
			Description:           pulumi.String("Allow egress from regional IP ranges."),
			Match: &compute.NetworkFirewallPolicyRuleMatchArgs{
				DestIpRanges: flatAggregates,
				Layer4Configs: compute.NetworkFirewallPolicyRuleMatchLayer4ConfigArray{
					&compute.NetworkFirewallPolicyRuleMatchLayer4ConfigArgs{
						IpProtocol: pulumi.String("all"),
					},
				},
			},
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"serviceAccountEmail": sa.Email,
	})

	return component, nil
}
