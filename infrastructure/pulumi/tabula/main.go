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
		// Required: every stack's committed Pulumi.<stack>.yaml declares its
		// env code (dev / nonprod / prod) — a silent default here would let a
		// misconfigured stack masquerade as another environment.
		env := cfg.Require("environment")
		imageTag := cfg.Get("imageTag")
		if imageTag == "" {
			imageTag = "latest"
		}
		// adoptExistingSecrets imports pre-existing Secret Manager secrets
		// (created by the standalone repo's Terraform/tabcli) into this
		// stack's state instead of attempting a colliding create. One-time
		// per stack: after the first successful `pulumi up`, flip it back to
		// false in Pulumi.<stack>.yaml — the resources are then state-managed
		// and a stale import option would error on later updates.
		adoptExistingSecrets := cfg.GetBool("adoptExistingSecrets")
		// The CI deployer (impersonated via WIF) reads DATABASE_URL to run
		// prisma migrate before each rollout; everything else is runtime-only.
		deployServiceAccount := cfg.Get("deployServiceAccount")

		// Artifact Registry repository the Bazel oci_push publishes into:
		// us-central1-docker.pkg.dev/<project>/tabula/api
		//
		// Always adopted via Import: the deploy workflow pre-creates the repo
		// (the image push happens before pulumi up — bootstrap ordering), so
		// by the time this program runs the repo exists in every environment.
		// Pulumi ignores the import option once the resource is in state.
		repo, err := artifactregistry.NewRepository(ctx, "tabula-images", &artifactregistry.RepositoryArgs{
			Project:      pulumi.String(project),
			Location:     pulumi.String(region),
			RepositoryId: pulumi.String("tabula"),
			Format:       pulumi.String("DOCKER"),
			Description:  pulumi.String("Tabula container images (pushed by bazel run //tabula/api:image_push)"),
		},
			pulumi.Import(pulumi.ID(fmt.Sprintf("projects/%s/locations/%s/repositories/tabula", project, region))),
			pulumi.IgnoreChanges([]string{"description", "labels"}),
		)
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
			secretOpts := []pulumi.ResourceOption{
				// Adopted secrets may carry label drift we don't manage.
				// Replication is NOT ignored: it is a required field, and
				// ignoring it during import leaves the provider with no
				// replication value to validate.
				pulumi.IgnoreChanges([]string{"labels"}),
			}
			if adoptExistingSecrets {
				secretOpts = append(secretOpts, pulumi.Import(pulumi.ID(
					fmt.Sprintf("projects/%s/secrets/%s", project, name))))
			}
			secret, err := secretmanager.NewSecret(ctx, name, &secretmanager.SecretArgs{
				Project:  pulumi.String(project),
				SecretId: pulumi.String(name),
				Replication: &secretmanager.SecretReplicationArgs{
					Auto: &secretmanager.SecretReplicationAutoArgs{},
				},
			}, secretOpts...)
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
			if name == "DATABASE_URL" && deployServiceAccount != "" {
				_, err = secretmanager.NewSecretIamMember(ctx, name+"-deployer-access", &secretmanager.SecretIamMemberArgs{
					Project:  pulumi.String(project),
					SecretId: secret.SecretId,
					Role:     pulumi.String("roles/secretmanager.secretAccessor"),
					Member:   pulumi.Sprintf("serviceAccount:%s", deployServiceAccount),
				})
				if err != nil {
					return err
				}
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
		// NODE_ENV derives from the env code (override with tabula:nodeEnv if
		// an environment ever needs to diverge).
		nodeEnv := cfg.Get("nodeEnv")
		if nodeEnv == "" {
			switch env {
			case "prod":
				nodeEnv = "production"
			case "dev":
				nodeEnv = "development"
			default:
				nodeEnv = "staging"
			}
		}

		envs := cloudrunv2.ServiceTemplateContainerEnvArray{
			&cloudrunv2.ServiceTemplateContainerEnvArgs{
				Name:  pulumi.String("NODE_ENV"),
				Value: pulumi.String(nodeEnv),
			},
			// Deploy provenance, surfaced by the API's root endpoint.
			&cloudrunv2.ServiceTemplateContainerEnvArgs{
				Name:  pulumi.String("GIT_SHA"),
				Value: pulumi.String(imageTag),
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
					},
				},
			},
		},
			pulumi.DependsOn([]pulumi.Resource{repo}),
			// Ports are left at the Cloud Run default (8080, matching the
			// API server). The imported live state's ports shape trips a
			// google-beta provider diff bug ("missing expected ["), so keep
			// them unmanaged.
			pulumi.IgnoreChanges([]string{"template.containers[0].ports"}),
		)
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
