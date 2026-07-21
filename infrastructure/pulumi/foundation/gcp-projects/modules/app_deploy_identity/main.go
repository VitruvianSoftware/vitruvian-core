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

// Package app_deploy_identity issues the PLATFORM-OWNED deploy service account
// for one application in one environment, plus the grants that reach outside
// the application: project-level deploy roles and the Workload Identity
// Federation binding a GitHub Actions job impersonates.
//
// Why this lives in the foundation and not next to the app
// (docs/engineering/core-vs-application-infrastructure.md §4.1): creating the
// identity is harmless, but GRANTING it power over a project the application
// does not own is not. If an app can widen its own deploy permissions by
// editing its own repo, the review boundary and the trust boundary have come
// apart. Applications remain free to create additional service accounts of
// their own — those can only ever hold grants the app itself may make.
//
// WHY STAGE 4 AND NOT STAGE 5 — this is load-bearing, not filing.
// Upstream seeds the app-infra pipeline's service accounts in 4-projects
// (modules/single_project's sa_roles), one stage ABOVE the 5-app-infra
// workloads they deploy. That separation is what makes it safe for stage 5 to
// be deployed by that identity WITHOUT a reviewer gate: the identity cannot
// edit its own grants, because its grants live in a stage it does not deploy.
//
// Putting this module in stage 5 (as it briefly was, in #995) created a
// circularity: stage 5 would hold both the workload and the privileged
// identity, so either every routine app deploy needs a reviewer approval, or
// the app's own pipeline can edit the stack that defines its permissions.
// Neither is acceptable; moving it up one stage dissolves the choice.
//
// Upstream divergence (documented, per the port policy): upstream's pipeline
// SAs serve a VM + Cloud Build deploy model. Our stage-5 apps are serverless
// workloads on FLOATING projects deployed from GitHub Actions via WIF, so the
// identity federates the shared foundation-pool from gcp-bootstrap instead.
//
// ADOPTION NOTE: DeployServiceAccount is created with
// CreateIgnoreAlreadyExists so this module can take ownership of an account
// that already exists — the migration path for apps whose deploy SA was
// previously minted by their own stack. The app-side resource is dropped with
// retainOnDelete + a state delete, never a destroy: recreating a live deploy SA
// drops its WIF binding and breaks the app's pipeline.
package app_deploy_identity

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Deploy issues one application's deploy identity in one environment.
func Deploy(ctx *pulumi.Context, name string, args *Args) (*Result, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}
	if args.App == "" {
		return nil, fmt.Errorf("App is required")
	}
	if args.WorkloadIdentityPool == nil {
		return nil, fmt.Errorf("WorkloadIdentityPool is required (from the gcp-bootstrap stack)")
	}
	if args.GitHubEnvironment == "" {
		return nil, fmt.Errorf("GitHubEnvironment is required (the per-env isolation layer)")
	}

	accountID := args.DeployAccountID
	if accountID == "" {
		accountID = args.App + "-deploy"
	}

	// 1. The deploy service account. CreateIgnoreAlreadyExists lets this module
	// ADOPT an account an app stack previously owned (see the package note).
	sa, err := serviceaccount.NewAccount(ctx, name+"-deploy-sa", &serviceaccount.AccountArgs{
		AccountId:                 pulumi.String(accountID),
		DisplayName:               pulumi.Sprintf("%s deploy identity (%s)", args.App, args.Env),
		Description:               pulumi.String("Platform-issued. Impersonated by GitHub Actions via WIF; grants authored in foundation/gcp-projects."),
		Project:                   args.ProjectID,
		CreateIgnoreAlreadyExists: pulumi.Bool(true),
	})
	if err != nil {
		return nil, err
	}

	// 2. Project-level deploy roles. These are the grants that reach outside the
	// application, which is precisely why they are authored here.
	for _, role := range args.DeployRoles {
		if _, err := projects.NewIAMMember(ctx, fmt.Sprintf("%s-deploy-%s", name, sanitize(role)), &projects.IAMMemberArgs{
			Project: args.ProjectID,
			Role:    pulumi.String(role),
			Member:  sa.Email.ApplyT(func(e string) string { return "serviceAccount:" + e }).(pulumi.StringOutput),
		}); err != nil {
			return nil, err
		}
	}

	// 3. WIF: let this app's per-env GitHub Environment impersonate the SA. The
	// pool is the shared foundation-pool from gcp-bootstrap — apps never mint
	// their own. The provider's attribute condition already pins
	// assertion.repository to the monorepo, so the ENVIRONMENT principalSet is
	// the per-env isolation layer (same pattern gcp-bootstrap uses for its
	// per-stage foundation-* Environments). This member string is replicated
	// EXACTLY from the app-side stack being adopted — changing it would revoke
	// the running pipeline's ability to deploy.
	if _, err := serviceaccount.NewIAMMember(ctx, name+"-wif-impersonation", &serviceaccount.IAMMemberArgs{
		ServiceAccountId: sa.Name,
		Role:             pulumi.String("roles/iam.workloadIdentityUser"),
		Member: pulumi.Sprintf("principalSet://iam.googleapis.com/%s/attribute.environment/%s",
			args.WorkloadIdentityPool, args.GitHubEnvironment),
	}); err != nil {
		return nil, err
	}

	return &Result{
		DeployServiceAccountEmail: sa.Email,
		DeployServiceAccountName:  sa.Name,
	}, nil
}

// sanitize turns an IAM role into a stable, unique Pulumi resource-name suffix
// ("roles/run.admin" -> "run-admin").
func sanitize(role string) string {
	out := make([]rune, 0, len(role))
	for _, r := range role {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			out = append(out, r)
		case len(out) > 0 && out[len(out)-1] != '-':
			out = append(out, '-')
		}
	}
	return string(out)
}
