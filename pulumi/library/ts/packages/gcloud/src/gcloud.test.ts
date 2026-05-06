/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the Gcloud module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("Gcloud", () => {
    it("should export the Gcloud class", async () => {
        const mod = await import("./index");
        expect(mod.Gcloud).toBeDefined();
    });

    it("should instantiate Gcloud", async () => {
        const mod = await import("./index");
        const gcloud = new mod.Gcloud("test-gcloud", {
            commands: ["gcloud services enable compute.googleapis.com"],
        });
        expect(gcloud).toBeDefined();
    });
});
