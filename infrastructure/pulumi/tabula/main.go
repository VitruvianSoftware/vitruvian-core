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

// Tabula API infrastructure: Artifact Registry for the Bazel-built image,
// the Cloud Run service, its runtime service account, and Secret Manager
// references for runtime secrets. Neon (Postgres) and Upstash (Redis) stay
// externally provisioned; their connection strings live in Secret Manager
// (DATABASE_URL / UPSTASH_REDIS_URL).
//
// Deploy: bazel run //infrastructure/pulumi/tabula:up
// The image tag is supplied per deploy:
//
//	pulumi config set tabula:imageTag <git-sha>
package main

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/artifactregistry"
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/cloudrunv2"
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/secretmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Runtime secrets the API reads from Secret Manager. Values are operator-
// managed (created empty here; populate with
// 'gcloud secrets versions add <name> --data-file=-').
var runtimeSecrets = []string{
	"DATABASE_URL",
	"JWT_SECRET",
	"WORKOS_API_KEY",
	"WORKOS_CLIENT_ID",
	"UPSTASH_REDIS_URL",
}

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "tabula")
		project := cfg.Require("project")
		region := cfg.Get("region")
		if region == "" {
			region = "us-central1"
		}
		env := cfg.Get("environment")
		if env == "" {
			env = "stg"
		}
		imageTag := cfg.Get("imageTag")
		if imageTag == "" {
			imageTag = "latest"
		}

		// Artifact Registry repository the Bazel oci_push publishes into:
		// us-central1-docker.pkg.dev/<project>/tabula/api
		repo, err := artifactregistry.NewRepository(ctx, "tabula-images", &artifactregistry.RepositoryArgs{
			Project:      pulumi.String(project),
			Location:     pulumi.String(region),
			RepositoryId: pulumi.String("tabula"),
			Format:       pulumi.String("DOCKER"),
			Description:  pulumi.String("Tabula container images (pushed by bazel run //tabula/api:image_push)"),
		})
		if err != nil {
			return err
		}

		// Least-privilege runtime identity for the Cloud Run service.
		sa, err := serviceaccount.NewAccount(ctx, "tabula-api-sa", &serviceaccount.AccountArgs{
			Project:     pulumi.String(project),
			AccountId:   pulumi.Sprintf("tabula-api-%s", env),
			DisplayName: pulumi.String("Tabula API runtime"),
		})
		if err != nil {
			return err
		}

		var secretEnvs cloudrunv2.ServiceTemplateContainerEnvArray
		for _, name := range runtimeSecrets {
			secret, err := secretmanager.NewSecret(ctx, name, &secretmanager.SecretArgs{
				Project:  pulumi.String(project),
				SecretId: pulumi.String(name),
				Replication: &secretmanager.SecretReplicationArgs{
					Auto: &secretmanager.SecretReplicationAutoArgs{},
				},
			}, pulumi.IgnoreChanges([]string{"labels"}))
			if err != nil {
				return err
			}
			_, err = secretmanager.NewSecretIamMember(ctx, name+"-access", &secretmanager.SecretIamMemberArgs{
				Project:  pulumi.String(project),
				SecretId: secret.SecretId,
				Role:     pulumi.String("roles/secretmanager.secretAccessor"),
				Member:   pulumi.Sprintf("serviceAccount:%s", sa.Email),
			})
			if err != nil {
				return err
			}
			secretEnvs = append(secretEnvs, &cloudrunv2.ServiceTemplateContainerEnvArgs{
				Name: pulumi.String(name),
				ValueSource: &cloudrunv2.ServiceTemplateContainerEnvValueSourceArgs{
					SecretKeyRef: &cloudrunv2.ServiceTemplateContainerEnvValueSourceSecretKeyRefArgs{
						Secret:  secret.SecretId,
						Version: pulumi.String("latest"),
					},
				},
			})
		}

		image := pulumi.Sprintf("%s-docker.pkg.dev/%s/tabula/api:%s", region, project, imageTag)
		envs := cloudrunv2.ServiceTemplateContainerEnvArray{
			&cloudrunv2.ServiceTemplateContainerEnvArgs{
				Name:  pulumi.String("NODE_ENV"),
				Value: pulumi.String("staging"),
			},
		}
		envs = append(envs, secretEnvs...)

		service, err := cloudrunv2.NewService(ctx, "tabula-api", &cloudrunv2.ServiceArgs{
			Project:  pulumi.String(project),
			Location: pulumi.String(region),
			Name:     pulumi.Sprintf("tabula-api-%s", env),
			Template: &cloudrunv2.ServiceTemplateArgs{
				ServiceAccount: sa.Email,
				Containers: cloudrunv2.ServiceTemplateContainerArray{
					&cloudrunv2.ServiceTemplateContainerArgs{
						Image: image,
						Envs:  envs,
						Ports: cloudrunv2.ServiceTemplateContainerPortArray{
							&cloudrunv2.ServiceTemplateContainerPortArgs{
								ContainerPort: pulumi.Int(8080),
							},
						},
					},
				},
			},
		}, pulumi.DependsOn([]pulumi.Resource{repo}))
		if err != nil {
			return err
		}

		// Public API: extension/web clients authenticate at the application
		// layer (JWT), matching the previous gcloud-based deployment.
		_, err = cloudrunv2.NewServiceIamMember(ctx, "tabula-api-public", &cloudrunv2.ServiceIamMemberArgs{
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
		ctx.Export("serviceAccount", sa.Email)
		_ = fmt.Sprintf
		return nil
	})
}
