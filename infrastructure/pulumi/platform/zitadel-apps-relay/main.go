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

// The Zitadel project and OIDC clients for the Vitruvian Relay
// (docs/superpowers/specs/2026-11-07-vitruvian-relay-design.md §6).
//
// The clients all issue JWT access tokens, so the relay can validate them
// locally against JWKS. All but gemini are public (no secret) with PKCE.
//
// The connector is the program on the user's computer. It signs in with the
// OAuth device flow (RFC 8628), so it has no redirect URI at all.
//
// Claude's "use your own OAuth client" option is the claude client. Claude's
// hosted apps (web, desktop, mobile) use one fixed callback.
//
// The chatgpt client is created only when chatgptRedirectUris is set. Our
// Zitadel does not advertise RFC 9207 issuer identification, so ChatGPT uses a
// per-connector callback (https://chatgpt.com/connector/oauth/{id}) that is
// only known after the connector is started in ChatGPT's UI.
//
// The gemini client is created only when geminiRedirectUris is set. The Gemini
// app's custom connector form asks for a client id AND secret and shows a
// per-user callback on oauth-redirect.googleusercontent.com. It is the one
// confidential client (client_secret_post), matching the sibling
// zitadel-apps-mcp-slack client that already works with Gemini.
//
// Each of those four also has a "-v2" sibling that asserts the user's roles in
// its access tokens (see clientSpecs). The multi-user relay requires the role
// claim, but the live clients were made with that off and the provider can only
// change it by replacing (= deleting) them. The old set keeps the current relay
// working until it is replaced; a later change removes it.
//
// The dashboard client is the relay's own server-rendered web page, where
// signed-in people see their computers and activity. The relay does the
// sign-in (authorization code with PKCE, no secret) and checks the same role
// claim as the MCP endpoint. Its callback is on the relay's own host.
//
// WHY ITS OWN PROJECT: Zitadel's audience scope is per project, so sharing a
// project with another app would blur that boundary. But note what the sibling
// vitruvian-slack-mcp stack established: in this instance `aud` is caller-authored (any
// authenticated user can request any project's audience scope). The relay must
// therefore authorise on the token's client id (azp) and subject, never on
// `aud` alone. Exported clientIds exist for exactly that pin.
//
// WHO MAY SIGN IN (P2, invite-only): projectRoleCheck is on, so a sign-in only
// completes for someone holding the relay-user role through a user grant.
// James holds it through grantUserIds; other people through inviteUserIds. All
// are plain user grants in the project's own org, applied by CI. There is no
// separate customer org in P2: creating one needs an instance-level (IAM_OWNER)
// machine user, and this stack's is ORG_OWNER. A person who registers in that
// org on their own holds no role, so they get nothing (README: Sign-up and
// invites).
//
// ROLE CLAIM: the project asserts roles, so access tokens carry
// urn:zitadel:iam:org:project:{projectId}:roles. The relay requires the role
// key inside it. The exported roleClaim output is that claim name.
//
// APPLYING: CI only, over tailnet (the public edge 403s the management API).
// See ../zitadel-apps/APPLYING-FROM-CI.md and
// .github/workflows/zitadel-apps-relay-apply.yaml. Never `:import` a client
// from this stack: the provider plans a replacement and deletes the live one
// (the sibling stack lost its client that way on 2026-06-26).
package main

import (
	"fmt"
	"net/url"
	"regexp"
	"strconv"
	"strings"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
	"github.com/pulumiverse/pulumi-zitadel/sdk/go/zitadel"
)

const cfgNamespace = "zitadel-apps-relay"

// claudeCallback is the one redirect URI Claude's hosted apps use for a
// manually registered client (claude.com/docs/connectors/building/authentication).
const claudeCallback = "https://claude.ai/api/mcp/auth_callback"

// Where each app may receive the authorization code. Host AND path are pinned:
// the host alone would accept any path on a shared redirector, and a bare
// prefix would accept look-alikes such as /connectorevil.
const (
	chatgptCallbackHost = "chatgpt.com"
	geminiCallbackHost  = "oauth-redirect.googleusercontent.com"
	// relayHost is where the relay's own web pages live. Sign-in itself stays
	// on auth.ipv1337.dev.
	relayHost = "relay.vitruviansoftware.dev"
)

// The dashboard's sign-in callback and where Zitadel sends people after sign-out.
const (
	dashboardCallback = "https://" + relayHost + "/auth/callback"
	dashboardLogout   = "https://" + relayHost + "/"
)

// pathRule allows one callback path shape: either exactly Exact, or Prefix
// followed by an id of letters, digits, "_" and "-" only. The narrow id
// alphabet refuses "/", a backslash (browsers read it as "/"), "%" and the dot
// segments "." and "..", any of which could walk the path somewhere else.
type pathRule struct {
	Exact  string
	Prefix string
}

func (r pathRule) matches(path string) bool {
	// A rule with neither field set would accept any id-shaped path.
	if r.Exact == "" && r.Prefix == "" {
		return false
	}
	if r.Exact != "" {
		return path == r.Exact
	}
	id, ok := strings.CutPrefix(path, r.Prefix)
	return ok && callbackID.MatchString(id)
}

var callbackID = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

var (
	// https://chatgpt.com/connector/oauth/{id} and the fixed
	// https://chatgpt.com/connector_platform_oauth_redirect.
	chatgptCallbackPaths = []pathRule{
		{Prefix: "/connector/oauth/"},
		{Exact: "/connector_platform_oauth_redirect"},
	}
	// The Gemini app's custom connectors: /r/user_bound_custom-mcp-{id}.
	geminiCallbackPaths = []pathRule{{Prefix: "/r/user_bound_custom-mcp-"}}
	// The relay dashboard has exactly one callback.
	dashboardCallbackPaths = []pathRule{{Exact: "/auth/callback"}}
)

// clientSpec is everything about one OIDC client that this stack decides.
// Built by pure functions so the decisions are unit-tested; main only turns
// specs into resources.
type clientSpec struct {
	Key string // resource name suffix, e.g. "connector-v2"
	// ExportKey prefixes the stack outputs, e.g. "connectorV2" gives connectorV2ClientId.
	ExportKey    string
	AppType      string
	GrantTypes   []string
	RedirectURIs []string
	// AuthMethod is how the client authenticates at the token endpoint.
	// OIDC_AUTH_METHOD_TYPE_NONE = public client, PKCE required.
	AuthMethod string
	// PostLogoutURIs is where Zitadel may send the browser after sign-out.
	PostLogoutURIs []string
	// AccessTokenRoleAssertion puts the user's roles into the access token.
	// Only read when the client is created (the provider ignores later changes).
	AccessTokenRoleAssertion bool
}

const (
	authNone = "OIDC_AUTH_METHOD_TYPE_NONE"
	authPost = "OIDC_AUTH_METHOD_TYPE_POST"
)

// clientSpecs returns the clients to create. chatgptRaw and geminiRaw are the
// comma-separated chatgptRedirectUris and geminiRedirectUris config; empty
// means no client for that app.
func clientSpecs(chatgptRaw, geminiRaw string) ([]clientSpec, error) {
	specs := []clientSpec{
		{
			Key:          "connector",
			ExportKey:    "connector",
			AppType:      "OIDC_APP_TYPE_NATIVE",
			GrantTypes:   []string{"OIDC_GRANT_TYPE_DEVICE_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"},
			RedirectURIs: []string{},
			AuthMethod:   authNone,
		},
		{
			Key:          "claude",
			ExportKey:    "claude",
			AppType:      "OIDC_APP_TYPE_WEB",
			GrantTypes:   []string{"OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"},
			RedirectURIs: []string{claudeCallback},
			AuthMethod:   authNone,
		},
	}
	chatgpt, err := parseRedirectURIs(chatgptRaw, chatgptCallbackHost, chatgptCallbackPaths)
	if err != nil {
		return nil, err
	}
	if len(chatgpt) > 0 {
		specs = append(specs, clientSpec{
			Key:          "chatgpt",
			ExportKey:    "chatgpt",
			AppType:      "OIDC_APP_TYPE_WEB",
			GrantTypes:   []string{"OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"},
			RedirectURIs: chatgpt,
			AuthMethod:   authNone,
		})
	}
	gemini, err := parseRedirectURIs(geminiRaw, geminiCallbackHost, geminiCallbackPaths)
	if err != nil {
		return nil, err
	}
	if len(gemini) > 0 {
		specs = append(specs, clientSpec{
			Key:          "gemini",
			ExportKey:    "gemini",
			AppType:      "OIDC_APP_TYPE_WEB",
			GrantTypes:   []string{"OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"},
			RedirectURIs: gemini,
			AuthMethod:   authPost,
		})
	}
	// A role-asserting sibling of every client above. The live clients were
	// created with accessTokenRoleAssertion off, and the provider cannot change
	// that without replacing (= deleting) them, so the multi-user relay gets its
	// own copies instead. Same type, grants, redirects and auth method.
	for _, old := range append([]clientSpec(nil), specs...) {
		v2 := old
		v2.Key = old.Key + "-v2"
		v2.ExportKey = old.ExportKey + "V2"
		v2.AccessTokenRoleAssertion = true
		specs = append(specs, v2)
	}
	// The dashboard's callback is a fixed constant, but it goes through the same
	// check as the configured ones so a typo in it can never ship.
	dashboard, err := parseRedirectURIs(dashboardCallback, relayHost, dashboardCallbackPaths)
	if err != nil {
		return nil, err
	}
	specs = append(specs, clientSpec{
		Key:                      "dashboard",
		ExportKey:                "dashboard",
		AppType:                  "OIDC_APP_TYPE_WEB",
		GrantTypes:               []string{"OIDC_GRANT_TYPE_AUTHORIZATION_CODE"},
		RedirectURIs:             dashboard,
		AuthMethod:               authNone,
		PostLogoutURIs:           []string{dashboardLogout},
		AccessTokenRoleAssertion: true,
	})
	return specs, nil
}

// roleClaim is the access-token claim that holds the user's roles for this
// project, as an object keyed by role key.
func roleClaim(projectID string) string {
	return "urn:zitadel:iam:org:project:" + projectID + ":roles"
}

// parseRedirectURIs splits a comma-separated list and refuses anything that is
// not an exact https URL on wantHost whose path matches one of rules. A
// redirect URI on the wrong host or path would hand an authorization code to
// someone else, so a typo is an apply error.
func parseRedirectURIs(raw, wantHost string, rules []pathRule) ([]string, error) {
	var out []string
	for _, part := range strings.Split(raw, ",") {
		s := strings.TrimSpace(part)
		if s == "" {
			continue
		}
		// Checked on the raw text, before parsing: Go drops an empty "?" or "#"
		// (ForceQuery, empty Fragment) and lower-cases the scheme, so the parsed
		// URL alone can't see these.
		if strings.ContainsAny(s, "\\?#") || !strings.HasPrefix(s, "https://") {
			return nil, fmt.Errorf("%s: redirect URI %q must start with lower-case https:// and contain no backslash, ? or #", cfgNamespace, s)
		}
		u, err := url.Parse(s)
		if err != nil || u.Scheme != "https" || u.Host != wantHost || u.User != nil || u.RawQuery != "" || u.Fragment != "" ||
			u.RawPath != "" || !anyRuleMatches(rules, u.Path) {
			return nil, fmt.Errorf("%s: redirect URI %q is not an allowed https callback on %s (no query, fragment or extra path segments)", cfgNamespace, s, wantHost)
		}
		out = append(out, s)
	}
	return out, nil
}

func anyRuleMatches(rules []pathRule, path string) bool {
	for _, r := range rules {
		if r.matches(path) {
			return true
		}
	}
	return false
}

// parseBool is strict on purpose: cfg.GetBool turns an unparseable value into
// false, which would silently disable the role check.
func parseBool(raw, key string) (bool, error) {
	if raw == "" {
		return false, nil
	}
	v, err := strconv.ParseBool(raw)
	if err != nil {
		return false, fmt.Errorf("%s:%s must be a boolean (%q is not one); refusing to apply", cfgNamespace, key, raw)
	}
	return v, nil
}

// splitIDs turns a comma-separated list of user ids into a clean slice.
func splitIDs(raw string) []string {
	var ids []string
	for _, id := range strings.Split(raw, ",") {
		if trimmed := strings.TrimSpace(id); trimmed != "" {
			ids = append(ids, trimmed)
		}
	}
	return ids
}

// resolveGrantUserIDs enforces that the role check and its grant land in the
// same apply. Check on with nobody granted locks everyone out, and the
// failure shows up later as a rejected login rather than as a config change.
func resolveGrantUserIDs(projectRoleCheck bool, raw, roleKey string) ([]string, error) {
	ids := splitIDs(raw)
	if dup := firstDuplicate(ids); dup != "" {
		return nil, fmt.Errorf("%s:grantUserIds lists %q more than once; refusing to apply", cfgNamespace, dup)
	}
	if projectRoleCheck && len(ids) == 0 {
		return nil, fmt.Errorf(
			"%s:projectRoleCheck is true but grantUserIds is empty; refusing to apply. "+
				"Grant %q to at least one user in the same apply, or leave the check off",
			cfgNamespace, roleKey,
		)
	}
	return ids, nil
}

// resolveInviteUserIDs reads inviteUserIds. Invitees are plain user grants like
// James's, so an id in both lists (or twice in one) is a config mistake: it
// would be two grants of the same role to one user.
func resolveInviteUserIDs(grantIDs []string, raw string) ([]string, error) {
	ids := splitIDs(raw)
	if dup := firstDuplicate(ids); dup != "" {
		return nil, fmt.Errorf("%s:inviteUserIds lists %q more than once; refusing to apply", cfgNamespace, dup)
	}
	have := map[string]bool{}
	for _, id := range grantIDs {
		have[id] = true
	}
	for _, id := range ids {
		if have[id] {
			return nil, fmt.Errorf("%s: user %q is in both grantUserIds and inviteUserIds; list each user once", cfgNamespace, id)
		}
	}
	return ids, nil
}

// firstDuplicate returns the first id seen twice, or "".
func firstDuplicate(ids []string) string {
	seen := map[string]bool{}
	for _, id := range ids {
		if seen[id] {
			return id
		}
		seen[id] = true
	}
	return ""
}

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, cfgNamespace)
		orgID := cfg.Get("orgId")
		projectName := cfg.Get("projectName")
		if projectName == "" {
			projectName = "relay"
		}
		roleKey := cfg.Get("roleKey")
		if roleKey == "" {
			roleKey = "relay-user"
		}
		projectRoleCheck, err := parseBool(cfg.Get("projectRoleCheck"), "projectRoleCheck")
		if err != nil {
			return err
		}
		grantIDs, err := resolveGrantUserIDs(projectRoleCheck, cfg.Get("grantUserIds"), roleKey)
		if err != nil {
			return err
		}
		inviteIDs, err := resolveInviteUserIDs(grantIDs, cfg.Get("inviteUserIds"))
		if err != nil {
			return err
		}
		specs, err := clientSpecs(cfg.Get("chatgptRedirectUris"), cfg.Get("geminiRedirectUris"))
		if err != nil {
			return err
		}

		ignoreOrg := pulumi.IgnoreChanges([]string{"orgId"})

		projectArgs := &zitadel.ProjectArgs{
			Name: pulumi.String(projectName),
			// On, so access tokens carry the roles claim the relay checks.
			ProjectRoleAssertion: pulumi.Bool(true),
			ProjectRoleCheck:     pulumi.Bool(projectRoleCheck),
		}
		if orgID != "" {
			projectArgs.OrgId = pulumi.String(orgID)
		}
		project, err := zitadel.NewProject(ctx, projectName, projectArgs, ignoreOrg)
		if err != nil {
			return err
		}

		role, err := zitadel.NewProjectRole(ctx, roleKey, &zitadel.ProjectRoleArgs{
			ProjectId:   project.ID(),
			RoleKey:     pulumi.String(roleKey),
			DisplayName: pulumi.String("Relay user"),
		}, ignoreOrg)
		if err != nil {
			return err
		}

		// James's grant and the invitees' grants are the same kind of thing, so
		// one loop. The resource name "grant-<id>" is unchanged for James's
		// existing grant, so it is not replaced.
		for _, userID := range append(append([]string(nil), grantIDs...), inviteIDs...) {
			grantArgs := &zitadel.UserGrantArgs{
				ProjectId: project.ID(),
				UserId:    pulumi.String(userID),
				RoleKeys:  pulumi.StringArray{pulumi.String(roleKey)},
			}
			if orgID != "" {
				grantArgs.OrgId = pulumi.String(orgID)
			}
			// The grant names the role by key, not by a resource output, so
			// Pulumi sees no dependency and creates both at once. Zitadel then
			// refuses the grant (Errors.Project.Role.NotFound, first apply
			// 2026-11-09). DependsOn makes the grant wait for the role.
			if _, err := zitadel.NewUserGrant(ctx, "grant-"+userID, grantArgs, ignoreOrg, pulumi.DependsOn([]pulumi.Resource{role})); err != nil {
				return err
			}
		}

		// Replace-triggering fields the provider does not read back; ignoring
		// them stops a spurious diff from replacing (= deleting) a live client.
		clientOpts := pulumi.IgnoreChanges([]string{
			"appType", "version", "accessTokenType", "accessTokenRoleAssertion",
			"idTokenRoleAssertion", "idTokenUserinfoAssertion", "clockSkew", "orgId",
		})

		for _, s := range specs {
			appArgs := &zitadel.ApplicationOidcArgs{
				ProjectId:     project.ID(),
				Name:          pulumi.String(projectName + "-" + s.Key),
				RedirectUris:  pulumi.ToStringArray(s.RedirectURIs),
				ResponseTypes: pulumi.StringArray{pulumi.String("OIDC_RESPONSE_TYPE_CODE")},
				GrantTypes:    pulumi.ToStringArray(s.GrantTypes),
				AppType:       pulumi.String(s.AppType),
				// NONE: public client, PKCE (S256) required by Zitadel.
				// POST (gemini only): Zitadel issues a client secret.
				AuthMethodType:           pulumi.String(s.AuthMethod),
				Version:                  pulumi.String("OIDC_VERSION_1_0"),
				AccessTokenType:          pulumi.String("OIDC_TOKEN_TYPE_JWT"),
				DevMode:                  pulumi.Bool(false),
				AccessTokenRoleAssertion: pulumi.Bool(s.AccessTokenRoleAssertion),
				IdTokenRoleAssertion:     pulumi.Bool(false),
				IdTokenUserinfoAssertion: pulumi.Bool(false),
			}
			// Set only where there is one, so the existing clients' plans do not move.
			if len(s.PostLogoutURIs) > 0 {
				appArgs.PostLogoutRedirectUris = pulumi.ToStringArray(s.PostLogoutURIs)
			}
			app, err := zitadel.NewApplicationOidc(ctx, projectName+"-"+s.Key, appArgs, clientOpts)
			if err != nil {
				return err
			}
			// The provider marks clientId secret, so it would print as
			// [secret]. A client id is not a credential: it goes into the
			// relay's config and the AI apps' connector settings, so it is
			// reported in plain text.
			ctx.Export(s.ExportKey+"ClientId", pulumi.Unsecret(app.ClientId))
			if s.AuthMethod != authNone {
				// Stays a secret output: encrypted in state, masked in logs.
				// Read it with the stack target's --show-secrets.
				ctx.Export(s.ExportKey+"ClientSecret", app.ClientSecret)
			}
			// Exported because it is ignored above, so Pulumi never reconciles
			// it; the relay's local JWT validation depends on it being JWT.
			ctx.Export(s.ExportKey+"AccessTokenType", app.AccessTokenType)
		}

		ctx.Export("projectId", project.ID())
		ctx.Export("roleClaim", project.ID().ApplyT(func(id pulumi.ID) string {
			return roleClaim(string(id))
		}).(pulumi.StringOutput))
		ctx.Export("projectRoleCheck", project.ProjectRoleCheck)
		ctx.Export("scopes", project.ID().ApplyT(func(id pulumi.ID) string {
			return "openid offline_access urn:zitadel:iam:org:project:id:" + string(id) + ":aud"
		}).(pulumi.StringOutput))
		return nil
	})
}
