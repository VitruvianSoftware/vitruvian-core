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

// A tool written with the Go kit. It has two commands: `hello` asks the app
// to show a short message, and `count` keeps a number in a preference its
// manifest declares. `vitruvian-tool init --template go` starts a new tool
// from this file.
package main

import (
	"context"
	"fmt"

	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit"
)

func main() {
	tool := toolkit.New("0.1.0")

	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		return app.Notify.HUD("Hello from a Go tool", "hand.wave")
	})

	tool.Command("count", func(ctx context.Context, app *toolkit.App) error {
		saved, err := app.Storage.Get("count")
		if err != nil {
			return err
		}
		next, _ := saved.(float64)
		next++
		if err := app.Storage.Set("count", next); err != nil {
			return err
		}
		return app.Notify.HUD(fmt.Sprintf("Counted to %d", int(next)), "number")
	})

	tool.Run()
}
