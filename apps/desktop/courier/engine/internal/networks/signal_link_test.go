// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// libsignal_ffi.a is built for macOS only (//third_party/libsignal), and
// Courier is a macOS app. On other platforms this file is left out, so the
// Linux CI lanes that run every go_test (go-race) compile an empty test rather
// than fail on a library that does not exist there.

//go:build darwin

package networks

import (
	"testing"

	"github.com/stretchr/testify/require"
	"go.mau.fi/mautrix-signal/pkg/libsignalgo"
)

// builtLibsignalVersion is the libsignal release //third_party/libsignal builds
// (commit 8fc2113b in MODULE.bazel and third_party/libsignal/Cargo.toml).
// libsignalgo's C header must come from the same release, or calls cross a
// mismatched ABI. Bumping mautrix-signal can move it: re-pin libsignal too.
const builtLibsignalVersion = "v0.102.2"

// TestSignalLinksLibsignalFFI is the guard that the Signal bridge can link
// Signal's Rust library: it calls into libsignal_ffi.a through libsignalgo's
// cgo bindings and checks a real signature round trip.
func TestSignalLinksLibsignalFFI(t *testing.T) {
	require.Equal(t, builtLibsignalVersion, libsignalgo.Version,
		"mautrix-signal's libsignalgo expects a different libsignal than //third_party/libsignal builds")

	primary, err := libsignalgo.GenerateIdentityKeyPair()
	require.NoError(t, err)
	secondary, err := libsignalgo.GenerateIdentityKeyPair()
	require.NoError(t, err)

	serialized, err := primary.Serialize()
	require.NoError(t, err)
	require.NotEmpty(t, serialized)

	signature, err := secondary.SignAlternateIdentity(primary.GetIdentityKey())
	require.NoError(t, err)

	verified, err := secondary.GetIdentityKey().VerifyAlternateIdentity(primary.GetIdentityKey(), signature)
	require.NoError(t, err)
	require.True(t, verified, "a signature libsignal just made must verify")

	verified, err = primary.GetIdentityKey().VerifyAlternateIdentity(primary.GetIdentityKey(), signature)
	require.NoError(t, err)
	require.False(t, verified, "the signature must not verify against the wrong key")
}
