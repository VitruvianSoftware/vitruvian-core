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

package main

import (
	"regexp"
	"testing"
)

// A Cloud Run revision name must be UNIQUE PER CONFIGURATION: Cloud Run rejects
// reusing a name for different config (`409 Revision ... with different
// configuration already exists`). So <service>-<digest> alone is not enough — one
// promoted image deployed with different env would collide. The config hash makes
// the name reflect image AND config, which is the naming rule tabula's app stack
// already follows (revisionNameFor). serverless_space appends whatever suffix the
// leaf gives it, so this is where tabula's identity strategy lives.
func TestConfigHash(t *testing.T) {
	base := map[string]string{"NODE_ENV": "production", "API_URL": "https://a.example", "SECRET_PREFIX": "TABULA_"}

	t.Run("stable across equal envs regardless of map order", func(t *testing.T) {
		a := configHash(base)
		b := configHash(map[string]string{"SECRET_PREFIX": "TABULA_", "API_URL": "https://a.example", "NODE_ENV": "production"})
		if a != b {
			t.Errorf("unstable: %q vs %q", a, b)
		}
	})
	t.Run("changes when a value changes", func(t *testing.T) {
		other := map[string]string{"NODE_ENV": "production", "API_URL": "https://b.example", "SECRET_PREFIX": "TABULA_"}
		if configHash(base) == configHash(other) {
			t.Error("same hash for different config — this is the 409")
		}
	})
	t.Run("changes when a key is added", func(t *testing.T) {
		added := map[string]string{"NODE_ENV": "production", "API_URL": "https://a.example", "SECRET_PREFIX": "TABULA_", "AUTH_POSTMESSAGE_ORIGIN": "chrome-extension://x"}
		if configHash(base) == configHash(added) {
			t.Error("adding a key did not change the hash")
		}
	})
	t.Run("is 6 lowercase hex chars", func(t *testing.T) {
		if !regexp.MustCompile(`^[0-9a-f]{6}$`).MatchString(configHash(base)) {
			t.Errorf("not 6 hex: %q", configHash(base))
		}
	})
	// {AB: "C"} and {A: "BC"} must not hash alike — the NUL separators guarantee it.
	t.Run("key/value boundary cannot collide", func(t *testing.T) {
		if configHash(map[string]string{"AB": "C"}) == configHash(map[string]string{"A": "BC"}) {
			t.Error("boundary collision — missing separators")
		}
	})
}

// deployedEnv must reproduce what the archetype actually sets on the service:
// the app's plain env PLUS the SECRET_PREFIX serverless_space injects. Hashing
// anything less would name a revision after a config it does not actually run.
func TestDeployedEnvIncludesSecretPrefix(t *testing.T) {
	app := AppConfig{EnvVars: map[string]string{"NODE_ENV": "production"}, SecretPrefix: "TABULA_"}
	env := deployedEnv(app)
	if env["SECRET_PREFIX"] != "TABULA_" {
		t.Errorf("SECRET_PREFIX missing from deployed env: %#v", env)
	}
	if env["NODE_ENV"] != "production" {
		t.Errorf("plain env dropped: %#v", env)
	}
	// changing only the secret prefix must change the revision identity
	if configHash(env) == configHash(deployedEnv(AppConfig{EnvVars: map[string]string{"NODE_ENV": "production"}, SecretPrefix: "OTHER_"})) {
		t.Error("secret prefix not reflected in the hash")
	}
}

// Golden value: the leaf must hash tabula's DEV deployed env to the same 6 hex
// its app stack produces, so the archetype names the revision exactly as the
// live service does. If this changes, the two implementations have drifted and a
// cutover would no longer land on the existing revision name.
func TestDevConfigHashMatchesTheLiveService(t *testing.T) {
	env := map[string]string{
		"NODE_ENV":                "production",
		"GOOGLE_CLOUD_PROJECT":    "prj-d-bu2-oss-floating-c3d1",
		"SECRET_PREFIX":           "TABULA_",
		"API_URL":                 "https://tabula-api.dev.vitruviansoftware.dev/api/v1",
		"AUTH_POSTMESSAGE_ORIGIN": "chrome-extension://eblknkhkhfolhecoobmpjhfejfcmfoof",
	}
	if got := configHash(env); got != "1b062f" {
		t.Errorf("dev configHash = %q, want 1b062f (drift from tabula/infra/app)", got)
	}
}
