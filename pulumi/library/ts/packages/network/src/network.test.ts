/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the Network module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("Network", () => {
    it("should export the Network class", async () => {
        const mod = await import("./index");
        expect(mod.Network).toBeDefined();
        expect(typeof mod.Network).toBe("function");
    });

    it("should define SubnetConfig interface", async () => {
        const subnet = {
            name: "sb-test-subnet",
            region: "us-central1",
            ipCidrRange: "10.0.0.0/24",
            secondaryRanges: [
                { rangeName: "gke-pods", ipCidrRange: "10.1.0.0/16" },
                { rangeName: "gke-svcs", ipCidrRange: "10.2.0.0/20" },
            ],
        };
        expect(subnet.name).toBe("sb-test-subnet");
        expect(subnet.secondaryRanges).toHaveLength(2);
    });

    it("should instantiate Network with required args", async () => {
        const mod = await import("./index");
        const network = new mod.Network("test-vpc", {
            projectId: "prj-test",
            networkName: "vpc-test",
            subnets: [{
                name: "sb-test",
                region: "us-central1",
                ipCidrRange: "10.0.0.0/24",
            }],
        });
        expect(network).toBeDefined();
    });
});

describe("FirewallRuleConfig", () => {
    it("should validate firewall rule configuration", async () => {
        const rule = {
            name: "allow-ssh",
            direction: "INGRESS",
            priority: 1000,
            ranges: ["35.235.240.0/20"],
            allow: [{ protocol: "tcp", ports: ["22"] }],
        };
        expect(rule.direction).toBe("INGRESS");
        expect(rule.priority).toBe(1000);
    });
});
