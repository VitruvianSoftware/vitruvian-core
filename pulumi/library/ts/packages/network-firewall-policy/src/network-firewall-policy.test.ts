/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the NetworkFirewallPolicy module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("NetworkFirewallPolicy", () => {
    it("should export the NetworkFirewallPolicy class", async () => {
        const mod = await import("./index");
        expect(mod.NetworkFirewallPolicy).toBeDefined();
    });

    it("should instantiate NetworkFirewallPolicy", async () => {
        const mod = await import("./index");
        const fw = new mod.NetworkFirewallPolicy("test-fw", {
            project: "prj-test",
            name: "test-fw-policy",
            network: "projects/prj-test/global/networks/vpc-01",
            rules: [{
                ruleName: "allow-iap-ssh",
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
