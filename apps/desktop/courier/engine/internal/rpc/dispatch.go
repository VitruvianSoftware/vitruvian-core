// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"bytes"
	"context"
	"encoding/json"
	"sync"
)

// Dispatcher calls the engine's protocol methods in-process, as the app would over the socket but without one:
// the local API's tools (internal/localapi) are built on it, so they answer from the very same code the app's
// requests run, and no query is written twice.
type Dispatcher struct{ d *Deps }

// NewDispatcher is a Dispatcher over d, the Deps the socket server serves from.
func NewDispatcher(d Deps) *Dispatcher { return &Dispatcher{d: &d} }

// Dispatch calls method with params (any value that encodes as a JSON object, or nil for none) and returns its
// result as JSON. An error is always an *Error, with the protocol's code and fixed message: an engine failure
// with no code of its own is logged, as the socket server logs it, and comes back as an internal error.
func (x *Dispatcher) Dispatch(ctx context.Context, method string, params any) (json.RawMessage, error) {
	h, ok := methods[method]
	if !ok {
		return nil, newError(CodeMethodNotFound)
	}
	var raw json.RawMessage
	if params != nil {
		b, err := json.Marshal(params)
		if err != nil {
			return nil, invalidParams("params don't fit this method")
		}
		if b = bytes.TrimSpace(b); !bytes.Equal(b, []byte("null")) {
			if len(b) == 0 || b[0] != '{' {
				return nil, invalidParams("params must be an object")
			}
			raw = b
		}
	}
	res, err := run(ctx, x.d, method, h, raw)
	if err != nil {
		e, unknown := classify(err)
		if unknown && ctx.Err() == nil {
			x.d.Log.Error().Str("method", method).Err(err).Msg("request failed inside the engine")
		}
		return nil, e
	}
	if res == nil {
		res = struct{}{}
	}
	line, err := encodeLine(res)
	if err != nil {
		return nil, newError(CodeInternal)
	}
	return bytes.TrimSpace(line), nil
}

// ProtocolCode is the error's code, for a caller outside this package that maps codes to its own words.
func (e *Error) ProtocolCode() int { return e.Code }

// Reason is why the params were refused (an invalid params error's data.reason), or "".
func (e *Error) Reason() string {
	if m, ok := e.Data.(map[string]string); ok {
		return m["reason"]
	}
	return ""
}

// Notifier sends the engine's own notifications, the ones that aren't store changes, to every app connection that
// has said hello: app.focus (from the local API's focus_app) and integrations.pairRequest. A connection that
// can't keep up loses a notification rather than holding up the engine.
type Notifier struct {
	mu   sync.Mutex
	subs map[chan []byte]struct{}
}

// noticeQueue is how many notifications a connection holds before more are dropped.
const noticeQueue = 16

// NewNotifier is a Notifier with no connections yet.
func NewNotifier() *Notifier { return &Notifier{subs: map[chan []byte]struct{}{}} }

type noticeLine struct {
	JSONRPC string `json:"jsonrpc"`
	Method  string `json:"method"`
	Params  any    `json:"params"`
}

// Publish sends the notification method with params to every connection, and says how many it was handed to: 0
// means no app is listening.
func (n *Notifier) Publish(method string, params any) int {
	line, err := encodeLine(noticeLine{JSONRPC: "2.0", Method: method, Params: params})
	if err != nil {
		return 0
	}
	n.mu.Lock()
	defer n.mu.Unlock()
	sent := 0
	for ch := range n.subs {
		select {
		case ch <- line:
			sent++
		default:
		}
	}
	return sent
}

func (n *Notifier) subscribe() (chan []byte, func()) {
	ch := make(chan []byte, noticeQueue)
	n.mu.Lock()
	n.subs[ch] = struct{}{}
	n.mu.Unlock()
	return ch, func() {
		n.mu.Lock()
		delete(n.subs, ch)
		n.mu.Unlock()
	}
}

// startNotices forwards the Notifier's notifications to the connection until it closes. It is started once, after
// the hello's answer is queued, like the change feed.
func (c *conn) startNotices(ch chan []byte, unsubscribe func()) {
	c.wg.Add(1)
	go func() {
		defer c.wg.Done()
		defer unsubscribe()
		for {
			select {
			case <-c.ctx.Done():
				return
			case line := <-ch:
				if !c.send(line) {
					return
				}
			}
		}
	}()
}
