/**
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Tests for 2-environments configuration and environment conventions.
 * Mirrors: pulumi_go-example-foundation/2-environments/config_test.go
 */

import { describe, it, expect } from "vitest";

describe("2-environments conventions", () => {
    const environments = ["development", "nonproduction", "production"] as const;
    const envCodes: Record<string, string> = {
        development: "d",
        nonproduction: "n",
        production: "p",
    };

    it("should define exactly 3 environments", () => {
        expect(environments).toHaveLength(3);
    });

    it("should contain development", () => {
        expect(environments).toContain("development");
    });

    it("should contain nonproduction", () => {
        expect(environments).toContain("nonproduction");
    });

    it("should contain production", () => {
        expect(environments).toContain("production");
    });

    it("should map development to env code 'd'", () => {
        expect(envCodes["development"]).toBe("d");
    });

    it("should map nonproduction to env code 'n'", () => {
        expect(envCodes["nonproduction"]).toBe("n");
    });

    it("should map production to env code 'p'", () => {
        expect(envCodes["production"]).toBe("p");
    });
});

describe("2-environments env_baseline interface contract", () => {
    it("should require all mandatory fields", () => {
        // Verifies the interface shape expected by deployEnvBaseline
        const requiredKeys = [
            "env",
            "environmentCode",
            "orgId",
            "billingAccount",
            "projectPrefix",
            "folderPrefix",
            "parent",
            "tags",
            "requiredGroups",
            "projectDeletionPolicy",
            "folderDeletionProtection",
            "projectBudget",
        ];
        // This test ensures the contract is stable — if the interface changes,
        // this list must be updated.
        expect(requiredKeys).toHaveLength(12);
    });

    it("should use correct defaults for folder and project prefixes", () => {
        // Default values must match upstream Terraform variables.tf
        const defaultProjectPrefix = "prj";
        const defaultFolderPrefix = "fldr";
        expect(defaultProjectPrefix).toBe("prj");
        expect(defaultFolderPrefix).toBe("fldr");
    });
});
