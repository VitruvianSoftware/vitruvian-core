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
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

// POST /v1/exec/stream: the same act as /v1/exec, delivered as it happens.
//
// Why a second endpoint rather than a flag on the first: the two have
// genuinely different failure modes. /v1/exec can answer 400 for a bad kind
// and 500 for a broken pipe, because it has not sent anything yet. A stream
// has committed to a 200 and an event-stream body with its first byte, so
// every later problem has to be expressed IN the stream. Splitting them
// keeps the buffered endpoint simple and honest.
//
// Server-Sent Events rather than a WebSocket: the traffic is one-directional
// (cancel is a TCP disconnect, not a message), it survives an HTTP proxy that
// knows nothing about upgrades, and Android's OkHttp reads it with no extra
// dependency.

// keepaliveInterval is how often a comment goes out while nothing prints. It
// is not decoration: a phone on cellular sits behind a NAT that drops an idle
// flow in a couple of minutes, and a `bazel build` that prints nothing for
// five is the normal case this exists for.
const keepaliveInterval = 15 * time.Second

// execStreamID numbers the streams for the act log and the exec:<id>
// notification key. Per-process and monotonic -- enough to tell two
// concurrent commands apart in a log, which is all it is for.
var execStreamID atomic.Int64

func (srv *server) execStream(w http.ResponseWriter, r *http.Request) {
	var req execRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if strings.TrimSpace(req.Command) == "" {
		writeError(w, http.StatusBadRequest, "command is required")
		return
	}
	// Validate the kind BEFORE the first byte. Afterwards the status line is
	// spent and the only way to report it would be an exit event, which a
	// client would read as "your command ran and failed".
	if _, _, err := argvFor(req.Kind, req.Command); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	// Flushing is not optional here: without it the whole point of the
	// endpoint is lost to the response buffer, and a client would get every
	// line at once when the command finished.
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "this server cannot stream")
		return
	}

	id := execStreamID.Add(1)
	logAct(req.Kind, fmt.Sprintf("stream #%d start: %s", id, req.Command))

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-store")
	// Nagle's algorithm's cousin: nginx and friends buffer proxied responses
	// by default and would hold every line until the body ended.
	w.Header().Set("X-Accel-Buffering", "no")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	// r.Context() is cancelled when the client disconnects, and runStream
	// turns that into a kill of the process group. That is the phone's
	// Cancel button: there is no cancel message to send, it just hangs up.
	lines := make(chan streamLine, 64)
	type result struct {
		code int
		dur  time.Duration
	}
	res := make(chan result, 1)
	go func() {
		code, dur := runStream(r.Context(), req, lines)
		res <- result{code, dur}
	}()

	ticker := time.NewTicker(keepaliveInterval)
	defer ticker.Stop()

	open := true
	for open {
		select {
		case line, ok := <-lines:
			if !ok {
				open = false
				break
			}
			if err := writeEvent(w, "line", line); err != nil {
				// The client is gone. Draining the channel keeps runStream
				// from blocking on a send while it winds down; the killed
				// process group is what actually ends it.
				go func() {
					for range lines {
					}
				}()
				open = false
				break
			}
			flusher.Flush()
			// The keepalive is only for silence, so real output resets it.
			ticker.Reset(keepaliveInterval)
		case <-ticker.C:
			// A comment, per the SSE spec: every client ignores it, and it
			// keeps the connection warm through a NAT that would otherwise
			// forget it.
			if _, err := fmt.Fprint(w, ": keepalive\n\n"); err != nil {
				open = false
				break
			}
			flusher.Flush()
		}
	}

	out := <-res
	logAct(req.Kind, fmt.Sprintf("stream #%d exit %d after %dms", id, out.code, out.dur.Milliseconds()))
	// Written unconditionally: if the client is gone this fails silently,
	// and if it is still there the contract promises exit as the last event.
	_ = writeEvent(w, "exit", streamExit{ExitCode: out.code, DurationMS: out.dur.Milliseconds()})
	flusher.Flush()

	// The notification outlives the request, so it gets a context of its
	// own: r.Context() is already cancelled in the case that matters most --
	// the phone went to sleep, which is exactly when a push is the point.
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		srv.sampler.Notifier().notify(ctx, "exec:"+strconv.FormatInt(id, 10),
			"Command finished · exit "+strconv.Itoa(out.code),
			firstNChars(req.Command, 80), "default", "checkered_flag", "vitruvian-remote://console")
	}()
}

// writeEvent writes one SSE event. The data is a single line of JSON, which
// keeps the framing trivial: SSE splits data on newlines, and a pretty-printed
// payload would arrive as several data: lines the client has to rejoin.
func writeEvent(w http.ResponseWriter, event string, payload any) error {
	b, err := json.Marshal(payload)
	if err != nil {
		log.Printf("stream: marshal %s: %v", event, err)
		return nil
	}
	_, err = fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event, b)
	return err
}

// firstNChars is logAct's truncation, reused for the notification body.
func firstNChars(s string, n int) string {
	s = strings.ReplaceAll(strings.TrimSpace(s), "\n", " ")
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "..."
}
