# Src

## Overview
Component package providing implementation for `tools/antigravity-telemetry/src`.

## Interface
- `[cli.rs:DEFAULT_ENDPOINT]`
- `[cli.rs:LAUNCH_AGENT_LABEL]`
- `[cli.rs:EXPORTER_NAME]`
- `[cli.rs:EXPORTER_SUBCOMMAND]`
- `[cli.rs:DEFAULT_HOOK_NAME]`
- `[cli.rs:legacy_gemini_settings_path]`
- `[cli.rs:default_hooks_dir]`
- `[cli.rs:launch_agent_path]`
- `[cli.rs:exporter_log_dir]`
- `[cli.rs:get_default_settings_path]`
- `[cli.rs:Kind]`
- `[cli.rs:Namespace]`
- `[cli.rs:ArgParser]`
- `[cli.rs:strip_legacy_hooks]`
- `[cli.rs:build_launch_agent_plist]`
- `[cli.rs:find_agy]`
- `[cli.rs:cmd_setup]`
- `[cli.rs:cmd_status]`
- `[cli.rs:cmd_emit]`
- `[cli.rs:cmd_export]`

## Invariants
- [gzip.rs:313]: `assert!(`
- [pyutil.rs:319]: `/// Non-numbers compare as absent: Python would raise TypeError there, which`
- [pyutil.rs:343]: `assert!(py_int(&J::str("12.5")).is_err());`
- [pyutil.rs:344]: `assert!(py_int(&J::Null).is_err());`
- [sys.rs:457]: `assert!(u`
- [telemetry_loader.rs:175]: `assert!(contains(b"def process_event(data):", MARKER));`
- [telemetry_loader.rs:176]: `assert!(!contains(b"404: Not Found", MARKER));`

## Side Effects
- [cli.rs:405]: `<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DT...`
- [http_client.rs:21]: `//! Fail-safe OTLP/HTTP transport (`http_client.py`, and the copies inlined in`
- [http_client.rs:24]: `//! `http://` goes over a `TcpStream` directly. std has no TLS, so `https://`,`
- [http_client.rs:26]: `//! `curl`. Python's `urlopen` behaviour is kept where it shows: one attempt,`
- [otlp_builder.rs:21]: `//! OTLP/HTTP JSON payload builder (`otlp_builder.py`).`
- [sys.rs:22]: `//! hostname, uid, `os.access`, randomness, clocks, `subprocess.run(timeout=)`,`
- [sys.rs:344]: `Spawn(std::io::Error),`
- [sys.rs:345]: `/// `subprocess.TimeoutExpired`: killed after the deadline.`
- [telemetry_loader.rs:30]: `//! download attempts (urllib verified, urllib unverified, curl) become curl`
- [telemetry_loader.rs:31]: `//! verified, curl unverified, plain curl, since std has no TLS.`

## Verification
- Run: `bazel test //tools/antigravity-telemetry/src/...`
