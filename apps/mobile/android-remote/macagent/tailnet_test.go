// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package main

import (
	"errors"
	"net"
	"sync"
	"testing"
)

// fakeListener records whether it was closed; nothing is ever accepted.
type fakeListener struct {
	addr   string
	mu     sync.Mutex
	closed bool
}

func (f *fakeListener) Accept() (net.Conn, error) { select {} }
func (f *fakeListener) Close() error {
	f.mu.Lock()
	f.closed = true
	f.mu.Unlock()
	return nil
}
func (f *fakeListener) Addr() net.Addr { return &net.TCPAddr{} }
func (f *fakeListener) isClosed() bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.closed
}

type tailnetHarness struct {
	w       *tailnetWatcher
	ip      string
	failing error
	opened  []*fakeListener
}

func newTailnetHarness() *tailnetHarness {
	h := &tailnetHarness{}
	h.w = &tailnetWatcher{
		port:   "7411",
		lookup: func() (string, bool) { return h.ip, h.ip != "" },
		listen: func(a string) (net.Listener, error) {
			if h.failing != nil {
				return nil, h.failing
			}
			l := &fakeListener{addr: a}
			h.opened = append(h.opened, l)
			return l, nil
		},
		serve: func(net.Listener) {},
	}
	return h
}

// The bug this exists for: the agent starts before Tailscale is up. It must
// start listening on its own once the address appears, with no restart.
func TestTailnetListenerStartsWhenTailscaleComesUpLater(t *testing.T) {
	h := newTailnetHarness()
	h.w.tick()
	if got := h.w.current(); got != "" || len(h.opened) != 0 {
		t.Fatalf("listening with no Tailscale address: %q, %d opened", got, len(h.opened))
	}
	h.ip = "100.124.228.116"
	h.w.tick()
	if got := h.w.current(); got != "100.124.228.116" {
		t.Fatalf("current = %q after the address appeared", got)
	}
	if len(h.opened) != 1 || h.opened[0].addr != "100.124.228.116:7411" {
		t.Fatalf("opened %+v", h.opened)
	}
	// Steady state opens nothing more.
	h.w.tick()
	h.w.tick()
	if len(h.opened) != 1 {
		t.Fatalf("re-opened on a steady address: %d listeners", len(h.opened))
	}
}

func TestTailnetListenerFollowsAddressChangesAndLoss(t *testing.T) {
	h := newTailnetHarness()
	h.ip = "100.64.0.1"
	h.w.tick()
	h.ip = "100.64.0.2"
	h.w.tick()
	if !h.opened[0].isClosed() || h.w.current() != "100.64.0.2" {
		t.Fatalf("did not move: old closed=%v current=%q", h.opened[0].isClosed(), h.w.current())
	}
	h.ip = ""
	h.w.tick()
	if !h.opened[1].isClosed() || h.w.current() != "" {
		t.Fatalf("did not close on loss: closed=%v current=%q", h.opened[1].isClosed(), h.w.current())
	}
}

func TestTailnetListenerRetriesAfterABindFailure(t *testing.T) {
	h := newTailnetHarness()
	h.ip = "100.64.0.1"
	h.failing = errors.New("can't assign requested address")
	h.w.tick()
	h.w.tick()
	if h.w.current() != "" {
		t.Fatal("claims to listen after a failed bind")
	}
	h.failing = nil
	h.w.tick()
	if h.w.current() != "100.64.0.1" || len(h.opened) != 1 {
		t.Fatalf("did not recover: current=%q opened=%d", h.w.current(), len(h.opened))
	}
}
