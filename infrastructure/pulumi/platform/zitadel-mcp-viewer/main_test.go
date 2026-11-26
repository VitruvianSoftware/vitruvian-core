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
	"testing"
	"time"
)

func TestViewerRoleIsReadOnly(t *testing.T) {
	// Widening this (to ORG_OWNER, say) would turn a read-only MCP identity into
	// one that can create and delete users. Make that a deliberate test change.
	if viewerRole != "ORG_OWNER_VIEWER" {
		t.Fatalf("viewerRole = %q, want ORG_OWNER_VIEWER", viewerRole)
	}
}

func TestResolvePATExpiry(t *testing.T) {
	now := time.Date(2026, 11, 25, 0, 0, 0, 0, time.UTC)
	tests := []struct {
		name    string
		raw     string
		want    string
		wantErr bool
	}{
		{name: "empty means never-expiring and is refused", raw: "", wantErr: true},
		{name: "not RFC 3339", raw: "2027-05-24", wantErr: true},
		{name: "in the past", raw: "2026-01-01T00:00:00Z", wantErr: true},
		{name: "exactly now is not the future", raw: "2026-11-25T00:00:00Z", wantErr: true},
		{name: "more than a year away", raw: "2028-01-01T00:00:00Z", wantErr: true},
		{name: "six months is fine", raw: "2027-05-24T00:00:00Z", want: "2027-05-24T00:00:00Z"},
		{name: "offset is normalised to UTC", raw: "2027-05-24T02:00:00+02:00", want: "2027-05-24T00:00:00Z"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := resolvePATExpiry(tt.raw, now)
			if (err != nil) != tt.wantErr {
				t.Fatalf("err = %v, wantErr %v", err, tt.wantErr)
			}
			if got != tt.want {
				t.Fatalf("got %q, want %q", got, tt.want)
			}
		})
	}
}
