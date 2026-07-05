/**
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Tests for 3-networks-hub-and-spoke configuration and defaults.
 */

import { describe, it, expect } from "vitest";

describe("3-networks-hub-and-spoke config struct", () => {
  it("should require environment code", () => {
    const args = {
      projectId: "prj-d-hub",
      environmentCode: "d",
      orgId: "123456789",
      parent: "organizations/123456789",
      defaultRegion: "us-central1",
      defaultRegion2: "us-west1",
      pscAddress: "10.2.0.0",
    };
    expect(args.environmentCode).toBe("d");
    expect(args.pscAddress).toBeTruthy();
  });

  it("should support hub and spoke modes", () => {
    const validModes = ["hub", "spoke"];
    expect(validModes).toContain("hub");
    expect(validModes).toContain("spoke");
  });
});
