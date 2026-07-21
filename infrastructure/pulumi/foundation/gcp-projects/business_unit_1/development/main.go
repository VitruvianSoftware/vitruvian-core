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

// Foundation stage 4 (projects) — thin business-unit leaf for the development
// environment, mirroring upstream terraform-example-foundation
// 4-projects/business_unit_1/development. This leaf pins the environment
// identity (development/d), creates the BU folder under the development env
// folder, and calls the shared modules/base_env for the per-env business-unit
// project set. The BU's shared infra-pipeline project lives in the sibling
// business_unit_1/shared leaf (upstream's `shared` workspace).
//
// File layout mirrors the upstream leaf: main.go (orchestration, upstream
// main.tf), config.go (variables.tf), remote.go (remote.tf), outputs.go
// (outputs.tf).
package main

import (
	"fmt"
	"foundation-projects/modules/app_deploy_identity"
	"foundation-projects/modules/base_env"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Environment pinned by this leaf project — upstream
// 4-projects/business_unit_1/development hardcodes env = "development" in its
// main.tf; the leaf dir is the pin, not per-stack config.
const (
	pinnedEnv     = "development"
	pinnedEnvCode = "d"
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
		// Platform-issued deploy identities for the apps hosted on this env's
		// oss-floating project. Minted HERE, one stage above the 5-app-infra
		// workloads they deploy, so an app's pipeline can never edit the stack
		// that defines its own permissions
		// (docs/engineering/core-vs-application-infrastructure.md §4.1).
		deploySAs := map[string]pulumi.StringOutput{}
		if cfg.OSSFloatingProjectEnabled {
			for _, app := range cfg.Apps {
				res, err := app_deploy_identity.Deploy(ctx, app.Name, &app_deploy_identity.Args{
					App:                  app.Name,
					Env:                  cfg.Env,
					ProjectID:            projects.OSSFloatingProjectID,
					DeployAccountID:      app.DeployAccountID,
					DeployRoles:          app.DeployRoles,
					WorkloadIdentityPool: refs.WIFPoolName,
					GitHubEnvironment:    app.GitHubEnvironment(cfg.Env),
				})
				if err != nil {
					return err
				}
				deploySAs[app.Name] = res.DeployServiceAccountEmail
			}
		}
		// The BU's app-infra pipeline identity: applies the stage-5 leaf for
		// this BU+env. Separate from the per-app SAs above because a stage-5
		// leaf is ONE stack that may host several apps, so it cannot be applied
		// by any single app's identity. Its own grants live here, in a stage it
		// does not apply — which is what makes ungating stage 5 safe.
		if cfg.OSSFloatingProjectEnabled && len(cfg.Apps) > 0 {
			pipeline, err := app_deploy_identity.DeployBUPipeline(ctx, cfg.BusinessCode, &app_deploy_identity.PipelineArgs{
				BusinessCode:         cfg.BusinessCode,
				Env:                  cfg.Env,
				ProjectID:            projects.OSSFloatingProjectID,
				Roles:                defaultAppInfraPipelineRoles,
				WorkloadIdentityPool: refs.WIFPoolName,
				GitHubEnvironment:    "foundation-app-" + cfg.Env,
			})
			if err != nil {
				return err
			}
			ctx.Export("app_infra_pipeline_service_account", pipeline.ServiceAccountEmail)
		}

		for app, email := range deploySAs {
			ctx.Export(app+"_deploy_service_account", email)
		}

		exportStackOutputs(ctx, cfg, projects)

		return nil
	})
}
