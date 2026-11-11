# Fmt

## Overview
Component package providing implementation for `apps/desktop/courier/gchat/src/fmt`.

## Interface
- `[inbound.rs:ConvertedInboundText]`
- `[inbound.rs:escape_html]`
- `[inbound.rs:annotations_to_matrix_html]`
- `[outbound.rs:MAX_OUTBOUND_TEXT_CHARS]`
- `[outbound.rs:OutboundFormattedMessage]`
- `[outbound.rs:unescape_html]`
- `[outbound.rs:matrix_html_to_annotations]`

## Invariants
- None

## Side Effects
- [inbound.rs:42]: `|| trimmed.starts_with("http://")`

## Verification
- Run: `bazel test //apps/desktop/courier/gchat/src/fmt/...`
