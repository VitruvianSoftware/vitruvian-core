/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the CloudRouter module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("CloudRouter", () => {
    it("should export the CloudRouter class", async () => {
        const mod = await import("./index");
        expect(mod.CloudRouter).toBeDefined();
    });

    it("should instantiate CloudRouter", async () => {
        const mod = await import("./index");
        const router = new mod.CloudRouter("test-router", {
            project: "prj-test",
            name: "router-01",
            network: "projects/prj-test/global/networks/vpc-01",
            region: "us-central1",
        });
        expect(router).toBeDefined();
    });
});
