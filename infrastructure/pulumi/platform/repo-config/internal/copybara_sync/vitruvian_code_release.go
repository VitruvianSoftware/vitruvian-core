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
	"fmt"

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

// vitruvianCodeReleaseTagPattern matches the mirror's v<version> release tags.
const vitruvianCodeReleaseTagPattern = "v*"

// vitruvianCodeReleaseDeployRefs are the only refs that may deploy to it: main
// (when Copybara exports a release-please version bump to main) and the
// mirror's v* release tags.
var vitruvianCodeReleaseDeployRefs = []struct {
	suffix  string
	branch  string
	tagGlob string
}{
	{suffix: "main", branch: "main"},
	{suffix: "tags", tagGlob: vitruvianCodeReleaseTagPattern},
}

// vitruvianCodeReleaseEnvironment declares the environment and its deployment
// policies on the vitruvian-code repository. As with courier_release.go, the
// secret values themselves live out of git and are pushed idempotently with
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
	for _, ref := range vitruvianCodeReleaseDeployRefs {
		args := &github.RepositoryEnvironmentDeploymentPolicyArgs{
			Repository:  repo.Name,
			Environment: env.Environment,
		}
		if ref.branch != "" {
			args.BranchPattern = pulumi.String(ref.branch)
		} else {
			args.TagPattern = pulumi.String(ref.tagGlob)
		}
		name := fmt.Sprintf("%s-deploy-policy-%s", vitruvianCodeReleaseEnvironmentName, ref.suffix)
		if _, err := github.NewRepositoryEnvironmentDeploymentPolicy(ctx, name, args, pulumi.DependsOn([]pulumi.Resource{env})); err != nil {
			return err
		}
	}
	return nil
}
