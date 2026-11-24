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
	"bytes"
	"fmt"
	"os"
	"strconv"
	"testing"
)

func parseActionsCacheLimitFile(raw []byte) (int, error) {
	if !bytes.HasSuffix(raw, []byte("\n")) {
		return 0, fmt.Errorf("actions-cache-limit-gb.txt must end with a single newline")
	}
	trimmed := bytes.TrimSuffix(raw, []byte("\n"))
	if len(trimmed) == 0 {
		return 0, fmt.Errorf("actions-cache-limit-gb.txt must not be empty")
	}
	if trimmed[0] < '1' || trimmed[0] > '9' {
		return 0, fmt.Errorf("actions-cache-limit-gb.txt must be a positive integer without leading zeros or sign, got %q", string(trimmed))
	}
	for _, b := range trimmed[1:] {
		if b < '0' || b > '9' {
			return 0, fmt.Errorf("actions-cache-limit-gb.txt must contain decimal digits only, got %q", string(trimmed))
		}
	}
	n, err := strconv.Atoi(string(trimmed))
	if err != nil || n < 1 {
		return 0, fmt.Errorf("actions-cache-limit-gb.txt invalid integer %q: %v", string(trimmed), err)
	}
	return n, nil
}

func TestActionsCacheLimitFile(t *testing.T) {
	raw, err := os.ReadFile("actions-cache-limit-gb.txt")
	if err != nil {
		t.Fatal(err)
	}
	n, err := parseActionsCacheLimitFile(raw)
	if err != nil {
		t.Fatal(err)
	}
	if n < 1 {
		t.Fatalf("parsed limit = %d, want >= 1", n)
	}
}

func TestParseActionsCacheLimitFile(t *testing.T) {
	tests := []struct {
		name    string
		raw     string
		want    int
		wantErr bool
	}{
		{name: "valid 15", raw: "15\n", want: 15},
		{name: "valid 1", raw: "1\n", want: 1},
		{name: "unit suffix", raw: "15GB\n", wantErr: true},
		{name: "zero", raw: "0\n", wantErr: true},
		{name: "negative", raw: "-3\n", wantErr: true},
		{name: "decimal", raw: "1.5\n", wantErr: true},
		{name: "plus sign", raw: "+15\n", wantErr: true},
		{name: "leading zero", raw: "015\n", wantErr: true},
		{name: "empty", raw: "", wantErr: true},
		{name: "newline only", raw: "\n", wantErr: true},
		{name: "missing trailing newline", raw: "15", wantErr: true},
		{name: "leading space", raw: " 15\n", wantErr: true},
		{name: "trailing space", raw: "15 \n", wantErr: true},
		{name: "multiple lines", raw: "15\n16\n", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseActionsCacheLimitFile([]byte(tt.raw))
			if tt.wantErr {
				if err == nil {
					t.Fatalf("parseActionsCacheLimitFile(%q) = %d, nil; want error", tt.raw, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("parseActionsCacheLimitFile(%q) unexpected error: %v", tt.raw, err)
			}
			if got != tt.want {
				t.Fatalf("parseActionsCacheLimitFile(%q) = %d, want %d", tt.raw, got, tt.want)
			}
		})
	}
}
