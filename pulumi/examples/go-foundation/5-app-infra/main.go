package main

import (
	"fmt"
	"strings"

	"foundation-5-app-infra/modules/confidential_space"
	"foundation-5-app-infra/modules/env_base"
	"foundation-5-app-infra/modules/serverless_space"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadAppInfraConfig(ctx)

		// 1. Stack Reference: 4-projects (per-environment)
		projStack, err := pulumi.NewStackReference(ctx, "projects", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.ProjectsStackName),
		})
		if err != nil {
			return err
		}

		// 2. Stack Reference: 0-bootstrap (shared / common — not per-environment)
		bootstrapStack, err := pulumi.NewStackReference(ctx, "bootstrap", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.BootstrapStackName),
		})
		if err != nil {
			return err
		}

		// --- Resolve outputs from 4-projects ---
		appProjectID := projStack.GetStringOutput(pulumi.String("shared_vpc_project"))
		appProjectNumber := projStack.GetStringOutput(pulumi.String("shared_vpc_project_number"))
		subnetsSelfLinks := projStack.GetOutput(pulumi.String("subnets_self_links")).ApplyT(func(v interface{}) string {
			if links, ok := v.([]interface{}); ok && len(links) > 0 {
				return links[0].(string)
			}
			return ""
		}).(pulumi.StringOutput)
		workloadSAEmail := projStack.GetStringOutput(pulumi.String("confidential_space_workload_sa"))

		cloudbuildProjectID := bootstrapStack.GetStringOutput(pulumi.String("cloudbuild_project_id"))

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
			CloudBuildProjectID:      cloudbuildProjectID,
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

type AppInfraConfig struct {
	Env                     string
	EnvCode                 string
	BusinessCode            string
	Region                  string
	ProjectsStackName       string
	BootstrapStackName      string
	ConfidentialImageDigest string
	ServerlessImageDigest   string
}

func loadAppInfraConfig(ctx *pulumi.Context) *AppInfraConfig {
	conf := config.New(ctx, "")
	c := &AppInfraConfig{
		Env:                     conf.Require("env"),
		BusinessCode:            conf.Get("business_code"),
		Region:                  conf.Get("region"),
		ProjectsStackName:       conf.Get("projects_stack_name"),
		BootstrapStackName:      conf.Get("bootstrap_stack_name"),
		ConfidentialImageDigest: conf.Get("confidential_image_digest"),
		ServerlessImageDigest:   conf.Get("serverless_image_digest"),
	}

	if c.BusinessCode == "" {
		c.BusinessCode = "bu1"
	}
	if c.ProjectsStackName == "" {
		c.ProjectsStackName = fmt.Sprintf("VitruvianSoftware/foundation-4-projects/%s", c.Env)
	}
	if c.BootstrapStackName == "" {
		c.BootstrapStackName = strings.Replace(c.ProjectsStackName, "foundation-4-projects/"+c.Env, "foundation-0-bootstrap/shared", 1)
	}
	envCodes := map[string]string{"development": "d", "nonproduction": "n", "production": "p"}
	c.EnvCode = envCodes[c.Env]
	if c.EnvCode == "" {
		c.EnvCode = c.Env[:1]
	}
	return c
}
