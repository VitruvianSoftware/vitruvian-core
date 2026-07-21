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

import "testing"

// The environment identity is pinned by the leaf directory, not by stack
// config (upstream business_unit_1/<env> layout). A wrong pin would deploy one
// environment's app identities into another environment's project.
func TestPinnedEnvironment(t *testing.T) {
	if pinnedEnv != "production" {
		t.Fatalf("pinnedEnv = %q, want %q", pinnedEnv, "production")
	}
}

// REGRESSION GUARD for the adoption of oauth-user-inspector's deploy SA from
// oauth-user-inspector/infra/identity. That account is live and deploying; if
// this stage grants it a different role set, adoption silently widens or
// narrows a running pipeline's permissions. This list is the one the app-side
// stack held at adoption time — changing it must be a deliberate, reviewed edit
// to BOTH this test and the stack config, never a drive-by.
func TestDefaultDeployRolesMatchAdoptedSet(t *testing.T) {
	want := []string{
		"roles/run.admin",
		"roles/iam.serviceAccountUser",
		"roles/serviceusage.serviceUsageConsumer",
		"roles/logging.viewer",
	}
	if len(defaultDeployRoles) != len(want) {
		t.Fatalf("defaultDeployRoles = %v, want %v", defaultDeployRoles, want)
	}
	for i := range want {
		if defaultDeployRoles[i] != want[i] {
			t.Errorf("defaultDeployRoles[%d] = %q, want %q", i, defaultDeployRoles[i], want[i])
		}
	}
}

// The WIF principalSet binds per GitHub Environment, not per repository — that
// is the per-env isolation layer. <app>-<env> must match the Environment name
// repo_config provisions.
func TestGitHubEnvironmentNaming(t *testing.T) {
	got := AppConfig{Name: "oauth-user-inspector"}.GitHubEnvironment(pinnedEnv)
	want := "oauth-user-inspector-production"
	if got != want {
		t.Fatalf("GitHubEnvironment = %q, want %q", got, want)
	}
}

func TestSplitListTrimsAndDropsEmpties(t *testing.T) {
	got := splitList(" a , ,b ")
	if len(got) != 2 || got[0] != "a" || got[1] != "b" {
		t.Fatalf("splitList = %#v, want [a b]", got)
	}
	if splitList("  ") != nil {
		t.Fatal("splitList(blank) should be nil")
	}
}
