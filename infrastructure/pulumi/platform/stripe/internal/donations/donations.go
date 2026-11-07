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

// Package donations is the donation product line of the stack: ONE product,
// ONE pay-what-you-want price, and ONE Payment Link per app that shows a
// donation button. Every link sells the same price, so changing the suggested
// amount is one edit, while each payment still carries its app's key in
// metadata for attribution.
//
// It holds desired state as plain Go values, kept apart from the generated
// Stripe SDK so it can be validated and unit-tested on a clean checkout (no
// SDK, no Stripe account, no network). Account-wide settings (mode, currency)
// live in package account; paid products, when they come, get a package of
// their own beside this one.
package donations

import (
	"fmt"
	"regexp"
	"strings"
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

// Settings is the `donations` object of a stack's config.
type Settings struct {
	ProductName     string  `json:"productName" yaml:"productName"`
	Amounts         Amounts `json:"amounts" yaml:"amounts"`
	ThankYouMessage string  `json:"thankYouMessage" yaml:"thankYouMessage"`
	Apps            []App   `json:"apps" yaml:"apps"`
}

// Stripe caps a single amount at 8 digits in the smallest unit
// (999,999.99 for usd).
const maxStripeAmount = 99_999_999

var appKeyRe = regexp.MustCompile(`^[a-z][a-z0-9-]{0,38}[a-z0-9]$`)

// Validate refuses a config the apply would otherwise get half way through:
// Stripe rejects some of these only after the product already exists.
func (s Settings) Validate() error {
	var errs []string
	add := func(format string, a ...any) { errs = append(errs, fmt.Sprintf(format, a...)) }

	if strings.TrimSpace(s.ProductName) == "" {
		add("donations.productName is required (it is what donors see on the checkout page)")
	}

	a := s.Amounts
	switch {
	case a.Minimum < 1:
		add("donations.amounts.minimum must be at least 1, got %d", a.Minimum)
	case a.Maximum > maxStripeAmount:
		add("donations.amounts.maximum must be at most %d, got %d", maxStripeAmount, a.Maximum)
	case !(a.Minimum <= a.Preset && a.Preset <= a.Maximum):
		add("donations.amounts must satisfy minimum <= preset <= maximum, got %d <= %d <= %d", a.Minimum, a.Preset, a.Maximum)
	}

	if len(s.Apps) == 0 {
		add("donations.apps must list at least one app (each gets its own Payment Link)")
	}
	seen := map[string]bool{}
	for i, app := range s.Apps {
		if !appKeyRe.MatchString(app.Key) {
			add("donations.apps[%d].key %q must be lowercase kebab-case, 2-40 characters", i, app.Key)
		}
		if seen[app.Key] {
			add("donations.apps[%d].key %q is listed twice; keys name resources and must be unique", i, app.Key)
		}
		seen[app.Key] = true
		if strings.TrimSpace(app.Name) == "" {
			add("donations.apps[%d].name is required", i)
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("invalid donations config:\n  - %s", strings.Join(errs, "\n  - "))
	}
	return nil
}

// LinkMetadata is attached to each Payment Link so Stripe's dashboard and
// exports show which app a donation came from. product-line keeps donations
// apart from paid products once both live in the same account.
func LinkMetadata(app App, stack string) map[string]string {
	return map[string]string{
		"app":          app.Key,
		"product-line": "donations",
		"managed-by":   "pulumi",
		"stack":        stack,
	}
}
