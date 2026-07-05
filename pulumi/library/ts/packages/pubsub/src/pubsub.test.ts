/**
 * Copyright 2026 Vitruvian Software
 *
 * Unit tests for the PubSub module.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { setupPulumiMocks } from "../../../test/mocks";

beforeAll(() => {
    setupPulumiMocks();
});

describe("PubSub", () => {
    it("should export the PubSub class", async () => {
        const mod = await import("./index");
        expect(mod.PubSub).toBeDefined();
    });

    it("should instantiate PubSub", async () => {
        const mod = await import("./index");
        const topic = new mod.PubSub("test-topic", {
            projectId: "prj-test",
            topicName: "my-topic",
        });
        expect(topic).toBeDefined();
    });
});
