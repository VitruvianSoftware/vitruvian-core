/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the OrgPolicy module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("OrgPolicyBoolean", () => {
    it("should export the OrgPolicyBoolean class", async () => {
        const mod = await import("./index");
        expect(mod.OrgPolicyBoolean).toBeDefined();
    });

    it("should enforce boolean constraint", async () => {
        const mod = await import("./index");
        const policy = new mod.OrgPolicyBoolean("test-bool-policy", {
            orgId: "123456789",
            constraint: "compute.disableSerialPortAccess",
            enforced: true,
        });
        expect(policy).toBeDefined();
    });
});

describe("OrgPolicyList", () => {
    it("should export the OrgPolicyList class", async () => {
        const mod = await import("./index");
        expect(mod.OrgPolicyList).toBeDefined();
    });

    it("should enforce list constraint with allowed values", async () => {
        const mod = await import("./index");
        const policy = new mod.OrgPolicyList("test-list-policy", {
            orgId: "123456789",
            constraint: "gcp.resourceLocations",
            policyType: "allow",
            values: ["us-locations"],
        });
        expect(policy).toBeDefined();
    });

    it("should enforce list constraint with denied values", async () => {
        const mod = await import("./index");
        const policy = new mod.OrgPolicyList("test-deny-policy", {
            orgId: "123456789",
            constraint: "compute.restrictVpnPeerIPs",
            policyType: "deny",
            values: ["0.0.0.0/0"],
        });
        expect(policy).toBeDefined();
    });
});
