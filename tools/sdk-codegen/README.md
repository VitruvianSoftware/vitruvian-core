# Sdk Codegen

## Overview
Subsystem blueprint grouping child modules under `tools/sdk-codegen`.

## Subdirectories & Boundaries
- [src](./src/README.md): Component package providing implementation for tools/sdk-codegen/src.


## Generated folders

Every file under `packages/vitruvian-sdk/kits/*/generated` (and `go/toolkit/*_gen.go`) is written by this tool. Do not add files there by hand, READMEs included: `--check` fails on any file no emitter writes. Document a generated folder from its parent README instead.
