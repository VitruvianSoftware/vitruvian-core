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
// Three kinds of client, all public (no secret) with PKCE, all issuing JWT
// access tokens so the relay can validate them locally against JWKS:
//
//   - connector: the program on the user's computer. It signs in with the OAuth
//     device flow (RFC 8628), so it has no redirect URI at all.
//   - claude: Claude's "use your own OAuth client" option. Claude's hosted apps
//     (web, desktop, mobile) use one fixed callback.
//   - chatgpt: created only when chatgptRedirectUris is set. Our Zitadel does
//     not advertise RFC 9207 issuer identification, so ChatGPT uses a
//     per-connector callback (https://chatgpt.com/connector/oauth/{id}) that
//     is only known after the connector is started in ChatGPT's UI.
//
// WHY ITS OWN PROJECT: Zitadel's audience scope is per project, so sharing a
// project with another app would blur that boundary. But note what the sibling
// mcp-slack stack established: in this instance `aud` is caller-authored (any
// authenticated user can request any project's audience scope). The relay must
// therefore authorise on the token's client id (azp) and subject, never on
// `aud` alone. Exported clientIds exist for exactly that pin.
//
// P0 SCOPE: projectRoleCheck is on with one grant, so only the named user can
// complete a sign-in through these clients while the relay is a spike.
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

// clientSpec is everything about one OIDC client that this stack decides.
// Built by pure functions so the decisions are unit-tested; main only turns
// specs into resources.
type clientSpec struct {
	Key          string // resource name suffix and export prefix
	AppType      string
	GrantTypes   []string
	RedirectURIs []string
}

// clientSpecs returns the clients to create. chatgptRaw is the comma-separated
// chatgptRedirectUris config; empty means no ChatGPT client.
func clientSpecs(chatgptRaw string) ([]clientSpec, error) {
	specs := []clientSpec{
		{
			Key:          "connector",
			AppType:      "OIDC_APP_TYPE_NATIVE",
			GrantTypes:   []string{"OIDC_GRANT_TYPE_DEVICE_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"},
			RedirectURIs: []string{},
		},
		{
			Key:          "claude",
			AppType:      "OIDC_APP_TYPE_WEB",
			GrantTypes:   []string{"OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"},
			RedirectURIs: []string{claudeCallback},
		},
	}
	chatgpt, err := parseRedirectURIs(chatgptRaw, "chatgpt.com")
	if err != nil {
		return nil, err
	}
	if len(chatgpt) > 0 {
		specs = append(specs, clientSpec{
			Key:          "chatgpt",
			AppType:      "OIDC_APP_TYPE_WEB",
			GrantTypes:   []string{"OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"},
			RedirectURIs: chatgpt,
		})
	}
	return specs, nil
}

// parseRedirectURIs splits a comma-separated list and refuses anything that is
// not an exact https URL on wantHost. A redirect URI on the wrong host would
// hand an authorization code to someone else, so a typo is an apply error.
func parseRedirectURIs(raw, wantHost string) ([]string, error) {
	var out []string
	for _, part := range strings.Split(raw, ",") {
		s := strings.TrimSpace(part)
		if s == "" {
			continue
		}
		u, err := url.Parse(s)
		if err != nil || u.Scheme != "https" || u.Host != wantHost || u.RawQuery != "" || u.Fragment != "" {
			return nil, fmt.Errorf("%s: redirect URI %q must be an https URL on %s with no query or fragment", cfgNamespace, s, wantHost)
		}
		out = append(out, s)
	}
	return out, nil
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

// resolveGrantUserIDs enforces that the role check and its grant land in the
// same apply. Check on with nobody granted locks everyone out, and the
// failure shows up later as a rejected login rather than as a config change.
func resolveGrantUserIDs(projectRoleCheck bool, raw, roleKey string) ([]string, error) {
	var ids []string
	for _, id := range strings.Split(raw, ",") {
		if trimmed := strings.TrimSpace(id); trimmed != "" {
			ids = append(ids, trimmed)
		}
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
		specs, err := clientSpecs(cfg.Get("chatgptRedirectUris"))
		if err != nil {
			return err
		}

		ignoreOrg := pulumi.IgnoreChanges([]string{"orgId"})

		projectArgs := &zitadel.ProjectArgs{
			Name:                 pulumi.String(projectName),
			ProjectRoleAssertion: pulumi.Bool(false),
			ProjectRoleCheck:     pulumi.Bool(projectRoleCheck),
		}
		if orgID != "" {
			projectArgs.OrgId = pulumi.String(orgID)
		}
		project, err := zitadel.NewProject(ctx, projectName, projectArgs, ignoreOrg)
		if err != nil {
			return err
		}

		if _, err := zitadel.NewProjectRole(ctx, roleKey, &zitadel.ProjectRoleArgs{
			ProjectId:   project.ID(),
			RoleKey:     pulumi.String(roleKey),
			DisplayName: pulumi.String("Relay user"),
		}, ignoreOrg); err != nil {
			return err
		}

		for _, userID := range grantIDs {
			grantArgs := &zitadel.UserGrantArgs{
				ProjectId: project.ID(),
				UserId:    pulumi.String(userID),
				RoleKeys:  pulumi.StringArray{pulumi.String(roleKey)},
			}
			if orgID != "" {
				grantArgs.OrgId = pulumi.String(orgID)
			}
			if _, err := zitadel.NewUserGrant(ctx, "grant-"+userID, grantArgs, ignoreOrg); err != nil {
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
			app, err := zitadel.NewApplicationOidc(ctx, projectName+"-"+s.Key, &zitadel.ApplicationOidcArgs{
				ProjectId:     project.ID(),
				Name:          pulumi.String(projectName + "-" + s.Key),
				RedirectUris:  pulumi.ToStringArray(s.RedirectURIs),
				ResponseTypes: pulumi.StringArray{pulumi.String("OIDC_RESPONSE_TYPE_CODE")},
				GrantTypes:    pulumi.ToStringArray(s.GrantTypes),
				AppType:       pulumi.String(s.AppType),
				// Public client: no secret, PKCE (S256) required by Zitadel.
				AuthMethodType:           pulumi.String("OIDC_AUTH_METHOD_TYPE_NONE"),
				Version:                  pulumi.String("OIDC_VERSION_1_0"),
				AccessTokenType:          pulumi.String("OIDC_TOKEN_TYPE_JWT"),
				DevMode:                  pulumi.Bool(false),
				AccessTokenRoleAssertion: pulumi.Bool(false),
				IdTokenRoleAssertion:     pulumi.Bool(false),
				IdTokenUserinfoAssertion: pulumi.Bool(false),
			}, clientOpts)
			if err != nil {
				return err
			}
			ctx.Export(s.Key+"ClientId", app.ClientId)
			// Exported because it is ignored above, so Pulumi never reconciles
			// it; the relay's local JWT validation depends on it being JWT.
			ctx.Export(s.Key+"AccessTokenType", app.AccessTokenType)
		}

		ctx.Export("projectId", project.ID())
		ctx.Export("projectRoleCheck", project.ProjectRoleCheck)
		ctx.Export("scopes", project.ID().ApplyT(func(id pulumi.ID) string {
			return "openid offline_access urn:zitadel:iam:org:project:id:" + string(id) + ":aud"
		}).(pulumi.StringOutput))
		return nil
	})
}
