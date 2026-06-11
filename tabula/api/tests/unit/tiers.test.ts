/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/**
 * Unit tests for tiers configuration
 */
import {
  getTierLimits,
  hasFeatureAccess,
  getLimit,
  isWithinLimit,
  validateTierLimit,
  getTierDisplayName,
  isPaidTier,
  TIER_CONFIGS,
} from "../../src/lib/tiers";

describe("Tier Configuration", () => {
  describe("TIER_CONFIGS", () => {
    it("should have configurations for all tiers", () => {
      expect(TIER_CONFIGS).toHaveProperty("free");
      expect(TIER_CONFIGS).toHaveProperty("pro");
      expect(TIER_CONFIGS).toHaveProperty("team");
    });

    it("should have increasing limits from free to team", () => {
      expect(TIER_CONFIGS.pro.maxWorkspaces).toBeGreaterThan(
        TIER_CONFIGS.free.maxWorkspaces,
      );
      expect(TIER_CONFIGS.team.maxWorkspaces).toBeGreaterThan(
        TIER_CONFIGS.pro.maxWorkspaces,
      );
    });
  });

  describe("getTierLimits", () => {
    it("should return limits for valid tier", () => {
      const limits = getTierLimits("pro");
      expect(limits.maxWorkspaces).toBe(100);
      expect(limits.backupRetentionDays).toBe(90);
    });

    it("should default to free tier for unknown tier", () => {
      const limits = getTierLimits("unknown");
      expect(limits.maxWorkspaces).toBe(10);
    });

    it("should handle case insensitivity", () => {
      const limits = getTierLimits("PRO");
      expect(limits.maxWorkspaces).toBe(100);
    });
  });

  describe("hasFeatureAccess", () => {
    it("should return true for features that are enabled", () => {
      expect(hasFeatureAccess("pro", "realtimeSyncEnabled")).toBe(true);
    });

    it("should return false for features that are disabled", () => {
      expect(hasFeatureAccess("free", "realtimeSyncEnabled")).toBe(false);
    });
  });

  describe("getLimit", () => {
    it("should return numeric limit", () => {
      expect(getLimit("free", "maxWorkspaces")).toBe(10);
      expect(getLimit("pro", "maxBackups")).toBe(100);
    });

    it("should return boolean for feature flags", () => {
      expect(getLimit("free", "autoBackupEnabled")).toBe(true);
      expect(getLimit("free", "realtimeSyncEnabled")).toBe(false);
    });
  });

  describe("isWithinLimit", () => {
    it("should return true when under limit", () => {
      expect(isWithinLimit("free", "maxWorkspaces", 5)).toBe(true);
    });

    it("should return false when at or over limit", () => {
      expect(isWithinLimit("free", "maxWorkspaces", 10)).toBe(false);
      expect(isWithinLimit("free", "maxWorkspaces", 15)).toBe(false);
    });
  });

  describe("validateTierLimit", () => {
    it("should return valid when under limit", () => {
      const result = validateTierLimit("free", "maxWorkspaces", 5);
      expect(result.valid).toBe(true);
      expect(result.current).toBe(5);
    });

    it("should return invalid with message when at limit", () => {
      const result = validateTierLimit("free", "maxWorkspaces", 10);
      expect(result.valid).toBe(false);
      expect(result.message).toContain("limit");
    });

    it("should return valid for boolean feature limits", () => {
      const result = validateTierLimit("free", "autoBackupEnabled", 0);
      expect(result.valid).toBe(true);
    });
  });

  describe("hasFeatureAccess - additional cases", () => {
    it("should return true for numeric limits (non-boolean features)", () => {
      // maxWorkspaces is a number, not a boolean, so hasFeatureAccess should return true
      expect(hasFeatureAccess("free", "maxWorkspaces")).toBe(true);
    });
  });

  describe("isWithinLimit - additional cases", () => {
    it("should return true for boolean feature (not a number)", () => {
      // autoBackupEnabled is a boolean, not a number
      expect(isWithinLimit("free", "autoBackupEnabled", 5)).toBe(true);
    });
  });

  describe("getTierDisplayName", () => {
    it("should return proper display names", () => {
      expect(getTierDisplayName("free")).toBe("Free");
      expect(getTierDisplayName("pro")).toBe("Pro");
      expect(getTierDisplayName("team")).toBe("Team");
    });

    it("should default to Free for unknown tiers", () => {
      expect(getTierDisplayName("unknown")).toBe("Free");
    });
  });

  describe("isPaidTier", () => {
    it("should return false for free tier", () => {
      expect(isPaidTier("free")).toBe(false);
    });

    it("should return true for pro tier", () => {
      expect(isPaidTier("pro")).toBe(true);
    });

    it("should return true for team tier", () => {
      expect(isPaidTier("team")).toBe(true);
    });
  });
});
