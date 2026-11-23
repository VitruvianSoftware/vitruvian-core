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

// Package checkoutworker provisions the Cloudflare Turnstile widget, the
// checkout Worker script, and its Workers Custom Domain alongside the Stripe
// donation stack.
package checkoutworker

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/account"
)

var workerNameRe = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,62}$`)

// Settings holds the Cloudflare Worker and Turnstile widget settings under
// vitruvian-stripe:checkoutWorker in each stack config.
type Settings struct {
	CloudflareZone      string   `json:"cloudflareZone" yaml:"cloudflareZone"`
	CloudflareZoneID    string   `json:"cloudflareZoneId" yaml:"cloudflareZoneId"`
	CustomDomain        string   `json:"customDomain" yaml:"customDomain"`
	WorkerName          string   `json:"workerName" yaml:"workerName"`
	AllowedOrigin       string   `json:"allowedOrigin" yaml:"allowedOrigin"`
	SiteBaseURL         string   `json:"siteBaseUrl" yaml:"siteBaseUrl"`
	TurnstileWidgetName string   `json:"turnstileWidgetName" yaml:"turnstileWidgetName"`
	TurnstileDomains    []string `json:"turnstileDomains" yaml:"turnstileDomains"`
}

// Validate checks that every required field is well-formed and that live mode
// never permits local development hostnames on the Turnstile allowlist.
func (s Settings) Validate(mode account.Mode) error {
	var errs []string
	add := func(format string, a ...any) { errs = append(errs, fmt.Sprintf(format, a...)) }

	if strings.TrimSpace(s.CloudflareZone) == "" {
		add("checkoutWorker.cloudflareZone is required")
	}
	if strings.TrimSpace(s.CloudflareZoneID) == "" {
		add("checkoutWorker.cloudflareZoneId is required")
	}
	if strings.TrimSpace(s.CustomDomain) == "" {
		add("checkoutWorker.customDomain is required")
	} else if s.CloudflareZone != "" && !strings.HasSuffix(s.CustomDomain, "."+s.CloudflareZone) {
		add("checkoutWorker.customDomain %q must be a subdomain of cloudflareZone %q", s.CustomDomain, s.CloudflareZone)
	}
	if !workerNameRe.MatchString(s.WorkerName) {
		add("checkoutWorker.workerName %q must match ^[a-z0-9][a-z0-9-]{0,62}$", s.WorkerName)
	}
	if !strings.HasPrefix(s.AllowedOrigin, "https://") || strings.HasSuffix(s.AllowedOrigin, "/") {
		add("checkoutWorker.allowedOrigin %q must start with https:// and have no trailing /", s.AllowedOrigin)
	}
	if !strings.HasPrefix(s.SiteBaseURL, "https://") || strings.HasSuffix(s.SiteBaseURL, "/") {
		add("checkoutWorker.siteBaseUrl %q must start with https:// and have no trailing /", s.SiteBaseURL)
	}
	if strings.TrimSpace(s.TurnstileWidgetName) == "" {
		add("checkoutWorker.turnstileWidgetName is required")
	}
	if len(s.TurnstileDomains) == 0 {
		add("checkoutWorker.turnstileDomains must list at least one hostname")
	}
	for i, d := range s.TurnstileDomains {
		trimmed := strings.TrimSpace(d)
		if trimmed == "" {
			add("checkoutWorker.turnstileDomains[%d] must not be empty", i)
			continue
		}
		if mode == account.ModeLive && (trimmed == "localhost" || trimmed == "127.0.0.1") {
			add("checkoutWorker.turnstileDomains[%d] %q is forbidden in live mode", i, trimmed)
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("invalid checkoutWorker config:\n  - %s", strings.Join(errs, "\n  - "))
	}
	return nil
}

// CheckoutURL returns the public POST endpoint served by the Worker custom domain.
func (s Settings) CheckoutURL() string {
	return "https://" + s.CustomDomain + "/checkout"
}
