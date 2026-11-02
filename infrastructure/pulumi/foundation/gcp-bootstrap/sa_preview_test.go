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
	"fmt"
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	saAccountType   = "gcp:serviceaccount/account:Account"
	saIAMMemberType = "gcp:serviceaccount/iAMMember:IAMMember"
	orgIAMMemberTyp = "gcp:organizations/iAMMember:IAMMember"
	testSeedProject = "seed-proj"
)

// allowedPreviewRoles is the spec for what a preview identity may hold. It is
// written out here, not read from previewReadRoles, so widening that list fails
// this test until the spec is changed on purpose.
var allowedPreviewRoles = []string{
	"roles/browser",
	"roles/iam.securityReviewer",
	"roles/orgpolicy.policyViewer",
	"roles/resourcemanager.folderViewer",
}

// expectedPreviewEnvironments is the spec for which read-only identity each
// PR-preview GitHub Environment federates to.
var expectedPreviewEnvironments = map[string]string{
	"foundation-bootstrap-preview":   "sa-terraform-bootstrap-preview",
	"foundation-org-preview":         "sa-terraform-org-preview",
	"foundation-env-preview":         "sa-terraform-env-preview",
	"foundation-net-preview":         "sa-terraform-net-preview",
	"foundation-proj-preview":        "sa-terraform-proj-preview",
	"foundation-org-folders-preview": "sa-terraform-bootstrap-preview",
	"foundation-app-preview":         "sa-terraform-proj-preview",
}

// Substrings that mark a role able to change resources, act as another
// identity, or read secret material. None may appear in a preview role.
var forbiddenRoleMarkers = []string{
	"admin", "editor", "owner", "writer", "creator", "user", "deleter",
	"secretmanager", "serviceAccountTokenCreator", "serviceAccountUser",
	"workloadIdentityUser", "storage.object",
}

// previewMocks records every resource's inputs by type, and gives service
// accounts and the WIF pool the computed outputs real GCP would.
type previewMocks struct {
	mu     sync.Mutex
	inputs map[string][]resource.PropertyMap
}

func (m *previewMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.inputs == nil {
		m.inputs = map[string][]resource.PropertyMap{}
	}
	m.inputs[args.TypeToken] = append(m.inputs[args.TypeToken], args.Inputs)

	outs := args.Inputs.Copy()
	switch args.TypeToken {
	case saAccountType:
		id := args.Inputs["accountId"].StringValue()
		email := fmt.Sprintf("%s@%s.iam.gserviceaccount.com", id, testSeedProject)
		outs["email"] = resource.NewStringProperty(email)
		outs["name"] = resource.NewStringProperty(fmt.Sprintf("projects/%s/serviceAccounts/%s", testSeedProject, email))
	case "gcp:iam/workloadIdentityPool:WorkloadIdentityPool":
		outs["name"] = resource.NewStringProperty("projects/123/locations/global/workloadIdentityPools/foundation-pool")
	}
	return args.Name + "_id", outs, nil
}

func (m *previewMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func (m *previewMocks) of(typ string) []resource.PropertyMap {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inputs[typ]
}

func saName(accountID string) string {
	return fmt.Sprintf("projects/%s/serviceAccounts/%s@%s.iam.gserviceaccount.com", testSeedProject, accountID, testSeedProject)
}

func testSeed() *SeedProject {
	return &SeedProject{ProjectID: pulumi.String(testSeedProject).ToStringOutput()}
}

func TestPreviewReadRolesAreExactlyTheAllowedSet(t *testing.T) {
	got := append([]string{}, previewReadRoles...)
	sort.Strings(got)
	want := append([]string{}, allowedPreviewRoles...)
	sort.Strings(want)
	assert.Equal(t, want, got)

	for _, role := range previewReadRoles {
		for _, marker := range forbiddenRoleMarkers {
			assert.NotContains(t, strings.ToLower(role), strings.ToLower(marker),
				"preview role %q is not read-only (matches %q)", role, marker)
		}
	}
}

func TestPreviewSAAccountIDs(t *testing.T) {
	for _, key := range previewStageKeys {
		id, err := previewSAAccountID(key)
		require.NoError(t, err, key)
		assert.Equal(t, "sa-terraform-"+key+"-preview", id)
		assert.LessOrEqual(t, len(id), maxServiceAccountIDLen, id)
	}
	_, err := previewSAAccountID("bootstrapx")
	assert.Error(t, err, "an id over 30 characters must be refused, not sent to GCP")
}

// Every preview identity holds exactly the allowed roles, and nothing else is
// granted to it anywhere in this program's preview-identity code path.
func TestPreviewIdentitiesHoldOnlyReadRoles(t *testing.T) {
	m := &previewMocks{}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := deployPreviewIdentities(ctx, &Config{OrgID: "123456789"}, testSeed())
		return err
	}, pulumi.WithMocks("foundation-bootstrap", "production", m))
	require.NoError(t, err)

	var accounts []string
	for _, in := range m.of(saAccountType) {
		accounts = append(accounts, in["accountId"].StringValue())
	}
	sort.Strings(accounts)
	assert.Equal(t, []string{
		"sa-terraform-bootstrap-preview",
		"sa-terraform-env-preview",
		"sa-terraform-net-preview",
		"sa-terraform-org-preview",
		"sa-terraform-proj-preview",
	}, accounts)

	rolesByMember := map[string][]string{}
	for _, in := range m.of(orgIAMMemberTyp) {
		member := in["member"].StringValue()
		rolesByMember[member] = append(rolesByMember[member], in["role"].StringValue())
	}
	want := append([]string{}, allowedPreviewRoles...)
	sort.Strings(want)
	for _, id := range accounts {
		member := fmt.Sprintf("serviceAccount:%s@%s.iam.gserviceaccount.com", id, testSeedProject)
		got := rolesByMember[member]
		sort.Strings(got)
		assert.Equal(t, want, got, "org roles for %s", id)
	}
	assert.Len(t, rolesByMember, len(accounts), "org roles granted to an identity that is not a preview SA")

	// No service-account-level grants (actAs, token minting) to or from them.
	assert.Empty(t, m.of(saIAMMemberType), "preview identities must not get service-account-level grants")
}

// Each PR-preview Environment federates to its read-only identity.
func TestPreviewEnvironmentsFederateToPreviewIdentities(t *testing.T) {
	m := &previewMocks{}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		sas := map[string]*serviceaccount.Account{}
		for _, key := range previewStageKeys {
			sa, err := serviceaccount.NewAccount(ctx, "sa-terraform-"+key, &serviceaccount.AccountArgs{
				Project:   pulumi.String(testSeedProject),
				AccountId: pulumi.String("sa-terraform-" + key),
			})
			if err != nil {
				return err
			}
			sas[key] = sa
		}
		cfg := &Config{OrgID: "123456789", GitHubOwner: "VitruvianSoftware"}
		previewSAs, err := deployPreviewIdentities(ctx, cfg, testSeed())
		if err != nil {
			return err
		}
		cicd := &CICDProject{ProjectID: pulumi.String("cicd-proj").ToStringOutput()}
		_, err = deployGitHubActionsBuild(ctx, cfg, testSeed(), cicd, sas, previewSAs, nil)
		return err
	}, pulumi.WithMocks("foundation-bootstrap", "production", m))
	require.NoError(t, err)

	// attribute.environment/<env> -> service accounts it may impersonate.
	federated := map[string][]string{}
	for _, in := range m.of(saIAMMemberType) {
		if in["role"].StringValue() != "roles/iam.workloadIdentityUser" {
			continue
		}
		member := in["member"].StringValue()
		i := strings.Index(member, "attribute.environment/")
		require.GreaterOrEqual(t, i, 0, "unexpected WIF member %q", member)
		env := strings.TrimPrefix(member[i:], "attribute.environment/")
		federated[env] = append(federated[env], in["serviceAccountId"].StringValue())
	}

	for env, previewID := range expectedPreviewEnvironments {
		assert.Contains(t, federated[env], saName(previewID), "%s must federate to %s", env, previewID)
	}

	// Deploy Environments must never federate to a preview identity, and a
	// preview identity must never be reachable from a non-preview Environment.
	for env, accounts := range federated {
		for _, account := range accounts {
			if strings.Contains(account, "-preview@") {
				assert.True(t, strings.HasSuffix(env, "-preview"), "%s federates to preview identity %s", env, account)
			}
		}
	}
}
