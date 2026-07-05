/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the CloudDns module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("CloudDns", () => {
    it("should export the CloudDns class", async () => {
        const mod = await import("./index");
        expect(mod.CloudDns).toBeDefined();
    });

    it("should instantiate CloudDns", async () => {
        const mod = await import("./index");
        const dns = new mod.CloudDns("test-dns", {
            projectId: "prj-dns-hub",
            name: "test-zone",
            domain: "example.com.",
            type: "private",
            networkSelfLink: "projects/prj-dns-hub/global/networks/vpc-dns",
        });
        expect(dns).toBeDefined();
    });
});
