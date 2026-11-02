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

// Pins WHO may impersonate a deploy identity. Whatever this binding names can
// deploy the application, so it must be exactly the app's own per-env GitHub
// Environment in the shared foundation pool, and nothing wider.

package app_deploy_identity

import (
	"reflect"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func runDeploy(t *testing.T, args *Args) []recorded {
	t.Helper()
	var mu sync.Mutex
	var got []recorded
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := Deploy(ctx, args.App, args)
		return err
	}, pulumi.WithMocks("proj", "stack", previewMocks{mu: &mu, got: &got}))
	if err != nil {
		t.Fatalf("Deploy: %v", err)
	}
	return got
}

func TestDeployWIFBindingIsExactlyTheEnvironmentPrincipal(t *testing.T) {
	got := runDeploy(t, &Args{
		App:                  "oauth-user-inspector",
		Env:                  "development",
		ProjectID:            pulumi.String("prj-d-bu1-oss-floating-648a"),
		DeployRoles:          []string{"roles/run.admin"},
		WorkloadIdentityPool: pulumi.String(testPool),
		GitHubEnvironment:    "oauth-user-inspector-development",
	})

	var members []string
	for _, r := range got {
		if r.typ != "gcp:serviceaccount/iAMMember:IAMMember" {
			continue
		}
		if role := r.inputs["role"].StringValue(); role != "roles/iam.workloadIdentityUser" {
			t.Errorf("%s: unexpected role %q on the deploy SA", r.name, role)
		}
		members = append(members, r.inputs["member"].StringValue())
	}
	want := "principalSet://iam.googleapis.com/" + testPool + "/attribute.environment/oauth-user-inspector-development"
	if len(members) != 1 || members[0] != want {
		t.Fatalf("WIF members on the deploy SA = %q, want exactly [%q]", members, want)
	}
}

// A repository-wide binding used to be an Args option. In a monorepo it lets
// every job in the repository impersonate the SA, so it must not come back as
// another field that switches the principal away from the Environment.
func TestArgsHasNoRepositoryWidePrincipalOption(t *testing.T) {
	typ := reflect.TypeOf(Args{})
	for i := 0; i < typ.NumField(); i++ {
		if name := typ.Field(i).Name; strings.Contains(strings.ToLower(name), "repositor") {
			t.Errorf("Args.%s: binding a deploy SA by repository widens it to every job in the repo", name)
		}
	}
}
