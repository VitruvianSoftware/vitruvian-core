# Src

## Overview
Component package providing implementation for `tools/design-sync/src`.

## Interface
- `[inject_reference_fonts.rs:rewrite_fonts_css]`
- `[inject_reference_fonts.rs:extract_font_urls]`
- `[inject_reference_fonts.rs:inject_stylesheet_link]`
- `[inject_reference_fonts.rs:run]`
- `[lib.rs:design_sync_dir]`
- `[vitruvian_slack_mcp_e2e.rs:has_http_200]`
- `[vitruvian_slack_mcp_e2e.rs:extract_resource_preview]`
- `[vitruvian_slack_mcp_e2e.rs:parse_tools_count]`
- `[vitruvian_slack_mcp_e2e.rs:parse_channels_count]`
- `[vitruvian_slack_mcp_e2e.rs:run]`
- `[prepare.rs:has_leaked_tailwind_color]`
- `[prepare.rs:run]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [inject_reference_fonts.rs:276]: `assert!(text.contains("url('./IBMPlexSans-Regular.woff2')"));`
- [inject_reference_fonts.rs:277]: `assert!(!text.contains("url('./fonts/"));`
- [inject_reference_fonts.rs:314]: `assert!(injected`
- [vitruvian_slack_mcp_e2e.rs:312]: `assert!(has_http_200(`
- [vitruvian_slack_mcp_e2e.rs:315]: `assert!(has_http_200("HTTP/2 200 \r\n"));`
- [vitruvian_slack_mcp_e2e.rs:316]: `assert!(!has_http_200("HTTP/1.1 401 Unauthorized"));`
- [prepare.rs:173]: `assert!(has_leaked_tailwind_color(`
- [prepare.rs:176]: `assert!(has_leaked_tailwind_color("  --color-slate-50: #f8fafc;"));`
- [prepare.rs:177]: `assert!(!has_leaked_tailwind_color(`

## Side Effects
- [vitruvian_slack_mcp_e2e.rs:29]: `/// Match `HTTP/[0-9.]+ 200` anywhere in `resp`.`
- [vitruvian_slack_mcp_e2e.rs:31]: `let prefix = "HTTP/";`
- [vitruvian_slack_mcp_e2e.rs:136]: `let mut cmd = Command::new("curl");`

## Verification
- Run: `bazel test //tools/design-sync/src/...`
