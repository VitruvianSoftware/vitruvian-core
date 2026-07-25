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
	"os"
	"strings"
	"testing"
)

// The committed conditioned-role config must reproduce the LIVE IAM binding
// EXACTLY. In GCP a condition's title and expression are part of the binding's
// IDENTITY: if either differs by one byte, the apply does not adopt the
// existing binding — it creates a SECOND one, leaving the app with two grants
// and the migration unable to complete cleanly.
//
// The wanted values below were read from the live policy with
// `gcloud projects get-iam-policy prj-d-bu1-oss-floating-648a`, so this test
// asserts against production reality rather than restating the config.
func TestConditionedSecretAdminMatchesLiveBinding(t *testing.T) {
	raw, err := os.ReadFile("Pulumi.production.yaml")
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	const key = "foundation-projects-bu1-development:oauth-user-inspector_deploy_conditional_roles:"
	var value string
	for _, line := range strings.Split(string(raw), "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), key) {
			value = strings.Trim(strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(line), key)), "'")
		}
	}
	if value == "" {
		t.Fatalf("config key %q not found", key)
	}

	parsed, err := parseConditionalRoles(value)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(parsed) != 1 {
		t.Fatalf("got %d conditional roles, want 1", len(parsed))
	}
	got := parsed[0]

	if got.Role != "roles/secretmanager.admin" {
		t.Errorf("Role = %q, want roles/secretmanager.admin", got.Role)
	}
	// Live title, verbatim.
	if got.Title != "oauth-user-inspector-secrets-only" {
		t.Errorf("Title = %q, want %q (live binding title)", got.Title, "oauth-user-inspector-secrets-only")
	}
	// After ${projectNumber} resolves to the dev project number, the expression
	// must equal the live one character for character.
	resolved := strings.ReplaceAll(got.Expression, "${projectNumber}", "715357066805")
	const live = `resource.name.startsWith("projects/715357066805/secrets/OAUTH_USER_INSPECTOR_")`
	if resolved != live {
		t.Errorf("resolved expression mismatch — this would create a SECOND binding, not adopt the live one:\n got: %s\nwant: %s", resolved, live)
	}
}

// secretmanager roles must never be in the PLAIN list: unconditioned they reach
// every co-tenant app's secrets in the shared oss project.
func TestPlainDeployRolesCarryNoSecretManagerRole(t *testing.T) {
	raw, err := os.ReadFile("Pulumi.production.yaml")
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	for _, line := range strings.Split(string(raw), "\n") {
		l := strings.TrimSpace(line)
		// Comments explain this very rule and name both the key and the role.
		if strings.HasPrefix(l, "#") {
			continue
		}
		// Match the PLAIN key only — "_deploy_conditional_roles" also ends in
		// "_roles" and legitimately carries a secretmanager role.
		if !strings.Contains(l, "_deploy_roles:") || strings.Contains(l, "_deploy_conditional_roles:") {
			continue
		}
		if strings.Contains(l, "secretmanager") {
			t.Errorf("plain _deploy_roles must not contain a secretmanager role (silent privilege escalation): %s", l)
		}
	}
}
