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
	"encoding/json"
	"reflect"
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func runDeploy(t *testing.T, args *Args) ([]recorded, error) {
	t.Helper()
	var mu sync.Mutex
	var got []recorded
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := Deploy(ctx, args.App, args)
		return err
	}, pulumi.WithMocks("proj", "stack", previewMocks{mu: &mu, got: &got}))
	return got, err
}

func oauthDeployArgs() *Args {
	return &Args{
		App:                  "oauth-user-inspector",
		Env:                  "development",
		ProjectID:            pulumi.String("prj-d-bu1-oss-floating-648a"),
		DeployRoles:          []string{"roles/run.admin"},
		WorkloadIdentityPool: pulumi.String(testPool),
		GitHubEnvironment:    "oauth-user-inspector-development",
	}
}

// saGrants returns every (role, principal) pair granted on a service account
// by r, whichever IAM resource type carries it, and whether r is a service
// account IAM resource at all. An unknown service account IAM type is
// reported rather than skipped, so a new way to grant cannot hide.
func saGrants(t *testing.T, r recorded) (pairs []string, isSAIAM bool) {
	t.Helper()
	str := func(k string) string {
		if v, ok := r.inputs[resource.PropertyKey(k)]; ok && v.IsString() {
			return v.StringValue()
		}
		return ""
	}
	switch r.typ {
	case "gcp:serviceaccount/iAMMember:IAMMember":
		return []string{str("role") + " " + str("member")}, true
	case "gcp:serviceaccount/iAMBinding:IAMBinding":
		if v, ok := r.inputs["members"]; ok && v.IsArray() {
			for _, m := range v.ArrayValue() {
				pairs = append(pairs, str("role")+" "+m.StringValue())
			}
		}
		return pairs, true
	case "gcp:serviceaccount/iAMPolicy:IAMPolicy":
		var policy struct {
			Bindings []struct {
				Role    string   `json:"role"`
				Members []string `json:"members"`
			} `json:"bindings"`
		}
		if err := json.Unmarshal([]byte(str("policyData")), &policy); err != nil {
			t.Errorf("%s: unreadable policyData: %v", r.name, err)
		}
		for _, b := range policy.Bindings {
			for _, m := range b.Members {
				pairs = append(pairs, b.Role+" "+m)
			}
		}
		return pairs, true
	}
	if strings.HasPrefix(r.typ, "gcp:serviceaccount/") && strings.Contains(strings.ToLower(r.typ), "iam") {
		t.Errorf("%s: unhandled service account IAM type %s", r.name, r.typ)
		return nil, true
	}
	return nil, false
}

// Every grant on the deploy service account, through ANY service account IAM
// resource type (member, binding or whole policy), taken together, must be
// exactly one: workloadIdentityUser for the app's own Environment principal.
func TestDeployWIFBindingIsExactlyTheEnvironmentPrincipal(t *testing.T) {
	got, err := runDeploy(t, oauthDeployArgs())
	if err != nil {
		t.Fatalf("Deploy: %v", err)
	}

	var grants []string
	for _, r := range got {
		pairs, _ := saGrants(t, r)
		grants = append(grants, pairs...)
	}
	sort.Strings(grants)
	want := []string{"roles/iam.workloadIdentityUser principalSet://iam.googleapis.com/" + testPool +
		"/attribute.environment/oauth-user-inspector-development"}
	if !reflect.DeepEqual(grants, want) {
		t.Fatalf("grants on the deploy SA = %q, want exactly %q", grants, want)
	}
}

// The Environment is the isolation layer; without one, the principal would be
// ".../attribute.environment/", so the module must refuse rather than build it.
func TestDeployRefusesEmptyGitHubEnvironment(t *testing.T) {
	args := oauthDeployArgs()
	args.GitHubEnvironment = ""
	got, err := runDeploy(t, args)
	if err == nil {
		t.Fatalf("Deploy with an empty GitHubEnvironment succeeded and declared %d resources; want an error", len(got))
	}
	if !strings.Contains(err.Error(), "GitHubEnvironment") {
		t.Errorf("error %q does not name GitHubEnvironment", err)
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
