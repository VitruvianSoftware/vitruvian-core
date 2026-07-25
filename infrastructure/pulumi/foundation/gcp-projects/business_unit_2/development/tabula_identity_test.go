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

// Adoption must be PERMISSION-NEUTRAL. In GCP a condition's title and
// expression are part of the binding's IDENTITY, so if either differs by one
// byte the apply does not adopt tabula's live binding — it creates a SECOND
// one. The wanted values were read from the live policy with
// `gcloud projects get-iam-policy prj-d-bu2-oss-floating-c3d1`.
func TestTabulaConditionedRolesMatchLiveBindings(t *testing.T) {
	raw, err := os.ReadFile("Pulumi.production.yaml")
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	const key = "foundation-projects-bu2-development:tabula_deploy_conditional_roles:"
	var value string
	for _, line := range strings.Split(string(raw), "\n") {
		l := strings.TrimSpace(line)
		if strings.HasPrefix(l, "#") {
			continue
		}
		if strings.HasPrefix(l, key) {
			value = strings.Trim(strings.TrimSpace(strings.TrimPrefix(l, key)), "'")
		}
	}
	if value == "" {
		t.Fatalf("config key %q not found", key)
	}
	parsed, err := parseConditionalRoles(value)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(parsed) != 2 {
		t.Fatalf("got %d conditional roles, want 2 (admin + secretAccessor)", len(parsed))
	}
	const live = `resource.name.startsWith("projects/325162998369/secrets/TABULA_")`
	wantRoles := map[string]bool{"roles/secretmanager.admin": false, "roles/secretmanager.secretAccessor": false}
	for _, cr := range parsed {
		if _, known := wantRoles[cr.Role]; !known {
			t.Errorf("unexpected conditioned role %q", cr.Role)
			continue
		}
		wantRoles[cr.Role] = true
		if cr.Title != "tabula-secrets-only" {
			t.Errorf("%s: title = %q, want the live %q", cr.Role, cr.Title, "tabula-secrets-only")
		}
		if got := strings.ReplaceAll(cr.Expression, "${projectNumber}", "325162998369"); got != live {
			t.Errorf("%s: resolved expression mismatch — would create a SECOND binding:\n got: %s\nwant: %s", cr.Role, got, live)
		}
	}
	for role, seen := range wantRoles {
		if !seen {
			t.Errorf("live conditioned role %q is missing from the config — adoption would DROP it", role)
		}
	}
}

// The four plain roles must match the live unconditioned set exactly; a missing
// one silently narrows tabula's deploy permissions at adoption.
func TestTabulaPlainRolesMatchLive(t *testing.T) {
	live := []string{
		"roles/run.admin",
		"roles/iam.serviceAccountUser",
		"roles/serviceusage.serviceUsageConsumer",
		"roles/logging.viewer",
	}
	if len(defaultAppDeployRoles) != len(live) {
		t.Fatalf("defaultAppDeployRoles has %d roles, live tabula has %d", len(defaultAppDeployRoles), len(live))
	}
	have := map[string]bool{}
	for _, r := range defaultAppDeployRoles {
		have[r] = true
	}
	for _, r := range live {
		if !have[r] {
			t.Errorf("live role %q missing from defaultAppDeployRoles — adoption would REVOKE it", r)
		}
	}
}
