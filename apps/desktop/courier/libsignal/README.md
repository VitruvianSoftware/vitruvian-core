<!--
Copyright 2026 VitruvianSoftware
Upstream: https://github.com/signalapp/libsignal (AGPL-3.0-only); this
directory is build glue for it, under the same licence.
SPDX-License-Identifier: AGPL-3.0-only
-->

# libsignal (Signal's Rust library), built by Bazel

Courier's Signal bridge (mautrix-signal) calls Signal's Rust library through
cgo. This directory builds that library, `libsignal_ffi.a`, from source inside
Bazel, so nothing prebuilt is downloaded and no `cargo` is needed.

What Go links is `//apps/desktop/courier/libsignal:signal_ffi`. It is macOS only
(arm64 and x86_64), built on an Apple-silicon Mac.

The guard is `//apps/desktop/courier/engine/internal/networks:networks_test`:
it calls into the library and checks a real signature round trip.
Run it with `bazel test`. Plain `go test ./...` on a Mac fails to link
`internal/networks` (`ld: library 'signal_ffi' not found`): upstream
libsignalgo expects a prebuilt `-lsignal_ffi`, and the patch that points it at
this build applies only under Bazel.

## What is pinned

| Piece | Version | Where |
|---|---|---|
| libsignal | v0.102.2, commit `8fc2113b` (what mautrix-signal v0.2609.0 expects) | `Cargo.toml`, `Cargo.lock` |
| Rust | 1.98.1 (libsignal's `rust-toolchain`) | `MODULE.bazel` |
| Signal's BoringSSL fork | `signalapp/boring` tag `signal-v5.2.0` | `Cargo.lock` |
| Google BoringSSL | commit `e2a57cfb` (the fork's submodule) + `boring-pq.patch` | `MODULE.bazel` (`@signal_boringssl`) |

The rest of the repository keeps Rust 1.75.0. The 1.98.1 toolchain is only
picked when the `:rust_1_98_1` flag is on, and only `:signal_ffi_rust_1_98_1`
turns it on (a Bazel transition). Targets here that only make sense under that
flag are marked incompatible elsewhere, so `bazel build //...` skips them.

## How the pieces fit

1. `Cargo.toml` is a one-package Cargo workspace that depends on libsignal's
   own crates as git dependencies. `MODULE.bazel` reads it with rules_rs
   (`crate.from_cargo(name = "libsignal_crates")`), which turns every crate,
   libsignal's included, into a Bazel target with its build script.
2. `lib.rs` is libsignal-ffi's crate root (one line, as upstream).
   `:signal_ffi_rust` compiles it as a `rust_static_library` named
   `libsignal_ffi.a`.
3. BoringSSL: `boring-sys` would normally run CMake on a git submodule.
   Instead Bazel compiles `@signal_boringssl` with BoringSSL's own Bazel
   rules, `:boringssl_prefix` lays it out as `lib/` + `include/`, and
   boring-sys is pointed at it with `BORING_BSSL_PATH`. Its bindgen step uses
   libclang from the repo's LLVM toolchain.
4. protoc: several libsignal crates generate code from `.proto` files at build
   time. `:protoc` is the protobuf module's protoc with its well-known types
   beside it.
5. Go: a patch (`tools/go_deps/mautrix-signal-libsignal-ffi.patch`) makes
   libsignalgo link `:signal_ffi` instead of looking for `-lsignal_ffi` on
   the linker path.

The per-crate fixes (`crate.annotation` in `MODULE.bazel`) each carry a
comment saying why they exist.

## Changing the pin

When mautrix-signal is bumped, its `pkg/libsignalgo/signalversion` says which
libsignal it wants; the link test fails if it no longer matches.

1. Change the commit in `Cargo.toml` (both lines) to the new libsignal tag.
2. Rebuild `Cargo.lock` from libsignal's own lock, so crates.io versions match
   upstream: copy upstream's `Cargo.lock` next to a copy of `Cargo.toml` and
   `lib.rs` in a scratch directory, run `cargo metadata --format-version 1`
   there, and copy the resulting lock back. (This is the one step that needs
   cargo; the build itself never does.) Re-apply any security bumps listed
   below if still needed, and run osv-scanner on the new lock.
3. Update the Rust version and checksums in `MODULE.bazel` if libsignal's
   `rust-toolchain` changed, and `@signal_boringssl` plus `boring-pq.patch` if
   the boring fork's tag changed.
4. Update `builtLibsignalVersion` in the link test, then run it.

## Deliberate differences from upstream

- `Cargo.lock` takes rustls 0.23.46 and rustls-webpki 0.103.16 instead of
  upstream's 0.23.41 / 0.103.13, to clear RUSTSEC-2026-0285, -0346, -0348,
  -0349 and -0382 (patch releases, same API).
- `Cargo.lock` takes ctutils 0.4.4, tokio 1.53.3 and webpki-root-certs 1.0.10
  instead of upstream's 0.4.2 / 1.52.3 / 1.0.8, to clear RUSTSEC-2026-0385,
  -0386 and -0383.
- `Cargo.lock` is cargo-generated, so it carries cargo's header rather than a
  licence header.
