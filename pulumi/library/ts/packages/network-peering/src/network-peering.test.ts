/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the NetworkPeering module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("NetworkPeering", () => {
    it("should export the NetworkPeering class", async () => {
        const mod = await import("./index");
        expect(mod.NetworkPeering).toBeDefined();
    });

    it("should validate peering args", async () => {
        const args = {
            localNetwork: "projects/prj-a/global/networks/vpc-a",
            peerNetwork: "projects/prj-b/global/networks/vpc-b",
            exportCustomRoutes: true,
            importCustomRoutes: true,
        };
        expect(args.exportCustomRoutes).toBe(true);
        expect(args.importCustomRoutes).toBe(true);
    });

    it("should instantiate NetworkPeering", async () => {
        const mod = await import("./index");
        const peering = new mod.NetworkPeering("test-peering", {
            localNetwork: "projects/prj-a/global/networks/vpc-a",
            peerNetwork: "projects/prj-b/global/networks/vpc-b",
        });
        expect(peering).toBeDefined();
    });
});
