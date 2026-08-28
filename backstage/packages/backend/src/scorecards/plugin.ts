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
  createBackendPlugin,
  coreServices,
} from "@backstage/backend-plugin-api";
import { CatalogClient } from "@backstage/catalog-client";
import { createScorecardRouter } from "./router";

/**
 * Serves Level 3 Operational Maturity Scorecards & Governance diagnostics.
 */
export const scorecardsPlugin = createBackendPlugin({
  pluginId: "scorecards",
  register(env) {
    env.registerInit({
      deps: {
        http: coreServices.httpRouter,
        logger: coreServices.logger,
        config: coreServices.rootConfig,
        discovery: coreServices.discovery,
        auth: coreServices.auth,
      },
      async init({ http, logger, config, discovery, auth }) {
        const catalogClient = new CatalogClient({ discoveryApi: discovery });
        const router = await createScorecardRouter({
          catalogClient,
          logger,
          config,
          auth,
        });

        http.use(router);
        http.addAuthPolicy({ path: "/entities", allow: "unauthenticated" });
        http.addAuthPolicy({ path: "/evaluate", allow: "unauthenticated" });
      },
    });
  },
});
