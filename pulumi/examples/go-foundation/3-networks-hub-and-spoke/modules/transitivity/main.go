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

// Package transitivity is the Pulumi port of upstream
// terraform-example-foundation 3-networks-hub-and-spoke/modules/transitivity.
// It deploys the hub transitivity appliance (ILB + MIG) plus the health-check
// firewall. It is gated off by default (enable_hub_and_spoke_transitivity=false)
// so the caller only invokes New when enabled.
package transitivity

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// New deploys the transitivity appliance and its health-check firewall. The
// appliance itself is the library component; the health-check firewall opens SSH
// from the Google health-check ranges to the transitivity ILBs.
func New(ctx *pulumi.Context, args *Args) error {
	_, err := networking.NewTransitivityAppliance(ctx, "transitivity", &networking.TransitivityApplianceArgs{
		ProjectID:   args.ProjectID,
		Regions:     []string{args.Region1, args.Region2},
		Network:     args.Network,
		NetworkName: args.NetworkName,
		Subnetworks: args.Subnetworks,
		RegionalAggregates: map[string][]string{
			args.Region1: {"10.0.0.0/16", "10.8.0.0/16", "100.64.0.0/18"},
			args.Region2: {"10.1.0.0/16", "10.9.0.0/16", "100.66.0.0/18"},
		},
		FirewallPolicy: args.FirewallPolicy,
	}, pulumi.DependsOn([]pulumi.Resource{args.VPC}))
	if err != nil {
		return err
	}

	// Health Check Firewall for Transitivity ILBs
	_, err = compute.NewFirewall(ctx, "fw-hub-allow-health-checks", &compute.FirewallArgs{
		Project: args.ProjectID,
		Name:    pulumi.String(fmt.Sprintf("fw-%s-hub-allow-health-checks", args.EnvCode)),
		Network: args.Network,
		Allows: compute.FirewallAllowArray{
			&compute.FirewallAllowArgs{
				Protocol: pulumi.String("tcp"),
				Ports:    pulumi.StringArray{pulumi.String("22")},
			},
		},
		SourceRanges: pulumi.StringArray{
			pulumi.String("130.211.0.0/22"),
			pulumi.String("35.191.0.0/16"),
		},
		TargetTags: pulumi.StringArray{
			pulumi.String("allow-transitivity"),
		},
	}, pulumi.DependsOn([]pulumi.Resource{args.VPC}))
	return err
}
