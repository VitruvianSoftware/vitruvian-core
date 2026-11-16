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

package orgsettings

import (
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func TestOrgURL(t *testing.T) {
	for _, base := range []string{"https://sentry.lab.ipv1337.dev/api/", "https://sentry.lab.ipv1337.dev/api"} {
		if got, want := OrgURL(base, "sentry"), "https://sentry.lab.ipv1337.dev/api/0/organizations/sentry/"; got != want {
			t.Errorf("OrgURL(%q) = %q, want %q", base, got, want)
		}
	}
}

func TestDesiredScrubsIPAddresses(t *testing.T) {
	if got, want := Body(Desired), `{"scrubIPAddresses":true}`; got != want {
		t.Fatalf("Body(Desired) = %s, want %s", got, want)
	}
}

func TestScriptChecksTheServerAnswer(t *testing.T) {
	for _, want := range []string{"curl -fsS -X PUT", `"scrubIPAddresses":true`, "exit 1", "SENTRY_TOKEN"} {
		if !strings.Contains(script, want) {
			t.Errorf("script lacks %q", want)
		}
	}
	if strings.Contains(script, "set -x") || strings.Contains(script, "echo \"$token") {
		t.Error("script must never print the token")
	}
}

type mocks struct {
	mu     sync.Mutex
	inputs map[string]resource.PropertyMap
}

func (m *mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.inputs[args.TypeToken] = args.Inputs
	return args.Name + "_id", args.Inputs, nil
}

func (m *mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func TestReconcileRegistersTheCommand(t *testing.T) {
	m := &mocks{inputs: map[string]resource.PropertyMap{}}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := Reconcile(ctx, "https://sentry.example/api/", "acme")
		return err
	}, pulumi.WithMocks("project", "stack", m))
	if err != nil {
		t.Fatal(err)
	}
	in, ok := m.inputs["command:local:Command"]
	if !ok {
		t.Fatalf("no command:local:Command registered; got %v", m.inputs)
	}
	env := in["environment"].ObjectValue()
	if got := env["SENTRY_ORG_URL"].StringValue(); got != "https://sentry.example/api/0/organizations/acme/" {
		t.Errorf("SENTRY_ORG_URL = %q", got)
	}
	if got := env["SENTRY_ORG_SETTINGS"].StringValue(); got != `{"scrubIPAddresses":true}` {
		t.Errorf("SENTRY_ORG_SETTINGS = %q", got)
	}
	if in["create"].StringValue() != script || in["update"].StringValue() != script {
		t.Error("create and update must both run the script")
	}
	if in.HasValue("delete") {
		t.Error("deleting the resource must not change the setting")
	}
}
