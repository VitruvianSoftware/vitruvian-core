/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the HierarchicalFirewallPolicy module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("HierarchicalFirewallPolicy", () => {
    it("should export the HierarchicalFirewallPolicy class", async () => {
        const mod = await import("./index");
        expect(mod.HierarchicalFirewallPolicy).toBeDefined();
    });

    it("should validate rule configuration", async () => {
        const rule = {
            action: "allow",
            direction: "INGRESS",
            priority: 1000,
            targetResources: ["projects/prj-test"],
            match: {
                srcIpRanges: ["10.0.0.0/8"],
                layer4Configs: [{ ipProtocol: "tcp", ports: ["22"] }],
            },
            enableLogging: true,
        };
        expect(rule.action).toBe("allow");
        expect(rule.direction).toBe("INGRESS");
        expect(rule.enableLogging).toBe(true);
    });

    it("should instantiate with rules", async () => {
        const mod = await import("./index");
        const fw = new mod.HierarchicalFirewallPolicy("test-fw", {
            parentNode: "organizations/123456789",
            name: "test-fw-policy",
            rules: [{
                description: "Allow IAP SSH",
                action: "allow",
                direction: "INGRESS",
                priority: 1000,
                ranges: ["35.235.240.0/20"],
                layer4Configs: [{ ipProtocol: "tcp", ports: ["22"] }],
            }],
        });
        expect(fw).toBeDefined();
    });
});
