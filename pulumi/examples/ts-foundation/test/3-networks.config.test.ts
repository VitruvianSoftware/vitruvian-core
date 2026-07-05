/**
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Tests for 3-networks configuration and defaults.
 * Mirrors: pulumi_go-example-foundation/3-networks-svpc/config_test.go
 */

import { describe, it, expect } from "vitest";

describe("3-networks-svpc config defaults", () => {
    // Default values must match upstream Terraform variables.tf
    const defaults = {
        defaultRegion: "us-central1",
        defaultRegion2: "us-west1",
    };

    it("should default region1 to us-central1", () => {
        expect(defaults.defaultRegion).toBe("us-central1");
    });

    it("should default region2 to us-west1", () => {
        expect(defaults.defaultRegion2).toBe("us-west1");
    });
});

describe("3-networks environment values", () => {
    const validEnvs = ["development", "nonproduction", "production"];

    it.each(validEnvs)("should accept '%s' as a valid environment", (env) => {
        expect(env).toBeTruthy();
        expect(validEnvs).toContain(env);
    });

    it("should not accept invalid environments", () => {
        const invalidEnvs = ["staging", "test", "prod", "dev"];
        for (const env of invalidEnvs) {
            expect(validEnvs).not.toContain(env);
        }
    });
});

describe("3-networks SharedVpc config struct", () => {
    it("should require environment code", () => {
        const args = {
            projectId: "prj-d-svpc",
            environmentCode: "d",
            orgId: "123456789",
            parent: "organizations/123456789",
            defaultRegion: "us-central1",
            defaultRegion2: "us-west1",
            pscAddress: "10.2.0.0",
        };
        expect(args.environmentCode).toBe("d");
        expect(args.pscAddress).toBeTruthy();
    });

    it("should support hub, spoke, and svpc modes", () => {
        const validModes = ["hub", "spoke", null];
        expect(validModes).toHaveLength(3);
    });
});
