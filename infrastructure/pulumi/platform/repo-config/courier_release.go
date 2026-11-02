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
	"fmt"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// courierReleaseEnvironmentName is the GitHub Environment the publishing job of
// .github/workflows/courier-release.yaml binds. It holds Courier's Telegram app
// ID (COURIER_TELEGRAM_API_ID, COURIER_TELEGRAM_API_HASH) as environment
// secrets, so only that job can read them.
const courierReleaseEnvironmentName = "courier-release"

// courierReleaseDeployRefs are the only refs that may deploy to it: main (a
// release-please release is published from a push to main) and Courier's
// release tags (a re-run dispatched on the tag).
var courierReleaseDeployRefs = []struct {
	suffix  string
	branch  string
	tagGlob string
}{
	{suffix: "main", branch: "main"},
	{suffix: "tags", tagGlob: courierReleaseTagPattern},
}

// courierReleaseEnvironment declares the environment and its deployment
// policies. The secrets themselves are NOT managed here, for the reason
// oauthEnvironment gives: this program is applied both locally and by CI
// against one state, and a value that exists only in a gitignored local file
// would be deleted by the next CI apply. //tools/sync-env-secrets sets them
// (`apply -- courier-release`). No reviewer: the release-please PR merging is
// the human gate, as for the other desktop apps' releases.
func courierReleaseEnvironment(ctx *pulumi.Context, repo *github.Repository) error {
	env, err := github.NewRepositoryEnvironment(ctx, courierReleaseEnvironmentName, &github.RepositoryEnvironmentArgs{
		Repository:  repo.Name,
		Environment: pulumi.String(courierReleaseEnvironmentName),
		DeploymentBranchPolicy: &github.RepositoryEnvironmentDeploymentBranchPolicyArgs{
			ProtectedBranches:    pulumi.Bool(false),
			CustomBranchPolicies: pulumi.Bool(true),
		},
	})
	if err != nil {
		return err
	}
	for _, ref := range courierReleaseDeployRefs {
		args := &github.RepositoryEnvironmentDeploymentPolicyArgs{
			Repository:  repo.Name,
			Environment: env.Environment,
		}
		if ref.branch != "" {
			args.BranchPattern = pulumi.String(ref.branch)
		} else {
			args.TagPattern = pulumi.String(ref.tagGlob)
		}
		name := fmt.Sprintf("%s-deploy-policy-%s", courierReleaseEnvironmentName, ref.suffix)
		if _, err := github.NewRepositoryEnvironmentDeploymentPolicy(ctx, name, args, pulumi.DependsOn([]pulumi.Resource{env})); err != nil {
			return err
		}
	}
	return nil
}
