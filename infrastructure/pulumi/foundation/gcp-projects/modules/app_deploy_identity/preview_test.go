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

// Tests for the read-only preview identity (#4120). What they pin is the
// SECURITY property: whatever this identity holds, every unmerged branch holds.
// So it must be bound to a dedicated *-preview Environment (never the deploy
// one), hold only read-only roles, and never touch the deploy identity's
// resources.

package app_deploy_identity

import (
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type recorded struct {
	typ, name string
	inputs    resource.PropertyMap
}

type previewMocks struct {
	mu  *sync.Mutex
	got *[]recorded
}

// NewResource records each resource and synthesises the computed fields the
// assertions read: GCP derives a service account's email and name from
// accountId + project, so without this they come back empty.
func (m previewMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	out := args.Inputs.Copy()
	if args.TypeToken == "gcp:serviceaccount/account:Account" {
		acct := out["accountId"].StringValue()
		proj := out["project"].StringValue()
		email := acct + "@" + proj + ".iam.gserviceaccount.com"
		out["email"] = resource.NewStringProperty(email)
		out["name"] = resource.NewStringProperty("projects/" + proj + "/serviceAccounts/" + email)
	}
	m.mu.Lock()
	*m.got = append(*m.got, recorded{typ: args.TypeToken, name: args.Name, inputs: out})
	m.mu.Unlock()
	return args.Name + "-id", out, nil
}

func (previewMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

const testPool = "projects/1064807322707/locations/global/workloadIdentityPools/foundation-pool"

func tabulaPreviewArgs() *PreviewArgs {
	return &PreviewArgs{
		App:                  "tabula",
		Env:                  "development",
		ProjectID:            pulumi.String("prj-d-bu2-oss-floating-c3d1"),
		WorkloadIdentityPool: pulumi.String(testPool),
		GitHubEnvironment:    "tabula-preview",
	}
}

func runPreview(t *testing.T, args *PreviewArgs) []recorded {
	t.Helper()
	var mu sync.Mutex
	var got []recorded
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := DeployPreview(ctx, args.App, args)
		return err
	}, pulumi.WithMocks("proj", "stack", previewMocks{mu: &mu, got: &got}))
	if err != nil {
		t.Fatalf("DeployPreview: %v", err)
	}
	return got
}

// The whole resource set, exactly: one SA, roles/viewer only, one WIF binding
// to the PREVIEW environment. Anything more is a widening of what every
// unmerged branch can do.
func TestDeployPreviewCreatesOnlyReadOnlyGrants(t *testing.T) {
	got := runPreview(t, tabulaPreviewArgs())

	var sa, roles, wif []recorded
	for _, r := range got {
		switch r.typ {
		case "gcp:serviceaccount/account:Account":
			sa = append(sa, r)
		case "gcp:projects/iAMMember:IAMMember":
			roles = append(roles, r)
		case "gcp:serviceaccount/iAMMember:IAMMember":
			wif = append(wif, r)
		default:
			t.Errorf("unexpected resource %s (%s)", r.name, r.typ)
		}
	}

	if len(sa) != 1 {
		t.Fatalf("got %d service accounts, want 1", len(sa))
	}
	if id := sa[0].inputs["accountId"].StringValue(); id != "tabula-preview" {
		t.Errorf("accountId = %q, want tabula-preview", id)
	}

	if len(roles) != 1 {
		t.Fatalf("got %d project role grants, want exactly 1 (roles/viewer)", len(roles))
	}
	if role := roles[0].inputs["role"].StringValue(); role != "roles/viewer" {
		t.Errorf("project role = %q, want roles/viewer", role)
	}
	if _, conditioned := roles[0].inputs["condition"]; conditioned {
		t.Errorf("roles/viewer should be unconditioned")
	}
	if m := roles[0].inputs["member"].StringValue(); m != "serviceAccount:tabula-preview@prj-d-bu2-oss-floating-c3d1.iam.gserviceaccount.com" {
		t.Errorf("viewer member = %q", m)
	}

	if len(wif) != 1 {
		t.Fatalf("got %d WIF bindings, want 1", len(wif))
	}
	wantMember := "principalSet://iam.googleapis.com/" + testPool + "/attribute.environment/tabula-preview"
	if m := wif[0].inputs["member"].StringValue(); m != wantMember {
		t.Errorf("WIF member = %q, want %q", m, wantMember)
	}
	if role := wif[0].inputs["role"].StringValue(); role != "roles/iam.workloadIdentityUser" {
		t.Errorf("WIF role = %q", role)
	}
}

// The preview identity must never share a Pulumi resource name with the deploy
// identity in the same stack. A collision is an engine error at best; at worst
// a later refactor "merges" them and the deploy SA's live bindings are deleted.
func TestPreviewResourceNamesDoNotCollideWithDeploy(t *testing.T) {
	got := runPreview(t, tabulaPreviewArgs())
	deployNames := map[string]bool{
		"tabula-deploy-sa":           true,
		"tabula-wif-impersonation":   true,
		"tabula-deploy-roles-viewer": true,
	}
	for _, r := range got {
		if deployNames[r.name] || strings.Contains(r.name, "-deploy-") {
			t.Errorf("preview resource %q collides with the deploy identity's naming", r.name)
		}
		if !strings.HasPrefix(r.name, "tabula-preview-") {
			t.Errorf("preview resource %q lacks the tabula-preview- prefix", r.name)
		}
	}
}

// Binding the preview identity to the deploy Environment would leave the hole
// open; binding it to an arbitrary name would make the Environment's purpose
// invisible. Only <name>-preview is accepted.
func TestPreviewRefusesNonPreviewEnvironment(t *testing.T) {
	for _, env := range []string{"tabula-development", "tabula-build", "", "-preview", "tabula-preview-x"} {
		a := tabulaPreviewArgs()
		a.GitHubEnvironment = env
		if _, _, err := validatePreview(a); err == nil {
			t.Errorf("GitHubEnvironment %q was accepted; only a dedicated *-preview Environment may be", env)
		}
	}
}

// Whatever this identity holds, every unmerged branch holds. Write roles and
// any Secret Manager role must be refused even if someone adds them to config.
func TestPreviewRefusesNonReadOnlyRoles(t *testing.T) {
	for _, role := range []string{
		"roles/run.admin",
		"roles/editor",
		"roles/owner",
		"roles/iam.serviceAccountUser",
		"roles/secretmanager.secretAccessor",
		"roles/secretmanager.admin",
		"roles/secretmanager.viewer",
	} {
		a := tabulaPreviewArgs()
		a.Roles = []string{"roles/viewer", role}
		if _, _, err := validatePreview(a); err == nil {
			t.Errorf("role %q was accepted on an identity every unmerged branch can assume", role)
		}
	}
}

func TestPreviewDefaultsAndLimits(t *testing.T) {
	id, roles, err := validatePreview(tabulaPreviewArgs())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id != "tabula-preview" || len(roles) != 1 || roles[0] != "roles/viewer" {
		t.Errorf("defaults = (%q, %v), want (tabula-preview, [roles/viewer])", id, roles)
	}

	// oauth-user-inspector-preview is 28 characters: inside GCP's 30 limit.
	o := tabulaPreviewArgs()
	o.App, o.GitHubEnvironment = "oauth-user-inspector", "oauth-user-inspector-preview"
	if id, _, err := validatePreview(o); err != nil || id != "oauth-user-inspector-preview" {
		t.Errorf("oauth-user-inspector: id=%q err=%v", id, err)
	}

	long := tabulaPreviewArgs()
	long.App = "an-application-name-far-too-long"
	long.GitHubEnvironment = long.App + "-preview"
	if _, _, err := validatePreview(long); err == nil {
		t.Error("an account id over 30 characters was accepted; GCP would reject it at apply")
	}

	if _, _, err := validatePreview(nil); err == nil {
		t.Error("nil args accepted")
	}
	noPool := tabulaPreviewArgs()
	noPool.WorkloadIdentityPool = nil
	if _, _, err := validatePreview(noPool); err == nil {
		t.Error("missing WorkloadIdentityPool accepted")
	}
}
