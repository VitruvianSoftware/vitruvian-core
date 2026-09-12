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

import type {
  BackstageUserInfo,
  UserInfoService,
} from "@backstage/backend-plugin-api";
import {
  AuthorizeResult,
  type PolicyDecision,
} from "@backstage/plugin-permission-common";
import type {
  PermissionPolicy,
  PolicyQuery,
  PolicyQueryUser,
} from "@backstage/plugin-permission-node";

/**
 * Entity refs granted unrestricted access when `permission.adminEntityRefs` is
 * not set in config. `platform-team` is the owning group declared in the repo
 * root `catalog-info.yaml`, so its members (today: `user:default/ipv1337`) are
 * the portal administrators.
 */
export const DEFAULT_ADMIN_ENTITY_REFS = ["group:default/platform-team"];

/**
 * Permission attribute actions that change state. Backstage tags every
 * permission with an optional action, so keying off it gives us a policy that
 * covers plugins we have not installed yet (rather than enumerating permission
 * names that would silently go unguarded).
 */
const MUTATING_ACTIONS: ReadonlySet<string> = new Set([
  "create",
  "update",
  "delete",
]);

// Entity refs are case-insensitive in Backstage; compare them normalized.
const normalizeRef = (ref: string): string =>
  ref.trim().toLocaleLowerCase("en-US");

/**
 * The portal's authorization model. Backstage core ships no admin concept —
 * upstream's guidance is to express one as a policy in code — so this is it:
 *
 *   - unauthenticated request  -> DENY
 *   - admin (see {@link DEFAULT_ADMIN_ENTITY_REFS}) -> ALLOW everything
 *   - any other signed-in user -> read-only (mutating actions DENY)
 *
 * Note this policy is only consulted when `permission.enabled: true` is set in
 * app-config; with the default (`false`) Backstage allows every request without
 * invoking a policy at all.
 */
export class VitruvianPermissionPolicy implements PermissionPolicy {
  private readonly adminEntityRefs: ReadonlySet<string>;

  constructor(
    adminEntityRefs: readonly string[],
    private readonly userInfo: Pick<UserInfoService, "getUserInfo">,
  ) {
    this.adminEntityRefs = new Set(adminEntityRefs.map(normalizeRef));
  }

  async handle(
    request: PolicyQuery,
    user?: PolicyQueryUser,
  ): Promise<PolicyDecision> {
    if (!user) {
      return { result: AuthorizeResult.DENY };
    }

    let info: BackstageUserInfo;
    try {
      // Resolved from credentials rather than the deprecated `user.info`, which
      // upstream has marked for removal.
      info = await this.userInfo.getUserInfo(user.credentials);
    } catch {
      // Fail closed: if we cannot establish who the caller is, grant nothing.
      return { result: AuthorizeResult.DENY };
    }

    if (this.isAdmin(info)) {
      return { result: AuthorizeResult.ALLOW };
    }

    const { action } = request.permission.attributes;
    return action && MUTATING_ACTIONS.has(action)
      ? { result: AuthorizeResult.DENY }
      : { result: AuthorizeResult.ALLOW };
  }

  private isAdmin(info: BackstageUserInfo): boolean {
    const refs = [
      info.userEntityRef,
      ...(info.ownershipEntityRefs ?? []),
    ].filter((ref): ref is string => typeof ref === "string" && ref.length > 0);

    return refs.some((ref) => this.adminEntityRefs.has(normalizeRef(ref)));
  }
}
