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
package main

import (
	"fmt"
	"foundation-5-app-infra/modules/confidential_space"
	"foundation-5-app-infra/modules/env_base"
	"foundation-5-app-infra/modules/serverless_space"
	"strings"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
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

		// 1. Stack Reference: this environment's 4-projects leaf
		// (business_unit_1/<env> — upstream's projects_env remote state).
		projStack, err := pulumi.NewStackReference(ctx, "projects", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.ProjectsStackName),
		})
		if err != nil {
			return err
		}

		// 2. Stack Reference: the BU's 4-projects shared leaf
		// (business_unit_1/shared — upstream's business_unit_shared remote
		// state, which supplies the project that hosts the Confidential Space
		// workload image registry).
		projSharedStack, err := pulumi.NewStackReference(ctx, "projects_shared", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.ProjectsSharedStackName),
		})
		if err != nil {
			return err
		}

		// --- Resolve outputs from the 4-projects env leaf ---
		appProjectID := projStack.GetStringOutput(pulumi.String("shared_vpc_project"))
		appProjectNumber := projStack.GetStringOutput(pulumi.String("shared_vpc_project_number"))
		subnetsSelfLinks := projStack.GetOutput(pulumi.String("subnets_self_links")).ApplyT(func(v interface{}) string {
			if links, ok := v.([]interface{}); ok && len(links) > 0 {
				return links[0].(string)
			}
			return ""
		}).(pulumi.StringOutput)
		workloadSAEmail := projStack.GetStringOutput(pulumi.String("confidential_space_workload_sa"))

		// Upstream's confidential_space module reads
		// bootstrap_cloudbuild_project_id from the 4-projects shared workspace
		// (the project whose Artifact Registry hosts the workload image). Our
		// WIF port has no Cloud Build project chain: the BU's shared
		// build/artifact home is the app-infra pipeline project owned by the
		// 4-projects business_unit_1/shared leaf, exported as
		// infra_pipeline_project_id (documented engine-difference workaround).
		imageProjectID := projSharedStack.GetStringOutput(pulumi.String("infra_pipeline_project_id"))

		appRegion := pulumi.String(cfg.Region).ToStringOutput()
		if cfg.Region == "" {
			appRegion = projStack.GetStringOutput(pulumi.String("default_region"))
		}
		ctx.Export("project_id", appProjectID)
		ctx.Export("region", appRegion)

		// 4. Deploy Base Environment Workload
		_, err = env_base.DeployEnvBase(ctx, "env-base", &env_base.EnvBaseArgs{
			Env:                cfg.Env,
			BusinessUnit:       cfg.BusinessCode,
			ProjectSuffix:      "app-infra",
			Hostname:           cfg.EnvCode + "-env-base",
			MachineType:        "f1-micro",
			NumInstances:       1,
			SourceImageFamily:  "debian-11",
			SourceImageProject: "debian-cloud",
			ProjectID:          appProjectID,
			Region:             appRegion,
			SubnetworkSelfLink: subnetsSelfLinks,
			// env_base is the non-peering SVPC instance; IAP secure tags belong on the
			// (separate) peering-project workload, so leave these nil here.
			IAPFirewallTags: nil,
		})
		if err != nil {
			return err
		}

		// 5. Deploy Confidential Space Workload
		_, err = confidential_space.DeployConfidentialSpace(ctx, "conf-space", &confidential_space.ConfidentialSpaceArgs{
			Env:                      cfg.Env,
			BusinessUnit:             cfg.BusinessCode,
			ProjectID:                appProjectID,
			ProjectNumber:            appProjectNumber,
			Region:                   appRegion,
			SubnetworkSelfLink:       subnetsSelfLinks,
			WorkloadSAEmail:          workloadSAEmail,
			ConfidentialImageDigest:  cfg.ConfidentialImageDigest,
			ConfidentialMachineType:  "n2d-standard-2",
			ConfidentialInstanceType: "SEV",
			CpuPlatform:              "AMD Milan",
			CloudBuildProjectID:      imageProjectID,
		})
		if err != nil {
			return err
		}

		// 6. Deploy Serverless (Cloud Run) Workload — the serverless peer to
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
				ProjectID:     appProjectID,
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
			ctx.Export("serverless_service_uri", ss.ServiceUri)
		}

		return nil
	})
}

// AppInfraConfig holds configuration for this environment leaf of the
// app-infra stage. The environment identity is pinned by the leaf (pinnedEnv /
// pinnedEnvCode), not read from config.
type AppInfraConfig struct {
	Env                     string
	EnvCode                 string
	BusinessCode            string
	Region                  string
	ProjectsStackName       string
	ProjectsSharedStackName string
	ConfidentialImageDigest string
	ServerlessImageDigest   string
}

func loadAppInfraConfig(ctx *pulumi.Context) *AppInfraConfig {
	conf := config.New(ctx, "")
	c := &AppInfraConfig{
		Env:                     pinnedEnv,
		EnvCode:                 pinnedEnvCode,
		BusinessCode:            conf.Get("business_code"),
		Region:                  conf.Get("region"),
		ProjectsStackName:       conf.Get("projects_stack_name"),
		ProjectsSharedStackName: conf.Get("projects_shared_stack_name"),
		ConfidentialImageDigest: conf.Get("confidential_image_digest"),
		ServerlessImageDigest:   conf.Get("serverless_image_digest"),
	}

	if c.BusinessCode == "" {
		c.BusinessCode = "bu1"
	}
	// The projects reference targets this environment's 4-projects env leaf
	// stack; the shared reference defaults to the sibling business_unit_1/shared
	// leaf, derived by name substitution.
	if c.ProjectsStackName == "" {
		c.ProjectsStackName = fmt.Sprintf("organization/vitruvian/foundation-projects-%s-%s/production", c.BusinessCode, pinnedEnv)
	}
	if c.ProjectsSharedStackName == "" {
		c.ProjectsSharedStackName = strings.Replace(c.ProjectsStackName,
			fmt.Sprintf("foundation-projects-%s-%s", c.BusinessCode, pinnedEnv),
			fmt.Sprintf("foundation-projects-%s-shared", c.BusinessCode), 1)
	}
	return c
}
