// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

/*
extern void gchat_test_only_set_allow_loopback(int allow);
*/
import "C"

import (
	"sync"
	"testing"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/simplevent"
)

var (
	recordedEventsMu        sync.Mutex
	recordedEventsByClim    = make(map[*Client][]bridgev2.RemoteEvent)
	recordedResyncsByClient = make(map[*Client][]*simplevent.ChatResync)
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
