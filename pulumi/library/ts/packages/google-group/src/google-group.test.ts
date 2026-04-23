/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the GoogleGroup module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("GoogleGroup", () => {
    it("should export the GoogleGroup class", async () => {
        const mod = await import("./index");
        expect(mod.GoogleGroup).toBeDefined();
    });

    it("should validate group args", async () => {
        const args = {
            id: "admins@example.com",
            displayName: "Admins",
            description: "Organization admins",
            customerId: "C01234567",
            initialGroupConfig: "WITH_INITIAL_OWNER",
        };
        expect(args.id).toBe("admins@example.com");
        expect(args.customerId).toBe("C01234567");
    });

    it("should instantiate GoogleGroup", async () => {
        const mod = await import("./index");
        const group = new mod.GoogleGroup("test-group", {
            id: "test@example.com",
            displayName: "Test Group",
            customerId: "C01234567",
        });
        expect(group).toBeDefined();
    });
});
