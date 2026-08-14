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

package revision

import (
	"regexp"
	"strings"
	"testing"
)

func TestEnvMap(t *testing.T) {
	const apiURL = "https://tabula-api.dev.vitruviansoftware.dev/api/v1"

	t.Run("always carries NODE_ENV and HOSTNAME", func(t *testing.T) {
		env := EnvMap("")
		for key, want := range map[string]string{
			"NODE_ENV": "production",
			"HOSTNAME": "0.0.0.0",
		} {
			if got := env[key]; got != want {
				t.Errorf("env[%q] = %q, want %q", key, got, want)
			}
		}
	})

	t.Run("carries API_URL when set", func(t *testing.T) {
		env := EnvMap(apiURL)
		if got := env["API_URL"]; got != apiURL {
			t.Errorf("env[API_URL] = %q, want %q", got, apiURL)
		}
	})

	// Empty must mean ABSENT, not empty-string — matches
	// tabula/infra/app/revision.EnvMap's contract (see its own test for why:
	// an explicitly-empty Cloud Run env var is noise in the revision diff and
	// hides which envs have been configured).
	t.Run("omits API_URL rather than setting it empty when unconfigured", func(t *testing.T) {
		env := EnvMap("")
		if _, ok := env["API_URL"]; ok {
			t.Errorf("env[API_URL] present (%q); want absent when unconfigured", env["API_URL"])
		}
	})
}

func TestShortDigest(t *testing.T) {
	t.Run("extracts the 8-hex fragment after @sha256:", func(t *testing.T) {
		got, err := ShortDigest("us-central1-docker.pkg.dev/p/tabula/web@sha256:1c1447862222deadbeef")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "1c144786" {
			t.Errorf("ShortDigest = %q, want 1c144786", got)
		}
	})

	t.Run("errors on a non-digest ref", func(t *testing.T) {
		for _, in := range []string{"", "no-marker", "x@sha256:short"} {
			if _, err := ShortDigest(in); err == nil {
				t.Errorf("ShortDigest(%q) = nil error, want error", in)
			}
		}
	})
}

// A Cloud Run revision is immutable: its name identifies image AND config
// together, so a revision name must change whenever API_URL changes — this is
// the exact env value that was silently wrong across environments (a single
// build-time constant baked into the client bundle) before this change made
// it a per-environment runtime env var instead.
func TestName(t *testing.T) {
	const (
		svc    = "tabula-web-development"
		digest = "1c144786"
	)
	base := EnvMap("https://a.example/api/v1")

	t.Run("is stable for the same image and config", func(t *testing.T) {
		a := Name(svc, digest, base)
		b := Name(svc, digest, EnvMap("https://a.example/api/v1"))
		if a != b {
			t.Errorf("unstable across equal configs (map order must not matter): %q vs %q", a, b)
		}
	})

	t.Run("changes when API_URL changes, same image", func(t *testing.T) {
		changed := EnvMap("https://b.example/api/v1")
		if got, other := Name(svc, digest, base), Name(svc, digest, changed); got == other {
			t.Errorf("same revision name %q for different API_URL — a promotion to a new env would silently keep serving the OLD env's API host", got)
		}
	})

	t.Run("changes when the image changes, same config", func(t *testing.T) {
		if got, other := Name(svc, digest, base), Name(svc, "deadbeef", base); got == other {
			t.Errorf("same revision name %q for different images", got)
		}
	})

	t.Run("stays a legal Cloud Run revision name", func(t *testing.T) {
		got := Name(svc, digest, base)
		if !strings.HasPrefix(got, svc+"-") {
			t.Errorf("%q is not prefixed with the service name", got)
		}
		if len(got) > 63 {
			t.Errorf("%q is %d chars, over the 63 limit", got, len(got))
		}
		if !regexp.MustCompile(`^[a-z][a-z0-9-]*$`).MatchString(got) {
			t.Errorf("%q is not a legal RFC1035 name", got)
		}
	})
}
