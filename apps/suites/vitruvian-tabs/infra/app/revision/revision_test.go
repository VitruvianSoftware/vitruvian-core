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
	const (
		project = "prj-d-bu2-oss-floating-c3d1"
		apiURL  = "https://tabula-api.dev.vitruviansoftware.dev/api/v1"
		extOrig = "chrome-extension://eblknkhkhfolhecoobmpjhfejfcmfoof"
	)

	t.Run("carries the public auth config when set", func(t *testing.T) {
		env := EnvMap(project, apiURL, extOrig, "")

		for key, want := range map[string]string{
			"NODE_ENV":                "production",
			"GOOGLE_CLOUD_PROJECT":    project,
			"SECRET_PREFIX":           SecretPrefix,
			"API_URL":                 apiURL,
			"AUTH_POSTMESSAGE_ORIGIN": extOrig,
		} {
			if got := env[key]; got != want {
				t.Errorf("env[%q] = %q, want %q", key, got, want)
			}
		}
	})

	// Empty must mean ABSENT, not empty-string: the app's own fallbacks
	// (`process.env.API_URL || ...`) treat "" and unset identically, but an
	// explicitly-empty Cloud Run env var is noise in the revision diff and
	// hides which envs have been configured.
	t.Run("omits unset optional keys rather than setting them empty", func(t *testing.T) {
		env := EnvMap(project, "", "", "")

		for _, key := range []string{"API_URL", "AUTH_POSTMESSAGE_ORIGIN", "CORS_ORIGIN"} {
			if _, ok := env[key]; ok {
				t.Errorf("env[%q] present (%q); want absent when unconfigured", key, env[key])
			}
		}
		if env["GOOGLE_CLOUD_PROJECT"] != project {
			t.Errorf("required keys must still be set; got %v", env)
		}
	})
}

func TestShortDigest(t *testing.T) {
	t.Run("extracts the 8-hex fragment after @sha256:", func(t *testing.T) {
		got, err := ShortDigest("us-central1-docker.pkg.dev/p/tabula/app@sha256:1c1447862222deadbeef")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "1c144786" {
			t.Errorf("ShortDigest = %q, want 1c144786", got)
		}
	})

	// The preflight must FAIL rather than emit a bogus name from a malformed
	// digest — a bogus desired name could never match the live name, so this
	// stays fail-open (deploy), never a false skip.
	t.Run("errors on a non-digest ref", func(t *testing.T) {
		for _, in := range []string{"", "no-marker", "x@sha256:short"} {
			if _, err := ShortDigest(in); err == nil {
				t.Errorf("ShortDigest(%q) = nil error, want error", in)
			}
		}
	})
}

// A Cloud Run revision is immutable: its name identifies image AND config
// together. The name was once derived from the image digest alone, so promoting
// the same image with changed env produced the SAME name for DIFFERENT content,
// and the API rejected it:
//
//	Error 409: Revision named 'tabula-api-development-1c144786' with different
//	configuration already exists.
func TestName(t *testing.T) {
	const (
		svc    = "tabula-api-development"
		digest = "1c144786"
	)
	base := map[string]string{"NODE_ENV": "production", "API_URL": "https://a.example"}

	t.Run("is stable for the same image and config", func(t *testing.T) {
		// Idempotence is load-bearing: the deploy runs `pulumi up` twice (deploy
		// then promote) and reruns after a transient failure must address the
		// SAME revision, not mint a second one. It is ALSO what the preflight
		// relies on to compare a freshly-computed name against the live one.
		a := Name(svc, digest, base)
		b := Name(svc, digest, map[string]string{"API_URL": "https://a.example", "NODE_ENV": "production"})
		if a != b {
			t.Errorf("unstable across equal configs (map order must not matter): %q vs %q", a, b)
		}
	})

	t.Run("changes when config changes, same image", func(t *testing.T) {
		changed := map[string]string{"NODE_ENV": "production", "API_URL": "https://b.example"}
		if got, other := Name(svc, digest, base), Name(svc, digest, changed); got == other {
			t.Errorf("same revision name %q for different config — this is the 409", got)
		}
	})

	t.Run("changes when a key is added", func(t *testing.T) {
		added := map[string]string{"NODE_ENV": "production", "API_URL": "https://a.example", "AUTH_POSTMESSAGE_ORIGIN": "chrome-extension://x"}
		if got, other := Name(svc, digest, base), Name(svc, digest, added); got == other {
			t.Errorf("adding a key did not change the name (%q) — the exact regression that broke this deploy", got)
		}
	})

	t.Run("changes when the image changes, same config", func(t *testing.T) {
		if got, other := Name(svc, digest, base), Name(svc, "deadbeef", base); got == other {
			t.Errorf("same revision name %q for different images", got)
		}
	})

	t.Run("stays a legal Cloud Run revision name", func(t *testing.T) {
		got := Name(svc, digest, base)
		// Cloud Run REQUIRES the revision name to be prefixed with the service
		// name, and it must be RFC1035: <=63 chars, lowercase alnum and '-',
		// starting with a letter.
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
