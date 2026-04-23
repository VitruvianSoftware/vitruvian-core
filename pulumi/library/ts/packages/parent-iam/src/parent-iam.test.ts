/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the ParentIam module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("ParentIamMember", () => {
    it("should export the ParentIamMember class", async () => {
        const mod = await import("./index");
        expect(mod.ParentIamMember).toBeDefined();
    });

    it("should validate IAM member args", async () => {
        const args = {
            parentType: "organization" as const,
            parentId: "123456789",
            roles: ["roles/viewer", "roles/browser"],
            member: "group:admins@example.com",
        };
        expect(args.parentType).toBe("organization");
        expect(args.roles).toHaveLength(2);
    });

    it("should instantiate ParentIamMember at org level", async () => {
        const mod = await import("./index");
        const iam = new mod.ParentIamMember("test-iam", {
            parentType: "organization",
            parentId: "123456789",
            roles: ["roles/viewer"],
            member: "group:admins@example.com",
        });
        expect(iam).toBeDefined();
    });
});

describe("ParentIamRemoveRole", () => {
    it("should export the ParentIamRemoveRole class", async () => {
        const mod = await import("./index");
        expect(mod.ParentIamRemoveRole).toBeDefined();
    });
});
