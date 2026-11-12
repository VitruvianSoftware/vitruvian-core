# Vitruvian Tool Kit

## Overview
Component package providing implementation for `packages/vitruvian-sdk/kits/python/vitruvian_tool_kit`.

## Interface
- `[panels.py:PanelEvent]`
- `[panels.py:PanelAnswer]`
- `[panels.py:Panel]`
- `[panels.py:text]`
- `[panels.py:heading]`
- `[panels.py:row]`
- `[panels.py:button]`
- `[panels.py:toggle]`
- `[panels.py:field]`
- `[panels.py:list_]`
- `[panels.py:progress]`
- `[panels.py:image]`
- `[panels.py:divider]`
- `[panels.py:link]`
- `[panels.py:spacer]`
- `[panels.py:choice]`
- `[panels.py:chips]`
- `[panels.py:tree]`
- `[tool.py:RPCErrorCode]`
- `[tool.py:RefusalCode]`
- Subdirectory: [generated](./generated/) (code written by `//tools/sdk-codegen`; do not edit)

## Invariants
- None

## Side Effects
- [wire.py:225]: `written = os.write(self._output, data)`

## Verification
- Run: `bazel test //packages/vitruvian-sdk/kits/python/vitruvian_tool_kit/...`
