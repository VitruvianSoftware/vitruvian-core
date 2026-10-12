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
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type seen struct {
	typeToken string
	name      string
	protect   bool
	importID  string
}

type mocks struct{ got *[]seen }

func (m mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	s := seen{typeToken: args.TypeToken, name: args.Name}
	if rpc := args.RegisterRPC; rpc != nil {
		s.protect = rpc.GetProtect()
		s.importID = rpc.GetImportId()
	}
	*m.got = append(*m.got, s)
	return args.Name + "_id", args.Inputs, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func run(t *testing.T) []seen {
	t.Helper()
	var got []seen
	if err := pulumi.RunErr(Manage, pulumi.WithMocks("repo-config", "dev", mocks{&got})); err != nil {
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
	err := pulumi.RunErr(Manage, pulumi.WithMocks("repo-config", "dev", mocks{&got}))
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
func TestDeclaresExactlyTheThreeResourcesImportedAndProtected(t *testing.T) {
	t.Setenv(Switch, "true")
	t.Setenv("CLOUDFLARE_API_TOKEN", "test-not-a-real-token")
	got := run(t)

	want := map[string]string{
		"site-apex-cname":          "cloudflare:index/record:Record",
		"site-pages-challenge-txt": "cloudflare:index/record:Record",
		"site-pages":               "github:index/repositoryPages:RepositoryPages",
	}
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
		if s.importID == "" {
			t.Errorf("%s must be imported by id: it already exists", s.name)
		}
	}
}

// The zone also carries mail, identity and other tools' records. This package
// may own the apex CNAME and this organisation's Pages challenge, nothing else.
func TestOwnsOnlyTheSiteRecords(t *testing.T) {
	apexCNAMEs, challenges := 0, 0
	for _, r := range Records() {
		switch {
		case r.Type == "CNAME" && r.Name == Apex:
			apexCNAMEs++
		case r.Type == "TXT" && r.Name == challengePrefix+"vitruviansoftware":
			challenges++
		default:
			t.Errorf("record %q (%s %s) is not one of the site's own records; "+
				"MX, SPF, DKIM, Google verification and other tools' records "+
				"must stay out of this package", r.Resource, r.Type, r.Name)
		}
		if r.ID == "" {
			t.Errorf("record %q has no id to adopt", r.Resource)
		}
	}
	if apexCNAMEs != 1 || challenges != 1 {
		t.Errorf("want exactly one apex CNAME and one challenge TXT, got %d and %d", apexCNAMEs, challenges)
	}
}
