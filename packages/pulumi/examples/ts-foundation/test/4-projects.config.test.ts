import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import * as pulumi from "@pulumi/pulumi";
import { setupPulumiMocks } from "./mocks";

describe("4-projects stack execution", () => {
  beforeEach(() => {
    // Setup Pulumi mocks and required config
    setupPulumiMocks();

    // Mock the required config variables for 4-projects
    process.env["PULUMI_CONFIG"] = JSON.stringify({
      "project:org_id": "123456789",
      "project:billing_account": "000000-000000-000000",
      "project:business_code": "bu1",
      "project:env": "development",
      "project:env_code": "d",
    });
  });

  afterEach(() => {
    delete process.env["PULUMI_CONFIG"];
    vi.resetModules();
  });

  it("should execute without errors", async () => {
    // Import the main index file which will run the Pulumi program
    const index =
      await import("../4-projects/business_unit_1/development/index");

    // Ensure that at least something was exported
    expect(index).toBeDefined();
  });
});
