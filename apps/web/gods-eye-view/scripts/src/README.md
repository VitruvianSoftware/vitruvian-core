# Src

## Overview
Component package providing implementation for `apps/web/gods-eye-view/scripts/src`.

## Interface
- `[build_military_names.rs:RELEASE]`
- `[build_military_names.rs:CLASSES]`
- `[build_military_names.rs:sha256_hex]`
- `[build_military_names.rs:parse_osm_record_id]`
- `[build_military_names.rs:MilitaryNamesPack]`
- `[build_military_names.rs:assemble_pack]`
- `[build_military_names.rs:assemble]`
- `[build_military_names.rs:run]`
- `[cesium_render.rs:RenderMode]`
- `[cesium_render.rs:CesiumRenderOpts]`
- `[cesium_render.rs:AssetRoute]`
- `[cesium_render.rs:CesiumRenderPlan]`
- `[cesium_render.rs:HELP_TEXT]`
- `[cesium_render.rs:parse_args]`
- `[cesium_render.rs:load_api_key]`
- `[cesium_render.rs:mime_type_for_path]`
- `[cesium_render.rs:resolve_asset_route]`
- `[cesium_render.rs:chromium_launch_args]`
- `[cesium_render.rs:progressive_sse_ladder]`
- `[cesium_render.rs:build_render_url]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [check_import_directions.rs:41]: `"assert",`
- [check_import_directions.rs:42]: `"assert/strict",`
- [check_import_directions.rs:420]: `// `const require = createRequire(import.meta.url)` is the ES-module way to`
- [check_package_boundaries.rs:354]: `Ok(r) => panic!("expected a failure matching {pattern:?}, got Ok({r:?})"),`
- [check_package_boundaries.rs:355]: `Err(e) => assert!(`
- [lib.rs:169]: `assert!(result.is_err());`
- [lib.rs:170]: `assert!(result.unwrap_err().contains("Duplicate OSM identity"));`
- [lib.rs:182]: `assert!(result.is_err());`

## Side Effects
- [build_military_names.rs:379]: `"Cached query result not found: {}. Run the Python script with DuckDB first.",`
- [cesium_render.rs:409]: `format!("http://127.0.0.1:{}/?{}", port, params.join("&"))`
- [check_import_directions.rs:58]: `"http",`
- [dev_helpers.rs:459]: `Some(ip) if !ip.is_empty() => format!("!! LAN URL: http://{}:{}/", ip, port),`
- [dev_helpers.rs:460]: `_ => format!("!! LAN URL: http://<this-machine-ip>:{}/", port),`
- [opensky_import_client.rs:95]: `pub fn run_with_executor<F>(args: &[String], exec: F) -> Result<(), String>`
- [opensky_import_client.rs:113]: `exec(`
- [opensky_import_client.rs:126]: `exec(`
- [sat_ortho.rs:297]: `let res = fetcher.fetch(&create_session_request(api_key))?;`
- [sat_ortho.rs:312]: `/// Fetch every tile, 8 at a time; a failed tile is a warning, as in the JS t...`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/scripts/src/...`
