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

// OAuth User Inspector deploy identity bootstrap: the GitHub Actions Workload
// Identity Federation (WIF) pool + provider, the keyless deploy service account
// the deploy workflow impersonates via WIF, and the least-privilege runtime
// service account the Cloud Run service runs as.
//
// Keyless CI: GitHub Actions presents its OIDC token to the WIF provider, which
// (gated on the repository claim) lets the workflow impersonate the deploy SA.
// The deploy SA holds the project roles needed to build/push images and roll out
// Cloud Run; the runtime SA only holds Secret Manager accessor (the app reads its
// OAuth client credentials from Secret Manager at runtime). The app stack
// (infrastructure/pulumi/oauth-user-inspector) consumes the runtime SA email via
// config and runs the service as it.
//
// Deploy: bazel run //infrastructure/pulumi/oauth-user-inspector-deploy-identity:up
package main

import (
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/iam"
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "oauth-user-inspector-deploy-identity")
		project := cfg.Require("project")
		region := cfg.Get("region")
		if region == "" {
			region = "us-west1"
		}
		repo := cfg.Get("repository")
		if repo == "" {
			repo = "VitruvianSoftware/vitruvian-core"
		}

		// Workload Identity pool that trusts GitHub Actions OIDC tokens.
		pool, err := iam.NewWorkloadIdentityPool(ctx, "github-actions-pool", &iam.WorkloadIdentityPoolArgs{
			Project:                pulumi.String(project),
			WorkloadIdentityPoolId: pulumi.String("github-actions-dev-1"),
			DisplayName:            pulumi.String("GitHub Actions"),
			Description:            pulumi.String("Workload Identity pool for GitHub Actions (oauth-user-inspector deploys)"),
		})
		if err != nil {
			return err
		}

		// OIDC provider: maps GitHub's token claims and restricts federation to
		// the monorepo via the attribute condition (assertion.repository == repo).
		provider, err := iam.NewWorkloadIdentityPoolProvider(ctx, "github-actions-provider", &iam.WorkloadIdentityPoolProviderArgs{
			Project:                        pulumi.String(project),
			WorkloadIdentityPoolId:         pool.WorkloadIdentityPoolId,
			WorkloadIdentityPoolProviderId: pulumi.String("github-actions-dev"),
			DisplayName:                    pulumi.String("GitHub Actions Provider"),
			AttributeMapping: pulumi.StringMap{
				"google.subject":       pulumi.String("assertion.sub"),
				"attribute.repository": pulumi.String("assertion.repository"),
			},
			AttributeCondition: pulumi.Sprintf("assertion.repository == %q", repo),
			Oidc: &iam.WorkloadIdentityPoolProviderOidcArgs{
				IssuerUri: pulumi.String("https://token.actions.githubusercontent.com"),
			},
		})
		if err != nil {
			return err
		}

		// Keyless deploy identity impersonated by GitHub Actions via WIF.
		deploySA, err := serviceaccount.NewAccount(ctx, "deploy-sa", &serviceaccount.AccountArgs{
			Project:     pulumi.String(project),
			AccountId:   pulumi.String("github-actions-dev"),
			DisplayName: pulumi.String("GitHub Actions deploy (oauth-user-inspector)"),
		})
		if err != nil {
			return err
		}

		// Least-privilege runtime identity for the Cloud Run service (consumed by
		// the app stack via the runtimeServiceAccount config).
		runtimeSA, err := serviceaccount.NewAccount(ctx, "runtime-sa", &serviceaccount.AccountArgs{
			Project:     pulumi.String(project),
			AccountId:   pulumi.String("oauth-user-inspector"),
			DisplayName: pulumi.String("OAuth User Inspector runtime"),
		})
		if err != nil {
			return err
		}

		// Project roles the deploy workflow needs to build/push the image and
		// roll out the Cloud Run service. Distinct resource names per role.
		deployMember := pulumi.Sprintf("serviceAccount:%s", deploySA.Email)

		_, err = projects.NewIAMMember(ctx, "deploy-role-run-admin", &projects.IAMMemberArgs{
			Project: pulumi.String(project),
			Role:    pulumi.String("roles/run.admin"),
			Member:  deployMember,
		})
		if err != nil {
			return err
		}

		_, err = projects.NewIAMMember(ctx, "deploy-role-artifactregistry-admin", &projects.IAMMemberArgs{
			Project: pulumi.String(project),
			Role:    pulumi.String("roles/artifactregistry.admin"),
			Member:  deployMember,
		})
		if err != nil {
			return err
		}

		_, err = projects.NewIAMMember(ctx, "deploy-role-service-account-user", &projects.IAMMemberArgs{
			Project: pulumi.String(project),
			Role:    pulumi.String("roles/iam.serviceAccountUser"),
			Member:  deployMember,
		})
		if err != nil {
			return err
		}

		_, err = projects.NewIAMMember(ctx, "deploy-role-service-usage-consumer", &projects.IAMMemberArgs{
			Project: pulumi.String(project),
			Role:    pulumi.String("roles/serviceusage.serviceUsageConsumer"),
			Member:  deployMember,
		})
		if err != nil {
			return err
		}

		_, err = projects.NewIAMMember(ctx, "deploy-role-logging-viewer", &projects.IAMMemberArgs{
			Project: pulumi.String(project),
			Role:    pulumi.String("roles/logging.viewer"),
			Member:  deployMember,
		})
		if err != nil {
			return err
		}

		// Runtime SA reads OAuth client credentials from Secret Manager.
		_, err = projects.NewIAMMember(ctx, "runtime-role-secret-accessor", &projects.IAMMemberArgs{
			Project: pulumi.String(project),
			Role:    pulumi.String("roles/secretmanager.secretAccessor"),
			Member:  pulumi.Sprintf("serviceAccount:%s", runtimeSA.Email),
		})
		if err != nil {
			return err
		}

		// Allow the GitHub Actions principal set (scoped to the monorepo) to
		// impersonate the deploy SA via Workload Identity Federation.
		_, err = serviceaccount.NewIAMMember(ctx, "deploy-wif-binding", &serviceaccount.IAMMemberArgs{
			ServiceAccountId: deploySA.Name,
			Role:             pulumi.String("roles/iam.workloadIdentityUser"),
			Member:           pulumi.Sprintf("principalSet://iam.googleapis.com/%s/attribute.repository/%s", pool.Name, repo),
		})
		if err != nil {
			return err
		}

		ctx.Export("workloadIdentityProvider", provider.Name)
		ctx.Export("deployServiceAccount", deploySA.Email)
		ctx.Export("runtimeServiceAccount", runtimeSA.Email)
		return nil
	})
}
