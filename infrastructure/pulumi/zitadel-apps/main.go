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

// Zitadel first-party OAuth applications, managed as code against the
// self-hosted Zitadel instance (gitops/argocd/platform/zitadel, public at
// https://auth.ipv1337.dev). The Zitadel *instance* is GitOps-managed; the
// OAuth *applications* it hosts for our apps live here so their redirect URIs
// (and other client settings) are version-controlled rather than hand-edited
// in the console.
//
// Currently manages: the hosted oauth-user-inspector OIDC client. Its
// redirect_uris MUST exactly match the app's own origin
// (https://oauth-inspector.ipv1337.dev/, trailing slash included) or Zitadel
// rejects the authorize request with invalid_request / "redirect_uri is missing
// in the client configuration".
//
// The Zitadel provider authenticates with a machine-user JWT profile key (set
// via `zitadel:*` config — see the project README). The app's client_id/secret
// are consumed by the running app from GCP Secret Manager
// (ZITADEL_APP_OAUTH_CLIENT_ID / _SECRET); to keep those valid, ADOPT the
// existing application by setting zitadel-apps:importId rather than letting this
// program create a new client. See the README.
//
// Applied by CI as the "expand" step of the oauth-user-inspector-deploy workflow
// (principles §2.14/§2.15), gated on ZITADEL_APPS_AUTO_APPLY. The Bazel run
// targets (:preview/:up) are local preview / break-glass only.
package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
	"github.com/pulumiverse/pulumi-zitadel/sdk/go/zitadel"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "zitadel-apps")

		// The Zitadel project that owns the application. Required. The org is
		// optional — when unset the provider uses the service user's default org
		// (the "Vitruvian" FirstInstance org).
		projectID := cfg.Require("projectId")
		orgID := cfg.Get("orgId")

		appName := cfg.Get("appName")
		if appName == "" {
			appName = "OAuth User Inspector"
		}

		// Allowed redirect / post-logout URIs. These must EXACTLY match what the
		// app sends (origin + path, trailing slash included). Defaults to the
		// production instance; override per stack with, e.g.:
		//   pulumi config set --path zitadel-apps:redirectUris[0] https://oauth-inspector.ipv1337.dev/
		redirectURIs := []string{"https://oauth-inspector.ipv1337.dev/"}
		if err := cfg.GetObject("redirectUris", &redirectURIs); err != nil {
			return err
		}
		postLogoutURIs := redirectURIs
		if err := cfg.GetObject("postLogoutRedirectUris", &postLogoutURIs); err != nil {
			return err
		}

		args := &zitadel.ApplicationOidcArgs{
			ProjectId:              pulumi.String(projectID),
			Name:                   pulumi.String(appName),
			RedirectUris:           pulumi.ToStringArray(redirectURIs),
			PostLogoutRedirectUris: pulumi.ToStringArray(postLogoutURIs),
			ResponseTypes:          pulumi.StringArray{pulumi.String("OIDC_RESPONSE_TYPE_CODE")},
			// Authorization-code flow with refresh tokens (offline_access), matching
			// the hosted server flow (code exchange + token refresh/revoke).
			GrantTypes: pulumi.StringArray{
				pulumi.String("OIDC_GRANT_TYPE_AUTHORIZATION_CODE"),
				pulumi.String("OIDC_GRANT_TYPE_REFRESH_TOKEN"),
			},
			// Confidential web app: the backend exchanges the code with a client
			// secret. It sends client_id/secret in the token-request BODY
			// (client_secret_post), so the client auth method is POST — this MUST
			// match the live client; a BASIC mismatch breaks the code->token exchange.
			AppType:        pulumi.String("OIDC_APP_TYPE_WEB"),
			AuthMethodType: pulumi.String("OIDC_AUTH_METHOD_TYPE_POST"),
			Version:        pulumi.String("OIDC_VERSION_1_0"),
			// devMode allows the http://localhost dev redirect; the live client has
			// it enabled and the redirect set keeps localhost.
			DevMode:                  pulumi.Bool(true),
			AccessTokenType:          pulumi.String("OIDC_TOKEN_TYPE_BEARER"),
			AccessTokenRoleAssertion: pulumi.Bool(false),
			IdTokenRoleAssertion:     pulumi.Bool(false),
			IdTokenUserinfoAssertion: pulumi.Bool(false),
		}
		if orgID != "" {
			args.OrgId = pulumi.String(orgID)
		}

		// Adopt the existing application instead of creating a new one, so the
		// client_id/secret already stored in GCP Secret Manager stay valid. Set
		// zitadel-apps:importId to the provider's import id for the existing app
		// (provider import format: "<app_id>:<project_id>[:<org_id>]", app-id first).
		// Leave unset to create a brand-new client (then re-sync the secrets).
		opts := []pulumi.ResourceOption{}
		if importID := cfg.Get("importId"); importID != "" {
			opts = append(opts, pulumi.Import(pulumi.ID(importID)))
		}

		app, err := zitadel.NewApplicationOidc(ctx, "oauth-user-inspector", args, opts...)
		if err != nil {
			return err
		}

		ctx.Export("clientId", app.ClientId)
		// Secret output — surfaced so it can be synced to GCP Secret Manager when
		// a NEW client is created. Pulumi keeps it encrypted in state and masks it
		// in plaintext output.
		ctx.Export("clientSecret", app.ClientSecret)
		ctx.Export("redirectUris", app.RedirectUris)
		return nil
	})
}
