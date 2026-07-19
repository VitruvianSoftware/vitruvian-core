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

// Foundation stage 3 (networks, hub-and-spoke) — thin shared root for the hub
// network, mirroring upstream terraform-example-foundation
// 3-networks-hub-and-spoke/envs/shared. This leaf pins the shared identity
// (shared/c) and deploys the shared/global network resources: the central hub
// Shared VPC (with its DNS hub forwarding zone and BGP routers, net-hubs.go),
// the org/folder-level hierarchical firewall policy
// (hierarchical_firewall.go), and (when enabled) the transitivity appliance
// (net-hubs-transitivity.go). The per-environment spoke VPCs live in the
// sibling envs/{development,nonproduction,production} leaves.
//
// Cross-stack peering serialization: GCP allows only one peering-mutating
// operation at a time per VPC. Within this stack the hub's PSA
// servicenetworking connection is the only mutation of the hub VPC's peering
// set; the spoke stacks' hub-to-spoke peerings only run after this stack has
// fully applied (deploy order shared → development → nonproduction →
// production, matching upstream's envs/shared-before-envs/<env> ordering).
// The spoke's own PSA-vs-peering serialization lives in modules/shared_vpc
// (createPeering).
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

		// The shared/hub stack uses the configured hub host project directly.
		hubProjectID := pulumi.String(cfg.HubProjectID).ToStringOutput()

		// Hierarchical Firewall Policy (org/folder level) — hub only
		// (hierarchical_firewall.go).
		if err := deployHierarchicalFirewall(ctx, cfg); err != nil {
			return err
		}

		// Hub Shared VPC (net-hubs.go).
		hubRes, hubVpcName, err := deployNetHubs(ctx, cfg, hubProjectID)
		if err != nil {
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
