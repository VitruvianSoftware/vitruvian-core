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

// Foundation stage 3 (networks, hub-and-spoke) — thin shared root for the hub
// network, mirroring upstream terraform-example-foundation
// 3-networks-hub-and-spoke/envs/shared. This leaf pins the shared identity
// (shared/c) and deploys the shared/global network resources: the central hub
// Shared VPC (with its DNS hub forwarding zone and BGP routers), the
// org/folder-level hierarchical firewall policy, and (when enabled) the
// transitivity appliance. The per-environment spoke VPCs live in the sibling
// envs/{development,nonproduction,production} leaves.
//
// Cross-stack peering serialization: GCP allows only one peering-mutating
// operation at a time per VPC. Within this stack the hub's PSA
// servicenetworking connection is the only mutation of the hub VPC's peering
// set; the spoke stacks' hub-to-spoke peerings only run after this stack has
// fully applied (deploy order shared → development → nonproduction →
// production, matching upstream's envs/shared-before-envs/<env> ordering).
// This preserves the PSA-before-peering serialization that the pre-split
// single-stack layout enforced with an explicit DependsOn on the hub
// PSAConnection. The spoke's own PSA-vs-peering serialization lives in
// modules/shared_vpc (createPeering).
package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Shared/hub identity pinned by this leaf project — upstream
// 3-networks-hub-and-spoke/envs/shared hardcodes the "shared" environment with
// the "c" (common) code in its main.tf; the leaf dir is the pin, not per-stack
// config.
const (
	pinnedEnv     = "shared"
	pinnedEnvCode = "c"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadNetSharedConfig(ctx)

		// Stack Reference to 1-org for project IDs and ACM policy (remote.go).
		orgStack, hubProjectID, err := lookupOrgRemote(ctx, cfg)
		if err != nil {
			return err
		}

		// Hub Shared VPC (net-hubs.go).
		hubRes, hubVpcName, err := deployNetHubs(ctx, cfg, orgStack, hubProjectID)
		if err != nil {
			return err
		}

		// Hierarchical Firewall Policy (org/folder level) — hub only
		// (hierarchical_firewall.go).
		if err := deployHierarchicalFirewall(ctx, cfg); err != nil {
			return err
		}

		// Transitivity Appliance — conditional, default false
		// (net-hubs-transitivity.go).
		if err := deployNetHubsTransitivity(ctx, cfg, hubProjectID, hubRes, hubVpcName); err != nil {
			return err
		}

		// Exports — see outputs.go (emitted by the shared_vpc module in hub
		// mode, matching upstream envs/shared/outputs.tf).
		return nil
	})
}
