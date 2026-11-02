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
// references (no outputs, so stage 5 takes its fail-closed path).
type envMocks struct {
	mu        sync.Mutex
	resources map[string][]resource.PropertyMap
}

func (m *envMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.resources[args.TypeToken] = append(m.resources[args.TypeToken], args.Inputs)
	if args.TypeToken == "pulumi:pulumi:StackReference" {
		return args.Name, resource.PropertyMap{
			"name":    resource.NewStringProperty(args.Name),
			"outputs": resource.NewObjectProperty(resource.PropertyMap{}),
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

// Every Environment ending in -preview backs a pull-request run, so whatever
// GCP_SERVICE_ACCOUNT it advertises must be a read-only -preview@ account,
// never a stage deploy account. This runs the real environment functions over
// the committed stack config and checks the variables they would publish.
func TestPreviewEnvironmentsAdvertisePreviewServiceAccounts(t *testing.T) {
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

	const seed = "@prj-b-seed-c010.iam.gserviceaccount.com"
	want := map[string]string{
		"foundation-bootstrap-preview":   "sa-terraform-bootstrap-preview" + seed,
		"foundation-org-preview":         "sa-terraform-org-preview" + seed,
		"foundation-org-folders-preview": "sa-terraform-bootstrap-preview" + seed,
		"foundation-env-preview":         "sa-terraform-env-preview" + seed,
		"foundation-net-preview":         "sa-terraform-net-preview" + seed,
		"foundation-proj-preview":        "sa-terraform-proj-preview" + seed,
		"foundation-app-preview":         "sa-terraform-proj-preview" + seed,
	}

	// Environment name -> GCP_SERVICE_ACCOUNT, for every preview Environment
	// that sets one.
	got := map[string]string{}
	previewEnvs := map[string]bool{}
	for _, e := range mocks.resources["github:index/repositoryEnvironment:RepositoryEnvironment"] {
		if name := e["environment"].StringValue(); strings.HasSuffix(name, "-preview") {
			previewEnvs[name] = true
		}
	}
	for _, v := range mocks.resources["github:index/actionsEnvironmentVariable:ActionsEnvironmentVariable"] {
		env := v["environment"].StringValue()
		if !strings.HasSuffix(env, "-preview") || v["variableName"].StringValue() != "GCP_SERVICE_ACCOUNT" {
			continue
		}
		sa := v["value"].StringValue()
		if prev, dup := got[env]; dup {
			t.Errorf("%s sets GCP_SERVICE_ACCOUNT twice (%q, %q)", env, prev, sa)
		}
		got[env] = sa
		if !strings.Contains(sa, "-preview@") {
			t.Errorf("%s: GCP_SERVICE_ACCOUNT = %q, want a read-only -preview@ account", env, sa)
		}
	}

	for env, sa := range want {
		if !previewEnvs[env] {
			t.Errorf("%s: Environment not created", env)
		}
		if got[env] != sa {
			t.Errorf("%s: GCP_SERVICE_ACCOUNT = %q, want %q", env, got[env], sa)
		}
	}
	// Anything else that sets the variable is new: it still has to pass the
	// -preview@ check above, but should also be added to want.
	var extra []string
	for env := range got {
		if _, ok := want[env]; !ok {
			extra = append(extra, env)
		}
	}
	sort.Strings(extra)
	if len(extra) > 0 {
		t.Errorf("preview Environments not in the expected table: %v", extra)
	}
	// The app previews (tabula-preview, oauth-user-inspector-preview) sign in
	// with GCP_DEPLOY_SERVICE_ACCOUNT instead (TestPreviewEnvironmentsUseReadOnlyIdentity);
	// make sure they were actually exercised here.
	for _, env := range []string{"tabula-preview", "oauth-user-inspector-preview"} {
		if !previewEnvs[env] {
			t.Errorf("%s: Environment not created, so it was not checked", env)
		}
	}
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
