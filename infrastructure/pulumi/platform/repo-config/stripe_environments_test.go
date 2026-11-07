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
	"errors"
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func runStripeEnvironments(t *testing.T, reviewerIds []int) (*recordingMocks, error) {
	t.Helper()
	mocks := &recordingMocks{resources: map[string][]resource.PropertyMap{}}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		repo, err := github.NewRepository(ctx, "vitruvian-core", &github.RepositoryArgs{
			Name: pulumi.String("vitruvian-core"),
		})
		if err != nil {
			return err
		}
		return stripeEnvironments(ctx, repo, reviewerIds)
	}, pulumi.WithMocks("repo-config", "dev", mocks))
	return mocks, err
}

// Each Stripe environment holds a Stripe key, so exactly main may deploy to it:
// a pull request's branch must never be able to read one. Production also
// waits for a required reviewer; the sandbox does not.
func TestStripeEnvironmentsArePinnedToMainAndProductionIsReviewed(t *testing.T) {
	const james = 3703513
	mocks, err := runStripeEnvironments(t, []int{james})
	if err != nil {
		t.Fatalf("stripeEnvironments: %v", err)
	}

	envs := map[string]resource.PropertyMap{}
	for _, e := range mocks.resources["github:index/repositoryEnvironment:RepositoryEnvironment"] {
		envs[e["environment"].StringValue()] = e
	}
	if len(envs) != 2 || envs["stripe-sandbox"] == nil || envs["stripe-production"] == nil {
		t.Fatalf("environments = %v, want stripe-sandbox and stripe-production", envs)
	}
	for name, e := range envs {
		bpv, ok := e["deploymentBranchPolicy"]
		if !ok || bpv.IsNull() {
			t.Fatalf("%s has no deploymentBranchPolicy, so ANY branch could read its key", name)
		}
		bp := bpv.ObjectValue()
		if !bp["customBranchPolicies"].BoolValue() || bp["protectedBranches"].BoolValue() {
			t.Errorf("%s deploymentBranchPolicy = %v, want custom policies only", name, bp)
		}
	}

	if v, ok := envs["stripe-sandbox"]["reviewers"]; ok && !v.IsNull() && len(v.ArrayValue()) > 0 {
		t.Errorf("stripe-sandbox has reviewers %v; the sandbox applies on merge", v)
	}
	rv, ok := envs["stripe-production"]["reviewers"]
	if !ok || rv.IsNull() || len(rv.ArrayValue()) != 1 {
		t.Fatalf("stripe-production reviewers = %v, want one reviewer block", rv)
	}
	users := rv.ArrayValue()[0].ObjectValue()["users"].ArrayValue()
	if len(users) != 1 || int(users[0].NumberValue()) != james {
		t.Errorf("stripe-production reviewer users = %v, want [%d]", users, james)
	}

	policies := map[string]resource.PropertyMap{}
	for _, p := range mocks.resources["github:index/repositoryEnvironmentDeploymentPolicy:RepositoryEnvironmentDeploymentPolicy"] {
		policies[p["environment"].StringValue()] = p
	}
	for _, name := range []string{"stripe-sandbox", "stripe-production"} {
		p := policies[name]
		if p == nil || p["branchPattern"].StringValue() != "main" {
			t.Errorf("%s deployment policy = %v, want branch main", name, p)
			continue
		}
		if v, ok := p["tagPattern"]; ok && v.StringValue() != "" {
			t.Errorf("%s policy has tagPattern %q; no tag may deploy to it", name, v.StringValue())
		}
	}
	if len(policies) != 2 {
		t.Errorf("deployment policies = %v, want exactly one per environment", policies)
	}
}

// A live Stripe apply with no human gate is refused at preview time.
func TestStripeProductionRefusesNoReviewer(t *testing.T) {
	_, err := runStripeEnvironments(t, nil)
	if !errors.Is(err, errNoStripeProductionReviewer) {
		t.Fatalf("stripeEnvironments(no reviewers) err = %v, want errNoStripeProductionReviewer", err)
	}
}
