/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the CloudStorage module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("CloudStorage", () => {
    it("should export the CloudStorage class", async () => {
        const mod = await import("./index");
        expect(mod.CloudStorage).toBeDefined();
    });

    it("should instantiate CloudStorage", async () => {
        const mod = await import("./index");
        const bucket = new mod.CloudStorage("test-bucket", {
            name: "my-test-bucket",
            projectId: "prj-test",
            location: "US",
        });
        expect(bucket).toBeDefined();
    });
});
