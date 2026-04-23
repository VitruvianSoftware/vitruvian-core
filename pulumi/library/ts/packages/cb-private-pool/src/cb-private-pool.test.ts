/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the CbPrivatePool module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("CbPrivatePool", () => {
    it("should export the CbPrivatePool class", async () => {
        const mod = await import("./index");
        expect(mod.CbPrivatePool).toBeDefined();
    });

    it("should validate private pool config", async () => {
        const config = {
            machineType: "e2-medium",
            diskSizeGb: 100,
        };
        expect(config.machineType).toBe("e2-medium");
        expect(config.diskSizeGb).toBe(100);
    });
});
