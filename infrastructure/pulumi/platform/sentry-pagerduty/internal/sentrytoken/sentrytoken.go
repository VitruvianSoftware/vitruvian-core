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

// Package sentrytoken resolves the Sentry API token for an explicit provider:
// SENTRY_TOKEN from the environment first, falling back to the encrypted stack
// secret `sentry:token`.
package sentrytoken

import (
	"fmt"
	"os"
	"strings"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const (
	// EnvName is the environment variable read in local and shell sessions.
	EnvName = "SENTRY_TOKEN"
	// ProviderNamespace is the Sentry provider's config namespace.
	ProviderNamespace = "sentry"
	// ConfigKey is the stack secret key inside ProviderNamespace.
	ConfigKey = "token"
)

// Resolve returns the Sentry API token wrapped as a Pulumi secret Output, or
// an error before any resource is registered if neither SENTRY_TOKEN nor
// `sentry:token` is set.
func Resolve(ctx *pulumi.Context) (pulumi.StringOutput, error) {
	if v := strings.TrimSpace(os.Getenv(EnvName)); v != "" {
		return pulumi.ToSecret(pulumi.String(v)).(pulumi.StringOutput), nil
	}
	if v := strings.TrimSpace(config.New(ctx, ProviderNamespace).Get(ConfigKey)); v != "" {
		return pulumi.ToSecret(pulumi.String(v)).(pulumi.StringOutput), nil
	}
	return pulumi.StringOutput{}, fmt.Errorf(
		"missing Sentry API token: export %s or set encrypted stack secret %s:%s",
		EnvName, ProviderNamespace, ConfigKey,
	)
}
