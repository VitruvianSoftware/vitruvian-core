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
  createBackendModule,
  coreServices,
} from "@backstage/backend-plugin-api";

export const mcpActionsOauthModule = createBackendModule({
  pluginId: "mcp-actions",
  moduleId: "oauth-discovery-enhancements",
  register(reg) {
    reg.registerInit({
      deps: {
        rootHttpRouter: coreServices.rootHttpRouter,
        discovery: coreServices.discovery,
        config: coreServices.rootConfig,
      },
      async init({ rootHttpRouter, discovery, config }) {
        const refreshTokenEnabled = config.getOptionalBoolean(
          "auth.experimentalRefreshToken.enabled",
        );

        rootHttpRouter.use(
          "/.well-known/oauth-protected-resource",
          async (_req, res) => {
            const [authBaseUrl, mcpBaseUrl] = await Promise.all([
              discovery.getExternalBaseUrl("auth"),
              discovery.getExternalBaseUrl("mcp-actions"),
            ]);

            res.json({
              resource: `${mcpBaseUrl}/v1`,
              authorization_servers: [authBaseUrl],
              scopes_supported: [
                "openid",
                ...(refreshTokenEnabled ? ["offline_access"] : []),
              ],
            });
          },
        );
      },
    });
  },
});
