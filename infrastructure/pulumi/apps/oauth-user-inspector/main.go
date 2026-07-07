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

// OAuth User Inspector infrastructure: Artifact Registry for the Bazel-built
// image, the Cloud Run service, and its runtime service account. The app reads
// its OAuth client credentials directly from GCP Secret Manager at runtime
// (server/server.ts -> SecretManagerServiceClient).
//
// Deploy: bazel run //infrastructure/pulumi/apps/oauth-user-inspector:up
package main

import (
	"fmt"
	"os"
	"strconv"

	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/artifactregistry"
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/cloudrunv2"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "oauth-user-inspector")
		project := cfg.Require("project")
		region := cfg.Get("region")
		if region == "" {
			region = "us-west1"
		}

		env := cfg.Require("environment")
		imageTag := envOrConfig("OAUTH_USER_INSPECTOR_IMAGE_TAG", cfg, "imageTag")
		if imageTag == "" {
			imageTag = "latest"
		}
		promote := envOrConfigBool("OAUTH_USER_INSPECTOR_PROMOTE", cfg, "promote")
		stableRevision := envOrConfig("OAUTH_USER_INSPECTOR_STABLE_REVISION", cfg, "stableRevision")

		runtimeSA := cfg.Require("runtimeServiceAccount")

		repo, err := artifactregistry.NewRepository(
			ctx, "oauth-user-inspector-images", &artifactregistry.RepositoryArgs{
				Project:      pulumi.String(project),
				Location:     pulumi.String(region),
				RepositoryId: pulumi.String("oauth-user-inspector"),
				Format:       pulumi.String("DOCKER"),
				Description:  pulumi.String("OAuth User Inspector container images (pushed by bazel run)"),
			},
			pulumi.Import(pulumi.ID(fmt.Sprintf("projects/%s/locations/%s/repositories/oauth-user-inspector", project, region))),
			pulumi.IgnoreChanges([]string{"description", "labels"}),
		)
		if err != nil {
			return err
		}

		image := pulumi.Sprintf("%s-docker.pkg.dev/%s/oauth-user-inspector/app:%s", region, project, imageTag)

		envs := cloudrunv2.ServiceTemplateContainerEnvArray{
			&cloudrunv2.ServiceTemplateContainerEnvArgs{
				Name:  pulumi.String("NODE_ENV"),
				Value: pulumi.String("production"),
			},
			&cloudrunv2.ServiceTemplateContainerEnvArgs{
				Name:  pulumi.String("GOOGLE_CLOUD_PROJECT"),
				Value: pulumi.String(project),
			},
		}

		revisionSuffix := imageTag
		if len(revisionSuffix) > 7 {
			revisionSuffix = revisionSuffix[:7]
		}
		revisionName := pulumi.Sprintf("oauth-user-inspector-%s-%s", env, revisionSuffix)
		var traffics cloudrunv2.ServiceTrafficArray
		if promote || stableRevision == "" {
			traffics = cloudrunv2.ServiceTrafficArray{
				&cloudrunv2.ServiceTrafficArgs{
					Type:     pulumi.String("TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"),
					Revision: revisionName,
					Percent:  pulumi.Int(100),
				},
			}
		} else {
			traffics = cloudrunv2.ServiceTrafficArray{
				&cloudrunv2.ServiceTrafficArgs{
					Type:     pulumi.String("TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"),
					Revision: pulumi.String(stableRevision),
					Percent:  pulumi.Int(100),
				},
				&cloudrunv2.ServiceTrafficArgs{
					Type:     pulumi.String("TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"),
					Revision: revisionName,
					Percent:  pulumi.Int(0),
					Tag:      pulumi.String("candidate"),
				},
			}
		}

		service, err := cloudrunv2.NewService(
			ctx, "oauth-user-inspector", &cloudrunv2.ServiceArgs{
				Project:  pulumi.String(project),
				Location: pulumi.String(region),
				Name:     pulumi.Sprintf("oauth-user-inspector-%s", env),
				Template: &cloudrunv2.ServiceTemplateArgs{
					Revision:       revisionName,
					ServiceAccount: pulumi.String(runtimeSA),
					Scaling: &cloudrunv2.ServiceTemplateScalingArgs{
						MaxInstanceCount: pulumi.Int(10),
					},
					Containers: cloudrunv2.ServiceTemplateContainerArray{
						&cloudrunv2.ServiceTemplateContainerArgs{
							Image: image,
							Envs:  envs,
							Ports: cloudrunv2.ServiceTemplateContainerPortArray{
								&cloudrunv2.ServiceTemplateContainerPortArgs{
									ContainerPort: pulumi.Int(8080),
								},
							},
							Resources: &cloudrunv2.ServiceTemplateContainerResourcesArgs{
								Limits: pulumi.StringMap{
									"cpu":    pulumi.String("1"),
									"memory": pulumi.String("512Mi"),
								},
							},
						},
					},
				},
				Traffics: traffics,
			},
			pulumi.DependsOn([]pulumi.Resource{repo}),
			// Ignore fields the old Cloud Build deploy set so they don't churn.
			pulumi.IgnoreChanges([]string{"client", "clientVersion", "launchStage", "annotations", "labels", "template.labels", "template.annotations"}),
		)
		if err != nil {
			return err
		}

		_, err = cloudrunv2.NewServiceIamMember(ctx, "oauth-user-inspector-public", &cloudrunv2.ServiceIamMemberArgs{
			Project:  pulumi.String(project),
			Location: pulumi.String(region),
			Name:     service.Name,
			Role:     pulumi.String("roles/run.invoker"),
			Member:   pulumi.String("allUsers"),
		})
		if err != nil {
			return err
		}

		ctx.Export("serviceUrl", service.Uri)
		ctx.Export("artifactRegistry", pulumi.Sprintf("%s-docker.pkg.dev/%s/%s", region, project, repo.RepositoryId))
		ctx.Export("serviceAccount", pulumi.String(runtimeSA))
		return nil
	})
}

// envOrConfig reads a per-invocation deploy input: the environment variable
// wins (process-scoped, so concurrent invocations can't clobber each other).
func envOrConfig(envName string, cfg *config.Config, cfgKey string) string {
	if v := os.Getenv(envName); v != "" {
		return v
	}
	return cfg.Get(cfgKey)
}

// envOrConfigBool is envOrConfig for booleans.
func envOrConfigBool(envName string, cfg *config.Config, cfgKey string) bool {
	if v := os.Getenv(envName); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			panic(fmt.Sprintf("%s=%q is not a boolean", envName, v))
		}
		return b
	}
	return cfg.GetBool(cfgKey)
}
