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
)

var (
	recordedEventsMu     sync.Mutex
	recordedEventsByClim = make(map[*Client][]bridgev2.RemoteEvent)
)

func init() {
	onRemoteEventQueued = func(c *Client, evt bridgev2.RemoteEvent) {
		recordedEventsMu.Lock()
		recordedEventsByClim[c] = append(recordedEventsByClim[c], evt)
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

func enableTestLoopback(t *testing.T) {
	t.Helper()
	C.gchat_test_only_set_allow_loopback(1)
	t.Cleanup(func() {
		C.gchat_test_only_set_allow_loopback(0)
	})
}
