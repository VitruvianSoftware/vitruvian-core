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

// iamGrants returns every (role, principal) pair r grants under the given
// provider module ("serviceaccount" or "projects"), whichever IAM resource
// type carries it (member, binding or whole policy), and whether r is such an
// IAM resource at all. An unknown IAM type in that module is reported rather
// than skipped, so a new way to grant cannot hide.
func iamGrants(t *testing.T, r recorded, module string) (pairs []string, isIAM bool) {
	t.Helper()
	str := func(k string) string {
		if v, ok := r.inputs[resource.PropertyKey(k)]; ok && v.IsString() {
			return v.StringValue()
		}
		return ""
	}
	switch r.typ {
	case "gcp:" + module + "/iAMMember:IAMMember":
		return []string{str("role") + " " + str("member")}, true
	case "gcp:" + module + "/iAMBinding:IAMBinding":
		if v, ok := r.inputs["members"]; ok && v.IsArray() {
			for _, m := range v.ArrayValue() {
				pairs = append(pairs, str("role")+" "+m.StringValue())
			}
		}
		return pairs, true
	case "gcp:" + module + "/iAMPolicy:IAMPolicy":
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
	if strings.HasPrefix(r.typ, "gcp:"+module+"/") && strings.Contains(strings.ToLower(r.typ), "iam") {
		t.Errorf("%s: unhandled %s IAM type %s", r.name, module, r.typ)
		return nil, true
	}
	return nil, false
}

// assertOnlyEnvironmentPrincipal checks that the grants on the deploy SA,
// across every IAM resource type, are exactly the Environment principalSet.
func assertOnlyEnvironmentPrincipal(t *testing.T, got []recorded, env string) {
	t.Helper()
	// Only grants ON the deploy SA count here; act-as grants the deploy SA
	// holds on runtime accounts are asserted in roles_test.go.
	deploySA := ""
	for _, r := range got {
		if r.typ == "gcp:serviceaccount/account:Account" && strings.HasSuffix(r.name, "-deploy-sa") {
			deploySA = r.inputs["name"].StringValue()
		}
	}
	if deploySA == "" {
		t.Fatal("deploy SA not declared")
	}
	var grants []string
	for _, r := range got {
		if v, ok := r.inputs["serviceAccountId"]; ok && v.IsString() && v.StringValue() != deploySA {
			continue
		}
		pairs, _ := iamGrants(t, r, "serviceaccount")
		grants = append(grants, pairs...)
	}
	sort.Strings(grants)
	want := []string{"roles/iam.workloadIdentityUser principalSet://iam.googleapis.com/" + testPool +
		"/attribute.environment/" + env}
	if !reflect.DeepEqual(grants, want) {
		t.Errorf("grants on the deploy SA = %q, want exactly %q", grants, want)
	}
}

// Every grant on the deploy service account, through ANY service account IAM
// resource type (member, binding or whole policy), taken together, must be
// exactly one: workloadIdentityUser for the app's own Environment principal.
func TestDeployWIFBindingIsExactlyTheEnvironmentPrincipal(t *testing.T) {
	got, err := runDeploy(t, oauthDeployArgs())
	if err != nil {
		t.Fatalf("Deploy: %v", err)
	}
	assertOnlyEnvironmentPrincipal(t, got, "oauth-user-inspector-development")
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

// expectedArgsFields is the complete input surface of Args. A repository-wide
// binding option used to live here and widened the deploy SA to every job in
// the repo; pinning the whole list means any new field, under any name, needs
// a visible edit to this test. When you add one, say here why it cannot change
// who may impersonate the deploy SA, and make sure
// TestDeployGrantsAreUnchangedWithEveryStringFieldSet still exercises it.
var expectedArgsFields = []string{
	"App string",
	"Env string",
	"ProjectID pulumi.StringInput",
	"DeployAccountID string",
	"DeployRoles []string",
	"WorkloadIdentityPool pulumi.StringInput",
	"GitHubEnvironment string",
	"ConditionalDeployRoles []app_deploy_identity.ConditionalRole",
	"ProjectNumber pulumi.StringInput",
	"ActAsServiceAccounts []string",
	"ServiceAccountNamingScheme string",
}

func TestArgsFieldsArePinned(t *testing.T) {
	typ := reflect.TypeOf(Args{})
	var got []string
	for i := 0; i < typ.NumField(); i++ {
		f := typ.Field(i)
		got = append(got, f.Name+" "+f.Type.String())
	}
	if !reflect.DeepEqual(got, expectedArgsFields) {
		t.Errorf("Args fields = %q\nwant %q\n(a new field must be added to expectedArgsFields on purpose; see its comment)", got, expectedArgsFields)
	}
}

// Whatever optional string settings are turned on, the deploy SA's grants
// stay exactly the Environment principal. Every string and StringInput field
// still at its zero value is filled with a non-empty dummy, so a field that
// switches or adds a principal when set (whatever it is called) is caught.
func TestDeployGrantsAreUnchangedWithEveryStringFieldSet(t *testing.T) {
	args := oauthDeployArgs()
	v := reflect.ValueOf(args).Elem()
	stringInput := reflect.TypeOf((*pulumi.StringInput)(nil)).Elem()
	var filled []string
	for i := 0; i < v.NumField(); i++ {
		f, name := v.Field(i), v.Type().Field(i).Name
		switch {
		case f.Kind() == reflect.String && f.String() == "":
			f.SetString("dummy-" + strings.ToLower(name))
			filled = append(filled, name)
		case f.Type() == stringInput && f.IsNil():
			f.Set(reflect.ValueOf(pulumi.String("dummy-" + strings.ToLower(name))))
			filled = append(filled, name)
		}
	}
	if len(filled) == 0 {
		t.Fatal("no optional string field was filled; the test exercises nothing")
	}
	t.Logf("filled: %v", filled)

	got, err := runDeploy(t, args)
	if err != nil {
		t.Fatalf("Deploy with every string field set: %v", err)
	}
	assertOnlyEnvironmentPrincipal(t, got, "oauth-user-inspector-development")
}

// Project-level grants must go to the deploy SA itself and nobody else. In
// particular no GitHub federation principal (principal:// or principalSet://)
// may get workloadIdentityUser, serviceAccountTokenCreator or
// serviceAccountUser at project scope, which would reach every service account
// in the shared project.
func TestProjectGrantsGoOnlyToTheDeploySA(t *testing.T) {
	args := oauthDeployArgs()
	args.DeployRoles = []string{"roles/run.admin", "roles/logging.viewer"}
	args.ConditionalDeployRoles = []ConditionalRole{{
		Role:       "roles/secretmanager.secretAccessor",
		Title:      "own secrets",
		Expression: `resource.name.startsWith("projects/${projectNumber}/secrets/X_")`,
	}}
	args.ProjectNumber = pulumi.String("123")
	got, err := runDeploy(t, args)
	if err != nil {
		t.Fatalf("Deploy: %v", err)
	}

	email := ""
	for _, r := range got {
		if r.typ == "gcp:serviceaccount/account:Account" {
			email = r.inputs["email"].StringValue()
		}
	}
	if email == "" {
		t.Fatal("deploy SA not declared")
	}
	sensitive := map[string]bool{
		"roles/iam.workloadIdentityUser":       true,
		"roles/iam.serviceAccountTokenCreator": true,
		"roles/iam.serviceAccountUser":         true,
	}
	n := 0
	for _, r := range got {
		pairs, _ := iamGrants(t, r, "projects")
		for _, p := range pairs {
			n++
			role, member, _ := strings.Cut(p, " ")
			if strings.HasPrefix(member, "principal") && sensitive[role] {
				t.Errorf("%s: project-wide %s for federation principal %q", r.name, role, member)
			}
			if member != "serviceAccount:"+email {
				t.Errorf("%s: project grant %s to %q, want only the deploy SA (%s)", r.name, role, member, email)
			}
		}
	}
	if n != 3 {
		t.Errorf("saw %d project grants, want 3 (two plain, one conditioned)", n)
	}
}
