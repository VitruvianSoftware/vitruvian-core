// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

/*
#include "gchat.h"
extern void gchat_test_only_set_allow_loopback(int allow);
extern void gchat_use_manual_clock(GChatClient *client, double fixed_jitter);
extern size_t gchat_advance_manual_clock(GChatClient *client, uint64_t delta_ms);
*/
import "C"

import (
	"sync"
	"testing"
	"time"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/simplevent"
)

var (
	recordedEventsMu        sync.Mutex
	recordedEventsByClim    = make(map[*Client][]bridgev2.RemoteEvent)
	recordedResyncsByClient = make(map[*Client][]*simplevent.ChatResync)

	manualClockMu     sync.Mutex
	manualClockByConn = make(map[*Connector]float64)
)

func init() {
	onRemoteEventQueued = func(c *Client, evt bridgev2.RemoteEvent) {
		recordedEventsMu.Lock()
		if resync, ok := evt.(*simplevent.ChatResync); ok {
			recordedResyncsByClient[c] = append(recordedResyncsByClient[c], resync)
		} else {
			recordedEventsByClim[c] = append(recordedEventsByClim[c], evt)
		}
		recordedEventsMu.Unlock()
	}
	onFFIClientCreated = func(c *Client, ffi *FFIClient) {
		if c == nil || c.Main == nil || ffi == nil {
			return
		}
		manualClockMu.Lock()
		jitter, ok := manualClockByConn[c.Main]
		manualClockMu.Unlock()
		if ok {
			ffi.UseManualClock(jitter)
		}
	}
}

func enableManualClockForConnector(conn *Connector, fixedJitter float64) {
	manualClockMu.Lock()
	manualClockByConn[conn] = fixedJitter
	manualClockMu.Unlock()
}

func (c *FFIClient) UseManualClock(fixedJitter float64) {
	if c == nil {
		return
	}
	c.mu.Lock()
	ptr := c.ptr
	c.mu.Unlock()
	if ptr != nil {
		C.gchat_use_manual_clock(ptr, C.double(fixedJitter))
	}
}

func (c *FFIClient) AdvanceManualClock(delta time.Duration) int {
	if c == nil {
		return 0
	}
	c.mu.Lock()
	ptr := c.ptr
	c.mu.Unlock()
	if ptr == nil {
		return 0
	}
	return int(C.gchat_advance_manual_clock(ptr, C.uint64_t(delta.Milliseconds())))
}

func (c *Client) advanceManualClock(delta time.Duration) int {
	c.mu.Lock()
	ffi := c.ffiClient
	c.mu.Unlock()
	if ffi == nil {
		return 0
	}
	return ffi.AdvanceManualClock(delta)
}

func (c *Client) recordedRemoteEvents() []bridgev2.RemoteEvent {
	recordedEventsMu.Lock()
	defer recordedEventsMu.Unlock()
	src := recordedEventsByClim[c]
	out := make([]bridgev2.RemoteEvent, len(src))
	copy(out, src)
	return out
}

func (c *Client) recordedChatResyncs() []*simplevent.ChatResync {
	recordedEventsMu.Lock()
	defer recordedEventsMu.Unlock()
	src := recordedResyncsByClient[c]
	out := make([]*simplevent.ChatResync, len(src))
	copy(out, src)
	return out
}

func enableTestLoopback(t *testing.T) {
	t.Helper()
	C.gchat_test_only_set_allow_loopback(1)
	t.Cleanup(func() {
		C.gchat_test_only_set_allow_loopback(0)
	})
}
