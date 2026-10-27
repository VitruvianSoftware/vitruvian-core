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

use std::collections::HashSet;
use std::fmt;
use std::thread;
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequiredColumn {
    pub table: &'static str,
    pub column: &'static str,
    pub migration: &'static str,
}

pub const REQUIRED_COLUMNS: &[RequiredColumn] = &[
    RequiredColumn {
        table: "users",
        column: "id",
        migration: "20251207000000_init",
    },
    RequiredColumn {
        table: "workspaces",
        column: "id",
        migration: "20251207000000_init",
    },
    RequiredColumn {
        table: "workspaces",
        column: "version",
        migration: "20260610000000_add_sync_versioning",
    },
    RequiredColumn {
        table: "space_groups",
        column: "version",
        migration: "20260610000000_add_sync_versioning",
    },
    RequiredColumn {
        table: "backups",
        column: "name",
        migration: "20260610000001_add_backup_name_and_type",
    },
    RequiredColumn {
        table: "backups",
        column: "type",
        migration: "20260610000001_add_backup_name_and_type",
    },
    RequiredColumn {
        table: "workspaces",
        column: "active_device_id",
        migration: "20260614000000_add_active_device_lease",
    },
    RequiredColumn {
        table: "workspaces",
        column: "active_device_seen_at",
        migration: "20260614000000_add_active_device_lease",
    },
    RequiredColumn {
        table: "space_collaborators",
        column: "id",
        migration: "20260615000000_add_sharing_acl",
    },
    RequiredColumn {
        table: "share_links",
        column: "id",
        migration: "20260615000000_add_sharing_acl",
    },
    RequiredColumn {
        table: "share_links",
        column: "relay_id_hash",
        migration: "20260615000001_add_share_link_relay_id",
    },
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MigrationDriftError {
    pub missing: Vec<RequiredColumn>,
    pub message: String,
}

impl MigrationDriftError {
    pub fn new(missing: Vec<RequiredColumn>) -> Self {
        let mut migrations: Vec<&str> = Vec::new();
        for c in &missing {
            if !migrations.contains(&c.migration) {
                migrations.push(c.migration);
            }
        }
        let cols: Vec<String> = missing
            .iter()
            .map(|c| format!("{}.{}", c.table, c.column))
            .collect();
        let message = format!(
            "Database schema is behind the application code -- missing column(s): {} \
             (from migration(s): {}). Run `prisma migrate deploy` against DATABASE_URL \
             before starting the server.",
            cols.join(", "),
            migrations.join(", ")
        );
        Self { missing, message }
    }
}

impl fmt::Display for MigrationDriftError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

#[derive(Debug, Clone, Copy)]
pub struct ProbeOptions {
    pub attempts: usize,
    pub backoff_ms: u64,
}

impl Default for ProbeOptions {
    fn default() -> Self {
        Self {
            attempts: 5,
            backoff_ms: 500,
        }
    }
}

pub trait SchemaColumnProbe {
    fn query_present_columns(&self) -> Result<Vec<(String, String)>, String>;
}

pub trait MigrationLogger {
    fn info(&self, msg: &str);
    fn warn(&self, msg: &str);
    fn error(&self, msg: &str);
    fn fatal(&self, missing: &[RequiredColumn], msg: &str);
}

pub fn find_missing_required_columns(
    probe: &dyn SchemaColumnProbe,
    opts: ProbeOptions,
) -> Result<Vec<RequiredColumn>, String> {
    let attempts = opts.attempts.max(1);
    let mut last_err = String::new();
    let mut rows: Option<Vec<(String, String)>> = None;

    for attempt in 1..=attempts {
        match probe.query_present_columns() {
            Ok(r) => {
                rows = Some(r);
                break;
            }
            Err(e) => {
                last_err = e;
                if attempt < attempts && opts.backoff_ms > 0 {
                    thread::sleep(Duration::from_millis(opts.backoff_ms * (attempt as u64)));
                }
            }
        }
    }

    let Some(present_rows) = rows else {
        return Err(last_err);
    };

    let present: HashSet<String> = present_rows
        .into_iter()
        .map(|(t, c)| format!("{t}.{c}"))
        .collect();

    Ok(REQUIRED_COLUMNS
        .iter()
        .filter(|c| !present.contains(&format!("{}.{}", c.table, c.column)))
        .cloned()
        .collect())
}

pub fn assert_database_schema_current(
    probe: &dyn SchemaColumnProbe,
    logger: &dyn MigrationLogger,
    skip_env: Option<&str>,
    opts: ProbeOptions,
) -> Result<(), MigrationDriftError> {
    if matches!(skip_env, Some("1") | Some("true")) {
        logger.warn("Database migration guard skipped via TABULA_SKIP_MIGRATION_CHECK");
        return Ok(());
    }

    let missing = match find_missing_required_columns(probe, opts) {
        Ok(m) => m,
        Err(err) => {
            logger.error(&format!(
                "Database migration guard could not query information_schema after retries ({err}); \
                 continuing startup UNVERIFIED -- schema drift will surface as 503"
            ));
            return Ok(());
        }
    };

    if !missing.is_empty() {
        let drift = MigrationDriftError::new(missing.clone());
        logger.fatal(&missing, &drift.message);
        return Err(drift);
    }

    logger.info("Database schema verified against required migrations");
    Ok(())
}
