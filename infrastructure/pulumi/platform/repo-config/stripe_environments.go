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

// The GitHub Environments the jobs of .github/workflows/delivery-stripe.yaml
// bind, one per Stripe stack. Each holds that stack's key as the environment
// secret STRIPE_API_KEY, so only its job can read it:
//
//   - stripe-sandbox: the Stripe sandbox (test mode). The job refuses anything
//     but an sk_test_/rk_test_ key. No reviewer: the merge is the human gate,
//     and the sandbox takes no real money.
//   - stripe-production: the live account. The job refuses anything but an
//     sk_live_/rk_live_ key, runs only after the sandbox applied in the same
//     run, and waits for a required reviewer to approve it.
//
// Both are pinned to main: no other branch, a pull request's included, may
// read a key. The secrets are NOT managed here, for the reason
// oauthEnvironment gives; //tools/sync-env-secrets sets them
// (`set -- <env> STRIPE_API_KEY`, then `apply -- <env>`).
const (
	stripeSandboxEnvironmentName    = "stripe-sandbox"
	stripeProductionEnvironmentName = "stripe-production"
)

// stripeEnvironments declares both. reviewerIds are the GitHub user ids that
// approve a production apply (productionReviewerIds); an empty list is an
// error, because a live Stripe apply with no human gate is not allowed.
func stripeEnvironments(ctx *pulumi.Context, repo *github.Repository, reviewerIds []int) error {
	if err := mainOnlyEnvironment(ctx, repo, stripeSandboxEnvironmentName, nil); err != nil {
		return err
	}
	if len(reviewerIds) == 0 {
		return errNoStripeProductionReviewer
	}
	return mainOnlyEnvironment(ctx, repo, stripeProductionEnvironmentName, github.RepositoryEnvironmentReviewerArray{
		&github.RepositoryEnvironmentReviewerArgs{
			Users: pulumi.ToIntArray(reviewerIds),
		},
	})
}

type stripeEnvError string

func (e stripeEnvError) Error() string { return string(e) }

const errNoStripeProductionReviewer = stripeEnvError("stripe-production needs at least one required reviewer: a live Stripe apply must wait for a human")

func mainOnlyEnvironment(ctx *pulumi.Context, repo *github.Repository, name string, reviewers github.RepositoryEnvironmentReviewerArray) error {
	args := &github.RepositoryEnvironmentArgs{
		Repository:  repo.Name,
		Environment: pulumi.String(name),
		DeploymentBranchPolicy: &github.RepositoryEnvironmentDeploymentBranchPolicyArgs{
			ProtectedBranches:    pulumi.Bool(false),
			CustomBranchPolicies: pulumi.Bool(true),
		},
	}
	if len(reviewers) > 0 {
		args.Reviewers = reviewers
	}
	env, err := github.NewRepositoryEnvironment(ctx, name, args)
	if err != nil {
		return err
	}
	_, err = github.NewRepositoryEnvironmentDeploymentPolicy(ctx, name+"-deploy-policy-main", &github.RepositoryEnvironmentDeploymentPolicyArgs{
		Repository:    repo.Name,
		Environment:   env.Environment,
		BranchPattern: pulumi.String("main"),
	}, pulumi.DependsOn([]pulumi.Resource{env}))
	return err
}
