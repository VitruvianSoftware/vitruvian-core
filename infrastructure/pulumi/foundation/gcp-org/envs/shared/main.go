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
		// The domain-restricted sharing policy depends on the log sinks (Gap 3
		// guard applied in org_policy.go).
		if err := deployOrgPolicies(ctx, cfg, logOutputs.LastResource); err != nil {
			return err
		}

		// 6. Deploy SCC Notifications
		// Gated on the SCC project's ApisReady (cold-deploy API propagation).
		if cfg.EnableSCCResources {
			if err := deploySCCNotification(ctx, cfg, projOutputs.SCCProjectID, projOutputs.SCCApisReady); err != nil {
				return err
			}
		}

		// 6a. Deploy the CAI Monitoring builder SA (sa.go, upstream sa.tf).
		// Cold-deploy fix: the SA must exist BEFORE the CAI monitoring Cloud
		// Function references it as the Cloud Build SA.
		caiBuilderSA, err := deployCAIMonitoringBuilderSA(ctx, cfg, projOutputs)
		if err != nil {
			return err
		}

		// 6b. Deploy CAI Monitoring infrastructure (Gap 2)
		caiOutputs, err := deployCAIMonitoring(ctx, cfg, projOutputs, caiBuilderSA)
		if err != nil {
			return err
		}

		// 7. Deploy Org-level Tags (with folder bindings)
		tagOutputs, err := deployTags(ctx, cfg, folders, bootstrapRef)
		if err != nil {
			return err
		}

		// 8. Deploy IAM bindings for groups
		if err := deployOrgIAM(ctx, cfg, projOutputs, bootstrapRef, caiBuilderSA); err != nil {
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
