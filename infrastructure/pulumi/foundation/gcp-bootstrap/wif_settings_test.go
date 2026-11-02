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
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

// expectedPoolInputs is every input of every workload identity pool, exactly,
// keyed by pool id. It is the pool-side counterpart of expectedProviderInputs
// and matches what is live (gcloud ... workload-identity-pools describe,
// 2026-11-02).
//
// Exact in both directions: a changed value fails, and so does an input that
// is not listed. That second half is what pins the settings left to GCP's
// defaults. In particular `mode` must stay ABSENT: unset means
// FEDERATION_ONLY, and the field is immutable, so it cannot be written into a
// pool that was created without it. A trust-domain mode, inline trust or
// certificate config, or attestation rules would all show up here as an
// unexpected key.
var expectedPoolInputs = map[string]map[string]interface{}{
	"foundation-pool": {
		"workloadIdentityPoolId": "foundation-pool",
		"disabled":               false,
	},
	"homelab-cluster-pool": {
		"workloadIdentityPoolId": "homelab-cluster-pool",
		"displayName":            "Homelab cluster",
		"description":            "Federates the homelab k3s cluster so in-cluster workloads need no GCP key",
		"disabled":               false,
	},
	"pulumi-esc-pool": {
		"workloadIdentityPoolId": "pulumi-esc-pool",
		"displayName":            "Pulumi ESC",
		"description":            "Federates Pulumi Cloud ESC environments so agent sessions need no GCP key",
		"disabled":               false,
	},
}

// Every pool the whole program declares is pinned whole, and no pool exists
// that is not listed: a new pool is a new way in, and must be added here on
// purpose.
func TestWholeProgramWorkloadIdentityPoolsArePinned(t *testing.T) {
	seen := map[string]bool{}
	for _, r := range runWholeProgram(t) {
		if r.typ != "gcp:iam/workloadIdentityPool:WorkloadIdentityPool" {
			continue
		}
		id := str(r, "workloadIdentityPoolId")
		got := r.inputs.Mappable()
		project, _ := got["project"].(string)
		assert.True(t, strings.HasPrefix(project, "prj-b-cicd-"), "%s: project %q is not the CI/CD project", id, project)
		delete(got, "project")
		want, known := expectedPoolInputs[id]
		if assert.True(t, known, "%s (%s): pool is not in the allow-list", id, r.name) {
			assert.Equal(t, want, got, "%s: pool inputs", id)
			assert.False(t, seen[id], "%s declared twice", id)
			seen[id] = true
		}
	}
	for id := range expectedPoolInputs {
		assert.True(t, seen[id], "%s not declared", id)
	}
}
