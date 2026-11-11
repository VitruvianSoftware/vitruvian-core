# Src

## Overview
Component package providing implementation for `gitops/argocd/platform/actions-runners-manifests/src`.

## Interface
- Internal implementation components

## Invariants
- [lib.rs:41]: `panic!("cannot find {MANIFEST}");`
- [lib.rs:126]: `assert!(`
- [lib.rs:138]: `assert!(`

## Side Effects
- None

## Verification
- Run: `bazel test //gitops/argocd/platform/actions-runners-manifests/src/...`
