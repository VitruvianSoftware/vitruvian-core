/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the InstanceTemplate and ComputeInstance modules.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("InstanceTemplate", () => {
    it("should export the InstanceTemplate class", async () => {
        const mod = await import("./index");
        expect(mod.InstanceTemplate).toBeDefined();
    });

    it("should validate template args", async () => {
        const args = {
            projectId: "prj-test",
            region: "us-central1",
            machineType: "e2-medium",
            sourceImage: "debian-cloud/debian-11",
            network: "projects/prj-test/global/networks/vpc-test",
            subnetwork: "projects/prj-test/regions/us-central1/subnetworks/sb-test",
        };
        expect(args.machineType).toBe("e2-medium");
        expect(args.region).toBe("us-central1");
    });

    it("should instantiate InstanceTemplate", async () => {
        const mod = await import("./index");
        const tmpl = new mod.InstanceTemplate("test-template", {
            projectId: "prj-test",
            region: "us-central1",
            machineType: "f1-micro",
            sourceImage: "debian-cloud/debian-11",
            network: "vpc-test",
            subnetwork: "sb-test",
        });
        expect(tmpl).toBeDefined();
    });
});

describe("ComputeInstance", () => {
    it("should export the ComputeInstance class", async () => {
        const mod = await import("./index");
        expect(mod.ComputeInstance).toBeDefined();
    });

    it("should instantiate ComputeInstance", async () => {
        const mod = await import("./index");
        const instance = new mod.ComputeInstance("test-instance", {
            projectId: "prj-test",
            zone: "us-central1-a",
            instanceName: "test-vm",
            instanceTemplate: "projects/prj-test/global/instanceTemplates/tmpl-test",
            subnetwork: "projects/prj-test/regions/us-central1/subnetworks/sb-test",
        });
        expect(instance).toBeDefined();
    });
});
