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
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// stripeSandboxEnvironmentName is the GitHub Environment the stripe-sandbox job
// of .github/workflows/delivery-stripe.yaml binds. It holds the Stripe
// sandbox's test-mode secret key as the environment secret STRIPE_API_KEY, so
// only that job can read it. The job refuses anything that is not an
// sk_test_/rk_test_ key; a live-mode stack would get an Environment of its own.
const stripeSandboxEnvironmentName = "stripe-sandbox"

// stripeSandboxEnvironment declares the environment, pinned to main: the
// delivery job runs on a push to main or a dispatch from it, and no other
// branch (a pull request's included) may read the key. The secret is NOT
// managed here, for the reason oauthEnvironment gives;
// //tools/sync-env-secrets sets it (`set -- stripe-sandbox STRIPE_API_KEY`,
// then `apply -- stripe-sandbox`). No reviewer: the merge of the change is the
// human gate, and the sandbox takes no real money.
func stripeSandboxEnvironment(ctx *pulumi.Context, repo *github.Repository) error {
	env, err := github.NewRepositoryEnvironment(ctx, stripeSandboxEnvironmentName, &github.RepositoryEnvironmentArgs{
		Repository:  repo.Name,
		Environment: pulumi.String(stripeSandboxEnvironmentName),
		DeploymentBranchPolicy: &github.RepositoryEnvironmentDeploymentBranchPolicyArgs{
			ProtectedBranches:    pulumi.Bool(false),
			CustomBranchPolicies: pulumi.Bool(true),
		},
	})
	if err != nil {
		return err
	}
	_, err = github.NewRepositoryEnvironmentDeploymentPolicy(ctx, stripeSandboxEnvironmentName+"-deploy-policy-main", &github.RepositoryEnvironmentDeploymentPolicyArgs{
		Repository:    repo.Name,
		Environment:   env.Environment,
		BranchPattern: pulumi.String("main"),
	}, pulumi.DependsOn([]pulumi.Resource{env}))
	return err
}
