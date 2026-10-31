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

//! Real-database check of `migrate_deploy_bin`. Runs as a `service_test`
//! after the `:migrate` itest task, which runs the Rust binary (and through it
//! the hermetic Prisma CLI) against a throwaway Postgres. Asserts the effect,
//! not the exit code: every migration directory in the source tree is
//! recorded as applied, and every column the API's startup guard requires
//! exists.

use std::fs;
use std::path::PathBuf;

use tabula_api_tools_rs_lib::migration_guard::{find_missing_required_columns, ProbeOptions};
use tabula_api_tools_rs_lib::store::PgClient;

const POSTGRES_LABEL: &str = "@@//apps/suites/tabula/api:postgres";

fn postgres_url() -> String {
    let ports =
        std::env::var("ASSIGNED_PORTS").expect("ASSIGNED_PORTS: not running under rules_itest");
    let map: serde_json::Value = serde_json::from_str(&ports).expect("ASSIGNED_PORTS is not JSON");
    let port = map
        .get(POSTGRES_LABEL)
        .and_then(|v| {
            v.as_u64()
                .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
        })
        .unwrap_or_else(|| panic!("no port for {POSTGRES_LABEL} in {ports}"));
    format!("postgresql://postgres@127.0.0.1:{port}/postgres")
}

fn migration_dirs() -> Vec<String> {
    let rf = runfiles::Runfiles::create().expect("runfiles");
    let schema: PathBuf =
        runfiles::rlocation!(rf, env!("SCHEMA_RLOCATION")).expect("schema in runfiles");
    let dir = schema.parent().unwrap().join("migrations");
    let mut names: Vec<String> = fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("read {}: {e}", dir.display()))
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    names.sort();
    names
}

#[test]
fn every_migration_is_applied_and_the_schema_is_current() {
    let pg = PgClient::from_url(&postgres_url()).expect("connect to the itest Postgres");

    let rows = pg
        .query_simple(
            "SELECT migration_name FROM _prisma_migrations \
             WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL \
             ORDER BY migration_name",
        )
        .expect("_prisma_migrations is readable (did migrate_deploy_bin run?)");
    let applied: Vec<String> = rows
        .into_iter()
        .filter_map(|r| r.get("migration_name").cloned().flatten())
        .collect();

    let on_disk = migration_dirs();
    assert!(!on_disk.is_empty(), "no migrations found in runfiles");
    assert_eq!(
        applied, on_disk,
        "applied migrations differ from the source tree"
    );

    let missing = find_missing_required_columns(
        &pg,
        ProbeOptions {
            attempts: 3,
            backoff_ms: 100,
        },
    )
    .expect("information_schema is readable");
    assert!(
        missing.is_empty(),
        "required columns missing after migrate: {missing:?}"
    );
}
