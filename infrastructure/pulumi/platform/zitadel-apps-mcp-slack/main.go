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

// The Zitadel project and OIDC client that let a remote agent harness (Google
// Gemini Spark) reach the hosted mcp-slack HTTP listener. Sibling of
// platform/zitadel-apps rather than an addition to it: that stack is
// oauth-user-inspector's (hardcoded secret prefix, GCP Secret Manager
// cred-sync, per-env Cloud Run origins) and mcp-slack shares none of those —
// it has no GCP target, one deployment, and needs a project of its own (below).
// Keeping them separate also keeps this apply away from a client whose
// accidental replacement has already broken hosted login once.
//
// WHY ITS OWN PROJECT (not an app inside oauth-user-inspector's): the audience
// -granting scope Zitadel understands is
// `urn:zitadel:iam:org:project:id:{projectId}:aud` — scoped to the PROJECT, not
// the application. Two apps in one project means an access token audienced for
// either validates at both, so `aud` stops being a boundary between them and
// becomes a shared namespace. mcp-slack validates that claim locally (below),
// so the boundary has to be real.
//
// TOKEN MODEL: JWT access tokens, validated locally by mcp-slack against JWKS.
// The alternative (opaque tokens + introspection) would require mcp-slack to
// hold its own Zitadel client credentials in-cluster on top of the Slack bot
// token; local validation needs only the public JWKS, so the deployment keeps
// exactly one secret.
//
// SPARK IS THE CLIENT, mcp-slack IS THE RESOURCE SERVER. Consequences that look
// wrong until you know that: the redirect URI is Google's fixed callback and
// contains nothing of ours (so the mcp-slack hostname appears nowhere in this
// file), and mcp-slack exposes no OAuth discovery endpoint of its own.
//
// APPLYING: the Zitadel management API is NOT reachable over the public
// Cloudflare edge — its bot protection returns 403/1010 to non-browser clients.
// CI applies over tailnet to the internal Envoy gateway LB. See
// ../zitadel-apps/APPLYING-FROM-CI.md; the same prerequisites apply here.
package main

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
	"github.com/pulumiverse/pulumi-zitadel/sdk/go/zitadel"
)

// googleSparkRedirectURI is Gemini's fixed OAuth callback. It is identical for
// every customer and every environment — Spark has one, we do not supply one,
// and there is nothing per-env to register. Sourced from Google's custom-MCP
// connector setup docs (verified 2026-08-06).
const googleSparkRedirectURI = "https://vertexaisearch.cloud.google.com/oauth-redirect"

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "zitadel-apps-mcp-slack")

		// Optional: when unset the provider uses the service user's default org
		// (the "Vitruvian" FirstInstance org), matching the sibling stack.
		orgID := cfg.Get("orgId")

		projectName := cfg.Get("projectName")
		if projectName == "" {
			projectName = "mcp-slack"
		}
		appName := cfg.Get("appName")
		if appName == "" {
			appName = "mcp-slack-spark"
		}

		// Parsed explicitly rather than via cfg.GetBool, which is fail-OPEN here:
		// GetBool routes through cast.ToBool, which swallows the parse error and
		// returns false for anything strconv.ParseBool doesn't recognise. So
		// `projectRoleCheck: "yes"` — a plausible way to try to turn this ON —
		// silently turns it off, and the apply reports success.
		//
		// This flag is the enforcement for "only the intended subject may
		// connect", so a silent false means the project issues tokens to any
		// authenticated user while the config file claims otherwise. Refusing the
		// apply is the only honest outcome for a value we can't interpret.
		projectRoleCheck := false
		if raw := cfg.Get("projectRoleCheck"); raw != "" {
			parsed, err := strconv.ParseBool(raw)
			if err != nil {
				return fmt.Errorf(
					"zitadel-apps-mcp-slack:projectRoleCheck must be a boolean "+
						"(%q is not one). Refusing to apply rather than silently "+
						"leaving the project role check disabled — this flag is what "+
						"restricts who may obtain a token for this project", raw,
				)
			}
			projectRoleCheck = parsed
		}

		projectArgs := &zitadel.ProjectArgs{
			Name: pulumi.String(projectName),
			// Role assertion off: mcp-slack authorizes on the audience claim, not
			// on project roles, so asserting roles into the token would add claims
			// nothing reads.
			ProjectRoleAssertion: pulumi.Bool(false),
			// ROLE CHECK IS THE ENFORCEMENT POINT FOR "only James's subject may
			// connect". With it true, a user needs an explicit role grant on this
			// project before Zitadel will issue them a token for it — which is a
			// real, server-side restriction rather than "there happens to be only
			// one user in the instance".
			//
			// It defaults FALSE. Turning it on with no role granted locks everyone
			// out, including the first end-to-end Spark login.
			//
			// THE FLAG AND THE GRANT ARE ONE ATOMIC CHANGE. An earlier version of
			// this comment prescribed the opposite — apply false, grant, apply
			// true — and that sequence is now explicitly forbidden: it leaves a
			// window where the check is live and nobody holds the role, and the
			// resulting failure surfaces as a rejected login rather than as a
			// config change, so it reads like a bug in the server's auth guard.
			// The guard below enforces this rather than trusting the reader.
			ProjectRoleCheck: pulumi.Bool(projectRoleCheck),
		}
		if orgID != "" {
			projectArgs.OrgId = pulumi.String(orgID)
		}

		project, err := zitadel.NewProject(ctx, projectName, projectArgs)
		if err != nil {
			return err
		}

		// The role that projectRoleCheck gates on. Created up front so enabling
		// the check later is a config flip plus a user grant, not a schema change
		// during an outage.
		roleKey := cfg.Get("roleKey")
		if roleKey == "" {
			roleKey = "mcp-slack-user"
		}
		roleArgs := &zitadel.ProjectRoleArgs{
			ProjectId:   project.ID(),
			RoleKey:     pulumi.String(roleKey),
			DisplayName: pulumi.String("mcp-slack user"),
		}
		if orgID != "" {
			roleArgs.OrgId = pulumi.String(orgID)
		}
		if _, err := zitadel.NewProjectRole(ctx, roleKey, roleArgs); err != nil {
			return err
		}

		// THE COUPLING GUARD — see resolveGrantUserIDs. Extracted rather than
		// written inline so it can actually be exercised by a test: this
		// constraint is a release-gate condition, and a gate enforced by code
		// nobody ran is the same shape of problem it exists to prevent.
		grantIDs, err := resolveGrantUserIDs(projectRoleCheck, cfg.Get("grantUserIds"), roleKey)
		if err != nil {
			return err
		}

		// Grants are created whether or not the check is on. Granting a role
		// nobody is checking is inert, so this is safe ahead of the flip — and
		// it means enabling the check later cannot introduce a gap, because the
		// grant is already in the state.
		for _, userID := range grantIDs {
			grantArgs := &zitadel.UserGrantArgs{
				ProjectId: project.ID(),
				UserId:    pulumi.String(userID),
				RoleKeys:  pulumi.StringArray{pulumi.String(roleKey)},
			}
			if orgID != "" {
				grantArgs.OrgId = pulumi.String(orgID)
			}
			if _, err := zitadel.NewUserGrant(ctx, "grant-"+userID, grantArgs); err != nil {
				return err
			}
		}

		appArgs := &zitadel.ApplicationOidcArgs{
			ProjectId: project.ID(),
			Name:      pulumi.String(appName),
			// Google's callback, and only Google's. Exact-match matters: Zitadel
			// rejects the authorize request with invalid_request / "redirect_uri is
			// missing in the client configuration" on any mismatch, including a
			// stray trailing slash.
			RedirectUris:  pulumi.StringArray{pulumi.String(googleSparkRedirectURI)},
			ResponseTypes: pulumi.StringArray{pulumi.String("OIDC_RESPONSE_TYPE_CODE")},
			// Refresh grant is what makes `offline_access` usable. It does not make
			// Spark ASK for it — the scope string pasted into Spark's config must
			// include offline_access, or scheduled use re-authenticates by hand.
			GrantTypes: pulumi.StringArray{
				pulumi.String("OIDC_GRANT_TYPE_AUTHORIZATION_CODE"),
				pulumi.String("OIDC_GRANT_TYPE_REFRESH_TOKEN"),
			},
			// Confidential client: Spark is configured with a client id AND secret,
			// so this cannot be a public/PKCE-style app. POST vs BASIC is the one
			// thing Google's docs do not state — the instance supports both, so a
			// mismatch is a one-field change here plus a re-apply, not a redesign.
			// Failure signature: Zitadel returns invalid_client at /oauth/v2/token
			// AFTER a successful redirect back. That is this field, not the server.
			AppType:        pulumi.String("OIDC_APP_TYPE_WEB"),
			AuthMethodType: pulumi.String("OIDC_AUTH_METHOD_TYPE_POST"),
			Version:        pulumi.String("OIDC_VERSION_1_0"),
			// JWT rather than the sibling stack's opaque BEARER: mcp-slack verifies
			// signature and audience against JWKS with no call back to Zitadel.
			AccessTokenType: pulumi.String("OIDC_TOKEN_TYPE_JWT"),
			// No localhost redirect exists for this client, so the dev affordance
			// that permits one is off.
			DevMode:                  pulumi.Bool(false),
			AccessTokenRoleAssertion: pulumi.Bool(false),
			IdTokenRoleAssertion:     pulumi.Bool(false),
			IdTokenUserinfoAssertion: pulumi.Bool(false),
		}

		// This client is CREATED and owned here; it is never adopted via
		// pulumi.Import. The pulumiverse/zitadel provider marks appType, version,
		// accessTokenType, clockSkew and the *RoleAssertion / userinfoAssertion
		// fields replace-triggering and does not populate them on import, so an
		// import plans a REPLACEMENT — which against the same Zitadel app means
		// "create replacement + delete original" and destroys the live client.
		// That is not hypothetical: it happened to the sibling stack's app on
		// 2026-06-26 (Errors.App.NotFound, hosted login down). IgnoreChanges on the
		// same fields prevents a spurious provider diff from replacing this one.
		//
		// Practical rule: if this client ever needs to be inspected or fixed, do it
		// here and re-apply. Do not hand-create one in the Zitadel console.
		opts := []pulumi.ResourceOption{
			pulumi.IgnoreChanges([]string{
				"appType",
				"version",
				"accessTokenType",
				"accessTokenRoleAssertion",
				"idTokenRoleAssertion",
				"idTokenUserinfoAssertion",
				"clockSkew",
			}),
		}

		app, err := zitadel.NewApplicationOidc(ctx, appName, appArgs, opts...)
		if err != nil {
			return err
		}

		// projectId is consumed by the mcp-slack deployment (it validates the
		// audience claim against it) and appears in the scope string pasted into
		// Spark. Exported rather than hardcoded anywhere downstream.
		ctx.Export("projectId", project.ID())
		// The exact scope string Spark must be configured with. Assembled here
		// because the audience form is easy to get subtly wrong by hand, and a
		// token missing it is valid in every other respect — it just fails every
		// call against mcp-slack.
		ctx.Export("sparkScopes", project.ID().ApplyT(func(id pulumi.ID) string {
			return "openid offline_access urn:zitadel:iam:org:project:id:" + string(id) + ":aud"
		}).(pulumi.StringOutput))
		ctx.Export("clientId", app.ClientId)
		// Exported because `accessTokenType` is in the IgnoreChanges list above and
		// therefore the ONE setting Pulumi will never reconcile. mcp-slack's whole
		// auth model assumes JWT: if the live client ever sits on BEARER (a partial
		// apply, a console edit during debugging, a create that didn't land), the
		// stack reports clean forever while the server rejects every request — and
		// the symptom is indistinguishable from a broken transport.
		//
		// Surfacing it as an output makes the check a query rather than a thing
		// someone has to remember to do in the console:
		//
		//   bazel run //infrastructure/pulumi/platform/zitadel-apps-mcp-slack:refresh
		//   pulumi stack output accessTokenType   # want: OIDC_TOKEN_TYPE_JWT
		//
		// The refresh matters: without it this reports the value Pulumi last wrote,
		// not the value Zitadel currently holds. Refresh updates state from live
		// even for ignored fields — the ignore suppresses the diff being *applied*,
		// not the state being read.
		ctx.Export("accessTokenType", app.AccessTokenType)
		// Exported so "is the access control actually on?" is a query rather than a
		// recollection. The bootstrap order means the PoC necessarily works before
		// this is enabled — apply with it false, grant the role, then apply again
		// with it true — and nothing about the endpoint functioning would reveal
		// that the last step never happened. Every tool call succeeds either way.
		//
		// So this is the value that answers it: `pulumi stack output
		// projectRoleCheck` must read true before the deployment is considered
		// restricted to its intended subject.
		ctx.Export("projectRoleCheck", project.ProjectRoleCheck)
		// Secret output: Pulumi keeps it encrypted in state and masks it in
		// plaintext output. It is pasted into Spark's connector config by hand —
		// there is no GCP Secret Manager sync here, unlike the sibling stack,
		// because the consumer is a k3s deployment, not a Cloud Run service.
		ctx.Export("clientSecret", app.ClientSecret)
		ctx.Export("authorizationEndpoint", pulumi.String("https://auth.ipv1337.dev/oauth/v2/authorize"))
		ctx.Export("tokenEndpoint", pulumi.String("https://auth.ipv1337.dev/oauth/v2/token"))
		return nil
	})
}

// resolveGrantUserIDs parses the grantUserIds config and enforces the coupling
// between it and projectRoleCheck.
//
// THE FLAG AND THE GRANT ARE ONE ATOMIC CHANGE. Enabling the project role
// check without granting the role to at least one user in the SAME apply is
// refused here rather than tracked as a task somebody remembers.
//
// The failure it prevents is specifically nasty because it does not surface
// where it is caused: enabling the check while nobody holds the role does not
// break the apply, it breaks the next LOGIN. Zitadel declines to issue a token
// for the project, the server rejects the request, and the symptom is an auth
// failure during the first end-to-end Spark test — which points every
// reasonable investigation at the server's auth guard rather than at a config
// flag flipped in an earlier, already-forgotten apply.
//
// Not hypothetical. As of 2026-08-06 the human user holds ZERO grants on any
// project in this org, and the existing oauth-user-inspector project works
// only because its role check is off. The first apply with this flag true and
// no grantUserIds would lock out the one person who needs in.
//
// Note the asymmetry: a grant with the check OFF is inert and harmless, so
// grants are always created. Only the reverse — check on, no grant — is
// refused. Failing closed here means refusing to apply, not applying something
// permissive.
func resolveGrantUserIDs(projectRoleCheck bool, raw, roleKey string) ([]string, error) {
	var ids []string
	for _, id := range strings.Split(raw, ",") {
		if trimmed := strings.TrimSpace(id); trimmed != "" {
			ids = append(ids, trimmed)
		}
	}
	if projectRoleCheck && len(ids) == 0 {
		return nil, fmt.Errorf(
			"zitadel-apps-mcp-slack:projectRoleCheck is true but grantUserIds "+
				"is empty. Refusing to apply: enabling the project role check "+
				"without granting %q to at least one user in the SAME apply "+
				"locks every user out of this project, and the resulting login "+
				"failure looks like a server auth bug rather than a config "+
				"change. Set grantUserIds to the Zitadel user id(s) that must "+
				"retain access, or leave projectRoleCheck false", roleKey,
		)
	}
	return ids, nil
}
