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
	"sync"
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// pdStackMocks answers the PagerDuty stack reference with `outputs` and
// records every resource.
type pdStackMocks struct {
	mu        sync.Mutex
	outputs   resource.PropertyMap
	resources map[string][]resource.PropertyMap
	refNames  []string
}

func (m *pdStackMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.resources[args.TypeToken] = append(m.resources[args.TypeToken], args.Inputs)
	if args.TypeToken == "pulumi:pulumi:StackReference" {
		m.refNames = append(m.refNames, args.Inputs["name"].StringValue())
		return args.Name, resource.PropertyMap{
			"name":    args.Inputs["name"],
			"outputs": resource.NewObjectProperty(m.outputs),
		}, nil
	}
	return args.Name + "-id", args.Inputs, nil
}

func (m *pdStackMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func runPagerdutyEnvironment(t *testing.T, outputs resource.PropertyMap) *pdStackMocks {
	t.Helper()
	mocks := &pdStackMocks{outputs: outputs, resources: map[string][]resource.PropertyMap{}}
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
	return mocks
}

// The key the PagerDuty stack mints becomes the repository secret the
// notify-ci-issues workflow reads, under exactly the name it reads.
func TestPagerdutyCIRoutingKeyBecomesRepoSecret(t *testing.T) {
	m := runPagerdutyEnvironment(t, resource.PropertyMap{
		"ciIntegrationKey": resource.MakeSecret(resource.NewStringProperty("pd-key-abc")),
	})
	if len(m.refNames) != 1 || m.refNames[0] != "ipv1337/vitruvian-pagerduty/production" {
		t.Fatalf("stack references = %v, want the PagerDuty production stack", m.refNames)
	}
	secrets := m.resources["github:index/actionsSecret:ActionsSecret"]
	if len(secrets) != 1 {
		t.Fatalf("actions secrets = %v, want exactly one", secrets)
	}
	s := secrets[0]
	if got := s["secretName"].StringValue(); got != "PAGERDUTY_CI_ROUTING_KEY" {
		t.Errorf("secretName = %q", got)
	}
	if got := s["repository"].StringValue(); got != "vitruvian-core" {
		t.Errorf("repository = %q", got)
	}
	if v, ok := s["plaintextValue"]; ok && !v.IsNull() {
		t.Errorf("plaintextValue is deprecated; the key belongs in value: %v", v)
	}
	v := s["value"]
	if !v.IsSecret() {
		t.Fatalf("value is not marked secret: %v", v)
	}
	if got := v.SecretValue().Element.StringValue(); got != "pd-key-abc" {
		t.Errorf("value = %q, want the stack output", got)
	}
}

// Before the PagerDuty stack has applied there is no key: the apply goes on
// without the secret rather than failing (repo-config owns the merge queue).
func TestPagerdutyCIRoutingKeySkippedUntilExported(t *testing.T) {
	m := runPagerdutyEnvironment(t, resource.PropertyMap{})
	if secrets := m.resources["github:index/actionsSecret:ActionsSecret"]; len(secrets) != 0 {
		t.Fatalf("actions secrets = %v, want none before the key exists", secrets)
	}
	if envs := m.resources["github:index/repositoryEnvironment:RepositoryEnvironment"]; len(envs) != 1 {
		t.Fatalf("the pagerduty-production environment must still be declared, got %v", envs)
	}
}
