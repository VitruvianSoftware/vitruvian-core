# Src

## Overview
Component package providing implementation for `tools/model-prices/src`.

## Interface
- `[lib.rs:OPENROUTER_MODELS_URL]`
- `[lib.rs:MODELS_TSV_REL]`
- `[lib.rs:PRICES_MJS_REL]`
- `[lib.rs:DEFAULT_MAX_CHANGE_STR]`
- `[lib.rs:MAX_PRICE_PER_MILLION_USD]`
- `[lib.rs:EXIT_PRICE_OUT_OF_RANGE]`
- `[lib.rs:MAX_OPENROUTER_RESPONSE_BYTES]`
- `[lib.rs:PriceErrorKind]`
- `[lib.rs:PriceError]`
- `[lib.rs:sanitize_log_output]`
- `[lib.rs:Price]`
- `[lib.rs:MaxChange]`
- `[lib.rs:ModelSpec]`
- `[lib.rs:PriceSource]`
- `[lib.rs:FallbackReason]`
- `[lib.rs:ResolvedRow]`
- `[lib.rs:ExistingRow]`
- `[lib.rs:ExistingPricesFile]`
- `[lib.rs:CliOptions]`
- `[lib.rs:CliParseResult]`

## Invariants
- None

## Side Effects
- [lib.rs:423]: `\x20 --check                  Fetch and compare without writing; exit 1 if an...`

## Verification
- Run: `bazel test //tools/model-prices/src/...`
