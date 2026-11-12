# Include

## Overview
Component package providing implementation for `apps/embedded/vitruvian-deck/include`.

## Interface
- Internal implementation components

## Invariants
- [lv_conf.h:151]: `* Note that `bg_opa`, `text_opa` etc don't require buffering into layer)`
- [lv_conf.h:295]: `/*Add a custom handler when assert happens e.g. to restart the MCU*/`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/embedded/vitruvian-deck/include/...`
