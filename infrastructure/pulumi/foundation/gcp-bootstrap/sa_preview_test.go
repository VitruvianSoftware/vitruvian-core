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
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	saAccountType   = "gcp:serviceaccount/account:Account"
	saIAMMemberType = "gcp:serviceaccount/iAMMember:IAMMember"
	orgIAMMemberTyp = "gcp:organizations/iAMMember:IAMMember"
	wifUserRole     = "roles/iam.workloadIdentityUser"
	envAttrPrefix   = "attribute.environment/"
	mockProject     = "mock-proj"
)

// allowedPreviewRoles is the spec for what a preview identity may hold. It is
// written out here, not read from previewReadRoles, so widening that list fails
// these tests until the spec is changed on purpose.
var allowedPreviewRoles = []string{
	"roles/browser",
	"roles/iam.securityReviewer",
	"roles/orgpolicy.policyViewer",
	"roles/resourcemanager.folderViewer",
}

// expectedPreviewEnvironments is the spec for which read-only identity each
// PR-preview GitHub Environment federates to (account ids).
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

// recorded is one resource the program registered, with its resolved inputs.
type recorded struct {
	typ, name string
	inputs    resource.PropertyMap
}

// programMocks records every resource and gives computed outputs the program
// reads back (service account email/name, project number).
type programMocks struct {
	mu        sync.Mutex
	resources []recorded
}

func (m *programMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.resources = append(m.resources, recorded{args.TypeToken, args.Name, args.Inputs})

	outs := args.Inputs.Copy()
	switch args.TypeToken {
	case saAccountType:
		id := args.Inputs["accountId"].StringValue()
		project := mockProject
		if p, ok := args.Inputs["project"]; ok && p.IsString() && p.StringValue() != "" {
			project = p.StringValue()
		}
		email := fmt.Sprintf("%s@%s.iam.gserviceaccount.com", id, project)
		outs["email"] = resource.NewStringProperty(email)
		outs["name"] = resource.NewStringProperty(fmt.Sprintf("projects/%s/serviceAccounts/%s", project, email))
		outs["member"] = resource.NewStringProperty("serviceAccount:" + email)
	case "gcp:organizations/project:Project":
		outs["number"] = resource.NewStringProperty("123456789012")
	}
	if id, ok := args.Inputs["workloadIdentityPoolId"]; ok && id.IsString() && args.TypeToken == "gcp:iam/workloadIdentityPool:WorkloadIdentityPool" {
		outs["name"] = resource.NewStringProperty("projects/123456789012/locations/global/workloadIdentityPools/" + id.StringValue())
	}
	if _, ok := outs["name"]; !ok {
		outs["name"] = resource.NewStringProperty("projects/123456789012/locations/global/mock/" + args.Name)
	}
	return args.Name + "_id", outs, nil
}

func (m *programMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	switch args.Token {
	case "gcp:organizations/getOrganization:getOrganization":
		return resource.NewPropertyMapFromMap(map[string]interface{}{"directoryCustomerId": "C0test", "orgId": "90456063361"}), nil
	case "gcp:organizations/getProject:getProject":
		return resource.NewPropertyMapFromMap(map[string]interface{}{"number": "123456789012", "projectId": mockProject}), nil
	case "gcp:storage/getProjectServiceAccount:getProjectServiceAccount":
		return resource.NewPropertyMapFromMap(map[string]interface{}{"emailAddress": "service-123@gs-project-accounts.iam.gserviceaccount.com"}), nil
	}
	return args.Args, nil
}

// committedConfig reads Pulumi.production.yaml's single-line values into the
// PULUMI_CONFIG shape, so the program runs with the real stack config.
func committedConfig(t *testing.T) string {
	t.Helper()
	raw, err := os.ReadFile("Pulumi.production.yaml")
	require.NoError(t, err)
	cfg := map[string]string{}
	for _, line := range strings.Split(string(raw), "\n") {
		l := strings.TrimSpace(line)
		if !strings.HasPrefix(l, "foundation-bootstrap:") {
			continue
		}
		key, value, ok := strings.Cut(l, ": ")
		if !ok {
			continue
		}
		value = strings.TrimSpace(value)
		if len(value) >= 2 && (value[0] == '"' || value[0] == '\'') && value[len(value)-1] == value[0] {
			value = value[1 : len(value)-1]
		}
		cfg[key] = value
	}
	require.NotEmpty(t, cfg["foundation-bootstrap:org_id"], "Pulumi.production.yaml: org_id not found")
	out, err := json.Marshal(cfg)
	require.NoError(t, err)
	return string(out)
}

// runWholeProgram runs the complete stack program under mocks with the
// committed config and returns every resource it declared.
func runWholeProgram(t *testing.T) []recorded {
	t.Helper()
	t.Setenv("PULUMI_CONFIG", committedConfig(t))
	m := &programMocks{}
	err := pulumi.RunErr(program, pulumi.WithMocks("foundation-bootstrap", "production", m))
	require.NoError(t, err)
	m.mu.Lock()
	defer m.mu.Unlock()
	// The live stack has ~390 resources. A run that registers only a handful
	// means the program stopped early, and every check below would pass on
	// nothing.
	require.Greater(t, len(m.resources), 200, "the whole program did not run")
	t.Logf("whole program declared %d resources", len(m.resources))
	return append([]recorded{}, m.resources...)
}

// stringsIn returns every string anywhere in a property value, including
// inside arrays, maps and secrets, so a grant cannot hide in a nested field.
func stringsIn(v resource.PropertyValue) []string {
	switch {
	case v.IsString():
		return []string{v.StringValue()}
	case v.IsArray():
		var out []string
		for _, e := range v.ArrayValue() {
			out = append(out, stringsIn(e)...)
		}
		return out
	case v.IsObject():
		var out []string
		for _, e := range v.ObjectValue() {
			out = append(out, stringsIn(e)...)
		}
		return out
	case v.IsSecret():
		return stringsIn(v.SecretValue().Element)
	case v.IsOutput():
		return stringsIn(v.OutputValue().Element)
	}
	return nil
}

func allStrings(r recorded) []string {
	return stringsIn(resource.NewObjectProperty(r.inputs))
}

func str(r recorded, key string) string {
	v, ok := r.inputs[resource.PropertyKey(key)]
	if !ok {
		return ""
	}
	if v.IsSecret() {
		v = v.SecretValue().Element
	}
	if v.IsString() {
		return v.StringValue()
	}
	return ""
}

// previewAccountsIn returns the preview account ids ("sa-terraform-x-preview")
// whose email appears anywhere in s.
func previewAccountsIn(s string) []string {
	var out []string
	for _, part := range strings.FieldsFunc(s, func(r rune) bool {
		return r == ':' || r == '/' || r == '"' || r == ',' || r == ' ' || r == '\n' || r == '[' || r == ']' || r == '{' || r == '}'
	}) {
		if at := strings.Index(part, "-preview@"); at > 0 {
			out = append(out, part[:at+len("-preview")])
		}
	}
	return out
}

// previewEnvsIn returns every attribute.environment/<x>-preview named in s.
func previewEnvsIn(s string) []string {
	var out []string
	for rest := s; ; {
		i := strings.Index(rest, envAttrPrefix)
		if i < 0 {
			return out
		}
		rest = rest[i+len(envAttrPrefix):]
		end := strings.IndexFunc(rest, func(r rune) bool {
			return !(r == '-' || r == '_' || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9'))
		})
		env := rest
		if end >= 0 {
			env = rest[:end]
		}
		if strings.HasSuffix(env, "-preview") {
			out = append(out, env)
		}
	}
}

func accountIDFromSAName(name string) string {
	email := name[strings.LastIndex(name, "/")+1:]
	id, _, _ := strings.Cut(email, "@")
	return id
}

func TestPreviewReadRolesAreExactlyTheAllowedSet(t *testing.T) {
	got := append([]string{}, previewReadRoles...)
	sort.Strings(got)
	want := append([]string{}, allowedPreviewRoles...)
	sort.Strings(want)
	assert.Equal(t, want, got)

	for _, role := range previewReadRoles {
		assert.True(t, strings.HasPrefix(role, "roles/"), "preview role %q is not a predefined role", role)
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

// Every resource in the whole program that names a preview identity must be
// one of exactly two shapes: an org-level grant of an allowed role to it, or
// a workloadIdentityUser binding on it whose member is its own preview
// Environment. Anything else (a project, folder, bucket or secret grant, a
// binding, a policy, a custom role, a grant of it on another account) fails.
func TestWholeProgramGrantsPreviewIdentitiesOnlyAllowedAccess(t *testing.T) {
	resources := runWholeProgram(t)

	allowed := map[string]bool{}
	for _, r := range allowedPreviewRoles {
		allowed[r] = true
	}
	rolesByAccount := map[string][]string{}

	for _, r := range resources {
		named := map[string]bool{}
		for _, s := range allStrings(r) {
			for _, id := range previewAccountsIn(s) {
				named[id] = true
			}
		}
		for id := range named {
			switch {
			case r.typ == orgIAMMemberTyp && strings.HasPrefix(str(r, "member"), "serviceAccount:"+id+"@"):
				role := str(r, "role")
				assert.True(t, allowed[role], "%s (%s): grants %q to %s, which is not an allowed preview role", r.name, r.typ, role, id)
				rolesByAccount[id] = append(rolesByAccount[id], role)
			case r.typ == saIAMMemberType && accountIDFromSAName(str(r, "serviceAccountId")) == id &&
				!strings.Contains(str(r, "member"), "-preview@"):
				assert.Equal(t, wifUserRole, str(r, "role"), "%s: %s on %s", r.name, str(r, "role"), id)
				envs := previewEnvsIn(str(r, "member"))
				if assert.Len(t, envs, 1, "%s: member %q is not a single preview Environment", r.name, str(r, "member")) {
					assert.Equal(t, expectedPreviewEnvironments[envs[0]], id, "%s: %s federates to %s", r.name, envs[0], id)
				}
			default:
				assert.Fail(t, "preview identity has access it must not have",
					"%s (%s) names %s; only allowed org roles and its own Environment's federation are permitted", r.name, r.typ, id)
			}
		}
	}

	want := append([]string{}, allowedPreviewRoles...)
	sort.Strings(want)
	for _, id := range []string{
		"sa-terraform-bootstrap-preview", "sa-terraform-env-preview", "sa-terraform-net-preview",
		"sa-terraform-org-preview", "sa-terraform-proj-preview",
	} {
		got := rolesByAccount[id]
		sort.Strings(got)
		assert.Equal(t, want, got, "org roles for %s", id)
	}
}

// Each preview Environment reaches its read-only identity and nothing else:
// across every resource the program declares, the only thing that may name a
// preview Environment is the workloadIdentityUser binding on its preview SA.
func TestWholeProgramPreviewEnvironmentsReachOnlyTheirPreviewIdentity(t *testing.T) {
	resources := runWholeProgram(t)

	reached := map[string][]string{}
	for _, r := range resources {
		envs := map[string]bool{}
		for _, s := range allStrings(r) {
			for _, env := range previewEnvsIn(s) {
				envs[env] = true
			}
		}
		for env := range envs {
			want, known := expectedPreviewEnvironments[env]
			if !assert.True(t, known, "%s (%s) names unknown preview Environment %s", r.name, r.typ, env) {
				continue
			}
			if !assert.Equal(t, saIAMMemberType, r.typ, "%s names %s but is a %s, not its federation binding", r.name, env, r.typ) {
				continue
			}
			assert.Equal(t, wifUserRole, str(r, "role"), "%s: %s gets %s", r.name, env, str(r, "role"))
			got := accountIDFromSAName(str(r, "serviceAccountId"))
			assert.Equal(t, want, got, "%s: %s reaches %s; it may reach only %s", r.name, env, got, want)
			reached[env] = append(reached[env], got)
		}
	}
	for env, want := range expectedPreviewEnvironments {
		assert.Equal(t, []string{want}, reached[env], "%s must federate to exactly %s", env, want)
	}
}

// Roles that let a member use a service account: federate to it, mint its
// tokens, or act as it. A grant of one of these is a grant of the account.
var serviceAccountUseRoles = map[string]bool{
	"roles/iam.workloadIdentityUser":             true,
	"roles/iam.serviceAccountTokenCreator":       true,
	"roles/iam.serviceAccountUser":               true,
	"roles/iam.serviceAccountOpenIdTokenCreator": true,
}

const (
	foundationPool = "projects/123456789012/locations/global/workloadIdentityPools/foundation-pool"
	homelabPool    = "projects/123456789012/locations/global/workloadIdentityPools/homelab-cluster-pool"
	escPool        = "projects/123456789012/locations/global/workloadIdentityPools/pulumi-esc-pool"
	orgAdmins      = "group:gcp-organization-admins@vitruviansoftware.dev"
)

func envPrincipal(env string) string {
	return "principalSet://iam.googleapis.com/" + foundationPool + "/attribute.environment/" + env
}

// expectedAccountGrants is the COMPLETE allow-list of who may use each service
// account in this program, by account id and role. A member that is not listed
// here fails, whatever its form: a whole-pool or whole-repository principalSet,
// a subject principal, another Environment, a wildcard. "self" stands for the
// account's own serviceAccount: member.
var expectedAccountGrants = func() map[string]map[string][]string {
	wif := "roles/iam.workloadIdentityUser"
	deployEnvs := map[string][]string{
		"sa-terraform-bootstrap": {"foundation-bootstrap", "foundation-org-folders"},
		"sa-terraform-org":       {"foundation-org"},
		"sa-terraform-env":       {"foundation-env", "foundation-env-development", "foundation-env-nonproduction", "foundation-env-production"},
		"sa-terraform-net":       {"foundation-net", "foundation-net-shared", "foundation-net-development", "foundation-net-nonproduction", "foundation-net-production"},
		"sa-terraform-proj":      {"foundation-proj", "foundation-proj-shared", "foundation-proj-development", "foundation-proj-nonproduction", "foundation-proj-production"},
	}
	out := map[string]map[string][]string{}
	for id, envs := range deployEnvs {
		var members []string
		for _, env := range envs {
			members = append(members, envPrincipal(env))
		}
		out[id] = map[string][]string{
			wif:                                    members,
			"roles/iam.serviceAccountTokenCreator": {"self", orgAdmins},
			"roles/iam.serviceAccountUser":         {orgAdmins},
		}
	}
	for env, id := range expectedPreviewEnvironments {
		if out[id] == nil {
			out[id] = map[string][]string{}
		}
		out[id][wif] = append(out[id][wif], envPrincipal(env))
	}
	out["sa-homelab-cluster"] = map[string][]string{wif: {
		"principal://iam.googleapis.com/" + homelabPool + "/subject/system:serviceaccount:backstage:backstage",
		"principal://iam.googleapis.com/" + homelabPool + "/subject/system:serviceaccount:grafana:grafana",
	}}
	out["sa-pulumi-esc"] = map[string][]string{wif: {
		"principal://iam.googleapis.com/" + escPool + "/subject/pulumi:environments:org:ipv1337:env:vitruvian-core/cloud-session",
	}}
	return out
}()

// grantPairs returns the (role, member) pairs an IAM resource grants, and
// whether it is a grant on a single service account. ok=false means the
// resource is an IAM type this test does not know how to read.
func grantPairs(r recorded) (pairs [][2]string, onAccount bool, ok bool) {
	onAccount = str(r, "serviceAccountId") != ""
	switch {
	case strings.HasSuffix(r.typ, "/iAMMember:IAMMember"):
		return [][2]string{{str(r, "role"), str(r, "member")}}, onAccount, true
	case strings.HasSuffix(r.typ, "/iAMBinding:IAMBinding"):
		for _, m := range stringsIn(r.inputs["members"]) {
			pairs = append(pairs, [2]string{str(r, "role"), m})
		}
		return pairs, onAccount, true
	case strings.HasSuffix(r.typ, "/iAMPolicy:IAMPolicy"):
		var policy struct {
			Bindings []struct {
				Role    string   `json:"role"`
				Members []string `json:"members"`
			} `json:"bindings"`
		}
		if err := json.Unmarshal([]byte(str(r, "policyData")), &policy); err != nil {
			return nil, onAccount, false
		}
		for _, b := range policy.Bindings {
			for _, m := range b.Members {
				pairs = append(pairs, [2]string{b.Role, m})
			}
		}
		return pairs, onAccount, true
	}
	return nil, onAccount, !onAccount
}

// Who may use each service account is an allow-list. Every IAM grant on a
// service account, of any IAM resource type, must name an expected member for
// that account and role; a grant of a role that uses service accounts at any
// wider scope (project, folder, org) is refused outright; and every federated
// principal string anywhere in the program must be one of those expected
// bindings, so a principal cannot reach an account by another route.
func TestWholeProgramServiceAccountUseIsAllowListed(t *testing.T) {
	resources := runWholeProgram(t)

	seen := map[string]map[string][]string{}
	for _, r := range resources {
		pairs, onAccount, ok := grantPairs(r)
		if !assert.True(t, ok, "%s (%s): unrecognized IAM resource on a service account", r.name, r.typ) {
			continue
		}
		allowedBinding := false
		if onAccount {
			saName := str(r, "serviceAccountId")
			id := accountIDFromSAName(saName)
			selfMember := "serviceAccount:" + saName[strings.LastIndex(saName, "/")+1:]
			for _, p := range pairs {
				role, member := p[0], p[1]
				if member == selfMember {
					member = "self"
				}
				want := expectedAccountGrants[id][role]
				assert.Contains(t, want, member, "%s (%s): %s on %s for %q is not on the allow-list", r.name, r.typ, role, id, p[1])
				if seen[id] == nil {
					seen[id] = map[string][]string{}
				}
				seen[id][role] = append(seen[id][role], member)
			}
			allowedBinding = r.typ == saIAMMemberType && len(pairs) == 1
		} else {
			for _, p := range pairs {
				assert.False(t, serviceAccountUseRoles[p[0]],
					"%s (%s): grants %s to %q at a scope wider than one service account", r.name, r.typ, p[0], p[1])
			}
		}

		for _, s := range allStrings(r) {
			if strings.Contains(s, "principalSet://") || strings.Contains(s, "principal://") {
				assert.True(t, allowedBinding && s == str(r, "member"),
					"%s (%s) names federated principal %q outside an allow-listed service account binding", r.name, r.typ, s)
			}
		}
	}

	for id, roles := range expectedAccountGrants {
		for role, want := range roles {
			got := append([]string{}, seen[id][role]...)
			sort.Strings(got)
			w := append([]string{}, want...)
			sort.Strings(w)
			assert.Equal(t, w, got, "members with %s on %s", role, id)
		}
	}
}

// expectedProviders is the COMPLETE allow-list of identity providers, by pool.
// Federated principals are scoped to a pool, not a provider, so every provider
// in a pool can satisfy that pool's bindings: a second provider in
// foundation-pool would bypass the repository pin and the environment mapping
// below. Each pool therefore holds exactly the one provider listed here.
var expectedProviders = map[string]string{
	"foundation-pool":      "foundation-gh-provider",
	"homelab-cluster-pool": "homelab-cluster-provider",
	"pulumi-esc-pool":      "pulumi-esc-provider",
}

// The GitHub provider must be the only provider in its pool, trust only
// GitHub's issuer, accept tokens only from this repository, and map
// attribute.environment from the job's Environment claim; every
// per-Environment binding above depends on all four.
func TestFoundationProviderIsPinnedToTheRepository(t *testing.T) {
	providersByPool := map[string][]string{}
	var foundation *recorded
	for _, r := range runWholeProgram(t) {
		if r.typ != "gcp:iam/workloadIdentityPoolProvider:WorkloadIdentityPoolProvider" {
			continue
		}
		r := r
		pool := str(r, "workloadIdentityPoolId")
		id := str(r, "workloadIdentityPoolProviderId")
		providersByPool[pool] = append(providersByPool[pool], id)
		assert.NotEmpty(t, str(r, "attributeCondition"), "%s has no attribute condition", r.name)
		if pool == "foundation-pool" && id == "foundation-gh-provider" {
			foundation = &r
		}
	}

	want := map[string][]string{}
	for pool, id := range expectedProviders {
		want[pool] = []string{id}
	}
	assert.Equal(t, want, providersByPool, "identity providers by pool")

	require.NotNil(t, foundation, "foundation-gh-provider not declared in foundation-pool")
	assert.Equal(t, "assertion.repository=='VitruvianSoftware/vitruvian-core'", str(*foundation, "attributeCondition"))

	oidc := foundation.inputs["oidc"]
	require.True(t, oidc.IsObject(), "foundation-gh-provider has no oidc block")
	issuer := oidc.ObjectValue()["issuerUri"]
	require.True(t, issuer.IsString(), "foundation-gh-provider has no issuer")
	assert.Equal(t, "https://token.actions.githubusercontent.com", issuer.StringValue())
	_, saml := foundation.inputs["saml"]
	assert.False(t, saml, "foundation-gh-provider must not also trust a SAML issuer")

	mapping := foundation.inputs["attributeMapping"]
	require.True(t, mapping.IsObject(), "attributeMapping missing")
	got := map[string]string{}
	for k, v := range mapping.ObjectValue() {
		got[string(k)] = v.StringValue()
	}
	assert.Equal(t, map[string]string{
		"google.subject":             "assertion.sub",
		"attribute.actor":            "assertion.actor",
		"attribute.aud":              "assertion.aud",
		"attribute.environment":      "assertion.environment",
		"attribute.repository":       "assertion.repository",
		"attribute.repository_owner": "assertion.repository_owner",
	}, got, "foundation-gh-provider attribute mapping")
}
