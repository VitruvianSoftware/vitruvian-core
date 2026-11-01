// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// notice waits for the first notification called method, passing over changed ones.
func (c *client) notice(method string) json.RawMessage {
	c.t.Helper()
	deadline := time.After(10 * time.Second)
	for {
		select {
		case m := <-c.notes:
			if m.Method == method {
				return m.Params
			}
		case <-deadline:
			c.t.Fatalf("no %s notification", method)
			return nil
		}
	}
}

// The Dispatcher answers from the same methods the socket serves, with the protocol's errors.
func TestDispatcherCallsMethodsInProcess(t *testing.T) {
	w := newWorld(t)
	d := NewDispatcher(w.deps)
	ctx := context.Background()

	raw, err := d.Dispatch(ctx, "room.events", map[string]any{"room_id": w.room, "limit": 2})
	require.NoError(t, err)
	var page struct {
		Events []struct {
			EventID string `json:"event_id"`
		} `json:"events"`
	}
	require.NoError(t, json.Unmarshal(raw, &page))
	require.Len(t, page.Events, 2)
	require.Equal(t, w.events[2], page.Events[0].EventID)

	raw, err = d.Dispatch(ctx, "reminder.clear", map[string]any{"room_ids": []string{w.room}})
	require.NoError(t, err)
	require.JSONEq(t, `{}`, string(raw), "an empty result is {}")

	for _, c := range []struct {
		method string
		params any
		code   int
		reason string
	}{
		{"room.events", map[string]any{"room_id": "!nope:courier.local"}, CodeNotFound, ""},
		{"room.events", map[string]any{"room_id": w.room, "limit": 0}, CodeInvalidParams, "limit must be 1 to 100"},
		{"no.such", nil, CodeMethodNotFound, ""},
		{"room.events", []string{"not an object"}, CodeInvalidParams, "params must be an object"},
	} {
		_, err := d.Dispatch(ctx, c.method, c.params)
		var e *Error
		require.True(t, errors.As(err, &e), "%s: %v", c.method, err)
		require.Equal(t, c.code, e.ProtocolCode())
		require.Equal(t, c.reason, e.Reason())
	}
}

// The engine's own notifications reach every connection that has said hello, and none that hasn't.
func TestNoticesReachGreetedConnections(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	n := NewNotifier()
	path := serve(t, Deps{Store: s, Notices: n, Version: "test-1"})
	require.Zero(t, n.Publish("app.focus", map[string]string{}), "no app yet")

	a, b, quiet := dial(t, path), dial(t, path), dial(t, path)
	a.hello()
	b.hello()
	require.Eventually(t, func() bool {
		n.mu.Lock()
		defer n.mu.Unlock()
		return len(n.subs) == 2
	}, 5*time.Second, 5*time.Millisecond)
	require.Equal(t, 2, n.Publish("app.focus", map[string]string{"chatID": "!r:courier.local"}))
	for _, c := range []*client{a, b} {
		require.JSONEq(t, `{"chatID":"!r:courier.local"}`, string(c.notice("app.focus")))
	}
	select {
	case m := <-quiet.notes:
		t.Fatalf("a connection without hello got %s", m.Method)
	case <-time.After(50 * time.Millisecond):
	}
}
