# Src

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/app/scripts/src`.

## Interface
- `[app_holds_engine.rs:resolve_app]`
- `[app_holds_engine.rs:run]`
- `[archs.rs:RELEASE_ARCHS]`
- `[archs.rs:parse_lipo_archs]`
- `[archs.rs:missing]`
- `[archs.rs:engine_lacks]`
- `[archs.rs:read]`
- `[engine_contract.rs:run]`
- `[engine_seed.rs:marker_from_source]`
- `[engine_seed.rs:contains]`
- `[engine_seed.rs:split_args]`
- `[engine_seed.rs:run]`
- `[inject_app_credentials.rs:validate_api_id]`
- `[inject_app_credentials.rs:validate_api_hash]`
- `[inject_app_credentials.rs:generate_plist]`
- `[inject_app_credentials.rs:store_dirs]`
- `[inject_app_credentials.rs:run]`
- `[install.rs:run]`
- `[publish.rs:APP_NAME]`
- `[publish.rs:CASK_NAME]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [archs.rs:67]: `assert!(parse_lipo_archs("").is_empty());`
- [archs.rs:75]: `assert!(missing(&RELEASE_ARCHS, &both).is_empty());`
- [archs.rs:89]: `assert!(engine_lacks(&app, &engine).is_empty());`
- [engine_seed.rs:176]: `assert!(contains(`
- [engine_seed.rs:180]: `assert!(!contains(`
- [engine_seed.rs:184]: `assert!(!contains(b"anything", b""));`
- [lib.rs:50]: `assert!(inject_app_credentials::validate_api_id("0").is_err());`
- [lib.rs:55]: `assert!(inject_app_credentials::validate_api_id("2147483648").is_err());`
- [lib.rs:60]: `assert!(inject_app_credentials::validate_api_id("99999999999999999999").is_er...`
- [run_test_copy.rs:253]: `assert!(is_installed_apps_data(`

## Side Effects
- [inject_app_credentials.rs:55]: `<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com...`
- [inject_app_credentials.rs:349]: `eprintln!("To fetch them: bazel run //tools/sync-env-secrets:bw-pull");`
- [inject_app_credentials.rs:451]: `.args([&app_str, "-exec", "xattr", "-c", "{}", "+"])`
- [publish.rs:393]: `let mut query = vec!["cquery".to_string()];`
- [publish.rs:394]: `query.extend(plan.bazel_flags.iter().cloned());`
- [publish.rs:395]: `query.extend(["--output=files".to_string(), TARGET.to_string()]);`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/app/scripts/src/...`
