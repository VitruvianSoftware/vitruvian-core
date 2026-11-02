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

// Pins #4120 step 1 for this leaf: oauth-user-inspector's read-only PR preview identity is
// switched ON in the committed stack config, is OFF by default for any other
// app, and is bound to the dedicated oauth-user-inspector-preview Environment rather than the
// deploy Environment.

package main

import (
	"os"
	"strings"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const previewApp = "oauth-user-inspector"

// The committed config must turn the preview identity on. Without it the
// repo-config wiring (step 2) has no service account to point at, and the
// deploy Environment can never be pinned to main.
func TestCommittedConfigEnablesPreviewIdentity(t *testing.T) {
	raw, err := os.ReadFile("Pulumi.production.yaml")
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	key := "foundation-projects-bu1-development:" + previewApp + "_preview_identity:"
	var value string
	for _, line := range strings.Split(string(raw), "\n") {
		l := strings.TrimSpace(line)
		if strings.HasPrefix(l, key) {
			value = strings.Trim(strings.TrimSpace(strings.TrimPrefix(l, key)), "\"'")
		}
	}
	if value != "true" {
		t.Fatalf("%s = %q, want \"true\" (#4120: the PR preview needs its own read-only identity)", key, value)
	}
}

func TestPreviewIdentityConfigLoading(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{
		"project:business_code": "bu1",
		"project:billing_account": "AAAAAA-BBBBBB-CCCCCC",
		"project:apps": "`+previewApp+`,other-app",
		"project:`+previewApp+`_preview_identity": "true"
	}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadProjectsConfig(ctx)
		if len(cfg.Apps) != 2 {
			t.Fatalf("got %d apps, want 2", len(cfg.Apps))
		}
		for _, app := range cfg.Apps {
			switch app.Name {
			case previewApp:
				if !app.PreviewIdentity {
					t.Errorf("%s: PreviewIdentity = false, want true", app.Name)
				}
				if got, want := app.PreviewGitHubEnvironment(), previewApp+"-preview"; got != want {
					t.Errorf("PreviewGitHubEnvironment = %q, want %q", got, want)
				}
				if app.PreviewGitHubEnvironment() == app.GitHubEnvironment(cfg.Env) {
					t.Errorf("preview and deploy Environments are the same (%q); the preview would keep deploy power",
						app.GitHubEnvironment(cfg.Env))
				}
			case "other-app":
				if app.PreviewIdentity {
					t.Errorf("other-app: PreviewIdentity defaulted to true; it must be opt-in")
				}
			}
		}
		return nil
	}, pulumi.WithMocks("project", "stack", projectsMocks(0)))
	if err != nil {
		t.Fatal(err)
	}
}
