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
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type recordingMocks struct {
	mu        sync.Mutex
	resources map[string][]resource.PropertyMap // by type token, in creation order
}

func (m *recordingMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.resources[args.TypeToken] = append(m.resources[args.TypeToken], args.Inputs)
	return args.Name + "-id", args.Inputs, nil
}

func (m *recordingMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// The courier-release environment exists with custom deployment policies, and
// those let exactly main and Courier's release tags deploy: never another
// branch (a pull request's branch could otherwise read the Telegram app ID),
// and never another product's tags.
func TestCourierReleaseEnvironment(t *testing.T) {
	mocks := &recordingMocks{resources: map[string][]resource.PropertyMap{}}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		repo, err := github.NewRepository(ctx, "vitruvian-core", &github.RepositoryArgs{
			Name: pulumi.String("vitruvian-core"),
		})
		if err != nil {
			return err
		}
		return courierReleaseEnvironment(ctx, repo)
	}, pulumi.WithMocks("repo-config", "dev", mocks))
	if err != nil {
		t.Fatalf("courierReleaseEnvironment: %v", err)
	}

	envs := mocks.resources["github:index/repositoryEnvironment:RepositoryEnvironment"]
	if len(envs) != 1 || envs[0]["environment"].StringValue() != "courier-release" {
		t.Fatalf("environments = %v, want one named courier-release", envs)
	}
	bp := envs[0]["deploymentBranchPolicy"].ObjectValue()
	if !bp["customBranchPolicies"].BoolValue() || bp["protectedBranches"].BoolValue() {
		t.Errorf("deploymentBranchPolicy = %v, want custom policies only", bp)
	}
	if _, ok := envs[0]["reviewers"]; ok {
		t.Errorf("reviewers = %v, want none (the release PR is the gate)", envs[0]["reviewers"])
	}

	var refs []string
	for _, p := range mocks.resources["github:index/repositoryEnvironmentDeploymentPolicy:RepositoryEnvironmentDeploymentPolicy"] {
		if p["environment"].StringValue() != "courier-release" {
			t.Errorf("policy %v is not on courier-release", p)
		}
		if v, ok := p["branchPattern"]; ok && v.StringValue() != "" {
			refs = append(refs, "branch:"+v.StringValue())
		}
		if v, ok := p["tagPattern"]; ok && v.StringValue() != "" {
			refs = append(refs, "tag:"+v.StringValue())
		}
	}
	sort.Strings(refs)
	if got, want := strings.Join(refs, " "), "branch:main tag:courier-v*"; got != want {
		t.Errorf("deploy refs = %q, want %q", got, want)
	}
}
