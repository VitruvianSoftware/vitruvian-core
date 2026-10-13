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

package site_domain

import (
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type seen struct {
	typeToken string
	name      string
	protect   bool
	importID  string
	// proxied is the `proxied` input sent to the provider; nil when absent.
	proxied *bool
}

// Pulumi registers resources concurrently, so the mock must serialise its own
// bookkeeping: an unlocked append loses entries and fails a count assertion
// intermittently.
type mocks struct {
	got *[]seen
	mu  *sync.Mutex
}

func (m mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	s := seen{typeToken: args.TypeToken, name: args.Name}
	if v, ok := args.Inputs["proxied"]; ok && v.IsBool() {
		b := v.BoolValue()
		s.proxied = &b
	}
	if rpc := args.RegisterRPC; rpc != nil {
		s.protect = rpc.GetProtect()
		s.importID = rpc.GetImportId()
	}
	m.mu.Lock()
	*m.got = append(*m.got, s)
	m.mu.Unlock()
	return args.Name + "_id", args.Inputs, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func run(t *testing.T) []seen {
	t.Helper()
	var got []seen
	if err := pulumi.RunErr(Manage, pulumi.WithMocks("repo-config", "dev", mocks{&got, &sync.Mutex{}})); err != nil {
		t.Fatalf("Manage: %v", err)
	}
	return got
}

// With the switch off the package must declare nothing: it ships dormant, so
// merging it changes no live record and no preview.
func TestDormantByDefault(t *testing.T) {
	t.Setenv(Switch, "")
	if got := run(t); len(got) != 0 {
		t.Fatalf("declared %d resources with the switch off: %+v", len(got), got)
	}
}

// Switched on without the token must fail with a message that names the
// missing secret, not with the provider's generic error.
func TestSwitchOnWithoutTokenFailsNamingTheSecret(t *testing.T) {
	t.Setenv(Switch, "true")
	t.Setenv("CLOUDFLARE_API_TOKEN", "")
	var got []seen
	err := pulumi.RunErr(Manage, pulumi.WithMocks("repo-config", "dev", mocks{&got, &sync.Mutex{}}))
	if err == nil {
		t.Fatal("Manage succeeded with the switch on and no token")
	}
	if !strings.Contains(err.Error(), "DNS_CLOUDFLARE_API_TOKEN") {
		t.Fatalf("error does not name the secret: %v", err)
	}
}

func TestOnlyTrueTurnsItOn(t *testing.T) {
	for _, v := range []string{"1", "yes", "TRUE", "True"} {
		t.Setenv(Switch, v)
		if Enabled() {
			t.Errorf("%s=%q must not enable the package", Switch, v)
		}
	}
	t.Setenv(Switch, "true")
	if !Enabled() {
		t.Errorf("%s=true must enable the package", Switch)
	}
}

// Everything it declares is a live resource being adopted, and every one is
// protected: a stray edit that would delete or replace one must fail the run.
func TestDeclaresExactlyTheFourResourcesProtectedAndImportedWhereTheyExist(t *testing.T) {
	t.Setenv(Switch, "true")
	t.Setenv("CLOUDFLARE_API_TOKEN", "test-not-a-real-token")
	got := run(t)

	want := map[string]string{
		"site-apex-cname":          "cloudflare:index/record:Record",
		"site-pages-challenge-txt": "cloudflare:index/record:Record",
		"site-www-cname":           "cloudflare:index/record:Record",
		"site-pages":               "github:index/repositoryPages:RepositoryPages",
	}
	// www did not exist before this package, so it is created, not imported.
	created := map[string]bool{"site-www-cname": true}
	// The mocks also see the default providers; only count real resources.
	var real []seen
	for _, s := range got {
		if !strings.HasPrefix(s.typeToken, "pulumi:providers:") {
			real = append(real, s)
		}
	}
	if len(real) != len(want) {
		t.Fatalf("declared %d resources, want %d: %+v", len(real), len(want), real)
	}
	for _, s := range real {
		tok, ok := want[s.name]
		if !ok {
			t.Errorf("unexpected resource %q (%s)", s.name, s.typeToken)
			continue
		}
		if s.typeToken != tok {
			t.Errorf("%s has type %s, want %s", s.name, s.typeToken, tok)
		}
		if !s.protect {
			t.Errorf("%s must be protected", s.name)
		}
		if s.typeToken == "cloudflare:index/record:Record" {
			wantProxied := s.name == "site-www-cname"
			if s.proxied == nil || *s.proxied != wantProxied {
				t.Errorf("%s sent proxied=%v to the provider, want %v", s.name, s.proxied, wantProxied)
			}
		}
		if created[s.name] {
			if s.importID != "" {
				t.Errorf("%s is created by this package, not imported (import id %q)", s.name, s.importID)
			}
		} else if s.importID == "" {
			t.Errorf("%s must be imported by id: it already exists", s.name)
		}
	}
}

// Only www is proxied. The apex must stay DNS-only so GitHub can issue and
// renew its certificate; proxying it would break that silently, weeks later.
func TestOnlyWwwIsProxied(t *testing.T) {
	for _, r := range Records() {
		want := r.Name == "www"
		if r.Proxied != want {
			t.Errorf("record %q (%s): Proxied = %v, want %v", r.Resource, r.Name, r.Proxied, want)
		}
	}
}

// The zone also carries mail, identity and other tools' records. This package
// may own the apex CNAME and this organisation's Pages challenge, nothing else.
func TestOwnsOnlyTheSiteRecords(t *testing.T) {
	apexCNAMEs, challenges, www := 0, 0, 0
	for _, r := range Records() {
		switch {
		case r.Type == "CNAME" && r.Name == Apex:
			apexCNAMEs++
		case r.Type == "CNAME" && r.Name == "www":
			www++
		case r.Type == "TXT" && r.Name == challengePrefix+"vitruviansoftware":
			challenges++
		default:
			t.Errorf("record %q (%s %s) is not one of the site's own records; "+
				"MX, SPF, DKIM, Google verification and other tools' records "+
				"must stay out of this package", r.Resource, r.Type, r.Name)
		}
		// Only www is created here; everything else is adopted and needs its id.
		if r.ID == "" && r.Name != "www" {
			t.Errorf("record %q has no id to adopt", r.Resource)
		}
	}
	if apexCNAMEs != 1 || challenges != 1 || www != 1 {
		t.Errorf("want exactly one apex CNAME, one challenge TXT and one www CNAME, got %d, %d and %d", apexCNAMEs, challenges, www)
	}
}
