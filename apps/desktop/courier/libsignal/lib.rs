// Upstream: https://github.com/signalapp/libsignal, rust/bridge/ffi/src/lib.rs
// SPDX-License-Identifier: AGPL-3.0-only
//
// The crate root of libsignal-ffi, the static library mautrix-signal's
// libsignalgo links as -lsignal_ffi. Upstream's lib.rs is this one line: all
// the exported `signal_*` C functions live in libsignal-ffi-impl.

extern crate libsignal_ffi_impl;
