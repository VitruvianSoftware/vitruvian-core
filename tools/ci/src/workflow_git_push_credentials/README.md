# Workflow Git Push Credentials

## Overview
Component package providing implementation for `tools/ci/src/workflow_git_push_credentials`.

## Interface
- Internal implementation components

## Invariants
- [tests.rs:111]: `assert!(`
- [tests.rs:117]: `assert!(`
- [tests.rs:164]: `assert!(`

## Side Effects
- [tests.rs:157]: `"git config http.https://github.com/.extraheader x",`

## Verification
- Run: `bazel test //tools/ci/src/workflow_git_push_credentials/...`
