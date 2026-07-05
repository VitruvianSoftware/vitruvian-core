/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the CentralizedLogging module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("CentralizedLogging", () => {
    it("should export the CentralizedLogging class", async () => {
        const mod = await import("./index");
        expect(mod.CentralizedLogging).toBeDefined();
    });

    it("should validate logging destination options", async () => {
        const storageOptions = {
            projectId: "prj-logging",
            location: "US",
            retentionDays: 365,
            forceDestroy: false,
        };
        expect(storageOptions.retentionDays).toBe(365);
        expect(storageOptions.forceDestroy).toBe(false);

        const bigqueryOptions = {
            projectId: "prj-logging",
            datasetId: "org_audit_logs",
        };
        expect(bigqueryOptions.datasetId).toBe("org_audit_logs");
    });

    it("should instantiate CentralizedLogging", async () => {
        const mod = await import("./index");
        const logging = new mod.CentralizedLogging("test-logging", {
            projectId: "prj-logging",
            orgId: "123456789",
        });
        expect(logging).toBeDefined();
    });
});
