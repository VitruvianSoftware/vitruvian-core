/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the CloudFunction module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("CloudFunction", () => {
    it("should export the CloudFunction class", async () => {
        const mod = await import("./index");
        expect(mod.CloudFunction).toBeDefined();
    });

    it("should instantiate CloudFunction", async () => {
        const mod = await import("./index");
        const fn = new mod.CloudFunction("test-fn", {
            projectId: "prj-test",
            region: "us-central1",
            name: "test-function",
            entryPoint: "handler",
            sourceBucket: "gs://my-bucket",
            sourceObject: "function.zip",
        });
        expect(fn).toBeDefined();
    });
});
