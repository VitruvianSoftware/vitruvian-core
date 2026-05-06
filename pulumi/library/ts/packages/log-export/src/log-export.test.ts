/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the LogExport module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("LogExport", () => {
    it("should export the LogExport class", async () => {
        const mod = await import("./index");
        expect(mod.LogExport).toBeDefined();
    });

    it("should instantiate LogExport", async () => {
        const mod = await import("./index");
        const sink = new mod.LogExport("test-sink", {
            destinationUri: "storage.googleapis.com/my-bucket",
            logSinkName: "org-audit-logs",
            parentResourceId: "123456789",
            resourceType: "organization",
        });
        expect(sink).toBeDefined();
    });
});
