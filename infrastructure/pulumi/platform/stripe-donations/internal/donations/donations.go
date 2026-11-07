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

// Package donations holds the stack's desired state as plain Go values, kept
// apart from the generated Stripe SDK so it can be validated and unit-tested
// on a clean checkout (no SDK, no Stripe account, no network).
//
// The model is deliberately small: ONE product, ONE pay-what-you-want price,
// and ONE Payment Link per app that shows a donation button. Every link sells
// the same price, so changing the suggested amount is one edit, while each
// payment still carries its app's key in metadata for attribution.
package donations

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

// Amounts are in the currency's smallest unit (cents for usd), the unit
// Stripe's API uses. They configure the price's custom_unit_amount: the
// customer types any amount between Minimum and Maximum, starting at Preset.
type Amounts struct {
	Minimum int `json:"minimum" yaml:"minimum"`
	Preset  int `json:"preset" yaml:"preset"`
	Maximum int `json:"maximum" yaml:"maximum"`
}

// App is one product that shows a donation button and gets its own link.
type App struct {
	// Key is the stable id: it names the Pulumi resource and goes into the
	// link's metadata. Renaming it REPLACES the link, which mints a new URL,
	// so treat it like a Pulumi project name.
	Key string `json:"key" yaml:"key"`
	// Name is what the app is called on the confirmation page.
	Name string `json:"name" yaml:"name"`
}

// Settings is the whole non-secret config of a stack.
type Settings struct {
	Mode            Mode    `json:"mode" yaml:"mode"`
	Currency        string  `json:"currency" yaml:"currency"`
	ProductName     string  `json:"productName" yaml:"productName"`
	Amounts         Amounts `json:"amounts" yaml:"amounts"`
	ThankYouMessage string  `json:"thankYouMessage" yaml:"thankYouMessage"`
	Apps            []App   `json:"apps" yaml:"apps"`
}

// Stripe caps a single amount at 8 digits in the smallest unit
// (999,999.99 for usd).
const maxStripeAmount = 99_999_999

var (
	currencyRe = regexp.MustCompile(`^[a-z]{3}$`)
	appKeyRe   = regexp.MustCompile(`^[a-z][a-z0-9-]{0,38}[a-z0-9]$`)
)

// Validate refuses a config the apply would otherwise get half way through:
// Stripe rejects some of these only after the product already exists.
func (s Settings) Validate() error {
	var errs []string
	add := func(format string, a ...any) { errs = append(errs, fmt.Sprintf(format, a...)) }

	if s.Mode != ModeTest && s.Mode != ModeLive {
		add("mode must be %q or %q, got %q", ModeTest, ModeLive, s.Mode)
	}
	if !currencyRe.MatchString(s.Currency) {
		add("currency must be a lowercase ISO 4217 code like \"usd\", got %q", s.Currency)
	}
	if strings.TrimSpace(s.ProductName) == "" {
		add("productName is required (it is what donors see on the checkout page)")
	}

	a := s.Amounts
	switch {
	case a.Minimum < 1:
		add("amounts.minimum must be at least 1, got %d", a.Minimum)
	case a.Maximum > maxStripeAmount:
		add("amounts.maximum must be at most %d, got %d", maxStripeAmount, a.Maximum)
	case !(a.Minimum <= a.Preset && a.Preset <= a.Maximum):
		add("amounts must satisfy minimum <= preset <= maximum, got %d <= %d <= %d", a.Minimum, a.Preset, a.Maximum)
	}

	if len(s.Apps) == 0 {
		add("apps must list at least one app (each gets its own Payment Link)")
	}
	seen := map[string]bool{}
	for i, app := range s.Apps {
		if !appKeyRe.MatchString(app.Key) {
			add("apps[%d].key %q must be lowercase kebab-case, 2-40 characters", i, app.Key)
		}
		if seen[app.Key] {
			add("apps[%d].key %q is listed twice; keys name resources and must be unique", i, app.Key)
		}
		seen[app.Key] = true
		if strings.TrimSpace(app.Name) == "" {
			add("apps[%d].name is required", i)
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("invalid stripe-donations config:\n  - %s", strings.Join(errs, "\n  - "))
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

// LinkMetadata is attached to each Payment Link so Stripe's dashboard and
// exports show which app a donation came from.
func LinkMetadata(app App, stack string) map[string]string {
	return map[string]string{
		"app":        app.Key,
		"managed-by": "pulumi",
		"stack":      stack,
	}
}
