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

// Package account holds what is true of the whole Stripe account a stack
// manages, whatever it sells: which Stripe mode the stack may touch, the
// currency, and the guard that keeps a key for the wrong mode out. Product
// lines (donations today, paid products later) live in their own packages
// and share these settings.
package account

import (
	"fmt"
	"regexp"
	"strings"
)

// Mode is which Stripe environment the stack is allowed to touch. It is set
// per stack (Pulumi.<stack>.yaml) and checked against the API key prefix, so a
// live key can never be pointed at the sandbox stack by mistake, or vice versa.
type Mode string

const (
	ModeTest Mode = "test"
	ModeLive Mode = "live"
)

// Settings is the account-wide, non-secret config of a stack.
type Settings struct {
	Mode     Mode   `json:"mode" yaml:"mode"`
	Currency string `json:"currency" yaml:"currency"`
}

var currencyRe = regexp.MustCompile(`^[a-z]{3}$`)

// Validate refuses an account config Stripe would reject part way through an
// apply.
func (s Settings) Validate() error {
	var errs []string
	if s.Mode != ModeTest && s.Mode != ModeLive {
		errs = append(errs, fmt.Sprintf("mode must be %q or %q, got %q", ModeTest, ModeLive, s.Mode))
	}
	if !currencyRe.MatchString(s.Currency) {
		errs = append(errs, fmt.Sprintf("currency must be a lowercase ISO 4217 code like \"usd\", got %q", s.Currency))
	}
	if len(errs) > 0 {
		return fmt.Errorf("invalid stripe account config:\n  - %s", strings.Join(errs, "\n  - "))
	}
	return nil
}

// CheckKeyMode refuses an API key whose prefix does not match the stack's
// mode, and refuses a publishable key outright (it cannot create anything and
// is a sign the wrong value was pasted). It never echoes the key itself.
func CheckKeyMode(key string, mode Mode) error {
	var want []string
	switch mode {
	case ModeTest:
		want = []string{"sk_test_", "rk_test_"}
	case ModeLive:
		want = []string{"sk_live_", "rk_live_"}
	default:
		return fmt.Errorf("unknown mode %q", mode)
	}
	if strings.HasPrefix(key, "pk_") {
		return fmt.Errorf("the Stripe key is a publishable key (pk_...); this stack needs a secret or restricted key (%s)", strings.Join(want, " or "))
	}
	for _, p := range want {
		if strings.HasPrefix(key, p) {
			return nil
		}
	}
	return fmt.Errorf("this stack is in %s mode, so the Stripe key must start with %s; refusing to apply with a key for another mode", mode, strings.Join(want, " or "))
}
