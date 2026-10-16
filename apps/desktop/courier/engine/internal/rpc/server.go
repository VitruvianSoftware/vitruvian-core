// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package rpc is the engine's side of the app protocol: JSON-RPC 2.0 over a local Unix socket, one JSON object per
// line. The protocol is defined in apps/desktop/courier/protocol/protocol.json, with examples beside it; the
// conformance test holds this package to both.
//
// Each connection must say hello first. Each request then runs on its own goroutine, since sending a message or
// waiting for a phone can take a long time, and one writer goroutine per connection puts answers and change
// notifications on the wire as they come. Closing a connection cancels everything it has in flight.
package rpc

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"sync"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/login"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Protocol is the protocol version this engine speaks: protocol.json's "protocol".
const Protocol = 1

// MaxFrameBytes is the longest line the engine reads, not counting its newline. A longer one closes the connection.
const MaxFrameBytes = 4 << 20

// outQueue is how many lines a connection's writer holds before senders wait. Notifications wait here too, so a
// client that stops reading backs up into the store's change feed, which drops and later says resync.
const outQueue = 64

// NetworkInfo is one network the engine knows, whether or not it is running.
type NetworkInfo struct {
	Name        string   // whatsapp
	DisplayName string   // WhatsApp
	Flows       []string // its sign-in flows, preferred first
}

// Deps is what the server serves from. Store is required. The others may be nil in a test that does not call the
// methods needing them; such a call is an internal error.
type Deps struct {
	Store   *store.Store
	Engine  *engine.Engine
	Actions *actions.Actions
	Login   *login.Driver
	Media   *media.Store
	// Networks lists every network the engine knows, in display order: hello's networks and accounts.list follow it.
	Networks []NetworkInfo
	// NotStarted holds, by network name, why a network was not started. Such a network shows as NOT_STARTED.
	NotStarted map[string]string
	// Version is the engine's version, sent in hello.
	Version string
}

// Serve answers connections on ln until ctx ends or ln fails, then closes ln and every connection, and returns
// once their requests in flight have returned. It returns nil when stopped by ctx.
func Serve(ctx context.Context, ln net.Listener, d Deps) error {
	if d.Store == nil {
		ln.Close()
		return errors.New("rpc: Deps.Store is required")
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	stop := context.AfterFunc(ctx, func() { ln.Close() })
	defer stop()

	var wg sync.WaitGroup
	var err error
	for {
		nc, aerr := ln.Accept()
		if aerr != nil {
			if ctx.Err() == nil {
				err = aerr
			}
			break
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			serveConn(ctx, nc, &d)
		}()
	}
	ln.Close()
	cancel()
	wg.Wait()
	return err
}

// conn is one client connection.
type conn struct {
	d      *Deps
	nc     net.Conn
	ctx    context.Context // ends when the connection closes; every request's context derives from it
	cancel context.CancelFunc
	out    chan []byte
	wg     sync.WaitGroup // request goroutines and the feed

	greeted bool // a hello succeeded; only the reader goroutine touches it
}

func serveConn(parent context.Context, nc net.Conn, d *Deps) {
	ctx, cancel := context.WithCancel(parent)
	c := &conn{d: d, nc: nc, ctx: ctx, cancel: cancel, out: make(chan []byte, outQueue)}
	stop := context.AfterFunc(ctx, func() { nc.Close() }) // unblocks the reader and the writer
	defer stop()
	writerDone := make(chan struct{})
	go func() {
		defer close(writerDone)
		c.writeLoop()
	}()
	c.readLoop()
	cancel()
	nc.Close()
	c.wg.Wait()
	<-writerDone
}

func (c *conn) writeLoop() {
	for {
		select {
		case <-c.ctx.Done():
			return
		case b := <-c.out:
			if _, err := c.nc.Write(b); err != nil {
				c.cancel()
				return
			}
		}
	}
}

// send queues one line for the writer. It waits while the queue is full, and gives up when the connection closes.
func (c *conn) send(line []byte) bool {
	select {
	case c.out <- line:
		return true
	case <-c.ctx.Done():
		return false
	}
}

var errFrameTooLarge = errors.New("frame too large")

// readFrame reads one line, without its newline, refusing one longer than MaxFrameBytes without reading on to its
// end.
func readFrame(r *bufio.Reader) ([]byte, error) {
	var line []byte
	for {
		chunk, err := r.ReadSlice('\n')
		n := len(chunk)
		if err == nil {
			n-- // the newline
		}
		if len(line)+n > MaxFrameBytes {
			return nil, errFrameTooLarge
		}
		line = append(line, chunk...)
		switch {
		case err == nil:
			return line[:len(line)-1], nil
		case errors.Is(err, bufio.ErrBufferFull):
			continue
		default:
			return nil, err // EOF mid-line drops the partial line
		}
	}
}

func (c *conn) readLoop() {
	r := bufio.NewReaderSize(c.nc, 64<<10)
	for {
		line, err := readFrame(r)
		if err != nil {
			return
		}
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}
		c.handle(line)
	}
}

// request is a parsed request line.
type request struct {
	id     json.RawMessage // "null" when the request's id could not be read
	method string
	params json.RawMessage // nil when absent or null
}

// parse reads one line as a JSON-RPC request. hasID is false for a notification, which gets no answer.
func parse(line []byte) (req request, hasID bool, rerr *Error) {
	req.id = json.RawMessage("null")
	if !json.Valid(line) {
		return req, true, newError(CodeParseError)
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(line, &fields); err != nil {
		return req, true, newError(CodeInvalidRequest) // a batch, or not an object
	}
	rawID, hasID := fields["id"]
	if hasID {
		switch b := bytes.TrimSpace(rawID); {
		case len(b) > 0 && (b[0] == '"' || b[0] == '-' || (b[0] >= '0' && b[0] <= '9')), bytes.Equal(b, []byte("null")):
			req.id = b
		default:
			return req, true, newError(CodeInvalidRequest)
		}
	}
	var version string
	if err := json.Unmarshal(fields["jsonrpc"], &version); err != nil || version != "2.0" {
		return req, true, newError(CodeInvalidRequest)
	}
	if err := json.Unmarshal(fields["method"], &req.method); err != nil || req.method == "" {
		return req, true, newError(CodeInvalidRequest)
	}
	if p := bytes.TrimSpace(fields["params"]); len(p) > 0 && !bytes.Equal(p, []byte("null")) {
		if p[0] != '{' {
			return req, true, invalidParams("params must be an object")
		}
		req.params = p
	}
	return req, hasID, nil
}

// handle answers one line. hello is answered here, in order, so a request sent right behind it sees it; every
// other method runs on its own goroutine.
func (c *conn) handle(line []byte) {
	req, hasID, perr := parse(line)
	if !hasID {
		return // a notification: the protocol defines none from the client
	}
	if perr != nil {
		c.reply(req.id, nil, perr)
		return
	}
	if req.method == "hello" {
		first := !c.greeted
		res, err := c.hello(req.params)
		c.reply(req.id, res, err)
		if first && c.greeted {
			// Only now, with the answer queued, so no notification gets ahead of it. A change in between is not
			// lost to the client: anything it asks next is read after this subscription began.
			c.startFeed()
		}
		return
	}
	if !c.greeted {
		c.reply(req.id, nil, newError(CodeHelloRequired))
		return
	}
	h, ok := methods[req.method]
	if !ok {
		c.reply(req.id, nil, newError(CodeMethodNotFound))
		return
	}
	c.wg.Add(1)
	go func() {
		defer c.wg.Done()
		res, err := run(c.ctx, c.d, h, req.params)
		if c.ctx.Err() != nil {
			return // the connection closed: nobody to answer
		}
		c.reply(req.id, res, err)
	}()
}

// run calls one method, turning a panic into an internal error so one bad request can't stop the engine.
func run(ctx context.Context, d *Deps, h handler, params json.RawMessage) (res any, err error) {
	defer func() {
		if r := recover(); r != nil {
			res, err = nil, newError(CodeInternal)
		}
	}()
	return h(ctx, d, params)
}

type helloResult struct {
	Protocol int      `json:"protocol"`
	Engine   string   `json:"engine"`
	Networks []string `json:"networks"`
}

func (c *conn) hello(raw json.RawMessage) (any, error) {
	var p struct {
		Protocol *int    `json:"protocol"`
		Client   *string `json:"client"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if p.Protocol == nil {
		return nil, invalidParams("protocol is required")
	}
	if p.Client == nil {
		return nil, invalidParams("client is required")
	}
	if *p.Protocol != Protocol {
		e := newError(CodeProtocolMismatch)
		e.Data = map[string]int{"engine": Protocol}
		return nil, e
	}
	c.greeted = true
	names := make([]string, 0, len(c.d.Networks))
	for _, n := range c.d.Networks {
		names = append(names, n.Name)
	}
	return helloResult{Protocol: Protocol, Engine: c.d.Version, Networks: names}, nil
}

type okResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  any             `json:"result"`
}

type errResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Error   *Error          `json:"error"`
}

func (c *conn) reply(id json.RawMessage, result any, err error) {
	var v any
	if err != nil {
		v = errResponse{JSONRPC: "2.0", ID: id, Error: toError(err)}
	} else {
		if result == nil {
			result = struct{}{}
		}
		v = okResponse{JSONRPC: "2.0", ID: id, Result: result}
	}
	line, merr := encodeLine(v)
	if merr != nil {
		line, _ = encodeLine(errResponse{JSONRPC: "2.0", ID: id, Error: newError(CodeInternal)})
	}
	c.send(line)
}

// encodeLine is v as one JSON line. HTML characters are left as they are: this is not going to a browser.
func encodeLine(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil { // Encode ends the line with \n
		return nil, err
	}
	return buf.Bytes(), nil
}

// decode reads params into v. Absent params decode as {}. A wrong type names the parameter, never its value.
func decode(raw json.RawMessage, v any) error {
	if len(raw) == 0 {
		raw = json.RawMessage("{}")
	}
	if err := json.Unmarshal(raw, v); err != nil {
		var te *json.UnmarshalTypeError
		if errors.As(err, &te) && te.Field != "" {
			return invalidParams(fmt.Sprintf("%s has the wrong type", te.Field))
		}
		return invalidParams("params don't fit this method")
	}
	return nil
}
