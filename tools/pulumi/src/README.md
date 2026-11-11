# Src

## Overview
Component package providing implementation for `tools/pulumi/src`.

## Interface
- `[argparse.rs:Kind]`
- `[argparse.rs:Opt]`
- `[argparse.rs:Parser]`
- `[argparse.rs:Values]`
- `[argparse.rs:Exit]`
- `[argparse.rs:help_width]`
- `[argparse.rs:wrap]`
- `[create_app.rs:extract_code]`
- `[create_app.rs:MAX_CODE_LEN]`
- `[create_app.rs:is_valid_code]`
- `[create_app.rs:create_html_file]`
- `[create_app.rs:run]`
- `[http.rs:Error]`
- `[http.rs:Request]`
- `[http.rs:send]`
- `[json.rs:Value]`
- `[json.rs:dedup]`
- `[json.rs:JsonError]`
- `[json.rs:loads]`
- `[json.rs:dumps]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [http.rs:402]: `assert!(sent.starts_with("POST /x?y=1 HTTP/1.1\r\n"), "{}", sent);`
- [http.rs:403]: `assert!(sent.contains("Content-Length: 8\r\n"), "{}", sent);`
- [http.rs:404]: `assert!(`
- [pulumi_cmd.rs:338]: `assert!(has_flag(&args, &["--stack", "-s"]));`
- [pulumi_cmd.rs:339]: `assert!(!has_flag(&args, &["--non-interactive"]));`
- [pulumi_cmd.rs:345]: `assert!(has_flag(&args, &["--stack", "-s"]));`
- [pystr.rs:203]: `assert!(is_space('\u{1c}'));`
- [pystr.rs:204]: `assert!(!is_space('\u{200b}'));`

## Side Effects
- [create_app.rs:316]: `let mut child = match c.spawn() {`
- [create_app.rs:387]: `let redirect_url = "http://localhost:8723/cb";`
- [http.rs:23]: `//! back. `http://` URLs (a test server in PULUMI_API) go over a plain`
- [http.rs:24]: `//! socket; `https://` goes through curl, since the standard library has no`
- [http.rs:27]: `//! http.client raises before anything is sent. Redirects are not followed.`
- [lib.rs:30]: `pub mod http;`
- [lib.rs:352]: `let req = http::Request {`
- [lib.rs:359]: `match http::send(&req) {`
- [pulumi_cmd.rs:191]: `if !(backend.starts_with("https://") || backend.starts_with("http://")) {`
- [retry_concurrent_update.rs:83]: `.spawn()`

## Verification
- Run: `bazel test //tools/pulumi/src/...`
