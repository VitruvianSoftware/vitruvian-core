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

// Package secrets centralizes how every secret-bearing Pulumi stack in this
// module resolves a secret value, so no stack commits a secret to git and every
// stack marks its secrets consistently.
//
// The repo's secrets model (see docs/repo-assessment.md and the repo memory) is:
// secrets never live in git — not even Pulumi-`secure:`-encrypted. In CI the
// GitHub pipeline secrets are injected as environment variables; in local dev
// they come from the gitignored Pulumi stack config. EnvOrConfig implements
// exactly that precedence for any stack that needs it, replacing the per-stack
// copies of this logic (it began life as an unexported helper in
// pkg/copybara_sync and a duplicate `buildbuddyKey` in repo_config).
package secrets

import (
	"os"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// EnvOrConfig resolves a REQUIRED secret WITHOUT ever committing it to git. It
// prefers the named environment variable (CI, where the GitHub pipeline secret
// is injected as env) and falls back to the Pulumi stack config key (local dev,
// from the gitignored Pulumi.<stack>.yaml). The env value is wrapped with
// pulumi.ToSecret so it is encrypted in state and masked in logs, matching the
// semantics of cfg.RequireSecret on the config-fallback path.
//
// The fallback uses RequireSecret, so a stack that reaches this path with the
// config key unset fails fast rather than silently deploying without the
// secret. Use EnvOrConfigOptional when the secret is allowed to be absent.
func EnvOrConfig(cfg *config.Config, envName, cfgKey string) pulumi.StringInput {
	if v := os.Getenv(envName); v != "" {
		return asSecret(v)
	}
	return cfg.RequireSecret(cfgKey)
}

// EnvOrConfigOptional is EnvOrConfig for a secret that may legitimately be
// unset. It returns nil when NEITHER the environment variable NOR the config
// key is present, so the caller can skip managing the dependent resource and
// keep previews/applies green until the secret is wired up (the defensive
// pattern used for optional pipeline secrets like the Dependabot BuildBuddy
// key). When present, resolution and secret-marking are identical to
// EnvOrConfig.
func EnvOrConfigOptional(cfg *config.Config, envName, cfgKey string) pulumi.StringInput {
	if v := os.Getenv(envName); v != "" {
		return asSecret(v)
	}
	if cfg.Get(cfgKey) != "" {
		return cfg.RequireSecret(cfgKey)
	}
	return nil
}

// asSecret wraps a plaintext value so Pulumi encrypts it in state and masks it
// in logs.
func asSecret(v string) pulumi.StringOutput {
	return pulumi.ToSecret(pulumi.String(v)).(pulumi.StringOutput)
}
