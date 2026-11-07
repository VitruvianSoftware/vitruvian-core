// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//go:build courierseed

package main

import (
	"context"
	"fmt"
	"time"

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix/bridgev2"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/networks"
	"github.com/VitruvianSoftware/courier/engine/internal/seed"
)

// seedEnv names the scenario file the test copy's engine plays (apps/desktop/courier/seed).
const seedEnv = "COURIER_SEED"

// seedSetup is the test copy's (courier-engine-seeded, built with the courierseed tag). With COURIER_SEED naming a
// scenario file, and no networks given already (a test's cfg.nets), the engine runs a fake network for each network
// the scenario names, under that network's real name ("whatsapp", so its icon and name match), instead of the real
// bridges. Each fake is told the scenario's chats and people on every start, so a later start describes them the
// same way, and the logins the first start made load again. The scenario itself plays only into a data directory it
// has not been played into (seed.Played): the returned afterStart plays it once the networks are up, then marks the
// directory. Without COURIER_SEED nothing changes.
func seedSetup(cfg *config, getenv func(string) string) (afterStart, error) {
	path := getenv(seedEnv)
	if path == "" || cfg.nets != nil {
		return nil, nil
	}
	sc, err := seed.Load(path)
	if err != nil {
		return nil, err
	}
	fakes := map[string]*fakenet.Network{}
	for _, name := range sc.Networks() {
		display := name
		if real, ok := networks.Get(name); ok {
			display = real.DisplayName
		}
		n := fakenet.New()
		n.BridgeName = &bridgev2.BridgeName{DisplayName: display, NetworkID: name, BeeperBridgeType: name}
		fakes[name] = n
		// No login flows: a fake can't sign anyone in, so Add Account offers none.
		cfg.nets = append(cfg.nets, networks.Network{
			Name: name, DisplayName: display,
			Spec: func() (engine.Spec, error) {
				return engine.Spec{Name: name, DisplayName: display, Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }}, nil
			},
		})
	}
	if err = sc.Prepare(fakes); err != nil {
		return nil, err
	}
	played, err := seed.Played(cfg.data)
	if err != nil || played {
		return nil, err
	}
	data := cfg.data
	return func(ctx context.Context, eng *engine.Engine, log zerolog.Logger) {
		if err := playSeed(ctx, eng, sc, fakes, data, path); err != nil {
			log.Error().Err(err).Msg("couldn't play the seed scenario")
		}
	}, nil
}

func playSeed(ctx context.Context, eng *engine.Engine, sc *seed.Scenario, fakes map[string]*fakenet.Network, data, path string) error {
	bridges := map[string]*bridgev2.Bridge{}
	for name := range fakes {
		h, ok := eng.Host(name)
		if !ok {
			return fmt.Errorf("%s did not start", name)
		}
		// Only into an empty data directory: one that already has accounts (a playback a quit cut short) is left as
		// it is rather than seeded twice.
		logins, err := h.Bridge.DB.UserLogin.GetAllForUser(ctx, ids.Me)
		if err != nil {
			return err
		}
		if len(logins) > 0 {
			return fmt.Errorf("%s already has accounts in this data folder; start from an empty one", name)
		}
		bridges[name] = h.Bridge
	}
	if err := sc.Play(ctx, bridges, fakes, time.Now()); err != nil {
		return err
	}
	return seed.MarkPlayed(data, path)
}
