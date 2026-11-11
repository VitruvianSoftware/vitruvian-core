# Src

## Overview
Component package providing implementation for `apps/web/oauth-user-inspector/scripts/src`.

## Interface
- `[check_sensitive.rs:is_sensitive]`
- `[check_sensitive.rs:run]`
- `[deploy.rs:SERVICE_NAME]`
- `[deploy.rs:DEFAULT_REGION]`
- `[deploy.rs:REQUIRED_SERVICES]`
- `[deploy.rs:DeployConfig]`
- `[deploy.rs:resolve_deploy_config]`
- `[deploy.rs:compute_service_account]`
- `[deploy.rs:run]`
- `[setup_dev.rs:PRE_COMMIT_HOOK_SCRIPT]`
- `[setup_dev.rs:install_pre_commit_hook]`
- `[setup_dev.rs:run]`
- `[smoke.rs:command_v]`
- `[smoke.rs:find_chrome_binary]`
- `[smoke.rs:as_captured]`
- `[smoke.rs:mounted]`
- `[smoke.rs:run]`
- `[start.rs:BuildCheckError]`
- `[start.rs:ServerCommand]`
- `[start.rs:exec_failure_message]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [lib.rs:43]: `assert!(is_sensitive(".env.local"));`
- [lib.rs:48]: `assert!(is_sensitive("some/path/.env.production"));`
- [lib.rs:53]: `assert!(is_sensitive(".env"));`
- [start.rs:265]: `assert!(msg.starts_with("failed to exec node: "), "{msg}");`
- [start.rs:266]: `assert!(!msg.contains("server.js"), "{msg}");`
- [start.rs:273]: `assert!(cmd.args().is_empty());`

## Side Effects
- [smoke.rs:24]: `//! prod past an HTTP-200-only check), so a plain curl is not enough. `CAND` is`
- [smoke.rs:33]: `//! - curl's result does not decide anything (it warms the revision up, with`
- [smoke.rs:106]: `let _ = Command::new("curl")`
- [start.rs:63]: `/// The program `exec` runs, and what a failed exec must name. For the`
- [start.rs:80]: `/// `exec` the server. Returns only on failure, with the message to log.`
- [start.rs:81]: `pub fn exec(&self) -> String {`

## Verification
- Run: `bazel test //apps/web/oauth-user-inspector/scripts/src/...`
