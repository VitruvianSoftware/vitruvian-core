# Delivery Drift

## Overview
Component package providing implementation for `tools/ci/src/delivery_drift`.

## Interface
- `[lib.rs:default_engine]`
- `[lib.rs:run]`
- `[lib.rs:run_with_engine]`

## Invariants
- [tests.rs:268]: `let jq = std::fs::canonicalize(&jq).unwrap_or_else(|e| panic!("JQ_BIN={jq}: {...`
- [tests.rs:362]: `assert!(r.conclusion_is("failure"), "{}", r.result);`
- [tests.rs:400]: `assert!(r.conclusion_is("success"));`

## Side Effects
- [lib.rs:313]: `const RUNS_QUERY: &str = r#"query($id: ID!, $n: Int!, $after: String) {`
- [lib.rs:398]: `cat(&[b"query=", RUNS_QUERY.as_bytes()]),`
- [tests.rs:101]: `[ -z "${STUB_RUNLIST_FAIL:-}" ] || { echo "gh: HTTP 502" >&2; exit 1; }`
- [tests.rs:112]: `[ -z "${STUB_GQL_FAIL:-}" ] || { echo "gh: HTTP 502" >&2; exit 1; }`
- [tests.rs:256]: `"#!/usr/bin/env bash\ncase \"$1\" in\n  query) printf '%s\\n' ${{STUB_LABELS:...`

## Verification
- Run: `bazel test //tools/ci/src/delivery_drift/...`
