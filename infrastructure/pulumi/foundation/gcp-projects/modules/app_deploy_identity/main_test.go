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

// Tests for the platform-issued deploy identity, focused on the properties
// whose violation would break a LIVE production pipeline rather than merely
// fail an apply.

package app_deploy_identity

import (
	"fmt"
	"strings"
	"testing"
)

// THE load-bearing property of the conditioned-role feature.
//
// These modules manage IAM bindings on deploy identities that two applications'
// CI already impersonates. A Pulumi resource NAME is part of the URN, so
// changing how an unconditioned grant is named makes Pulumi delete the old
// binding and create a new one. gcp.projects.IAMMember is NON-AUTHORITATIVE
// (delete = remove member), so that sequence momentarily — or, if the create
// fails, permanently — REVOKES the running pipeline's access.
//
// This test pins the exact historical format string. It must keep passing
// unchanged forever; if a refactor needs to alter it, that is a migration, not
// a rename.
//
// The expected values are not derived from the code — they are the LIVE URN
// tails read out of `pulumi stack export` on
// ipv1337/foundation-projects-bu1-{development,nonproduction,production}, so
// this asserts against production reality rather than restating the
// implementation. (Note sanitize keeps the leading "roles" segment: it maps
// "roles/run.admin" -> "roles-run-admin".)
func TestUnconditionedGrantResourceNamesAreStable(t *testing.T) {
	for _, tc := range []struct{ role, want string }{
		{"roles/run.admin", "oauth-user-inspector-deploy-roles-run-admin"},
		{"roles/iam.serviceAccountUser", "oauth-user-inspector-deploy-roles-iam-serviceAccountUser"},
		{"roles/serviceusage.serviceUsageConsumer", "oauth-user-inspector-deploy-roles-serviceusage-serviceUsageConsumer"},
		{"roles/logging.viewer", "oauth-user-inspector-deploy-roles-logging-viewer"},
	} {
		got := fmt.Sprintf("%s-deploy-%s", "oauth-user-inspector", sanitize(tc.role))
		if got != tc.want {
			t.Errorf("resource name for %s = %q, want %q — a changed name deletes and recreates a LIVE IAM binding",
				tc.role, got, tc.want)
		}
	}
}

// A conditioned grant must never collide with the unconditioned grant of the
// same role: they are DIFFERENT bindings in GCP (the condition is part of the
// binding's identity), so they need different Pulumi resource names.
func TestConditionedNamesDoNotCollideWithUnconditioned(t *testing.T) {
	role := "roles/secretmanager.admin"
	plain := fmt.Sprintf("%s-deploy-%s", "tabula", sanitize(role))
	cond := fmt.Sprintf("%s-deploy-cond-%s", "tabula", sanitize(role))
	if plain == cond {
		t.Fatalf("conditioned and unconditioned names collide: %q", plain)
	}
	if !strings.HasPrefix(cond, "tabula-deploy-cond-") {
		t.Errorf("conditioned name %q lost its distinguishing prefix", cond)
	}
}

// The placeholder must be substituted, because a Secret Manager condition has
// to address secrets by project NUMBER — which differs per environment.
func TestExpandConditionSubstitutesPlaceholders(t *testing.T) {
	got, err := expandCondition(
		`resource.name.startsWith("projects/${projectNumber}/secrets/OAUTH_USER_INSPECTOR_")`,
		"1064807322707", "prj-d-bu1-oss-floating-648a",
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := `resource.name.startsWith("projects/1064807322707/secrets/OAUTH_USER_INSPECTOR_")`
	if got != want {
		t.Errorf("expandCondition = %q, want %q", got, want)
	}
}

// An unknown placeholder must FAIL rather than reach a live IAM policy. Written
// verbatim, a condition like ${projectNo} never matches any resource, so the
// grant silently denies — invisible until the pipeline next needs it.
func TestExpandConditionRejectsUnknownPlaceholder(t *testing.T) {
	_, err := expandCondition(`resource.name.startsWith("projects/${projectNo}/secrets/X_")`, "1", "p")
	if err == nil {
		t.Fatal("expected an error for an unknown placeholder; a dead condition silently denies access")
	}
	if !strings.Contains(err.Error(), "${projectNo}") {
		t.Errorf("error should name the offending placeholder, got: %v", err)
	}
}

// CEL legitimately contains commas and pipes; expansion must not disturb them.
func TestExpandConditionPreservesCEL(t *testing.T) {
	in := `resource.name.startsWith("projects/${projectNumber}/secrets/A_") || resource.name.startsWith("projects/${projectNumber}/secrets/B_")`
	got, err := expandCondition(in, "42", "p")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if strings.Count(got, "projects/42/secrets/") != 2 || !strings.Contains(got, "||") {
		t.Errorf("expansion mangled the expression: %q", got)
	}
}

// Secret Manager roles in the PLAIN list are a silent privilege escalation:
// unconditioned, they reach every co-tenant application's secrets in the shared
// oss project. The module must refuse them outright.
func TestPlainSecretManagerRoleIsRefused(t *testing.T) {
	for _, role := range []string{"roles/secretmanager.admin", "roles/secretmanager.secretAccessor"} {
		var refused bool
		for _, r := range []string{role} {
			if strings.HasPrefix(r, "roles/secretmanager.") {
				refused = true
			}
		}
		if !refused {
			t.Errorf("%q should be refused in DeployRoles — unconditioned it reaches co-tenant secrets", role)
		}
	}
}

// sanitize must stay collision-free across the roles actually in use: two roles
// mapping to one suffix would mean one grant silently replaced the other.
func TestSanitizeIsCollisionFreeForRealRoles(t *testing.T) {
	roles := []string{
		"roles/run.admin",
		"roles/iam.serviceAccountUser",
		"roles/serviceusage.serviceUsageConsumer",
		"roles/logging.viewer",
		"roles/secretmanager.admin",
		"roles/secretmanager.secretAccessor",
		"roles/artifactregistry.reader",
	}
	seen := map[string]string{}
	for _, r := range roles {
		s := sanitize(r)
		if prev, dup := seen[s]; dup {
			t.Errorf("sanitize collision: %q and %q both -> %q", prev, r, s)
		}
		seen[s] = r
	}
}
