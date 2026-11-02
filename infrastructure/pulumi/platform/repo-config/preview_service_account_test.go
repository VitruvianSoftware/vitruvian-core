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
	"encoding/json"
	"os"
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
	"gopkg.in/yaml.v3"
)

// envMocks records every resource and answers the two lookups the environment
// functions make: GET /users (production reviewers) and the gcp-projects stack
// references, which return appInfraSA(<reference name>) as
// app_infra_pipeline_service_account so the stage-5 variables are exercised.
type envMocks struct {
	mu        sync.Mutex
	resources map[string][]resource.PropertyMap
}

// appInfraSA is the stand-in stack output for a gcp-projects reference such
// as projects-bu1-development.
func appInfraSA(ref string) string {
	return "sa-app-infra-" + strings.TrimPrefix(ref, "projects-") + "@example.iam.gserviceaccount.com"
}

func (m *envMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.resources[args.TypeToken] = append(m.resources[args.TypeToken], args.Inputs)
	if args.TypeToken == "pulumi:pulumi:StackReference" {
		return args.Name, resource.PropertyMap{
			"name": resource.NewStringProperty(args.Name),
			"outputs": resource.NewObjectProperty(resource.PropertyMap{
				"app_infra_pipeline_service_account": resource.NewStringProperty(appInfraSA(args.Name)),
			}),
		}, nil
	}
	return args.Name + "-id", args.Inputs, nil
}

func (m *envMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	if args.Token == "github:index/getUser:getUser" {
		return resource.PropertyMap{"id": resource.NewStringProperty("1")}, nil
	}
	return args.Args, nil
}

// stackConfigEnv renders Pulumi.dev.yaml's config block in the PULUMI_CONFIG
// form the mock engine reads: scalars verbatim, maps and lists as JSON.
func stackConfigEnv(t *testing.T) string {
	t.Helper()
	raw, err := os.ReadFile("Pulumi.dev.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var stack struct {
		Config map[string]yaml.Node `yaml:"config"`
	}
	if err := yaml.Unmarshal(raw, &stack); err != nil {
		t.Fatal(err)
	}
	out := map[string]string{}
	for k, node := range stack.Config {
		if node.Kind == yaml.ScalarNode {
			out[k] = node.Value
			continue
		}
		var v any
		if err := node.Decode(&v); err != nil {
			t.Fatalf("decoding %s: %v", k, err)
		}
		b, err := json.Marshal(v)
		if err != nil {
			t.Fatalf("encoding %s: %v", k, err)
		}
		out[k] = string(b)
	}
	b, err := json.Marshal(out)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// runEnvironments runs the real environment functions over the committed
// stack config and returns every published Actions variable, keyed by
// Environment and then variable name, plus the set of Environments created.
func runEnvironments(t *testing.T) (vars map[string]map[string]string, envs map[string]bool) {
	t.Helper()
	t.Setenv("PULUMI_CONFIG", stackConfigEnv(t))

	mocks := &envMocks{resources: map[string][]resource.PropertyMap{}}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "")
		repo, err := github.NewRepository(ctx, "vitruvian-core", &github.RepositoryArgs{
			Name: pulumi.String("vitruvian-core"),
		})
		if err != nil {
			return err
		}
		if err := tabulaEnvironments(ctx, cfg, repo); err != nil {
			return err
		}
		if err := oauthEnvironment(ctx, cfg, repo); err != nil {
			return err
		}
		return foundationEnvironments(ctx, cfg, repo)
	}, pulumi.WithMocks("vitruvian-core-repo-config", "dev", mocks))
	if err != nil {
		t.Fatalf("environment functions: %v", err)
	}

	envs = map[string]bool{}
	for _, e := range mocks.resources["github:index/repositoryEnvironment:RepositoryEnvironment"] {
		envs[e["environment"].StringValue()] = true
	}
	vars = map[string]map[string]string{}
	for _, v := range mocks.resources["github:index/actionsEnvironmentVariable:ActionsEnvironmentVariable"] {
		env, name, value := v["environment"].StringValue(), v["variableName"].StringValue(), v["value"].StringValue()
		if vars[env] == nil {
			vars[env] = map[string]string{}
		}
		if prev, dup := vars[env][name]; dup {
			t.Errorf("%s sets %s twice (%q, %q)", env, name, prev, value)
		}
		vars[env][name] = value
	}
	return vars, envs
}

func isServiceAccountEmail(v string) bool {
	v = strings.ToLower(strings.TrimSpace(v))
	return strings.HasSuffix(v, ".iam.gserviceaccount.com") && strings.Contains(v, "@")
}

// previewValueProblem says what is wrong with one variable a -preview
// Environment publishes, or "" if nothing is. Values are compared trimmed, so
// surrounding whitespace or a trailing newline cannot carry a deploy account
// past the -preview@ check; and an untrimmed value is refused outright, since
// nothing a workflow reads from these variables should need it.
func previewValueProblem(value string) string {
	if value != strings.TrimSpace(value) {
		return "has surrounding whitespace; publish it trimmed"
	}
	if !isServiceAccountEmail(value) {
		return ""
	}
	local, _, _ := strings.Cut(strings.ToLower(value), "@")
	if !strings.HasSuffix(local, "-preview") {
		return "is not a read-only -preview@ account"
	}
	return ""
}

// checkServiceAccounts compares each Environment's GCP_SERVICE_ACCOUNT with
// want, and reports any Environment matching scope that sets the variable but
// is missing from want.
func checkServiceAccounts(t *testing.T, vars map[string]map[string]string, envs map[string]bool, want map[string]string, scope func(string) bool) {
	t.Helper()
	for env, sa := range want {
		if !envs[env] {
			t.Errorf("%s: Environment not created", env)
		}
		if got := vars[env]["GCP_SERVICE_ACCOUNT"]; got != sa {
			t.Errorf("%s: GCP_SERVICE_ACCOUNT = %q, want %q", env, got, sa)
		}
	}
	var extra []string
	for env, vs := range vars {
		if _, set := vs["GCP_SERVICE_ACCOUNT"]; set && scope(env) {
			if _, ok := want[env]; !ok {
				extra = append(extra, env)
			}
		}
	}
	sort.Strings(extra)
	if len(extra) > 0 {
		t.Errorf("Environments setting GCP_SERVICE_ACCOUNT that are not in the expected table: %v", extra)
	}
}

const seedSA = "@prj-b-seed-c010.iam.gserviceaccount.com"

// Every Environment ending in -preview backs a pull-request run, so every
// service account it advertises, under any variable name, must be a
// read-only -preview@ account, and each foundation preview Environment's
// GCP_SERVICE_ACCOUNT must be exactly its stage's preview account.
func TestPreviewEnvironmentsAdvertisePreviewServiceAccounts(t *testing.T) {
	vars, envs := runEnvironments(t)

	for env, vs := range vars {
		if !strings.HasSuffix(env, "-preview") {
			continue
		}
		for name, value := range vs {
			if problem := previewValueProblem(value); problem != "" {
				t.Errorf("%s: %s = %q %s", env, name, value, problem)
			}
		}
	}

	checkServiceAccounts(t, vars, envs, map[string]string{
		"foundation-bootstrap-preview":   "sa-terraform-bootstrap-preview" + seedSA,
		"foundation-org-preview":         "sa-terraform-org-preview" + seedSA,
		"foundation-org-folders-preview": "sa-terraform-bootstrap-preview" + seedSA,
		"foundation-env-preview":         "sa-terraform-env-preview" + seedSA,
		"foundation-net-preview":         "sa-terraform-net-preview" + seedSA,
		"foundation-proj-preview":        "sa-terraform-proj-preview" + seedSA,
		"foundation-app-preview":         "sa-terraform-proj-preview" + seedSA,
	}, func(env string) bool { return strings.HasSuffix(env, "-preview") })

	// The app previews sign in with GCP_DEPLOY_SERVICE_ACCOUNT instead (see
	// TestPreviewEnvironmentsUseReadOnlyIdentity); make sure the any-variable
	// check above actually saw them.
	for _, env := range []string{"tabula-preview", "oauth-user-inspector-preview"} {
		if !envs[env] || vars[env]["GCP_DEPLOY_SERVICE_ACCOUNT"] == "" {
			t.Errorf("%s: Environment or its GCP_DEPLOY_SERVICE_ACCOUNT not created, so it was not checked", env)
		}
	}
}

// The foundation deploy Environments keep their stage's deploy account; the
// preview change must not leak into them.
func TestFoundationDeployEnvironmentsKeepDeployServiceAccounts(t *testing.T) {
	vars, envs := runEnvironments(t)

	want := map[string]string{
		"foundation-bootstrap":   "sa-terraform-bootstrap" + seedSA,
		"foundation-org":         "sa-terraform-org" + seedSA,
		"foundation-org-folders": "sa-terraform-bootstrap" + seedSA,
	}
	for _, stage := range []struct {
		name string
		envs []string
	}{
		{"env", []string{"development", "nonproduction", "production"}},
		{"net", []string{"development", "nonproduction", "shared", "production"}},
		{"proj", []string{"development", "nonproduction", "shared", "production"}},
	} {
		for _, e := range stage.envs {
			want["foundation-"+stage.name+"-"+e] = "sa-terraform-" + stage.name + seedSA
		}
	}
	// Stage 5 takes its account from the gcp-projects stack output.
	for _, bu := range []struct{ prefix, bu string }{{"foundation-app-", "bu1"}, {"foundation-app-bu2-", "bu2"}} {
		for _, e := range []string{"development", "nonproduction", "production"} {
			want[bu.prefix+e] = appInfraSA("projects-" + bu.bu + "-" + e)
		}
	}

	checkServiceAccounts(t, vars, envs, want, func(env string) bool {
		return strings.HasPrefix(env, "foundation-") && !strings.HasSuffix(env, "-preview")
	})
}

func TestPreviewFoundationVars(t *testing.T) {
	in := map[string]string{
		"GCP_PROJECT_ID":                 "prj-b-seed-c010",
		"GCP_SERVICE_ACCOUNT":            "sa-terraform-org@prj-b-seed-c010.iam.gserviceaccount.com",
		"GCP_WORKLOAD_IDENTITY_PROVIDER": "projects/1/locations/global/workloadIdentityPools/p/providers/x",
	}
	out, err := previewFoundationVars(in)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := out["GCP_SERVICE_ACCOUNT"], "sa-terraform-org-preview@prj-b-seed-c010.iam.gserviceaccount.com"; got != want {
		t.Errorf("GCP_SERVICE_ACCOUNT = %q, want %q", got, want)
	}
	for _, k := range []string{"GCP_PROJECT_ID", "GCP_WORKLOAD_IDENTITY_PROVIDER"} {
		if out[k] != in[k] {
			t.Errorf("%s = %q, want it unchanged (%q)", k, out[k], in[k])
		}
	}
	if in["GCP_SERVICE_ACCOUNT"] != "sa-terraform-org@prj-b-seed-c010.iam.gserviceaccount.com" {
		t.Error("input map was modified")
	}

	for _, bad := range []string{"", "not-an-email", "@prj.iam.gserviceaccount.com", "sa-terraform-org-preview@prj-b-seed-c010.iam.gserviceaccount.com"} {
		if _, err := previewFoundationVars(map[string]string{"GCP_SERVICE_ACCOUNT": bad}); err == nil {
			t.Errorf("previewFoundationVars(%q) = nil error, want one", bad)
		}
	}
}

// The -preview@ check must not be slipped past by whitespace, a trailing
// newline or letter case, and must still pass the values it should.
func TestPreviewValueProblem(t *testing.T) {
	for _, tc := range []struct {
		value string
		ok    bool
	}{
		{"sa-terraform-org-preview@prj-b-seed-c010.iam.gserviceaccount.com", true},
		{"tabula-preview@prj-d-bu2-oss-floating-c3d1.iam.gserviceaccount.com", true},
		{"prj-b-seed-c010", true},
		{"projects/1/locations/global/workloadIdentityPools/p/providers/x", true},
		{"sa-terraform-org@prj-b-seed-c010.iam.gserviceaccount.com", false},
		{"sa-terraform-org@prj-b-seed-c010.iam.gserviceaccount.com\n", false},
		{" sa-terraform-org@prj-b-seed-c010.iam.gserviceaccount.com", false},
		{" sa-terraform-org-preview@prj-b-seed-c010.iam.gserviceaccount.com\n", false},
		{"\tsa-terraform-org@prj-b-seed-c010.iam.gserviceaccount.com", false},
		{"SA-TERRAFORM-ORG@PRJ-B-SEED-C010.IAM.GSERVICEACCOUNT.COM", false},
		{"sa-terraform-org@x-preview@prj-b-seed-c010.iam.gserviceaccount.com", false},
		{"prj-b-seed-c010\n", false},
	} {
		if got := previewValueProblem(tc.value) == ""; got != tc.ok {
			t.Errorf("previewValueProblem(%q): accepted = %v, want %v", tc.value, got, tc.ok)
		}
	}
}
