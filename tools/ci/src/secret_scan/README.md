# Secret Scan

## Overview
Component package providing implementation for `tools/ci/src/secret_scan`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:40]: `.unwrap_or_else(|| panic!("no {name} in the secret_scan source"))`
- [tests.rs:106]: `assert!(o.all().contains("gitleaks did not run"), "{}", o.all());`
- [tests.rs:107]: `assert!(!o.all().contains("found a candidate secret"));`

## Side Effects
- [lib.rs:138]: `b", or unset USE_SYSTEM_GITLEAKS to use the pinned,\n    checksum-verified do...`
- [lib.rs:200]: `b") -- this is an exec\nfailure, NOT a secret finding. The fetched binary is ...`
- [lib.rs:214]: `/// Fetch, verify and unpack the pinned gitleaks into `bin_dir`. `Err` is the`
- [tests.rs:22]: `//! with a stub `gitleaks` (and, for the download path, a fake `curl`) first on`
- [tests.rs:24]: `//! the decision logic: an exec failure is not a finding, a finding is, and a`
- [tests.rs:293]: `/// The download path: no system gitleaks requested, a fake curl serving`

## Verification
- Run: `bazel test //tools/ci/src/secret_scan/...`
