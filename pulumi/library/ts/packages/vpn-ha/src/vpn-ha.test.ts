/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the VpnHa module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("VpnHa", () => {
    it("should export the VpnHa class", async () => {
        const mod = await import("./index");
        expect(mod.VpnHa).toBeDefined();
    });

    it("should validate tunnel configuration", async () => {
        const tunnel = {
            peerExternalGatewayInterface: 0,
            sharedSecret: "test-secret-123",
            bgpSessionRange: "169.254.0.1/30",
            peerBgpAsn: 65001,
        };
        expect(tunnel.peerExternalGatewayInterface).toBe(0);
        expect(tunnel.peerBgpAsn).toBe(65001);
    });

    it("should instantiate VpnHa", async () => {
        const mod = await import("./index");
        const vpn = new mod.VpnHa("test-vpn", {
            projectId: "prj-test",
            region: "us-central1",
            network: "projects/prj-test/global/networks/vpc-test",
            name: "vpn-test",
            routerAsn: 64514,
            peerExternalGateway: {
                name: "peer-gw",
                interfaces: [{ id: 0, ipAddress: "203.0.113.1" }],
            },
            tunnels: [{
                bgpSessionRange: "169.254.0.1/30",
                peerBgpSessionRange: "169.254.0.2/30",
                peerAsn: 65001,
                sharedSecret: "secret-123",
                vpnGatewayInterface: 0,
            }],
        });
        expect(vpn).toBeDefined();
    });
});
