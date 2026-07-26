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

package main

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/orgpolicy"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// GitHub Actions' OIDC issuer. Fixed by the vendor; not configurable.
const githubIssuerURI = "https://token.actions.githubusercontent.com"

// deployWIFIssuerPolicy sets the ONE folder-scoped policy that says which
// external OIDC issuers may back a workload identity provider in this
// foundation.
//
// ---------------------------------------------------------------------------
// WHY THIS IS ONE FUNCTION AND NOT TWO POLICIES
// ---------------------------------------------------------------------------
// `constraints/iam.workloadIdentityPoolProviders` denies all external issuers by
// default (a CFT security default), so every federation this stack builds needs
// its issuer named here first. The allowlist is a SINGLE resource --
// folders/<id>/policies/iam.workloadIdentityPoolProviders -- so it must be built
// as the UNION of every issuer the stack federates. A second orgpolicy.Policy
// for the same constraint would not add to the list; it would fight the first
// one for the same GCP resource, and the winner would depend on apply order.
//
// This was originally created inline by deployGitHubActionsBuild with GitHub's
// issuer hard-coded, which produced exactly the failure it was written to
// prevent as soon as a second federation arrived:
//
//	Error 400: Precondition check failed
//	"Org Policy violated for value: 'https://api.pulumi.com/oidc'."
//	subject: orgpolicy:projects/.../workloadIdentityPools/pulumi-esc-pool
//
// The pool, service account and bindings all created fine -- only the provider,
// the one resource that names an issuer, was refused.
//
// Ordering matters as much as content: the policy must exist BEFORE any
// provider that relies on it, so callers pass the returned resource to
// pulumi.DependsOn. Returning it (rather than creating providers here) keeps
// that dependency explicit at each call site.
//
// SECURITY NOTE: allowing an issuer here means any workload identity provider
// under this folder MAY be configured to trust it. It does not by itself grant
// anything -- the provider's audience condition and the service account's IAM
// bindings still decide who can exchange a token for what. Adding an issuer is
// nonetheless a deliberate widening of the folder's trust surface, which is why
// each one is gated on the config that actually uses it: no `github_owner`, no
// GitHub issuer; no `pulumi_esc_org`, no Pulumi issuer.
//
// Returns (nil, nil) when there is nothing to allow, or when deploying at the
// org root -- there we do not touch org policy at all, and it must be managed
// out of band.
func deployWIFIssuerPolicy(ctx *pulumi.Context, cfg *Config) (*orgpolicy.Policy, error) {
	if cfg.ParentType != "folder" {
		return nil, nil
	}

	// Order is deliberate and stable: a set that reorders between applies would
	// show a spurious diff on every preview.
	allowed := pulumi.StringArray{}
	if cfg.GitHubOwner != "" {
		allowed = append(allowed, pulumi.String(githubIssuerURI))
	}
	if cfg.PulumiESCOrg != "" {
		allowed = append(allowed, pulumi.String(pulumiESCIssuerURI))
	}
	if len(allowed) == 0 {
		return nil, nil
	}

	// The logical name stays "wif-github-issuer-allow" even though the policy is
	// no longer GitHub-only. Renaming it would make Pulumi delete and recreate the
	// policy, and for the window between those two operations the folder would
	// deny ALL issuers -- taking the foundation's GitHub Actions WIF down to
	// rename a string. The URN is an identity, not a description.
	policy, err := orgpolicy.NewPolicy(ctx, "wif-github-issuer-allow", &orgpolicy.PolicyArgs{
		Name:   pulumi.Sprintf("folders/%s/policies/iam.workloadIdentityPoolProviders", cfg.ParentID),
		Parent: pulumi.Sprintf("folders/%s", cfg.ParentID),
		Spec: &orgpolicy.PolicySpecArgs{
			Rules: orgpolicy.PolicySpecRuleArray{
				&orgpolicy.PolicySpecRuleArgs{
					Values: &orgpolicy.PolicySpecRuleValuesArgs{
						AllowedValues: allowed,
					},
				},
			},
		},
	})
	if err != nil {
		return nil, err
	}
	return policy, nil
}
