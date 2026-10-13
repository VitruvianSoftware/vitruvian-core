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

// Package toolkit is what a Vitruvian tool is written with, in Go: declare
// commands, handle them, call the app.
//
//	tool := toolkit.New("0.1.0")
//	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
//		return app.Notify.HUD("Hello", "hand.wave")
//	})
//	tool.Run()
//
// A tool is a program the Vitruvian app starts and talks to in JSON, one
// message per line, over the program's standard input and output. The kit
// is that conversation: it answers the app's greeting, runs a command's
// handler when the app asks, and turns each call on App into a request and
// its answer.
//
// Handlers run one at a time, on the goroutine that called Run or Serve. A
// call to the app inside a handler waits there for its answer, so from the
// handler's side every call is an ordinary function call. One more
// goroutine reads standard input; what the app sends while a handler waits
// is kept and handled after the handler returns.
//
// Never write to standard output yourself: it is the link. Write to
// standard error, or call App.Log.
package toolkit
