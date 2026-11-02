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
	"testing"
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
