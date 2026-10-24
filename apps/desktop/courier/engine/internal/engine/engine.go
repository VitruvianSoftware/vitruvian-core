// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package engine runs one bridge host per chat network over courier's single local store.
package engine

import (
	"context"
	"errors"
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

// Engine is the set of running bridge hosts, one per network. The networks start behind it (StartNetworks), one
// at a time, while the app is already being served: until a network's host is up, Status says it is starting.
type Engine struct {
	store *store.Store

	mu     sync.Mutex // guards hosts, order, status and stopped
	hosts  map[string]*host.Host
	order  []string          // the running networks, in start order
	status map[string]Status // a network that isn't running: starting, or why it won't run this session
	// stopped is set by Stop: no StartNetworks starts anything after it.
	stopped bool
	// starting counts the StartNetworks calls in flight; Stop waits for them.
	starting sync.WaitGroup
	stop     sync.Once
}

// Status is where a network is this session.
type Status struct {
	Running  bool
	Starting bool
	// NotStarted is why the network won't run this session; "" while it is starting or running.
	NotStarted string
}

var (
	// ErrStarting is HostForRoom's answer for a chat whose network hasn't started yet; it will.
	ErrStarting = errors.New("is still starting")
	// ErrNotRunning is HostForRoom's answer for a chat whose network won't run this session.
	ErrNotRunning = errors.New("is not running")
	// errStopped is the reason of a network the engine was stopped before it reached.
	errStopped = errors.New("the engine stopped before this network started")
)

// validName is the shape of a network name: it becomes a ghost-ID prefix, where an underscore or a capital
// would break parsing.
var validName = regexp.MustCompile(`^[a-z]+$`)

// New is an engine with no networks yet, over s. Expect and StartNetworks give it its networks.
func New(s *store.Store) *Engine {
	return &Engine{store: s, hosts: map[string]*host.Host{}, status: map[string]Status{}}
}

// Start is New, then StartNetworks: every network it can is running when it returns. Networks that fail are left
// out and reported by name; the ones that started keep running.
func Start(ctx context.Context, dataDir string, s *store.Store, m *media.Store, specs []Spec, log zerolog.Logger) (*Engine, map[string]error) {
	e := New(s)
	return e, e.StartNetworks(ctx, dataDir, m, specs, log)
}

// Expect marks every spec's network Starting, so that one StartNetworks hasn't reached yet says so rather than
// looking stopped (Ruling C7). A caller that serves before it starts the networks calls it first. A name the engine
// already has a status for keeps it.
func (e *Engine) Expect(specs []Spec) {
	e.mu.Lock()
	defer e.mu.Unlock()
	for _, spec := range specs {
		if _, running := e.hosts[spec.Name]; running {
			continue
		}
		if _, known := e.status[spec.Name]; !known {
			e.status[spec.Name] = Status{Starting: true}
		}
	}
}

// StartNetworks starts every network it can, in order, adding each host as it is up. The store hears
// NetworkChanged for a network before its start and again once it is running or has failed, so the app reads the
// accounts again. A network that fails is left out and reported by name, its reason kept for Status; the others
// carry on. It returns when every spec has started or failed, or when ctx ends or Stop is called: those stop only
// more networks starting. A start already under way finishes, and each bridge is started without ctx's
// cancellation, so the bridges outlive the stop signal and are stopped by Stop (Ruling C32).
func (e *Engine) StartNetworks(ctx context.Context, dataDir string, m *media.Store, specs []Spec, log zerolog.Logger) map[string]error {
	errs := map[string]error{}
	e.mu.Lock()
	if e.stopped {
		e.mu.Unlock()
		e.notStarted(specs, errs)
		return errs
	}
	e.starting.Add(1)
	e.mu.Unlock()
	defer e.starting.Done()
	e.Expect(specs)

	bridgeCtx := context.WithoutCancel(ctx)
	for i, spec := range specs {
		if ctx.Err() != nil || e.isStopped() {
			e.notStarted(specs[i:], errs)
			break
		}
		if !validName.MatchString(spec.Name) {
			errs[spec.Name] = fmt.Errorf("invalid network name %q: it must match [a-z]+", spec.Name)
			e.failed(spec.Name, errs[spec.Name])
			continue
		}
		if _, dup := e.Host(spec.Name); dup {
			// Under its own key: errs[name] must stay absent for the network that IS running.
			errs[spec.Name+" (duplicate)"] = fmt.Errorf("network %s is already running; names must be unique", spec.Name)
			continue
		}
		e.store.NetworkChanged(spec.Name) // its account is STARTING
		h, err := startOne(bridgeCtx, dataDir, spec, e.store, m, log)
		if err != nil {
			errs[spec.Name] = err
			e.failed(spec.Name, err)
			continue
		}
		e.mu.Lock()
		e.hosts[spec.Name] = h
		e.order = append(e.order, spec.Name)
		delete(e.status, spec.Name)
		e.mu.Unlock()
		e.store.NetworkChanged(spec.Name)
	}
	return errs
}

// failed keeps why a network didn't start, and tells the store.
func (e *Engine) failed(name string, err error) {
	e.mu.Lock()
	e.status[name] = Status{NotStarted: err.Error()}
	e.mu.Unlock()
	e.store.NetworkChanged(name)
}

// notStarted reports each spec the engine was stopped before it reached, unless it is running already.
func (e *Engine) notStarted(specs []Spec, errs map[string]error) {
	for _, spec := range specs {
		if _, running := e.Host(spec.Name); running {
			continue
		}
		errs[spec.Name] = errStopped
		e.mu.Lock()
		e.status[spec.Name] = Status{NotStarted: errStopped.Error()}
		e.mu.Unlock()
	}
}

func (e *Engine) isStopped() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.stopped
}

// Status says where a network is: running, starting, or not running this session and why. A name the engine was
// never given is the zero Status.
func (e *Engine) Status(name string) Status {
	e.mu.Lock()
	defer e.mu.Unlock()
	if _, ok := e.hosts[name]; ok {
		return Status{Running: true}
	}
	return e.status[name]
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
	e.mu.Lock()
	defer e.mu.Unlock()
	h, ok := e.hosts[name]
	return h, ok
}

// HostForRoom finds the bridge a room belongs to, by the network recorded on its row. A network that hasn't
// started yet is ErrStarting; one that won't run this session, or that the engine doesn't know, is ErrNotRunning.
// It never falls back to another network's host.
func (e *Engine) HostForRoom(ctx context.Context, roomID string) (*host.Host, error) {
	room, ok, err := e.store.GetRoom(ctx, roomID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, fmt.Errorf("no chat with id %s", roomID)
	}
	e.mu.Lock()
	h, ok := e.hosts[room.Network]
	st := e.status[room.Network]
	e.mu.Unlock()
	switch {
	case ok:
		return h, nil
	case st.Starting:
		return nil, fmt.Errorf("chat %s is on %s, which %w", roomID, room.Network, ErrStarting)
	default:
		return nil, fmt.Errorf("chat %s is on %s, which %w", roomID, room.Network, ErrNotRunning)
	}
}

// Names lists the running networks, sorted.
func (e *Engine) Names() []string {
	e.mu.Lock()
	names := append([]string(nil), e.order...)
	e.mu.Unlock()
	sort.Strings(names)
	return names
}

// Stop waits for a StartNetworks in flight to return (it starts no more networks once Stop is called), then stops
// the hosts started so far, in reverse start order. Safe to call more than once.
func (e *Engine) Stop() {
	e.stop.Do(func() {
		e.mu.Lock()
		e.stopped = true
		e.mu.Unlock()
		e.starting.Wait()
		e.mu.Lock()
		order := append([]string(nil), e.order...)
		hosts := e.hosts
		e.mu.Unlock()
		for i := len(order) - 1; i >= 0; i-- {
			hosts[order[i]].Stop()
		}
	})
}
