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
import { GoogleAuth } from "google-auth-library";
import Router from "express-promise-router";
import {
  mapService,
  parseCloudRunRefs,
  serviceUrl,
  type CloudRunStatus,
} from "./refs";

/**
 * Serves Cloud Run status for entities that name their services.
 *
 * WHY THIS IS A BACKEND ROUTE AND NOT A PROXY ENTRY
 * -------------------------------------------------
 * The proxy forwards a static header; it cannot mint a Google token. This
 * identity is federated (Workload Identity, no key -- see
 * docs/gcp-cluster-federation.md), so the credential is a short-lived token
 * exchanged at request time from the pod's projected ServiceAccount token.
 * GoogleAuth's ADC chain does that exchange for us given the external-account
 * credential file; nothing long-lived is stored anywhere.
 */
export const cloudRunPlugin = createBackendPlugin({
  pluginId: "cloud-run",
  register(env) {
    env.registerInit({
      deps: { http: coreServices.httpRouter, logger: coreServices.logger },
      async init({ http, logger }) {
        // One GoogleAuth for the process: it caches the exchanged token and
        // refreshes it, so a per-request instance would re-do the STS exchange
        // on every card render.
        const auth = new GoogleAuth({
          scopes: ["https://www.googleapis.com/auth/cloud-platform.read-only"],
        });

        const router = Router();
        router.get("/services", async (req, res) => {
          const { refs, invalid } = parseCloudRunRefs(
            typeof req.query.refs === "string" ? req.query.refs : undefined,
          );
          if (invalid.length) {
            logger.warn(
              `cloud-run: ignoring ${invalid.length} malformed ref(s): ${invalid.join(", ")}`,
            );
          }
          if (!refs.length) {
            res.json({ services: [], invalid });
            return;
          }

          const client = await auth.getClient();
          const services: CloudRunStatus[] = await Promise.all(
            refs.map(async (ref) => {
              try {
                const r = await client.request<Record<string, unknown>>({
                  url: serviceUrl(ref),
                });
                return mapService(ref, r.data as never);
              } catch (e) {
                // One unreachable environment must not blank the whole card.
                // Surfacing it as not-ready with the reason is more useful than
                // a 500 that hides the environments that DID answer.
                logger.warn(
                  `cloud-run: ${ref.project}/${ref.service} failed: ${e}`,
                );
                return {
                  label: ref.label,
                  service: ref.service,
                  traffic: [],
                  ready: false,
                  message: e instanceof Error ? e.message : String(e),
                };
              }
            }),
          );
          res.json({ services, invalid });
        });

        http.use(router);
        // Entity data, not secrets -- but it is still an authenticated read,
        // consistent with the rest of this backend after the default auth
        // policy was re-enabled.
        http.addAuthPolicy({ path: "/services", allow: "user-cookie" });
      },
    });
  },
});
