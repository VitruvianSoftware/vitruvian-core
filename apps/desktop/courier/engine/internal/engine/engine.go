// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package engine runs one bridge host per chat network over courier's single local store.
package engine

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"runtime/debug"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/status"

	enginemod "github.com/VitruvianSoftware/courier/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/localmatrix"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Spec says how to build and configure one network's bridge.
type Spec struct {
	Name        string
	DisplayName string
	ModulePath  string
	Connector   func() (bridgev2.NetworkConnector, error)
	Configure   func(networkConfig any) error // may be nil
}

// BridgeReport describes a network bridge's runtime state and build version.
type BridgeReport struct {
	Network     string
	DisplayName string
	BridgeID    string
	ModulePath  string
	Version     string
	MautrixVer  string
	State       string
	Error       string
	Message     string
	StartedAtMS int64
}

// LoginHook lets the engine cancel active interactive logins and update host references when restarting a bridge.
type LoginHook interface {
	CancelNetwork(network string)
	SetHost(network string, h *host.Host)
}

// Engine is the set of running bridge hosts, one per network. The networks start behind it (StartNetworks), one
// at a time, while the app is already being served: until a network's host is up, Status says it is starting.
type Engine struct {
	store *store.Store

	hostsMu   sync.RWMutex // guards hosts, order, status, specs, specOrder, startedAt, dataDir, media, log, login and stopped
	restartMu sync.Mutex   // serializes RestartNetwork calls
	hosts     map[string]*host.Host
	order     []string          // the running networks, in start order
	status    map[string]Status // a network that isn't running: starting, or why it won't run this session
	specs     map[string]Spec
	specOrder []string
	startedAt map[string]time.Time
	dataDir   string
	media     *media.Store
	log       zerolog.Logger
	login     LoginHook
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
	return &Engine{
		store:     s,
		hosts:     map[string]*host.Host{},
		status:    map[string]Status{},
		specs:     map[string]Spec{},
		startedAt: map[string]time.Time{},
	}
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
	e.hostsMu.Lock()
	defer e.hostsMu.Unlock()
	for _, spec := range specs {
		if validName.MatchString(spec.Name) {
			if _, seen := e.specs[spec.Name]; !seen {
				e.specs[spec.Name] = spec
				e.specOrder = append(e.specOrder, spec.Name)
			}
		}
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
// accounts again; and a "spaces" change once it is running or has failed, so the app reads the account spaces again
// (a linked network that failed keeps its space: Ruling 3). A network that fails is left out and reported by name,
// its reason kept for Status; the others carry on. It returns when every spec has started or failed, or when ctx ends
// or Stop is called: those stop only more networks starting. A start already under way finishes, and each bridge is
// started without ctx's cancellation, so the bridges outlive the stop signal and are stopped by Stop (Ruling C32).
func (e *Engine) StartNetworks(ctx context.Context, dataDir string, m *media.Store, specs []Spec, log zerolog.Logger) map[string]error {
	errs := map[string]error{}
	e.hostsMu.Lock()
	if e.stopped {
		e.hostsMu.Unlock()
		e.notStarted(specs, errs)
		return errs
	}
	e.dataDir = dataDir
	e.media = m
	e.log = log
	alreadyRunning := make(map[string]bool, len(e.hosts))
	for name := range e.hosts {
		alreadyRunning[name] = true
	}
	e.starting.Add(1)
	e.hostsMu.Unlock()
	defer e.starting.Done()
	e.Expect(specs)

	bridgeCtx := context.WithoutCancel(ctx)
	seenInSpecs := make(map[string]bool, len(specs))
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
		if seenInSpecs[spec.Name] || alreadyRunning[spec.Name] {
			// Under its own key: errs[name] must stay absent for the network that IS running.
			errs[spec.Name+" (duplicate)"] = fmt.Errorf("network %s is already running; names must be unique", spec.Name)
			continue
		}
		seenInSpecs[spec.Name] = true

		e.restartMu.Lock()
		if ctx.Err() != nil || e.isStopped() {
			e.restartMu.Unlock()
			e.notStarted(specs[i:], errs)
			break
		}
		if _, running := e.Host(spec.Name); running {
			// Started concurrently by RestartNetwork while StartNetworks was on an earlier spec.
			e.restartMu.Unlock()
			continue
		}
		e.store.NetworkChanged(spec.Name) // its account is STARTING
		h, err := startOne(bridgeCtx, dataDir, spec, e.store, m, log)
		if err != nil {
			errs[spec.Name] = err
			e.failed(spec.Name, err)
			e.restartMu.Unlock()
			continue
		}
		e.pruneLoginStates(bridgeCtx, h, log)
		e.fillRoomLogins(bridgeCtx, h, log)
		e.hostsMu.Lock()
		e.hosts[spec.Name] = h
		if !slices.Contains(e.order, spec.Name) {
			e.order = append(e.order, spec.Name)
		}
		delete(e.status, spec.Name)
		e.startedAt[spec.Name] = time.Now()
		loginHook := e.login
		e.hostsMu.Unlock()
		if loginHook != nil {
			loginHook.SetHost(spec.Name, h)
		}
		e.store.NetworkChanged(spec.Name)
		e.store.SpacesChanged() // a linked account's space is now the running network's
		e.restartMu.Unlock()
	}
	return errs
}

// pruneLoginStates drops the stored states of h's network's logins its bridge no longer has (an account deleted from
// the network's own side), now that the bridge has loaded its accounts, so a stale row can't count as an account while
// the network starts next time. A failure only costs that: it is logged, by network, and the start goes on.
func (e *Engine) pruneLoginStates(ctx context.Context, h *host.Host, log zerolog.Logger) {
	logins, err := h.Bridge.DB.UserLogin.GetAllForUser(ctx, ids.Me)
	if err == nil {
		keep := make([]string, 0, len(logins))
		for _, l := range logins {
			keep = append(keep, string(l.ID))
		}
		_, err = e.store.PruneLoginStates(ctx, h.Network, keep)
	}
	if err != nil {
		log.Warn().Err(err).Str("network", h.Network).Msg("couldn't drop the states of accounts the bridge no longer has")
	}
}

// fillRoomLogins gives h's network's chats that have no login (kept before milestone 4.4, or before a second account
// was added) the receiver of their portal, read from the bridge's own database in one query. bridgev2 resends the
// bridge info that carries it only when a chat's name or avatar changes, so without this those chats would never get
// their account tag. A chat that has a login keeps it; a portal every login shares (receiver "") or a receiver over
// localmatrix.MaxReceiverBytes gives none. Idempotent: a second start finds nothing to fill. A failure only costs
// the tags: it is logged, by network, and the start goes on.
func (e *Engine) fillRoomLogins(ctx context.Context, h *host.Host, log zerolog.Logger) {
	portals, err := h.Bridge.DB.Portal.GetAllWithMXID(ctx)
	if err == nil {
		logins := make(map[string]string, len(portals))
		for _, p := range portals {
			if p.MXID != "" && p.Receiver != "" && len(p.Receiver) <= localmatrix.MaxReceiverBytes {
				logins[string(p.MXID)] = string(p.Receiver)
			}
		}
		_, err = e.store.FillRoomLogins(ctx, h.Network, logins)
	}
	if err != nil {
		log.Warn().Err(err).Str("network", h.Network).Msg("couldn't fill in which account older chats belong to")
	}
}

// failed keeps why a network didn't start, and tells the store: its accounts changed, and its space may have (a
// linked network keeps it, NOT_STARTED, with its chats: Ruling 3).
func (e *Engine) failed(name string, err error) {
	e.hostsMu.Lock()
	e.status[name] = Status{NotStarted: err.Error()}
	e.hostsMu.Unlock()
	e.store.NetworkChanged(name)
	e.store.SpacesChanged()
}

// notStarted reports each spec the engine was stopped before it reached, unless it is running already.
func (e *Engine) notStarted(specs []Spec, errs map[string]error) {
	for _, spec := range specs {
		if _, running := e.Host(spec.Name); running {
			continue
		}
		errs[spec.Name] = errStopped
		e.failed(spec.Name, errStopped)
	}
}

func (e *Engine) isStopped() bool {
	e.hostsMu.RLock()
	defer e.hostsMu.RUnlock()
	return e.stopped
}

// Status says where a network is: running, starting, or not running this session and why. A name the engine was
// never given is the zero Status.
func (e *Engine) Status(name string) Status {
	e.hostsMu.RLock()
	defer e.hostsMu.RUnlock()
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
	e.hostsMu.RLock()
	defer e.hostsMu.RUnlock()
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
	e.hostsMu.RLock()
	h, ok := e.hosts[room.Network]
	st := e.status[room.Network]
	e.hostsMu.RUnlock()
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
	e.hostsMu.RLock()
	names := append([]string(nil), e.order...)
	e.hostsMu.RUnlock()
	sort.Strings(names)
	return names
}

// Stop waits for a StartNetworks in flight to return (it starts no more networks once Stop is called), then stops
// the hosts started so far, in reverse start order. Safe to call more than once.
func (e *Engine) Stop() {
	e.stop.Do(func() {
		e.hostsMu.Lock()
		e.stopped = true
		e.hostsMu.Unlock()
		e.starting.Wait()
		e.restartMu.Lock()
		defer e.restartMu.Unlock()
		e.hostsMu.RLock()
		order := append([]string(nil), e.order...)
		hosts := make(map[string]*host.Host, len(e.hosts))
		for k, v := range e.hosts {
			hosts[k] = v
		}
		e.hostsMu.RUnlock()
		for i := len(order) - 1; i >= 0; i-- {
			if h := hosts[order[i]]; h != nil {
				h.Stop()
			}
		}
	})
}

// SetLogin attaches the login driver hook so RestartNetwork can cancel active logins and update host references.
func (e *Engine) SetLogin(l LoginHook) {
	e.hostsMu.Lock()
	e.login = l
	hosts := make(map[string]*host.Host, len(e.hosts))
	for k, v := range e.hosts {
		hosts[k] = v
	}
	e.hostsMu.Unlock()
	if l != nil {
		for k, h := range hosts {
			l.SetHost(k, h)
		}
	}
}

// parseGoModVersions extracts module versions from a go.mod file's require and replace directives.
func parseGoModVersions(raw string) map[string]string {
	out := map[string]string{}
	inRequire := false
	inReplace := false
	for _, line := range strings.Split(raw, "\n") {
		if idx := strings.Index(line, "//"); idx >= 0 {
			line = line[:idx]
		}
		line = strings.TrimSpace(line)
		switch {
		case line == "":
			continue
		case line == "require (":
			inRequire = true
			continue
		case line == "replace (":
			inReplace = true
			continue
		case line == ")":
			inRequire = false
			inReplace = false
			continue
		}
		if inReplace || strings.HasPrefix(line, "replace ") {
			rest := strings.TrimPrefix(line, "replace ")
			if parts := strings.SplitN(rest, "=>", 2); len(parts) == 2 {
				left := strings.Fields(parts[0])
				right := strings.Fields(parts[1])
				if len(left) >= 1 && len(right) >= 2 {
					out[left[0]] = right[1]
				}
			}
			continue
		}
		if inRequire {
			if fields := strings.Fields(line); len(fields) >= 2 {
				out[fields[0]] = fields[1]
			}
			continue
		}
		if strings.HasPrefix(line, "require ") {
			if fields := strings.Fields(strings.TrimPrefix(line, "require ")); len(fields) >= 2 {
				out[fields[0]] = fields[1]
			}
		}
	}
	return out
}

// ModuleVersions returns map[modulePath]version parsed at build time from the embedded go.mod,
// overlaid with runtime/debug.ReadBuildInfo() when available.
func ModuleVersions() map[string]string {
	out := parseGoModVersions(enginemod.GoMod)
	if bi, ok := debug.ReadBuildInfo(); ok && bi != nil {
		for _, dep := range bi.Deps {
			ver := dep.Version
			if dep.Replace != nil && dep.Replace.Version != "" {
				ver = dep.Replace.Version
			}
			if ver != "" && ver != "(devel)" {
				out[dep.Path] = ver
			}
		}
	}
	return out
}

// Bridges returns runtime status and build version metadata for every registered network bridge.
func (e *Engine) Bridges(ctx context.Context) ([]BridgeReport, error) {
	e.hostsMu.RLock()
	names := append([]string(nil), e.specOrder...)
	for _, n := range e.order {
		if !slices.Contains(names, n) {
			names = append(names, n)
		}
	}
	specs := make(map[string]Spec, len(e.specs))
	for k, v := range e.specs {
		specs[k] = v
	}
	hosts := make(map[string]*host.Host, len(e.hosts))
	for k, v := range e.hosts {
		hosts[k] = v
	}
	statuses := make(map[string]Status, len(e.status))
	for k, v := range e.status {
		statuses[k] = v
	}
	started := make(map[string]time.Time, len(e.startedAt))
	for k, v := range e.startedAt {
		started[k] = v
	}
	e.hostsMu.RUnlock()

	versions := ModuleVersions()
	mautrixVer := versions["maunium.net/go/mautrix"]
	reports := make([]BridgeReport, 0, len(names))
	for _, name := range names {
		spec := specs[name]
		displayName := spec.DisplayName
		if displayName == "" {
			displayName = name
		}
		modPath := spec.ModulePath
		if modPath == "" && versions["go.mau.fi/mautrix-"+name] != "" {
			modPath = "go.mau.fi/mautrix-" + name
		}
		rep := BridgeReport{
			Network:     name,
			DisplayName: displayName,
			BridgeID:    name,
			ModulePath:  modPath,
			Version:     versions[modPath],
			MautrixVer:  mautrixVer,
		}
		if t := started[name]; !t.IsZero() {
			rep.StartedAtMS = t.UnixMilli()
		}
		st := statuses[name]
		h, running := hosts[name]
		switch {
		case st.Starting:
			rep.State = "STARTING"
		case !running:
			rep.State = "NOT_STARTED"
			rep.Message = st.NotStarted
		default:
			rep.State, rep.Error, rep.Message = e.bridgeStateSummary(ctx, name, h)
		}
		reports = append(reports, rep)
	}
	return reports, nil
}

func (e *Engine) bridgeStateSummary(ctx context.Context, network string, h *host.Host) (state, errCode, message string) {
	if e.store == nil {
		return "UNCONFIGURED", "", ""
	}
	states, err := e.store.LoginStates(ctx, network)
	if err != nil {
		return "UNCONFIGURED", "", ""
	}
	type parsedState struct {
		StateEvent string `json:"state_event"`
		Error      string `json:"error"`
		Message    string `json:"message"`
		Timestamp  int64  `json:"timestamp"`
	}
	var own *parsedState
	var logins []parsedState
	var newestLogin int64
	for _, ls := range states {
		var ps parsedState
		_ = json.Unmarshal(ls.State, &ps)
		if ls.LoginID == "" {
			own = &ps
			continue
		}
		if h != nil && h.Bridge != nil {
			if ul := h.Bridge.GetCachedUserLoginByID(networkid.UserLoginID(ls.LoginID)); ul == nil || ul.UserMXID != ids.Me {
				continue
			}
		}
		logins = append(logins, ps)
		if ps.Timestamp > newestLogin {
			newestLogin = ps.Timestamp
		}
	}
	var chosen parsedState
	switch {
	case len(logins) == 0:
		if own != nil {
			chosen = *own
		}
	case own != nil && own.Timestamp > newestLogin:
		chosen = *own
	default:
		chosen = logins[0]
		found := false
		for _, group := range [][]string{
			{"LOGGED_OUT", "BAD_CREDENTIALS", "UNKNOWN_ERROR"},
			{"CONNECTING", "TRANSIENT_DISCONNECT", "BRIDGE_UNREACHABLE"},
		} {
			for _, l := range logins {
				if slices.Contains(group, l.StateEvent) {
					chosen = l
					found = true
					break
				}
			}
			if found {
				break
			}
		}
	}
	if chosen.StateEvent == "" {
		chosen.StateEvent = "UNCONFIGURED"
	}
	return chosen.StateEvent, chosen.Error, chosen.Message
}

// RestartNetwork stops the running bridge host for name, closes its database, and starts a fresh host.
func (e *Engine) RestartNetwork(ctx context.Context, name string) error {
	e.restartMu.Lock()
	defer e.restartMu.Unlock()

	e.hostsMu.RLock()
	if e.stopped {
		e.hostsMu.RUnlock()
		return fmt.Errorf("%w: %w", errStopped, ErrNotRunning)
	}
	spec, ok := e.specs[name]
	dataDir := e.dataDir
	m := e.media
	log := e.log
	loginHook := e.login
	prevStarted := e.startedAt[name]
	e.hostsMu.RUnlock()
	if !ok {
		return fmt.Errorf("unknown network %q: %w", name, ErrNotRunning)
	}

	if loginHook != nil {
		loginHook.CancelNetwork(name)
	}

	e.hostsMu.Lock()
	old := e.hosts[name]
	delete(e.hosts, name)
	e.status[name] = Status{Starting: true}
	e.hostsMu.Unlock()

	if loginHook != nil {
		loginHook.SetHost(name, nil)
	}
	e.store.NetworkChanged(name)

	if old != nil {
		_ = old.Close()
	}

	bridgeCtx := context.WithoutCancel(ctx)
	h, err := startOne(bridgeCtx, dataDir, spec, e.store, m, log)
	if err != nil {
		e.failed(name, err)
		return err
	}
	e.pruneLoginStates(bridgeCtx, h, log)
	e.fillRoomLogins(bridgeCtx, h, log)

	now := time.Now()
	if !prevStarted.IsZero() && now.UnixMilli() <= prevStarted.UnixMilli() {
		now = prevStarted.Add(time.Millisecond)
	}

	e.hostsMu.Lock()
	e.hosts[name] = h
	if !slices.Contains(e.order, name) {
		e.order = append(e.order, name)
	}
	delete(e.status, name)
	e.startedAt[name] = now
	e.hostsMu.Unlock()

	if loginHook != nil {
		loginHook.SetHost(name, h)
	}
	e.store.NetworkChanged(name)
	e.store.SpacesChanged()
	return nil
}

// RemoveAccount disconnects or remotely logs out accountID on network, deletes its user_login row in the bridge DB,
// and cleans up login_state, sub_accounts, and (when deleteChats is true) rooms and events in courier.db.
func (e *Engine) RemoveAccount(ctx context.Context, network, accountID string, logoutRemote, deleteChats bool) error {
	if accountID == "" {
		return errors.New("account_id is required")
	}
	e.restartMu.Lock()
	defer e.restartMu.Unlock()

	h, ok := e.Host(network)
	if ok && h != nil && h.Bridge != nil {
		loginID := networkid.UserLoginID(accountID)
		if ul := h.Bridge.GetCachedUserLoginByID(loginID); ul != nil {
			ul.Delete(ctx, status.BridgeState{StateEvent: status.StateLoggedOut}, bridgev2.DeleteOpts{
				LogoutRemote:     logoutRemote,
				DontCleanupRooms: !deleteChats,
				BlockingCleanup:  true,
			})
		} else {
			dbUL, err := h.Bridge.DB.UserLogin.GetByID(ctx, loginID)
			if err != nil {
				return err
			}
			if dbUL != nil {
				if err := h.Bridge.DB.UserLogin.Delete(ctx, loginID); err != nil {
					return err
				}
			} else {
				found, err := e.hasLoginState(ctx, network, accountID)
				if err != nil {
					return err
				}
				if !found {
					return store.ErrNotFound
				}
			}
		}
	} else {
		e.hostsMu.RLock()
		dataDir := e.dataDir
		e.hostsMu.RUnlock()
		deletedOffline, err := host.DeleteOfflineUserLogin(ctx, dataDir, network, accountID)
		if err != nil {
			return err
		}
		found, err := e.hasLoginState(ctx, network, accountID)
		if err != nil {
			return err
		}
		if !deletedOffline && !found {
			return store.ErrNotFound
		}
	}
	if err := e.store.RemoveAccountData(ctx, network, accountID, deleteChats); err != nil {
		return err
	}
	e.store.NetworkChanged(network)
	e.store.SpacesChanged()
	return nil
}

func (e *Engine) hasLoginState(ctx context.Context, network, accountID string) (bool, error) {
	states, err := e.store.LoginStates(ctx, network)
	if err != nil {
		return false, err
	}
	for _, st := range states {
		if st.LoginID == accountID {
			return true, nil
		}
	}
	return false, nil
}

// RefreshSubAccounts scans the bridge DB's portal (room_type = 'space') and ghost (is_bot = 1) tables
// alongside courier.db's bot DM rooms and returns the updated sub_accounts list for (network, accountID).
func (e *Engine) RefreshSubAccounts(ctx context.Context, network, accountID string) ([]store.SubAccount, error) {
	if h, ok := e.Host(network); ok && h.Bridge != nil && h.Bridge.DB != nil {
		portals, err := h.Bridge.DB.Portal.GetAllWithMXID(ctx)
		if err != nil {
			return nil, err
		}
		spaceMXIDByKey := map[networkid.PortalKey]string{}
		for _, p := range portals {
			if p.MXID != "" && p.RoomType == database.RoomTypeSpace {
				spaceMXIDByKey[p.PortalKey] = string(p.MXID)
			}
		}
		for _, p := range portals {
			if p.MXID == "" {
				continue
			}
			roomID := string(p.MXID)
			r, roomOK, err := e.store.GetRoom(ctx, roomID)
			if err != nil {
				return nil, err
			}
			loginID := string(p.Receiver)
			if loginID == "" && p.RelayLoginID != "" {
				loginID = string(p.RelayLoginID)
			}
			if loginID == "" && roomOK && r.LoginID != "" {
				loginID = r.LoginID
			}
			if p.RoomType == database.RoomTypeSpace {
				if err := e.store.SetRoomSpace(ctx, roomID, true, ""); err != nil {
					return nil, err
				}
				if loginID == accountID || (loginID == "" && accountID != "") {
					title := p.Name
					if title == "" && roomOK {
						title = r.Name
					}
					avatar := string(p.AvatarMXC)
					if avatar == "" && roomOK {
						avatar = r.AvatarURI
					}
					if err := e.store.UpsertSubAccount(ctx, store.SubAccount{
						Network:     network,
						LoginID:     accountID,
						SubID:       roomID,
						Title:       title,
						AvatarURI:   avatar,
						Kind:        "space",
						Enabled:     true,
						ShowInInbox: "all",
					}); err != nil {
						return nil, err
					}
				}
				continue
			}
			if p.ParentKey.ID != "" {
				if parentMXID, ok := spaceMXIDByKey[p.ParentKey]; ok {
					if err := e.store.SetRoomSpace(ctx, roomID, false, parentMXID); err != nil {
						return nil, err
					}
				} else if parentMXID, ok := spaceMXIDByKey[networkid.PortalKey{ID: p.ParentKey.ID, Receiver: p.Receiver}]; ok {
					if err := e.store.SetRoomSpace(ctx, roomID, false, parentMXID); err != nil {
						return nil, err
					}
				}
			}
			if p.RoomType == database.RoomTypeDM && p.OtherUserID != "" {
				ghost, err := h.Bridge.DB.Ghost.GetByID(ctx, p.OtherUserID)
				if err != nil {
					return nil, err
				}
				if ghost != nil && ghost.IsBot {
					ghostMXID := string(ids.GhostMXID(network, p.OtherUserID))
					if err := e.store.SetProfileExtraMeta(ctx, ghostMXID, ghost.Identifiers, "", true); err != nil {
						return nil, err
					}
					if loginID == accountID {
						title := p.Name
						if title == "" {
							title = ghost.Name
						}
						if title == "" && roomOK {
							title = r.Name
						}
						avatar := string(p.AvatarMXC)
						if avatar == "" {
							avatar = string(ghost.AvatarMXC)
						}
						if avatar == "" && roomOK {
							avatar = r.AvatarURI
						}
						if err := e.store.UpsertSubAccount(ctx, store.SubAccount{
							Network:     network,
							LoginID:     accountID,
							SubID:       roomID,
							Title:       title,
							AvatarURI:   avatar,
							Kind:        "bot",
							Enabled:     true,
							ShowInInbox: "all",
						}); err != nil {
							return nil, err
						}
					}
				}
			}
		}
	}
	return e.store.SyncBotSubAccounts(ctx, network, accountID)
}
