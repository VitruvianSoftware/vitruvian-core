# Portmanager

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/UI/PortManager`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [PortManagerView.swift:36]: `TextField(strings.filter, text: $service.query).textFieldStyle(.plain)`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/UI/PortManager/...`
