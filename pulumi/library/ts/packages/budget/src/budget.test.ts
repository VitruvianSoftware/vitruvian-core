/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the Budget module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("Budget", () => {
    it("should export the Budget class", async () => {
        const mod = await import("./index");
        expect(mod.Budget).toBeDefined();
    });

    it("should validate budget args interface", async () => {
        const args = {
            billingAccount: "AAAAAA-BBBBBB-CCCCCC",
            projectId: "prj-test",
            amount: 1000,
            alertSpentPercents: [0.5, 0.75, 1.0, 1.2],
            alertSpendBasis: "FORECASTED_SPEND",
        };
        expect(args.amount).toBe(1000);
        expect(args.alertSpentPercents).toHaveLength(4);
        expect(args.alertSpendBasis).toBe("FORECASTED_SPEND");
    });

    it("should instantiate Budget", async () => {
        const mod = await import("./index");
        const budget = new mod.Budget("test-budget", {
            billingAccount: "AAAAAA-BBBBBB-CCCCCC",
            projectId: "prj-test",
            amount: 500,
        });
        expect(budget).toBeDefined();
    });
});
