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

// Package main is the oauth-user-inspector shared build stack.
//
// It owns the cross-environment singletons that live in the foundation's
// infra-pipeline project (prj-c-bu1-infra-pipeline-*): the Artifact Registry
// repository that holds the app image, and the build identity that pushes to it.
// The image is built ONCE here and promoted by digest into each environment's
// Cloud Run service (dev/nonproduction/production), so this is a single stack
// (production only), not per-environment.
//
// It also grants each environment's Cloud Run service agent read access to the
// shared registry, since those services run in the per-env oss projects but pull
// the image from this shared registry.
//
// Deploy: bazel run //infrastructure/pulumi/apps/oauth-user-inspector-build:up
package main

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/artifactregistry"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "oauth-user-inspector-build")
		region := cfg.Get("region")
		if region == "" {
			region = "us-west1"
		}

		// The shared build project (prj-c-bu1-infra-pipeline-*) is created by
		// foundation stage 4's business_unit_1/shared leaf and exported there.
		projStack, err := pulumi.NewStackReference(ctx, "projects-shared", &pulumi.StackReferenceArgs{
			Name: pulumi.String("ipv1337/foundation-projects-bu1-shared/production"),
		})
		if err != nil {
			return err
		}
		buildProject := projStack.GetStringOutput(pulumi.String("infra_pipeline_project_id"))

		// 1. Shared Artifact Registry for the app image (build once, promote digest).
		ar, err := artifactregistry.NewRepository(ctx, "oauth-user-inspector-images", &artifactregistry.RepositoryArgs{
			Project:      buildProject,
			Location:     pulumi.String(region),
			RepositoryId: pulumi.String("oauth-user-inspector"),
			Format:       pulumi.String("DOCKER"),
			Description:  pulumi.String("oauth-user-inspector container images (build-once, promoted by digest)"),
		})
		if err != nil {
			return err
		}

		// 2. Build identity: the CI build job federates this SA (foundation-pool,
		//    build environment) and pushes images to the AR.
		buildSA, err := serviceaccount.NewAccount(ctx, "build-sa", &serviceaccount.AccountArgs{
			Project:     buildProject,
			AccountId:   pulumi.String("oauth-user-inspector-build"),
			DisplayName: pulumi.String("oauth-user-inspector image build/push"),
		})
		if err != nil {
			return err
		}
		if _, err := artifactregistry.NewRepositoryIamMember(ctx, "build-sa-ar-writer", &artifactregistry.RepositoryIamMemberArgs{
			Project:    buildProject,
			Location:   pulumi.String(region),
			Repository: ar.RepositoryId,
			Role:       pulumi.String("roles/artifactregistry.writer"),
			Member:     pulumi.Sprintf("serviceAccount:%s", buildSA.Email),
		}); err != nil {
			return err
		}

		// 3. Per-env Cloud Run service agent AR reader. Each env's oss project has a
		//    Cloud Run service agent (service-<projnum>@serverless-robot-prod...) that
		//    must pull the image from this shared registry. Project numbers come from
		//    the per-env foundation-projects business_unit_1 leaf stacks.
		for _, env := range []string{"development", "nonproduction", "production"} {
			s, err := pulumi.NewStackReference(ctx, "projects-"+env, &pulumi.StackReferenceArgs{
				Name: pulumi.String("ipv1337/foundation-projects-bu1-" + env + "/production"),
			})
			if err != nil {
				return err
			}
			num := s.GetStringOutput(pulumi.String("oss_floating_project_number"))
			if _, err := artifactregistry.NewRepositoryIamMember(ctx, "ar-reader-"+env, &artifactregistry.RepositoryIamMemberArgs{
				Project:    buildProject,
				Location:   pulumi.String(region),
				Repository: ar.RepositoryId,
				Role:       pulumi.String("roles/artifactregistry.reader"),
				Member:     pulumi.Sprintf("serviceAccount:service-%s@serverless-robot-prod.iam.gserviceaccount.com", num),
			}); err != nil {
				return err
			}
		}

		ctx.Export("artifact_registry", pulumi.Sprintf("%s-docker.pkg.dev/%s/oauth-user-inspector", region, buildProject))
		ctx.Export("build_service_account", buildSA.Email)
		return nil
	})
}
