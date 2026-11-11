# Generated

## Overview
Component package providing implementation for `packages/vitruvian-sdk/kits/python/vitruvian_tool_kit/generated`.

## Interface
- `[manifest.py:ToolManifest]`
- `[manifest.py:Contributes]`
- `[manifest.py:StatusContribution]`
- `[manifest.py:SlotContribution]`
- `[manifest.py:Command]`
- `[manifest.py:Panel]`
- `[manifest.py:Preference]`
- `[manifest.py:PreferenceOption]`
- `[manifest.py:Runtime]`
- `[messages.py:ShapeError]`
- `[messages.py:RPCErrorObject]`
- `[messages.py:RefusalData]`
- `[messages.py:EmptyObject]`
- `[messages.py:InitializeParams]`
- `[messages.py:InitializeResult]`
- `[messages.py:CommandRunParams]`
- `[messages.py:PreferencesChangedParams]`
- `[messages.py:LanguageChangedParams]`
- `[messages.py:CommandsStateParams]`
- `[messages.py:NotifyHUDParams]`

## Invariants
- [messages.py:45]: `raise ShapeError(where, "an object")`
- [messages.py:51]: `raise ShapeError(f"{where}.{key}", "there")`
- [messages.py:57]: `raise ShapeError(where, "text")`

## Side Effects
- [manifest.py:369]: `exec: str`
- [manifest.py:377]: `exec=_string(_required(found, "exec", where), where + ".exec"),`
- [manifest.py:383]: `out["exec"] = self.exec`

## Verification
- Run: `bazel test //packages/vitruvian-sdk/kits/python/vitruvian_tool_kit/generated/...`
