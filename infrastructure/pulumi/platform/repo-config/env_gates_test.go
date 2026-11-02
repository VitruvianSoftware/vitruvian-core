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
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// Every Environment that holds a deploy or registry-push identity must be
// pinned to main (#4120). GCP checks only the repository and the Environment
// name, so a missing branch policy lets any unmerged branch sign in as that
// Environment's service account. Only <app>-preview, which holds the
// read-only identity the PR pulumi-preview leg runs as, stays open.
func TestDeployEnvironmentsArePinnedToMain(t *testing.T) {
	type want struct {
		mainOnly bool
		tags     []string
		reviewer bool
	}
	cases := []struct {
		app  string
		gate func(string) envGate
		envs map[string]want
	}{
		{"tabula", tabulaEnvGate, map[string]want{
			"development":   {mainOnly: true},
			"build":         {mainOnly: true, tags: []string{"tabula-api-v*", "tabula-web-v*"}},
			"nonproduction": {mainOnly: true, tags: []string{"tabula-api-v*", "tabula-web-v*"}},
			"production":    {mainOnly: true, tags: []string{"tabula-api-v*", "tabula-web-v*"}, reviewer: true},
			"preview":       {},
		}},
		{"oauth-user-inspector", oauthEnvGate, map[string]want{
			"development":   {mainOnly: true},
			"build":         {mainOnly: true, tags: []string{"oauth-user-inspector-v*"}},
			"nonproduction": {mainOnly: true, tags: []string{"oauth-user-inspector-v*"}},
			"production":    {mainOnly: true, tags: []string{"oauth-user-inspector-v*"}, reviewer: true},
			"preview":       {},
		}},
	}
	for _, c := range cases {
		for env, w := range c.envs {
			g := c.gate(env)
			var tags []string
			for _, tp := range g.tags {
				tags = append(tags, tp.pattern)
			}
			got := want{mainOnly: g.mainOnly, tags: tags, reviewer: g.reviewer}
			if !reflect.DeepEqual(got, w) {
				t.Errorf("%s-%s gate = %+v, want %+v", c.app, env, got, w)
			}
		}
	}
}

// The tag policies' Pulumi resource names must not move: the nonproduction
// and production policies already exist as <env>-deploy-policy-tags(-web), and
// a renamed resource is a delete plus a create, which briefly leaves a
// release-gated Environment without its tag rule.
func TestTagPolicyResourceNamesAreStable(t *testing.T) {
	for _, tc := range []struct {
		name string
		tags []envTagPolicy
		want []string
	}{
		{"tabula", tabulaReleaseTags, []string{"tags", "tags-web"}},
		{"oauth-user-inspector", oauthReleaseTags, []string{"tags"}},
	} {
		var got []string
		for _, tp := range tc.tags {
			got = append(got, tp.suffix)
		}
		if !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s tag policy suffixes = %v, want %v", tc.name, got, tc.want)
		}
	}
}

// envGateMocks records resources like recordingMocks, and answers the GetUser
// invoke productionReviewerIds makes with a numeric id.
type envGateMocks struct{ recordingMocks }

func (m *envGateMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	if args.Token == "github:index/getUser:getUser" {
		return resource.PropertyMap{"id": resource.NewStringProperty("1")}, nil
	}
	return args.Args, nil
}

// The gate table is only half the property: what matters is the Environment
// resources actually built from it (#4120). Run both builders under mocks and
// check every Environment they create. Each one must be either a deliberately
// open *-preview Environment, or carry custom branch policies (not "protected
// branches", which lets any protected branch in) with exactly the expected
// main/tag rows. An Environment this table does not know fails, so a new one
// cannot slip in open by default.
func TestDeployEnvironmentResourcesArePinnedToMain(t *testing.T) {
	tabulaTags := []string{"branch:main", "tag:tabula-api-v*", "tag:tabula-web-v*"}
	oauthTags := []string{"branch:main", "tag:oauth-user-inspector-v*"}
	want := map[string][]string{ // nil = deliberately open
		"tabula-preview":                     nil,
		"tabula-development":                 {"branch:main"},
		"tabula-build":                       tabulaTags,
		"tabula-nonproduction":               tabulaTags,
		"tabula-production":                  tabulaTags,
		"oauth-user-inspector-preview":       nil,
		"oauth-user-inspector-development":   {"branch:main"},
		"oauth-user-inspector-build":         oauthTags,
		"oauth-user-inspector-nonproduction": oauthTags,
		"oauth-user-inspector-production":    oauthTags,
	}

	mocks := &envGateMocks{recordingMocks{resources: map[string][]resource.PropertyMap{}}}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		repo, err := github.NewRepository(ctx, "vitruvian-core", &github.RepositoryArgs{
			Name: pulumi.String("vitruvian-core"),
		})
		if err != nil {
			return err
		}
		cfg := config.New(ctx, "")
		if err := tabulaEnvironments(ctx, cfg, repo); err != nil {
			return err
		}
		return oauthEnvironment(ctx, cfg, repo)
	}, pulumi.WithMocks("repo-config", "dev", mocks))
	if err != nil {
		t.Fatalf("building environments: %v", err)
	}

	refs := map[string][]string{}
	for _, p := range mocks.resources["github:index/repositoryEnvironmentDeploymentPolicy:RepositoryEnvironmentDeploymentPolicy"] {
		env := p["environment"].StringValue()
		if v, ok := p["branchPattern"]; ok && v.StringValue() != "" {
			refs[env] = append(refs[env], "branch:"+v.StringValue())
		}
		if v, ok := p["tagPattern"]; ok && v.StringValue() != "" {
			refs[env] = append(refs[env], "tag:"+v.StringValue())
		}
	}

	seen := map[string]bool{}
	for _, e := range mocks.resources["github:index/repositoryEnvironment:RepositoryEnvironment"] {
		name := e["environment"].StringValue()
		seen[name] = true
		wantRefs, known := want[name]
		if !known {
			t.Errorf("%s: unexpected Environment; add it to this test's table, pinned (or deliberately open if it holds only a read-only identity)", name)
			continue
		}
		got := append([]string(nil), refs[name]...)
		sort.Strings(got)
		bpv, hasBP := e["deploymentBranchPolicy"]
		if wantRefs == nil {
			if hasBP && !bpv.IsNull() {
				t.Errorf("%s: deploymentBranchPolicy = %v, want none (open preview Environment)", name, bpv)
			}
			if len(got) != 0 {
				t.Errorf("%s: deploy refs = %v, want none", name, got)
			}
			continue
		}
		if !hasBP || bpv.IsNull() {
			t.Errorf("%s: no deploymentBranchPolicy, so ANY branch may deploy", name)
		} else {
			bp := bpv.ObjectValue()
			if bp["protectedBranches"].BoolValue() || !bp["customBranchPolicies"].BoolValue() {
				t.Errorf("%s: deploymentBranchPolicy = %v, want protectedBranches=false customBranchPolicies=true", name, bp)
			}
		}
		if g, w := strings.Join(got, " "), strings.Join(wantRefs, " "); g != w {
			t.Errorf("%s: deploy refs = %q, want %q", name, g, w)
		}
	}
	for name := range want {
		if !seen[name] {
			t.Errorf("%s: Environment was not created", name)
		}
	}
}

// A gate nobody wrote a case for must come out pinned, not open.
func TestUnknownEnvironmentGateIsClosed(t *testing.T) {
	for app, gate := range map[string]func(string) envGate{"tabula": tabulaEnvGate, "oauth-user-inspector": oauthEnvGate} {
		if g := gate("staging"); !g.mainOnly {
			t.Errorf("%s gate for an unlisted env = %+v, want mainOnly (default closed)", app, g)
		}
	}
}
