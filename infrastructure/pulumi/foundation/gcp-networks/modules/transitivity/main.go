// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Package transitivity is the Pulumi port of upstream
// terraform-example-foundation 3-networks-hub-and-spoke/modules/transitivity.
// It deploys the hub transitivity appliance (ILB + MIG) plus the health-check
// firewall. It is GATED OFF by default (enable_hub_and_spoke_transitivity=false)
// so there is no live state today; the caller only invokes New when enabled.
package transitivity

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// New deploys the transitivity appliance and its health-check firewall. The
// appliance itself is the library component (already gated off); the
// health-check firewall opens SSH from the Google health-check ranges to the
// transitivity ILBs.
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
		Name:    pulumi.String("fw-c-hub-allow-health-checks"),
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
