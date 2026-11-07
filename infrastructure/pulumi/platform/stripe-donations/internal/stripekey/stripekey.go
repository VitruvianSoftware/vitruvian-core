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

// Package stripekey resolves the Stripe API key for the provider, following
// the repo's secret pattern (principles §2.4, repo-config/internal/secrets):
// the STRIPE_API_KEY environment variable first (a pipeline secret in CI),
// then the encrypted stack secret `stripe-donations:apiKey` for local work.
//
// On top of that pattern it refuses a key for the wrong Stripe mode, so a live
// key can never drive the sandbox stack. The check runs inside an Apply, so the
// plaintext never leaves the secret Output and the error never contains it.
package stripekey

import (
	"os"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/stripe-donations/internal/donations"
)

// EnvName is the variable CI sets from its pipeline secret. It is also the
// variable Stripe's provider reads on its own; the program passes the key
// explicitly anyway so the mode check below always runs.
const EnvName = "STRIPE_API_KEY"

// ConfigKey is the stack secret used when EnvName is unset.
const ConfigKey = "apiKey"

// Resolve returns the key as a secret Output that fails the deployment when
// the key does not match mode.
func Resolve(cfg *config.Config, mode donations.Mode) pulumi.StringOutput {
	var raw pulumi.StringOutput
	if v := os.Getenv(EnvName); v != "" {
		raw = pulumi.ToSecret(pulumi.String(v)).(pulumi.StringOutput)
	} else {
		raw = cfg.RequireSecret(ConfigKey)
	}
	checked := raw.ApplyT(func(k string) (string, error) {
		if err := donations.CheckKeyMode(k, mode); err != nil {
			return "", err
		}
		return k, nil
	}).(pulumi.StringOutput)
	return pulumi.ToSecret(checked).(pulumi.StringOutput)
}
