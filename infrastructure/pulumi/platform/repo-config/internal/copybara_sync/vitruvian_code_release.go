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

package copybara_sync

import (
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// vitruvianCodeReleaseEnvironmentName is the GitHub Environment the package job
// of VitruvianSoftware/vitruvian-code's .github/workflows/release.yml binds. It
// holds the Apple Developer ID signing certificate and App Store Connect notary
// API key (VITRUVIAN_SIGNING_CERT_P12, VITRUVIAN_SIGNING_CERT_PASSWORD,
// VITRUVIAN_NOTARY_API_KEY_P8, VITRUVIAN_NOTARY_KEY_ID,
// VITRUVIAN_NOTARY_ISSUER_ID) as environment secrets, so only that job can read
// them.
const vitruvianCodeReleaseEnvironmentName = "vitruvian-code-release"

// vitruvianCodeReleaseEnvironment declares the environment and its single
// deployment policy on the vitruvian-code repository. Only branch main may
// deploy to it because release.yml runs exclusively on push to main (when
// Copybara exports a release-please version bump). As with vitruvian_courier_release.go,
// the secret values themselves live out of git and are pushed idempotently with
// `REPO=VitruvianSoftware/vitruvian-code bazel run //tools/sync-env-secrets:apply -- vitruvian-code-release`
// so CI applies of repo-config never wipe them. No required reviewer: the
// monorepo release-please PR merge is the human gate.
func vitruvianCodeReleaseEnvironment(ctx *pulumi.Context, repo *github.Repository) error {
	env, err := github.NewRepositoryEnvironment(ctx, vitruvianCodeReleaseEnvironmentName, &github.RepositoryEnvironmentArgs{
		Repository:  repo.Name,
		Environment: pulumi.String(vitruvianCodeReleaseEnvironmentName),
		DeploymentBranchPolicy: &github.RepositoryEnvironmentDeploymentBranchPolicyArgs{
			ProtectedBranches:    pulumi.Bool(false),
			CustomBranchPolicies: pulumi.Bool(true),
		},
	}, pulumi.DependsOn([]pulumi.Resource{repo}))
	if err != nil {
		return err
	}
	_, err = github.NewRepositoryEnvironmentDeploymentPolicy(ctx, vitruvianCodeReleaseEnvironmentName+"-deploy-policy-main", &github.RepositoryEnvironmentDeploymentPolicyArgs{
		Repository:    repo.Name,
		Environment:   env.Environment,
		BranchPattern: pulumi.String("main"),
	}, pulumi.DependsOn([]pulumi.Resource{env}))
	return err
}
