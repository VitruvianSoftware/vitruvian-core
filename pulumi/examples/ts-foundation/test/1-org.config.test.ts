/**
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Tests for 1-org config defaults.
 */

import { describe, it, expect, vi } from "vitest";

vi.mock("@pulumi/pulumi", () => {
    class MockConfig {
        private values: Record<string, string>;
        constructor() { this.values = {}; }
        get(key: string): string | undefined { return this.values[key]; }
        require(key: string): string {
            const v = this.values[key];
            if (v === undefined) throw new Error(`missing required config: ${key}`);
            return v;
        }
        getBoolean(key: string): boolean | undefined { return this.values[key] ? this.values[key] === "true" : undefined; }
        getObject<T>(key: string): T | undefined { return this.values[key] ? JSON.parse(this.values[key]) : undefined; }
        set(key: string, value: string) { this.values[key] = value; }
    }
    return {
        Config: MockConfig,
    };
});

import { loadOrgConfig } from "../1-org/config";
import * as pulumi from "@pulumi/pulumi";

describe("1-org config defaults", () => {
    function configWithRequired(): pulumi.Config {
        const cfg = new pulumi.Config();
        (cfg as any).values = {
            org_id: "123456789",
            billing_account: "AAAAAA-BBBBBB-CCCCCC",
            remote_state_bucket: "bkt-b-tfstate-1234",
        };
        return cfg;
    }

    it("should apply correct defaults", () => {
        const cfg = loadOrgConfig(configWithRequired());
        expect(cfg.orgId).toBe("123456789");
        expect(cfg.billingAccount).toBe("AAAAAA-BBBBBB-CCCCCC");
        expect(cfg.enableBillingAccountSink).toBe(false);
        expect(cfg.projectPrefix).toBe("prj");
        expect(cfg.folderPrefix).toBe("fldr");
        expect(cfg.defaultRegion).toBe("us-central1");
        expect(cfg.parent).toBe("organizations/123456789");
        expect(cfg.parentType).toBe("organization");
        expect(cfg.parentId).toBe("123456789");
        expect(cfg.enableHubAndSpoke).toBe(false);
        expect(cfg.enableHubAndSpokeTransitivity).toBe(false);
        expect(cfg.domainsToAllow).toEqual([]);
        expect(cfg.essentialContactsDomainsToAllow).toEqual([]);
        expect(cfg.essentialContactsLanguage).toBe("en");
        expect(cfg.sccNotificationName).toBe("scc-notify");
        expect(cfg.sccNotificationFilter).toBe("state = \"ACTIVE\"");
        expect(cfg.createUniqueTagKey).toBe(false);
        expect(cfg.enableCaiMonitoring).toBe(false);
        expect(cfg.enableSccResources).toBe(false);
        expect(cfg.enableKmsKeyUsageTracking).toBe(true);
        expect(cfg.createAccessContextManagerAccessPolicy).toBe(true);
        expect(cfg.enforceAllowedWorkerPools).toBe(false);
        expect(cfg.caiMonitoringKmsForceDestroy).toBe(false);
        expect(cfg.projectDeletionPolicy).toBe("PREVENT");
        expect(cfg.folderDeletionProtection).toBe(true);
        expect(cfg.logExportStorageForceDestroy).toBe(false);
        expect(cfg.logExportStorageVersioning).toBe(false);
    });
});
