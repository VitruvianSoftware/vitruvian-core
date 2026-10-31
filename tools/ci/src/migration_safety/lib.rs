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

//! migration-safety.sh — Squawk migration-safety gate for Tabula's Prisma
//! migrations (issue #819).

use shell_compat::{capture, cat, env_or, err, mktemp_dir, out, status, subst, write_file};
use std::process::Command;

const SQUAWK_VERSION: &str = "2.67.0";
const MIG_DIR: &str = "apps/suites/tabula/api/prisma/migrations";

fn fail(msg: &[u8]) -> i32 {
    err(&cat(&[b"::error::migration-safety: ", msg, b"\n"]));
    1
}

fn note(msg: &[u8]) {
    out(&cat(&[b"migration-safety: ", msg, b"\n"]));
}

fn find_root() -> Vec<u8> {
    if let Some(v) = shell_compat::env("BUILD_WORKSPACE_DIRECTORY") {
        if !v.is_empty() {
            return v;
        }
    }
    let r = capture(
        0,
        Command::new("git").arg("rev-parse").arg("--show-toplevel"),
    );
    if r.ok() {
        let root = subst(r.stdout);
        if !root.is_empty() {
            return root;
        }
    }
    let r = capture(0, &mut Command::new("pwd"));
    subst(r.stdout)
}

fn squawk(config: &[u8], extra_args: &[&[u8]]) -> i32 {
    let pkg = cat(&[b"squawk-cli@", SQUAWK_VERSION.as_bytes()]);
    let mut cmd = Command::new("npx");
    cmd.arg("--yes")
        .arg(shell_compat::os(&pkg))
        .arg("-c")
        .arg(shell_compat::os(config));
    for a in extra_args {
        cmd.arg(shell_compat::os(a));
    }
    status(0, &mut cmd, false)
}

fn squawk_quiet(config: &[u8], extra_args: &[&[u8]]) -> i32 {
    let pkg = cat(&[b"squawk-cli@", SQUAWK_VERSION.as_bytes()]);
    let mut cmd = Command::new("npx");
    cmd.arg("--yes")
        .arg(shell_compat::os(&pkg))
        .arg("-c")
        .arg(shell_compat::os(config))
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    for a in extra_args {
        cmd.arg(shell_compat::os(a));
    }
    status(0, &mut cmd, true)
}

fn selftest(config: &[u8], tmp: &[u8]) -> i32 {
    let bad = cat(&[tmp, b"/backward_incompatible.sql"]);
    let good = cat(&[tmp, b"/backward_compatible.sql"]);

    let _ = write_file(
        &bad,
        b"ALTER TABLE \"users\" DROP COLUMN \"email\";\nALTER TABLE \"users\" ALTER COLUMN \"id\" SET DATA TYPE VARCHAR(100);\n",
        0o644,
    );
    let _ = write_file(
        &good,
        b"ALTER TABLE \"users\" ADD COLUMN \"nickname\" text;\n",
        0o644,
    );

    if squawk_quiet(config, &[&good]) != 0 {
        return fail(b"self-test FAILED -- a backward-COMPATIBLE fixture (ADD nullable COLUMN) was REJECTED. apps/suites/tabula/api/prisma/.squawk.toml is mis-tuned and would block safe expand migrations.");
    }
    if squawk_quiet(config, &[&bad]) == 0 {
        return fail(b"self-test FAILED -- a backward-INCOMPATIBLE fixture (DROP COLUMN + type narrow) PASSED. The gate is not catching hazards; check that ban-drop-column / changing-column-type are not in excluded_rules.");
    }

    let ign = cat(&[tmp, b"/ignore_ok.sql"]);
    let ignscoped = cat(&[tmp, b"/ignore_scoped.sql"]);
    let _ = write_file(
        &ign,
        b"-- squawk-ignore changing-column-type\nALTER TABLE \"users\" ALTER COLUMN \"name\" SET DATA TYPE VARCHAR(500);\n",
        0o644,
    );
    let _ = write_file(
        &ignscoped,
        b"-- squawk-ignore changing-column-type\nALTER TABLE \"users\" DROP COLUMN \"email\";\n",
        0o644,
    );

    if squawk_quiet(config, &[&ign]) != 0 {
        return fail(b"self-test FAILED -- a widening with '-- squawk-ignore changing-column-type' was REJECTED. The documented escape hatch no longer works; safe-but-flagged changes have no remedy except *_contract.");
    }
    if squawk_quiet(config, &[&ignscoped]) == 0 {
        return fail(b"self-test FAILED -- '-- squawk-ignore changing-column-type' suppressed an UNRELATED hazard (DROP COLUMN). The ignore must be rule-scoped, not a blanket bypass.");
    }

    note(b"self-test OK (drop/type-narrow rejected, add-nullable accepted, scoped squawk-ignore honored).");
    0
}

fn is_contract_migration(path: &[u8]) -> bool {
    let s = match std::str::from_utf8(path) {
        Ok(s) => s,
        Err(_) => return false,
    };
    // */*_contract/migration.sql
    if !s.ends_with("/migration.sql") {
        return false;
    }
    let dir = &s[..s.len() - "/migration.sql".len()];
    dir.ends_with("_contract")
}

fn parse_changed_migrations(diff_output: &[u8], mig_dir: &str) -> Vec<Vec<u8>> {
    let mut result = Vec::new();
    for line in shell_compat::lines(diff_output) {
        if line.is_empty() {
            continue;
        }
        let s = match std::str::from_utf8(&line) {
            Ok(s) => s,
            Err(_) => continue,
        };
        let parts: Vec<&str> = s.split('\t').collect();
        if parts.len() < 2 {
            continue;
        }
        let status_code = parts[0];
        if status_code.starts_with('A')
            || status_code.starts_with('M')
            || status_code.starts_with('C')
        {
            let file = if parts.len() >= 3 { parts[2] } else { parts[1] };
            if file.starts_with(mig_dir) && file.ends_with("migration.sql") {
                result.push(file.as_bytes().to_vec());
            }
        } else if status_code.starts_with('R') && status_code != "R100" {
            if parts.len() >= 3 {
                let file = parts[2];
                if file.starts_with(mig_dir) && file.ends_with("migration.sql") {
                    result.push(file.as_bytes().to_vec());
                }
            }
        }
    }
    result
}

fn lint_changed(root: &[u8], config: &[u8], base: &[u8]) -> i32 {
    let r = capture(
        0,
        Command::new("git")
            .arg("-C")
            .arg(shell_compat::os(root))
            .arg("diff")
            .arg("-M")
            .arg("--name-status")
            .arg(shell_compat::os(&cat(&[base, b"...HEAD"]))),
    );
    let diff_output = subst(r.stdout);
    let changed = parse_changed_migrations(&diff_output, MIG_DIR);

    if changed.is_empty() {
        note(&cat(&[
            b"no added/modified migrations since ",
            base,
            b" -- nothing to lint.",
        ]));
        return 0;
    }

    let mut rc = 0;
    for f in &changed {
        if f.is_empty() {
            continue;
        }
        if is_contract_migration(f) {
            note(&cat(&[b"SKIP deliberate contract migration: ", f]));
            continue;
        }
        let full_path = cat(&[root, b"/", f]);
        if squawk(config, &[&full_path]) == 0 {
            note(&cat(&[b"OK: ", f]));
        } else {
            err(&cat(&[
                b"::error file=",
                f,
                b"::Backward-incompatible migration. Two remedies: (1) DELIBERATE destructive change -> make it a *_contract migration so it is applied only via `--phase contract`, post-soak, never auto-applied during a blue-green rollout; (2) you have VERIFIED this statement is backward-COMPATIBLE (e.g. a type widening Squawk flags conservatively) -> add `-- squawk-ignore <rule>` on the line above it. See docs/engineering/application-development-principles.md#expandcontract-migrations.\n",
            ]));
            rc = 1;
        }
    }
    rc
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let root = find_root();
    let config = cat(&[&root, b"/apps/suites/tabula/api/prisma/.squawk.toml"]);

    let tmp = match mktemp_dir() {
        Ok(t) => t,
        Err(e) => {
            err(&cat(&[
                b"migration-safety: mktemp failed: ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            return 1;
        }
    };

    let rc = selftest(&config, &tmp);
    let _ = std::fs::remove_dir_all(shell_compat::path(&tmp));
    if rc != 0 {
        return rc;
    }

    // The expand-phase status parser is guarded by
    // //apps/suites/tabula/api:tabula_api_tools_rs_test (it is Rust now), not here.

    if !args.is_empty() && !args[0].is_empty() {
        if lint_changed(&root, &config, &args[0]) != 0 {
            return 1;
        }
    }

    note(b"all checks passed.");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn contract_migration_detected() {
        assert!(is_contract_migration(
            b"apps/suites/tabula/api/prisma/migrations/20260702000000_drop_ws_id_contract/migration.sql"
        ));
    }

    #[test]
    fn expand_migration_not_contract() {
        assert!(!is_contract_migration(
            b"apps/suites/tabula/api/prisma/migrations/20260701000000_add_col/migration.sql"
        ));
    }

    #[test]
    fn contract_terms_is_not_a_contract_migration() {
        assert!(!is_contract_migration(
            b"apps/suites/tabula/api/prisma/migrations/20260701000000_contract_terms/migration.sql"
        ));
    }

    #[test]
    fn non_sql_file_is_not_contract() {
        assert!(!is_contract_migration(
            b"apps/suites/tabula/api/prisma/migrations/20260702000000_drop_ws_id_contract/README.md"
        ));
    }

    #[test]
    fn parse_added_migration() {
        let diff =
            b"A\tapps/suites/tabula/api/prisma/migrations/20260701000000_add_col/migration.sql\n";
        let result = parse_changed_migrations(diff, MIG_DIR);
        assert_eq!(result.len(), 1);
        assert_eq!(
            result[0],
            b"apps/suites/tabula/api/prisma/migrations/20260701000000_add_col/migration.sql"
        );
    }

    #[test]
    fn parse_modified_migration() {
        let diff =
            b"M\tapps/suites/tabula/api/prisma/migrations/20260701000000_add_col/migration.sql\n";
        let result = parse_changed_migrations(diff, MIG_DIR);
        assert_eq!(result.len(), 1);
    }

    #[test]
    fn parse_rename_r100_skipped() {
        let diff = b"R100\told/path/migration.sql\tapps/suites/tabula/api/prisma/migrations/20260701000000_add_col/migration.sql\n";
        let result = parse_changed_migrations(diff, MIG_DIR);
        assert!(result.is_empty());
    }

    #[test]
    fn parse_partial_rename_included() {
        let diff = b"R080\told/path/migration.sql\tapps/suites/tabula/api/prisma/migrations/20260701000000_add_col/migration.sql\n";
        let result = parse_changed_migrations(diff, MIG_DIR);
        assert_eq!(result.len(), 1);
    }

    #[test]
    fn parse_deleted_migration_excluded() {
        let diff =
            b"D\tapps/suites/tabula/api/prisma/migrations/20260701000000_add_col/migration.sql\n";
        let result = parse_changed_migrations(diff, MIG_DIR);
        assert!(result.is_empty());
    }

    #[test]
    fn parse_non_migration_file_excluded() {
        let diff = b"A\tapps/suites/tabula/api/prisma/schema.prisma\n";
        let result = parse_changed_migrations(diff, MIG_DIR);
        assert!(result.is_empty());
    }

    #[test]
    fn parse_mixed_diff_output() {
        let diff = b"A\tapps/suites/tabula/api/prisma/migrations/20260701000000_add_col/migration.sql\n\
                      D\tapps/suites/tabula/api/prisma/migrations/20260601000000_old/migration.sql\n\
                      M\tapps/suites/tabula/api/prisma/migrations/20260702000000_fix/migration.sql\n\
                      A\tsrc/index.ts\n";
        let result = parse_changed_migrations(diff, MIG_DIR);
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn parse_empty_diff() {
        let result = parse_changed_migrations(b"", MIG_DIR);
        assert!(result.is_empty());
    }

    #[test]
    fn contract_suffix_only_matches_directory_name() {
        assert!(is_contract_migration(b"foo/bar_contract/migration.sql"));
        assert!(!is_contract_migration(b"foo/contractbar/migration.sql"));
        assert!(!is_contract_migration(b"foo/bar_contractor/migration.sql"));
    }

    #[test]
    fn copy_status_included() {
        let diff = b"C100\toriginal.sql\tapps/suites/tabula/api/prisma/migrations/20260701000000_add_col/migration.sql\n";
        let result = parse_changed_migrations(diff, MIG_DIR);
        assert_eq!(result.len(), 1);
    }
}
