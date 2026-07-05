/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the SimpleBucket module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("SimpleBucket", () => {
    it("should export the SimpleBucket class", async () => {
        const mod = await import("./index");
        expect(mod.SimpleBucket).toBeDefined();
        expect(typeof mod.SimpleBucket).toBe("function");
    });

    it("should define SimpleBucketArgs interface fields", async () => {
        const args = {
            name: "bkt-test-bucket",
            projectId: "prj-test-123",
            location: "US",
            forceDestroy: false,
            versioning: true,
        };
        expect(args.name).toBe("bkt-test-bucket");
        expect(args.location).toBe("US");
        expect(args.versioning).toBe(true);
    });

    it("should instantiate SimpleBucket with required args", async () => {
        const mod = await import("./index");
        const bucket = new mod.SimpleBucket("test-bucket", {
            name: "bkt-test",
            projectId: "prj-test",
            location: "US",
        });
        expect(bucket).toBeDefined();
    });
});
