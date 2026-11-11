# Configure Tailscale

## Overview
Component package providing implementation for `tools/cloud-bootstrap/src/configure_tailscale`.

## Interface
- `[lib.rs:HOOK]`
- `[lib.rs:run]`

## Invariants
- [tests.rs:44]: `let rel = std::env::var_os(var).unwrap_or_else(|| panic!("{var} is not set by...`
- [tests.rs:45]: `fs::canonicalize(&rel).unwrap_or_else(|e| panic!("{var}={rel:?}: {e}"))`
- [tests.rs:176]: `assert!(`

## Side Effects
- [lib.rs:80]: `# forced through an HTTP/HTTPS proxy, so raw WireGuard cannot leave. tailscaled`
- [lib.rs:81]: `# dials control + DERP through $HTTPS_PROXY and exposes a local SOCKS5/HTTP p...`
- [lib.rs:84]: `# Reach peers once up:  curl --proxy socks5h://localhost:1055 http://<peer>/`

## Verification
- Run: `bazel test //tools/cloud-bootstrap/src/configure_tailscale/...`
