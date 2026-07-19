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

// Package main is the per-environment deploy/runtime identity stack for
// oauth-user-inspector on the vitruviansoftware.dev foundation.
//
// Unlike the original personal-project bootstrap (which stood up its OWN Workload
// Identity Pool `github-actions-dev-1`), this stack federates the SHARED
// foundation-pool provisioned by gcp-bootstrap in prj-b-cicd. It creates the
// per-env deploy + runtime service accounts inside the env's oss project
// (prj-{env}-bu1-oss-floating), binds the deploy SA to the foundation-pool
// scoped to the `oauth-user-inspector-<env>` GitHub Environment (the provider's
// wif_attribute_condition already pins the repo, so environment scoping is the
// per-env isolation layer — mirroring the foundation's own per-stage
// attribute.environment principalSets), and grants least-privilege, per-app
// IAM. The runtime SA's Secret Manager access is
// conditioned to this app's SECRET_PREFIX so co-tenant OSS apps in the same oss
// project cannot read each other's secrets.
//
// Runs as sa-terraform-proj (folder-scoped serviceAccountAdmin + iam from Phase 1).
// Deploy: bazel run //oauth-user-inspector/infra/identity:up --stack <env>
package main

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const secretPrefix = "OAUTH_USER_INSPECTOR_"

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "oauth-user-inspector-deploy-identity")
		projectID := cfg.Require("project") // the env's oss project id
		bootstrapStack := cfg.Get("bootstrap_stack")
		if bootstrapStack == "" {
			bootstrapStack = "ipv1337/foundation-bootstrap/production"
		}
		projectsStack := cfg.Require("projects_stack") // ipv1337/foundation-projects-bu1-<env>/production

		// Shared foundation WIF pool (prj-b-cicd), from gcp-bootstrap.
		bootstrap, err := pulumi.NewStackReference(ctx, "bootstrap", &pulumi.StackReferenceArgs{
			Name: pulumi.String(bootstrapStack),
		})
		if err != nil {
			return err
		}
		poolName := bootstrap.GetStringOutput(pulumi.String("wif_pool_name"))

		// The env's oss project number (for the Secret Manager IAM condition).
		projStack, err := pulumi.NewStackReference(ctx, "projects", &pulumi.StackReferenceArgs{
			Name: pulumi.String(projectsStack),
		})
		if err != nil {
			return err
		}
		projectNumber := projStack.GetStringOutput(pulumi.String("oss_floating_project_number"))

		// Deploy SA — impersonated by CI to run `pulumi up` for the app stack.
		deploySA, err := serviceaccount.NewAccount(ctx, "deploy-sa", &serviceaccount.AccountArgs{
			Project:     pulumi.String(projectID),
			AccountId:   pulumi.String("oauth-user-inspector-deploy"),
			DisplayName: pulumi.String("oauth-user-inspector deploy (CI)"),
		})
		if err != nil {
			return err
		}
		// Runtime SA — the Cloud Run service identity.
		runtimeSA, err := serviceaccount.NewAccount(ctx, "runtime-sa", &serviceaccount.AccountArgs{
			Project:     pulumi.String(projectID),
			AccountId:   pulumi.String("oauth-user-inspector-rt"),
			DisplayName: pulumi.String("oauth-user-inspector runtime"),
		})
		if err != nil {
			return err
		}

		// Federate the deploy SA against the SHARED foundation-pool, scoped to
		// this env's GitHub Environment (`oauth-user-inspector-<env>`, created by
		// repo_config). The provider's wif_attribute_condition already pins
		// assertion.repository to VitruvianSoftware/vitruvian-core, so the
		// environment principalSet is the per-env isolation layer — the same
		// pattern gcp-bootstrap uses for its per-stage foundation-* Environments.
		if _, err := serviceaccount.NewIAMMember(ctx, "deploy-wif-binding", &serviceaccount.IAMMemberArgs{
			ServiceAccountId: deploySA.Name,
			Role:             pulumi.String("roles/iam.workloadIdentityUser"),
			Member: pulumi.Sprintf(
				"principalSet://iam.googleapis.com/%s/attribute.environment/oauth-user-inspector-%s",
				poolName, ctx.Stack(),
			),
		}); err != nil {
			return err
		}

		// Per-app least-privilege deploy IAM, scoped to the oss project.
		deployMember := pulumi.Sprintf("serviceAccount:%s", deploySA.Email)
		for _, r := range []struct{ name, role string }{
			{"deploy-role-run-admin", "roles/run.admin"},
			{"deploy-role-sa-user", "roles/iam.serviceAccountUser"},
			{"deploy-role-serviceusage", "roles/serviceusage.serviceUsageConsumer"},
			{"deploy-role-logging-viewer", "roles/logging.viewer"},
		} {
			if _, err := projects.NewIAMMember(ctx, r.name, &projects.IAMMemberArgs{
				Project: pulumi.String(projectID),
				Role:    pulumi.String(r.role),
				Member:  deployMember,
			}); err != nil {
				return err
			}
		}

		// Deploy SA: Secret Manager ADMIN conditioned to this app's prefix. The
		// zitadel-apps stack (applied by the same oauth-user-inspector-<env> CI
		// environment, i.e. as this deploy SA) syncs the minted OIDC client
		// id/secret into the oss project's Secret Manager under the prefix
		// (cred-sync-to-GCP-SM, spec §9). NOTE: secretmanager.secrets.CREATE is
		// authorized against the PROJECT resource, which a secret-prefix
		// condition cannot match — so the FIRST per-env apply (creating the two
		// secrets) runs as sa-terraform-proj (folder-scoped secretmanager.admin
		// from Phase 1); this grant covers everything after creation (version
		// adds on rotation, metadata reads/updates, drift refresh) without giving
		// the deploy SA reach into co-tenant apps' secrets.
		if _, err := projects.NewIAMMember(ctx, "deploy-role-secret-admin", &projects.IAMMemberArgs{
			Project: pulumi.String(projectID),
			Role:    pulumi.String("roles/secretmanager.admin"),
			Member:  deployMember,
			Condition: &projects.IAMMemberConditionArgs{
				Title:      pulumi.String("oauth-user-inspector-secrets-only"),
				Expression: pulumi.Sprintf("resource.name.startsWith(\"projects/%s/secrets/%s\")", projectNumber, secretPrefix),
			},
		}); err != nil {
			return err
		}

		// Runtime SA: Secret Manager access CONDITIONED to this app's prefix, so a
		// co-tenant app in the same oss project can't read another app's secrets.
		if _, err := projects.NewIAMMember(ctx, "runtime-role-secret-accessor", &projects.IAMMemberArgs{
			Project: pulumi.String(projectID),
			Role:    pulumi.String("roles/secretmanager.secretAccessor"),
			Member:  pulumi.Sprintf("serviceAccount:%s", runtimeSA.Email),
			Condition: &projects.IAMMemberConditionArgs{
				Title:      pulumi.String("oauth-user-inspector-secrets-only"),
				Expression: pulumi.Sprintf("resource.name.startsWith(\"projects/%s/secrets/%s\")", projectNumber, secretPrefix),
			},
		}); err != nil {
			return err
		}

		ctx.Export("deployServiceAccount", deploySA.Email)
		ctx.Export("runtimeServiceAccount", runtimeSA.Email)
		return nil
	})
}
