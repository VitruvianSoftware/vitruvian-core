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
 * Account Tier Configuration
 *
 * Centralized tier configuration for feature limits and capabilities.
 * Reusable across backup, workspace, sync, and future features.
 */

export type TierType = "free" | "pro" | "team";

export interface TierLimits {
  // Workspace limits
  maxWorkspaces: number;
  maxTabsPerWorkspace: number;

  // Backup limits
  maxBackups: number;
  backupRetentionDays: number;
  autoBackupEnabled: boolean;
  autoBackupIntervalHours: number;

  // Sync limits
  realtimeSyncEnabled: boolean;
  syncIntervalSeconds: number;
  maxDevices: number;

  // Resource limits
  maxResourcesPerWorkspace: number;
  maxNotesPerWorkspace: number;
  maxTasksPerWorkspace: number;

  // Storage limits (in bytes)
  maxStorageBytes: number;
}

/**
 * Tier configurations
 * All limits are defined here for easy modification
 */
export const TIER_CONFIGS: Record<TierType, TierLimits> = {
  free: {
    maxWorkspaces: 10,
    maxTabsPerWorkspace: 100,
    maxBackups: 10,
    backupRetentionDays: 30,
    autoBackupEnabled: true,
    autoBackupIntervalHours: 6,
    realtimeSyncEnabled: false,
    syncIntervalSeconds: 300, // 5 minutes
    maxDevices: 2,
    maxResourcesPerWorkspace: 50,
    maxNotesPerWorkspace: 20,
    maxTasksPerWorkspace: 50,
    maxStorageBytes: 50 * 1024 * 1024, // 50 MB
  },
  pro: {
    maxWorkspaces: 100,
    maxTabsPerWorkspace: 500,
    maxBackups: 100,
    backupRetentionDays: 90,
    autoBackupEnabled: true,
    autoBackupIntervalHours: 1,
    realtimeSyncEnabled: true,
    syncIntervalSeconds: 30, // 30 seconds
    maxDevices: 10,
    maxResourcesPerWorkspace: 500,
    maxNotesPerWorkspace: 200,
    maxTasksPerWorkspace: 500,
    maxStorageBytes: 1024 * 1024 * 1024, // 1 GB
  },
  team: {
    maxWorkspaces: 1000,
    maxTabsPerWorkspace: 1000,
    maxBackups: 500,
    backupRetentionDays: 365,
    autoBackupEnabled: true,
    autoBackupIntervalHours: 1,
    realtimeSyncEnabled: true,
    syncIntervalSeconds: 10, // 10 seconds
    maxDevices: 100,
    maxResourcesPerWorkspace: 1000,
    maxNotesPerWorkspace: 1000,
    maxTasksPerWorkspace: 1000,
    maxStorageBytes: 10 * 1024 * 1024 * 1024, // 10 GB
  },
};

/**
 * Get limits for a specific tier
 */
export function getTierLimits(tier: string): TierLimits {
  const normalized = tier.toLowerCase() as TierType;
  return TIER_CONFIGS[normalized] || TIER_CONFIGS.free;
}

/**
 * Check if a tier has access to a specific feature
 */
export function hasFeatureAccess(
  tier: string,
  feature: keyof TierLimits,
): boolean {
  const limits = getTierLimits(tier);
  const value = limits[feature];
  return typeof value === "boolean" ? value : true;
}

/**
 * Get the limit value for a specific limit key
 */
export function getLimit(
  tier: string,
  limitKey: keyof TierLimits,
): number | boolean {
  const limits = getTierLimits(tier);
  return limits[limitKey];
}

/**
 * Check if a count exceeds the tier limit
 */
export function isWithinLimit(
  tier: string,
  limitKey: keyof TierLimits,
  currentCount: number,
): boolean {
  const limit = getLimit(tier, limitKey);
  if (typeof limit !== "number") return true;
  return currentCount < limit;
}

/**
 * Validation result type
 */
export interface TierValidationResult {
  valid: boolean;
  message?: string;
  limit?: number;
  current?: number;
}

/**
 * Validate an operation against tier limits
 */
export function validateTierLimit(
  tier: string,
  limitKey: keyof TierLimits,
  currentCount: number,
): TierValidationResult {
  const limits = getTierLimits(tier);
  const limit = limits[limitKey];

  if (typeof limit !== "number") {
    return { valid: true };
  }

  if (currentCount >= limit) {
    return {
      valid: false,
      message: `${tier} tier limit of ${limit} reached for ${String(limitKey)}`,
      limit,
      current: currentCount,
    };
  }

  return { valid: true, limit, current: currentCount };
}

/**
 * Get tier display name
 */
export function getTierDisplayName(tier: string): string {
  const names: Record<TierType, string> = {
    free: "Free",
    pro: "Pro",
    team: "Team",
  };
  return names[tier.toLowerCase() as TierType] || "Free";
}

/**
 * Check if tier is a paid tier
 */
export function isPaidTier(tier: string): boolean {
  const normalized = tier.toLowerCase();
  return normalized === "pro" || normalized === "team";
}
