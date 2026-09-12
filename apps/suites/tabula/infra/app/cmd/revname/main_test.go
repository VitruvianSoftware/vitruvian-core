/*
Copyright (c) 2026 VitruvianSoftware

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

package main

import (
	"os"
	"path/filepath"
	"regexp"
	"testing"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/tabula/revision"
)

func writeConfig(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "Pulumi.development.yaml")
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

const digest = "us-central1-docker.pkg.dev/p/tabula/app@sha256:de6621651234567890"

func TestComputeRevisionName(t *testing.T) {
	cfg := writeConfig(t, `config:
  tabula-app:project: "prj-d-bu2-oss-floating-c3d1"
  tabula-app:environment: "development"
  tabula-app:apiUrl: "https://tabula-api.dev.vitruviansoftware.dev/api/v1"
  tabula-app:authPostmessageOrigin: "chrome-extension://eblknkhkhfolhecoobmpjhfejfcmfoof"
  tabula-app:corsOrigin: "https://tabula.dev.vitruviansoftware.dev"
`)

	t.Run("matches what the revision package produces", func(t *testing.T) {
		got, err := computeRevisionName(cfg, digest)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		// Independently reconstruct the expected name from the shared package —
		// this is the exact equivalence the preflight relies on.
		env := revision.EnvMap(
			"prj-d-bu2-oss-floating-c3d1",
			"https://tabula-api.dev.vitruviansoftware.dev/api/v1",
			"chrome-extension://eblknkhkhfolhecoobmpjhfejfcmfoof",
			"https://tabula.dev.vitruviansoftware.dev",
		)
		want := revision.Name("tabula-api-development", "de662165", env)
		if got != want {
			t.Errorf("computeRevisionName = %q, want %q", got, want)
		}
		if !regexp.MustCompile(`^tabula-api-development-de662165-[0-9a-f]{6}$`).MatchString(got) {
			t.Errorf("%q is not the expected shape", got)
		}
	})

	t.Run("the same digest+config is stable across calls", func(t *testing.T) {
		a, _ := computeRevisionName(cfg, digest)
		b, _ := computeRevisionName(cfg, digest)
		if a != b {
			t.Errorf("unstable: %q vs %q", a, b)
		}
	})

	t.Run("a changed config value changes the name (same digest)", func(t *testing.T) {
		other := writeConfig(t, `config:
  tabula-app:project: "prj-d-bu2-oss-floating-c3d1"
  tabula-app:environment: "development"
  tabula-app:apiUrl: "https://DIFFERENT.example/api/v1"
  tabula-app:authPostmessageOrigin: "chrome-extension://eblknkhkhfolhecoobmpjhfejfcmfoof"
`)
		a, _ := computeRevisionName(cfg, digest)
		b, err := computeRevisionName(other, digest)
		if err != nil {
			t.Fatal(err)
		}
		if a == b {
			t.Errorf("different config produced the same name %q — the preflight would wrongly skip a real deploy", a)
		}
	})

	// Every error path must return an error, so the preflight fails OPEN
	// (deploys) rather than emitting a bogus name that could never match live —
	// or worse, a partial name that accidentally does.
	t.Run("fails loud on malformed or incomplete input", func(t *testing.T) {
		cases := map[string]struct{ path, digest string }{
			"missing file":   {filepath.Join(t.TempDir(), "nope.yaml"), digest},
			"not a digest":   {cfg, "latest"},
			"absent project": {writeConfig(t, "config:\n  tabula-app:environment: \"development\"\n"), digest},
			"absent env":     {writeConfig(t, "config:\n  tabula-app:project: \"p\"\n"), digest},
			"garbage yaml":   {writeConfig(t, ":\n\t- ]["), digest},
		}
		for name, tc := range cases {
			if _, err := computeRevisionName(tc.path, tc.digest); err == nil {
				t.Errorf("%s: got nil error, want error (must fail open)", name)
			}
		}
	})
}
