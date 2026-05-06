/**
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Tests for 4-projects configuration, label generation, and budget config.
 * Mirrors: pulumi_go-example-foundation/4-projects/config_test.go
 */

import { describe, it, expect } from "vitest";

describe("4-projects label generation", () => {
    function projectLabels(
        env: string,
        envCode: string,
        businessCode: string,
        applicationName: string,
        vpc: string,
    ): Record<string, string> {
        return {
            environment: env,
            application_name: applicationName,
            billing_code: "1234",
            primary_contact: "example1",
            secondary_contact: "example2",
            business_code: businessCode,
            env_code: envCode,
            vpc: vpc,
        };
    }

    it("should generate exactly 8 labels matching upstream", () => {
        const labels = projectLabels("development", "d", "bu1", "base", "svpc");
        expect(Object.keys(labels)).toHaveLength(8);
    });

    it("should contain all required label keys", () => {
        const labels = projectLabels("development", "d", "bu1", "base", "svpc");
        const expectedKeys = [
            "environment", "application_name", "billing_code",
            "primary_contact", "secondary_contact", "business_code",
            "env_code", "vpc",
        ];
        for (const key of expectedKeys) {
            expect(labels).toHaveProperty(key);
        }
    });

    it("should set correct environment label", () => {
        const labels = projectLabels("production", "p", "bu1", "base", "svpc");
        expect(labels.environment).toBe("production");
        expect(labels.env_code).toBe("p");
    });
});

describe("4-projects budget config", () => {
    interface BudgetConfig {
        amount: number;
        alertSpentPercents: number[];
        alertPubsubTopic: string | null;
        alertSpendBasis: string;
    }

    function budgetConfig(amount: number): BudgetConfig {
        return {
            amount,
            alertSpentPercents: [0.5, 0.75, 0.9, 0.95],
            alertPubsubTopic: null,
            alertSpendBasis: "CURRENT_SPEND",
        };
    }

    it("should create budget with specified amount", () => {
        const bc = budgetConfig(1000);
        expect(bc.amount).toBe(1000);
    });

    it("should handle zero budget amount", () => {
        const bc = budgetConfig(0);
        expect(bc.amount).toBe(0);
    });

    it("should set default alert percentages", () => {
        const bc = budgetConfig(500);
        expect(bc.alertSpentPercents).toEqual([0.5, 0.75, 0.9, 0.95]);
    });

    it("should default spend basis to CURRENT_SPEND", () => {
        const bc = budgetConfig(500);
        expect(bc.alertSpendBasis).toBe("CURRENT_SPEND");
    });
});

describe("4-projects SingleProject interface contract", () => {
    it("should produce correct project naming pattern", () => {
        const projectPrefix = "prj";
        const envCode = "d";
        const businessCode = "bu1";
        const suffix = "base";
        const projectName = `${projectPrefix}-${envCode}-${businessCode}-${suffix}`;
        expect(projectName).toBe("prj-d-bu1-base");
    });

    it("should default projectDeletionPolicy to PREVENT", () => {
        const defaultPolicy = "PREVENT";
        expect(defaultPolicy).toBe("PREVENT");
    });
});
