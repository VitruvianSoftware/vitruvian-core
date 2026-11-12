# Windowlayout

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/WindowLayout`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [WindowStageManagerSupport.swift:31]: `/// `stripFrames` is lazy: the default/off paths never query the window server.`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/WindowLayout/...`
