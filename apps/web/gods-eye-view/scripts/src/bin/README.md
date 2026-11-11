# Bin

## Overview
Component package providing implementation for `apps/web/gods-eye-view/scripts/src/bin`.

## Interface
- Internal implementation components

## Invariants
- [check_format_scope.rs:38]: `assert!(out.contains("Checked "));`
- [check_format_scope.rs:39]: `assert!(out.contains(" source files."));`
- [check_import_directions.rs:38]: `assert!(out.contains("\"modules\":"));`
- [check_import_directions.rs:39]: `assert!(out.contains("\"portableEntries\":"));`
- [check_package_boundaries.rs:38]: `assert!(out.contains("Checked infrastructure:"));`
- [check_package_boundaries.rs:39]: `assert!(out.contains("Checked application:"));`
- [tle_mirror.rs:57]: `assert!(root.join("package.json").is_file(), "no package.json in {}", root.di...`
- [tle_mirror.rs:66]: `assert!(groups.contains(&"active".to_string()));`
- [tle_mirror.rs:67]: `assert!(groups.contains(&"stations".to_string()));`

## Side Effects
- [tle_mirror.rs:90]: `"fetch('/api/celestrak/active'); fetch(\"/api/celestrak/cubesat\");\n",`
- [tle_mirror.rs:96]: `"fetch('/api/celestrak/amateur');\n",`
- [tle_mirror.rs:202]: `Err("fetch failed".to_string())`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/scripts/src/bin/...`
