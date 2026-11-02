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
	"testing"

	"gopkg.in/yaml.v3"
)

// The <app>-preview Environments back the PR pulumi-preview leg, which any
// unmerged branch can run (#4120). Their vars must name the READ-ONLY
// <app>-preview service account minted by foundation gcp-projects (#4197), in
// the app's development project, and never the deploy SA. If they named the
// deploy SA, moving the preview leg off <app>-development would buy nothing:
// a PR branch would still log in as the deploy identity.
func TestPreviewEnvironmentsUseReadOnlyIdentity(t *testing.T) {
	raw, err := os.ReadFile("Pulumi.dev.yaml")
	if err != nil {
		t.Fatal(err)
	}
	// Only the two var maps are decoded; other config keys have other shapes.
	var stack struct {
		Config map[string]yaml.Node `yaml:"config"`
	}
	if err := yaml.Unmarshal(raw, &stack); err != nil {
		t.Fatal(err)
	}

	for key, app := range map[string]string{"tabulaVars": "tabula", "oauthVars": "oauth-user-inspector"} {
		node, ok := stack.Config["vitruvian-core-repo-config:"+key]
		if !ok {
			t.Fatalf("Pulumi.dev.yaml has no %s", key)
		}
		var vars map[string]map[string]string
		if err := node.Decode(&vars); err != nil {
			t.Fatalf("decoding %s: %v", key, err)
		}
		preview, dev := vars["preview"], vars["development"]
		if preview == nil {
			t.Errorf("%s[preview] is missing: the %s-preview Environment would have no WIF vars, so the PR preview leg could not authenticate", key, app)
			continue
		}
		for _, k := range []string{"GCP_DEPLOY_SERVICE_ACCOUNT", "GCP_PROJECT_ID", "GCP_REGION", "GCP_WORKLOAD_IDENTITY_PROVIDER"} {
			if preview[k] == "" {
				t.Errorf("%s[preview].%s is empty", key, k)
			}
		}
		// The preview runs against the development stack, so it shares that
		// project and WIF provider; only the identity differs.
		for _, k := range []string{"GCP_PROJECT_ID", "GCP_WORKLOAD_IDENTITY_PROVIDER"} {
			if preview[k] != dev[k] {
				t.Errorf("%s[preview].%s = %q, want the development value %q", key, k, preview[k], dev[k])
			}
		}
		wantSA := app + "-preview@" + dev["GCP_PROJECT_ID"] + ".iam.gserviceaccount.com"
		if got := preview["GCP_DEPLOY_SERVICE_ACCOUNT"]; got != wantSA {
			t.Errorf("%s[preview].GCP_DEPLOY_SERVICE_ACCOUNT = %q, want the read-only %q", key, got, wantSA)
		}
	}
}
