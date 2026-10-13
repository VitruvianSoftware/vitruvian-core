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
	"errors"
	"fmt"
	"time"
)

// The codes a failure carries. The first five are JSON-RPC's own; the rest
// are the protocol's refusals.
const (
	CodeParseError     = -32700
	CodeInvalidRequest = -32600
	CodeMethodNotFound = -32601
	CodeInvalidParams  = -32602
	CodeInternalError  = -32603

	// CodeNotInUses: the service is not listed in the tool's `uses`.
	CodeNotInUses = -32001
	// CodeNotInstalled: the tool is not installed, or is switched off.
	CodeNotInstalled = -32002
	// CodePermissionMissing: Vitruvian lacks a macOS permission the service
	// needs.
	CodePermissionMissing = -32003
	// CodeUnavailable: not available right now.
	CodeUnavailable = -32004
	// CodeCommandRefused: the tool will not run the command.
	CodeCommandRefused = -32010
)

// Error is a failure as the link carries it. A call to the app returns one
// when the app refused the request.
func (e *Error) Error() string {
	return fmt.Sprintf("vitruvian: %s (%d)", e.Message, e.Code)
}

// RefusedError is a command the tool will not run, and a few English words
// for the log saying why. The app is answered with CodeCommandRefused.
type RefusedError struct {
	Reason string
}

func (e *RefusedError) Error() string { return e.Reason }

// Refuse is what a handler returns to refuse its command.
func Refuse(reason string) error {
	return &RefusedError{Reason: reason}
}

// ErrLinkClosed is what a call returns when the app has said goodbye or
// closed the link, or has not said hello yet.
var ErrLinkClosed = errors.New("vitruvian: the link to the app is closed")

// NoAnswerError is what a call returns when no answer came within the
// tool's AnswerTimeout.
type NoAnswerError struct {
	After time.Duration
}

func (e *NoAnswerError) Error() string {
	return fmt.Sprintf("vitruvian: no answer from the app within %v", e.After)
}
