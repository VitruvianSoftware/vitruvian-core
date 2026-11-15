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
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func TestPagerdutyEnvironmentIsPinnedToMainWithoutReviewers(t *testing.T) {
	// pdStackMocks: pagerdutyEnvironment also reads the PagerDuty stack.
	mocks := &pdStackMocks{outputs: resource.PropertyMap{}, resources: map[string][]resource.PropertyMap{}}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		repo, err := github.NewRepository(ctx, "vitruvian-core", &github.RepositoryArgs{
			Name: pulumi.String("vitruvian-core"),
		})
		if err != nil {
			return err
		}
		return pagerdutyEnvironment(ctx, repo)
	}, pulumi.WithMocks("repo-config", "dev", mocks))
	if err != nil {
		t.Fatalf("pagerdutyEnvironment: %v", err)
	}

	envs := mocks.resources["github:index/repositoryEnvironment:RepositoryEnvironment"]
	if len(envs) != 1 || envs[0]["environment"].StringValue() != pagerdutyProductionEnvironmentName {
		t.Fatalf("environments = %v, want single %s", envs, pagerdutyProductionEnvironmentName)
	}
	e := envs[0]
	bpv, ok := e["deploymentBranchPolicy"]
	if !ok || bpv.IsNull() {
		t.Fatalf("%s has no deploymentBranchPolicy, so ANY branch could read its token", pagerdutyProductionEnvironmentName)
	}
	bp := bpv.ObjectValue()
	if !bp["customBranchPolicies"].BoolValue() || bp["protectedBranches"].BoolValue() {
		t.Errorf("%s deploymentBranchPolicy = %v, want custom policies only", pagerdutyProductionEnvironmentName, bp)
	}
	if v, ok := e["reviewers"]; ok && !v.IsNull() && len(v.ArrayValue()) > 0 {
		t.Errorf("%s has reviewers %v; expected none", pagerdutyProductionEnvironmentName, v)
	}

	policies := mocks.resources["github:index/repositoryEnvironmentDeploymentPolicy:RepositoryEnvironmentDeploymentPolicy"]
	if len(policies) != 1 {
		t.Fatalf("deployment policies = %v, want exactly one", policies)
	}
	p := policies[0]
	if p["environment"].StringValue() != pagerdutyProductionEnvironmentName || p["branchPattern"].StringValue() != "main" {
		t.Errorf("deployment policy = %v, want environment %s branch main", p, pagerdutyProductionEnvironmentName)
	}
	if v, ok := p["tagPattern"]; ok && v.StringValue() != "" {
		t.Errorf("policy has tagPattern %q; no tag may deploy to it", v.StringValue())
	}
}
