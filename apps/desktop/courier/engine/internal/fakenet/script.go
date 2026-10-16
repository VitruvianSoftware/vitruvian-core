// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package fakenet

import (
	"context"
	"errors"
	"maps"
	"sync"

	"maunium.net/go/mautrix/bridgev2"
)

// ScriptFlow is the login flow ID of the scripted login. Setting Network.Script makes CreateLogin return it.
const ScriptFlow = "script"

// ScriptedLogin is a login process that plays back the steps a test gives it, in order: Start returns
// Steps[0], then each Wait, SubmitUserInput or SubmitCookies returns the next one. It records what was
// submitted and whether Cancel ran, so a test can check both.
type ScriptedLogin struct {
	Steps []*bridgev2.LoginStep
	// Hold, when set, makes Wait block until it is closed, the login is cancelled or the context ends,
	// the way a real network waits for a phone.
	Hold chan struct{}

	mu        sync.Mutex
	next      int
	submitted []map[string]string
	override  *bridgev2.UserLogin
	cancelled int
	done      chan struct{} // closed by the first Cancel
	closeOnce sync.Once
}

var (
	_ bridgev2.LoginProcessWithOverride   = (*ScriptedLogin)(nil)
	_ bridgev2.LoginProcessDisplayAndWait = (*ScriptedLogin)(nil)
	_ bridgev2.LoginProcessUserInput      = (*ScriptedLogin)(nil)
	_ bridgev2.LoginProcessCookies        = (*ScriptedLogin)(nil)
)

func (s *ScriptedLogin) step() (*bridgev2.LoginStep, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.next >= len(s.Steps) {
		return nil, errors.New("fakenet: the login script has no step left")
	}
	st := s.Steps[s.next]
	s.next++
	return st, nil
}

func (s *ScriptedLogin) Start(context.Context) (*bridgev2.LoginStep, error) { return s.step() }

// StartWithOverride is what a connector offers for signing in again to a login that exists.
func (s *ScriptedLogin) StartWithOverride(_ context.Context, override *bridgev2.UserLogin) (*bridgev2.LoginStep, error) {
	s.mu.Lock()
	s.override = override
	s.mu.Unlock()
	return s.step()
}

func (s *ScriptedLogin) Wait(ctx context.Context) (*bridgev2.LoginStep, error) {
	if s.Hold != nil {
		select {
		case <-s.Hold:
		case <-s.doneChan():
			return nil, errors.New("fakenet: login cancelled")
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	return s.step()
}

func (s *ScriptedLogin) SubmitUserInput(_ context.Context, in map[string]string) (*bridgev2.LoginStep, error) {
	s.record(in)
	return s.step()
}

func (s *ScriptedLogin) SubmitCookies(_ context.Context, in map[string]string) (*bridgev2.LoginStep, error) {
	s.record(in)
	return s.step()
}

func (s *ScriptedLogin) record(in map[string]string) {
	s.mu.Lock()
	s.submitted = append(s.submitted, maps.Clone(in))
	s.mu.Unlock()
}

func (s *ScriptedLogin) Cancel() {
	s.mu.Lock()
	s.cancelled++
	s.mu.Unlock()
	s.closeOnce.Do(func() { close(s.doneChan()) })
}

// doneChan returns the channel the first Cancel closes.
func (s *ScriptedLogin) doneChan() chan struct{} {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.done == nil {
		s.done = make(chan struct{})
	}
	return s.done
}

// Submitted lists what each Submit call received, in order.
func (s *ScriptedLogin) Submitted() []map[string]string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]map[string]string(nil), s.submitted...)
}

// Cancelled is how many times Cancel ran.
func (s *ScriptedLogin) Cancelled() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.cancelled
}

// Override is the login StartWithOverride was given, or nil if it was not used.
func (s *ScriptedLogin) Override() *bridgev2.UserLogin {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.override
}
