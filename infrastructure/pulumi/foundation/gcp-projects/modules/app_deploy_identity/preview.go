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

// preview.go issues the READ-ONLY identity an application's advisory
// `pulumi preview` on a pull request runs as (#4120).
//
// WHY A SEPARATE IDENTITY
// -----------------------
// The deploy SA (Deploy, main.go) is bound to the app's per-env GitHub
// Environment, e.g. tabula-development. Nothing on the Google side checks the
// branch: the WIF provider pins only the repository, so the Environment's
// branch policy is the only ref check. The PR preview job must run on unmerged
// branches, so while it uses the deploy Environment that Environment cannot be
// pinned to main, and ANY unmerged branch can deploy as the app and read its
// secrets.
//
// This identity breaks that knot. The preview job moves to its own
// <app>-preview Environment, bound to THIS identity, which can read but not
// change anything. The deploy Environment can then be pinned to main.
//
// WHY READ-ONLY IS ENFORCED HERE RATHER THAN DOCUMENTED
// -----------------------------------------------------
// This identity is reachable from any unmerged branch BY DESIGN, so every role
// it holds is effectively granted to every branch author. The roles are checked
// against an allowlist instead of passed through: a config edit that adds
// roles/run.admin or a secret accessor fails the preview instead of silently
// re-opening the hole this identity exists to close.
//
// roles/viewer is enough because the app stacks make no data-source reads at
// preview time (no Secret Manager lookups; the Cloudflare zone id is pinned)
// and the preview runs without --refresh. roles/viewer does NOT include
// secretmanager.versions.access, so secret VALUES stay unreadable.
package app_deploy_identity

import (
	"fmt"
	"sort"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// previewEnvironmentSuffix is the suffix every preview GitHub Environment must
// carry. Binding a preview identity to the deploy Environment
// (<app>-development) would leave the hole open, so it is refused outright.
const previewEnvironmentSuffix = "-preview"

// previewAllowedRoles is the complete set DeployPreview will grant. Every entry
// is read-only and none can read a secret's value.
var previewAllowedRoles = map[string]bool{
	"roles/viewer": true,
}

// defaultPreviewRoles is what an advisory `pulumi preview` of an app stack needs.
var defaultPreviewRoles = []string{"roles/viewer"}

// PreviewArgs configures one application's read-only preview identity.
type PreviewArgs struct {
	// App is the application name. It seeds the default account id
	// (<App>-preview).
	App string
	// Env is the environment whose project this identity reads (display only).
	Env string
	// ProjectID is the app-hosting project the preview reads.
	ProjectID pulumi.StringInput
	// AccountID overrides the default <App>-preview account id.
	AccountID string
	// Roles to grant on ProjectID. Empty means defaultPreviewRoles. Every role
	// must be in previewAllowedRoles.
	Roles []string
	// WorkloadIdentityPool is the FULL pool resource name from gcp-bootstrap.
	WorkloadIdentityPool pulumi.StringInput
	// GitHubEnvironment is the GitHub Environment allowed to impersonate this
	// identity, e.g. "tabula-preview". Must end in "-preview".
	GitHubEnvironment string
}

// PreviewResult is what the leaf exports so repo-config can set the preview
// Environment's GCP_DEPLOY_SERVICE_ACCOUNT variable.
type PreviewResult struct {
	ServiceAccountEmail pulumi.StringOutput
	ServiceAccountName  pulumi.StringOutput
}

// validatePreview checks args and returns the resolved account id and roles.
// Pure, so the refusals are testable without a Pulumi engine.
func validatePreview(args *PreviewArgs) (string, []string, error) {
	if args == nil {
		return "", nil, fmt.Errorf("args is required")
	}
	if args.App == "" {
		return "", nil, fmt.Errorf("App is required")
	}
	if args.ProjectID == nil {
		return "", nil, fmt.Errorf("ProjectID is required")
	}
	if args.WorkloadIdentityPool == nil {
		return "", nil, fmt.Errorf("WorkloadIdentityPool is required (from the gcp-bootstrap stack)")
	}
	if !strings.HasSuffix(args.GitHubEnvironment, previewEnvironmentSuffix) ||
		args.GitHubEnvironment == previewEnvironmentSuffix {
		return "", nil, fmt.Errorf(
			"preview identity for %q: GitHubEnvironment %q must be a dedicated <name>%s Environment, "+
				"never the deploy Environment, or unmerged branches keep deploy-level access (#4120)",
			args.App, args.GitHubEnvironment, previewEnvironmentSuffix,
		)
	}

	accountID := args.AccountID
	if accountID == "" {
		accountID = args.App + "-preview"
	}
	// GCP account ids are 6-30 characters; fail at preview, not at apply.
	if n := len(accountID); n < 6 || n > 30 {
		return "", nil, fmt.Errorf("preview account id %q is %d characters; GCP allows 6-30 (set AccountID)", accountID, n)
	}

	roles := args.Roles
	if len(roles) == 0 {
		roles = defaultPreviewRoles
	}
	for _, role := range roles {
		if !previewAllowedRoles[role] {
			return "", nil, fmt.Errorf(
				"preview identity for %q: role %q is not allowed; this identity is reachable from any "+
					"unmerged branch, so it may hold only %s",
				args.App, role, strings.Join(sortedPreviewRoles(), ", "),
			)
		}
	}
	return accountID, roles, nil
}

// DeployPreview issues one application's read-only preview identity: the
// service account, its read-only project roles, and the WIF binding that lets
// the <app>-preview GitHub Environment impersonate it.
//
// Resource names use a "-preview-" infix so they never collide with the deploy
// identity's (name+"-deploy-*", name+"-wif-impersonation").
func DeployPreview(ctx *pulumi.Context, name string, args *PreviewArgs) (*PreviewResult, error) {
	accountID, roles, err := validatePreview(args)
	if err != nil {
		return nil, err
	}

	sa, err := serviceaccount.NewAccount(ctx, name+"-preview-sa", &serviceaccount.AccountArgs{
		AccountId:   pulumi.String(accountID),
		DisplayName: pulumi.Sprintf("%s preview identity (%s, read-only)", args.App, args.Env),
		Description: pulumi.String("Platform-issued, READ-ONLY. Impersonated by the PR pulumi-preview job via WIF from the " +
			args.GitHubEnvironment + " Environment; grants authored in foundation/gcp-projects (#4120)."),
		Project: args.ProjectID,
	})
	if err != nil {
		return nil, err
	}

	member := sa.Email.ApplyT(func(e string) string { return "serviceAccount:" + e }).(pulumi.StringOutput)
	for _, role := range roles {
		if _, err := projects.NewIAMMember(ctx, fmt.Sprintf("%s-preview-%s", name, sanitize(role)), &projects.IAMMemberArgs{
			Project: args.ProjectID,
			Role:    pulumi.String(role),
			Member:  member,
		}); err != nil {
			return nil, err
		}
	}

	if _, err := serviceaccount.NewIAMMember(ctx, name+"-preview-wif-impersonation", &serviceaccount.IAMMemberArgs{
		ServiceAccountId: sa.Name,
		Role:             pulumi.String("roles/iam.workloadIdentityUser"),
		Member: pulumi.Sprintf("principalSet://iam.googleapis.com/%s/attribute.environment/%s",
			args.WorkloadIdentityPool, args.GitHubEnvironment),
	}); err != nil {
		return nil, err
	}

	return &PreviewResult{ServiceAccountEmail: sa.Email, ServiceAccountName: sa.Name}, nil
}

func sortedPreviewRoles() []string {
	out := make([]string, 0, len(previewAllowedRoles))
	for r := range previewAllowedRoles {
		out = append(out, r)
	}
	sort.Strings(out)
	return out
}
