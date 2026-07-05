/**
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Tests for 0-bootstrap config defaults.
 * Mirrors: pulumi_go-example-foundation/0-bootstrap/config_test.go
 */

import { describe, it, expect, vi } from "vitest";

// Mock Pulumi SDK before importing config
vi.mock("@pulumi/pulumi", () => {
    class MockConfig {
        private values: Record<string, string>;
        constructor(namespace?: string) {
            this.values = {};
        }
        get(key: string): string | undefined { return this.values[key]; }
        require(key: string): string {
            const v = this.values[key];
            if (v === undefined) throw new Error(`missing required config: ${key}`);
            return v;
        }
        getBoolean(key: string): boolean | undefined { return undefined; }
        getObject<T>(key: string): T | undefined { return undefined; }
        set(key: string, value: string) { this.values[key] = value; }
    }
    return {
        Config: MockConfig,
        Output: { create: (v: any) => v },
        output: (v: any) => v,
        interpolate: (strings: TemplateStringsArray, ...values: any[]) =>
            strings.reduce((acc, s, i) => acc + s + (values[i] ?? ""), ""),
    };
});

import { loadConfig } from "../0-bootstrap/config";
import * as pulumi from "@pulumi/pulumi";

describe("0-bootstrap config defaults", () => {
    function configWithRequired(): pulumi.Config {
        const cfg = new pulumi.Config();
        (cfg as any).values = {
            org_id: "123456789",
            billing_account: "AAAAAA-BBBBBB-CCCCCC",
            group_org_admins: "admins@example.com",
            group_billing_admins: "billing@example.com",
            billing_data_users: "billing-data@example.com",
            audit_data_users: "audit@example.com",
        };
        return cfg;
    }

    it("should apply correct project_prefix default", () => {
        const cfg = loadConfig(configWithRequired());
        expect(cfg.projectPrefix).toBe("prj");
    });

    it("should apply correct folder_prefix default", () => {
        const cfg = loadConfig(configWithRequired());
        expect(cfg.folderPrefix).toBe("fldr");
    });

    it("should apply correct bucket_prefix default", () => {
        const cfg = loadConfig(configWithRequired());
        expect(cfg.bucketPrefix).toBe("bkt");
    });

    it("should apply correct project_deletion_policy default", () => {
        const cfg = loadConfig(configWithRequired());
        expect(cfg.projectDeletionPolicy).toBe("PREVENT");
    });

    it("should apply correct default_region default", () => {
        const cfg = loadConfig(configWithRequired());
        expect(cfg.defaultRegion).toBe("us-central1");
    });

    it("should apply correct default_region_2 default", () => {
        const cfg = loadConfig(configWithRequired());
        expect(cfg.defaultRegion2).toBe("us-west1");
    });

    it("should apply correct default_region_gcs default", () => {
        const cfg = loadConfig(configWithRequired());
        expect(cfg.defaultRegionGcs).toBe("US");
    });

    it("should apply correct default_region_kms default", () => {
        const cfg = loadConfig(configWithRequired());
        expect(cfg.defaultRegionKms).toBe("us");
    });

    it("should apply correct kms_key_protection_level default", () => {
        const cfg = loadConfig(configWithRequired());
        expect(cfg.kmsKeyProtectionLevel).toBe("SOFTWARE");
    });
});

describe("0-bootstrap parent resolution", () => {
    function configWithValues(overrides: Record<string, string>): pulumi.Config {
        const cfg = new pulumi.Config();
        (cfg as any).values = {
            org_id: "123456789",
            billing_account: "AAAAAA-BBBBBB-CCCCCC",
            group_org_admins: "admins@example.com",
            group_billing_admins: "billing@example.com",
            billing_data_users: "billing-data@example.com",
            audit_data_users: "audit@example.com",
            ...overrides,
        };
        return cfg;
    }

    it("should set parent to org when no parent_folder is specified", () => {
        const cfg = loadConfig(configWithValues({}));
        expect(cfg.parent).toBe("organizations/123456789");
        expect(cfg.parentType).toBe("organization");
        expect(cfg.parentId).toBe("123456789");
    });

    it("should set parent to folder when parent_folder is specified", () => {
        const cfg = loadConfig(configWithValues({ parent_folder: "987654321" }));
        expect(cfg.parent).toBe("folders/987654321");
        expect(cfg.parentType).toBe("folder");
        expect(cfg.parentId).toBe("987654321");
    });
});

describe("0-bootstrap groups config", () => {
    it("should populate required groups from config", () => {
        const cfg = new pulumi.Config();
        (cfg as any).values = {
            org_id: "123456789",
            billing_account: "AAAAAA-BBBBBB-CCCCCC",
            group_org_admins: "admins@test.com",
            group_billing_admins: "billing@test.com",
            billing_data_users: "billing-data@test.com",
            audit_data_users: "audit@test.com",
        };

        const result = loadConfig(cfg);
        expect(result.groups.requiredGroups.groupOrgAdmins).toBe("admins@test.com");
        expect(result.groups.requiredGroups.groupBillingAdmins).toBe("billing@test.com");
        expect(result.groups.requiredGroups.billingDataUsers).toBe("billing-data@test.com");
        expect(result.groups.requiredGroups.auditDataUsers).toBe("audit@test.com");
    });

    it("should default initialGroupConfig to WITH_INITIAL_OWNER", () => {
        const cfg = new pulumi.Config();
        (cfg as any).values = {
            org_id: "123456789",
            billing_account: "AAAAAA-BBBBBB-CCCCCC",
            group_org_admins: "admins@test.com",
            group_billing_admins: "billing@test.com",
            billing_data_users: "billing-data@test.com",
            audit_data_users: "audit@test.com",
        };

        const result = loadConfig(cfg);
        expect(result.initialGroupConfig).toBe("WITH_INITIAL_OWNER");
    });
});
