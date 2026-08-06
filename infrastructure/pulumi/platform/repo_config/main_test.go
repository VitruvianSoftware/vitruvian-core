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

import "testing"

// parseBoolConfig is the strict boolean parser behind boolConfig (#825):
// unlike cfg.GetBool (cast.ToBool) and the TryBool-swallows-the-error
// pattern it replaces, an unparseable value must error rather than quietly
// resolve to the permissive default.
func TestParseBoolConfig(t *testing.T) {
	tests := []struct {
		name    string
		raw     string
		def     bool
		want    bool
		wantErr bool
	}{
		{name: "unset uses default true", raw: "", def: true, want: true},
		{name: "unset uses default false", raw: "", def: false, want: false},
		{name: "literal true", raw: "true", def: false, want: true},
		{name: "literal false", raw: "false", def: true, want: false},
		{name: "literal 1", raw: "1", def: false, want: true},
		{name: "literal 0", raw: "0", def: true, want: false},
		{name: "uppercase TRUE", raw: "TRUE", def: false, want: true},
		// The whole point of the fix: these previously parsed as false
		// (cast.ToBool/TryBool swallow the error) instead of failing loudly.
		{name: "yes is not a bool", raw: "yes", def: false, wantErr: true},
		{name: "on is not a bool", raw: "on", def: false, wantErr: true},
		{name: "garbage is not a bool", raw: "not-a-bool", def: false, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseBoolConfig("someFlag", tt.raw, tt.def)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("parseBoolConfig(%q, def=%v) = %v, nil; want an error", tt.raw, tt.def, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("parseBoolConfig(%q, def=%v) unexpected error: %v", tt.raw, tt.def, err)
			}
			if got != tt.want {
				t.Fatalf("parseBoolConfig(%q, def=%v) = %v, want %v", tt.raw, tt.def, got, tt.want)
			}
		})
	}
}
