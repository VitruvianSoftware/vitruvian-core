# Rust Src

## Overview
Component package providing implementation for `apps/mcp/vitruvian-roborock-mcp/rust_src`.

## Interface
- `[auth.rs:SETUP_HINT]`
- `[auth.rs:AuthError]`
- `[auth.rs:ApiError]`
- `[auth.rs:ApiClient]`
- `[auth.rs:ClientFactory]`
- `[auth.rs:explain_api_error]`
- `[auth.rs:AuthStatus]`
- `[auth.rs:auth_status]`
- `[auth.rs:require_credentials]`
- `[auth.rs:LoginFlow]`
- `[cli.rs:DaemonSubcommand]`
- `[cli.rs:Subcommand]`
- `[cli.rs:ParsedArgs]`
- `[cli.rs:ParseOutcome]`
- `[cli.rs:help_text]`
- `[cli.rs:parse_args]`
- `[cli.rs:CliClient]`
- `[cli.rs:CliHooks]`
- `[cli.rs:CliExecution]`
- `[cli.rs:format_status]`

## Invariants
- [codes.rs:497]: `assert!(str_bit(&s, 55));`
- [codes.rs:498]: `assert!(!str_bit(&s, 54));`
- [codes.rs:499]: `assert!(!str_bit("", 55));`
- [crypto.rs:279]: `assert!(encrypt_ecb(b"", &key).unwrap().is_empty());`
- [crypto.rs:280]: `assert!(encrypt_ecb(b"x", b"short").is_err());`
- [crypto.rs:291]: `assert!(decrypt_cbc(&ct[..15], &key).is_err());`
- [lib.rs:161]: `assert!(Instant::now() <= deadline, "condition not reached in time");`
- [lib.rs:225]: `panic!("status blew up");`
- [lib.rs:236]: `panic!("map blew up");`
- [link.rs:346]: `// However `connect` ends (an error, or a panic), the attempt is over:`

## Side Effects
- [cloud.rs:22]: `//! The Roborock cloud HTTP API: region discovery, emailed-code login, and`
- [cloud.rs:74]: `pub query: Vec<(String, String)>,`
- [cloud.rs:92]: `// plain HTTP.`
- [daemon.rs:22]: `//! Loopback HTTP daemon server and synchronous HTTP client.`
- [daemon.rs:108]: `.unwrap_or_else(|| format!("daemon returned HTTP {}", self.status))`
- [daemon.rs:199]: `format!("http://{}:{}", config::DAEMON_HOST, self.port)`
- [local.rs:165]: `.spawn(move || write_loop(writer_stream, writer_rx))`
- [local.rs:170]: `.spawn(move || read_loop(reader, reader_inner))`
- [local.rs:180]: `.spawn(move || loop {`
- [mqtt.rs:131]: `.spawn(move || run(opts, first, rx, worker_shared, on_unauthorized))`

## Verification
- Run: `bazel test //apps/mcp/vitruvian-roborock-mcp/...`
