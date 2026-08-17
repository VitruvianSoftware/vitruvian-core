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
import { policyExtensionPoint } from "@backstage/plugin-permission-node/alpha";

import {
  DEFAULT_ADMIN_ENTITY_REFS,
  VitruvianPermissionPolicy,
} from "./vitruvianPolicy";

/**
 * Installs {@link VitruvianPermissionPolicy} in place of the upstream
 * allow-all reference policy.
 *
 * Admins are configurable via `permission.adminEntityRefs` so changing who
 * administers the portal is a config (GitOps) change rather than a code change.
 */
export const permissionModuleVitruvianPolicy = createBackendModule({
  pluginId: "permission",
  moduleId: "vitruvian-policy",
  register(reg) {
    reg.registerInit({
      deps: {
        policy: policyExtensionPoint,
        config: coreServices.rootConfig,
        userInfo: coreServices.userInfo,
        logger: coreServices.logger,
      },
      async init({ policy, config, userInfo, logger }) {
        const adminEntityRefs =
          config.getOptionalStringArray("permission.adminEntityRefs") ??
          DEFAULT_ADMIN_ENTITY_REFS;

        if (!config.getOptionalBoolean("permission.enabled")) {
          logger.warn(
            "permission.enabled is not true — Backstage will allow every request " +
              "without consulting the Vitruvian permission policy.",
          );
        }

        logger.info(
          `Vitruvian permission policy active; admin entity refs: ${adminEntityRefs.join(", ")}`,
        );

        policy.setPolicy(
          new VitruvianPermissionPolicy(adminEntityRefs, userInfo),
        );
      },
    });
  },
});
