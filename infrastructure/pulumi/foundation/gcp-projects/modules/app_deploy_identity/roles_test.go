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

// Tests for the project-role allow-list (roles.go). What they pin: no role
// that lets a principal act as, mint tokens for, or manage service accounts can
// be granted at project level by this module, whether by widening the
// allow-list or by passing it in from a caller; and the act-as permission a
// deploy does need lands on the named runtime accounts and nowhere else.

package app_deploy_identity

import (
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// The allow-lists themselves: if anyone adds a never-project-wide role (or any
// roles/iam.* / roles/resourcemanager.* role) to either list, this fails.
func TestAllowListsHoldNoProjectWideImpersonationRole(t *testing.T) {
	for name, list := range map[string]map[string]bool{
		"allowedProjectRoles":            allowedProjectRoles,
		"allowedConditionalProjectRoles": allowedConditionalProjectRoles,
	} {
		for role := range list {
			if isNeverProjectWide(role) {
				t.Errorf("%s contains %q, which must never be granted at project level", name, role)
			}
		}
	}
}

// The deny list must keep covering the roles it exists for; a trimmed list
// would let the test above pass vacuously.
func TestNeverProjectWideCoversTheImpersonationRoles(t *testing.T) {
	for _, role := range []string{
		"roles/owner", "roles/editor",
		"roles/iam.serviceAccountUser", "roles/iam.serviceAccountTokenCreator",
		"roles/iam.workloadIdentityUser", "roles/iam.serviceAccountKeyAdmin",
		"roles/iam.serviceAccountAdmin", "roles/resourcemanager.projectIamAdmin",
	} {
		if !isNeverProjectWide(role) {
			t.Errorf("isNeverProjectWide(%q) = false", role)
		}
	}
}

// refusedRoles is every role a caller must not be able to pass in: the deny
// list plus one ordinary role that simply is not on the allow-list.
func refusedRoles() []string {
	return append(append([]string{}, neverProjectWide...), "roles/storage.admin", "roles/run.developer")
}

func projectGrantCount(t *testing.T, got []recorded) int {
	t.Helper()
	n := 0
	for _, r := range got {
		pairs, _ := iamGrants(t, r, "projects")
		n += len(pairs)
	}
	return n
}

// A caller passing any refused role, plain or conditioned, fails the program
// before a single project grant is declared.
func TestDeployRefusesRolesOutsideTheAllowList(t *testing.T) {
	for _, role := range refusedRoles() {
		args := oauthDeployArgs()
		args.DeployRoles = []string{"roles/run.admin", role}
		got, err := runDeploy(t, args)
		if err == nil {
			t.Errorf("Deploy with DeployRoles %q succeeded; want a refusal", role)
		} else if !strings.Contains(err.Error(), role) {
			t.Errorf("refusal for %q does not name the role: %v", role, err)
		}
		if n := projectGrantCount(t, got); n != 0 {
			t.Errorf("%q: %d project grants declared before the refusal; want 0", role, n)
		}

		args = oauthDeployArgs()
		args.ProjectNumber = pulumi.String("123")
		args.ConditionalDeployRoles = []ConditionalRole{{
			Role: role, Title: "t", Expression: `resource.name.startsWith("projects/${projectNumber}/secrets/X_")`,
		}}
		if _, err := runDeploy(t, args); err == nil {
			t.Errorf("Deploy with conditional role %q succeeded; want a refusal", role)
		}
	}
}

func runPipeline(t *testing.T, args *PipelineArgs) ([]recorded, error) {
	t.Helper()
	var mu sync.Mutex
	var got []recorded
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := DeployBUPipeline(ctx, args.BusinessCode, args)
		return err
	}, pulumi.WithMocks("proj", "stack", previewMocks{mu: &mu, got: &got}))
	return got, err
}

func pipelineArgs() *PipelineArgs {
	return &PipelineArgs{
		BusinessCode:         "bu1",
		Env:                  "development",
		ProjectID:            pulumi.String("prj-d-bu1-oss-floating-648a"),
		Roles:                []string{"roles/run.admin", "roles/serviceusage.serviceUsageConsumer", "roles/logging.viewer"},
		ActAsServiceAccounts: []string{"oauth-user-inspector-rt"},
		WorkloadIdentityPool: pulumi.String(testPool),
		GitHubEnvironment:    "foundation-app-development",
	}
}

func TestPipelineRefusesRolesOutsideTheAllowList(t *testing.T) {
	for _, role := range refusedRoles() {
		args := pipelineArgs()
		args.Roles = append(args.Roles, role)
		got, err := runPipeline(t, args)
		if err == nil {
			t.Errorf("DeployBUPipeline with role %q succeeded; want a refusal", role)
		}
		if n := projectGrantCount(t, got); n != 0 {
			t.Errorf("%q: %d project grants declared before the refusal; want 0", role, n)
		}
	}
}

// actAsGrants returns "<role> <service account> <member>" for every service
// account grant that is NOT the WIF binding.
func actAsGrants(got []recorded) []string {
	var out []string
	for _, r := range got {
		if r.typ != "gcp:serviceaccount/iAMMember:IAMMember" {
			continue
		}
		role := r.inputs["role"].StringValue()
		if role == "roles/iam.workloadIdentityUser" {
			continue
		}
		out = append(out, role+" "+r.inputs["serviceAccountId"].StringValue()+" "+r.inputs["member"].StringValue())
	}
	return out
}

// The deploy SA can act as exactly the named runtime account, in its own
// project, and holds no service-account role at project level.
func TestDeployActAsIsScopedToTheNamedRuntimeAccount(t *testing.T) {
	const p = "prj-d-bu1-oss-floating-648a"
	args := oauthDeployArgs()
	args.DeployRoles = []string{"roles/run.admin", "roles/serviceusage.serviceUsageConsumer", "roles/logging.viewer"}
	args.ActAsServiceAccounts = []string{"oauth-user-inspector-rt"}
	got, err := runDeploy(t, args)
	if err != nil {
		t.Fatalf("Deploy: %v", err)
	}
	want := "roles/iam.serviceAccountUser projects/" + p + "/serviceAccounts/oauth-user-inspector-rt@" + p +
		".iam.gserviceaccount.com serviceAccount:oauth-user-inspector-deploy@" + p + ".iam.gserviceaccount.com"
	if g := actAsGrants(got); len(g) != 1 || g[0] != want {
		t.Errorf("act-as grants = %q, want exactly [%q]", g, want)
	}
	for _, r := range got {
		pairs, _ := iamGrants(t, r, "projects")
		for _, pr := range pairs {
			if role, _, _ := strings.Cut(pr, " "); isNeverProjectWide(role) {
				t.Errorf("%s: project-level %s", r.name, role)
			}
		}
	}
}

func TestPipelineActAsIsScopedToTheNamedRuntimeAccount(t *testing.T) {
	got, err := runPipeline(t, pipelineArgs())
	if err != nil {
		t.Fatalf("DeployBUPipeline: %v", err)
	}
	g := actAsGrants(got)
	if len(g) != 1 || !strings.Contains(g[0], "/serviceAccounts/oauth-user-inspector-rt@") {
		t.Errorf("act-as grants = %q, want exactly one on oauth-user-inspector-rt", g)
	}
}

// Act-as targets are bare ids in the same project, and never another
// platform-issued identity.
func TestActAsRefusesPlatformIdentitiesAndForeignAccounts(t *testing.T) {
	for _, id := range []string{
		"oauth-user-inspector-deploy", // this app's own deploy SA
		"tabula-deploy",               // another app's deploy SA
		"sa-tabula-deploy-dev",        // standard deploy naming
		"tabula-preview",              // a preview identity
		"sa-app-infra-bu1",            // the BU pipeline identity
		"x@prj-c-cicd-1064807322707.iam.gserviceaccount.com", // an email (other project)
		"projects/p/serviceAccounts/x",                       // a resource name
		"rt",                                                 // too short
	} {
		args := oauthDeployArgs()
		args.ActAsServiceAccounts = []string{id}
		if _, err := runDeploy(t, args); err == nil {
			t.Errorf("Deploy with act-as %q succeeded; want a refusal", id)
		}
		pa := pipelineArgs()
		pa.ActAsServiceAccounts = []string{id}
		if _, err := runPipeline(t, pa); err == nil {
			t.Errorf("DeployBUPipeline with act-as %q succeeded; want a refusal", id)
		}
	}
}
