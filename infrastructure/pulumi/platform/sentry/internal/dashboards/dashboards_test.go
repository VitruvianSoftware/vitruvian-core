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

package dashboards

import (
	"encoding/json"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func TestDashboardsURL(t *testing.T) {
	for _, base := range []string{"https://sentry.lab.ipv1337.dev/api/", "https://sentry.lab.ipv1337.dev/api"} {
		if got, want := DashboardsURL(base, "sentry"), "https://sentry.lab.ipv1337.dev/api/0/organizations/sentry/dashboards/"; got != want {
			t.Errorf("DashboardsURL(%q) = %q, want %q", base, got, want)
		}
	}
}

func TestDefaultDashboardsValid(t *testing.T) {
	defs := DefaultDashboards()
	if len(defs) != 3 {
		t.Fatalf("len(DefaultDashboards()) = %d, want 3", len(defs))
	}
	for _, d := range defs {
		if d.Title == "" || len(d.Widgets) == 0 {
			t.Fatalf("invalid dashboard %+v", d)
		}
		for _, w := range d.Widgets {
			if w.WidgetType != "error-events" {
				t.Errorf("widget %q has widgetType %q, want error-events", w.Title, w.WidgetType)
			}
			if len(w.Queries) == 0 {
				t.Errorf("widget %q has no queries", w.Title)
			}
		}
		raw, err := Body(d)
		if err != nil {
			t.Fatalf("Body(%q): %v", d.Title, err)
		}
		var roundtrip Dashboard
		if err := json.Unmarshal([]byte(raw), &roundtrip); err != nil {
			t.Fatalf("unmarshal %q: %v", d.Title, err)
		}
	}
}

func TestScriptDoesNotLeakToken(t *testing.T) {
	if strings.Contains(script, "set -x") || strings.Contains(script, "echo \"$token") {
		t.Error("script must never print the token")
	}
}

type mocks struct {
	mu    sync.Mutex
	count int
}

func (m *mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.count++
	return args.Name + "_id", args.Inputs, nil
}

func (m *mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func TestReconcileRegistersDashboards(t *testing.T) {
	m := &mocks{}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cmds, err := Reconcile(ctx, "https://sentry.example/api/", "sentry")
		if err != nil {
			return err
		}
		if len(cmds) != 3 {
			t.Fatalf("len(cmds) = %d, want 3", len(cmds))
		}
		return nil
	}, pulumi.WithMocks("project", "stack", m))
	if err != nil {
		t.Fatal(err)
	}
	if m.count != 3 {
		t.Errorf("registered %d resources, want 3", m.count)
	}
}
