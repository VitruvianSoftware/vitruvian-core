/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the DnsHub module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("DnsHub", () => {
    it("should export the DnsHub class", async () => {
        const mod = await import("./index");
        expect(mod.DnsHub).toBeDefined();
    });

    it("should instantiate DnsHub", async () => {
        const mod = await import("./index");
        const dns = new mod.DnsHub("test-dns", {
            projectId: "prj-dns-hub",
            networkSelfLink: "projects/prj-dns-hub/global/networks/vpc-dns",
        });
        expect(dns).toBeDefined();
    });
});
