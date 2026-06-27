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

// OAuth User Inspector infrastructure: Artifact Registry for the Docker-built
// image, the Cloud Run service, and its runtime service account. The app reads
// its OAuth client credentials directly from GCP Secret Manager at runtime
// (server/server.ts -> SecretManagerServiceClient), so the secrets are NOT
// injected as env here — the runtime service account is simply granted
// project-level Secret Manager accessor (mirroring the app's old deploy.sh,
// which bound roles/secretmanager.secretAccessor at the project level).
//
// Deploy: bazel run //infrastructure/pulumi/oauth-user-inspector:up
// The image tag is supplied per deploy:
//
//	pulumi config set oauth-user-inspector:imageTag <git-sha>
package main

import (
	"fmt"

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
		imageTag := cfg.Get("imageTag")
		if imageTag == "" {
			imageTag = "latest"
		}
		// Runtime identity for the Cloud Run service. The SA itself (and its
		// project-level Secret Manager accessor grant) is owned by the
		// oauth-user-inspector-deploy-identity bootstrap stack; this stack only
		// references its email.
		runtimeSA := cfg.Require("runtimeServiceAccount")

		// Artifact Registry repository the deploy workflow's docker buildx
		// publishes into: us-west1-docker.pkg.dev/<project>/oauth-user-inspector/app
		//
		// Always adopted via Import: the deploy workflow pre-creates the repo
		// (the image push happens before pulumi up — bootstrap ordering), so
		// by the time this program runs the repo exists. Pulumi ignores the
		// import option once the resource is in state.
		repo, err := artifactregistry.NewRepository(
			ctx, "oauth-user-inspector-images", &artifactregistry.RepositoryArgs{
				Project:      pulumi.String(project),
				Location:     pulumi.String(region),
				RepositoryId: pulumi.String("oauth-user-inspector"),
				Format:       pulumi.String("DOCKER"),
				Description:  pulumi.String("OAuth User Inspector container images (pushed by docker buildx from the deploy workflow)"),
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
			// The app reads GOOGLE_CLOUD_PROJECT to resolve the Secret Manager
			// project (server/server.ts). Cloud Run does not set it implicitly,
			// so inject it from the stack's project.
			&cloudrunv2.ServiceTemplateContainerEnvArgs{
				Name:  pulumi.String("GOOGLE_CLOUD_PROJECT"),
				Value: pulumi.String(project),
			},
		}

		service, err := cloudrunv2.NewService(
			ctx, "oauth-user-inspector", &cloudrunv2.ServiceArgs{
				Project:  pulumi.String(project),
				Location: pulumi.String(region),
				Name:     pulumi.String("oauth-user-inspector"),
				Template: &cloudrunv2.ServiceTemplateArgs{
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
			},
			// The Cloud Run service already exists (created by the old Cloud
			// Build deploy), so adopt it on first run.
			pulumi.Import(pulumi.ID(fmt.Sprintf("projects/%s/locations/%s/services/oauth-user-inspector", project, region))),
			// Ignore fields the old Cloud Build deploy set so they don't churn.
			pulumi.IgnoreChanges([]string{"client", "clientVersion", "launchStage", "annotations", "labels", "template.labels", "template.annotations"}),
			pulumi.DependsOn([]pulumi.Resource{repo}),
		)
		if err != nil {
			return err
		}

		// Public service: --allow-unauthenticated in the old deploy. Clients hit
		// the React frontend + Express backend directly; there is no upstream
		// auth proxy.
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
