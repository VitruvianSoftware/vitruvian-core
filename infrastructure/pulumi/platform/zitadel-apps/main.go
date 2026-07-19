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
// MULTI-ENV (stage-5 OSS application stage): one stack per environment
// (development / nonproduction / production), each minting its OWN OIDC client
// for that env's oauth-user-inspector deployment. Its redirect_uris MUST
// exactly match the app's origin (trailing slash included) or Zitadel rejects
// the authorize request with invalid_request / "redirect_uri is missing in the
// client configuration".
//
// CRED-SYNC-TO-GCP-SM (spec §9): when `ossProject` is configured, the minted
// clientId/clientSecret are ALSO written into that env's oss-floating
// project's Secret Manager under the app's OAUTH_USER_INSPECTOR_ prefix, so
// the running app (server/server.ts, SECRET_PREFIX) reads them directly —
// closing the previously-manual sync gap. The GCP write requires GCP
// credentials at apply time: the first per-env apply (which CREATES the two
// secrets) runs as sa-terraform-proj (folder-scoped secretmanager.admin,
// Phase 1); subsequent CI applies run as the env's deploy SA, whose
// prefix-conditioned secretmanager.admin grant (deploy-identity stack) covers
// version adds/updates on the existing secrets.
//
// The Zitadel provider authenticates with a machine-user JWT profile key (set
// via `zitadel:*` config — see the project README). This program CREATES and
// owns each client; whenever it mints a new one, the GCP secrets above are
// re-synced by the same apply. Do NOT try to adopt an existing client via
// import — it is destructive on this provider and deletes the live app (see
// the opts block below).
//
// Applied by CI as the "expand" step of the oauth-user-inspector-deploy
// workflow (principles §2.14/§2.15), gated on ZITADEL_APPS_AUTO_APPLY. The
// Bazel run targets (:preview/:up) are local preview / break-glass only.
package main

import (
	"os"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/secretmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
	"github.com/pulumiverse/pulumi-zitadel/sdk/go/zitadel"
)

// secretPrefix namespaces this app's Secret Manager entries in the shared oss
// project (must match the app stack's SECRET_PREFIX env and the identity
// stack's IAM conditions).
const secretPrefix = "OAUTH_USER_INSPECTOR_"

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

		// The env's Cloud Run host is only known AFTER the app stack's first
		// deploy, so it cannot be committed config. When the app stack exists,
		// its serviceUrl is appended via StackReference — guarded behind
		// ZITADEL_APPS_APP_STACK / appStack so the FIRST per-env apply (app stack
		// not yet created) doesn't fail. The deploy workflow probes for the app
		// stack and sets the env var when present, so the run.app redirect
		// self-heals on the next pipeline run after the first app deploy.
		redirectIn := pulumi.StringArrayInput(pulumi.ToStringArray(redirectURIs))
		postLogoutIn := pulumi.StringArrayInput(pulumi.ToStringArray(postLogoutURIs))
		if appStack := envOrConfig("ZITADEL_APPS_APP_STACK", cfg, "appStack"); appStack != "" {
			ref, err := pulumi.NewStackReference(ctx, "app-stack", &pulumi.StackReferenceArgs{
				Name: pulumi.String(appStack),
			})
			if err != nil {
				return err
			}
			serviceURL := ref.GetStringOutput(pulumi.String("serviceUrl"))
			redirectIn = serviceURL.ApplyT(func(u string) []string {
				return appendServiceURI(redirectURIs, u)
			}).(pulumi.StringArrayOutput)
			postLogoutIn = serviceURL.ApplyT(func(u string) []string {
				return appendServiceURI(postLogoutURIs, u)
			}).(pulumi.StringArrayOutput)
		}

		args := &zitadel.ApplicationOidcArgs{
			ProjectId:              pulumi.String(projectID),
			Name:                   pulumi.String(appName),
			RedirectUris:           redirectIn,
			PostLogoutRedirectUris: postLogoutIn,
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
			// devMode allows the http://localhost dev redirect; every env keeps the
			// localhost redirect for local development against the env's client, so
			// devMode stays on (dropping localhost + devMode in production is a
			// deliberate hardening follow-up, not a per-env difference today).
			DevMode:                  pulumi.Bool(true),
			AccessTokenType:          pulumi.String("OIDC_TOKEN_TYPE_BEARER"),
			AccessTokenRoleAssertion: pulumi.Bool(false),
			IdTokenRoleAssertion:     pulumi.Bool(false),
			IdTokenUserinfoAssertion: pulumi.Bool(false),
		}
		if orgID != "" {
			args.OrgId = pulumi.String(orgID)
		}

		// IMPORTANT — this app is CREATED and owned by Pulumi; do NOT adopt it via
		// pulumi.Import. The pulumiverse/zitadel provider marks appType, version,
		// accessTokenType, clockSkew and the *RoleAssertion / userinfoAssertion
		// fields as replace-triggering, and its import does NOT populate them — so an
		// import plans a *replacement*. For this resource a replacement is an "import
		// replacement + delete original" against the SAME Zitadel app, which DELETES
		// the live client. (Proven: the 2026-06-26 CI apply replaced+deleted app
		// 378961731390539356, breaking hosted login with Errors.App.NotFound.) The
		// recovery is always: create a fresh client here; the same apply then syncs
		// its clientId/clientSecret to GCP Secret Manager (below) — there is no
		// non-destructive adopt for this provider.
		//
		// IgnoreChanges on the force-new fields is belt-and-suspenders: it prevents a
		// spurious provider diff (or a re-introduced import) from ever replacing — and
		// thus deleting — the live client out from under the stored credentials.
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

		app, err := zitadel.NewApplicationOidc(ctx, "oauth-user-inspector", args, opts...)
		if err != nil {
			return err
		}

		// Cred-sync-to-GCP-SM (spec §9): write the minted client id/secret into
		// the env's oss project under the app prefix, where the running app reads
		// them (server.ts getSecret with SECRET_PREFIX). SecretData comes from
		// provider secret outputs, so the values stay encrypted in state.
		if ossProject := cfg.Get("ossProject"); ossProject != "" {
			for _, s := range []struct {
				id  string
				val pulumi.StringInput
			}{
				{secretPrefix + "ZITADEL_APP_OAUTH_CLIENT_ID", app.ClientId},
				{secretPrefix + "ZITADEL_APP_OAUTH_CLIENT_SECRET", app.ClientSecret},
			} {
				sec, err := secretmanager.NewSecret(ctx, s.id, &secretmanager.SecretArgs{
					Project:  pulumi.String(ossProject),
					SecretId: pulumi.String(s.id),
					Replication: &secretmanager.SecretReplicationArgs{
						Auto: &secretmanager.SecretReplicationAutoArgs{},
					},
				})
				if err != nil {
					return err
				}
				if _, err := secretmanager.NewSecretVersion(ctx, s.id+"-v", &secretmanager.SecretVersionArgs{
					Secret:     sec.ID(),
					SecretData: s.val,
				}); err != nil {
					return err
				}
			}
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

// appendServiceURI appends the app's Cloud Run origin (with a trailing slash,
// which Zitadel requires to exactly match) unless it is empty or already
// present.
func appendServiceURI(base []string, serviceURL string) []string {
	if serviceURL == "" {
		return base
	}
	uri := strings.TrimSuffix(serviceURL, "/") + "/"
	for _, b := range base {
		if b == uri {
			return base
		}
	}
	return append(append([]string{}, base...), uri)
}

// envOrConfig reads a per-invocation input: the environment variable wins
// (process-scoped, so concurrent invocations can't clobber each other).
func envOrConfig(envName string, cfg *config.Config, cfgKey string) string {
	if v := os.Getenv(envName); v != "" {
		return v
	}
	return cfg.Get(cfgKey)
}
