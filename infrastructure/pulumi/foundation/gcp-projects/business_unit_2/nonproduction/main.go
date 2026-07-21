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

// Foundation stage 4 (projects) — thin business-unit leaf for the nonproduction
// environment, mirroring upstream terraform-example-foundation
// 4-projects/business_unit_2/nonproduction. This leaf pins the environment
// identity (nonproduction/n), creates the BU folder under the nonproduction env
// folder, and calls the shared modules/base_env for the per-env business-unit
// project set. The BU's shared infra-pipeline project lives in the sibling
// business_unit_2/shared leaf (upstream's `shared` workspace).
//
// File layout mirrors the upstream leaf: main.go (orchestration, upstream
// main.tf), config.go (variables.tf), remote.go (remote.tf), outputs.go
// (outputs.tf).
package main

import (
	"fmt"
	"foundation-projects/modules/base_env"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Environment pinned by this leaf project — upstream
// 4-projects/business_unit_2/nonproduction hardcodes env = "nonproduction" in its
// main.tf; the leaf dir is the pin, not per-stack config.
const (
	pinnedEnv     = "nonproduction"
	pinnedEnvCode = "n"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadProjectsConfig(ctx)

		// 1. Cross-stage StackReferences (remote.go) — the environment folder +
		// KMS project, and conditionally the org/network stage outputs.
		refs, err := loadStackReferences(ctx, cfg)
		if err != nil {
			return err
		}

		// 2. Create the Business Unit folder under the environment folder
		buFolder, err := organizations.NewFolder(ctx, "bu-folder", &organizations.FolderArgs{
			DisplayName: refs.FolderID.ApplyT(func(_ string) string {
				return fmt.Sprintf("%s-%s-%s", cfg.FolderPrefix, cfg.Env, cfg.BusinessCode)
			}).(pulumi.StringOutput),
			// env_folder is exported as envFolder.Name, which GCP already
			// formats as "folders/{id}"; use it directly (prefixing would double it).
			Parent:             refs.FolderID,
			DeletionProtection: pulumi.Bool(cfg.FolderDeletionProtection),
		})
		if err != nil {
			return err
		}

		// 3. Deploy Business Unit Projects (each type internally toggle-gated)
		buFolderID := buFolder.ID().ApplyT(func(id pulumi.ID) string {
			return string(id)
		}).(pulumi.StringOutput)

		// base_env.Args carries the subset of cfg the module needs plus the
		// cross-stage StackReference outputs. Labels/Budget are supplied from the
		// leaf's tested helpers so label/budget behaviour is preserved exactly.
		beArgs := &base_env.Args{
			ProjectPrefix:  cfg.ProjectPrefix,
			EnvCode:        cfg.EnvCode,
			BusinessCode:   cfg.BusinessCode,
			BillingAccount: cfg.BillingAccount,
			RandomSuffix:   cfg.RandomSuffix,

			SVPCProjectEnabled:        cfg.SVPCProjectEnabled,
			FloatingProjectEnabled:    cfg.FloatingProjectEnabled,
			OSSFloatingProjectEnabled: cfg.OSSFloatingProjectEnabled,
			PeeringProjectEnabled:     cfg.PeeringProjectEnabled,

			EnforceVpcSc:   cfg.EnforceVpcSc,
			CMEKEnabled:    cfg.CMEKEnabled,
			PeeringEnabled: cfg.PeeringEnabled,

			ApiPropagationSeconds: cfg.ApiPropagationSeconds,

			SubnetRegion:           cfg.SubnetRegion,
			SubnetIPRange:          cfg.SubnetIPRange,
			PeeringIAPFWEnabled:    cfg.PeeringIAPFWEnabled,
			FirewallEnableLogging:  cfg.FirewallEnableLogging,
			WindowsActivation:      cfg.WindowsActivation,
			OptionalFWRulesEnabled: cfg.OptionalFWRulesEnabled,

			KeyringName:         cfg.KeyringName,
			KMSLocation:         cfg.KMSLocation,
			KeyName:             cfg.KeyName,
			KeyRotationPeriod:   cfg.KeyRotationPeriod,
			GCSBucketPrefix:     cfg.GCSBucketPrefix,
			GCSLocation:         cfg.GCSLocation,
			GCSPlacementRegions: cfg.GCSPlacementRegions,

			FolderID:         buFolderID,
			NetworkProjectID: refs.NetworkProjectID,
			PerimeterName:    refs.PerimeterName,
			KMSProjectID:     refs.KMSProjectID,
			ACMPolicyID:      refs.ACMPolicyID,

			Labels: func(suffix, vpc string) pulumi.StringMap {
				return projectLabels(cfg, suffix, vpc)
			},
			Budget: budgetConfig(cfg),
		}
		projects, err := base_env.New(ctx, beArgs)
		if err != nil {
			return err
		}

		// 4. Deploy Confidential Space Project (optional, toggle-gated)
		if cfg.ConfidentialSpaceEnabled {
			confResult, err := base_env.DeployConfidentialSpaceProject(ctx, beArgs)
			if err != nil {
				return err
			}
			projects.ConfSpaceProjectID = &confResult.ProjectID
			projects.ConfSpaceProjectNumber = &confResult.ProjectNumber
			projects.ConfSpaceWorkloadSA = &confResult.WorkloadSAEmail
		}

		// 5. Exports (outputs.go)
		exportStackOutputs(ctx, cfg, projects)

		return nil
	})
}
