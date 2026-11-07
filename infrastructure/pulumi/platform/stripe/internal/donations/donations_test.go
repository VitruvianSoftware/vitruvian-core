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

package donations

import (
	"os"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe/internal/account"
)

func valid() Settings {
	return Settings{
		ProductName:     "Support Vitruvian Software",
		Amounts:         Amounts{Minimum: 100, Preset: 500, Maximum: 100000},
		ThankYouMessage: "Thank you!",
		Apps:            []App{{Key: "vitruvian", Name: "Vitruvian"}},
	}
}

func TestValidateAcceptsGoodConfig(t *testing.T) {
	if err := valid().Validate(); err != nil {
		t.Fatalf("valid config rejected: %v", err)
	}
}

func TestValidateRejectsBadConfig(t *testing.T) {
	cases := map[string]struct {
		mutate func(*Settings)
		want   string
	}{
		"missing product name": {func(s *Settings) { s.ProductName = " " }, "productName"},
		"preset below minimum": {func(s *Settings) { s.Amounts.Preset = 50 }, "minimum <= preset <= maximum"},
		"preset above maximum": {func(s *Settings) { s.Amounts.Preset = 200000 }, "minimum <= preset <= maximum"},
		"zero minimum":         {func(s *Settings) { s.Amounts.Minimum = 0 }, "amounts.minimum"},
		"maximum over cap":     {func(s *Settings) { s.Amounts.Maximum = 100_000_000 }, "amounts.maximum"},
		"no apps":              {func(s *Settings) { s.Apps = nil }, "at least one app"},
		"bad app key":          {func(s *Settings) { s.Apps[0].Key = "Vitruvian App" }, "kebab-case"},
		"duplicate app key": {func(s *Settings) {
			s.Apps = append(s.Apps, App{Key: "vitruvian", Name: "Again"})
		}, "listed twice"},
		"missing app name": {func(s *Settings) { s.Apps[0].Name = "" }, "apps[0].name"},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			s := valid()
			tc.mutate(&s)
			err := s.Validate()
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("want error containing %q, got %v", tc.want, err)
			}
		})
	}
}

func TestLinkMetadataNamesTheApp(t *testing.T) {
	md := LinkMetadata(App{Key: "home-speaker", Name: "HomeSpeaker"}, "sandbox")
	if md["app"] != "home-speaker" || md["product-line"] != "donations" || md["stack"] != "sandbox" || md["managed-by"] != "pulumi" {
		t.Fatalf("unexpected metadata: %v", md)
	}
}

// ns is the stack's config namespace: the `name:` in Pulumi.yaml.
const ns = "vitruvian-stripe:"

// The committed sandbox stack config must pass the same validation the apply
// runs, and must stay in test mode: a live-mode flip belongs in its own stack.
func TestCommittedSandboxConfig(t *testing.T) {
	raw, err := os.ReadFile("../../Pulumi.sandbox.yaml")
	if err != nil {
		t.Fatalf("read stack config: %v", err)
	}
	var doc struct {
		Config map[string]yaml.Node `yaml:"config"`
	}
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("parse stack config: %v", err)
	}
	if _, ok := doc.Config["stripe:apiKey"]; ok {
		t.Fatal("Pulumi.sandbox.yaml sets stripe:apiKey; the program passes the key to the provider itself (internal/stripekey), so set STRIPE_API_KEY or the secret " + ns + "apiKey instead")
	}
	// The key may only appear as Pulumi ciphertext (`pulumi config set
	// --secret`), never as a plain string.
	if n, ok := doc.Config[ns+"apiKey"]; ok {
		var secure struct {
			Secure string `yaml:"secure"`
		}
		if n.Kind != yaml.MappingNode || n.Decode(&secure) != nil || secure.Secure == "" {
			t.Fatal(ns + "apiKey is in Pulumi.sandbox.yaml as plaintext; set it with `config -- set --secret apiKey` so only ciphertext is committed, or use STRIPE_API_KEY")
		}
	}

	decode := func(key string, into any) {
		t.Helper()
		n, ok := doc.Config[ns+key]
		if !ok {
			t.Fatalf("Pulumi.sandbox.yaml is missing %s%s", ns, key)
		}
		if err := n.Decode(into); err != nil {
			t.Fatalf("decode %s%s: %v", ns, key, err)
		}
	}
	var acct account.Settings
	var mode string
	decode("mode", &mode)
	acct.Mode = account.Mode(mode)
	decode("currency", &acct.Currency)
	if err := acct.Validate(); err != nil {
		t.Fatal(err)
	}
	if acct.Mode != account.ModeTest {
		t.Fatalf("the sandbox stack must stay in test mode, got %q", acct.Mode)
	}

	var s Settings
	decode("donations", &s)
	if err := s.Validate(); err != nil {
		t.Fatal(err)
	}
}
