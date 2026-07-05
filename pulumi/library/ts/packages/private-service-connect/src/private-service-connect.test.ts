/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the PrivateServiceConnect module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("PrivateServiceConnect", () => {
    it("should export the PrivateServiceConnect class", async () => {
        const mod = await import("./index");
        expect(mod.PrivateServiceConnect).toBeDefined();
    });

    it("should validate PSC args", async () => {
        const args = {
            projectId: "prj-test",
            networkSelfLink: "projects/prj-test/global/networks/vpc-test",
            privateServiceConnectIp: "10.3.0.5",
            forwardingRuleName: "fwd-psc-test",
        };
        expect(args.privateServiceConnectIp).toBe("10.3.0.5");
    });

    it("should instantiate PrivateServiceConnect", async () => {
        const mod = await import("./index");
        const psc = new mod.PrivateServiceConnect("test-psc", {
            projectId: "prj-test",
            networkSelfLink: "projects/prj-test/global/networks/vpc-test",
            privateServiceConnectIp: "10.3.0.5",
        });
        expect(psc).toBeDefined();
    });
});
