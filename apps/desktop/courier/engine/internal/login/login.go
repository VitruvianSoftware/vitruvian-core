// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package login steps through a network's sign-in one step at a time, so the app can show each step and send
// back what the person did. It holds the sessions in progress, checks what is submitted before the network
// sees it, and cancels the sign-in on every way out except finishing it, so no half-open pairing is left.
//
// It never logs or returns a value it was given: passwords, tokens and cookies only travel to the connector.
package login

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"sync"
	"time"

	"maunium.net/go/mautrix/bridgev2"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

var (
	// ErrAlreadyLinked means the account a sign-in would sign in again still works: the network's first account, or
	// the one StartOptions.AccountID names. Only an account in a state Reconnect fixes may be signed in again (an
	// expired sign-in, a revoked device). StartOptions.Another signs in beside it instead.
	ErrAlreadyLinked = errors.New("this network is already linked")
	// ErrUnknownLogin means no sign-in has that ID: it finished, was cancelled, timed out or never existed.
	ErrUnknownLogin = errors.New("no sign-in in progress with that ID")
	// ErrBadValue means the request can be corrected and sent again: a value the network won't take, an unknown
	// flow, or a call that doesn't fit the step. The sign-in stays open.
	ErrBadValue = errors.New("that isn't accepted")
	// ErrNotRunning means the network didn't start (Telegram without its credentials, say), so it can't be linked.
	ErrNotRunning = errors.New("this network isn't running")
	// ErrLoginInProgress means the network already has a sign-in in progress. Only one runs per network at a time,
	// so a double-click can't pair two devices; cancelling, finishing or timing out frees the network.
	ErrLoginInProgress = errors.New("a sign-in is already in progress for this network")
)

// DefaultIdleTimeout is how long a sign-in may sit with nobody touching it before it is cancelled.
const DefaultIdleTimeout = 10 * time.Minute

// Driver runs sign-ins. Each has a LoginID; the calls that take one are safe to make from different goroutines.
// Calls on one sign-in run one at a time, except Cancel, which never waits for them.
type Driver struct {
	// IdleTimeout is how long a sign-in may go without a call before its process is cancelled and it is
	// forgotten. A call in progress (a Wait for the phone) is not idle. Zero means DefaultIdleTimeout, and a
	// negative value means never. Set it before the first call.
	IdleTimeout time.Duration

	eng   *engine.Engine
	store *store.Store
	flows func(network string) ([]string, bool)

	mu       sync.Mutex
	sessions map[string]*session
	starting map[string]bool // networks a Start is setting up a sign-in for; guarded by mu
}

// NewDriver makes a driver that starts sign-ins on e's networks. flows says which login flows a network offers,
// preferred first, and whether it is a known network at all (the engine's host does not know, because some
// flows are not listed by the connector). s says whether the account a network has still works, and may be
// nil when that does not matter (every network with an account is then linked).
func NewDriver(e *engine.Engine, s *store.Store, flows func(network string) ([]string, bool)) *Driver {
	return &Driver{IdleTimeout: DefaultIdleTimeout, eng: e, store: s, flows: flows}
}

// session is one sign-in in progress.
type session struct {
	id       string
	network  string
	proc     bridgev2.LoginProcess
	override *bridgev2.UserLogin // the account this sign-in signs in again; nil for a new one

	mu   sync.Mutex          // one call at a time; never held by Cancel
	step *bridgev2.LoginStep // the step the person was last shown; guarded by mu

	// Both guarded by Driver.mu.
	busy  int         // calls in progress or waiting; the idle timer only counts down at zero
	timer *time.Timer // nil when there is no idle timeout
}

// refusal marks an error that is the caller's to fix: the call is answered with it and the sign-in goes on.
type refusal struct{ error }

func (r refusal) Unwrap() error { return r.error }

// StartOptions say which account a sign-in is for, on a network that has one already. The zero value is 4.3's
// rule: the network's first account (by ID), signed in again only when Reconnect would fix it.
//
// An account is bridgev2's user login: its ID (a UserLoginID, a chat's rooms.login_id) is not the LoginID of a
// sign-in in progress (Step.LoginID), so it is called AccountID here (Ruling C16).
type StartOptions struct {
	// Another signs in beside the accounts linked, whatever state they are in: a second account.
	Another bool
	// AccountID signs that account in again: only in a state Reconnect fixes (LOGGED_OUT,
	// BAD_CREDENTIALS, UNKNOWN_ERROR), else ErrAlreadyLinked. An ID that is no account of the network's is
	// ErrBadValue, and so is setting both.
	AccountID string
}

// Start begins signing in to a network with one of its login flows ("" means its first) and returns the first
// step. A flow the network doesn't offer is ErrBadValue; a network that isn't running is ErrNotRunning; a
// network with a sign-in already in progress is ErrLoginInProgress. Which account it is for is o's: the account
// it would sign in again still working is ErrAlreadyLinked.
//
// The account signed in again is handed to the connector as the login to override. A sign-in that completes as that
// same account updates it in place (bridgev2 reuses a login with the same ID, as the pinned bridges' DeleteOnConflict
// path does: a WhatsApp number signed in again replaces itself). One that completes as another account (the person
// scanned with another phone) adds that account, or signs it in again, and the one asked for is never deleted or
// logged out: it keeps its state, its banner and Reconnect, and its chats (Ruling 11; bridgev2's provisioning API
// would delete it). The complete step says which account it became (Step.AccountID, Step.OtherAccount).
func (d *Driver) Start(ctx context.Context, network, flow string, o StartOptions) (Step, error) {
	if d.flows == nil || d.eng == nil {
		return Step{}, errors.New("this driver has no networks to sign in to")
	}
	offered, known := d.flows(network)
	if !known {
		return Step{}, fmt.Errorf("%w: there is no network called %q", ErrBadValue, network)
	}
	if o.Another && o.AccountID != "" {
		return Step{}, fmt.Errorf("%w: a sign-in is either beside the accounts or in place of one", ErrBadValue)
	}
	if flow == "" && len(offered) > 0 {
		flow = offered[0]
	}
	if !slices.Contains(offered, flow) {
		return Step{}, fmt.Errorf("%w: %s has no login flow %q (it has: %v)", ErrBadValue, network, flow, offered)
	}
	h, ok := d.eng.Host(network)
	if !ok {
		return Step{}, fmt.Errorf("%w: %s", ErrNotRunning, network)
	}
	if !d.reserve(network) {
		return Step{}, fmt.Errorf("%w: %s", ErrLoginInProgress, network)
	}
	defer d.unreserve(network) // by then the session is registered, or there is none
	me, err := h.Me(ctx)
	if err != nil {
		return Step{}, err
	}
	override, err := d.signingInAgain(ctx, network, me, o)
	if err != nil {
		return Step{}, err
	}
	proc, err := h.Bridge.Network.CreateLogin(ctx, me, flow)
	if err != nil {
		return Step{}, fmt.Errorf("start %s login (%s): %w", network, flow, err)
	}
	return d.begin(ctx, network, proc, override)
}

// reserve claims a network for one Start, unless a sign-in for it is live or another Start holds it. It is one
// step under d.mu, so of two Starts at once only one gets through.
func (d *Driver) reserve(network string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.starting[network] {
		return false
	}
	for _, s := range d.sessions {
		if s.network == network {
			return false
		}
	}
	if d.starting == nil {
		d.starting = map[string]bool{}
	}
	d.starting[network] = true
	return true
}

func (d *Driver) unreserve(network string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	delete(d.starting, network)
}

// signingInAgain is the account of me's that a sign-in on network signs in again (o): nil for one beside the
// accounts, or on a network with none. Neither option, with an account, is the first one (bridgev2's default
// login: the lowest ID).
func (d *Driver) signingInAgain(ctx context.Context, network string, me *bridgev2.User, o StartOptions) (*bridgev2.UserLogin, error) {
	var account *bridgev2.UserLogin
	switch {
	case o.Another:
		return nil, nil
	case o.AccountID != "":
		for _, l := range me.GetUserLogins() {
			if string(l.ID) == o.AccountID {
				account = l
			}
		}
		if account == nil {
			return nil, fmt.Errorf("%w: %s has no such account", ErrBadValue, network)
		}
	default:
		if account = me.GetDefaultLogin(); account == nil {
			return nil, nil
		}
	}
	if !d.mayRelink(ctx, network, string(account.ID)) {
		return nil, fmt.Errorf("%w: %s", ErrAlreadyLinked, network)
	}
	return account, nil
}

// mayRelink reports whether the network's account accountID is one the person is allowed to sign in again: it has
// signed out, its credentials stopped working, or the bridge hit an error it could not get past (UNKNOWN_ERROR, which
// the app offers Reconnect for). It goes by that account's own state (the store keeps one per login: surprise 6), never
// another account's or the bridge's own. With no state recorded, or state that can't be read, it is working.
func (d *Driver) mayRelink(ctx context.Context, network, accountID string) bool {
	if d.store == nil {
		return false
	}
	states, err := d.store.LoginStates(ctx, network)
	if err != nil {
		return false
	}
	for _, l := range states {
		if l.LoginID != accountID {
			continue
		}
		var st struct {
			StateEvent string `json:"state_event"`
		}
		if json.Unmarshal(l.State, &st) != nil {
			return false
		}
		switch st.StateEvent {
		case "LOGGED_OUT", "BAD_CREDENTIALS", "UNKNOWN_ERROR":
			return true
		}
		return false
	}
	return false
}

// StartProcess steps through a login process that already exists, for a front end that creates its own (the
// test CLI, a test). It does no checks about the network. network is only a label.
func (d *Driver) StartProcess(ctx context.Context, network string, proc bridgev2.LoginProcess) (Step, error) {
	return d.begin(ctx, network, proc, nil)
}

func (d *Driver) begin(ctx context.Context, network string, proc bridgev2.LoginProcess, override *bridgev2.UserLogin) (Step, error) {
	id, err := newLoginID()
	if err != nil {
		proc.Cancel()
		return Step{}, err
	}
	s := &session{id: id, network: network, proc: proc, override: override, busy: 1}
	d.add(s)
	defer d.release(s)
	s.mu.Lock()
	defer s.mu.Unlock()
	step, err := startProcess(ctx, proc, override)
	return d.advance(ctx, s, step, err)
}

func startProcess(ctx context.Context, proc bridgev2.LoginProcess, override *bridgev2.UserLogin) (*bridgev2.LoginStep, error) {
	if override != nil {
		if p, ok := proc.(bridgev2.LoginProcessWithParams); ok {
			return p.StartWithParams(ctx, bridgev2.LoginStartParams{Override: override})
		}
		if p, ok := proc.(bridgev2.LoginProcessWithOverride); ok {
			return p.StartWithOverride(ctx, override)
		}
	}
	return proc.Start(ctx)
}

// Wait waits for the phone to do what a display_and_wait step asked, and returns the next step.
func (d *Driver) Wait(ctx context.Context, loginID string) (Step, error) {
	return d.call(ctx, loginID, func(s *session) (*bridgev2.LoginStep, error) {
		if s.step == nil || s.step.Type != bridgev2.LoginStepTypeDisplayAndWait {
			return nil, refusal{fmt.Errorf("%w: this sign-in isn't waiting for the phone", ErrBadValue)}
		}
		w, ok := s.proc.(bridgev2.LoginProcessDisplayAndWait)
		if !ok {
			return nil, errors.New("this sign-in can't wait for the phone, so it can't be finished from here")
		}
		return w.Wait(ctx)
	})
}

// Submit sends what the person entered for a user_input step (values by field ID), or collected for a cookies
// step (values by cookie ID), and returns the next step. Values are checked first: one the network would refuse
// is ErrBadValue, which names the field but never repeats the value, and the sign-in stays open for another try.
func (d *Driver) Submit(ctx context.Context, loginID string, values map[string]string) (Step, error) {
	return d.call(ctx, loginID, func(s *session) (*bridgev2.LoginStep, error) {
		if s.step == nil {
			return nil, refusal{fmt.Errorf("%w: this sign-in isn't asking for anything", ErrBadValue)}
		}
		switch s.step.Type {
		case bridgev2.LoginStepTypeUserInput:
			p := s.step.UserInputParams
			if p == nil {
				return nil, errors.New("the sign-in asked for typed input but listed no fields")
			}
			checked, err := checkFields(p.Fields, values)
			if err != nil {
				return nil, refusal{err}
			}
			sub, ok := s.proc.(bridgev2.LoginProcessUserInput)
			if !ok {
				return nil, errors.New("this sign-in asks for typed input but can't take it")
			}
			return sub.SubmitUserInput(ctx, checked)
		case bridgev2.LoginStepTypeCookies:
			p := s.step.CookiesParams
			if p == nil {
				return nil, errors.New("the sign-in asked for cookies but listed none")
			}
			checked, err := checkCookies(p.Fields, values)
			if err != nil {
				return nil, refusal{err}
			}
			sub, ok := s.proc.(bridgev2.LoginProcessCookies)
			if !ok {
				return nil, errors.New("this sign-in asks for cookies but can't take them")
			}
			return sub.SubmitCookies(ctx, checked)
		default:
			return nil, refusal{fmt.Errorf("%w: this sign-in isn't asking for typed input or cookies", ErrBadValue)}
		}
	})
}

// Cancel ends a sign-in and tells the network to forget it. It does not wait for a call in progress (a Wait is
// interrupted by it), and it does nothing for a sign-in that is already over.
func (d *Driver) Cancel(loginID string) {
	d.mu.Lock()
	s := d.sessions[loginID]
	d.mu.Unlock()
	if s != nil {
		d.cancelSession(s)
	}
}

// call runs one call on a session, one at a time with the others, and turns the connector's answer into a Step.
func (d *Driver) call(ctx context.Context, loginID string, do func(*session) (*bridgev2.LoginStep, error)) (Step, error) {
	s, err := d.acquire(loginID)
	if err != nil {
		return Step{}, err
	}
	defer d.release(s)
	s.mu.Lock()
	defer s.mu.Unlock()
	if !d.live(s) { // cancelled or timed out while this call waited its turn
		return Step{}, fmt.Errorf("%w: it has ended", ErrUnknownLogin)
	}
	step, err := do(s)
	var r refusal
	if errors.As(err, &r) {
		return Step{}, r.error
	}
	return d.advance(ctx, s, step, err)
}

// advance turns the connector's answer to a call into the app's next step. Every way out except a completed
// login cancels the process, exactly once. s.mu is held.
func (d *Driver) advance(ctx context.Context, s *session, step *bridgev2.LoginStep, err error) (Step, error) {
	if err != nil {
		d.cancelSession(s)
		if cerr := ctx.Err(); cerr != nil {
			return Step{}, cerr
		}
		return Step{}, fmt.Errorf("the sign-in failed: %w", err)
	}
	if step == nil {
		d.cancelSession(s)
		return Step{}, errors.New("the login returned no next step")
	}
	if step.Type == bridgev2.LoginStepTypeComplete {
		d.remove(s)
		out := toStep(s.id, step)
		if step.CompleteParams != nil {
			out.AccountID = string(step.CompleteParams.UserLoginID)
			out.OtherAccount = s.override != nil && out.AccountID != string(s.override.ID)
		}
		return out, nil
	}
	if cerr := ctx.Err(); cerr != nil {
		d.cancelSession(s)
		return Step{}, cerr
	}
	if !d.live(s) { // Cancel ran while the connector was still working
		return Step{}, fmt.Errorf("%w: it was cancelled", ErrUnknownLogin)
	}
	out := toStep(s.id, step)
	if out.Type == StepUnsupported {
		d.cancelSession(s)
		return out, nil
	}
	s.step = step
	return out, nil
}

// add registers a session, which starts out busy (a call is creating it) so its idle timer is not running.
func (d *Driver) add(s *session) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.sessions == nil {
		d.sessions = map[string]*session{}
	}
	d.sessions[s.id] = s
	if idle := d.idle(); idle > 0 {
		s.timer = time.AfterFunc(idle, func() { d.expire(s) })
		s.timer.Stop()
	}
}

func (d *Driver) idle() time.Duration {
	if d.IdleTimeout == 0 {
		return DefaultIdleTimeout
	}
	return d.IdleTimeout
}

// acquire marks a session busy for one call, which stops its idle timer.
func (d *Driver) acquire(id string) (*session, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	s, ok := d.sessions[id]
	if !ok {
		return nil, ErrUnknownLogin
	}
	s.busy++
	if s.timer != nil {
		s.timer.Stop()
	}
	return s, nil
}

// release ends one call's hold on a session and, when none is left, starts the idle timer again.
func (d *Driver) release(s *session) {
	d.mu.Lock()
	defer d.mu.Unlock()
	s.busy--
	if s.busy == 0 && s.timer != nil && d.sessions[s.id] == s {
		s.timer.Reset(d.idle())
	}
}

// expire is the idle timer firing. A call that started in the meantime wins.
func (d *Driver) expire(s *session) {
	d.mu.Lock()
	if s.busy > 0 || d.sessions[s.id] != s {
		d.mu.Unlock()
		return
	}
	delete(d.sessions, s.id)
	d.mu.Unlock()
	s.proc.Cancel()
}

func (d *Driver) live(s *session) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.sessions[s.id] == s
}

// remove forgets a session and reports whether this call was the one that did.
func (d *Driver) remove(s *session) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.sessions[s.id] != s {
		return false
	}
	delete(d.sessions, s.id)
	if s.timer != nil {
		s.timer.Stop()
	}
	return true
}

// cancelSession forgets a session and cancels its process, once however many paths get here.
func (d *Driver) cancelSession(s *session) {
	if d.remove(s) {
		s.proc.Cancel()
	}
}

func newLoginID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
