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
	"regexp"
	"strings"
	"testing"
)

// The bu2 rewrite of this stack dropped two env vars the retired
// infrastructure/pulumi/apps/tabula stack set, and both are load-bearing for
// the browser-extension login flow:
//
//   - API_URL — auth.service.ts builds the WorkOS redirectUri as
//     `${API_URL}/auth/callback`. Unset, it falls back to localhost, so the
//     deployed service asks WorkOS to redirect to the developer's laptop.
//   - AUTH_POSTMESSAGE_ORIGIN — the exact origin the auth callback page
//     postMessages the token to (auth.routes.ts resolvePostMessageOrigin).
//     Unset, it falls back to http://localhost:3000, so the extension's opener
//     never receives the token.
//
// Neither is a secret: one is a public URL, the other a chrome-extension://
// origin. They are plain config precisely so this test can pin them.
func TestEnvMap(t *testing.T) {
	const (
		project = "prj-d-bu2-oss-floating-c3d1"
		apiURL  = "https://tabula-api.dev.vitruviansoftware.dev/api/v1"
		extOrig = "chrome-extension://eblknkhkhfolhecoobmpjhfejfcmfoof"
	)

	t.Run("carries the public auth config when set", func(t *testing.T) {
		env := envMap(project, apiURL, extOrig)

		for key, want := range map[string]string{
			"NODE_ENV":                "production",
			"GOOGLE_CLOUD_PROJECT":    project,
			"SECRET_PREFIX":           secretPrefix,
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
		env := envMap(project, "", "")

		for _, key := range []string{"API_URL", "AUTH_POSTMESSAGE_ORIGIN"} {
			if _, ok := env[key]; ok {
				t.Errorf("env[%q] present (%q); want absent when unconfigured", key, env[key])
			}
		}
		if env["GOOGLE_CLOUD_PROJECT"] != project {
			t.Errorf("required keys must still be set; got %v", env)
		}
	})
}

// A Cloud Run revision is immutable: its name identifies image AND config
// together. The name was derived from the image digest alone, so promoting the
// same image with changed env produced the SAME name for DIFFERENT content, and
// the API rejected it:
//
//	Error 409: Revision named 'tabula-api-development-1c144786' with different
//	configuration already exists.
//
// That is exactly what happened when API_URL and AUTH_POSTMESSAGE_ORIGIN were
// added: one image, promoted by digest through three envs, suddenly carrying
// different env vars. The digest is still necessary in the name (build-once /
// promote-by-digest means the image identifies the artifact) but it is not
// SUFFICIENT.
func TestRevisionNameFor(t *testing.T) {
	const (
		svc    = "tabula-api-development"
		digest = "1c144786"
	)
	base := map[string]string{"NODE_ENV": "production", "API_URL": "https://a.example"}

	t.Run("is stable for the same image and config", func(t *testing.T) {
		// Idempotence is load-bearing: the deploy runs `pulumi up` twice (deploy
		// then promote) and reruns after a transient failure must address the
		// SAME revision, not mint a second one.
		a := revisionNameFor(svc, digest, base)
		b := revisionNameFor(svc, digest, map[string]string{"API_URL": "https://a.example", "NODE_ENV": "production"})
		if a != b {
			t.Errorf("unstable across equal configs (map order must not matter): %q vs %q", a, b)
		}
	})

	t.Run("changes when config changes, same image", func(t *testing.T) {
		changed := map[string]string{"NODE_ENV": "production", "API_URL": "https://b.example"}
		if got, other := revisionNameFor(svc, digest, base), revisionNameFor(svc, digest, changed); got == other {
			t.Errorf("same revision name %q for different config — this is the 409", got)
		}
	})

	t.Run("changes when a key is added", func(t *testing.T) {
		added := map[string]string{"NODE_ENV": "production", "API_URL": "https://a.example", "AUTH_POSTMESSAGE_ORIGIN": "chrome-extension://x"}
		if got, other := revisionNameFor(svc, digest, base), revisionNameFor(svc, digest, added); got == other {
			t.Errorf("adding a key did not change the name (%q) — the exact regression that broke this deploy", got)
		}
	})

	t.Run("changes when the image changes, same config", func(t *testing.T) {
		if got, other := revisionNameFor(svc, digest, base), revisionNameFor(svc, "deadbeef", base); got == other {
			t.Errorf("same revision name %q for different images", got)
		}
	})

	t.Run("stays a legal Cloud Run revision name", func(t *testing.T) {
		got := revisionNameFor(svc, digest, base)
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
