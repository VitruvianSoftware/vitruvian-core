// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Tier {
    Free,
    Pro,
    Team,
}

impl Tier {
    pub fn parse(raw: &str) -> Self {
        match raw.to_ascii_lowercase().as_str() {
            "pro" => Self::Pro,
            "team" => Self::Team,
            _ => Self::Free,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Free => "free",
            Self::Pro => "pro",
            Self::Team => "team",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TierLimits {
    pub max_workspaces: usize,
    pub max_tabs_per_workspace: usize,
    pub max_total_tabs: usize,
    pub max_backups: usize,
    pub backup_retention_days: usize,
    pub auto_backup_enabled: bool,
    pub max_devices: usize,
    pub realtime_sync_enabled: bool,
    pub max_shared_workspaces: usize,
    pub max_collaborators_per_workspace: usize,
    pub max_storage_bytes: u64,
    pub rate_limit_per_minute: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LimitValue {
    Number(u64),
    Bool(bool),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TierValidationResult {
    pub valid: bool,
    pub limit: LimitValue,
    pub current: usize,
    pub message: Option<String>,
}

pub const FREE_LIMITS: TierLimits = TierLimits {
    max_workspaces: 10,
    max_tabs_per_workspace: 100,
    max_total_tabs: 500,
    max_backups: 10,
    backup_retention_days: 7,
    auto_backup_enabled: true,
    max_devices: 2,
    realtime_sync_enabled: false,
    max_shared_workspaces: 0,
    max_collaborators_per_workspace: 0,
    max_storage_bytes: 10 * 1024 * 1024,
    rate_limit_per_minute: 60,
};

pub const PRO_LIMITS: TierLimits = TierLimits {
    max_workspaces: 100,
    max_tabs_per_workspace: 500,
    max_total_tabs: 5000,
    max_backups: 100,
    backup_retention_days: 90,
    auto_backup_enabled: true,
    max_devices: 10,
    realtime_sync_enabled: true,
    max_shared_workspaces: 10,
    max_collaborators_per_workspace: 5,
    max_storage_bytes: 100 * 1024 * 1024,
    rate_limit_per_minute: 300,
};

pub const TEAM_LIMITS: TierLimits = TierLimits {
    max_workspaces: 1000,
    max_tabs_per_workspace: 1000,
    max_total_tabs: 25000,
    max_backups: 500,
    backup_retention_days: 365,
    auto_backup_enabled: true,
    max_devices: 50,
    realtime_sync_enabled: true,
    max_shared_workspaces: 100,
    max_collaborators_per_workspace: 50,
    max_storage_bytes: 1024 * 1024 * 1024,
    rate_limit_per_minute: 1000,
};

pub fn get_tier_limits(tier: &str) -> TierLimits {
    match Tier::parse(tier) {
        Tier::Free => FREE_LIMITS,
        Tier::Pro => PRO_LIMITS,
        Tier::Team => TEAM_LIMITS,
    }
}

pub fn get_limit(tier: &str, feature: &str) -> LimitValue {
    let limits = get_tier_limits(tier);
    match feature {
        "maxWorkspaces" => LimitValue::Number(limits.max_workspaces as u64),
        "maxTabsPerWorkspace" => LimitValue::Number(limits.max_tabs_per_workspace as u64),
        "maxTotalTabs" => LimitValue::Number(limits.max_total_tabs as u64),
        "maxBackups" => LimitValue::Number(limits.max_backups as u64),
        "backupRetentionDays" => LimitValue::Number(limits.backup_retention_days as u64),
        "autoBackupEnabled" => LimitValue::Bool(limits.auto_backup_enabled),
        "maxDevices" => LimitValue::Number(limits.max_devices as u64),
        "realtimeSyncEnabled" => LimitValue::Bool(limits.realtime_sync_enabled),
        "maxSharedWorkspaces" => LimitValue::Number(limits.max_shared_workspaces as u64),
        "maxCollaboratorsPerWorkspace" => {
            LimitValue::Number(limits.max_collaborators_per_workspace as u64)
        }
        "maxStorageBytes" => LimitValue::Number(limits.max_storage_bytes),
        "rateLimitPerMinute" => LimitValue::Number(limits.rate_limit_per_minute as u64),
        _ => LimitValue::Bool(true),
    }
}

pub fn has_feature_access(tier: &str, feature: &str) -> bool {
    match get_limit(tier, feature) {
        LimitValue::Bool(b) => b,
        LimitValue::Number(_) => true,
    }
}

pub fn is_within_limit(tier: &str, limit_key: &str, current_count: usize) -> bool {
    match get_limit(tier, limit_key) {
        LimitValue::Number(limit) => (current_count as u64) < limit,
        LimitValue::Bool(_) => true,
    }
}

pub fn validate_tier_limit(
    tier: &str,
    limit_key: &str,
    current_count: usize,
) -> TierValidationResult {
    let limit = get_limit(tier, limit_key);
    if let LimitValue::Bool(_) = limit {
        return TierValidationResult {
            valid: true,
            limit,
            current: current_count,
            message: None,
        };
    }
    let valid = is_within_limit(tier, limit_key, current_count);
    let num = match limit {
        LimitValue::Number(n) => n,
        LimitValue::Bool(_) => 0,
    };
    TierValidationResult {
        valid,
        limit,
        current: current_count,
        message: if valid {
            None
        } else {
            Some(format!(
                "You have reached the {} limit ({}) for your {} tier. Upgrade to increase your limits.",
                limit_key, num, tier
            ))
        },
    }
}

pub fn get_tier_display_name(tier: &str) -> &'static str {
    match Tier::parse(tier) {
        Tier::Free => "Free",
        Tier::Pro => "Pro",
        Tier::Team => "Team",
    }
}

pub fn is_paid_tier(tier: &str) -> bool {
    matches!(Tier::parse(tier), Tier::Pro | Tier::Team)
}
