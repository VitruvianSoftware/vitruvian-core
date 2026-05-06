/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the ComputeInstance module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("ComputeInstance", () => {
    it("should export the ComputeInstance class", async () => {
        const mod = await import("./index");
        expect(mod.ComputeInstance).toBeDefined();
    });

    it("should instantiate ComputeInstance", async () => {
        const mod = await import("./index");
        const instance = new mod.ComputeInstance("test-instance", {
            project: "prj-test",
            zone: "us-central1-a",
            hostname: "vm-01",
            instanceTemplate: "projects/prj-test/global/instanceTemplates/tpl-01",
        });
        expect(instance).toBeDefined();
    });
});
