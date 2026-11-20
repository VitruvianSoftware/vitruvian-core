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

package filters

import (
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry/internal/config"
)

func TestDesiredForProjects(t *testing.T) {
	got := DesiredForProjects([]config.ProjectConfig{
		{Slug: "vitruviansoftware-dev"},
		{Slug: "vitruvian-devx"},
	})
	if !slices.Contains(got["vitruviansoftware-dev"], "browser-extensions") {
		t.Errorf("expected browser-extensions for web project, got %v", got["vitruviansoftware-dev"])
	}
	if !slices.Contains(got["vitruvian-devx"], "web-crawlers") || slices.Contains(got["vitruvian-devx"], "browser-extensions") {
		t.Errorf("unexpected filters for CLI project: %v", got["vitruvian-devx"])
	}
}

func TestScriptDoesNotLeakToken(t *testing.T) {
	if strings.Contains(script, "set -x") || strings.Contains(script, "echo \"$token") {
		t.Error("script must never print the token")
	}
}

type filtersMocks struct {
	mu     *sync.Mutex
	inputs *resource.PropertyMap
	ignore *[]string
}

func (m filtersMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	if args.Name == "sentry-project-filters" {
		m.mu.Lock()
		*m.inputs = args.Inputs
		if args.RegisterRPC != nil {
			*m.ignore = args.RegisterRPC.GetIgnoreChanges()
		}
		m.mu.Unlock()
	}
	return args.Name + "_id", args.Inputs, nil
}

func (filtersMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// Adding a Sentry project must be an UPDATE of the filters command, never a
// replace: the Sentry apply's plan guard refuses any replace, and Triggers
// forced one on every new project (mini-party, 2026-11-20). So the command
// carries no triggers input, and ignores the triggers already in state so
// dropping them is not a replace either.
func TestNewProjectsUpdateTheFiltersCommandInsteadOfReplacingIt(t *testing.T) {
	var inputs resource.PropertyMap
	var ignore []string
	m := filtersMocks{mu: &sync.Mutex{}, inputs: &inputs, ignore: &ignore}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := Reconcile(ctx, "https://sentry.example", "org", []config.ProjectConfig{
			{Name: "Mini Party", Slug: "mini-party", Platform: "javascript-react", ResolveAge: 720},
		})
		return err
	}, pulumi.WithMocks("sentry", "production", m))
	if err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if inputs == nil {
		t.Fatal("sentry-project-filters was not registered")
	}
	if v, ok := inputs["triggers"]; ok && !v.IsNull() {
		t.Errorf("filters command has triggers %v: a change to them replaces the command", v)
	}
	if !slices.Contains(ignore, "triggers") {
		t.Errorf("filters command ignoreChanges = %v, want it to include triggers", ignore)
	}
	env, ok := inputs["environment"]
	if !ok || !env.IsObject() || !strings.Contains(env.ObjectValue()["SENTRY_FILTERS_MAP"].StringValue(), "mini-party") {
		t.Errorf("the project map must be in environment, so a change to it runs Update: %v", env)
	}
}
