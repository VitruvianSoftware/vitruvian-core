// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Signal does its encryption through Signal's own Rust library, libsignal_ffi.a, which is built for macOS only
// (//apps/desktop/courier/libsignal; see docs/m2-libsignal.md). Courier is a macOS app, so Signal is registered here, in a
// file only darwin builds. Nothing that Linux CI compiles imports mautrix-signal, so those lanes never look for a
// library that does not exist there.

//go:build darwin

package networks

import (
	"fmt"

	signal "go.mau.fi/mautrix-signal/pkg/connector"
	"maunium.net/go/mautrix/bridgev2"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/gchat"
)

// platformNetworks lists the networks that exist only on this platform, after the portable ones in All.
func platformNetworks() []Network {
	return []Network{
		{
			Name: "signal", DisplayName: "Signal",
			ModulePath: "go.mau.fi/mautrix-signal",
			// qr is the only flow mautrix-signal has (GetLoginFlows): Courier shows a QR code and the user scans it
			// from Signal on their phone under Settings, Linked devices.
			Flows: []string{"qr"},
			Spec:  signalSpec,
		},
		{
			Name: "gchat", DisplayName: "Google Chat",
			ModulePath: "maunium.net/go/mautrix",
			Flows:      []string{"cookies"},
			Spec:       gchatSpec,
		},
	}
}

func gchatSpec() (engine.Spec, error) {
	return engine.Spec{
		Name:        "gchat",
		DisplayName: "Google Chat",
		ModulePath:  "maunium.net/go/mautrix",
		Connector:   func() (bridgev2.NetworkConnector, error) { return gchat.NewConnector(), nil },
	}, nil
}

// signalSpec is Signal's example config with one change: polls arrive as polls (extev_polls), not as text asking
// people to vote on the phone.
func signalSpec() (engine.Spec, error) {
	return engine.Spec{
		Name:        "signal",
		DisplayName: "Signal",
		ModulePath:  "go.mau.fi/mautrix-signal",
		Connector:   func() (bridgev2.NetworkConnector, error) { return &signal.SignalConnector{}, nil },
		Configure: func(data any) error {
			cfg, ok := data.(*signal.SignalConfig)
			if !ok {
				return fmt.Errorf("unexpected Signal config type %T", data)
			}
			cfg.ExtEvPolls = true
			return nil
		},
	}, nil
}
