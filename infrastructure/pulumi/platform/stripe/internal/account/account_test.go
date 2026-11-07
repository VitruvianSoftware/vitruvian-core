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

package account

import (
	"strings"
	"testing"
)

func TestValidate(t *testing.T) {
	if err := (Settings{Mode: ModeTest, Currency: "usd"}).Validate(); err != nil {
		t.Fatalf("valid config rejected: %v", err)
	}
	cases := map[string]struct {
		s    Settings
		want string
	}{
		"unknown mode":       {Settings{Mode: "prod", Currency: "usd"}, "mode must be"},
		"uppercase currency": {Settings{Mode: ModeTest, Currency: "USD"}, "currency"},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			err := tc.s.Validate()
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("want error containing %q, got %v", tc.want, err)
			}
		})
	}
}

func TestCheckKeyMode(t *testing.T) {
	ok := []struct {
		key  string
		mode Mode
	}{
		{"sk_test_abc", ModeTest},
		{"rk_test_abc", ModeTest},
		{"sk_live_abc", ModeLive},
		{"rk_live_abc", ModeLive},
	}
	for _, c := range ok {
		if err := CheckKeyMode(c.key, c.mode); err != nil {
			t.Errorf("CheckKeyMode(%q-prefixed, %s) = %v, want nil", c.key[:8], c.mode, err)
		}
	}

	bad := []struct {
		key  string
		mode Mode
	}{
		{"sk_live_abc", ModeTest}, // live key on the sandbox stack: the case this guard exists for
		{"rk_live_abc", ModeTest},
		{"sk_test_abc", ModeLive},
		{"pk_test_abc", ModeTest},
		{"", ModeTest},
	}
	for _, c := range bad {
		err := CheckKeyMode(c.key, c.mode)
		if err == nil {
			t.Errorf("CheckKeyMode(%q, %s) = nil, want an error", c.key, c.mode)
			continue
		}
		if c.key != "" && strings.Contains(err.Error(), c.key) {
			t.Errorf("error message leaks the key: %v", err)
		}
	}
}
