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

// The 1-org shared environment root, mirroring the Terraform foundation's
// 1-org/envs/shared. Each concern lives in its own file matching the upstream
// .tf file names (folders.go ↔ folders.tf, org_policy.go ↔ org_policy.tf, …);
// main.go only wires them together in deployment order.

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadOrgConfig(ctx)

		// 1. Stack Reference to Bootstrap (for cross-stage outputs)
		bootstrapRef, err := newBootstrapReference(ctx, cfg)
		if err != nil {
			return err
		}

		// 2. Deploy Folders (Common, Network, Environment)
		folders, err := deployFolders(ctx, cfg)
		if err != nil {
			return err
		}

		// 3. Deploy all Org-level Projects
		projOutputs, err := deployOrgProjects(ctx, cfg, folders)
		if err != nil {
			return err
		}

		// 4. Deploy Centralized Logging (org sinks → Storage, Pub/Sub, BigQuery)
		// Must run BEFORE policies so domain-restricted sharing waits for sinks (Gap 3)
		logOutputs, err := deployLogSinks(ctx, cfg, projOutputs)
		if err != nil {
			return err
		}

		// 5. Deploy Organization Policies (14+ boolean + list)
		// The domain-restricted sharing policy waits for the log sinks via the
		// wait-logs-export sleep created in org_policy.go (upstream Gap 3 guard).
		if err := deployOrgPolicies(ctx, cfg, logOutputs.LastResource); err != nil {
			return err
		}

		// 6. Deploy SCC Notifications
		if cfg.EnableSCCResources {
			if err := deploySCCNotification(ctx, cfg, projOutputs.SCCProjectID); err != nil {
				return err
			}
		}

		// 6a. Deploy the CAI Monitoring builder SA (sa.go, upstream sa.tf)
		if err := deployCAIMonitoringBuilderSA(ctx, cfg, projOutputs); err != nil {
			return err
		}

		// 6b. Deploy CAI Monitoring infrastructure (Gap 2)
		caiOutputs, err := deployCAIMonitoring(ctx, cfg, projOutputs)
		if err != nil {
			return err
		}

		// 7. Deploy Org-level Tags (with folder bindings)
		tagOutputs, err := deployTags(ctx, cfg, folders, bootstrapRef)
		if err != nil {
			return err
		}

		// 8. Deploy IAM bindings for groups
		if err := deployOrgIAM(ctx, cfg, projOutputs, bootstrapRef); err != nil {
			return err
		}

		// 9. Deploy Essential Contacts
		if err := deployEssentialContacts(ctx, cfg); err != nil {
			return err
		}

		// 9.5 Access Context Manager Policy (org_policy.go)
		accessContextManagerPolicyID, err := deployAccessContextManagerPolicy(ctx, cfg)
		if err != nil {
			return err
		}

		// 10. Exports (outputs.go)
		exportOrgOutputs(ctx, cfg, folders, projOutputs, logOutputs, caiOutputs, tagOutputs, accessContextManagerPolicyID)

		return nil
	})
}
