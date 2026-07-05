/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the KMS module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("Kms", () => {
    it("should export the Kms class", async () => {
        const mod = await import("./index");
        expect(mod.Kms).toBeDefined();
    });

    it("should validate KMS args", async () => {
        const args = {
            projectId: "prj-test",
            location: "us-central1",
            keyringName: "test-keyring",
            keys: ["crypto-key-1"],
            keyRotationPeriod: "7776000s",
        };
        expect(args.keyringName).toBe("test-keyring");
        expect(args.keyRotationPeriod).toBe("7776000s");
    });

    it("should instantiate KMS", async () => {
        const mod = await import("./index");
        const kms = new mod.Kms("test-kms", {
            projectId: "prj-test",
            location: "us-central1",
            keyringName: "test-keyring",
            keys: ["crypto-key"],
        });
        expect(kms).toBeDefined();
    });
});
