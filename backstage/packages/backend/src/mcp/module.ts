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

/**
 * Configures the auth policy for the MCP actions plugin endpoint (/v1).
 *
 * Allows unauthenticated callers (e.g. local coding assistants like Antigravity
 * or Claude Code) to reach the MCP router without requiring a pre-minted bearer token
 * or browser cookie. Authorisation continues to be enforced downstream by the
 * Vitruvian permission policy, which restricts unauthenticated calls to read-only actions.
 */
export const mcpActionsAuthModule = createBackendModule({
  pluginId: "mcp-actions",
  moduleId: "auth-policy",
  register(reg) {
    reg.registerInit({
      deps: {
        httpRouter: coreServices.httpRouter,
      },
      async init({ httpRouter }) {
        httpRouter.addAuthPolicy({
          path: "/v1",
          allow: "unauthenticated",
        });
      },
    });
  },
});
