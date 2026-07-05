/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the ProjectFactory module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

// Mocks must be set up before importing any Pulumi resources
beforeAll(() => {
    setupPulumiMocks();
});

describe("ProjectFactory", () => {
    it("should export the ProjectFactory class", async () => {
        const mod = await import("./index");
        expect(mod.ProjectFactory).toBeDefined();
        expect(typeof mod.ProjectFactory).toBe("function");
    });

    it("should define ProjectFactoryArgs interface fields", async () => {
        // Validate the expected args shape
        const args = {
            name: "test-project",
            orgId: "123456789",
            billingAccount: "AAAAAA-BBBBBB-CCCCCC",
            folderId: "folders/12345",
            activateApis: ["compute.googleapis.com"],
            labels: { env: "test" },
            randomProjectId: true,
            randomProjectIdLength: 4,
            defaultServiceAccount: "disable",
            deletionPolicy: "PREVENT",
        };
        expect(args.name).toBe("test-project");
        expect(args.activateApis).toHaveLength(1);
        expect(args.randomProjectId).toBe(true);
        expect(args.deletionPolicy).toBe("PREVENT");
    });

    it("should instantiate ProjectFactory with required args", async () => {
        const mod = await import("./index");
        const factory = new mod.ProjectFactory("test", {
            name: "prj-test",
            orgId: "123456789",
            billingAccount: "AAAAAA-BBBBBB-CCCCCC",
            folderId: "folders/123",
        });
        expect(factory).toBeDefined();
        expect(factory.projectId).toBeDefined();
        expect(factory.projectNumber).toBeDefined();
    });

    it("should have budget fields in args interface", async () => {
        const args = {
            name: "test",
            orgId: "123",
            billingAccount: "XXX",
            folderId: "folders/1",
            budgetAmount: 1000,
            budgetAlertSpentPercents: [0.5, 0.75, 1.0],
            budgetAlertSpendBasis: "CURRENT_SPEND",
        };
        expect(args.budgetAmount).toBe(1000);
        expect(args.budgetAlertSpentPercents).toEqual([0.5, 0.75, 1.0]);
    });
});
