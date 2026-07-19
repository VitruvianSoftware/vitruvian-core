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

// Package base_env is the per-environment project orchestrator, the Pulumi port
// of upstream terraform-example-foundation 4-projects/modules/base_env. It
// creates the business-unit project set (SVPC-attached, floating, oss-floating,
// peering) plus their attached infrastructure (Shared-VPC attach, VPC-SC
// perimeter attach, CMEK storage, peering network + firewall) and — via a
// separate exported entrypoint — the Confidential Space project.
//
// File layout mirrors the upstream module's per-concern split: variables.go
// (variables.tf), outputs.go (outputs.tf), example_shared_vpc_project.go,
// example_floating_project.go, example_peering_project.go,
// example_storage_cmek.go, example_confidential_space_project.go. This file
// holds the New orchestrator (Go needs an explicit call graph where Terraform
// is declarative). Upstream's business_unit_folder.tf has no analogue here:
// our port creates the BU folder in each business_unit_1/{env} leaf, and the
// remote.tf reads live in the leaves' remote.go (the leaves pass resolved
// outputs in via Args).
//
// Each project is created through single_project.New, whose logical names are
// passed through unchanged so this is a pure structural extraction of the former
// inline root code with a byte-identical resource graph.
package base_env

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// New creates three project types per BU/env, matching the Terraform
// foundation's project factory pattern:
//   - SVPC-attached: connected to the Shared VPC host project w/ VPC-SC
//   - Floating: standalone project, not attached to any VPC
//   - Peering: project with its own VPC peered to the host network
func New(ctx *pulumi.Context, args *Args) (*BUProjects, error) {
	result := &BUProjects{}

	// Default every StringOutput to an empty string so exports remain well-typed
	// when a project type is disabled.
	emptyStr := pulumi.String("").ToStringOutput()
	result.SVPCProjectID = emptyStr
	result.SVPCProjectNumber = emptyStr
	result.FloatingProjectID = emptyStr
	result.OSSFloatingProjectID = emptyStr
	result.OSSFloatingProjectNumber = emptyStr
	result.PeeringProjectID = emptyStr
	result.PeeringNetworkSelfLink = emptyStr
	result.PeeringSubnetSelfLink = emptyStr
	result.IAPFirewallTags = pulumi.Map{}.ToMapOutput()

	// 1. SVPC-attached Project — example_shared_vpc_project.go (CMEK storage
	// hangs off it, example_storage_cmek.go).
	if err := deploySharedVPCProject(ctx, args, result); err != nil {
		return nil, err
	}

	// 2. Floating Project (+ the monorepo's OSS floating project) —
	// example_floating_project.go.
	if err := deployFloatingProject(ctx, args, result); err != nil {
		return nil, err
	}

	// 3. Peering Project + network — example_peering_project.go.
	if err := deployPeeringProject(ctx, args, result); err != nil {
		return nil, err
	}

	// Populate TF-parity outputs
	//
	// TODO(shared-VPC enablement): upstream's `subnets_self_links` output is the
	// SHARED-VPC HOST's subnets (local.subnets_self_links, from the 3-networks
	// remote state), consumed by 5-app-infra to place service-project resources.
	// We currently export the PEERING project's subnet here — the wrong network
	// (the peering subnet already has its own `peering_subnetwork_self_link`
	// export). When shared-VPC projects are enabled, read `subnets_self_links` from
	// the gcp-networks stack (it exports exactly that) and export that instead.
	if args.PeeringProjectEnabled && args.PeeringEnabled {
		result.SubnetsSelfLinks = pulumi.StringArray{result.PeeringSubnetSelfLink}.ToStringArrayOutput()
		result.PeeringComplete = pulumi.Bool(true).ToBoolOutput()
	} else {
		result.SubnetsSelfLinks = pulumi.ToStringArray([]string{}).ToStringArrayOutput()
		result.PeeringComplete = pulumi.Bool(false).ToBoolOutput()
	}
	result.VPCSCPerimeterName = args.PerimeterName
	result.AccessContextManagerPolicyID = args.ACMPolicyID

	return result, nil
}
