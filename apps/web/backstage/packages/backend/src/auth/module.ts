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

import {
  coreServices,
  createBackendModule,
} from "@backstage/backend-plugin-api";
import {
  authProvidersExtensionPoint,
  createOAuthProviderFactory,
} from "@backstage/plugin-auth-node";
import {
  githubAuthenticator,
  githubSignInResolvers,
} from "@backstage/plugin-auth-backend-module-github-provider";

import { DEFAULT_ALLOWED_ORG, assertActiveOrgMember } from "./githubOrgSignIn";

/**
 * Replaces the stock GitHub auth provider with one that additionally proves the
 * signing-in user is an active member of the configured GitHub organisation.
 *
 * Before this, sign-in was gated only by `usernameMatchingUserEntityName`: any
 * GitHub account whose login happened to match a hand-declared catalog User
 * entity could sign in, and nothing ever consulted GitHub about the org. Both
 * checks now apply — org membership AND a catalog user — so the catalog stays
 * the source of ownership while GitHub is the source of truth for who belongs.
 *
 * Deliberately credential-free: membership is proven with the user's own OAuth
 * token (`read:org`, requested below), so the portal stores no PAT or GitHub App
 * key to rotate.
 */
export const authModuleGithubOrgProvider = createBackendModule({
  pluginId: "auth",
  moduleId: "github-org-provider",
  register(reg) {
    reg.registerInit({
      deps: {
        providers: authProvidersExtensionPoint,
        config: coreServices.rootConfig,
        logger: coreServices.logger,
      },
      async init({ providers, config, logger }) {
        const org =
          config.getOptionalString("auth.github.allowedOrg") ??
          DEFAULT_ALLOWED_ORG;

        logger.info(
          `GitHub sign-in restricted to active members of the '${org}' organisation`,
        );

        providers.registerProvider({
          providerId: "github",
          factory: createOAuthProviderFactory({
            authenticator: githubAuthenticator,
            // Keep the built-in resolvers registered even though the explicit
            // signInResolver below is what normally runs. Without this, naming
            // one in app-config (e.g. usernameMatchingUserEntityName) fails
            // startup with "Sign-in resolver ... is not available" -- config and
            // code could silently diverge and wedge the rollout.
            signInResolverFactories: {
              ...githubSignInResolvers,
            },
            // Needed for /user/memberships/orgs/{org}. Existing sessions were
            // issued with read:user only, so users re-consent once on next login.
            additionalScopes: ["read:org"],
            async signInResolver(info, ctx) {
              await assertActiveOrgMember({
                org,
                accessToken: info.result.session.accessToken,
              });

              // Membership proven; resolve to the catalog user exactly as the
              // stock usernameMatchingUserEntityName resolver did, so ownership
              // and group membership keep working unchanged.
              const username = info.result.fullProfile.username;
              if (!username) {
                throw new Error(
                  "GitHub profile did not include a username to match against the catalog",
                );
              }
              return ctx.signInWithCatalogUser({
                entityRef: { name: username },
              });
            },
          }),
        });
      },
    });
  },
});
