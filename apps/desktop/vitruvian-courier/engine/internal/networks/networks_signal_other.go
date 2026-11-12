// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// libsignal_ffi.a is built for macOS only, so there is no Signal bridge here. See networks_signal_darwin.go.

//go:build !darwin

package networks

// platformNetworks has nothing to add: Signal exists only on macOS.
func platformNetworks() []Network { return nil }
