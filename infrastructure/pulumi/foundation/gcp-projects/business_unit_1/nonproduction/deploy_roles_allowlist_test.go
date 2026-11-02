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

// Checks this leaf's role inputs against app_deploy_identity's allow-list:
// the built-in defaults and every role in the committed stack config. The
// module refuses these at program time anyway; this catches it in `go test`,
// before a preview, and names the config key.

package main

import (
	"foundation-projects/modules/app_deploy_identity"
	"os"
	"strings"
	"testing"
)

// committedConfig returns every `<key>: <value>` in Pulumi.production.yaml
// whose key ends in suffix, comments skipped and quotes trimmed.
func committedConfig(t *testing.T, suffix string) map[string]string {
	t.Helper()
	raw, err := os.ReadFile("Pulumi.production.yaml")
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	out := map[string]string{}
	for _, line := range strings.Split(string(raw), "\n") {
		l := strings.TrimSpace(line)
		if strings.HasPrefix(l, "#") {
			continue
		}
		key, val, ok := strings.Cut(l, ": ")
		if !ok || !strings.HasSuffix(key, suffix) {
			continue
		}
		out[key] = strings.Trim(strings.TrimSpace(val), `"'`)
	}
	return out
}

func TestDefaultRolesPassTheAllowList(t *testing.T) {
	for name, roles := range map[string][]string{
		"defaultAppDeployRoles":        defaultAppDeployRoles,
		"defaultAppInfraPipelineRoles": defaultAppInfraPipelineRoles,
	} {
		for _, r := range roles {
			if app_deploy_identity.NeverProjectWide(r) {
				t.Errorf("%s holds %q, which must never be granted at project level", name, r)
			}
		}
		if err := app_deploy_identity.CheckProjectRoles(roles); err != nil {
			t.Errorf("%s: %v", name, err)
		}
	}
}

func TestCommittedDeployRolesPassTheAllowList(t *testing.T) {
	plain := committedConfig(t, "_deploy_roles")
	if len(plain) == 0 {
		t.Fatal("no <app>_deploy_roles in Pulumi.production.yaml; the check would pass vacuously")
	}
	for key, val := range plain {
		roles := splitAppList(val)
		for _, r := range roles {
			if app_deploy_identity.NeverProjectWide(r) {
				t.Errorf("%s holds %q, which must never be granted at project level", key, r)
			}
		}
		if err := app_deploy_identity.CheckProjectRoles(roles); err != nil {
			t.Errorf("%s: %v", key, err)
		}
	}
	for key, val := range committedConfig(t, "_deploy_conditional_roles") {
		parsed, err := parseConditionalRoles(val)
		if err != nil {
			t.Fatalf("%s: %v", key, err)
		}
		if err := app_deploy_identity.CheckConditionalRoles(parsed); err != nil {
			t.Errorf("%s: %v", key, err)
		}
	}
	// Every app that deploys must name the runtime account it deploys as,
	// or its Cloud Run deploy loses actAs now that it is not project-wide.
	actAs := committedConfig(t, "_deploy_act_as")
	for key := range plain {
		want := strings.TrimSuffix(key, "_deploy_roles") + "_deploy_act_as"
		if len(splitAppList(actAs[want])) == 0 {
			t.Errorf("%s is set but %s is empty", key, want)
		}
	}
}
