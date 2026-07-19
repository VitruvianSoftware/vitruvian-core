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

// Foundation stage 5 (app-infra) — thin business-unit leaf for the production
// environment, mirroring upstream terraform-example-foundation
// 5-app-infra/business_unit_1/production. This leaf pins the environment
// identity (production/p) and calls the shared modules/{env_base,
// confidential_space,serverless_space} packages with outputs resolved from the
// 4-projects leaves of this business unit.
//
// Per-concern layout mirroring upstream's file split: main.go (main.tf) is
// the orchestration, config.go (variables.tf) the stack configuration,
// remote.go (remote.tf) the 4-projects Stack References, and outputs.go
// (outputs.tf) the stack exports.
package main

import (
	"foundation-5-app-infra/modules/confidential_space"
	"foundation-5-app-infra/modules/env_base"
	"foundation-5-app-infra/modules/serverless_space"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Environment pinned by this leaf project — upstream
// 5-app-infra/business_unit_1/production hardcodes environment = "production"
// in its main.tf locals; the leaf dir is the pin, not per-stack config.
const (
	pinnedEnv     = "production"
	pinnedEnvCode = "p"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadAppInfraConfig(ctx)

		// 1. Resolve the cross-stage inputs from the 4-projects leaves
		// (Stack References — see remote.go).
		remote, err := resolveProjectsRemoteState(ctx, cfg)
		if err != nil {
			return err
		}

		exportAppInfraOutputs(ctx, remote)

		// 2. Deploy Base Environment Workload
		_, err = env_base.DeployEnvBase(ctx, "env-base", &env_base.EnvBaseArgs{
			Env:                cfg.Env,
			BusinessUnit:       cfg.BusinessCode,
			ProjectSuffix:      "app-infra",
			Hostname:           cfg.EnvCode + "-env-base",
			MachineType:        "f1-micro",
			NumInstances:       1,
			SourceImageFamily:  "debian-11",
			SourceImageProject: "debian-cloud",
			ProjectID:          remote.AppProjectID,
			Region:             remote.Region,
			SubnetworkSelfLink: remote.SubnetSelfLink,
			// env_base is the non-peering SVPC instance; IAP secure tags belong on the
			// (separate) peering-project workload, so leave these nil here.
			IAPFirewallTags: nil,
		})
		if err != nil {
			return err
		}

		// 3. Deploy Confidential Space Workload
		_, err = confidential_space.DeployConfidentialSpace(ctx, "conf-space", &confidential_space.ConfidentialSpaceArgs{
			Env:                      cfg.Env,
			BusinessUnit:             cfg.BusinessCode,
			ProjectID:                remote.AppProjectID,
			ProjectNumber:            remote.AppProjectNumber,
			Region:                   remote.Region,
			SubnetworkSelfLink:       remote.SubnetSelfLink,
			WorkloadSAEmail:          remote.WorkloadSAEmail,
			ConfidentialImageDigest:  cfg.ConfidentialImageDigest,
			ConfidentialMachineType:  "n2d-standard-2",
			ConfidentialInstanceType: "SEV",
			CpuPlatform:              "AMD Milan",
			CloudBuildProjectID:      remote.ImageProjectID,
		})
		if err != nil {
			return err
		}

		// 4. Deploy Serverless (Cloud Run) Workload — the serverless peer to
		//    env_base/confidential_space. Only deployed when an image digest is
		//    configured, so the reference stack stays applyable without a build.
		if cfg.ServerlessImageDigest != "" {
			ssRegion := cfg.Region
			if ssRegion == "" {
				ssRegion = "us-central1"
			}
			ss, err := serverless_space.DeployServerlessSpace(ctx, "serverless-space", &serverless_space.ServerlessSpaceArgs{
				Env:           cfg.Env,
				BusinessUnit:  cfg.BusinessCode,
				ProjectID:     remote.AppProjectID,
				Region:        ssRegion,
				ServiceName:   cfg.EnvCode + "-serverless-space",
				ImageDigest:   pulumi.String(cfg.ServerlessImageDigest),
				SecretPrefix:  "EXAMPLE_APP_",
				PublicInvoker: true,
				MaxInstances:  2,
			})
			if err != nil {
				return err
			}
			exportServerlessOutputs(ctx, ss)
		}

		return nil
	})
}
