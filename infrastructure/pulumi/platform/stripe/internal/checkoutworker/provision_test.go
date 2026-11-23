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

package checkoutworker

import (
	"os"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"gopkg.in/yaml.v3"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/account"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/donations"
)

func validSettings() Settings {
	return Settings{
		CloudflareZone:      "vitruviansoftware.dev",
		CloudflareZoneID:    "fa827eb1be98b4f6059cf34f90c64774",
		CustomDomain:        "donate-api.vitruviansoftware.dev",
		WorkerName:          "vitruvian-donate-checkout",
		AllowedOrigin:       "https://vitruviansoftware.dev",
		SiteBaseURL:         "https://vitruviansoftware.dev",
		TurnstileWidgetName: "vitruvian-donate",
		TurnstileDomains:    []string{"vitruviansoftware.dev"},
	}
}

func validDonations() donations.Settings {
	return donations.Settings{
		ProductName:     "Support Vitruvian Software",
		Amounts:         donations.Amounts{Minimum: 100, Preset: 500, Maximum: 100000},
		ThankYouMessage: "Thank you!",
		Apps: []donations.App{
			{Key: "development", Name: "Vitruvian Software"},
			{Key: "vitruvian", Name: "Vitruvian Atrium"},
		},
	}
}

func TestValidate(t *testing.T) {
	if err := validSettings().Validate(account.ModeLive); err != nil {
		t.Fatalf("valid live config rejected: %v", err)
	}

	sSandbox := validSettings()
	sSandbox.TurnstileDomains = []string{"vitruviansoftware.dev", "localhost", "127.0.0.1"}
	if err := sSandbox.Validate(account.ModeTest); err != nil {
		t.Fatalf("valid test config with localhost rejected: %v", err)
	}
	if err := sSandbox.Validate(account.ModeLive); err == nil || !strings.Contains(err.Error(), "forbidden in live mode") {
		t.Fatalf("expected live mode rejection for localhost, got %v", err)
	}

	cases := map[string]struct {
		mutate func(*Settings)
		want   string
	}{
		"missing zone":            {func(s *Settings) { s.CloudflareZone = "" }, "cloudflareZone"},
		"missing zone id":         {func(s *Settings) { s.CloudflareZoneID = "" }, "cloudflareZoneId"},
		"domain outside zone":     {func(s *Settings) { s.CustomDomain = "donate.ipv1337.dev" }, "subdomain of cloudflareZone"},
		"bad worker name":         {func(s *Settings) { s.WorkerName = "Bad_Worker" }, "workerName"},
		"allowedOrigin http":      {func(s *Settings) { s.AllowedOrigin = "http://vitruviansoftware.dev" }, "allowedOrigin"},
		"allowedOrigin trailing":  {func(s *Settings) { s.AllowedOrigin = "https://vitruviansoftware.dev/" }, "allowedOrigin"},
		"siteBaseUrl trailing":    {func(s *Settings) { s.SiteBaseURL = "https://vitruviansoftware.dev/" }, "siteBaseUrl"},
		"missing widget name":     {func(s *Settings) { s.TurnstileWidgetName = " " }, "turnstileWidgetName"},
		"empty turnstile domains": {func(s *Settings) { s.TurnstileDomains = nil }, "at least one hostname"},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			s := validSettings()
			tc.mutate(&s)
			err := s.Validate(account.ModeTest)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("want error containing %q, got %v", tc.want, err)
			}
		})
	}
}

func TestCommittedStackCheckoutWorkerConfigs(t *testing.T) {
	cases := []struct {
		file string
		mode account.Mode
	}{
		{"../../Pulumi.sandbox.yaml", account.ModeTest},
		{"../../Pulumi.production.yaml", account.ModeLive},
	}
	for _, tc := range cases {
		t.Run(tc.file, func(t *testing.T) {
			raw, err := os.ReadFile(tc.file)
			if err != nil {
				t.Fatalf("read %s: %v", tc.file, err)
			}
			var doc struct {
				Config map[string]yaml.Node `yaml:"config"`
			}
			if err := yaml.Unmarshal(raw, &doc); err != nil {
				t.Fatalf("parse %s: %v", tc.file, err)
			}
			node, ok := doc.Config["vitruvian-stripe:checkoutWorker"]
			if !ok {
				t.Fatalf("%s missing vitruvian-stripe:checkoutWorker", tc.file)
			}
			var s Settings
			if err := node.Decode(&s); err != nil {
				t.Fatalf("decode checkoutWorker in %s: %v", tc.file, err)
			}
			if err := s.Validate(tc.mode); err != nil {
				t.Fatalf("validate checkoutWorker in %s: %v", tc.file, err)
			}
		})
	}
}

type seenResource struct {
	typeToken string
	name      string
	protect   bool
	inputs    resource.PropertyMap
}

type cfMocks struct {
	mu  *sync.Mutex
	got *[]seenResource
}

func (m cfMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	*m.got = append(*m.got, seenResource{
		typeToken: args.TypeToken,
		name:      args.Name,
		protect:   args.RegisterRPC != nil && args.RegisterRPC.GetProtect(),
		inputs:    args.Inputs,
	})
	m.mu.Unlock()

	outs := args.Inputs.Copy()
	if args.TypeToken == "cloudflare:index/turnstileWidget:TurnstileWidget" {
		outs["secret"] = resource.NewStringProperty("0xMOCK_TURNSTILE_SECRET")
		return "0xMOCK_SITEKEY", outs, nil
	}
	return args.Name + "_id", outs, nil
}

func (cfMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func runProvision(t *testing.T, mode account.Mode) ([]seenResource, error) {
	t.Helper()
	var got []seenResource
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := Provision(ctx, ProvisionArgs{
			Mode:         mode,
			Settings:     validSettings(),
			Donations:    validDonations(),
			PriceID:      pulumi.ID("price_123").ToIDOutput(),
			StripeAPIKey: pulumi.ToSecret(pulumi.String("sk_live_mock")).(pulumi.StringOutput),
		})
		return err
	}, pulumi.WithMocks("vitruvian-stripe", "test", cfMocks{mu: &sync.Mutex{}, got: &got}))
	return got, err
}

func TestProvisionDormantAndPartialEnvErrors(t *testing.T) {
	t.Setenv(TokenEnv, "")
	t.Setenv(AccountIDEnv, "")
	got, err := runProvision(t, account.ModeLive)
	if err != nil {
		t.Fatalf("dormant Provision failed: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("expected 0 resources when Cloudflare env vars unset, got %d", len(got))
	}

	t.Setenv(TokenEnv, "cf-token")
	t.Setenv(AccountIDEnv, "")
	if _, err := runProvision(t, account.ModeLive); err == nil || !strings.Contains(err.Error(), AccountIDEnv) {
		t.Fatalf("expected error naming %s, got %v", AccountIDEnv, err)
	}

	t.Setenv(TokenEnv, "")
	t.Setenv(AccountIDEnv, "cf-account")
	if _, err := runProvision(t, account.ModeLive); err == nil || !strings.Contains(err.Error(), TokenEnv) {
		t.Fatalf("expected error naming %s, got %v", TokenEnv, err)
	}
}

func TestProvisionResourcesAndProtection(t *testing.T) {
	for _, tc := range []struct {
		name        string
		mode        account.Mode
		wantProtect bool
	}{
		{"live mode protects widget and domain", account.ModeLive, true},
		{"test mode leaves widget and domain unprotected", account.ModeTest, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv(TokenEnv, "cf-token")
			t.Setenv(AccountIDEnv, "cf-account")
			got, err := runProvision(t, tc.mode)
			if err != nil {
				t.Fatalf("Provision: %v", err)
			}

			byName := map[string]seenResource{}
			for _, r := range got {
				if strings.HasPrefix(r.typeToken, "pulumi:providers:") {
					continue
				}
				byName[r.name] = r
			}
			if len(byName) != 3 {
				t.Fatalf("declared %d resources, want 3: %+v", len(byName), byName)
			}

			widget, ok := byName["donate-turnstile"]
			if !ok || widget.typeToken != "cloudflare:index/turnstileWidget:TurnstileWidget" {
				t.Fatalf("missing turnstile widget resource: %+v", widget)
			}
			if widget.protect != tc.wantProtect {
				t.Errorf("widget protect = %v, want %v", widget.protect, tc.wantProtect)
			}

			domain, ok := byName["donate-checkout-domain"]
			if !ok || domain.typeToken != "cloudflare:index/workersDomain:WorkersDomain" {
				t.Fatalf("missing workers domain resource: %+v", domain)
			}
			if domain.protect != tc.wantProtect {
				t.Errorf("domain protect = %v, want %v", domain.protect, tc.wantProtect)
			}

			script, ok := byName["donate-checkout-worker"]
			if !ok || script.typeToken != "cloudflare:index/workersScript:WorkersScript" {
				t.Fatalf("missing workers script resource: %+v", script)
			}
			if mod := script.inputs["module"]; !mod.HasValue() || !mod.BoolValue() {
				t.Errorf("worker script module = %v, want true", mod)
			}

			plainNames := map[string]bool{}
			for _, b := range script.inputs["plainTextBindings"].ArrayValue() {
				if n := b.ObjectValue()["name"]; n.IsString() {
					plainNames[n.StringValue()] = true
				}
			}
			for _, want := range []string{
				"DONATIONS_PRICE_ID",
				"ALLOWED_APPS_JSON",
				"SUBMIT_MESSAGE",
				"ALLOWED_ORIGIN",
				"TURNSTILE_HOSTNAMES",
				"SITE_BASE_URL",
			} {
				if !plainNames[want] {
					t.Errorf("worker missing plainTextBinding %q", want)
				}
			}

			secretNames := map[string]bool{}
			for _, b := range script.inputs["secretTextBindings"].ArrayValue() {
				if n := b.ObjectValue()["name"]; n.IsString() {
					secretNames[n.StringValue()] = true
				}
			}
			for _, want := range []string{"STRIPE_API_KEY", "TURNSTILE_SECRET"} {
				if !secretNames[want] {
					t.Errorf("worker missing secretTextBinding %q", want)
				}
			}
		})
	}
}

func TestWorkerScriptInvariants(t *testing.T) {
	for _, want := range []string{
		"https://challenges.cloudflare.com/turnstile/v0/siteverify",
		"https://api.stripe.com/v1/checkout/sessions",
		"verifyResult.action !== EXPECTED_ACTION",
		"expectedHostnames.has(verifyResult.hostname)",
		"https://checkout.stripe.com/",
	} {
		if !strings.Contains(WorkerScript, want) {
			t.Errorf("worker.js missing invariant %q", want)
		}
	}
	if strings.Contains(WorkerScript, `"Access-Control-Allow-Origin": "*"`) {
		t.Errorf("worker.js must never use wildcard CORS")
	}
}
