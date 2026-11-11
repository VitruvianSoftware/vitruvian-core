# Src

## Overview
Component package providing implementation for `apps/suites/wand/core/src`.

## Interface
- `[bindings.rs:Platform]`
- `[bindings.rs:Button]`
- `[bindings.rs:Press]`
- `[bindings.rs:TriggerMode]`
- `[bindings.rs:Trigger]`
- `[bindings.rs:MediaAction]`
- `[bindings.rs:VolumeAction]`
- `[bindings.rs:BrightnessAction]`
- `[bindings.rs:KeyChord]`
- `[bindings.rs:SystemAction]`
- `[bindings.rs:NavAction]`
- `[bindings.rs:Direction]`
- `[bindings.rs:Action]`
- `[bindings.rs:Binding]`
- `[bindings.rs:Bindings]`
- `[bindings.rs:default_bindings]`
- `[buttons.rs:DEFAULT_LONG_PRESS_US]`
- `[buttons.rs:DEFAULT_DOUBLE_PRESS_US]`
- `[buttons.rs:DEFAULT_TAP_MAX_US]`
- `[buttons.rs:DEFAULT_TAP_MAX_MOVE]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/suites/wand/core/src/...`
