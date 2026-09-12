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
// This stack owns only what the APPLICATION may grant itself. It creates the
// RUNTIME service account inside the env's oss project
// (prj-{env}-bu1-oss-floating), with Secret Manager access conditioned to this
// app's SECRET_PREFIX so co-tenant OSS apps in the same project cannot read
// each other's secrets.
//
// The DEPLOY identity is deliberately NOT here. It is platform-issued by
// stage-4 foundation/gcp-projects (modules/app_deploy_identity), one stage above
// the workloads it deploys, so this app cannot widen its own deploy permissions
// by editing its own repo — see
// docs/engineering/core-vs-application-infrastructure.md §4.1. That covers the
// account itself, its project roles (including the prefix-conditioned
// secretmanager.admin) and the foundation-pool WIF binding. This stack merely
// re-exports the resulting email for convenience.
//
// The Cloudflare-token accessors below stay app-side: they are per-secret grants
// on this app's own token, which the app may make for itself.
//
// Runs as sa-terraform-proj (folder-scoped serviceAccountAdmin + iam from Phase 1).
// Deploy: bazel run //oauth-user-inspector/infra/identity:up --stack <env>
package main

import (
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/secretmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const secretPrefix = "OAUTH_USER_INSPECTOR_"

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "oauth-user-inspector-deploy-identity")
		projectID := cfg.Require("project")            // the env's oss project id
		projectsStack := cfg.Require("projects_stack") // ipv1337/foundation-projects-bu1-<env>/production

		// The env's oss project number (for the Secret Manager IAM condition).
		projStack, err := pulumi.NewStackReference(ctx, "projects", &pulumi.StackReferenceArgs{
			Name: pulumi.String(projectsStack),
		})
		if err != nil {
			return err
		}
		projectNumber := projStack.GetStringOutput(pulumi.String("oss_floating_project_number"))

		// Runtime SA — the Cloud Run service identity.
		runtimeSA, err := serviceaccount.NewAccount(ctx, "runtime-sa", &serviceaccount.AccountArgs{
			Project:     pulumi.String(projectID),
			AccountId:   pulumi.String("oauth-user-inspector-rt"),
			DisplayName: pulumi.String("oauth-user-inspector runtime"),
		})
		if err != nil {
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

		// --- Custom-domain verification anchoring (dev-only, config-gated) ---
		// Each env's deploy job runs tools/ci/ensure-site-verification.sh AS
		// ITS OWN DEPLOY SA (the _deploy-cloud-run.yaml "Ensure custom-domain
		// ownership" step): the SA SELF-verifies the Cloudflare zone via Site
		// Verification DNS-TXT (the Cloud Run DomainMapping precondition).
		// Ownership in that service is PER-CALLER and owner delegation is a
		// dead end (the API refuses owners-list writes while an external
		// token-verified owner is present), so all three env SAs verify
		// independently — three google-site-verification TXT records on the
		// zone apex is the expected steady state.
		//
		// The ONE resource anchored here is a secretAccessor grant on the
		// human-seeded CLOUDFLARE_API_TOKEN secret in THIS (dev) project for
		// every env's deploy SA (emails derived from cloudflareTokenAccessorProjects):
		// the token is stored ONCE, in the dev project's Secret Manager (secrets
		// model §pipeline-env — no GitHub secret), and each env's deploy job
		// reads it at runtime for the verification step and the app stack's
		// Cloudflare provider (the per-env grey-cloud CNAME stays in Pulumi). The
		// secret RESOURCE itself is deliberately unmanaged here — only its IAM is
		// code. It does not match the OAUTH_USER_INSPECTOR_ prefix condition
		// above, hence these explicit secret-scoped grants.
		//
		// siteverification.googleapis.com is NOT enabled here. The getToken/insert
		// WRITE calls DO require it enabled on the CALLING SA's quota project
		// (each env's own floating project; the script pins it via
		// SITEVERIFY_QUOTA_PROJECT/x-goog-user-project) — but that enable lives
		// in the FOUNDATION project factory's ActivateApis for every
		// prj-{env}-bu1-oss-floating project (gcp-projects
		// modules/base_env/example_floating_project.go), declared as the
		// project OWNER exactly like every other API on these projects, PLUS a
		// one-time manual console enable per project (the API is console-only).
		// An additive gcp.projects.Service here, applied as the app's deploy /
		// foundation-proj SA, lacks serviceusage.services.enable on the project
		// (only creator-time enable at stage-4), which is why PR #949's attempt
		// 403'd. Enabling one more API the app's OWN project needs, in that
		// project's own foundation-managed API list, is normal project config —
		// not the shared-infra-pipeline coupling objected to in #938.
		if cfg.GetBool("domainVerificationAnchor") {
			for _, p := range strings.Split(cfg.Get("cloudflareTokenAccessorProjects"), ",") {
				p = strings.TrimSpace(p)
				if p == "" {
					continue
				}
				if _, err := secretmanager.NewSecretIamMember(ctx, "cf-token-accessor-"+p, &secretmanager.SecretIamMemberArgs{
					Project:  pulumi.String(projectID),
					SecretId: pulumi.String("CLOUDFLARE_API_TOKEN"),
					Role:     pulumi.String("roles/secretmanager.secretAccessor"),
					Member:   pulumi.Sprintf("serviceAccount:oauth-user-inspector-deploy@%s.iam.gserviceaccount.com", p),
				}); err != nil {
					return err
				}
			}
		}

		// The deploy SA is now issued by stage-4 gcp-projects (§4.1); re-export it
		// from there so existing consumers of this stack keep working.
		ctx.Export("deployServiceAccount", projStack.GetStringOutput(pulumi.String("oauth-user-inspector_deploy_service_account")))
		ctx.Export("runtimeServiceAccount", runtimeSA.Email)
		return nil
	})
}
