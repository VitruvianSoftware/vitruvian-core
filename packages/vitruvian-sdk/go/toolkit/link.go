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

package toolkit

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"strconv"
	"time"
)

// maxLineBytes is the longest line the protocol allows, not counting its
// line break.
const maxLineBytes = 1_048_576

// message is one line on the link, taken apart. A request has a method and
// an id; a notice a method and no id; an answer an id and a result or an
// error.
type message struct {
	id     json.RawMessage
	method string
	params json.RawMessage
	result json.RawMessage
	err    *Error
}

func (m message) isRequest() bool { return m.method != "" && m.id != nil }

func (m message) isNotice() bool { return m.method != "" && m.id == nil }

// answers says whether m is the answer to the request this tool sent
// under id.
func (m message) answers(id int64) bool {
	if m.method != "" || m.id == nil {
		return false
	}
	number, err := strconv.ParseInt(string(m.id), 10, 64)
	return err == nil && number == id
}

// parse takes a line apart. False for a line that is not a message of
// JSON-RPC 2.0: the line is then dropped, as there is nothing to answer.
func parse(line []byte) (message, bool) {
	var fields map[string]json.RawMessage
	if json.Unmarshal(line, &fields) != nil {
		return message{}, false
	}
	var version string
	if json.Unmarshal(fields["jsonrpc"], &version) != nil || version != "2.0" {
		return message{}, false
	}
	id, hasID := fields["id"]
	_, hasResult := fields["result"]
	rawError, hasError := fields["error"]
	if raw, ok := fields["method"]; ok {
		var found message
		if hasResult || hasError || json.Unmarshal(raw, &found.method) != nil || found.method == "" {
			return message{}, false
		}
		if params, ok := fields["params"]; ok {
			if !bytes.HasPrefix(bytes.TrimSpace(params), []byte("{")) {
				return message{}, false
			}
			found.params = params
		}
		if hasID {
			if !isID(id) {
				return message{}, false
			}
			found.id = id
		}
		return found, true
	}
	if hasError {
		var failure Error
		if hasResult || !hasID || json.Unmarshal(rawError, &failure) != nil {
			return message{}, false
		}
		return message{id: id, err: &failure}, true
	}
	if !hasResult || !isID(id) {
		return message{}, false
	}
	return message{id: id, result: fields["result"]}, true
}

// isID says whether raw is a whole number or a string.
func isID(raw json.RawMessage) bool {
	var text string
	if json.Unmarshal(raw, &text) == nil {
		return true
	}
	_, err := strconv.ParseInt(string(bytes.TrimSpace(raw)), 10, 64)
	return err == nil
}

// outgoing is a message this tool writes.
type outgoing struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  any             `json:"params,omitempty"`
	Result  any             `json:"result,omitempty"`
	Error   *Error          `json:"error,omitempty"`
}

// state is what waiting on the link came to.
type state int

const (
	got   state = iota // a message came
	ended              // the app closed the link, or it broke
	late               // the time given passed first
)

// link is the tool's end of the conversation. One goroutine reads the
// input and hands each message over, and waits until it has been taken:
// the app cannot get ahead of the tool by more than one line. Everything
// else is done on the goroutine that serves.
type link struct {
	inbox  chan message
	done   chan struct{}
	out    io.Writer
	broken bool
}

// read is the reading goroutine. `gone` is called once the app has said
// goodbye or the input has ended, whichever is first, and the inbox is
// closed at the end of the input. A line over the limit is dropped, and
// so is a last line with no line break: the protocol never delivers it.
func (l *link) read(in io.Reader, gone func()) {
	defer close(l.inbox)
	defer gone()
	reader := bufio.NewReaderSize(in, 64*1024)
	for {
		line, err := readLine(reader)
		if err != nil {
			return
		}
		found, ok := parse(line)
		if !ok {
			continue
		}
		if found.isNotice() && found.method == MethodShutdown {
			gone()
		}
		select {
		case l.inbox <- found:
		case <-l.done:
			return
		}
	}
}

// readLine reads up to the next line break. A line longer than the limit
// is read to its end and given back as nil, never held whole.
func readLine(reader *bufio.Reader) ([]byte, error) {
	var line []byte
	tooLong := false
	for {
		chunk, err := reader.ReadSlice('\n')
		if !tooLong && len(line)+len(chunk) > maxLineBytes+1 {
			tooLong, line = true, nil
		}
		if !tooLong {
			line = append(line, chunk...)
		}
		switch {
		case err == nil && tooLong:
			return nil, nil
		case err == nil:
			return line[:len(line)-1], nil
		case errors.Is(err, bufio.ErrBufferFull):
			continue
		default:
			return nil, err
		}
	}
}

// next is the next message. With timeout nil it waits for as long as the
// link is open. A message that has already come is handed over even when
// the time is up.
func (l *link) next(timeout <-chan time.Time) (message, state) {
	if l.broken {
		return message{}, ended
	}
	select {
	case found, ok := <-l.inbox:
		if !ok {
			return message{}, ended
		}
		return found, got
	default:
	}
	select {
	case found, ok := <-l.inbox:
		if !ok {
			return message{}, ended
		}
		return found, got
	case <-timeout:
		return message{}, late
	}
}

// send writes one message as one line, in one write. False when it could
// not be written; the link has then ended.
func (l *link) send(m outgoing) bool {
	if l.broken {
		return false
	}
	m.JSONRPC = "2.0"
	var line bytes.Buffer
	encoder := json.NewEncoder(&line)
	encoder.SetEscapeHTML(false)
	if encoder.Encode(m) != nil {
		return false
	}
	if _, err := l.out.Write(line.Bytes()); err != nil {
		l.broken = true
		return false
	}
	return true
}
