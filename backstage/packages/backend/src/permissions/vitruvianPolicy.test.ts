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

import type { BackstageUserInfo } from "@backstage/backend-plugin-api";
import {
  AuthorizeResult,
  type Permission,
} from "@backstage/plugin-permission-common";
import type {
  PolicyQuery,
  PolicyQueryUser,
} from "@backstage/plugin-permission-node";

import {
  DEFAULT_ADMIN_ENTITY_REFS,
  VitruvianPermissionPolicy,
} from "./vitruvianPolicy";

const permission = (
  name: string,
  action?: "create" | "read" | "update" | "delete",
): Permission =>
  ({ name, attributes: action ? { action } : {}, type: "basic" }) as Permission;

const query = (p: Permission): PolicyQuery =>
  ({ permission: p }) as PolicyQuery;

const ADMIN: BackstageUserInfo = {
  userEntityRef: "user:default/ipv1337",
  ownershipEntityRefs: ["user:default/ipv1337", "group:default/platform-team"],
};

const NON_ADMIN: BackstageUserInfo = {
  userEntityRef: "user:default/contributor",
  ownershipEntityRefs: [
    "user:default/contributor",
    "group:default/tabula-team",
  ],
};

// The policy only ever touches `credentials`, so a token stand-in is enough.
const asUser = (): PolicyQueryUser => ({}) as PolicyQueryUser;

const policyFor = (
  info: BackstageUserInfo | Error,
  adminRefs: readonly string[] = DEFAULT_ADMIN_ENTITY_REFS,
) =>
  new VitruvianPermissionPolicy(adminRefs, {
    getUserInfo: async () => {
      if (info instanceof Error) {
        throw info;
      }
      return info;
    },
  });

describe("VitruvianPermissionPolicy", () => {
  it("denies unauthenticated requests outright", async () => {
    const decision = await policyFor(ADMIN).handle(
      query(permission("catalog.entity.read", "read")),
      undefined,
    );

    expect(decision.result).toBe(AuthorizeResult.DENY);
  });

  it.each([
    ["catalog.entity.create", "create"],
    ["catalog.entity.delete", "delete"],
    ["catalog.entity.refresh", "update"],
    ["scaffolder.task.create", "create"],
  ] as const)("allows an admin to %s", async (name, action) => {
    const decision = await policyFor(ADMIN).handle(
      query(permission(name, action)),
      asUser(),
    );

    expect(decision.result).toBe(AuthorizeResult.ALLOW);
  });

  it("treats membership of an admin group as admin, case-insensitively", async () => {
    const mixedCase: BackstageUserInfo = {
      userEntityRef: "User:Default/ipv1337",
      ownershipEntityRefs: ["Group:Default/Platform-Team"],
    };

    const decision = await policyFor(mixedCase).handle(
      query(permission("catalog.entity.delete", "delete")),
      asUser(),
    );

    expect(decision.result).toBe(AuthorizeResult.ALLOW);
  });

  it.each([
    ["catalog.entity.create", "create"],
    ["catalog.entity.delete", "delete"],
    ["scaffolder.task.create", "create"],
  ] as const)(
    "denies a non-admin the mutating permission %s",
    async (name, action) => {
      const decision = await policyFor(NON_ADMIN).handle(
        query(permission(name, action)),
        asUser(),
      );

      expect(decision.result).toBe(AuthorizeResult.DENY);
    },
  );

  it.each([
    ["catalog.entity.read", "read"],
    ["catalog.location.read", "read"],
  ] as const)("still allows a non-admin to %s", async (name, action) => {
    const decision = await policyFor(NON_ADMIN).handle(
      query(permission(name, action)),
      asUser(),
    );

    expect(decision.result).toBe(AuthorizeResult.ALLOW);
  });

  it("allows a non-admin a permission carrying no action attribute", async () => {
    const decision = await policyFor(NON_ADMIN).handle(
      query(permission("some.plugin.view")),
      asUser(),
    );

    expect(decision.result).toBe(AuthorizeResult.ALLOW);
  });

  it("fails closed when user info cannot be resolved", async () => {
    const decision = await policyFor(new Error("token rejected")).handle(
      query(permission("catalog.entity.read", "read")),
      asUser(),
    );

    expect(decision.result).toBe(AuthorizeResult.DENY);
  });

  it("honours a configured admin ref that is not the default group", async () => {
    const decision = await policyFor(NON_ADMIN, [
      "group:default/tabula-team",
    ]).handle(query(permission("catalog.entity.delete", "delete")), asUser());

    expect(decision.result).toBe(AuthorizeResult.ALLOW);
  });

  it("does not treat the default admin group as admin once it is unconfigured", async () => {
    const decision = await policyFor(ADMIN, ["group:default/nobody"]).handle(
      query(permission("catalog.entity.delete", "delete")),
      asUser(),
    );

    expect(decision.result).toBe(AuthorizeResult.DENY);
  });
});
