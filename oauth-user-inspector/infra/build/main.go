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
// The build SA is federated against the SHARED foundation-pool (gcp-bootstrap),
// scoped to the `oauth-user-inspector-build` GitHub Environment — the same
// pattern as the per-env deploy SAs in oauth-user-inspector-deploy-identity.
// The CI build job (oauth-user-inspector-deploy.yaml, `build` job) impersonates
// it keylessly to docker-push into the registry.
//
// Deploy: CI-only — .github/workflows/oauth-user-inspector-build-stack.yaml
// applies this stack as sa-terraform-proj (the stage-4 projects SA, via the
// foundation-proj-shared GitHub Environment). The build SA this stack CREATES
// cannot be the identity that APPLIES it, and sa-terraform-proj already owns
// prj-c-bu1-infra-pipeline-* (folder-scoped artifactregistry.admin +
// iam.serviceAccountAdmin from gcp-bootstrap), so no extra grants are needed.
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
		bootstrapStack := cfg.Get("bootstrap_stack")
		if bootstrapStack == "" {
			bootstrapStack = "ipv1337/foundation-bootstrap/production"
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

		// Shared foundation WIF pool (prj-b-cicd), from gcp-bootstrap — same
		// reference the deploy-identity stacks use.
		bootstrap, err := pulumi.NewStackReference(ctx, "bootstrap", &pulumi.StackReferenceArgs{
			Name: pulumi.String(bootstrapStack),
		})
		if err != nil {
			return err
		}
		poolName := bootstrap.GetStringOutput(pulumi.String("wif_pool_name"))

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
		// Federate the build SA against the SHARED foundation-pool, scoped to
		// the `oauth-user-inspector-build` GitHub Environment (created by
		// repo_config). The provider's wif_attribute_condition already pins
		// assertion.repository to VitruvianSoftware/vitruvian-core, so the
		// environment principalSet is the isolation layer — the same pattern as
		// the per-env deploy SAs in oauth-user-inspector-deploy-identity.
		// Without this binding the CI build job's google-github-actions/auth
		// impersonation of the build SA is refused.
		if _, err := serviceaccount.NewIAMMember(ctx, "build-wif-binding", &serviceaccount.IAMMemberArgs{
			ServiceAccountId: buildSA.Name,
			Role:             pulumi.String("roles/iam.workloadIdentityUser"),
			Member: pulumi.Sprintf(
				"principalSet://iam.googleapis.com/%s/attribute.environment/oauth-user-inspector-build",
				poolName,
			),
		}); err != nil {
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

		// 3. Per-env AR readers on this shared registry. Two identities per env
		//    need read access:
		//      a) the Cloud Run service agent (service-<projnum>@serverless-robot-prod)
		//         PULLS the image at runtime; and
		//      b) the per-env deploy SA (oauth-user-inspector-deploy@<oss project>)
		//         which runs `pulumi up` — Cloud Run validates image access as the
		//         DEPLOYING principal on service create, so without this the create
		//         fails with `artifactregistry.repositories.downloadArtifacts denied`.
		//    Project number + id come from the per-env foundation-projects leaf.
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
			// The stage-5 (gcp-app-infra) pipeline SA now performs the Cloud
			// Run deploy for adopted workloads, so IT needs to pull the image
			// too. A cross-project AR pull needs BOTH the Cloud Run service
			// agent AND the deploying identity to have reader — the service
			// agent is granted just above, and without this the apply fails
			// 403 artifactregistry.repositories.downloadArtifacts.
			//
			// Authored here only because this stack still owns the repo IAM.
			// It belongs in the foundation with the rest of the repo's grants;
			// an app stack granting a FOUNDATION identity access to a
			// foundation-project resource is exactly the inversion
			// core-vs-application-infrastructure.md §3 test 4 rules out.
			appInfraSA := s.GetStringOutput(pulumi.String("app_infra_pipeline_service_account"))
			if _, err := artifactregistry.NewRepositoryIamMember(ctx, "ar-reader-app-infra-"+env, &artifactregistry.RepositoryIamMemberArgs{
				Project:    buildProject,
				Location:   pulumi.String(region),
				Repository: ar.RepositoryId,
				Role:       pulumi.String("roles/artifactregistry.reader"),
				Member:     pulumi.Sprintf("serviceAccount:%s", appInfraSA),
			}); err != nil {
				return err
			}
			ossProject := s.GetStringOutput(pulumi.String("oss_floating_project"))
			if _, err := artifactregistry.NewRepositoryIamMember(ctx, "ar-reader-deploy-"+env, &artifactregistry.RepositoryIamMemberArgs{
				Project:    buildProject,
				Location:   pulumi.String(region),
				Repository: ar.RepositoryId,
				Role:       pulumi.String("roles/artifactregistry.reader"),
				Member:     pulumi.Sprintf("serviceAccount:oauth-user-inspector-deploy@%s.iam.gserviceaccount.com", ossProject),
			}); err != nil {
				return err
			}
		}

		ctx.Export("artifact_registry", pulumi.Sprintf("%s-docker.pkg.dev/%s/oauth-user-inspector", region, buildProject))
		ctx.Export("build_service_account", buildSA.Email)
		return nil
	})
}
