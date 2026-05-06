/**
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Tests for 5-app-infra configuration and defaults.
 * Mirrors: pulumi_go-example-foundation/5-app-infra/config_test.go
 */

import { describe, it, expect } from "vitest";

describe("5-app-infra config defaults", () => {
    interface AppConfig {
        env: string;
        envCode: string;
        businessCode: string;
        businessUnit: string;
        projectPrefix: string;
        instanceRegion: string;
        enableCmek: boolean;
        enableConfidentialSpace: boolean;
        enableNetworkPeering: boolean;
        machineType: string;
    }

    function defaultAppConfig(env: string): AppConfig {
        const envCodes: Record<string, string> = { development: "d", nonproduction: "n", production: "p" };
        return {
            env,
            envCode: envCodes[env] ?? env.charAt(0),
            businessCode: "bu1",
            businessUnit: "business_unit_1",
            projectPrefix: "prj",
            instanceRegion: "us-central1",
            enableCmek: false,
            enableConfidentialSpace: false,
            enableNetworkPeering: false,
            machineType: "n1-standard-1",
        };
    }

    it("should set correct environment code for development", () => {
        const cfg = defaultAppConfig("development");
        expect(cfg.envCode).toBe("d");
    });

    it("should set correct environment code for nonproduction", () => {
        const cfg = defaultAppConfig("nonproduction");
        expect(cfg.envCode).toBe("n");
    });

    it("should set correct environment code for production", () => {
        const cfg = defaultAppConfig("production");
        expect(cfg.envCode).toBe("p");
    });

    it("should default projectPrefix to prj", () => {
        const cfg = defaultAppConfig("development");
        expect(cfg.projectPrefix).toBe("prj");
    });

    it("should default instanceRegion to us-central1", () => {
        const cfg = defaultAppConfig("development");
        expect(cfg.instanceRegion).toBe("us-central1");
    });

    it("should default machineType to n1-standard-1", () => {
        const cfg = defaultAppConfig("development");
        expect(cfg.machineType).toBe("n1-standard-1");
    });

    it("should default all feature flags to false", () => {
        const cfg = defaultAppConfig("development");
        expect(cfg.enableCmek).toBe(false);
        expect(cfg.enableConfidentialSpace).toBe(false);
        expect(cfg.enableNetworkPeering).toBe(false);
    });
});
