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

// Foundation stage 3 (networks, svpc) — thin shared root, mirroring upstream
// terraform-example-foundation 3-networks-svpc/envs/shared. This leaf pins the
// shared identity and deploys the shared/global network resources: the
// org/folder-level hierarchical firewall policy. The per-environment Shared
// VPCs live in the sibling envs/{development,nonproduction,production} leaves.
package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Shared identity pinned by this leaf project — upstream
// 3-networks-svpc/envs/shared hardcodes the "shared" environment; the leaf dir
// is the pin, not per-stack config.
const pinnedEnv = "shared"

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadSharedConfig(ctx)

		// Hierarchical Firewall Policy (org/folder level) —
		// hierarchical_firewall.go.
		if err := deployHierarchicalFirewall(ctx, cfg); err != nil {
			return err
		}

		// TF 3-networks-svpc shared has no outputs — see outputs.go.
		return nil
	})
}
