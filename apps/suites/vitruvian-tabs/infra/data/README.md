# Data

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/infra/data`.

## Interface
- Internal implementation components

## Invariants
- [main.go:115]: `{name: "development", gcpProject: cfg.Require("developmentProject")},`
- [main.go:116]: `{name: "nonproduction", gcpProject: cfg.Require("nonproductionProject")},`
- [main.go:117]: `{name: "production", gcpProject: cfg.Require("productionProject")},`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/infra/data/...`
