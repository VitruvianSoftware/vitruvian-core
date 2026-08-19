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

package cluster_reader

import "testing"

func TestSanitizersDoNotCollide(t *testing.T) {
	// Two SAs differing only before the @ must not collapse to one resource
	// name -- the second binding would silently replace the first, and one of
	// the two identities would end up with no access at all.
	a := sanitizeMember("serviceAccount:sa-homelab-cluster@prj-b-cicd-e096.iam.gserviceaccount.com")
	b := sanitizeMember("serviceAccount:sa-other@prj-b-cicd-e096.iam.gserviceaccount.com")
	if a == b {
		t.Fatalf("distinct members collided: %q", a)
	}
	for _, bad := range []string{":", "@", "."} {
		if got := sanitizeMember("serviceAccount:x@y.com"); containsAny(got, bad) {
			t.Fatalf("sanitized member still contains %q: %q", bad, got)
		}
	}
	if got, want := sanitizeRole("roles/run.viewer"), "run-viewer"; got != want {
		t.Fatalf("sanitizeRole: got %q want %q", got, want)
	}
	if sanitizeRole("roles/run.viewer") == sanitizeRole("roles/monitoring.viewer") {
		t.Fatal("distinct roles collided")
	}
}

func TestOnlyReadOnlyRolesAreAllowed(t *testing.T) {
	// The guard that matters: this identity is reachable from a browser-facing
	// service, so a config edge that hands it write access must fail the apply
	// rather than quietly succeed.
	for _, r := range []string{"roles/run.admin", "roles/editor", "roles/owner", "roles/run.developer"} {
		if allowedRoles[r] {
			t.Fatalf("%q must not be grantable by this module", r)
		}
	}
	for _, r := range []string{"roles/run.viewer", "roles/monitoring.viewer"} {
		if !allowedRoles[r] {
			t.Fatalf("%q should be grantable", r)
		}
	}
}

func containsAny(s, chars string) bool {
	for _, c := range chars {
		for _, x := range s {
			if x == c {
				return true
			}
		}
	}
	return false
}
