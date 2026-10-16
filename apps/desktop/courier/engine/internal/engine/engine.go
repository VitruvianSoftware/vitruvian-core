// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package engine runs one bridge host per chat network over courier's single local store.
package engine

import (
	"context"
	"fmt"
	"regexp"
	"runtime/debug"
	"sort"
	"sync"

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix/bridgev2"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Spec says how to build and configure one network's bridge.
type Spec struct {
	Name      string
	Connector func() (bridgev2.NetworkConnector, error)
	Configure func(networkConfig any) error // may be nil
}

// Engine is the set of running bridge hosts, one per network.
type Engine struct {
	store *store.Store
	hosts map[string]*host.Host
	order []string
	stop  sync.Once
}

// validName is the shape of a network name: it becomes a ghost-ID prefix, where an underscore or a capital
// would break parsing.
var validName = regexp.MustCompile(`^[a-z]+$`)

// Start starts every network it can. Networks that fail are left out and reported by name;
// the ones that started keep running.
func Start(ctx context.Context, dataDir string, s *store.Store, m *media.Store, specs []Spec, log zerolog.Logger) (*Engine, map[string]error) {
	e := &Engine{store: s, hosts: map[string]*host.Host{}}
	errs := map[string]error{}
	for _, spec := range specs {
		if !validName.MatchString(spec.Name) {
			errs[spec.Name] = fmt.Errorf("invalid network name %q: it must match [a-z]+", spec.Name)
			continue
		}
		if _, dup := e.hosts[spec.Name]; dup {
			// Under its own key: errs[name] must stay absent for the network that IS running.
			errs[spec.Name+" (duplicate)"] = fmt.Errorf("network %s is already running; names must be unique", spec.Name)
			continue
		}
		h, err := startOne(ctx, dataDir, spec, s, m, log)
		if err != nil {
			errs[spec.Name] = err
			continue
		}
		e.hosts[spec.Name] = h
		e.order = append(e.order, spec.Name)
	}
	return e, errs
}

// startOne builds one network's connector and starts its host. A panic while doing so (in the connector's
// constructor, Init or Start, or in bridgev2's own start-up) is caught and returned as that network's error, so
// the other networks still start. Only start-up is covered: a panic later, in a goroutine a bridge starts for
// itself, is not recovered by bridgev2 and still stops the whole engine.
func startOne(ctx context.Context, dataDir string, spec Spec, s *store.Store, m *media.Store, log zerolog.Logger) (h *host.Host, err error) {
	defer func() {
		if r := recover(); r != nil {
			// The stack goes to the log only; the error stays one line for the person reading it.
			log.Error().Str("network", spec.Name).Any("panic", r).Bytes("stack", debug.Stack()).
				Msg("network panicked while starting")
			h, err = nil, fmt.Errorf("%s panicked while starting: %v", spec.Name, r)
		}
	}()
	nc, err := spec.Connector()
	if err != nil {
		return nil, err
	}
	var opts []host.Option
	if spec.Configure != nil {
		opts = append(opts, host.WithConfigure(spec.Configure))
	}
	return host.Start(ctx, dataDir, spec.Name, s, m, nc, log, opts...)
}

// Host returns the running host for a network.
func (e *Engine) Host(name string) (*host.Host, bool) {
	h, ok := e.hosts[name]
	return h, ok
}

// HostForRoom finds the bridge a room belongs to, by the network recorded on its row.
// It never falls back to another network's host.
func (e *Engine) HostForRoom(ctx context.Context, roomID string) (*host.Host, error) {
	room, ok, err := e.store.GetRoom(ctx, roomID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, fmt.Errorf("no chat with id %s", roomID)
	}
	h, ok := e.hosts[room.Network]
	if !ok {
		return nil, fmt.Errorf("chat %s is on %s, which is not running", roomID, room.Network)
	}
	return h, nil
}

// Names lists the running networks, sorted.
func (e *Engine) Names() []string {
	names := append([]string(nil), e.order...)
	sort.Strings(names)
	return names
}

// Stop stops the hosts in reverse start order. Safe to call more than once.
func (e *Engine) Stop() {
	e.stop.Do(func() {
		for i := len(e.order) - 1; i >= 0; i-- {
			e.hosts[e.order[i]].Stop()
		}
	})
}
